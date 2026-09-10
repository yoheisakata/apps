// CheckersViews.swift — チェッカーの対局画面

import SwiftUI

struct CheckersGameView: View {
    @EnvironmentObject var game: CheckersGameState
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            if !game.hasStarted {
                CheckersSetupView()
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
                CheckersBoardView()
                MoveRecordView(title: "記録", entries: game.moveList)
                    .frame(maxHeight: .infinity)
            }
            CheckersSidebarView()
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
            let heightBudget = max(24, (geo.size.height - reserved) / 8)
            let widthBudget = max(24, geo.size.width / 8)
            let cell = min(heightBudget, widthBudget)

            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    EndGameOverlayButton { game.goToSetup() }
                }
                .frame(height: topBarHeight)

                Spacer(minLength: 0)
                statusBar
                CheckersBoardView(cell: cell)
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
                Text("\(game.opponentMode == .human ? "黒" : "あなた") \(game.position.pieceCount(.black))")
                    .font(.callout.bold())
            }
            HStack(spacing: 6) {
                Circle().fill(Color.white)
                    .overlay(Circle().stroke(Color.gray, lineWidth: 1))
                    .frame(width: 18, height: 18)
                Text("\(game.opponentMode == .human ? "白" : "相手") \(game.position.pieceCount(.white))")
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

struct CheckersSetupView: View {
    @EnvironmentObject var game: CheckersGameState
    @State private var mode: OpponentMode = .ai

    var body: some View {
        GameSetupView(
            title: "チェッカー",
            subtitle: "斜めに進んで相手を飛び越えて取ります。取れるときは必ず取る捕獲優先ルールです。",
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

struct CheckersBoardView: View {
    @EnvironmentObject var game: CheckersGameState
    var cell: CGFloat = 56

    var body: some View {
        let n = CheckersPosition.size
        VStack(spacing: 0) {
            ForEach(0..<n, id: \.self) { r in
                HStack(spacing: 0) {
                    ForEach(0..<n, id: \.self) { c in
                        CheckersSquareView(index: r * n + c, size: cell, isDark: (r + c) % 2 == 1)
                    }
                }
            }
        }
        .background(Color(red: 0.93, green: 0.87, blue: 0.75))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.black.opacity(0.7), lineWidth: 2))
    }
}

struct CheckersSquareView: View {
    @EnvironmentObject var game: CheckersGameState
    let index: Int
    let size: CGFloat
    let isDark: Bool

    var body: some View {
        ZStack {
            background
            if let piece = game.position.board[index] {
                CheckersPieceView(piece: piece, size: size * 0.82,
                                  isSelected: game.selected == index)
            } else if game.legalTargets.contains(index) {
                Circle()
                    .fill(Theme.target)
                    .frame(width: size * 0.3, height: size * 0.3)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { game.tapCell(index) }
    }

    @ViewBuilder
    private var background: some View {
        let base = isDark ? Color(red: 0.42, green: 0.28, blue: 0.18) : Color(red: 0.93, green: 0.87, blue: 0.75)
        if game.selected == index {
            Rectangle().fill(Theme.selected)
        } else if let hint = game.hintMove, hint.from == index || hint.to == index {
            Rectangle().fill(Theme.hintBg)
        } else if let last = game.lastMove, last.from == index || last.to == index {
            Rectangle().fill(Theme.lastMoveBg)
        } else {
            Rectangle().fill(base)
        }
    }
}

struct CheckersPieceView: View {
    let piece: CheckersPiece
    let size: CGFloat
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .fill(piece.owner == .black ? Color.black : Color.white)
                .overlay(Circle().stroke(isSelected ? Color.blue : Color.black.opacity(0.4),
                                         lineWidth: isSelected ? 3 : 1))
                .shadow(color: .black.opacity(0.35), radius: 1, y: 1)
            if piece.isKing {
                Image(systemName: "crown.fill")
                    .font(.system(size: size * 0.4))
                    .foregroundStyle(piece.owner == .black ? Color.yellow : Color.orange)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - サイドバー

struct CheckersSidebarView: View {
    @EnvironmentObject var game: CheckersGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameTopBar(title: "チェッカー")

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
                Text("相手を飛び越えて取れるときは必ず取らなければなりません(捕獲優先)。連続して取れるときはそのまま続けて取れます。端の列(端筋)のコマは取られにくいので安全地帯として活用しましょう。奥の段まで進めるとキングに昇格し、4方向に動けるようになります。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(4)
            }

            SaveSlotsBox(game: .checkers,
                         onSave: { slot in
                             guard !game.aiThinking else { return false }
                             return SaveStore.save(game.makeSave(), game: .checkers, slot: slot)
                         },
                         onLoad: { slot in
                             guard let save = SaveStore.load(CheckersSave.self, game: .checkers, slot: slot) else { return false }
                             game.restore(from: save)
                             return true
                         })

            Spacer()
        }
    }
}
