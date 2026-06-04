import CoreVideo
import CoreGraphics
import UIKit

struct PixelBufferInfo {
    let width: Int
    let height: Int
    let pixelFormatType: String
    let bytesPerRow: Int
    let dataSize: Int
    let planeCount: Int
    let pointer: String
}

struct PixelSample {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8
}

enum PixelBufferInspector {

    // MARK: - CVPixelBuffer 作成

    static func createRGBA(width: Int, height: Int) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true,
        ]
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width, height,
            kCVPixelFormatType_32BGRA,
            attrs as CFDictionary,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess else { return nil }
        return pixelBuffer
    }

    // MARK: - プロパティ取得

    static func info(from pixelBuffer: CVPixelBuffer) -> PixelBufferInfo {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let dataSize = CVPixelBufferGetDataSize(pixelBuffer)
        let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)

        return PixelBufferInfo(
            width: width,
            height: height,
            pixelFormatType: fourCCString(format),
            bytesPerRow: bytesPerRow,
            dataSize: dataSize,
            planeCount: planeCount,
            pointer: String(format: "%p", unsafeBitCast(pixelBuffer, to: Int.self))
        )
    }

    // MARK: - ピクセルデータの読み書き

    static func fillGradient(_ pixelBuffer: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }

        for y in 0..<height {
            let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let b = UInt8(x * 255 / max(width - 1, 1))
                let g = UInt8(y * 255 / max(height - 1, 1))
                row[x * 4 + 0] = b
                row[x * 4 + 1] = g
                row[x * 4 + 2] = 0
                row[x * 4 + 3] = 255
            }
        }
    }

    static func samplePixel(at point: CGPoint, in pixelBuffer: CVPixelBuffer) -> PixelSample? {
        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let x = Int(point.x)
        let y = Int(point.y)
        guard x >= 0, y >= 0, x < width, y < height else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let pixel = base.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)

        return PixelSample(r: pixel[2], g: pixel[1], b: pixel[0], a: pixel[3])
    }

    // MARK: - CGImage 変換

    static func toCGImage(_ pixelBuffer: CVPixelBuffer) -> CGImage? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        guard let ctx = CGContext(
            data: base,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        return ctx.makeImage()
    }

    static func fromCGImage(_ cgImage: CGImage) -> CVPixelBuffer? {
        let width = cgImage.width
        let height = cgImage.height
        guard let pixelBuffer = createRGBA(width: width, height: height) else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        guard let ctx = CGContext(
            data: base,
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }

    // MARK: - ユーティリティ

    private static func fourCCString(_ format: OSType) -> String {
        let chars: [Character] = [
            Character(UnicodeScalar((format >> 24) & 0xFF)!),
            Character(UnicodeScalar((format >> 16) & 0xFF)!),
            Character(UnicodeScalar((format >> 8) & 0xFF)!),
            Character(UnicodeScalar(format & 0xFF)!),
        ]
        return String(chars)
    }
}
