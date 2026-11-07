import SwiftUI

let appVersion = "0.1.0"

@main
struct MyChatApp: App {
    @StateObject private var store = ChatStore()

    var body: some Scene {
        WindowGroup("MyChat") {
            ContentView()
                .environmentObject(store)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("新しいチャット") { store.newConversation() }
                    .keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView()
        }
    }
}
