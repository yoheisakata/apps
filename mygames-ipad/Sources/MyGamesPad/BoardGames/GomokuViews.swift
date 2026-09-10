// GomokuViews.swift — 五目並べの対局画面

import SwiftUI

struct GomokuGameView: View {
    @EnvironmentObject var game: GomokuGameState
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            if !game.hasStarted {
                GomokuSetupView()
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
                GomokuBoardView()
                MoveRecordView(title: "記録", entries: game.moveList)
                    .frame(maxHeight: .infinity)
            }
            GomokuSidebarView()
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
            let n = GomokuPosition.size
            // 盤の一辺 = spacing*(n-1) + margin*2、margin = spacing*0.7 なので
            // 一辺 = spacing*(n-1+1.4) = spacing*(n+0.4)
            let heightBudget = max(4, (geo.size.height - reserved) / (CGFloat(n) + 0.4))
            let widthBudget = max(4, geo.size.width / (CGFloat(n) + 0.4))
            let spacing = min(heightBudget, widthBudget)

            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    EndGameOverlayButton { game.goToSetup() }
                }
                .frame(height: topBarHeight)

                Spacer(minLength: 0)
                statusBar
                GomokuBoardView(spacing: spacing)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(Color.black).frame(width: 18, height: 18)
                Text(game.opponentMode == .human ? "黒" : "あなた(黒)").font(.callout.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 18, height: 18)
                Text(game.opponentMode == .human ? "白" : "相手(白)").font(.callout.bold())
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
                    Text(resultTitle)
                        .font(.largeTitle.bold())
                        .foregroundStyle(resultColor)
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

    private var resultTitle: String {
        if game.opponentMode == .human {
            switch game.result {
            case .draw: return "引き分け"
            case .humanWin, .humanLose: return "対局終了"
            case .ongoing: return ""
            }
        }
        switch game.result {
        case .humanWin: return "勝ち!"
        case .humanLose: return "負け"
        case .draw: return "引き分け"
        case .ongoing: return ""
        }
    }

    private var resultColor: Color {
        if game.opponentMode == .human { return .primary }
        switch game.result {
        case .humanWin: return .green
        case .humanLose: return .red
        default: return .secondary
        }
    }

    private var resultText: String {
        switch game.result {
        case .humanWin(let t), .humanLose(let t), .draw(let t): return t
        case .ongoing: return ""
        }
    }
}

// MARK: - セットアップ画面

struct GomokuSetupView: View {
    @EnvironmentObject var game: GomokuGameState
    @State private var mode: OpponentMode = .ai

    var body: some View {
        GameSetupView(
            title: "五目並べ",
            subtitle: "先に5つ並べたら勝ち。いちばん手軽な入門ゲームです。",
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

struct GomokuBoardView: View {
    @EnvironmentObject var game: GomokuGameState

    var spacing: CGFloat = 34
    private var margin: CGFloat { spacing * 0.7 }

    var body: some View {
        let n = GomokuPosition.size
        let side = spacing * CGFloat(n - 1) + margin * 2
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.boardWood)
            gridLines(n: n)
            ForEach(0..<n * n, id: \.self) { i in
                GomokuPointView(index: i, size: spacing * 0.92)
                    .position(point(i / n, i % n))
            }
        }
        .frame(width: side, height: side)
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.gridLine, lineWidth: 2))
    }

    private func point(_ r: Int, _ c: Int) -> CGPoint {
        CGPoint(x: margin + CGFloat(c) * spacing,
                y: margin + CGFloat(r) * spacing)
    }

    private func gridLines(n: Int) -> some View {
        Path { p in
            for i in 0..<n {
                p.move(to: point(i, 0))
                p.addLine(to: point(i, n - 1))
                p.move(to: point(0, i))
                p.addLine(to: point(n - 1, i))
            }
        }
        .stroke(Theme.gridLine.opacity(0.8), lineWidth: 1)
    }
}

struct GomokuPointView: View {
    @EnvironmentObject var game: GomokuGameState
    let index: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            Color.clear
            if let disc = game.position.board[index] {
                Circle()
                    .fill(disc == .black ? Color.black : Color.white)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                if game.lastMove == index {
                    Circle()
                        .stroke(disc == .black ? Color.white : Color.black, lineWidth: 2)
                        .frame(width: size * 0.45, height: size * 0.45)
                }
            } else if game.hintMove == index {
                Circle()
                    .fill(Theme.hintBg)
                    .frame(width: size * 0.5, height: size * 0.5)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .onTapGesture { game.tapCell(index) }
    }
}

// MARK: - サイドバー

struct GomokuSidebarView: View {
    @EnvironmentObject var game: GomokuGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameTopBar(title: "五目並べ")

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

            GroupBox("コツ") {
                Text("両端が空いた3(活三)を作ると、次に両端どちらでも4にできるので強力です。逆に相手の活三は見つけたらすぐ止めること。攻めと守りの分岐点を見極めるのが上達のコツです。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(4)
            }

            SaveSlotsBox(game: .gomoku,
                         onSave: { slot in
                             guard !game.aiThinking else { return false }
                             return SaveStore.save(game.makeSave(), game: .gomoku, slot: slot)
                         },
                         onLoad: { slot in
                             guard let save = SaveStore.load(GomokuSave.self, game: .gomoku, slot: slot) else { return false }
                             game.restore(from: save)
                             return true
                         })

            Spacer()
        }
    }
}
