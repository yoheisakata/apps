// ConnectFourViews.swift — コネクトフォーの対局画面

import SwiftUI

struct ConnectFourGameView: View {
    @EnvironmentObject var game: ConnectFourGameState
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            if !game.hasStarted {
                ConnectFourSetupView()
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
                ConnectFourBoardView()
                MoveRecordView(title: "記録", entries: game.moveList)
                    .frame(maxHeight: .infinity)
            }
            ConnectFourSidebarView()
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
            // 幅 = spacing*6 + margin*2、高さ = spacing*5 + margin*2、margin = spacing*0.55 なので
            // 幅 = spacing*7.1、高さ = spacing*6.1
            let heightBudget = max(4, (geo.size.height - reserved) / 6.1)
            let widthBudget = max(4, geo.size.width / 7.1)
            let spacing = min(heightBudget, widthBudget)

            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    EndGameOverlayButton { game.goToSetup() }
                }
                .frame(height: topBarHeight)

                Spacer(minLength: 0)
                statusBar
                ConnectFourBoardView(spacing: spacing)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var statusBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(Theme.connectFourBlue).frame(width: 18, height: 18)
                Text(game.opponentMode == .human ? "青" : "あなた(青)").font(.callout.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(Theme.connectFourYellow)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 18, height: 18)
                Text(game.opponentMode == .human ? "黄" : "相手(黄)").font(.callout.bold())
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

struct ConnectFourSetupView: View {
    @EnvironmentObject var game: ConnectFourGameState
    @State private var mode: OpponentMode = .ai

    var body: some View {
        GameSetupView(
            title: "コネクトフォー",
            subtitle: "列に落として縦・横・斜めに4つ並べたら勝ちです。",
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

struct ConnectFourBoardView: View {
    @EnvironmentObject var game: ConnectFourGameState

    var spacing: CGFloat = 52
    private var margin: CGFloat { spacing * 0.55 }

    var body: some View {
        let cols = ConnectFourPosition.cols, rows = ConnectFourPosition.rows
        let width = spacing * CGFloat(cols - 1) + margin * 2
        let height = spacing * CGFloat(rows - 1) + margin * 2
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Theme.othelloFelt.opacity(0.85))
            ForEach(0..<cols, id: \.self) { c in
                ConnectFourColumnOverlay(col: c, width: spacing, height: height)
                    .position(x: margin + CGFloat(c) * spacing, y: height / 2)
            }
            ForEach(0..<(rows * cols), id: \.self) { i in
                ConnectFourSlotView(index: i, size: spacing * 0.82)
                    .position(x: margin + CGFloat(i % cols) * spacing,
                              y: margin + CGFloat(i / cols) * spacing)
            }
        }
        .frame(width: width, height: height)
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.black.opacity(0.7), lineWidth: 2))
    }
}

/// 列全体をタップ範囲にする透明なオーバーレイ(どの段をタップしても同じ列に落ちる)
struct ConnectFourColumnOverlay: View {
    @EnvironmentObject var game: ConnectFourGameState
    let col: Int
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(highlight)
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onTapGesture { game.tapColumn(col) }
    }

    private var highlight: Color {
        if game.hintColumn == col { return Theme.hintBg.opacity(0.3) }
        return Color.white.opacity(0.001)   // ヒットテストのためほぼ透明だが0にはしない
    }
}

struct ConnectFourSlotView: View {
    @EnvironmentObject var game: ConnectFourGameState
    let index: Int
    let size: CGFloat

    var body: some View {
        ZStack {
            // ダークモードでは.systemBackgroundがほぼ黒になり、黒の駒が背景に
            // 埋もれて見えなくなるため、明暗モードに関わらず固定の明るい色にする
            Circle().fill(Color(white: 0.95))
            if let disc = game.position.board[index] {
                Circle()
                    .fill(disc == .black ? Theme.connectFourBlue : Theme.connectFourYellow)
                    .overlay(Circle().stroke(Color.black.opacity(0.4), lineWidth: 1))
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
                if game.lastMove == index {
                    Circle()
                        .stroke(Color.black, lineWidth: 2)
                        .padding(3)
                }
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

// MARK: - サイドバー

struct ConnectFourSidebarView: View {
    @EnvironmentObject var game: ConnectFourGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameTopBar(title: "コネクトフォー")

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
                Text("中央の列を先に取ると4方向すべてで有利になります。相手が3つ並んだら、たとえ攻めの手が見えていてもまず止めましょう。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(4)
            }

            SaveSlotsBox(game: .connectFour,
                         onSave: { slot in
                             guard !game.aiThinking else { return false }
                             return SaveStore.save(game.makeSave(), game: .connectFour, slot: slot)
                         },
                         onLoad: { slot in
                             guard let save = SaveStore.load(ConnectFourSave.self, game: .connectFour, slot: slot) else { return false }
                             game.restore(from: save)
                             return true
                         })

            Spacer()
        }
    }
}
