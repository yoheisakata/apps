import SwiftUI

struct ContentView: View {
    @StateObject private var cacheVM = CacheViewModel()
    @StateObject private var appVM = AppViewModel()
    @StateObject private var dupEngine = DupPhotosEngine()

    var body: some View {
        TabView {
            CacheCleanerView(vm: cacheVM)
                .tabItem { Label("キャッシュ掃除", systemImage: "sparkles") }

            AppUninstallerView(vm: appVM)
                .tabItem { Label("アプリ削除", systemImage: "trash") }

            DupPhotosView(engine: dupEngine)
                .tabItem { Label("重複写真", systemImage: "photo.on.rectangle.angled") }
        }
        .padding(12)
    }
}
