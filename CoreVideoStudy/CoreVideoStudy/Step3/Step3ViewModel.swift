import SwiftUI
import CoreVideo
import CoreMedia

@Observable
final class Step3ViewModel: CaptureEngineDelegate {
    var frameInfo = ""
    var isRunning = false
    var permissionDenied = false

    let engine = CaptureEngine()
    var renderer: MetalRenderer?

    func setup() {
        Task {
            let granted = await engine.requestPermissionAndSetup()
            if granted {
                engine.delegate = self
                engine.start()
                isRunning = true
            } else {
                permissionDenied = true
            }
        }
    }

    func stop() {
        engine.stop()
        isRunning = false
    }

    func captureEngine(_ engine: CaptureEngine, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        renderer?.update(pixelBuffer: pixelBuffer)

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let seconds = CMTimeGetSeconds(timestamp)
        let info = "\(width)×\(height) | \(String(format: "%.3f", seconds))s"
        DispatchQueue.main.async { [weak self] in
            self?.frameInfo = info
        }
    }
}
