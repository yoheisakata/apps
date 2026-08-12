import AppKit
import SwiftUI
import CoreServices

/// 通常の Dock アイコン付きアプリ(`.regular`)として動作する。ただし
/// `NSApplication.shared.run()` を直接呼ぶ構成(SwiftUI の App/WindowGroup を使わない ―
/// `App.swift` 参照)のままなので、macOS の WindowGroup アプリのデフォルト挙動である
/// 「最後のウィンドウを閉じるとアプリも終了する」は適用されない。ウィンドウを閉じても
/// プロセス(と aria2c 子プロセス、yt-dlp のダウンロード)は終了せず、Dock アイコン右クリック
/// またはメニューバー拡張アイコンの「終了」を選んだ時(=Cmd+Qと同義)だけ本当に終了する。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let aria2Engine = Aria2Engine()
    let ytDlpManager = YtDlpManager()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?

    /// ブラウザで magnet: リンクをクリックした際に macOS が送ってくる Apple Event を受け取れるよう、
    /// 起動の最初期(applicationDidFinishLaunching より前)にハンドラを登録しておく。
    /// ここで登録し忘れると、アプリ未起動状態からの初回クリックを取りこぼす。
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURL(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        Settings.registerDefaults()
        setupMainMenu()
        aria2Engine.start()
        setupStatusItem()
        showWindow()
        aria2Engine.noteEvent("起動完了 (applicationDidFinishLaunching)")
    }

    /// `NSApplication.shared.run()` を直接呼ぶ構成(SwiftUI の App/WindowGroup を使わない)では
    /// mainMenu が自動生成されない。Edit メニュー(Cut/Copy/Paste/Select All)が無いと
    /// テキストフィールドで Cmd+V などの標準編集ショートカットが効かないため、最低限のメニューを組み立てる。
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Downloader を終了", action: #selector(quitAction), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        editMenu.addItem(withTitle: "カット", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "コピー", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "ペースト", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "すべてを選択", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    /// magnet: リンクからの起動・呼び出しを処理する。
    @objc private func handleGetURL(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue else {
            aria2Engine.noteEvent("kAEGetURL イベントを受信したが URL 文字列が取得できなかった")
            return
        }
        aria2Engine.noteEvent("kAEGetURL イベント受信: \(urlString.prefix(100))")
        aria2Engine.addMagnet(urlString)
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Dock アイコンをクリックしたとき(ウィンドウを閉じた後など)にウィンドウを呼び戻す。
    /// 通常の Dock アプリならではの期待挙動 ― `.accessory` の頃は Dock アイコンが無く不要だった。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showWindow()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        aria2Engine.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: "downloader")

        let menu = NSMenu()
        menu.addItem(withTitle: "ウィンドウを開く", action: #selector(showWindowAction), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "終了", action: #selector(quitAction), keyEquivalent: "q")
        for menuItem in menu.items {
            menuItem.target = self
        }
        item.menu = menu
        statusItem = item
    }

    @objc private func showWindowAction() {
        showWindow()
    }

    @objc private func quitAction() {
        aria2Engine.stop()
        NSApp.terminate(nil)
    }

    private func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ContentView()
            .environmentObject(aria2Engine)
            .environmentObject(ytDlpManager)
        let hosting = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "Downloader"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        newWindow.setContentSize(NSSize(width: 640, height: 560))
        newWindow.center()
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
    }
}
