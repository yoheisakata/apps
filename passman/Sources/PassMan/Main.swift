import SwiftUI

@main
struct PassManApp: App {
    @StateObject private var vault = VaultModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(vault)
                .frame(minWidth: 640, minHeight: 420)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(after: .appSettings) {
                Menu("暗号化バックアップ") {
                    Button("バックアップを書き出す…") {
                        exportBackup(vault: vault)
                    }
                    .disabled(vault.state != .unlocked)

                    Button("バックアップから復元…") {
                        vault.showingBackupRestore = true
                    }
                    .disabled(vault.state != .unlocked)
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(vault)
        }
    }
}
