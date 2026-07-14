import SwiftUI

let appVersion = "1.0.0"

@main
struct OmoideApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}
