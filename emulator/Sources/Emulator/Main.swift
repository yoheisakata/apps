import SwiftUI

let appVersion = "0.1.0"

@main
struct RetroGamesApp: App {
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
                    .keyboardShortcut("w", modifiers: .command)
                }
            }
        }
    }
}
