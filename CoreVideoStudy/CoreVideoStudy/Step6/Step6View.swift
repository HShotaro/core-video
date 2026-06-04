import SwiftUI

struct Step6View: View {
    @State private var vm = Step6ViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if vm.permissionDenied {
                    ContentUnavailableView("カメラ権限が必要です", systemImage: "camera.slash")
                } else {
                    if let image = vm.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity)
                            .cornerRadius(8)
                    } else {
                        ProgressView("カメラ起動中...").frame(height: 200)
                    }

                    Button(vm.isEncoding ? "エンコード停止" : "H.264 エンコード開始") {
                        vm.toggleEncoding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.isEncoding ? .red : .blue)
                    .frame(maxWidth: .infinity)

                    if vm.encodedFrameCount > 0 {
                        GroupBox("VTCompressionSession 出力") {
                            InfoRow(label: "エンコード済みフレーム", value: "\(vm.encodedFrameCount)")
                            InfoRow(label: "キーフレーム (I フレーム)", value: "\(vm.keyFrameCount)")
                            InfoRow(label: "最新フレームサイズ", value: vm.lastFrameSize)
                            InfoRow(label: "PTS", value: vm.lastPTS)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Step 6: VideoToolbox")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.setup() }
        .onDisappear { vm.stop() }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary).font(.caption)
            Spacer()
            Text(value).font(.system(.caption, design: .monospaced))
        }
    }
}
