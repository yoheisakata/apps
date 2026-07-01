import SwiftUI

struct ContentView: View {
    @StateObject private var cacheVM = CacheViewModel()
    @StateObject private var appVM = AppViewModel()

    var body: some View {
        TabView {
            CacheCleanerView(vm: cacheVM)
                .tabItem { Label("キャッシュ掃除", systemImage: "sparkles") }

            AppUninstallerView(vm: appVM)
                .tabItem { Label("アプリ削除", systemImage: "trash") }
        }
        .padding(12)
    }
}
