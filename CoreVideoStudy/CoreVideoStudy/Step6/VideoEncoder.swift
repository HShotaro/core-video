import VideoToolbox
import CoreMedia
import CoreVideo

struct EncodedFrameInfo {
    let isKeyFrame: Bool
    let presentationTimeStamp: CMTime
    let dataSize: Int
    let codecType: String
}

final class VideoEncoder {
    private var session: VTCompressionSession?
    var onEncodedFrame: ((EncodedFrameInfo) -> Void)?

    var encodedCount = 0
    var keyFrameCount = 0

    func setup(width: Int, height: Int, codec: CMVideoCodecType = kCMVideoCodecType_H264) -> Bool {
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: codec,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: outputCallback,
            refcon: Unmanaged.passUnretained(self).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else { return false }

        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel,
                             value: kVTProfileLevel_H264_High_AutoLevel)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate,
                             value: 2_000_000 as CFNumber)
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_MaxKeyFrameInterval,
                             value: 30 as CFNumber)
        VTCompressionSessionPrepareToEncodeFrames(session)
        return true
    }

    func encode(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let session else { return }
        VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: timestamp,
            duration: CMTime(value: 1, timescale: 30),
            frameProperties: nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: nil
        )
    }

    func invalidate() {
        guard let session else { return }
        VTCompressionSessionInvalidate(session)
        self.session = nil
    }

    // MARK: - C Callback

    private let outputCallback: VTCompressionOutputCallback = { refcon, _, status, flags, sampleBuffer in
        guard
            status == noErr,
            let sampleBuffer,
            let refcon
        else { return }

        let encoder = Unmanaged<VideoEncoder>.fromOpaque(refcon).takeUnretainedValue()
        encoder.encodedCount += 1

        let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false)
            as? [[CFString: Any]]
        let isNotSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
        let isKey = !flags.contains(.frameDropped) && !isNotSync

        if isKey { encoder.keyFrameCount += 1 }

        let size = CMSampleBufferGetTotalSampleSize(sampleBuffer)
        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        let info = EncodedFrameInfo(
            isKeyFrame: isKey,
            presentationTimeStamp: pts,
            dataSize: size,
            codecType: "H.264"
        )
        DispatchQueue.main.async {
            encoder.onEncodedFrame?(info)
        }
    }
}
