import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            YouTubeView()
                .tabItem { Label("YouTube", systemImage: "play.rectangle") }
            TorrentView()
                .tabItem { Label("Torrent", systemImage: "arrow.down.circle") }
        }
    }
}
