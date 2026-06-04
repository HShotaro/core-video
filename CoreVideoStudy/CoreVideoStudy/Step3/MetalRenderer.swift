import Metal
import MetalKit
import CoreVideo
import AVFoundation

final class MetalRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var renderPipeline: MTLRenderPipelineState?

    private var currentTexture: MTLTexture?
    private let lock = NSLock()

    init?(mtkView: MTKView) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue()
        else { return nil }

        self.device = device
        self.commandQueue = queue
        super.init()

        mtkView.device = device
        mtkView.delegate = self
        mtkView.framebufferOnly = true
        mtkView.colorPixelFormat = .bgra8Unorm

        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        buildPipeline(mtkView: mtkView)
    }

    func update(pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            cache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width, height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture else { return }
        let texture = CVMetalTextureGetTexture(cvTexture)

        lock.lock()
        currentTexture = texture
        lock.unlock()
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        lock.lock()
        let texture = currentTexture
        lock.unlock()

        guard
            let texture,
            let pipeline = renderPipeline,
            let drawable = view.currentDrawable,
            let descriptor = view.currentRenderPassDescriptor,
            let cmdBuffer = commandQueue.makeCommandBuffer(),
            let encoder = cmdBuffer.makeRenderCommandEncoder(descriptor: descriptor)
        else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        encoder.endEncoding()

        cmdBuffer.present(drawable)
        cmdBuffer.commit()
    }

    // MARK: - Private

    private func buildPipeline(mtkView: MTKView) {
        let vertexSrc = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut { float4 pos [[position]]; float2 uv; };
        vertex VertexOut vert(uint vid [[vertex_id]]) {
            float2 pos[4] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };
            float2 uv[4]  = { {0,1},   {1,1},  {0,0},  {1,0} };
            VertexOut out;
            out.pos = float4(pos[vid], 0, 1);
            out.uv  = uv[vid];
            return out;
        }
        """
        let fragmentSrc = """
        #include <metal_stdlib>
        using namespace metal;
        struct VertexOut { float4 pos [[position]]; float2 uv; };
        fragment float4 frag(VertexOut in [[stage_in]],
                             texture2d<float> tex [[texture(0)]]) {
            constexpr sampler s(filter::linear);
            return tex.sample(s, in.uv);
        }
        """
        guard
            let lib = try? device.makeLibrary(source: vertexSrc + fragmentSrc, options: nil),
            let vert = lib.makeFunction(name: "vert"),
            let frag = lib.makeFunction(name: "frag")
        else { return }

        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vert
        desc.fragmentFunction = frag
        desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
        renderPipeline = try? device.makeRenderPipelineState(descriptor: desc)
    }
}
