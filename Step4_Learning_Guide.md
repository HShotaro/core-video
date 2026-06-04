# Step 4: Core Image フィルター

## 学習目標

`CIContext` と `CIFilter` を使って `CVPixelBuffer` にリアルタイムでフィルターを適用し、
CIContext のバックエンド選択とパフォーマンス特性を理解する。

---

## Core Image の処理フロー

```
CVPixelBuffer
        ↓ CIImage(cvPixelBuffer:)       // ピクセルデータを「レシピ」として包む（まだ処理しない）
CIImage
        ↓ .applyingFilter("CISepiaTone", parameters: [...])
CIImage (フィルター後のレシピ)            // チェーンできる。まだ処理しない。
        ↓ CIContext.createCGImage(ciImage, from: extent)  // ここで初めて処理実行
CGImage / CVPixelBuffer
```

**遅延評価**: `CIImage` は「どう処理するか」のレシピ。
`CIContext.render()` / `createCGImage()` が呼ばれた時点で初めて GPU 処理が走る。
複数フィルターをチェーンしても中間バッファは作られない。

---

## CIContext のバックエンド

```swift
// GPU（Metal）バックエンド — 推奨
let context = CIContext(options: [.useSoftwareRenderer: false])

// CPU ソフトウェアバックエンド — デバッグ用
let context = CIContext(options: [.useSoftwareRenderer: true])

// Metal デバイスを明示指定
let context = CIContext(mtlDevice: MTLCreateSystemDefaultDevice()!)
```

**GPU vs CPU の速度差**:
- 1280×720 BGRA フレームへのガウシアンブラー
  - CPU: ~30ms（30fps 以下）
  - GPU: ~2ms（30fps 以上で余裕あり）

---

## 代表的な CIFilter

| フィルター名 | 効果 | 主なパラメータ |
|---|---|---|
| `CIColorControls` | 明度・コントラスト・彩度 | `kCIInputSaturationKey` (0=グレースケール) |
| `CISepiaTone` | セピア調 | `kCIInputIntensityKey` (0.0〜1.0) |
| `CIGaussianBlur` | ガウシアンぼかし | `kCIInputRadiusKey` |
| `CISharpenLuminance` | シャープネス | `kCIInputSharpnessKey` |
| `CIVibrance` | 彩度の選択的強調 | `kCIInputAmountKey` |
| `CIColorInvert` | 色反転 | なし |
| `CIVignette` | 周辺減光 | `kCIInputIntensityKey`, `kCIInputRadiusKey` |
| `CICompositeOperations` | 合成 | `kCIInputBackgroundImageKey` |

---

## CIGaussianBlur のエッジ問題

ガウシアンブラーはエッジのピクセルが参照するサンプルが足りず、
`ciImage.extent` が入力より大きくなり周囲が透明になる。

```swift
// 対処法: ブラー前の extent でクロップ
let original = CIImage(cvPixelBuffer: pixelBuffer)
let blurred  = original.applyingFilter("CIGaussianBlur", parameters: [...])
let cropped  = blurred.cropped(to: original.extent)  // 元の範囲にクロップ
```

---

## CIImage → CVPixelBuffer への書き出し

```swift
// 方法1: CGImage 経由（汎用）
let cgImage = context.createCGImage(ciImage, from: ciImage.extent)

// 方法2: CVPixelBuffer に直接書き出す（ゼロコピーに近い）
var outputBuffer: CVPixelBuffer?
CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &outputBuffer)
context.render(ciImage, to: outputBuffer!)
```

方法2 のほうが中間バッファが少なく、パフォーマンスが良い。
VideoToolbox / AVAssetWriter へ渡す場合は CVPixelBuffer のまま扱うと効率的。

---

## フィルター処理時間の計測

```swift
let start = CFAbsoluteTimeGetCurrent()
let image = context.createCGImage(filtered, from: filtered.extent)
let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000  // ms
```

| フィルター | GPU 処理時間（1280×720）|
|---|---|
| パススルー | ~0.5 ms |
| グレースケール | ~1 ms |
| セピア | ~1 ms |
| ガウシアンブラー (radius 8) | ~2 ms |
| ビネット | ~2 ms |

---

## 学べること

| 概念 | 内容 |
|---|---|
| CIImage の遅延評価 | フィルターチェーンを組んでも render() まで処理しない |
| CIContext バックエンド | Metal / CPU の選択とパフォーマンス特性 |
| フィルターチェーン | 複数フィルターを applyingFilter でチェーンできる |
| CIGaussianBlur の extent | エッジ問題と cropped(to:) による対処 |
| CIContext.render | CVPixelBuffer への直接書き出しで中間バッファを削減 |

---

## core-audio との対応

| Core Audio | Core Video |
|---|---|
| `vDSP_vsmul` (ゲイン適用) | `CIColorControls(saturation: 0)` |
| `CIGaussianBlur` 相当 | IIR/Biquad LPF — 信号を「なまらせる」処理 |
| `kAUVoiceIOProperty_BypassVoiceProcessing` | `FilterType.none`（パススルー）|
| Accelerate `vDSP` の遅延実行はない | CIImage の遅延評価（render 時に処理）|
