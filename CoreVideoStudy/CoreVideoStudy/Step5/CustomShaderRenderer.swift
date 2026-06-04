import Metal
import MetalKit
import CoreVideo

enum ShaderEffect: String, CaseIterable, Identifiable {
    case passthrough = "パススルー"
    case grayscale = "グレースケール"
    case negative = "ネガ反転"
    case sepia = "セピア"
    case sobel = "エッジ検出 (Sobel)"
    case pixelate = "モザイク"

    var id: String { rawValue }
}

final class CustomShaderRenderer: NSObject, MTKViewDelegate {
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    private var pipelines: [ShaderEffect: MTLRenderPipelineState] = [:]

    private var currentTexture: MTLTexture?
    private let lock = NSLock()
    var currentEffect: ShaderEffect = .passthrough

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
        buildPipelines(mtkView: mtkView)
    }

    func update(pixelBuffer: CVPixelBuffer) {
        guard let cache = textureCache else { return }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault, cache, pixelBuffer, nil,
            .bgra8Unorm, width, height, 0, &cvTexture
        )
        guard status == kCVReturnSuccess, let cvTexture else { return }

        lock.lock()
        currentTexture = CVMetalTextureGetTexture(cvTexture)
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
            let pipeline = pipelines[currentEffect],
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

    // MARK: - Pipeline building

    private func buildPipelines(mtkView: MTKView) {
        let vertexSrc = """
        #include <metal_stdlib>
        using namespace metal;
        struct V { float4 pos [[position]]; float2 uv; };
        vertex V vert(uint vid [[vertex_id]]) {
            float2 p[4] = { {-1,-1}, {1,-1}, {-1,1}, {1,1} };
            float2 u[4] = { {0,1},   {1,1},  {0,0},  {1,0} };
            V out; out.pos = float4(p[vid],0,1); out.uv = u[vid];
            return out;
        }
        """

        let fragments: [ShaderEffect: String] = [
            .passthrough: passthroughFrag,
            .grayscale: grayscaleFrag,
            .negative: negativeFrag,
            .sepia: sepiaFrag,
            .sobel: sobelFrag,
            .pixelate: pixelateFrag,
        ]

        for (effect, fragSrc) in fragments {
            guard
                let lib = try? device.makeLibrary(source: vertexSrc + fragSrc, options: nil),
                let vert = lib.makeFunction(name: "vert"),
                let frag = lib.makeFunction(name: "frag")
            else { continue }

            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = vert
            desc.fragmentFunction = frag
            desc.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat
            pipelines[effect] = try? device.makeRenderPipelineState(descriptor: desc)
        }
    }

    private let passthroughFrag = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 pos [[position]]; float2 uv; };
    fragment float4 frag(V in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::linear);
        return tex.sample(s, in.uv);
    }
    """

    private let grayscaleFrag = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 pos [[position]]; float2 uv; };
    fragment float4 frag(V in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::linear);
        float4 c = tex.sample(s, in.uv);
        float g = dot(c.rgb, float3(0.299, 0.587, 0.114));
        return float4(g, g, g, c.a);
    }
    """

    private let negativeFrag = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 pos [[position]]; float2 uv; };
    fragment float4 frag(V in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::linear);
        float4 c = tex.sample(s, in.uv);
        return float4(1.0 - c.rgb, c.a);
    }
    """

    private let sepiaFrag = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 pos [[position]]; float2 uv; };
    fragment float4 frag(V in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::linear);
        float4 c = tex.sample(s, in.uv);
        float r = dot(c.rgb, float3(0.393, 0.769, 0.189));
        float g = dot(c.rgb, float3(0.349, 0.686, 0.168));
        float b = dot(c.rgb, float3(0.272, 0.534, 0.131));
        return float4(r, g, b, c.a);
    }
    """

    private let sobelFrag = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 pos [[position]]; float2 uv; };
    fragment float4 frag(V in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::linear);
        uint2 sz = uint2(tex.get_width(), tex.get_height());
        float2 d = float2(1.0/sz.x, 1.0/sz.y);
        auto lum = [&](float2 uv) {
            float4 c = tex.sample(s, uv);
            return dot(c.rgb, float3(0.299, 0.587, 0.114));
        };
        float gx = -lum(in.uv+float2(-d.x,-d.y)) - 2*lum(in.uv+float2(-d.x,0)) - lum(in.uv+float2(-d.x,d.y))
                   +lum(in.uv+float2( d.x,-d.y)) + 2*lum(in.uv+float2( d.x,0)) + lum(in.uv+float2( d.x,d.y));
        float gy = -lum(in.uv+float2(-d.x,-d.y)) - 2*lum(in.uv+float2(0,-d.y)) - lum(in.uv+float2(d.x,-d.y))
                   +lum(in.uv+float2(-d.x, d.y)) + 2*lum(in.uv+float2(0, d.y)) + lum(in.uv+float2(d.x, d.y));
        float edge = clamp(sqrt(gx*gx + gy*gy), 0.0, 1.0);
        return float4(edge, edge, edge, 1.0);
    }
    """

    private let pixelateFrag = """
    #include <metal_stdlib>
    using namespace metal;
    struct V { float4 pos [[position]]; float2 uv; };
    fragment float4 frag(V in [[stage_in]], texture2d<float> tex [[texture(0)]]) {
        constexpr sampler s(filter::nearest);
        float blockSize = 20.0;
        uint2 sz = uint2(tex.get_width(), tex.get_height());
        float2 block = floor(in.uv * float2(sz) / blockSize) * blockSize / float2(sz);
        return tex.sample(s, block);
    }
    """
}
