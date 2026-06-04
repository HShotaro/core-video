import SwiftUI

struct Step2View: View {
    @State private var vm = Step2ViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if vm.permissionDenied {
                    ContentUnavailableView(
                        "カメラ権限が必要です",
                        systemImage: "camera.slash",
                        description: Text("設定 > プライバシー > カメラ で許可してください")
                    )
                } else if let image = vm.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .cornerRadius(8)
                } else {
                    ProgressView("カメラ起動中...")
                        .frame(height: 200)
                }

                if !vm.frameInfo.isEmpty {
                    GroupBox("CMSampleBuffer → CVPixelBuffer") {
                        InfoRow(label: "解像度 / bytesPerRow", value: vm.frameInfo)
                        InfoRow(label: "PixelFormat (FourCC)", value: vm.pixelFormatType)
                        InfoRow(label: "タイムスタンプ", value: vm.frameTimestamp)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Step 2: AVCaptureSession")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.onAppear() }
        .onDisappear { vm.onDisappear() }
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
