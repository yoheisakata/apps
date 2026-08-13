import AppKit
import SwiftUI

/// LSUIElement アプリ(Dock アイコンなし)として、メニューバーに常駐する。
/// ウィンドウを閉じても再生(と PlaylistStore/PlayerEngine)は終了せず、
/// メニューバーの「終了」を選んだ時だけ本当に終了する(downloader/Sources/Downloader/AppDelegate.swift と同じ構成)。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = PlaylistStore()
    let player = PlayerEngine()
    private var statusItem: NSStatusItem?
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupMainMenu()
        setupStatusItem()
        showWindow()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// `NSApplication.shared.run()` を直接呼ぶ構成では mainMenu が自動生成されないため、
    /// テキストフィールドで Cmd+V などの標準編集ショートカットが効くよう最低限のメニューを組み立てる。
    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
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

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "music.note", accessibilityDescription: "MyMusic")

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
        newWindow.setContentSize(NSSize(width: 380, height: 640))
        newWindow.center()
        newWindow.delegate = self
        newWindow.makeKeyAndOrderFront(nil)
        window = newWindow
        NSApp.activate(ignoringOtherApps: true)
    }
}
