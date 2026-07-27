import AppKit

/// SwiftUI の `App`/`WindowGroup` は使わない — 最後のウィンドウを閉じると
/// アプリごと終了してしまうため、AppDelegate でメニューバー常駐を手動管理する。
@main
enum DownloaderMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
