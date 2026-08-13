// GomokuViews.swift — 五目並べの対局画面

import SwiftUI

struct GomokuGameView: View {
    @EnvironmentObject var game: GomokuGameState
    @EnvironmentObject var router: Router

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                statusBar
                GomokuBoardView()
            }
            GomokuSidebarView()
                .frame(width: 300)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { resultOverlay }
    }

    private var statusBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(Color.black).frame(width: 18, height: 18)
                Text("あなた(黒)").font(.callout.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 18, height: 18)
                Text("相手(白)").font(.callout.bold())
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

struct GomokuBoardView: View {
    @EnvironmentObject var game: GomokuGameState

    private let spacing: CGFloat = 34
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
                    .frame(minHeight: 80, maxHeight: .infinity)
                    .onChange(of: game.moveList.count) { _ in
                        if let last = game.moveList.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
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
