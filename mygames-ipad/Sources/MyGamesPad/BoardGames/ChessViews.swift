// ChessViews.swift — チェスの対局画面

import SwiftUI

struct ChessGameView: View {
    @EnvironmentObject var game: ChessGameState
    @EnvironmentObject var router: Router

    var body: some View {
        Group {
            if !game.hasStarted {
                ChessSetupView()
            } else if game.opponentMode == .human {
                twoPlayerLayout
            } else {
                aiLayout
            }
        }
        .background(Color(uiColor: .systemBackground))
        .overlay { promotionOverlay }
        .overlay { resultOverlay }
    }

    private var aiLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ChessBoardView()
                MoveRecordView(title: "棋譜", entries: game.moveList)
                    .frame(maxHeight: .infinity)
            }
            ChessSidebarView()
                .frame(width: 300)
        }
        .padding(16)
    }

    /// 2人対戦: 設定・棋譜などは出さず、盤と「ゲーム終了」ボタンだけを
    /// 縦向き・横向きどちらでも画面いっぱいに表示する(2026-09-09、ユーザー指示
    /// 「ゲーム終了ボタンだけを表示。盤にかぶらない場所に表示」)。
    private var twoPlayerLayout: some View {
        GeometryReader { geo in
            let topBarHeight: CGFloat = 44
            let reserved: CGFloat = 44 + topBarHeight + 24   // 段・筋ラベル+思考中インジケーター+ゲーム終了バー+余白
            let heightBudget = max(24, (geo.size.height - reserved) / 8)
            let widthBudget = max(24, (geo.size.width - 16) / 8)
            let cell = min(heightBudget, widthBudget)

            VStack(spacing: 8) {
                HStack {
                    Spacer()
                    EndGameOverlayButton { game.goToSetup() }
                }
                .frame(height: topBarHeight)

                Spacer(minLength: 0)
                ChessBoardView(cell: cell)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }

    @ViewBuilder
    private var promotionOverlay: some View {
        if game.promotionPending != nil {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("どの駒に昇格しますか?")
                        .font(.title3.bold())
                    Text("ほとんどの場合はクイーンが最善です。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        ForEach([ChessPieceKind.queen, .rook, .bishop, .knight], id: \.self) { kind in
                            Button {
                                game.resolvePromotion(kind)
                            } label: {
                                VStack(spacing: 2) {
                                    Text(kind.glyph).font(.system(size: 30))
                                    Text(kind.japaneseName).font(.caption2)
                                }
                                .frame(width: 76, height: 60)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
                .padding(24)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .systemBackground)))
                .shadow(radius: 20)
            }
        }
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

struct ChessSetupView: View {
    @EnvironmentObject var game: ChessGameState
    @State private var mode: OpponentMode = .ai

    var body: some View {
        GameSetupView(
            title: "チェス",
            subtitle: "キャスリング・アンパッサン対応のチェスです。",
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

struct ChessBoardView: View {
    @EnvironmentObject var game: ChessGameState
    var cell: CGFloat = 62

    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { r in
                        Text("\(8 - r)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: cell)
                    }
                }
                VStack(spacing: 0) {
                    ForEach(0..<8, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<8, id: \.self) { c in
                                ChessSquareView(square: ChessSquare(row: r, col: c), size: cell)
                            }
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gridLine, lineWidth: 2))
            }
            HStack(spacing: 0) {
                Spacer().frame(width: 16)
                ForEach(0..<8, id: \.self) { c in
                    Text(String(Character(UnicodeScalar(97 + c)!)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: cell)
                }
            }
            HStack {
                if game.aiThinking {
                    ProgressView().controlSize(.small)
                    Text("考え中…").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .frame(height: 18)
        }
    }
}

struct ChessSquareView: View {
    @EnvironmentObject var game: ChessGameState
    let square: ChessSquare
    let size: CGFloat

    var body: some View {
        ZStack {
            baseColor
            highlight
            if game.legalTargets.contains(square) && game.position[square] == nil {
                Circle()
                    .fill(Theme.target)
                    .frame(width: size * 0.3, height: size * 0.3)
            }
            if let piece = game.position[square] {
                ChessPieceView(piece: piece, size: size)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { game.tapSquare(square) }
    }

    private var baseColor: some View {
        Rectangle().fill((square.row + square.col) % 2 == 0 ? Theme.chessLight : Theme.chessDark)
    }

    @ViewBuilder
    private var highlight: some View {
        if game.selected == square {
            Rectangle().fill(Theme.selected)
        } else if game.legalTargets.contains(square) && game.position[square] != nil {
            Rectangle().fill(Theme.target)
        } else if isHint {
            Rectangle().fill(Theme.hintBg)
        } else if isLastMove {
            Rectangle().fill(Theme.lastMoveBg)
        }
    }

    private var isLastMove: Bool {
        guard let last = game.lastMove else { return false }
        return last.to == square || last.from == square
    }

    private var isHint: Bool {
        guard let hint = game.hintMove else { return false }
        return hint.to == square || hint.from == square
    }
}

struct ChessPieceView: View {
    let piece: ChessPiece
    let size: CGFloat

    var body: some View {
        Text(piece.kind.glyph)
            .font(.system(size: size * 0.72))
            .foregroundStyle(piece.color == .white ? Color.white : Color.black)
            .shadow(color: piece.color == .white ? .black.opacity(0.85) : .white.opacity(0.4),
                    radius: 1)
    }
}

// MARK: - サイドバー

struct ChessSidebarView: View {
    @EnvironmentObject var game: ChessGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameTopBar(title: "チェス")

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

            GroupBox("駒ガイド") {
                Text(game.guideText.isEmpty ? "盤上の駒をクリックすると、その駒の動きと使い方をここに表示します。" : game.guideText)
                    .font(.callout)
                    .foregroundStyle(game.guideText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                    .padding(4)
            }

            SaveSlotsBox(game: .chess,
                         onSave: { slot in
                             guard !game.aiThinking else { return false }
                             return SaveStore.save(game.makeSave(), game: .chess, slot: slot)
                         },
                         onLoad: { slot in
                             guard let save = SaveStore.load(ChessSave.self, game: .chess, slot: slot) else { return false }
                             game.restore(from: save)
                             return true
                         })

            Spacer()
        }
    }
}
