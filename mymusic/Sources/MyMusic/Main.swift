import AppKit

let appVersion = "1.1.0"

/// SwiftUI の `App`/`WindowGroup` は使わない — 最後のウィンドウを閉じると
/// アプリごと終了してしまうため、AppDelegate でメニューバー常駐を手動管理する
/// (downloader/Sources/Downloader/App.swift と同じ構成)。
@main
enum MyMusicMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
