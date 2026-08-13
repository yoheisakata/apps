// ShogiViews.swift — 将棋の対局画面
//
// 盤面クリックで合法手をハイライト、悪手の注意、ヒント、駒落ち、待った、
// 駒の動きガイド付きの学習用将棋。

import SwiftUI
import AppKit

// MARK: - メイン画面

struct ShogiGameView: View {
    @EnvironmentObject var game: ShogiGameState
    @EnvironmentObject var router: Router

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 8) {
                ShogiHandView(player: .gote)
                ShogiBoardView()
                ShogiHandView(player: .sente)
            }
            ShogiSidebarView()
                .frame(width: 300)
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay { promotionOverlay }
        .overlay { resultOverlay }
    }

    @ViewBuilder
    private var promotionOverlay: some View {
        if game.promotionChoice != nil {
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text("成りますか?")
                        .font(.title3.bold())
                    Text("成ると駒が強くなります。歩・香・桂・銀は金と同じ動きに、角は馬、飛車は龍になります。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(width: 280)
                    HStack(spacing: 12) {
                        Button("成る") { game.resolvePromotion(promote: true) }
                            .buttonStyle(.borderedProminent)
                            .keyboardShortcut(.defaultAction)
                        Button("成らない") { game.resolvePromotion(promote: false) }
                            .buttonStyle(.bordered)
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
        switch game.result {
        case .ongoing:
            EmptyView()
        case .humanWin(let text), .humanLose(let text):
            ZStack {
                Color.black.opacity(0.3).ignoresSafeArea()
                VStack(spacing: 14) {
                    Text(isWin ? "勝ち!" : "負け")
                        .font(.largeTitle.bold())
                        .foregroundStyle(isWin ? Color.green : Color.red)
                    Text(text)
                        .font(.callout)
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

    private var isWin: Bool {
        if case .humanWin = game.result { return true }
        return false
    }
}

// MARK: - 盤

struct ShogiBoardView: View {
    @EnvironmentObject var game: ShogiGameState
    let cell: CGFloat = 54

    var body: some View {
        VStack(spacing: 2) {
            // 筋の番号(9..1)
            HStack(spacing: 0) {
                ForEach(0..<9, id: \.self) { c in
                    Text("\(9 - c)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: cell)
                }
                Spacer().frame(width: 16)
            }
            HStack(spacing: 2) {
                VStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { r in
                        HStack(spacing: 0) {
                            ForEach(0..<9, id: \.self) { c in
                                ShogiSquareView(square: Square(row: r, col: c), size: cell)
                            }
                        }
                    }
                }
                .background(Theme.boardWood)
                .overlay(gridOverlay)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gridLine, lineWidth: 2))

                // 段の番号(一..九)
                VStack(spacing: 0) {
                    ForEach(0..<9, id: \.self) { r in
                        Text(Notation.rankKanji[r])
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(width: 14, height: cell)
                    }
                }
            }
        }
    }

    private var gridOverlay: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width
                let h = geo.size.height
                for i in 1..<9 {
                    let x = w * CGFloat(i) / 9
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 9
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Theme.gridLine.opacity(0.7), lineWidth: 1)
        }
        .allowsHitTesting(false)
    }
}

struct ShogiSquareView: View {
    @EnvironmentObject var game: ShogiGameState
    let square: Square
    let size: CGFloat

    var body: some View {
        ZStack {
            background
            if game.legalTargets.contains(square) && game.position[square] == nil {
                Circle()
                    .fill(Theme.target)
                    .frame(width: size * 0.3, height: size * 0.3)
            }
            if let piece = game.position[square] {
                ShogiPieceView(piece: piece, size: size)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
        .onTapGesture { game.tapSquare(square) }
    }

    @ViewBuilder
    private var background: some View {
        if case .board(let sel) = game.selection, sel == square {
            Rectangle().fill(Theme.selected)
        } else if game.legalTargets.contains(square) && game.position[square] != nil {
            Rectangle().fill(Theme.target)
        } else if isHint {
            Rectangle().fill(Theme.hintBg)
        } else if isLastMove {
            Rectangle().fill(Theme.lastMoveBg)
        } else {
            Rectangle().fill(Color.clear)
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

struct ShogiPieceView: View {
    let piece: Piece
    let size: CGFloat
    /// true なら後手の駒でも回転させずに描く(動き図用)
    var upright: Bool = false

    var body: some View {
        ZStack {
            PentagonShape()
                .fill(Theme.pieceWood)
                .overlay(PentagonShape().stroke(Theme.gridLine, lineWidth: 1))
                .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
            Text(Notation.kanji(for: piece))
                .font(.system(size: size * 0.42, weight: .bold, design: .serif))
                .foregroundStyle(piece.promoted ? Theme.promotedRed : Color.black)
                .offset(y: size * 0.04)
        }
        .frame(width: size * 0.82, height: size * 0.88)
        .rotationEffect(!upright && piece.player == .gote ? .degrees(180) : .degrees(0))
    }
}

/// 将棋駒の五角形
struct PentagonShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: w * 0.5, y: 0))              // 上の頂点
        p.addLine(to: CGPoint(x: w * 0.88, y: h * 0.24))
        p.addLine(to: CGPoint(x: w * 0.97, y: h))
        p.addLine(to: CGPoint(x: w * 0.03, y: h))
        p.addLine(to: CGPoint(x: w * 0.12, y: h * 0.24))
        p.closeSubpath()
        return p
    }
}

// MARK: - 持ち駒

struct ShogiHandView: View {
    @EnvironmentObject var game: ShogiGameState
    let player: Player

    private let order: [PieceType] = [.rook, .bishop, .gold, .silver, .knight, .lance, .pawn]

    var body: some View {
        HStack(spacing: 6) {
            Text(player == .sente ? "▲あなた" : "△相手")
                .font(.callout.bold())
                .frame(width: 74, alignment: .leading)
            ForEach(order, id: \.self) { type in
                let count = game.position.handCount(player, type)
                if count > 0 {
                    handPiece(type: type, count: count)
                }
            }
            Spacer()
            if player != game.humanPlayer && game.aiThinking {
                ProgressView().controlSize(.small)
                Text("考え中…").font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.boardWood.opacity(0.4)))
    }

    private func handPiece(type: PieceType, count: Int) -> some View {
        HStack(spacing: 1) {
            ShogiPieceView(piece: Piece(type: type, player: player), size: 38)
            if count > 1 {
                Text("\(count)").font(.caption.bold())
            }
        }
        .padding(2)
        .background(selectionBackground(type))
        .contentShape(Rectangle())
        .onTapGesture {
            if player == game.humanPlayer { game.tapHandPiece(type) }
        }
    }

    @ViewBuilder
    private func selectionBackground(_ type: PieceType) -> some View {
        if player == game.humanPlayer,
           case .hand(let sel) = game.selection, sel == type {
            RoundedRectangle(cornerRadius: 4).fill(Theme.selected)
        } else {
            Color.clear
        }
    }
}

// MARK: - 駒の動き図

/// 選択した駒の動ける範囲を 5×5 のミニ盤で図示する。
/// 常に「自分から見て前が上」になる向きで描く(後手の駒も向きを揃える)。
struct MovementDiagramView: View {
    let piece: Piece
    private let cell: CGFloat = 22

    private enum Mark {
        case step            // その位置へ1マス動ける
        case slide(String)   // その方向へ何マスでも(矢印グリフ)
    }

    /// 中心を (0,0) とした相対座標 → マーク
    private var marks: [String: Mark] {
        // 図は常に先手向き(前 = 上)で描く
        let normalized = Piece(type: piece.type, player: .sente, promoted: piece.promoted)
        var result: [String: Mark] = [:]
        for v in Position.vectors(for: normalized) {
            if v.slide {
                let arrow = Self.arrowGlyph(dr: v.dr, dc: v.dc)
                for dist in 1...2 {
                    result["\(v.dr * dist),\(v.dc * dist)"] = .slide(arrow)
                }
            } else {
                result["\(v.dr),\(v.dc)"] = .step
            }
        }
        return result
    }

    private static func arrowGlyph(dr: Int, dc: Int) -> String {
        switch (dr < 0 ? -1 : (dr > 0 ? 1 : 0), dc < 0 ? -1 : (dc > 0 ? 1 : 0)) {
        case (-1, 0):  return "↑"
        case (1, 0):   return "↓"
        case (0, -1):  return "←"
        case (0, 1):   return "→"
        case (-1, -1): return "↖"
        case (-1, 1):  return "↗"
        case (1, -1):  return "↙"
        case (1, 1):   return "↘"
        default:       return ""
        }
    }

    var body: some View {
        let m = marks
        VStack(spacing: 0) {
            ForEach(-2...2, id: \.self) { dr in
                HStack(spacing: 0) {
                    ForEach(-2...2, id: \.self) { dc in
                        cellView(mark: m["\(dr),\(dc)"], isCenter: dr == 0 && dc == 0)
                    }
                }
            }
        }
        .background(Theme.boardWood.opacity(0.6))
        .overlay(gridOverlay)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Theme.gridLine.opacity(0.6), lineWidth: 1))
    }

    @ViewBuilder
    private func cellView(mark: Mark?, isCenter: Bool) -> some View {
        ZStack {
            if isCenter {
                ShogiPieceView(piece: piece, size: cell, upright: true)
            } else {
                switch mark {
                case .step:
                    Circle()
                        .fill(Color.green.opacity(0.75))
                        .frame(width: cell * 0.45, height: cell * 0.45)
                case .slide(let arrow):
                    Text(arrow)
                        .font(.system(size: cell * 0.62, weight: .bold))
                        .foregroundStyle(Color.green.opacity(0.9))
                case nil:
                    EmptyView()
                }
            }
        }
        .frame(width: cell, height: cell)
    }

    private var gridOverlay: some View {
        GeometryReader { geo in
            Path { p in
                let w = geo.size.width
                let h = geo.size.height
                for i in 1..<5 {
                    let x = w * CGFloat(i) / 5
                    p.move(to: CGPoint(x: x, y: 0))
                    p.addLine(to: CGPoint(x: x, y: h))
                    let y = h * CGFloat(i) / 5
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: w, y: y))
                }
            }
            .stroke(Theme.gridLine.opacity(0.35), lineWidth: 0.5)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - サイドバー

struct ShogiSidebarView: View {
    @EnvironmentObject var game: ShogiGameState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GameTopBar(title: "将棋")

            // 対局設定
            GroupBox("対局") {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("手合", selection: $game.handicap) {
                        ForEach(Handicap.allCases) { h in
                            Text(h.rawValue).tag(h)
                        }
                    }
                    Picker("相手の強さ", selection: $game.aiLevel) {
                        ForEach(AILevel.allCases) { l in
                            Text(l.rawValue).tag(l)
                        }
                    }
                    Toggle("学習モード(悪手の注意を表示)", isOn: $game.learningMode)
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

            // コーチのメッセージ
            GroupBox("コーチ") {
                Text(game.coachMessage)
                    .font(.callout)
                    .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                    .padding(4)
            }

            // 駒の説明
            GroupBox("駒ガイド") {
                HStack(alignment: .top, spacing: 10) {
                    if let piece = game.guidePiece {
                        MovementDiagramView(piece: piece)
                    }
                    Text(game.guideText.isEmpty ? "盤上の駒をクリックすると、その駒の動きと使い方をここに表示します。" : game.guideText)
                        .font(.callout)
                        .foregroundStyle(game.guideText.isEmpty ? .secondary : .primary)
                        .frame(maxWidth: .infinity, minHeight: 60, alignment: .topLeading)
                }
                .padding(4)
            }

            // 棋譜
            GroupBox("棋譜") {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(game.kifu) { entry in
                                Text("\(entry.id). \(entry.text)")
                                    .font(.system(.callout, design: .monospaced))
                                    .id(entry.id)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                    .frame(minHeight: 100, maxHeight: .infinity)
                    .onChange(of: game.kifu.count) { _ in
                        if let last = game.kifu.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }

            // 途中保存
            SaveSlotsBox(game: .shogi,
                         onSave: { slot in
                             guard !game.aiThinking else { return false }
                             return SaveStore.save(game.makeSave(), game: .shogi, slot: slot)
                         },
                         onLoad: { slot in
                             guard let save = SaveStore.load(ShogiSave.self, game: .shogi, slot: slot) else { return false }
                             game.restore(from: save)
                             return true
                         })

            Spacer()
        }
    }
}
