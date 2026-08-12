import SwiftUI

let appVersion = "1.0.0"

@main
struct MyTubeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 1180, height: 760)
    }
}
