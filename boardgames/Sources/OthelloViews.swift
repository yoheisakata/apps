// OthelloViews.swift — オセロの対局画面

import SwiftUI

struct OthelloGameView: View {
    @EnvironmentObject var game: OthelloGameState
    @EnvironmentObject var router: Router

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                scoreBar
                OthelloBoardView()
            }
            OthelloSidebarView()
                .frame(width: 300)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { resultOverlay }
    }

    private var scoreBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(Color.black).frame(width: 20, height: 20)
                Text("あなた \(game.position.count(.black))")
                    .font(.callout.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 20, height: 20)
                Text("相手 \(game.position.count(.white))")
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
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(radius: 20)
            }
        }
    }

    private var resultTitle: String {
        switch game.result {
        case .humanWin: return "勝ち!"
        case .humanLose: return "負け"
        case .draw: return "引き分け"
        case .ongoing: return ""
        }
    }

    private var resultColor: Color {
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

// MARK: - 盤

struct OthelloBoardView: View {
    @EnvironmentObject var game: OthelloGameState
    let cell: CGFloat = 60

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
            .onChange(of: disc) { newDisc in
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
                    Picker("相手の強さ", selection: $game.aiLevel) {
                        ForEach(Difficulty.allCases) { d in
                            Text(d.rawValue).tag(d)
                        }
                    }
                    HStack {
                        Button("新しい対局") { game.newGame() }
                            .buttonStyle(.borderedProminent)
                        Button("待った") { game.undo() }
                            .disabled(game.aiThinking)
                        Button("ヒント") { game.showHint() }
                            .disabled(!game.isHumanTurn)
                    }
                }
                .padding(4)
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

            GroupBox("記録") {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(game.moveList) { entry in
                                Text("\(entry.id). \(entry.text)")
                                    .font(.system(.callout, design: .monospaced))
                                    .id(entry.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                    .frame(minHeight: 100, maxHeight: .infinity)
                    .onChange(of: game.moveList.count) { _ in
                        if let last = game.moveList.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
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
