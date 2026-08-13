import SwiftUI

/// トップレベルのビュー。かつては「YouTube」「Torrent」の `TabView` だったが、
/// torrent 機能(aria2c ラッパー)を撤去したため YouTube タブの中身をそのまま表示する。
struct ContentView: View {
    var body: some View {
        YouTubeView()
    }
}
