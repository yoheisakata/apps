import SwiftUI

let appVersion = "1.2.0"

@main
struct OrganizerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 680)
    }
}
