import SwiftUI
import CoreVideo
import CoreMedia
import Photos

@Observable
final class Step7ViewModel: CaptureEngineDelegate {
    var recordingState: RecordingState = .idle
    var savedVideoURL: URL?
    var permissionDenied = false
    var statusMessage = ""
    var previewImage: UIImage?
    var selectedFilter: FilterType = .none

    private let captureEngine = CaptureEngine()
    private let recorder = VideoRecorder()
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

        recorder.onStateChange = { [weak self] state in
            self?.recordingState = state
            switch state {
            case .idle: self?.statusMessage = "録画停止"
            case .recording: self?.statusMessage = "録画中..."
            case .finishing: self?.statusMessage = "書き出し中..."
            }
        }

        recorder.onFinished = { [weak self] url in
            guard let url else {
                self?.statusMessage = "録画失敗"
                return
            }
            self?.savedVideoURL = url
            self?.saveToPhotoLibrary(url: url)
        }
    }

    func toggleRecording() {
        switch recordingState {
        case .idle:
            setupDone = false
            recorder.selectedFilter = selectedFilter
            statusMessage = "録画開始準備中..."
        case .recording:
            recorder.stopRecording()
        case .finishing:
            break
        }
    }

    func stop() {
        captureEngine.stop()
        if recordingState == .recording {
            recorder.stopRecording()
        }
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

        if recordingState == .idle && statusMessage == "録画開始準備中..." {
            let w = CVPixelBufferGetWidth(pixelBuffer)
            let h = CVPixelBufferGetHeight(pixelBuffer)
            recorder.startRecording(width: w, height: h)
        }

        if recordingState == .recording {
            recorder.appendFrame(pixelBuffer: pixelBuffer, timestamp: timestamp)
        }
    }

    private func saveToPhotoLibrary(url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = "写真ライブラリ権限なし（一時ファイルに保存済）"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, _ in
                DispatchQueue.main.async { [weak self] in
                    self?.statusMessage = success ? "カメラロールに保存完了" : "保存失敗"
                }
            }
        }
    }
}
