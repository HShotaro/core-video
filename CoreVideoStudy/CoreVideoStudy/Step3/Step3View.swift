import SwiftUI
import MetalKit

struct Step3View: View {
    @State private var vm = Step3ViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if vm.permissionDenied {
                ContentUnavailableView("カメラ権限が必要です", systemImage: "camera.slash")
            } else {
                MetalView(viewModel: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 4) {
                    Text("CVMetalTextureCache ゼロコピーレンダリング")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if !vm.frameInfo.isEmpty {
                        Text(vm.frameInfo)
                            .font(.system(.caption2, design: .monospaced))
                    }
                }
                .padding(8)
                .background(.bar)
            }
        }
        .navigationTitle("Step 3: Metal レンダリング")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.setup() }
        .onDisappear { vm.stop() }
    }
}

private struct MetalView: UIViewRepresentable {
    let viewModel: Step3ViewModel

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor = .black
        let renderer = MetalRenderer(mtkView: view)
        viewModel.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
