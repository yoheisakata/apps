// MahjongViews.swift — 麻雀の対局画面

import SwiftUI

// MARK: - 牌の表示

struct MahjongTileView: View {
    let tile: Int
    var size: CGFloat = 40          // 高さ。幅は 0.72 倍
    var highlighted = false

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.12)
            .fill(Color.white)
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.12)
                    .stroke(highlighted ? Color.orange : Color.gray.opacity(0.6),
                            lineWidth: highlighted ? 3 : 1)
            )
            .overlay(
                Text(MahjongTiles.name(tile))
                    .font(.system(size: size * 0.34, weight: .bold))
                    .foregroundStyle(tileColor)
                    .minimumScaleFactor(0.5)
            )
            .frame(width: size * 0.72, height: size)
            .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
    }

    private var tileColor: Color {
        switch tile {
        case 0..<9:   return Color(red: 0.65, green: 0.1, blue: 0.1)   // 萬
        case 9..<18:  return Color(red: 0.1, green: 0.25, blue: 0.7)   // 筒
        case 18..<27: return Color(red: 0.05, green: 0.5, blue: 0.15)  // 索
        case 31:      return Color.gray                                // 白
        case 32:      return Color(red: 0.05, green: 0.5, blue: 0.15)  // 發
        case 33:      return Color(red: 0.75, green: 0.1, blue: 0.1)   // 中
        default:      return .black                                    // 風牌
        }
    }
}

/// 裏向きの牌
struct MahjongTileBackView: View {
    var size: CGFloat = 32

    var body: some View {
        RoundedRectangle(cornerRadius: size * 0.12)
            .fill(Color(red: 0.15, green: 0.35, blue: 0.55))
            .overlay(RoundedRectangle(cornerRadius: size * 0.12).stroke(Color.black.opacity(0.4), lineWidth: 1))
            .frame(width: size * 0.72, height: size)
    }
}

// MARK: - メイン画面

struct MahjongGameView: View {
    @EnvironmentObject var game: MahjongGameState
    @EnvironmentObject var router: Router

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            tableArea
                .frame(minWidth: 620)
            MahjongSidebarView()
                .frame(width: 300)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { resultOverlay }
    }

    private var tableArea: some View {
        VStack(spacing: 10) {
            // 上段: 3人の AI
            HStack(alignment: .top, spacing: 14) {
                ForEach(1...3, id: \.self) { p in
                    OpponentView(player: p)
                        .frame(maxWidth: .infinity)
                }
            }

            // 中央: 山の残り
            HStack(spacing: 10) {
                Image(systemName: "square.stack.3d.up")
                Text("山 残り \(game.wall.count) 枚")
                    .font(.callout.bold())
                if case .aiPlaying = game.phase {
                    ProgressView().controlSize(.small)
                }
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.othelloFelt.opacity(0.25)))

            // 自分の河
            VStack(alignment: .leading, spacing: 4) {
                Text("あなたの捨て牌")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                RiverView(tiles: game.rivers[0], tileSize: 30)
                    .frame(minHeight: 66, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))

            Spacer(minLength: 4)

            // 自分の手牌
            handArea
        }
    }

    private var handArea: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("あなたの手牌")
                    .font(.callout.bold())
                if game.activePlayer == 0 && game.result == .ongoing {
                    Text("あなたの番です")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.green.opacity(0.25)))
                }
                Spacer()
                actionButtons
            }
            HStack(spacing: 4) {
                ForEach(Array(game.hands[0].enumerated()), id: \.offset) { _, tile in
                    Button {
                        game.humanDiscard(tile)
                    } label: {
                        MahjongTileView(tile: tile, size: 56,
                                        highlighted: game.hintTile == tile)
                    }
                    .buttonStyle(.plain)
                    .disabled(!game.isHumanTurn)
                }
                if let drawn = game.drawnTile {
                    Spacer().frame(width: 14)
                    Button {
                        game.humanDiscard(drawn)
                    } label: {
                        MahjongTileView(tile: drawn, size: 56,
                                        highlighted: game.hintTile == drawn)
                    }
                    .buttonStyle(.plain)
                    .disabled(!game.isHumanTurn)
                }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.boardWood.opacity(0.35)))
    }

    @ViewBuilder
    private var actionButtons: some View {
        if case .ronOffer = game.phase {
            Button("ロン!") { game.acceptRon() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            Button("スルー") { game.declineRon() }
                .buttonStyle(.bordered)
        } else if game.isHumanTurn && game.canTsumo {
            Button("ツモ!") { game.humanTsumo() }
                .buttonStyle(.borderedProminent)
                .tint(.red)
        }
    }

    @ViewBuilder
    private var resultOverlay: some View {
        switch game.result {
        case .ongoing:
            EmptyView()
        case .win(let winner, let tsumo, let tile, let yaku, let points):
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text(winner == 0 ? "和了(あがり)!" : "\(MahjongGameState.seatNames[winner])の和了")
                        .font(.largeTitle.bold())
                        .foregroundStyle(winner == 0 ? Color.green : Color.red)
                    Text("\(tsumo ? "ツモ" : "ロン") · 和了牌 \(MahjongTiles.name(tile))")
                        .font(.callout)
                    // 和了した手牌
                    HStack(spacing: 3) {
                        ForEach(Array(game.hands[winner].enumerated()), id: \.offset) { _, t in
                            MahjongTileView(tile: t, size: 38)
                        }
                    }
                    VStack(spacing: 3) {
                        ForEach(yaku, id: \.self) { y in
                            Text(y).font(.callout)
                        }
                        Text(points)
                            .font(.callout.bold())
                            .padding(.top, 4)
                    }
                    HStack(spacing: 12) {
                        Button("次の局へ") { game.newGame() }
                            .buttonStyle(.borderedProminent)
                        Button("メニューへ") { router.backToMenu() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(radius: 20)
            }
        case .exhaustiveDraw(let tenpai):
            ZStack {
                Color.black.opacity(0.35).ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("流局")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.secondary)
                    Text(tenpai.isEmpty
                         ? "山が尽きました。聴牌者なしです。"
                         : "山が尽きました。聴牌: \(tenpai.map { MahjongGameState.seatNames[$0] }.joined(separator: "、"))")
                        .font(.callout)
                    HStack(spacing: 12) {
                        Button("次の局へ") { game.newGame() }
                            .buttonStyle(.borderedProminent)
                        Button("メニューへ") { router.backToMenu() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(radius: 20)
            }
        }
    }
}

// MARK: - 相手の表示

struct OpponentView: View {
    @EnvironmentObject var game: MahjongGameState
    let player: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(MahjongGameState.seatNames[player])
                    .font(.caption.bold())
                if game.activePlayer == player && game.result == .ongoing {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                }
            }
            // 裏向きの手牌
            HStack(spacing: 2) {
                ForEach(0..<min(game.hands[player].count, 13), id: \.self) { _ in
                    MahjongTileBackView(size: 24)
                }
            }
            Text("捨て牌")
                .font(.caption2)
                .foregroundStyle(.secondary)
            RiverView(tiles: game.rivers[player], tileSize: 24)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
    }
}

/// 河(捨て牌)の表示
struct RiverView: View {
    let tiles: [Int]
    let tileSize: CGFloat

    private let perRow = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(0..<max(1, (tiles.count + perRow - 1) / perRow), id: \.self) { row in
                HStack(spacing: 2) {
                    ForEach(Array(tiles.dropFirst(row * perRow).prefix(perRow).enumerated()),
                            id: \.offset) { _, t in
                        MahjongTileView(tile: t, size: tileSize)
                    }
                }
            }
        }
    }
}

// MARK: - サイドバー

struct MahjongSidebarView: View {
    @EnvironmentObject var game: MahjongGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameTopBar(title: "麻雀")

            GroupBox("対局") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("相手の強さ", selection: $game.aiLevel) {
                        ForEach(Difficulty.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    HStack {
                        Button("新しい局") { game.newGame() }
                            .buttonStyle(.borderedProminent)
                        Button("ヒント") { game.showHint() }
                            .disabled(!game.isHumanTurn)
                    }
                }
                .padding(4)
            }

            GroupBox("状況") {
                Text(game.message)
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .topLeading)
                    .padding(4)
            }

            GroupBox("入門ルール") {
                Text("""
                手牌13枚+ツモ1枚から要らない牌を1枚捨てるのを繰り返し、「3枚1組(同じ牌3枚、または連番3枚)×4 + 同じ牌2枚」を先に完成させたら和了です。
                自分でツモった牌で完成すれば「ツモ」、相手の捨て牌で完成すれば「ロン」。
                この入門版では鳴き・リーチ・ドラ・フリテンを省略しています。役がなくても和了できます(役は参考表示)。
                """)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(4)
            }

            SaveSlotsBox(game: .mahjong,
                         onSave: { slot in
                             guard let save = game.makeSave() else { return false }
                             return SaveStore.save(save, game: .mahjong, slot: slot)
                         },
                         onLoad: { slot in
                             guard let save = SaveStore.load(MahjongSave.self, game: .mahjong, slot: slot) else { return false }
                             game.restore(from: save)
                             return true
                         })

            Spacer()
        }
    }
}
