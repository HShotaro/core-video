import SwiftUI

struct Step7View: View {
    @State private var vm = Step7ViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if vm.permissionDenied {
                ContentUnavailableView("カメラ権限が必要です", systemImage: "camera.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .bottomLeading) {
                    if let image = vm.previewImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView("カメラ起動中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if vm.recordingState == .recording {
                        HStack(spacing: 4) {
                            Circle().fill(.red).frame(width: 10, height: 10)
                            Text("REC").font(.system(.caption, design: .monospaced)).foregroundStyle(.red)
                        }
                        .padding(8)
                        .background(.black.opacity(0.5))
                        .cornerRadius(4)
                        .padding(12)
                    }
                }

                VStack(spacing: 8) {
                    if !vm.statusMessage.isEmpty {
                        Text(vm.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FilterType.allCases) { filter in
                                Button(filter.rawValue) {
                                    vm.selectedFilter = filter
                                }
                                .buttonStyle(.bordered)
                                .tint(vm.selectedFilter == filter ? .blue : .gray)
                                .font(.caption2)
                                .disabled(vm.recordingState == .recording)
                            }
                        }
                        .padding(.horizontal)
                    }

                    Button(recordButtonTitle) {
                        vm.toggleRecording()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(vm.recordingState == .recording ? .red : .blue)
                    .disabled(vm.recordingState == .finishing)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .navigationTitle("Step 7: リアルタイム録画")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.setup() }
        .onDisappear { vm.stop() }
    }

    private var recordButtonTitle: String {
        switch vm.recordingState {
        case .idle: return "録画開始"
        case .recording: return "録画停止"
        case .finishing: return "書き出し中..."
        }
    }
}
