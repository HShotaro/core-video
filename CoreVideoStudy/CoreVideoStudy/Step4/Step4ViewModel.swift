import SwiftUI
import CoreVideo
import CoreMedia

@Observable
final class Step4ViewModel: CaptureEngineDelegate {
    var filteredImage: UIImage?
    var selectedFilter: FilterType = .none
    var permissionDenied = false
    var processingTimeMs = ""

    private let captureEngine = CaptureEngine()
    private let filterEngine = CIFilterEngine()
    private var isProcessing = false

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
        guard !isProcessing else { return }
        isProcessing = true

        let filter = selectedFilter
        let start = CFAbsoluteTimeGetCurrent()
        let image = filterEngine.apply(filter: filter, to: pixelBuffer)
        let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000

        DispatchQueue.main.async { [weak self] in
            self?.filteredImage = image
            self?.processingTimeMs = String(format: "%.1f ms", elapsed)
            self?.isProcessing = false
        }
    }
}
