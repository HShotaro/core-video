# Core Video 学習プロジェクト

iOS の Core Video / VideoToolbox を C API レベルから理解するための学習プロジェクト。
`core-audio` プロジェクトで学んだ AVFoundation の内側（CVPixelBuffer・CMSampleBuffer）を
映像処理の観点から掘り下げる。

---

## iOS との対応（core-audio プロジェクトとの比較）

| Core Audio | Core Video |
|---|---|
| `AudioComponentDescription` | `CVPixelBufferInfo` (FourCC / format type) |
| `AudioComponentInstanceNew` | `CVPixelBufferCreate` |
| `AudioUnitInitialize` / `Dispose` | `CVPixelBufferLockBaseAddress` / `Unlock` |
| `AudioBufferList` | `CVPixelBuffer` (baseAddress) |
| `AURenderCallback` (プルモデル) | `AVCaptureVideoDataOutputSampleBufferDelegate` (プッシュ) |
| `VPIO (kAUVoiceIOProperty_*)` | `VTCompressionSession` (エンコードプロパティ) |
| `vDSP` (信号処理) | Metal シェーダー / Core Image (映像処理) |
| SPSC Ring Buffer | `NSLock` + テクスチャ更新 (GPU スレッド境界) |

---

## 学習ステップ

### Step 1: CVPixelBuffer の基礎
**詳細**: [Step1_Learning_Guide.md](Step1_Learning_Guide.md)

`CVPixelBuffer` を直接操作し、Core Video の最小単位を理解する。

| 学習内容 | 概要 |
|---|---|
| CVPixelBufferCreate | バッファ確保とピクセルフォーマット (FourCC) の指定 |
| Lock / Unlock | CPU アクセスのための排他制御 |
| bytesPerRow | GPU アライメントパディングを考慮した行アドレス計算 |
| CGImage 変換 | CGContext を介した相互変換 |
| CMSampleBuffer との関係 | `CMSampleBufferGetImageBuffer` で CVPixelBuffer を取り出す |

---

### Step 2: AVCaptureSession でカメラ映像を取得
**詳細**: [Step2_Learning_Guide.md](Step2_Learning_Guide.md)

カメラから `CMSampleBuffer` を受け取り `CVPixelBuffer` を取り出す。

| 学習内容 | 概要 |
|---|---|
| AVCaptureSession | Input → Output のデータフロー管理 |
| CMSampleBuffer の構造 | PTS・CVImageBuffer・FormatDescription の関係 |
| videoSettings | kCVPixelFormatType_32BGRA vs YCbCr の使い分け |
| alwaysDiscardsLateVideoFrames | バックプレッシャーによるフレームドロップ |
| スレッド管理 | デリゲートキューとメインスレッドの分離 |

---

### Step 3: Metal でリアルタイム描画
**詳細**: [Step3_Learning_Guide.md](Step3_Learning_Guide.md)

`CVMetalTextureCache` でゼロコピーテクスチャ変換し `MTKView` に描画する。

| 学習内容 | 概要 |
|---|---|
| CVMetalTextureCache | CVPixelBuffer → MTLTexture のゼロコピー変換 |
| MTKView | CADisplayLink と同期した Metal 描画ビュー |
| TriangleStrip | フルスクリーン描画の標準的な頂点構成 |
| NDC / UV 座標 | Metal 座標系とテクスチャ UV の関係・Y 軸反転 |
| MTLCommandBuffer | GPU へのコマンド記録と送信のフロー |

---

### Step 4: Core Image フィルター
**詳細**: [Step4_Learning_Guide.md](Step4_Learning_Guide.md)

`CIContext` と `CIFilter` をリアルタイムに適用し、遅延評価の仕組みを理解する。

| 学習内容 | 概要 |
|---|---|
| CIImage の遅延評価 | render() まで処理しないレシピチェーン |
| CIContext バックエンド | Metal / CPU の選択とパフォーマンス比較 |
| 代表的な CIFilter | グレースケール・セピア・ブラー・ビネットなど |
| CIGaussianBlur の extent | エッジ問題と cropped(to:) による対処 |
| CVPixelBuffer への直接書き出し | `CIContext.render(_:to:)` で中間バッファを削減 |

---

### Step 5: カスタム Metal シェーダー
**詳細**: [Step5_Learning_Guide.md](Step5_Learning_Guide.md)

Metal フラグメントシェーダーを自作し、エッジ検出・モザイクを実装する。

| 学習内容 | 概要 |
|---|---|
| Vertex / Fragment シェーダー | GPU 並列処理の基本構造 |
| グレースケール変換 | BT.601 輝度重み付き平均の原理 |
| Sobel エッジ検出 | 3×3 近傍演算による輝度勾配 |
| モザイク（ピクセレート）| UV 座標のブロック丸め + nearest サンプラー |
| MTLRenderPipelineState | シェーダーのコンパイル済みパイプライン |

**シェーダー比較**

| シェーダー | アルゴリズム | 負荷 |
|---|---|---|
| パススルー | そのままサンプリング | 最低 |
| グレースケール | dot(rgb, weights) | 低 |
| セピア | 3×3 行列変換 | 低 |
| Sobel | 3×3 近傍演算 × 2 | 中 |
| モザイク | UV 丸め + nearest | 低 |

---

### Step 6: VideoToolbox でハードウェアエンコード
**詳細**: [Step6_Learning_Guide.md](Step6_Learning_Guide.md)

`VTCompressionSession` で CVPixelBuffer を H.264 にリアルタイムエンコードする。

| 学習内容 | 概要 |
|---|---|
| VTCompressionSession | ハードウェアエンコーダの C API |
| I / P / B フレーム | フレーム間予測と圧縮効率の関係 |
| C コールバック + Unmanaged | Swift オブジェクトを C API に安全に渡す方法 |
| kCMSampleAttachmentKey_NotSync | キーフレームの判定方法 |
| H.264 vs HEVC | 圧縮効率・互換性・レイテンシの比較 |

---

### Step 7: リアルタイム録画
**詳細**: [Step7_Learning_Guide.md](Step7_Learning_Guide.md)

カメラ映像にエフェクトを適用しながら MP4 ファイルに書き出す。
Step 1〜6 の知識が統合される最終ステップ。

| 学習内容 | 概要 |
|---|---|
| AVAssetWriter | MP4/MOV ファイルへのリアルタイム書き出し |
| AVAssetWriterInputPixelBufferAdaptor | CVPixelBuffer を直接 WriterInput に渡す橋渡し |
| presentationTime の相対化 | 録画開始を 0 にするための PTS 変換 |
| isReadyForMoreMediaData | バックプレッシャーによるフレームドロップ |
| finishWriting | 非同期ファイル確定のタイミング管理 |
| PHPhotoLibrary | カメラロールへの動画保存 |

---

## プロジェクト構成

```
core-video/
├── CoreVideoStudy/
│   └── CoreVideoStudy/
│       ├── Step1/
│       │   ├── PixelBufferInspector.swift  # CVPixelBuffer C API操作
│       │   ├── Step1ViewModel.swift
│       │   └── Step1View.swift
│       ├── Step2/
│       │   ├── CaptureEngine.swift         # AVCaptureSession + CVPixelBuffer取り出し
│       │   ├── Step2ViewModel.swift
│       │   └── Step2View.swift
│       ├── Step3/
│       │   ├── MetalRenderer.swift         # CVMetalTextureCache + MTKView
│       │   ├── Step3ViewModel.swift
│       │   └── Step3View.swift
│       ├── Step4/
│       │   ├── CIFilterEngine.swift        # CIContext + CIFilter
│       │   ├── Step4ViewModel.swift
│       │   └── Step4View.swift
│       ├── Step5/
│       │   ├── CustomShaderRenderer.swift  # カスタム Metal シェーダー
│       │   ├── Step5ViewModel.swift
│       │   └── Step5View.swift
│       ├── Step6/
│       │   ├── VideoEncoder.swift          # VTCompressionSession
│       │   ├── Step6ViewModel.swift
│       │   └── Step6View.swift
│       └── Step7/
│           ├── VideoRecorder.swift         # AVAssetWriter + エフェクト
│           ├── Step7ViewModel.swift
│           └── Step7View.swift
├── Step1_Learning_Guide.md
├── Step2_Learning_Guide.md
├── Step3_Learning_Guide.md
├── Step4_Learning_Guide.md
├── Step5_Learning_Guide.md
├── Step6_Learning_Guide.md
├── Step7_Learning_Guide.md
└── README.md
```

## 動作環境

- iOS 17.0+
- Xcode 16+（PBXFileSystemSynchronizedRootGroup 使用）
- Step 2〜7 はカメラ権限が必要。**実機推奨**
- Step 5 の Metal シェーダーは A9+ チップ以降推奨
- Step 6 の HEVC エンコードは A9+ チップ以降
