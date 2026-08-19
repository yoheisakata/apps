import SwiftUI

let appVersion = "1.2.1"

@main
struct MyOrganizerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 680)
    }
}
