import SwiftUI
import CoreVideo
import CoreMedia

@Observable
final class Step2ViewModel: CaptureEngineDelegate {
    var previewImage: UIImage?
    var frameInfo = ""
    var pixelFormatType = ""
    var frameTimestamp = ""
    var permissionDenied = false

    private let engine = CaptureEngine()
    private var frameCount = 0

    func onAppear() {
        Task {
            let granted = await engine.requestPermissionAndSetup()
            if granted {
                engine.delegate = self
                engine.start()
            } else {
                permissionDenied = true
            }
        }
    }

    func onDisappear() {
        engine.stop()
    }

    func captureEngine(_ engine: CaptureEngine, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        frameCount += 1
        guard frameCount % 3 == 0 else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)

        let image = pixelBufferToUIImage(pixelBuffer)
        let seconds = CMTimeGetSeconds(timestamp)
        let info = "\(width)×\(height) | bytesPerRow: \(bytesPerRow)"
        let fmt = fourCCString(format)
        let ts = String(format: "%.3f s", seconds)

        DispatchQueue.main.async { [weak self] in
            self?.previewImage = image
            self?.frameInfo = info
            self?.pixelFormatType = fmt
            self?.frameTimestamp = ts
        }
    }

    private func pixelBufferToUIImage(_ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private func fourCCString(_ format: OSType) -> String {
        let chars: [Character] = [
            Character(UnicodeScalar((format >> 24) & 0xFF)!),
            Character(UnicodeScalar((format >> 16) & 0xFF)!),
            Character(UnicodeScalar((format >> 8) & 0xFF)!),
            Character(UnicodeScalar(format & 0xFF)!),
        ]
        return String(chars)
    }
}
