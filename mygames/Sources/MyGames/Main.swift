import SwiftUI
import AppKit

let appVersion = "0.3.0"

/// ⌘Q やウィンドウを閉じたときの終了処理。エミュレーションタイマーを止めないまま
/// プロセスが exit() に入ると、実行中の retro_run とレースしてクラッシュするため
/// (snes9x の SPC_DSP::run 内で SIGSEGV する事例あり)、後片付けが終わるまで終了を遅らせる。
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let core = LibretroCore.current, core.isRunning else { return .terminateNow }
        core.stop {
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}

@main
struct MyGamesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var emulator = EmulatorViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(emulator)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("ROMを開く…") {
                    emulator.openFilePanel()
                }
                .keyboardShortcut("o", modifiers: .command)

                Divider()

                if emulator.isRunning {
                    Button(emulator.isPaused ? "再開" : "一時停止") {
                        emulator.togglePause()
                    }
                    .keyboardShortcut("p", modifiers: .command)

                    Button("リセット") {
                        emulator.reset()
                    }
                    .keyboardShortcut("r", modifiers: .command)

                    Divider()

                    Button("ステートセーブ") {
                        emulator.saveState()
                    }
                    .keyboardShortcut("s", modifiers: [.command, .shift])

                    Button("ステートロード") {
                        emulator.loadState()
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])

                    Divider()

                    Button("停止") {
                        emulator.stop()
                    }
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
        }
    }
}
