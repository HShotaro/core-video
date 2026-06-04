# Step 1: CVPixelBuffer の基礎

## 学習目標

Core Video の中心データ型 `CVPixelBuffer` を直接操作し、
「AVFoundation / Core Image が内部でやっていること」をゼロから理解する。

---

## Core Video の基本フロー

```
CVPixelBufferCreate(...)           // バッファ確保（ピクセルメモリをアロケート）
        ↓
CVPixelBufferLockBaseAddress(...)  // CPU アクセス開始（GPU ↔ CPU 同期）
        ↓
CVPixelBufferGetBaseAddress(...)   // 生ポインタ取得
        ↓
... ピクセルデータの読み書き ...
        ↓
CVPixelBufferUnlockBaseAddress(...)// CPU アクセス終了
```

---

## PixelFormat — 映像の「ビット配置」

`CVPixelBufferCreate` で指定する `pixelFormatType` は FourCC コードで映像のビット配置を示す。

| FourCC | 意味 | 用途 |
|---|---|---|
| `BGRA` (`kCVPixelFormatType_32BGRA`) | Blue-Green-Red-Alpha 各 8bit | iOS カメラ出力・CGContext 互換 |
| `420v` (`kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange`) | YCbCr 4:2:0 BT.709 Video Range | カメラ映像（効率的）|
| `420f` (`kCVPixelFormatType_420YpCbCr8BiPlanarFullRange`) | YCbCr 4:2:0 Full Range | カメラ映像（高精度）|
| `x420` (`kCVPixelFormatType_Lossy_420YpCbCr8BiPlanarVideoRange`) | 圧縮 YCbCr | A16 以降の効率化フォーマット |

**YCbCr と BGRA の違い**:  
- YCbCr: 輝度 (Y) と色差 (Cb/Cr) を分離。人間の目は輝度変化に敏感なため効率的に圧縮できる。  
- BGRA: CGContext・Metal テクスチャと直接互換。変換不要で扱いやすい。

---

## CVPixelBuffer の主要 API

```swift
// 作成
CVPixelBufferCreate(allocator, width, height, pixelFormatType, attrs, &pixelBuffer)

// プロパティ取得
CVPixelBufferGetWidth(pixelBuffer)
CVPixelBufferGetHeight(pixelBuffer)
CVPixelBufferGetPixelFormatType(pixelBuffer)  // FourCC
CVPixelBufferGetBytesPerRow(pixelBuffer)       // パディング込みの行バイト数
CVPixelBufferGetDataSize(pixelBuffer)          // 総バイト数
CVPixelBufferGetPlaneCount(pixelBuffer)        // YCbCr は 2 プレーン、BGRAは 0（シングル）

// ロック・アンロック（必ずペアで使う）
CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

// アドレス取得
CVPixelBufferGetBaseAddress(pixelBuffer)            // シングルプレーン
CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0)  // Y プレーン（YCbCr の場合）
CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1)  // CbCr プレーン
```

---

## bytesPerRow とアライメント

`bytesPerRow` は必ずしも `width × bpp` と一致しない。
GPU の要求するアライメント（64 byte / 256 byte 境界など）に合わせてパディングされる。

```
width = 100px, BGRA (4 bytes/px)
最低必要バイト数 = 400 bytes
実際の bytesPerRow = 512 bytes（次の 64 byte アライメント境界）

→ ピクセルデータは行ごとに読む必要がある
   row[n] = base + n * bytesPerRow  （base + n * width * 4 ではない）
```

---

## CGContext 初期化パラメータ詳解

`CGContext` の初期化は BGRA フォーマットとの対応を正確に伝える必要がある。

```swift
CGContext(
    data: base,
    width: width, height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
             | CGBitmapInfo.byteOrder32Little.rawValue
)
```

### `data: base`

`CVPixelBuffer` の生メモリポインタをそのまま渡す。CGContext は新しいメモリを確保しない。
`data: nil` にすると CGContext が自前でメモリを確保するが、その場合 CVPixelBuffer に書き戻せない。

### `bitsPerComponent: 8`

1チャンネル（B・G・R・A それぞれ）あたりのビット数。`UInt8`（0〜255）に対応する。

```
8 bits/component × 4 components (B,G,R,A) = 32 bits = 4 bytes/pixel
```

`kCVPixelFormatType_32BGRA` の `32` がこれに対応している。ピクセル書き込みコードの `UInt8` 型がそのまま 1チャンネル分。

### `bytesPerRow`

`width * 4` ではなく `CVPixelBufferGetBytesPerRow()` の値を使う。

```
bytesPerRow = width * 4 + padding

// 例: width = 100px
width * 4   = 400 bytes（最低限）
bytesPerRow = 448 bytes（次の 64byte 境界 = 7 × 64）
padding     = 48 bytes

// 例: width = 256px
width * 4   = 1024 bytes
bytesPerRow = 1024 bytes（アライメントと一致）
padding     = 0 bytes
```

`width * 4` を渡すと CGContext と CVPixelBuffer のメモリ解釈がズレ、描画が斜めにズレる。

### `bitmapInfo` — BGRA になる組み合わせ

2つのフラグの OR。

**`CGImageAlphaInfo.premultipliedFirst`**

- `First` = アルファはメモリ先頭（index 0）
- `premultiplied` = RGB 値がアルファ乗算済み（CGContext の内部形式）

論理的なチャンネル順: `[A][R][G][B]`

**`CGBitmapInfo.byteOrder32Little`**

CPU のリトルエンディアンで 32bit を読む指定。

```
物理メモリ: [0xBB][0xGG][0xRR][0xAA]  ← BGRA の並び
32bit リトルエンディアンで読む → 0xAARRGGBB（論理的に ARGB）
```

**2つを組み合わせると**

`premultipliedFirst`（論理 ARGB）+ `byteOrder32Little`（バイト逆順）= 物理メモリが BGRA になる。

| パラメータ | 値 | 意味 |
|---|---|---|
| `bitsPerComponent` | `8` | 各チャンネル UInt8（0〜255）|
| `bytesPerRow` | `CVPixelBufferGetBytesPerRow()` | パディング込みの行幅 |
| `space` | `DeviceRGB` | デバイス依存 RGB（変換コストなし）|
| `bitmapInfo` | `premultipliedFirst \| byteOrder32Little` | 物理メモリが BGRA になる組み合わせ |

1つでもズレると色チャンネルが入れ替わるか画像が壊れる。

---

## CGImage との変換

```
CVPixelBuffer ─→ CGContext.makeImage() ─→ CGImage ─→ UIImage
CVPixelBuffer ←─ CGContext.draw()      ←─ CGImage ←─ UIImage
```

```swift
// CVPixelBuffer → CGImage
CVPixelBufferLockBaseAddress(buf, .readOnly)
let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), ...)
let cgImage = ctx.makeImage()
CVPixelBufferUnlockBaseAddress(buf, .readOnly)

// CGImage → CVPixelBuffer
CVPixelBufferCreate(...)
CVPixelBufferLockBaseAddress(buf, [])
let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), ...)
ctx.draw(cgImage, in: CGRect(origin: .zero, size: CGSize(width, height)))
CVPixelBufferUnlockBaseAddress(buf, [])
```

---

## CMSampleBuffer との関係

AVCaptureSession や VideoToolbox のデコーダが返すのは `CMSampleBuffer`。
そこから CVPixelBuffer を取り出す API:

```swift
// AVFoundation（カメラ出力）
let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)  // CVImageBuffer = CVPixelBuffer

// CMSampleBufferGetImageBuffer は CVImageBuffer? を返す
// CVImageBuffer は CVPixelBuffer の上位型（実質同じ）
```

---

## 学べること

| 概念 | 内容 |
|---|---|
| CVPixelBuffer | Core Video の中心的なメモリ型。GPU・CPU 間の共有バッファ |
| PixelFormatType | FourCC によるビット配置の識別 |
| Lock / Unlock | GPU と CPU の排他アクセス制御 |
| bytesPerRow | アライメントパディングを考慮した行アドレス計算 |
| CGImage 変換 | CGContext を介した相互変換 |
| CMSampleBuffer | AVFoundation の出力コンテナ。中身は CVImageBuffer = CVPixelBuffer |

---

## core-audio との対応

| Core Audio | Core Video |
|---|---|
| `AudioComponentFindNext` / `AudioComponentInstanceNew` | `CVPixelBufferCreate` |
| `AudioUnitGetProperty` (sampleRate など) | `CVPixelBufferGetWidth/Height/PixelFormatType` |
| `AudioUnitInitialize` / `AudioUnitUninitialize` | `CVPixelBufferLockBaseAddress` / `UnlockBaseAddress` |
| `AudioBufferList` へのサンプル書き込み | baseAddress ポインタへのピクセル書き込み |
| ASBD (AudioStreamBasicDescription) | CVPixelBufferInfo (FourCC + bytesPerRow + planeCount) |
