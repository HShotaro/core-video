import SwiftUI
import MetalKit

struct Step5View: View {
    @State private var vm = Step5ViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if vm.permissionDenied {
                ContentUnavailableView("カメラ権限が必要です", systemImage: "camera.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ShaderMetalView(viewModel: vm)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 8) {
                    Text("カスタム Metal フラグメントシェーダー")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(ShaderEffect.allCases) { effect in
                                Button(effect.rawValue) {
                                    vm.selectedEffect = effect
                                }
                                .buttonStyle(.bordered)
                                .tint(vm.selectedEffect == effect ? .blue : .gray)
                                .font(.caption)
                            }
                        }
                        .padding(.horizontal)
                    }
                }
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .navigationTitle("Step 5: Metal シェーダー")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.setup() }
        .onDisappear { vm.stop() }
    }
}

private struct ShaderMetalView: UIViewRepresentable {
    let viewModel: Step5ViewModel

    func makeUIView(context: Context) -> MTKView {
        let view = MTKView()
        view.backgroundColor = .black
        let renderer = CustomShaderRenderer(mtkView: view)
        viewModel.renderer = renderer
        return view
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}
