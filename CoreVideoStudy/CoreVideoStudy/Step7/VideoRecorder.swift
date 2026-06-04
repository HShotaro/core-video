import AVFoundation
import CoreVideo
import CoreImage
import UIKit

enum RecordingState {
    case idle, recording, finishing
}

final class VideoRecorder {
    var state: RecordingState = .idle
    var onStateChange: ((RecordingState) -> Void)?
    var onFinished: ((URL?) -> Void)?

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var startTime: CMTime?
    private let filterEngine = CIFilterEngine()

    var selectedFilter: FilterType = .none

    func startRecording(width: Int, height: Int) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".mp4")

        guard let writer = try? AVAssetWriter(url: url, fileType: .mp4) else { return }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ]
        ]

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: attrs
        )

        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        self.assetWriter = writer
        self.videoInput = input
        self.adaptor = adaptor
        self.startTime = nil
        self.state = .recording
        onStateChange?(.recording)
    }

    func appendFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard state == .recording, let input = videoInput, input.isReadyForMoreMediaData else { return }

        let presentationTime: CMTime
        if let start = startTime {
            presentationTime = CMTimeSubtract(timestamp, start)
        } else {
            startTime = timestamp
            presentationTime = .zero
        }

        let filtered = filterEngine.applyToCVPixelBuffer(filter: selectedFilter, input: pixelBuffer) ?? pixelBuffer
        adaptor?.append(filtered, withPresentationTime: presentationTime)
    }

    func stopRecording() {
        guard state == .recording else { return }
        state = .finishing
        onStateChange?(.finishing)

        videoInput?.markAsFinished()
        assetWriter?.finishWriting { [weak self] in
            let url = self?.assetWriter?.outputURL
            DispatchQueue.main.async {
                self?.state = .idle
                self?.onStateChange?(.idle)
                self?.onFinished?(url)
            }
        }
    }
}
