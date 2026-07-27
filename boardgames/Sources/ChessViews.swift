// ChessViews.swift — チェスの対局画面

import SwiftUI

struct ChessGameView: View {
    @EnvironmentObject var game: ChessGameState
    @EnvironmentObject var router: Router

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            ChessBoardView()
            ChessSidebarView()
                .frame(width: 300)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { promotionOverlay }
        .overlay { resultOverlay }
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
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .windowBackgroundColor)))
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

struct ChessBoardView: View {
    @EnvironmentObject var game: ChessGameState
    let cell: CGFloat = 62

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

            GroupBox("駒ガイド") {
                Text(game.guideText.isEmpty ? "盤上の駒をクリックすると、その駒の動きと使い方をここに表示します。" : game.guideText)
                    .font(.callout)
                    .foregroundStyle(game.guideText.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, minHeight: 50, alignment: .topLeading)
                    .padding(4)
            }

            GroupBox("棋譜") {
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
