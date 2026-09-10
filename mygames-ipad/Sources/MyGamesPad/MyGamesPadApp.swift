import SwiftUI

@main
struct MyGamesPadApp: App {
    @UIApplicationDelegateAdaptor(OrientationAppDelegate.self) var appDelegate
    @StateObject private var router = Router()
    @StateObject private var shogi = ShogiGameState()
    @StateObject private var chess = ChessGameState()
    @StateObject private var othello = OthelloGameState()
    @StateObject private var go = GoGameState()
    @StateObject private var diamond = DiamondGameState()
    @StateObject private var gomoku = GomokuGameState()
    @StateObject private var checkers = CheckersGameState()
    @StateObject private var connectFour = ConnectFourGameState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(router)
                .environmentObject(shogi)
                .environmentObject(chess)
                .environmentObject(othello)
                .environmentObject(go)
                .environmentObject(diamond)
                .environmentObject(gomoku)
                .environmentObject(checkers)
                .environmentObject(connectFour)
        }
    }
}
