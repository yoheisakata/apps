// OthelloViews.swift — オセロの対局画面

import SwiftUI

struct OthelloGameView: View {
    @EnvironmentObject var game: OthelloGameState
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            if !game.hasStarted {
                OthelloSetupView()
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
                scoreBar
                OthelloBoardView()
                MoveRecordView(title: "記録", entries: game.moveList)
                    .frame(maxHeight: .infinity)
            }
            OthelloSidebarView()
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
            let reserved: CGFloat = 54 + topBarHeight   // スコアバー+余白+盤の内側パディング+ゲーム終了バー
            let heightBudget = max(24, (geo.size.height - reserved) / 8)
            let widthBudget = max(24, (geo.size.width - 14) / 8)
            let cell = min(heightBudget, widthBudget)

            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    EndGameOverlayButton { game.goToSetup() }
                }
                .frame(height: topBarHeight)

                Spacer(minLength: 0)
                scoreBar
                OthelloBoardView(cell: cell)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    private var scoreBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(Color.black).frame(width: 20, height: 20)
                Text("\(game.opponentMode == .human ? "黒" : "あなた") \(game.position.count(.black))")
                    .font(.callout.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 20, height: 20)
                Text("\(game.opponentMode == .human ? "白" : "相手") \(game.position.count(.white))")
                    .font(.callout.bold())
            }
            Spacer()
            if game.aiThinking {
                ProgressView().controlSize(.small)
                Text("考え中…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 32)
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
                    Text(resultText).font(.callout)
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
        if game.opponentMode == .human {
            return .primary
        }
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

struct OthelloSetupView: View {
    @EnvironmentObject var game: OthelloGameState
    @State private var mode: OpponentMode = .ai

    var body: some View {
        GameSetupView(
            title: "オセロ",
            subtitle: "角(すみ)を取るのがコツ。定番のリバーシです。",
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

struct OthelloBoardView: View {
    @EnvironmentObject var game: OthelloGameState
    var cell: CGFloat = 60

    var body: some View {
        let targets = game.legalTargets
        VStack(spacing: 0) {
            ForEach(0..<8, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { c in
                        OthelloCellView(index: r * 8 + c, size: cell, isTarget: targets.contains(r * 8 + c))
                    }
                }
            }
        }
        .background(Theme.othelloFelt)
        .overlay(gridOverlay)
        .overlay(starDots)
        .padding(5)
        .background(Theme.othelloFelt)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.7), lineWidth: 2))
    }

    /// 盤の線(9本×9本)
    private var gridOverlay: some View {
        Path { p in
            let side = cell * 8
            for i in 0...8 {
                let d = cell * CGFloat(i)
                p.move(to: CGPoint(x: d, y: 0))
                p.addLine(to: CGPoint(x: d, y: side))
                p.move(to: CGPoint(x: 0, y: d))
                p.addLine(to: CGPoint(x: side, y: d))
            }
        }
        .stroke(Color.black.opacity(0.55), lineWidth: 1)
        .allowsHitTesting(false)
    }

    /// 本物のオセロ盤にある4つの黒点(星)
    private var starDots: some View {
        let dots: [(r: Int, c: Int)] = [(2, 2), (2, 6), (6, 2), (6, 6)]
        return ForEach(0..<4, id: \.self) { i in
            Circle()
                .fill(Color.black.opacity(0.7))
                .frame(width: 7, height: 7)
                .position(x: cell * CGFloat(dots[i].c), y: cell * CGFloat(dots[i].r))
                .allowsHitTesting(false)
        }
    }
}

struct OthelloCellView: View {
    @EnvironmentObject var game: OthelloGameState
    let index: Int
    let size: CGFloat
    let isTarget: Bool

    var body: some View {
        ZStack {
            Rectangle().fill(game.hintMove == index && game.position.board[index] == nil
                             ? Color.white.opacity(0.12) : Color.clear)
            if let disc = game.position.board[index] {
                FlippingDisc(disc: disc, delay: flipDelay)
                    .padding(size * 0.09)
                if game.lastMove == index {
                    Circle()
                        .fill(Color.red)
                        .frame(width: size * 0.13, height: size * 0.13)
                }
            } else if isTarget {
                Circle()
                    .fill(game.hintMove == index ? Theme.hintBg : Color.black.opacity(0.25))
                    .frame(width: size * 0.35, height: size * 0.35)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { game.tapCell(index) }
    }

    /// 打った場所から遠い石ほど遅れて返る(波のような演出)
    private var flipDelay: Double {
        guard let last = game.lastMove else { return 0 }
        let dr = abs(index / 8 - last / 8)
        let dc = abs(index % 8 - last % 8)
        return Double(max(dr, dc)) * 0.07
    }
}

/// 色が変わるときに横方向に潰れてから開く「裏返し」アニメーション付きの石
struct FlippingDisc: View {
    let disc: Disc
    let delay: Double

    @State private var shown: Disc = .black
    @State private var xScale: CGFloat = 1

    var body: some View {
        Circle()
            .fill(shown == .black ? Color.black : Color.white)
            .overlay(Circle().stroke(Color.black.opacity(0.3), lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
            .scaleEffect(x: xScale, y: 1)
            .onAppear { shown = disc }          // 打たれた石はそのまま出現
            .onChange(of: disc) { _, newDisc in
                guard newDisc != shown else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                    withAnimation(.easeIn(duration: 0.16)) { xScale = 0.06 }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.17) {
                        shown = newDisc
                        withAnimation(.easeOut(duration: 0.16)) { xScale = 1 }
                    }
                }
            }
    }
}

// MARK: - サイドバー

struct OthelloSidebarView: View {
    @EnvironmentObject var game: OthelloGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameTopBar(title: "オセロ")

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
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                    .padding(4)
            }

            GroupBox("コツ") {
                Text("角(四隅)の石は絶対に返されないので最優先で狙いましょう。逆に角の斜め内側(b2 など)に打つと角を取られやすくなります。序盤は取りすぎない方が終盤に有利です。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(4)
            }

            SaveSlotsBox(game: .othello,
                         onSave: { slot in
                             guard !game.aiThinking else { return false }
                             return SaveStore.save(game.makeSave(), game: .othello, slot: slot)
                         },
                         onLoad: { slot in
                             guard let save = SaveStore.load(OthelloSave.self, game: .othello, slot: slot) else { return false }
                             game.restore(from: save)
                             return true
                         })

            Spacer()
        }
    }
}
