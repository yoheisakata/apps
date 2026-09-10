// DiamondViews.swift — ダイヤモンドゲームの対局画面

import SwiftUI

struct DiamondGameView: View {
    @EnvironmentObject var game: DiamondGameState
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            if !game.hasStarted {
                DiamondSetupView()
            } else if game.opponentMode == .human {
                twoPlayerLayout
            } else {
                aiLayout
            }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay { resultOverlay }
    }

    private var aiLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                statusBar
                DiamondBoardView()
                MoveRecordView(title: "記録", entries: game.moveList)
                    .frame(maxHeight: .infinity)
            }
            DiamondSidebarView()
                .frame(width: 300)
        }
        .padding(16)
    }

    /// 2人対戦: 設定・記録などは出さず、盤と「ゲーム終了」ボタンだけを
    /// 縦向き・横向きどちらでも画面いっぱいに表示する(2026-09-09、ユーザー指示
    /// 「ゲーム終了ボタンだけを表示。盤にかぶらない場所に表示」)。
    private var twoPlayerLayout: some View {
        GeometryReader { geo in
            let topBarHeight: CGFloat = 44
            let reserved: CGFloat = 38 + topBarHeight   // 状況バー+余白+ゲーム終了バー
            // 標準サイズ(scale=1)での盤の幅564・高さ548から逆算してscaleを決める
            let widthBudget = max(0.2, geo.size.width / 564)
            let heightBudget = max(0.2, (geo.size.height - reserved) / 548)
            let scale = min(widthBudget, heightBudget)

            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    EndGameOverlayButton { game.goToSetup() }
                }
                .frame(height: topBarHeight)

                Spacer(minLength: 0)
                statusBar
                DiamondBoardView(scale: scale)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(Color.red).frame(width: 18, height: 18)
                Text(game.opponentMode == .human ? "赤(下から上へ)" : "あなた(赤・下から上へ)").font(.callout.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(Color.yellow)
                    .overlay(Circle().stroke(Color.orange, lineWidth: 1))
                    .frame(width: 18, height: 18)
                Text(game.opponentMode == .human ? "黄(上から下へ)" : "相手(黄)").font(.callout.bold())
            }
            Spacer()
            if game.aiThinking {
                ProgressView().controlSize(.small)
                Text("考え中…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 30)
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if case .ongoing = game.result {
            EmptyView()
        } else {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(game.opponentMode == .human ? "対局終了" : (isWin ? "勝ち!" : "負け"))
                        .font(.largeTitle.bold())
                        .foregroundStyle(game.opponentMode == .human ? Color.primary : (isWin ? Color.green : Color.red))
                    Text(resultText).font(.callout).frame(maxWidth: 380)
                    HStack(spacing: 12) {
                        Button("もう一局") { game.newGame() }
                            .buttonStyle(.borderedProminent)
                        Button("待ったで続ける") { game.undo() }
                            .buttonStyle(.bordered)
                        Button("メニューへ") { router.backToMenu() }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(28)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .systemBackground)))
                .shadow(radius: 20)
            }
        }
    }

    private var isWin: Bool {
        if case .humanWin = game.result { return true }
        return false
    }

    private var resultText: String {
        switch game.result {
        case .humanWin(let t), .humanLose(let t): return t
        case .ongoing: return ""
        }
    }
}

// MARK: - セットアップ画面

struct DiamondSetupView: View {
    @EnvironmentObject var game: DiamondGameState
    @State private var mode: OpponentMode = .ai

    var body: some View {
        GameSetupView(
            title: "ダイヤモンドゲーム",
            subtitle: "跳び越しの連鎖で向かい側を目指すレースゲームです。",
            mode: $mode,
            extraSettings: {
                Picker("相手の強さ", selection: $game.aiLevel) {
                    ForEach(Difficulty.allCases) { d in
                        Text(d.rawValue).tag(d)
                    }
                }
            },
            onStart: {
                game.opponentMode = mode
                game.newGame()
                #if os(iOS)
                OrientationLock.apply(mode == .human ? .portrait : .landscape)
                #endif
            }
        )
        .onAppear { mode = game.opponentMode }
    }
}

// MARK: - 盤

struct DiamondBoardView: View {
    @EnvironmentObject var game: DiamondGameState

    /// 標準サイズ(unitX=16/unitY=31/margin=26/コマ27)に対する倍率。2人対戦の
    /// フルスクリーンレイアウトで画面に合わせて盤全体を拡大縮小するために使う
    /// (2026-09-09、ユーザー指示)。
    var scale: CGFloat = 1.0
    private var unitX: CGFloat { 16 * scale }     // x が 1 増えるごとの横幅(隣接マスは x±2)
    private var unitY: CGFloat { 31 * scale }
    private var margin: CGFloat { 26 * scale }
    private var cellSize: CGFloat { 27 * scale }

    private var cells: [DPoint] {
        DiamondPosition.allCells.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    }

    var body: some View {
        let width = unitX * 32 + margin * 2       // x は -16〜16
        let height = unitY * 16 + margin * 2
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.boardWood.opacity(0.55))
            ForEach(cells, id: \.self) { p in
                DiamondCellView(point: p, size: cellSize)
                    .position(screenPoint(p, width: width))
            }
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.gridLine.opacity(0.6), lineWidth: 2))
    }

    private func screenPoint(_ p: DPoint, width: CGFloat) -> CGPoint {
        CGPoint(x: width / 2 + CGFloat(p.x) * unitX,
                y: margin + CGFloat(p.y) * unitY)
    }
}

struct DiamondCellView: View {
    @EnvironmentObject var game: DiamondGameState
    let point: DPoint
    let size: CGFloat

    var body: some View {
        ZStack {
            // 穴(マス)
            Circle()
                .fill(holeColor)
                .overlay(Circle().stroke(Theme.gridLine.opacity(0.35), lineWidth: 1))
            // コマ
            if let player = game.position.occupant(point) {
                Circle()
                    .fill(player == .south ? Color.red : Color.yellow)
                    .overlay(Circle().stroke(strokeColor(player), lineWidth: game.selected == point ? 3 : 1))
                    .padding(3)
                    .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture { game.tapCell(point) }
    }

    private func strokeColor(_ player: DiamondPlayer) -> Color {
        if game.selected == point { return .blue }
        return player == .south ? Color(red: 0.5, green: 0, blue: 0) : .orange
    }

    private var holeColor: Color {
        if game.legalTargets.contains(point) {
            return Theme.target
        }
        if let hint = game.hintMove, hint.from == point || hint.to == point {
            return Theme.hintBg
        }
        if let last = game.lastMove, last.from == point || last.to == point {
            return Theme.lastMoveBg
        }
        // 陣地をうっすら色分け
        if DiamondPosition.northHome.contains(point) { return Color.yellow.opacity(0.18) }
        if DiamondPosition.southHome.contains(point) { return Color.red.opacity(0.15) }
        return Color.black.opacity(0.07)
    }
}

// MARK: - サイドバー

struct DiamondSidebarView: View {
    @EnvironmentObject var game: DiamondGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameTopBar(title: "ダイヤモンドゲーム")

            GroupBox("対局") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(game.opponentMode == .human ? "2人対戦" : "vs CPU(\(game.aiLevel.rawValue))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button { game.goToSetup() } label: { Label("設定を変える", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.borderedProminent)
                }
                .padding(4)
            }

            if game.opponentMode == .ai {
                GroupBox("操作") {
                    HStack {
                        Button("待った") { game.undo() }
                            .disabled(game.aiThinking)
                        Button("ヒント") { game.showHint() }
                            .disabled(!game.isHumanTurn)
                    }
                    .padding(4)
                }
            }

            GroupBox("状況") {
                Text(game.message)
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .padding(4)
            }

            GroupBox("ルールとコツ") {
                Text("コマは隣の空きマスへ1歩、または隣のコマを跳び越して進めます。跳び越しは続けて何回でも(緑のマスが行き先)。自分のコマ10個を先に向かい側の三角形へ全部入れたら勝ち。コマを数珠つなぎに並べて「ジャンプの道」を作るのが最大のコツです。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(4)
            }

            SaveSlotsBox(game: .diamond,
                         onSave: { slot in
                             guard !game.aiThinking else { return false }
                             return SaveStore.save(game.makeSave(), game: .diamond, slot: slot)
                         },
                         onLoad: { slot in
                             guard let save = SaveStore.load(DiamondSave.self, game: .diamond, slot: slot) else { return false }
                             game.restore(from: save)
                             return true
                         })

            Spacer()
        }
    }
}
