# Step 7: リアルタイム録画

## 学習目標

`AVAssetWriter` + `AVAssetWriterInput` を使い、
カメラ映像に Metal / Core Image エフェクトを適用しながら MP4 ファイルに書き出す。
Step 1〜6 で学んだ知識（CVPixelBuffer・AVCaptureSession・CIFilter・VTCompressionSession）
が統合されたリアルタイム録画パイプラインを実装する。

---

## AVAssetWriter の録画フロー

```
AVCaptureSession → CMSampleBuffer → CVPixelBuffer
                                          ↓ CIFilter / Metal エフェクト
                                    CVPixelBuffer（加工済み）
                                          ↓ AVAssetWriterInputPixelBufferAdaptor
AVAssetWriter  ─→  AVAssetWriterInput ─→ MP4 ファイル
```

---

## AVAssetWriter の初期化

```swift
let writer = try AVAssetWriter(url: outputURL, fileType: .mp4)

// 映像設定
let videoSettings: [String: Any] = [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: 1280,
    AVVideoHeightKey: 720,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 4_000_000,     // 4Mbps
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    ]
]

let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
videoInput.expectsMediaDataInRealTime = true  // リアルタイム入力

// CVPixelBuffer を直接渡すためのアダプター
let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: videoInput,
    sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
    ]
)
writer.add(videoInput)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
```

---

## presentationTime の計算

```swift
// カメラの PTS は起動からの絶対時間。録画開始を 0 にするため差分を取る
var startTime: CMTime?

func appendFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
    if startTime == nil { startTime = timestamp }
    let presentationTime = CMTimeSubtract(timestamp, startTime!)
    adaptor.append(pixelBuffer, withPresentationTime: presentationTime)
}
```

---

## AVAssetWriterInput.isReadyForMoreMediaData

```swift
guard videoInput.isReadyForMoreMediaData else {
    // 書き込みが追いついていない → このフレームは捨てる
    return
}
adaptor.append(pixelBuffer, withPresentationTime: pts)
```

`isReadyForMoreMediaData` が `false` の間に無理にデータを押し込むと
`append` が失敗しファイルが破損する。
ドロップしても音声がないため視覚的に問題が出にくい。

---

## 録画の終了処理

```swift
videoInput.markAsFinished()  // これ以上フレームが来ないことを通知

writer.finishWriting { [weak self] in
    // ここで MP4 ファイルが確定する
    let url = self?.writer.outputURL
    // PHPhotoLibrary でカメラロールに保存
    PHPhotoLibrary.shared().performChanges {
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url!)
    }
}
```

> `finishWriting` は非同期。完了前にアプリを終了すると MP4 が壊れる。

---

## VTCompressionSession vs AVAssetWriter の違い

| | VTCompressionSession | AVAssetWriter |
|---|---|---|
| 目的 | ライブエンコード（ストリーミング等）| ファイル書き出し |
| 出力 | CMSampleBuffer（生の圧縮データ）| MP4/MOV ファイル |
| コンテナ | なし | MP4 / MOV / m4v |
| 音声サポート | なし（映像のみ）| AVAssetWriterInput を追加できる |
| 内部実装 | AVAssetWriter が内部で VTCompressionSession を使っている |

---

## エフェクト適用パイプラインのスレッド設計

```
AVCaptureSession
  ↓ (captureQueue)
CaptureEngineDelegate.captureEngine(_:didOutput:timestamp:)
  ↓ CIFilterEngine.applyToCVPixelBuffer(filter:input:)  ← メインスレッド外
  ↓ AVAssetWriterInputPixelBufferAdaptor.append(...)    ← メインスレッド外で OK
  ↓ DispatchQueue.main.async { previewImage = ... }     ← UI 更新はメインスレッド
```

---

## PHPhotoLibrary への保存

```swift
// iOS 14 以降: .addOnly 権限（カメラロールへの追加のみ）
PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
    guard status == .authorized else { return }
    PHPhotoLibrary.shared().performChanges({
        PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
    }) { success, error in
        // 完了コールバック（バックグラウンドスレッド）
    }
}
```

---

## 学べること

| 概念 | 内容 |
|---|---|
| AVAssetWriter | MP4/MOV ファイルへのリアルタイム書き出し |
| AVAssetWriterInputPixelBufferAdaptor | CVPixelBuffer を直接 AVAssetWriterInput に渡す橋渡し |
| presentationTime の相対化 | 録画開始を 0 にするための PTS 変換 |
| isReadyForMoreMediaData | バックプレッシャーによるフレームドロップ戦略 |
| finishWriting の非同期性 | ファイル確定のタイミング管理 |
| PHPhotoLibrary | 録画ファイルをカメラロールに保存する手順 |

---

## Step 1〜7 の統合図

```
Step 1: CVPixelBuffer（生ピクセルデータ）
    ↓ Lock / Unlock / FourCC
Step 2: AVCaptureSession → CMSampleBuffer → CVPixelBuffer
    ↓ CMSampleBufferGetImageBuffer()
Step 3: CVMetalTextureCache → MTLTexture → MTKView 描画
    ↓ ゼロコピー Metal レンダリング
Step 4: CIContext + CIFilter → リアルタイムフィルター
    ↓ 遅延評価 + GPU バックエンド
Step 5: カスタム Metal シェーダー（Sobel / モザイク）
    ↓ MTLRenderPipelineState + Fragment シェーダー
Step 6: VTCompressionSession → H.264 エンコード
    ↓ I/P フレーム + C コールバック
Step 7: AVAssetWriter + CIFilter → MP4 録画
         ↓
    カメラロール保存
```
