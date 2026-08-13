// BoardGamesRootView.swift — 将棋・チェス・オセロ等のボードゲーム集(旧 boardgames アプリ)。
// MyGames の「ボードゲーム」タブから表示される。

import SwiftUI
import AppKit

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
            case .game(.mahjong):
                MahjongGameView()
            }
        }
        .frame(minWidth: 880, minHeight: 660)
    }
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
    @EnvironmentObject var mahjong: MahjongGameState

    /// 一度でも開いた(=対局が始まっている)ゲーム。メニューに戻って再クリックしても続きから
    @State private var startedGames: Set<GameKind> = []

    private let columns = [GridItem(.fixed(180), spacing: 28),
                           GridItem(.fixed(180), spacing: 28),
                           GridItem(.fixed(180), spacing: 28),
                           GridItem(.fixed(180), spacing: 28)]

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                VStack(spacing: 4) {
                    Text("ボードゲーム")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("アイコンをクリックすると始まります。続きの読み込みは各ゲーム内の「途中保存」からどうぞ。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 28)

                LazyVGrid(columns: columns, alignment: .center, spacing: 28) {
                    ForEach(GameKind.allCases) { kind in
                        GameIconButton(kind: kind) { open(kind) }
                    }
                }

                Spacer(minLength: 24)
            }
            .padding(24)
            .frame(maxWidth: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func open(_ kind: GameKind) {
        // 初回だけ新規対局を始める。以降は続きから(新規は各ゲーム内のボタンで)
        if !startedGames.contains(kind) {
            switch kind {
            case .shogi:   shogi.newGame()
            case .chess:   chess.newGame()
            case .othello: othello.newGame()
            case .go:      go.newGame()
            case .diamond: diamond.newGame()
            case .gomoku:  gomoku.newGame()
            case .mahjong: mahjong.newGame()
            }
            startedGames.insert(kind)
        }
        router.open(kind)
    }
}

// MARK: - ゲームアイコン

struct GameIconButton: View {
    let kind: GameKind
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 22)
                        .fill(emblemBackground)
                        .frame(width: 96, height: 96)
                        .shadow(color: .black.opacity(hovering ? 0.35 : 0.15),
                                radius: hovering ? 8 : 3, y: 2)
                    if kind == .othello {
                        OthelloEmblem()
                    } else {
                        Text(kind.emblem)
                            .font(.system(size: 50, weight: .bold, design: .serif))
                            .foregroundStyle(emblemForeground)
                    }
                }
                .scaleEffect(hovering ? 1.08 : 1.0)

                Text(kind.displayName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(kind.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 28)
            }
            .frame(width: 170)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { over in
            withAnimation(.easeOut(duration: 0.15)) { hovering = over }
        }
    }

    private var emblemBackground: Color {
        switch kind {
        case .shogi:   return Theme.boardWood
        case .chess:   return Theme.chessDark
        case .othello: return Theme.othelloFelt
        case .go:      return Theme.boardWood
        case .diamond: return Color(red: 0.85, green: 0.2, blue: 0.25)
        case .gomoku:  return Theme.boardWood
        case .mahjong: return .white
        }
    }

    private var emblemForeground: Color {
        switch kind {
        case .shogi:   return .black
        case .chess:   return .white
        case .othello: return .black
        case .go:      return .black
        case .diamond: return .white
        case .gomoku:  return .black
        case .mahjong: return Color(red: 0.75, green: 0.1, blue: 0.1)
        }
    }
}

/// オセロのアイコン絵柄: 2行2列(黒白/白黒)の駒を市松に並べる
struct OthelloEmblem: View {
    private let rows: [[Color]] = [[.black, .white], [.white, .black]]

    var body: some View {
        VStack(spacing: 6) {
            ForEach(0..<2) { row in
                HStack(spacing: 6) {
                    ForEach(0..<2) { col in
                        Circle()
                            .fill(rows[row][col])
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
                            .shadow(color: .black.opacity(0.3), radius: 1, y: 1)
                    }
                }
            }
        }
    }
}
