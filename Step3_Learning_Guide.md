# Step 3: Metal でリアルタイム描画

## 学習目標

`CVMetalTextureCache` を使って `CVPixelBuffer` を **ゼロコピー** で Metal テクスチャに変換し、
`MTKView` にカメラ映像をリアルタイムで表示する。

---

## CVMetalTextureCache — ゼロコピーの仕組み

```
CVPixelBuffer (GPU/CPU 共有メモリ)
        ↓ CVMetalTextureCacheCreateTextureFromImage()
CVMetalTexture (Metal テクスチャのラッパー)
        ↓ CVMetalTextureGetTexture()
MTLTexture (Metal が直接サンプリングできる形)
```

**ゼロコピーとは**: `CVPixelBuffer` のメモリを **そのまま** Metal テクスチャとして使う。
`UIImage` 経由の場合は CPU ↔ GPU 間のメモリコピーが発生するが、
`CVMetalTextureCache` を使えばそのコストがない。

```
UIImage 経由（コピーあり）:
  CVPixelBuffer → CPU メモリ読み取り → UIImage → GPU アップロード → MTLTexture
  コスト: 1フレーム (1280×720 BGRA) = 3.7MB コピー × 30fps = 111MB/s

CVMetalTextureCache 経由（ゼロコピー）:
  CVPixelBuffer ─────────────────────────────→ MTLTexture（同一メモリ）
  コスト: ほぼゼロ
```

---

## MTKView の描画フロー

```
MTKView.preferredFramesPerSecond (デフォルト 60fps)
        ↓ CADisplayLink が毎フレーム呼び出す
MTKViewDelegate.draw(in:)
        ↓
MTLCommandBuffer 作成
        ↓
MTLRenderCommandEncoder 作成（RenderPassDescriptor 経由）
        ↓
setFragmentTexture(texture, index: 0)   // CVMetalTexture → MTLTexture をセット
        ↓
drawPrimitives(.triangleStrip, count: 4) // 画面全体を覆う 2 枚の三角形 (4 頂点)
        ↓
endEncoding → present(drawable) → commit
```

---

## フルスクリーン描画の頂点構成

```metal
// 画面全体を覆う TriangleStrip (4 頂点)
// NDC 座標 (x, y) と UV 座標 (u, v)

float2 pos[4] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };
//               左下      右下    左上    右上
float2 uv[4]  = { {0,1},   {1,1},  {0,0},  {1,0} };
//               左下      右下    左上    右上（V 軸が Metal では上から下）
```

iOS の Metal は Y 軸が上向き（NDC）、テクスチャ UV は Y が上から下。
そのため UV の V を反転する必要がある。

---

## Metal シェーダーの最小構成

```metal
#include <metal_stdlib>
using namespace metal;

struct VertexOut {
    float4 pos [[position]];
    float2 uv;
};

vertex VertexOut vert(uint vid [[vertex_id]]) {
    // 頂点バッファなし。vid (0〜3) から直接座標を計算
    float2 positions[4] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };
    float2 uvs[4]       = { {0,1},   {1,1},  {0,0},  {1,0} };
    VertexOut out;
    out.pos = float4(positions[vid], 0, 1);
    out.uv  = uvs[vid];
    return out;
}

fragment float4 frag(VertexOut in [[stage_in]],
                     texture2d<float> tex [[texture(0)]]) {
    constexpr sampler s(filter::linear);
    return tex.sample(s, in.uv);
}
```

---

## CVMetalTextureCacheのライフサイクル管理

```swift
// 1. キャッシュ作成（アプリ起動時）
CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)

// 2. フレームごとにテクスチャ生成（CVMetalTexture は参照カウント管理）
CVMetalTextureCacheCreateTextureFromImage(
    kCFAllocatorDefault,
    cache,
    pixelBuffer,
    nil,           // テクスチャ属性（nil = デフォルト）
    .bgra8Unorm,   // テクスチャフォーマット
    width, height,
    0,             // プレーンインデックス（BGRA は 0）
    &cvTexture
)

// 3. ローカル変数 cvTexture が解放されるとキャッシュにテクスチャが戻る
// → 必要以上に保持しないこと（メモリリークの原因）
```

---

## 学べること

| 概念 | 内容 |
|---|---|
| CVMetalTextureCache | CVPixelBuffer → MTLTexture のゼロコピー変換 |
| MTKView | CADisplayLink と同期した Metal 描画ビュー |
| MTLCommandBuffer | GPU へのコマンド記録と送信 |
| MTLRenderCommandEncoder | レンダリングパイプラインの設定と描画命令 |
| TriangleStrip | フルスクリーン描画の標準的な頂点構成 |
| NDC / UV 座標 | Metal の座標系とテクスチャ UV の関係 |

---

## core-audio との対応

| Core Audio | Core Video (Metal) |
|---|---|
| `AURenderCallback` (ハードウェアがプル) | `MTKViewDelegate.draw(in:)` (DisplayLink がプル) |
| `AudioBufferList` へのサンプル書き込み | `MTLRenderCommandEncoder` への描画コマンド |
| `AudioOutputUnitStart` | `MTKView.isPaused = false` |
| `AudioUnitReset` (バッファクリア) | `CVMetalTextureCacheFlush` |
| SPSC Queue でリアルタイムスレッドに安全渡し | `NSLock` で描画スレッドに安全にテクスチャを渡す |
