import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink("Step 1: CVPixelBuffer の基礎") {
                    Step1View()
                }
                NavigationLink("Step 2: AVCaptureSession でカメラ映像を取得") {
                    Step2View()
                }
                NavigationLink("Step 3: Metal でリアルタイム描画") {
                    Step3View()
                }
                NavigationLink("Step 4: Core Image フィルター") {
                    Step4View()
                }
                NavigationLink("Step 5: カスタム Metal シェーダー") {
                    Step5View()
                }
                NavigationLink("Step 6: VideoToolbox でハードウェアエンコード") {
                    Step6View()
                }
                NavigationLink("Step 7: リアルタイム録画") {
                    Step7View()
                }
            }
            .navigationTitle("Core Video Study")
        }
    }
}

#Preview {
    ContentView()
}
