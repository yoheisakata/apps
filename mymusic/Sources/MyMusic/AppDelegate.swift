import AppKit
import SwiftUI

/// Dock アイコンを持つ通常のアプリ(`.regular`)。mytube と同じく**メニューバーには常駐しない**
/// (2026-08-12、「mytube のようにメニューバーに置かなくていい」という要望への対応。
/// それ以前は `LSUIElement` + ステータスアイテムでメニューバーに常駐していた)。
/// ただし mytube と違い、**ウィンドウを閉じてもアプリは終了しない**(再生を止めないため) ―
/// `applicationShouldTerminateAfterLastWindowClosed` は `false` のままで、Dock アイコンを
/// クリックすると `applicationShouldHandleReopen` でウィンドウを開き直す。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = PlaylistStore()
    let player = PlayerEngine()
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        setupMainMenu()
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// ウィンドウを閉じた後に Dock アイコンをクリックしたときの復帰口
    /// (メニューバーの「ウィンドウを開く」が無くなったため、ここが主な入口になる)。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows { showWindow() }
        return true
    }

    /// `NSApplication.shared.run()` を直接呼ぶ構成では mainMenu が自動生成されないため、
    /// テキストフィールドで Cmd+V などの標準編集ショートカットが効くよう最低限のメニューを組み立てる。
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let showItem = appMenu.addItem(withTitle: "ウィンドウを開く", action: #selector(showWindowAction), keyEquivalent: "0")
        showItem.target = self
        appMenu.addItem(.separator())
        let quitItem = appMenu.addItem(withTitle: "MyMusic を終了", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
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

    @objc private func showWindowAction() {
        showWindow()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    private func showWindow() {
        if let window {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = ContentView()
            .environmentObject(store)
            .environmentObject(player)
        let hosting = NSHostingController(rootView: rootView)
        let newWindow = NSWindow(contentViewController: hosting)
        newWindow.title = "MyMusic"
        newWindow.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        // サイドバー(220pt)+ 曲リストの横長レイアウトに合わせた既定サイズ。
        newWindow.setContentSize(NSSize(width: 940, height: 620))
        newWindow.contentMinSize = NSSize(width: 720, height: 420)
        newWindow.center()
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
    }
}
