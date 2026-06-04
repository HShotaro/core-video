import CoreImage
import CoreVideo
import UIKit

enum FilterType: String, CaseIterable, Identifiable {
    case none = "なし"
    case grayscale = "グレースケール"
    case sepia = "セピア"
    case blur = "ガウシアンブラー"
    case sharpen = "シャープ"
    case vibrance = "ビビッド"
    case invert = "反転"
    case vignette = "ビネット"

    var id: String { rawValue }
}

final class CIFilterEngine {
    private let context: CIContext

    init() {
        // GPU ベースの CIContext（Metal バックエンド）
        context = CIContext(options: [.useSoftwareRenderer: false])
    }

    func apply(filter: FilterType, to pixelBuffer: CVPixelBuffer) -> UIImage? {
        var ciImage = CIImage(cvPixelBuffer: pixelBuffer)

        switch filter {
        case .none:
            break

        case .grayscale:
            ciImage = ciImage.applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.0
            ])

        case .sepia:
            ciImage = ciImage.applyingFilter("CISepiaTone", parameters: [
                kCIInputIntensityKey: 0.8
            ])

        case .blur:
            ciImage = ciImage.applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: 8.0
            ])
            // ブラーはエッジが透明になるためクロップ
            ciImage = ciImage.cropped(to: CIImage(cvPixelBuffer: pixelBuffer).extent)

        case .sharpen:
            ciImage = ciImage.applyingFilter("CISharpenLuminance", parameters: [
                kCIInputSharpnessKey: 1.5
            ])

        case .vibrance:
            ciImage = ciImage.applyingFilter("CIVibrance", parameters: [
                kCIInputAmountKey: 1.5
            ])

        case .invert:
            ciImage = ciImage.applyingFilter("CIColorInvert")

        case .vignette:
            ciImage = ciImage.applyingFilter("CIVignette", parameters: [
                kCIInputIntensityKey: 1.5,
                kCIInputRadiusKey: 1.0
            ])
        }

        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    func applyToCVPixelBuffer(filter: FilterType, input: CVPixelBuffer) -> CVPixelBuffer? {
        var ciImage = CIImage(cvPixelBuffer: input)

        switch filter {
        case .none: break
        case .grayscale:
            ciImage = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        case .sepia:
            ciImage = ciImage.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: 0.8])
        default:
            ciImage = ciImage.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0.0])
        }

        let width = CVPixelBufferGetWidth(input)
        let height = CVPixelBufferGetHeight(input)
        var output: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &output)
        guard let output else { return nil }
        context.render(ciImage, to: output)
        return output
    }
}
