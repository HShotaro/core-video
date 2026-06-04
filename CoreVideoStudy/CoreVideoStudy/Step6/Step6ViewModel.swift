import SwiftUI
import CoreVideo
import CoreMedia

@Observable
final class Step6ViewModel: CaptureEngineDelegate {
    var isEncoding = false
    var encodedFrameCount = 0
    var keyFrameCount = 0
    var lastFrameSize = ""
    var lastPTS = ""
    var permissionDenied = false
    var previewImage: UIImage?

    private let captureEngine = CaptureEngine()
    private let encoder = VideoEncoder()
    private var setupDone = false
    private var frameCount = 0

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

        encoder.onEncodedFrame = { [weak self] info in
            guard let self else { return }
            encodedFrameCount = encoder.encodedCount
            keyFrameCount = encoder.keyFrameCount
            lastFrameSize = "\(info.dataSize) bytes\(info.isKeyFrame ? " [I]" : " [P]")"
            lastPTS = String(format: "%.3f s", CMTimeGetSeconds(info.presentationTimeStamp))
        }
    }

    func toggleEncoding() {
        isEncoding.toggle()
        if !isEncoding {
            encoder.invalidate()
            setupDone = false
        }
    }

    func stop() {
        captureEngine.stop()
        encoder.invalidate()
    }

    func captureEngine(_ engine: CaptureEngine, didOutput pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        frameCount += 1
        if frameCount % 3 == 0 {
            let ci = CIImage(cvPixelBuffer: pixelBuffer)
            let ctx = CIContext()
            if let cg = ctx.createCGImage(ci, from: ci.extent) {
                let img = UIImage(cgImage: cg)
                DispatchQueue.main.async { [weak self] in self?.previewImage = img }
            }
        }

        guard isEncoding else { return }

        if !setupDone {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            setupDone = encoder.setup(width: w, height: h)
        }
        encoder.encode(pixelBuffer: pixelBuffer, timestamp: timestamp)
    }
}
