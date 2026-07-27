// GoViews.swift — 囲碁の対局画面

import SwiftUI

struct GoGameView: View {
    @EnvironmentObject var game: GoGameState
    @EnvironmentObject var router: Router

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                capturesBar
                GoBoardView()
            }
            GoSidebarView()
                .frame(width: 300)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { resultOverlay }
    }

    private var capturesBar: some View {
        HStack(spacing: 20) {
            HStack(spacing: 6) {
                Circle().fill(Color.black).frame(width: 18, height: 18)
                Text("あなた · アゲハマ \(game.position.captures[Disc.black.rawValue])")
                    .font(.callout.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 18, height: 18)
                Text("相手 · アゲハマ \(game.position.captures[Disc.white.rawValue])")
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
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
                .shadow(radius: 20)
            }
        }
    }

    private var resultTitle: String {
        switch game.result {
        case .humanWin: return "勝ち!"
        case .humanLose: return "負け"
        case .draw: return "持碁"
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

struct GoBoardView: View {
    @EnvironmentObject var game: GoGameState

    private var spacing: CGFloat { game.position.size <= 9 ? 52 : 38 }
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
                    Picker("盤の広さ", selection: $game.boardSize) {
                        Text("9路盤(入門)").tag(9)
                        Text("13路盤").tag(13)
                    }
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
