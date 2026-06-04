import SwiftUI

struct Step1View: View {
    @State private var vm = Step1ViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let image = vm.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity)
                        .frame(height: 200)
                        .background(Color.black)
                        .cornerRadius(8)
                }

                if let info = vm.pixelBufferInfo {
                    GroupBox("CVPixelBuffer プロパティ") {
                        InfoRow(label: "サイズ", value: "\(info.width) × \(info.height)")
                        InfoRow(label: "フォーマット (FourCC)", value: info.pixelFormatType)
                        InfoRow(label: "bytesPerRow", value: "\(info.bytesPerRow)")
                        InfoRow(label: "dataSize", value: "\(info.dataSize) bytes")
                        InfoRow(label: "planeCount", value: "\(info.planeCount)")
                        InfoRow(label: "ポインタ", value: info.pointer)
                    }
                }

                if let p = vm.sampledPixel {
                    GroupBox("サンプリング (128, 128)") {
                        HStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color(red: Double(p.r)/255, green: Double(p.g)/255, blue: Double(p.b)/255))
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading) {
                                Text("R: \(p.r)  G: \(p.g)  B: \(p.b)  A: \(p.a)")
                                    .font(.system(.body, design: .monospaced))
                            }
                        }
                    }
                }

                Button("CVPixelBuffer を作成・描画・サンプリング") {
                    vm.createAndFill()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                GroupBox("ログ") {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(vm.log, id: \.self) { line in
                            Text(line)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Step 1: CVPixelBuffer")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
                .font(.caption)
            Spacer()
            Text(value)
                .font(.system(.caption, design: .monospaced))
        }
    }
}
