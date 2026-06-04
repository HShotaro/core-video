# Step 2: AVCaptureSession でカメラ映像を取得

## 学習目標

`AVCaptureSession` を使ってカメラ映像を `CMSampleBuffer` → `CVPixelBuffer` として取得し、
映像データのリアルタイムフローを理解する。

---

## AVCaptureSession のフロー

```
AVCaptureDevice            // カメラハードウェア
        ↓ AVCaptureDeviceInput
AVCaptureSession           // セッション管理（beginConfiguration / commitConfiguration）
        ↓ AVCaptureVideoDataOutput
AVCaptureVideoDataOutputSampleBufferDelegate
  captureOutput(_:didOutput:from:)
        ↓ CMSampleBufferGetImageBuffer(sampleBuffer)
CVPixelBuffer              // 生ピクセルデータ
```

---

## CMSampleBuffer の構造

`CMSampleBuffer` はフレームの「コンテナ」。実際のピクセルデータとメタデータを包む。

```
CMSampleBuffer
├── CVImageBuffer (= CVPixelBuffer)  ← CMSampleBufferGetImageBuffer() で取り出す
├── CMTime (PresentationTimeStamp)   ← CMSampleBufferGetPresentationTimeStamp()
├── CMTime (Duration)                ← CMSampleBufferGetDuration()
├── CMFormatDescription              ← CMSampleBufferGetFormatDescription()
└── Attachments (SPS/PPS など)       ← CMSampleBufferGetAttachments()
```

---

## AVCaptureVideoDataOutput の設定

```swift
videoOutput.videoSettings = [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
]
// BGRA を指定することで CGContext / Metal と直接互換のバッファが届く
// デフォルトは 420v (YCbCr) — Core Image には使えるが CGContext には変換が必要

videoOutput.alwaysDiscardsLateVideoFrames = true
// 処理が遅れてもキューを詰まらせない
```

---

## デリゲートスレッドとデータ競合

デリゲートは `setSampleBufferDelegate(_:queue:)` で指定したキューで呼ばれる。

```swift
// NG: メインスレッドで直接 UI 更新
videoOutput.setSampleBufferDelegate(self, queue: .main)

// OK: 専用キューで処理し、UI 更新だけ main に dispatch
let outputQueue = DispatchQueue(label: "capture.output")
videoOutput.setSampleBufferDelegate(self, queue: outputQueue)

func captureOutput(..., didOutput sampleBuffer: ...) {
    let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
    // 重い処理はここで
    DispatchQueue.main.async { /* UI更新 */ }
}
```

---

## sessionPreset と解像度

| Preset | 解像度 | 用途 |
|---|---|---|
| `.hd1280x720` | 1280×720 | 学習・開発用 |
| `.hd1920x1080` | 1920×1080 | 高品質録画 |
| `.photo` | 最大解像度 | 静止画 |
| `.medium` | 480×360 | 低負荷処理 |

---

## CMTime とタイムスタンプ

```swift
let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
let seconds = CMTimeGetSeconds(pts)
// pts はデバイス起動からの経過時間（モノトニッククロック）

// フレームレート計算
// 30fps = 各フレームの duration = CMTime(value: 1, timescale: 30)
```

---

## 学べること

| 概念 | 内容 |
|---|---|
| AVCaptureSession | Input → Output のデータフロー管理 |
| CMSampleBuffer | AVFoundation の汎用フレームコンテナ |
| CVImageBuffer | CMSampleBuffer の中身。CVPixelBuffer の上位型 |
| alwaysDiscardsLateVideoFrames | バックプレッシャーによるフレームドロップ戦略 |
| CMTime | 映像タイムラインの精密な時刻表現 |
| スレッド管理 | デリゲートキューとメインスレッドの分離 |

---

## core-audio との対応

| Core Audio | Core Video |
|---|---|
| `kAudioUnitSubType_RemoteIO` | `AVCaptureDevice` |
| `AudioUnitSetProperty(kAudioUnitProperty_StreamFormat)` | `videoOutput.videoSettings` |
| `AURenderCallback` (プルモデル) | `AVCaptureVideoDataOutputSampleBufferDelegate` (プッシュモデル) |
| `AudioBufferList` | `CVPixelBuffer` |
| `AudioTimeStamp.mSampleTime` | `CMSampleBufferGetPresentationTimeStamp` |

> **プッシュ vs プル**: Core Audio はハードウェアがコールバックを呼ぶ「プルモデル」。
> AVCaptureSession はカメラが新フレームを「プッシュ」してくる設計。
> リアルタイム性の要求度が異なるため、スレッドポリシーも違う。
