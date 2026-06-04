# Step 6: VideoToolbox でハードウェアエンコード

## 学習目標

`VTCompressionSession` を使って `CVPixelBuffer` を H.264/HEVC に
**ハードウェアエンコード**し、エンコードパイプラインとフレーム構造を理解する。

---

## VideoToolbox のエンコードフロー

```
CVPixelBuffer（生映像）
        ↓ VTCompressionSessionEncodeFrame()
VTCompressionSession（ハードウェアエンコーダ）
        ↓ 非同期コールバック VTCompressionOutputCallback
CMSampleBuffer（エンコード済みフレーム）
  ├── CMBlockBuffer（圧縮データ: NAL ユニット）
  ├── CMTime (PTS/DTS)
  └── Attachments (キーフレームフラグ etc.)
```

---

## VTCompressionSession の作成

```swift
VTCompressionSessionCreate(
    allocator:               kCFAllocatorDefault,
    width:                   Int32(width),
    height:                  Int32(height),
    codecType:               kCMVideoCodecType_H264,   // or kCMVideoCodecType_HEVC
    encoderSpecification:    nil,    // ハードウェアエンコーダを OS が自動選択
    imageBufferAttributes:   nil,    // 入力PixelBufferの制約（nil = 自動）
    compressedDataAllocator: nil,
    outputCallback:          outputCallback,
    refcon:                  Unmanaged.passUnretained(self).toOpaque(),
    compressionSessionOut:   &session
)
```

---

## 主要なエンコードプロパティ

```swift
// リアルタイムエンコード（低レイテンシ優先）
VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime,
                     value: kCFBooleanTrue)

// プロファイル / レベル
VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                     value: kVTProfileLevel_H264_High_AutoLevel)
// kVTProfileLevel_HEVC_Main_AutoLevel  (HEVC の場合)

// ビットレート (bps)
VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                     value: 2_000_000 as CFNumber)  // 2Mbps

// キーフレーム間隔（フレーム数）
VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                     value: 30 as CFNumber)  // 30フレームに1回 I フレーム

// B フレーム無効（低レイテンシ録画用）
VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AllowFrameReordering,
                     value: kCFBooleanFalse)
```

---

## フレームの種類（H.264）

| フレームタイプ | 内容 | サイズ |
|---|---|---|
| I フレーム（キーフレーム）| 完全な画像データ | 大（~50KB）|
| P フレーム | 直前の I/P フレームとの差分 | 小（~5KB）|
| B フレーム | 前後のフレームを参照する双方向差分 | 最小 |

`MaxKeyFrameInterval = 30` → 1秒に1回（30fps 想定）I フレームが入る

---

## C コールバックと Unmanaged

VideoToolbox の出力コールバックは C 関数ポインタ形式。
Swift オブジェクトを渡すには `Unmanaged` を使う。

```swift
// 渡す側
refcon: Unmanaged.passUnretained(self).toOpaque()
// → self の参照を保持せずに void* に変換

// コールバック内で受け取る
let encoder = Unmanaged<VideoEncoder>.fromOpaque(refcon!).takeUnretainedValue()
// → void* を VideoEncoder に戻す（参照カウント変更なし）
```

> **注意**: `passUnretained` は self が生きている間のみ安全。
> コールバックが呼ばれる前に self が解放されないよう管理する。

---

## キーフレームの判定

```swift
// CMSampleBuffer の Attachment を確認する
let attachments = CMSampleBufferGetAttachments(sampleBuffer, createIfNecessary: false)
let isNotSync = (attachments as? [String: Any])?[kCMSampleAttachmentKey_NotSync as String]
let isKeyFrame = (isNotSync == nil)
// kCMSampleAttachmentKey_NotSync がないフレーム = キーフレーム
```

---

## H.264 vs HEVC の選択

| | H.264 | HEVC (H.265) |
|---|---|---|
| 圧縮効率 | 標準 | H.264 の約2倍効率 |
| 互換性 | 高い | iOS 11+ / A9+ チップ以降 |
| ハードウェアエンコード | 全 iOS デバイス | A9+ 以降 |
| リアルタイム低レイテンシ | 良好 | やや高レイテンシ |
| codecType | `kCMVideoCodecType_H264` | `kCMVideoCodecType_HEVC` |

---

## 学べること

| 概念 | 内容 |
|---|---|
| VTCompressionSession | ハードウェアビデオエンコーダの C API |
| I/P/B フレーム | 映像圧縮におけるフレーム間予測 |
| C コールバックと Unmanaged | Swift オブジェクトを C API に安全に渡す方法 |
| kCMSampleAttachmentKey_NotSync | キーフレーム判定の方法 |
| RealTime vs 品質優先 | エンコードモードの使い分け |

---

## core-audio との対応

| Core Audio | Core Video |
|---|---|
| `VoiceProcessingIO (VPIO)` | `VTCompressionSession` |
| `kAURenderCallbackStruct` (C コールバック) | `VTCompressionOutputCallback` (C コールバック) |
| `kAUVoiceIOProperty_BypassVoiceProcessing` | `kVTCompressionPropertyKey_RealTime` |
| `AudioUnitUninitialize` + `Dispose` | `VTCompressionSessionInvalidate` |
| `inRefCon` + `Unmanaged` | `refcon` + `Unmanaged` |
