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
    }
}
