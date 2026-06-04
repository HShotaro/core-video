import SwiftUI

struct Step4View: View {
    @State private var vm = Step4ViewModel()

    var body: some View {
        VStack(spacing: 0) {
            if vm.permissionDenied {
                ContentUnavailableView("カメラ権限が必要です", systemImage: "camera.slash")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ZStack(alignment: .topTrailing) {
                    if let image = vm.filteredImage {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ProgressView("カメラ起動中...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }

                    if !vm.processingTimeMs.isEmpty {
                        Text(vm.processingTimeMs)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(4)
                            .background(.black.opacity(0.6))
                            .foregroundStyle(.white)
                            .cornerRadius(4)
                            .padding(8)
                    }
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FilterType.allCases) { filter in
                            Button(filter.rawValue) {
                                vm.selectedFilter = filter
                            }
                            .buttonStyle(.bordered)
                            .tint(vm.selectedFilter == filter ? .blue : .gray)
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 8)
                .background(.bar)
            }
        }
        .navigationTitle("Step 4: Core Image フィルター")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { vm.setup() }
        .onDisappear { vm.stop() }
    }
}
