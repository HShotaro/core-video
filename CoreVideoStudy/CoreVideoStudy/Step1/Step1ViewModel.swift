import SwiftUI
import CoreVideo

@Observable
final class Step1ViewModel {
    var pixelBufferInfo: PixelBufferInfo?
    var sampledPixel: PixelSample?
    var previewImage: UIImage?
    var log: [String] = []

    private var pixelBuffer: CVPixelBuffer?

    func createAndFill() {
        let buf = PixelBufferInspector.createRGBA(width: 256, height: 256)
        pixelBuffer = buf
        guard let buf else {
            addLog("CVPixelBufferCreate 失敗")
            return
        }
        addLog("CVPixelBufferCreate 成功")

        PixelBufferInspector.fillGradient(buf)
        addLog("グラデーション書き込み完了")

        pixelBufferInfo = PixelBufferInspector.info(from: buf)
        if let info = pixelBufferInfo {
            addLog("サイズ: \(info.width)×\(info.height) | フォーマット: \(info.pixelFormatType) | bytesPerRow: \(info.bytesPerRow)")
        }

        if let cgImage = PixelBufferInspector.toCGImage(buf) {
            previewImage = UIImage(cgImage: cgImage)
            addLog("CGImage 変換成功 → UIImage 生成完了")
        }

        sampledPixel = PixelBufferInspector.samplePixel(at: CGPoint(x: 128, y: 128), in: buf)
        if let p = sampledPixel {
            addLog("(128,128) ピクセル: R=\(p.r) G=\(p.g) B=\(p.b) A=\(p.a)")
        }
    }

    func roundTrip(image: UIImage) {
        guard let cgImage = image.cgImage else { return }
        guard let buf = PixelBufferInspector.fromCGImage(cgImage) else {
            addLog("UIImage → CVPixelBuffer 変換失敗")
            return
        }
        addLog("UIImage → CVPixelBuffer 変換成功")
        let info = PixelBufferInspector.info(from: buf)
        addLog("Round-trip: \(info.width)×\(info.height) | \(info.pixelFormatType)")

        if let back = PixelBufferInspector.toCGImage(buf) {
            previewImage = UIImage(cgImage: back)
            addLog("CVPixelBuffer → CGImage → UIImage 完了")
        }
    }

    private func addLog(_ msg: String) {
        log.insert(msg, at: 0)
    }
}
