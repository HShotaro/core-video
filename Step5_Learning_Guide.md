# Step 5: カスタム Metal シェーダー

## 学習目標

Metal のフラグメントシェーダーを自作し、Core Image では実現しにくい
ピクセル単位の映像処理（エッジ検出・モザイクなど）を実装する。
`MTLRenderPipelineState` の構造と `CVMetalTextureCache` との組み合わせを理解する。

---

## Metal レンダリングパイプライン

```
Vertex シェーダー
  → 頂点座標 (NDC) + UV 座標を出力
        ↓ ラスタライズ（補間）
Fragment シェーダー
  → ピクセルごとにテクスチャをサンプリング → 出力色を決定
        ↓
フレームバッファ (MTLDrawable)
```

---

## シェーダーの種類と役割

```metal
// Vertex シェーダー: 各頂点に対して1回呼ばれる
vertex VertexOut vert(uint vid [[vertex_id]]) {
    // vid: 0, 1, 2, 3 の頂点インデックス
    // 頂点バッファ不要でインラインで座標を定義できる
}

// Fragment シェーダー: 各ピクセルに対して1回呼ばれる
fragment float4 frag(VertexOut in [[stage_in]],
                     texture2d<float> tex [[texture(0)]]) {
    // [[stage_in]]: vertex シェーダーの出力（補間済み UV 等）
    // [[texture(0)]]: setFragmentTexture(_, index: 0) で渡したテクスチャ
    constexpr sampler s(filter::linear);  // バイリニア補間
    return tex.sample(s, in.uv);          // UV 座標でサンプリング
}
```

---

## グレースケール変換の原理

```metal
float4 color = tex.sample(s, uv);
// 人間の視覚感度（輝度の重み付き平均）
float luma = dot(color.rgb, float3(0.299, 0.587, 0.114));
//           R: 29.9%    G: 58.7%    B: 11.4%
return float4(luma, luma, luma, color.a);
```

**BT.601 vs BT.709の違い**:
- BT.601: SDTV 用。重み (0.299, 0.587, 0.114)
- BT.709: HDTV 用。重み (0.2126, 0.7152, 0.0722)
- iOS カメラの YCbCr は BT.709 ベース

---

## Sobel エッジ検出の原理

```
隣接 3×3 ピクセルの輝度を使って勾配を計算する

Gx カーネル（水平方向の勾配）:
  -1  0  +1
  -2  0  +2
  -1  0  +1

Gy カーネル（垂直方向の勾配）:
  -1 -2 -1
   0  0  0
  +1 +2 +1

edge = sqrt(Gx² + Gy²)
```

```metal
float2 d = float2(1.0 / tex.get_width(), 1.0 / tex.get_height());

float gx = -lum(uv + float2(-d.x, -d.y)) - 2*lum(uv + float2(-d.x, 0)) ...;
float gy = -lum(uv + float2(-d.x, -d.y)) - 2*lum(uv + float2(0, -d.y)) ...;
float edge = clamp(sqrt(gx*gx + gy*gy), 0.0, 1.0);
```

---

## モザイク（ピクセレート）の原理

```metal
float blockSize = 20.0;  // ブロックサイズ（ピクセル単位）
uint2 sz = uint2(tex.get_width(), tex.get_height());

// UV 座標をブロック単位に丸める
float2 block = floor(in.uv * float2(sz) / blockSize) * blockSize / float2(sz);
constexpr sampler s(filter::nearest);  // nearest: 補間なし（シャープなブロック）
return tex.sample(s, block);
```

---

## MTLRenderPipelineState の構築

```swift
let desc = MTLRenderPipelineDescriptor()
desc.vertexFunction   = library.makeFunction(name: "vert")
desc.fragmentFunction = library.makeFunction(name: "frag")
desc.colorAttachments[0].pixelFormat = .bgra8Unorm  // MTKView と一致させる

let pipeline = try device.makeRenderPipelineState(descriptor: desc)
// pipeline はスレッドセーフ・再利用可能
```

---

## 複数シェーダーの切り替え

```swift
// パイプラインをエフェクトごとに事前構築（起動時）
var pipelines: [ShaderEffect: MTLRenderPipelineState] = [:]

// 描画時に切り替え
encoder.setRenderPipelineState(pipelines[currentEffect]!)
encoder.setFragmentTexture(texture, index: 0)
encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
```

`MTLRenderPipelineState` の構築は重い処理なので、
アプリ起動時または非描画タイミングで事前に行う。

---

## Core Image vs カスタム Metal シェーダー

| | Core Image | カスタム Metal |
|---|---|---|
| 実装コスト | 低い（フィルター名を指定するだけ）| 高い（GLSL 同等の Metal コード）|
| 柔軟性 | CIFilter の種類に限定 | 任意のアルゴリズムを実装可能 |
| パフォーマンス | 最適化済みだが制御不可 | 自分でチューニング可能 |
| Sobel, モザイク | カスタム CIKernel が必要 | フラグメントシェーダーで直接実装 |

---

## 学べること

| 概念 | 内容 |
|---|---|
| Vertex / Fragment シェーダー | GPU 上で並列実行される映像処理の最小単位 |
| sampler（filter::linear / nearest） | テクスチャ補間方式の違いと用途 |
| グレースケール輝度変換 | BT.601 重み付き平均の原理 |
| Sobel エッジ検出 | 3×3 近傍演算による輝度勾配の計算 |
| MTLRenderPipelineState | シェーダーとフォーマットのコンパイル済みパイプライン |
| 複数パイプラインの管理 | エフェクト切り替えの設計パターン |
