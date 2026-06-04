import SwiftUI
import CoreVideo
import CoreMedia

@Observable
final class Step5ViewModel: CaptureEngineDelegate {
    var selectedEffect: ShaderEffect = .passthrough
    var permissionDenied = false
    var frameInfo = ""

    let captureEngine = CaptureEngine()
    var renderer: CustomShaderRenderer?

    func setup() {
        Task {
            let granted = await captureEngine.requestPermissionAndSetup()
            if granted {
                captureEngine.delegate = self
                captureEngine.start()
            } else {
                permissionDenied = true
            }
        }
    }

    func stop() {
        captureEngine.stop()
    }

    func captureEngine(_ engine: CaptureEngine, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        renderer?.update(pixelBuffer: pixelBuffer)

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        DispatchQueue.main.async { [weak self] in
            self?.frameInfo = "\(width)×\(height)"
            self?.renderer?.currentEffect = self?.selectedEffect ?? .passthrough
        }
    }
}
