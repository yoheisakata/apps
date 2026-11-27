import SwiftUI

let appVersion = "1.4.0"

@main
struct MyToolsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 980, height: 680)
    }
}
