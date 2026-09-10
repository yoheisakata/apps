// BoardGamesRootView.swift — 将棋・チェス・オセロ等のボードゲーム集(旧 boardgames アプリ)。
// MyGames の「ボードゲーム」タブから表示される。

import SwiftUI

// MARK: - 画面切り替え

struct BoardGamesRootView: View {
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            switch router.screen {
            case .menu:
                MenuView()
            case .game(.shogi):
                ShogiGameView()
            case .game(.chess):
                ChessGameView()
            case .game(.othello):
                OthelloGameView()
            case .game(.go):
                GoGameView()
            case .game(.diamond):
                DiamondGameView()
            case .game(.gomoku):
                GomokuGameView()
            case .game(.checkers):
                CheckersGameView()
            case .game(.connectFour):
                ConnectFourGameView()
            case .cardGames(let id):
                ZStack(alignment: .topLeading) {
                    LauncherTheme.background.ignoresSafeArea()
                    CardGamesWebView(gameID: id)
                    Button {
                        router.backToMenu()
                    } label: {
                        Label("その他のゲーム", systemImage: "chevron.left")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(LauncherTheme.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                    }
                    .padding(12)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ランチャー配色
//
// アイコンのグラデーションはトランプ側(pwa/cardgames)の:root CSS変数の配色を
// そのまま流用している。背景は元々トランプ側に合わせた深緑グラデーションに
// していたが、2026-09-08にユーザー指示で黒に変更し、2026-09-09にユーザー指示で
// セピア(暖色の焦げ茶)に変更した。

enum LauncherTheme {
    static let background = Color(red: 0x3a / 255.0, green: 0x2c / 255.0, blue: 0x1e / 255.0)
    static let text = Color(red: 0xea / 255.0, green: 0xf5 / 255.0, blue: 0xec / 255.0)
    static let sub = Color(red: 0x8f / 255.0, green: 0xbf / 255.0, blue: 0xa0 / 255.0)
    static let accent = Color(red: 0xf2 / 255.0, green: 0xc1 / 255.0, blue: 0x4e / 255.0)
    static let accent2 = Color(red: 0xe0 / 255.0, green: 0xa9 / 255.0, blue: 0x2e / 255.0)

    static let titleGradient = LinearGradient(
        colors: [Color(red: 0xf7 / 255.0, green: 0xdd / 255.0, blue: 0x8f / 255.0), accent],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// アイコンの背景グラデーション(開始色, 終了色, 影の色)。トランプ側の
    /// 8ゲーム分のグラデーションをそのまま`GameKind.allCases`の並び順に流用。
    static let iconGradients: [(Color, Color, Color)] = [
        (Color(red: 0x3b / 255.0, green: 0x07 / 255.0, blue: 0x64 / 255.0),
         Color(red: 0x93 / 255.0, green: 0x33 / 255.0, blue: 0xea / 255.0),
         Color(red: 0x93 / 255.0, green: 0x33 / 255.0, blue: 0xea / 255.0)),          // shogi(神経衰弱の紫)
        (Color(red: 0x1c / 255.0, green: 0x1c / 255.0, blue: 0x1c / 255.0),
         Color(red: 0xc0 / 255.0, green: 0x39 / 255.0, blue: 0x2b / 255.0),
         Color(red: 0xc0 / 255.0, green: 0x39 / 255.0, blue: 0x2b / 255.0)),          // chess(ババ抜きの黒赤)
        (Color(red: 0xb4 / 255.0, green: 0x53 / 255.0, blue: 0x09 / 255.0),
         Color(red: 0xf5 / 255.0, green: 0x9e / 255.0, blue: 0x0b / 255.0),
         Color(red: 0xf5 / 255.0, green: 0x9e / 255.0, blue: 0x0b / 255.0)),          // othello(スピードの橙)
        (Color(red: 0x7a / 255.0, green: 0x5a / 255.0, blue: 0x0f / 255.0),
         accent,
         accent),                                                                     // go(大富豪の金)
        (Color(red: 0x0f / 255.0, green: 0x3d / 255.0, blue: 0x5c / 255.0),
         Color(red: 0x3b / 255.0, green: 0x82 / 255.0, blue: 0xf6 / 255.0),
         Color(red: 0x3b / 255.0, green: 0x82 / 255.0, blue: 0xf6 / 255.0)),          // diamond(７並べの青)
        (Color(red: 0x0f / 255.0, green: 0x5c / 255.0, blue: 0x33 / 255.0),
         Color(red: 0x22 / 255.0, green: 0xc5 / 255.0, blue: 0x5e / 255.0),
         Color(red: 0x22 / 255.0, green: 0xc5 / 255.0, blue: 0x5e / 255.0)),          // gomoku(21の緑)
        (Color(red: 0x0f / 255.0, green: 0x17 / 255.0, blue: 0x2a / 255.0),
         Color(red: 0x47 / 255.0, green: 0x55 / 255.0, blue: 0x69 / 255.0),
         Color(red: 0x47 / 255.0, green: 0x55 / 255.0, blue: 0x69 / 255.0)),          // checkers(ポーカーのスレート)
        (Color(red: 0x3b / 255.0, green: 0x0a / 255.0, blue: 0x0a / 255.0),
         Color(red: 0xc0 / 255.0, green: 0x39 / 255.0, blue: 0x2b / 255.0),
         Color(red: 0xc0 / 255.0, green: 0x39 / 255.0, blue: 0x2b / 255.0)),          // connectFour(ブラックジャックの濃赤)
    ]
}

// MARK: - メインメニュー

struct MenuView: View {
    @EnvironmentObject var router: Router
    @EnvironmentObject var shogi: ShogiGameState
    @EnvironmentObject var chess: ChessGameState
    @EnvironmentObject var othello: OthelloGameState
    @EnvironmentObject var go: GoGameState
    @EnvironmentObject var diamond: DiamondGameState
    @EnvironmentObject var gomoku: GomokuGameState

    private let columns = [GridItem(.fixed(150), spacing: 20),
                           GridItem(.fixed(150), spacing: 20),
                           GridItem(.fixed(150), spacing: 20),
                           GridItem(.fixed(150), spacing: 20)]

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                Text("ゲーム")
                    .font(.system(size: 28, weight: .heavy, design: .rounded))
                    .foregroundStyle(LauncherTheme.titleGradient)
                    .padding(.top, 20)
                Text("遊びたいゲームを選んでね")
                    .font(.system(size: 13))
                    .foregroundStyle(LauncherTheme.sub)
                    .padding(.bottom, 8)

                // ボードゲーム8種+トランプの8種、全16個を同じグリッドに並べる
                // (2026-09-09、ユーザー指示「トランプの各ゲームをトップページに
                // おいて」— 当初はトランプをまとめて1個のアイコンにしていたが、
                // それだと結局WKWebView側のホーム画面を経由する必要があったため、
                // トランプの個別ゲームも直接タップできるアイコンにした)。トランプの
                // 各アイコンはタップしたときだけWKWebViewを読み込み、goSetup()で
                // そのゲームのセットアップ画面へ直行する(`CardGamesWebView`参照)。
                LazyVGrid(columns: columns, alignment: .center, spacing: 18) {
                    ForEach(GameKind.allCases) { kind in
                        GameIconButton(kind: kind) { open(kind) }
                    }
                    ForEach(CardGameEntry.all) { entry in
                        let gradient = LauncherTheme.iconGradients[entry.colorIndex % LauncherTheme.iconGradients.count]
                        LauncherIconTile(title: entry.title, gradient: gradient,
                                         action: { router.openCardGames(entry.id) }) {
                            Text(entry.emblem).font(.system(size: 34))
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .background(LauncherTheme.background)
    }

    private func open(_ kind: GameKind) {
        router.open(kind)
    }
}

// MARK: - ゲームアイコン

/// ランチャーのアイコンタイル(角丸グラデーション+絵柄+タイトル)の共通部品。
/// ボードゲームのアイコン(`GameIconButton`)とトランプのアイコンの両方で使う。
struct LauncherIconTile<Emblem: View>: View {
    let title: String
    let gradient: (Color, Color, Color)
    let action: () -> Void
    @ViewBuilder let emblem: () -> Emblem

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(LinearGradient(colors: [gradient.0, gradient.1],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 72, height: 72)
                        .shadow(color: gradient.2.opacity(0.45), radius: 8, y: 4)
                    emblem()
                }

                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LauncherTheme.text.opacity(0.8))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: 76)
            }
            .frame(width: 150)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct GameIconButton: View {
    let kind: GameKind
    let action: () -> Void

    var body: some View {
        LauncherIconTile(title: kind.displayName, gradient: gradient, action: action) {
            if kind == .othello {
                OthelloEmblem()
            } else {
                Text(kind.emblem)
                    .font(.system(size: 34, weight: .bold, design: .serif))
                    .foregroundStyle(.white)
            }
        }
    }

    private var gradient: (Color, Color, Color) {
        let index = GameKind.allCases.firstIndex(of: kind) ?? 0
        return LauncherTheme.iconGradients[index % LauncherTheme.iconGradients.count]
    }
}

/// オセロのアイコン絵柄: 2行2列(黒白/白黒)の駒を市松に並べる
struct OthelloEmblem: View {
    private let rows: [[Color]] = [[.black, .white], [.white, .black]]

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<2) { row in
                HStack(spacing: 4) {
                    ForEach(0..<2) { col in
                        Circle()
                            .fill(rows[row][col])
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    }
                }
            }
        }
    }
}
