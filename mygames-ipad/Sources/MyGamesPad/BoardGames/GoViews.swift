// GoViews.swift — 囲碁の対局画面

import SwiftUI

struct GoGameView: View {
    @EnvironmentObject var game: GoGameState
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            if !game.hasStarted {
                GoSetupView()
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
                capturesBar
                GoBoardView()
                MoveRecordView(title: "記録", entries: game.moveList)
                    .frame(maxHeight: .infinity)
            }
            GoSidebarView()
                .frame(width: 300)
        }
        .padding(16)
    }

    /// 2人対戦: 設定・記録などは出さず、盤と「ゲーム終了」ボタンだけを
    /// 縦向き・横向きどちらでも画面いっぱいに表示する(2026-09-09、ユーザー指示
    /// 「ゲーム終了ボタンだけを表示。盤にかぶらない場所に表示」)。囲碁だけは
    /// 「パス」を上部バーに残す — 設定ではなく、2回連続で終局する正式な着手の
    /// 一つなので、2人対戦でも押せなくすると終局できなくなってしまうため。
    private var twoPlayerLayout: some View {
        GeometryReader { geo in
            let topBarHeight: CGFloat = 44
            let reserved: CGFloat = 38 + topBarHeight   // アゲハマ表示バー+余白+ゲーム終了バー
            let n = game.position.size
            // 盤の一辺 = spacing*(n-1) + margin*2、margin = spacing*0.7 なので
            // 一辺 = spacing*(n+0.4)
            let heightBudget = max(4, (geo.size.height - reserved) / (CGFloat(n) + 0.4))
            let widthBudget = max(4, geo.size.width / (CGFloat(n) + 0.4))
            let spacing = min(heightBudget, widthBudget)

            VStack(spacing: 8) {
                HStack {
                    Button("パス(2回続くと終局)") { game.humanPass() }
                        .disabled(!game.isHumanTurn)
                    Spacer()
                    EndGameOverlayButton { game.goToSetup() }
                }
                .frame(height: topBarHeight)

                Spacer(minLength: 0)
                capturesBar
                GoBoardView(spacingOverride: spacing)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var capturesBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(Color.black).frame(width: 18, height: 18)
                Text("\(game.opponentMode == .human ? "黒" : "あなた") · アゲハマ \(game.position.captures[Disc.black.rawValue])")
                    .font(.callout.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 18, height: 18)
                Text("\(game.opponentMode == .human ? "白" : "相手") · アゲハマ \(game.position.captures[Disc.white.rawValue])")
                    .font(.callout.bold())
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
            case .draw: return "持碁"
            case .humanWin, .humanLose: return "対局終了"
            case .ongoing: return ""
            }
        }
        switch game.result {
        case .humanWin: return "勝ち!"
        case .humanLose: return "負け"
        case .draw: return "持碁"
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

struct GoSetupView: View {
    @EnvironmentObject var game: GoGameState
    @State private var mode: OpponentMode = .ai

    var body: some View {
        GameSetupView(
            title: "囲碁",
            subtitle: "9路盤から始める囲碁。囲んで取って地を作ろう。",
            mode: $mode,
            extraSettings: {
                Picker("盤の広さ", selection: $game.boardSize) {
                    Text("9路盤(入門)").tag(9)
                    Text("13路盤").tag(13)
                }
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

struct GoBoardView: View {
    @EnvironmentObject var game: GoGameState

    var spacingOverride: CGFloat? = nil
    private var spacing: CGFloat { spacingOverride ?? (game.position.size <= 9 ? 52 : 38) }
    private var margin: CGFloat { spacing * 0.7 }

    var body: some View {
        let n = game.position.size
        let side = spacing * CGFloat(n - 1) + margin * 2
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Theme.boardWood)
            gridLines(n: n)
            starPoints(n: n)
            stones(n: n)
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

    private func starPoints(n: Int) -> some View {
        let coords: [Int] = n == 9 ? [2, 4, 6] : [3, 6, 9]
        return ForEach(coords, id: \.self) { r in
            ForEach(coords, id: \.self) { c in
                Circle()
                    .fill(Theme.gridLine)
                    .frame(width: 7, height: 7)
                    .position(point(r, c))
            }
        }
    }

    private func stones(n: Int) -> some View {
        ForEach(0..<n * n, id: \.self) { i in
            GoPointView(index: i, size: spacing * 0.94)
                .position(point(i / n, i % n))
        }
    }
}

struct GoPointView: View {
    @EnvironmentObject var game: GoGameState
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
        .onTapGesture { game.tapPoint(index) }
    }
}

// MARK: - サイドバー

struct GoSidebarView: View {
    @EnvironmentObject var game: GoGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameTopBar(title: "囲碁")

            GroupBox("対局") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(game.opponentMode == .human ? "2人対戦・\(game.boardSize)路盤" : "vs CPU(\(game.aiLevel.rawValue))・\(game.boardSize)路盤")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button { game.goToSetup() } label: { Label("設定を変える", systemImage: "slider.horizontal.3") }
                        .buttonStyle(.borderedProminent)
                }
                .padding(4)
            }

            GroupBox("操作") {
                VStack(alignment: .leading, spacing: 8) {
                    if game.opponentMode == .ai {
                        HStack {
                            Button("待った") { game.undo() }
                                .disabled(game.aiThinking)
                            Button("ヒント") { game.showHint() }
                                .disabled(!game.isHumanTurn)
                        }
                    }
                    Button("パス(2回続くと終局)") { game.humanPass() }
                        .disabled(!game.isHumanTurn)
                }
                .padding(4)
            }

            GroupBox("状況") {
                Text(game.message)
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .padding(4)
            }

            GroupBox("コツ") {
                Text("石は上下左右がすべて相手に囲まれると取られます。隅は少ない石で地を作れるので、序盤は隅から。終局前に、取れる相手の石は取り切ってからパスしましょう(数え上げは中国ルール: 石+囲った空点)。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(4)
            }

            SaveSlotsBox(game: .go,
                         onSave: { slot in
                             guard !game.aiThinking else { return false }
                             return SaveStore.save(game.makeSave(), game: .go, slot: slot)
                         },
                         onLoad: { slot in
                             guard let save = SaveStore.load(GoSave.self, game: .go, slot: slot) else { return false }
                             game.restore(from: save)
                             return true
                         })

            Spacer()
        }
    }
}
