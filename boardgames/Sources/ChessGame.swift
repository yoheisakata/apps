// ChessGame.swift — チェスの対局管理 + 簡易 AI

import Foundation
import SwiftUI

enum ChessResult: Equatable {
    case ongoing
    case humanWin(String)
    case humanLose(String)
    case draw(String)
}

// MARK: - AI

struct ChessAI {
    var level: Difficulty

    static func pieceValue(_ kind: ChessPieceKind) -> Int {
        switch kind {
        case .pawn:   return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook:   return 500
        case .queen:  return 900
        case .king:   return 100_000
        }
    }

    static func evaluate(_ position: ChessPosition, for color: ChessColor) -> Int {
        var score = 0
        for i in 0..<64 {
            guard let p = position.board[i] else { continue }
            var v = pieceValue(p.kind)
            // 中央寄りをわずかに加点(ポーン・ナイト)
            if p.kind == .pawn || p.kind == .knight {
                let r = i / 8, c = i % 8
                let center = 3 - max(abs(r * 2 - 7), abs(c * 2 - 7)) / 2
                v += center * 5
            }
            score += p.color == color ? v : -v
        }
        return score
    }

    func chooseMove(in position: ChessPosition) -> ChessMove? {
        let moves = position.legalMoves()
        guard !moves.isEmpty else { return nil }
        switch level {
        case .easy:
            // 取れる駒があればたまに取る、あとはランダム
            let captures = moves.filter { position[$0.to] != nil }
            if !captures.isEmpty && Int.random(in: 0..<100) < 50 {
                return captures.randomElement()
            }
            return moves.randomElement()
        case .normal:
            return best(position: position, moves: moves, depth: 1, noise: 60)
        case .hard:
            return best(position: position, moves: moves, depth: 2, noise: 15)
        }
    }

    private func best(position: ChessPosition, moves: [ChessMove], depth: Int, noise: Int) -> ChessMove? {
        let me = position.sideToMove
        var bestMove: ChessMove?
        var bestScore = Int.min
        for m in moves.shuffled() {
            let next = position.applying(m)
            var score = -negamax(next, depth: depth - 1, for: me.opponent,
                                 alpha: Int.min / 2, beta: Int.max / 2)
            if noise > 0 { score += Int.random(in: -noise...noise) }
            if score > bestScore {
                bestScore = score
                bestMove = m
            }
        }
        return bestMove
    }

    private func negamax(_ position: ChessPosition, depth: Int, for color: ChessColor,
                         alpha: Int, beta: Int) -> Int {
        if depth <= 0 {
            return Self.evaluate(position, for: color)
        }
        let moves = position.legalMoves()
        if moves.isEmpty {
            return position.isInCheck(color) ? -1_000_000 - depth : 0   // メイト or ステイルメイト
        }
        var alpha = alpha
        var best = Int.min / 2
        for m in moves {
            let next = position.applying(m)
            let score = -negamax(next, depth: depth - 1, for: color.opponent,
                                 alpha: -beta, beta: -alpha)
            if score > best { best = score }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }
        return best
    }
}

// MARK: - 対局管理

@MainActor
final class ChessGameState: ObservableObject {
    @Published var position = ChessPosition.initial()
    @Published var selected: ChessSquare?
    @Published var legalTargets: Set<ChessSquare> = []
    @Published var lastMove: ChessMove?
    @Published var moveList: [KifuEntry] = []
    @Published var result: ChessResult = .ongoing
    @Published var aiThinking = false
    @Published var message = "あなたが白番です。中央のポーン(e2 か d2)を突くのが定番の初手です。"
    @Published var guideText = ""
    @Published var hintMove: ChessMove?
    @Published var aiLevel: Difficulty = .easy
    /// 昇格の選択待ち(from/to が確定していて、昇格先だけ選ぶ)
    @Published var promotionPending: (from: ChessSquare, to: ChessSquare)?

    private var history: [ChessPosition] = []
    private var moveToken = 0

    let humanColor: ChessColor = .white

    var isHumanTurn: Bool {
        result == .ongoing && !aiThinking && position.sideToMove == humanColor
            && promotionPending == nil
    }

    func newGame() {
        moveToken += 1
        aiThinking = false
        position = ChessPosition.initial()
        selected = nil
        legalTargets = []
        lastMove = nil
        moveList = []
        history = []
        result = .ongoing
        hintMove = nil
        promotionPending = nil
        message = "対局開始。あなたが白番です。中央のポーン(e2 か d2)を突くのが定番の初手です。"
    }

    func undo() {
        guard !aiThinking else { return }
        var steps = 0
        while let prev = history.last, steps < 2 {
            history.removeLast()
            if !moveList.isEmpty { moveList.removeLast() }
            position = prev
            steps += 1
            if position.sideToMove == humanColor { break }
        }
        moveToken += 1
        selected = nil
        legalTargets = []
        lastMove = nil
        hintMove = nil
        result = .ongoing
        message = "一手戻しました。"
    }

    // MARK: - 操作

    func tapSquare(_ sq: ChessSquare) {
        guard result == .ongoing, !aiThinking, promotionPending == nil else { return }
        if let piece = position[sq] {
            guideText = ChessPieceGuide.text(for: piece)
        }
        guard position.sideToMove == humanColor else { return }

        if let from = selected {
            if sq == from {
                selected = nil
                legalTargets = []
                return
            }
            if legalTargets.contains(sq) {
                let candidates = position.legalMoves(from: from).filter { $0.to == sq }
                if candidates.count > 1 {
                    // 昇格: 昇格先を選ばせる
                    promotionPending = (from, sq)
                } else if let m = candidates.first {
                    commitHumanMove(m)
                }
                return
            }
        }
        if let piece = position[sq], piece.color == humanColor {
            selected = sq
            legalTargets = Set(position.legalMoves(from: sq).map { $0.to })
        } else {
            selected = nil
            legalTargets = []
        }
    }

    func resolvePromotion(_ kind: ChessPieceKind) {
        guard let pending = promotionPending else { return }
        promotionPending = nil
        commitHumanMove(ChessMove(from: pending.from, to: pending.to, promotion: kind))
    }

    private func commitHumanMove(_ m: ChessMove) {
        apply(m)
        selected = nil
        legalTargets = []
        hintMove = nil
        if position.isInCheck(humanColor.opponent) {
            message = "チェック!相手のキングに迫っています。"
        } else {
            message = "相手の番です。"
        }
        checkGameEnd()
        if result == .ongoing { scheduleAIMove() }
    }

    private func apply(_ m: ChessMove) {
        history.append(position)
        moveList.append(KifuEntry(id: moveList.count + 1,
                                  text: ChessNotation.describe(m, in: position)))
        position = position.applying(m)
        lastMove = m
    }

    private func checkGameEnd() {
        if position.isInsufficientMaterial {
            result = .draw("お互いにメイトできる駒が残っていません。引き分けです。")
            return
        }
        guard position.legalMoves().isEmpty else { return }
        if position.isInCheck(position.sideToMove) {
            if position.sideToMove == humanColor {
                result = .humanLose("チェックメイト。負けてしまいました。")
            } else {
                result = .humanWin("チェックメイト!あなたの勝ちです。")
            }
        } else {
            result = .draw("ステイルメイト(手がないけれどチェックではない)。引き分けです。")
        }
    }

    private func scheduleAIMove() {
        guard result == .ongoing, position.sideToMove != humanColor else { return }
        aiThinking = true
        moveToken += 1
        let token = moveToken
        let snapshot = position
        let ai = ChessAI(level: aiLevel)
        Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let move = ai.chooseMove(in: snapshot)
            await MainActor.run { self.finishAIMove(move, token: token) }
        }
    }

    private func finishAIMove(_ move: ChessMove?, token: Int) {
        guard token == moveToken else { return }
        aiThinking = false
        guard result == .ongoing else { return }
        guard let move else {
            checkGameEnd()
            return
        }
        apply(move)
        if position.isInCheck(humanColor) {
            message = "チェック!キングを守りましょう。逃げる・間に駒を入れる・チェックしている駒を取る、のどれかです。"
        }
        checkGameEnd()
    }

    func showHint() {
        guard isHumanTurn else { return }
        let snapshot = position
        aiThinking = true
        Task.detached(priority: .userInitiated) {
            let move = ChessAI(level: .hard).chooseMove(in: snapshot)
            await MainActor.run {
                self.aiThinking = false
                guard let move else { return }
                self.hintMove = move
                self.message = "ヒント: \(ChessNotation.describe(move, in: snapshot)) が良さそうです。"
            }
        }
    }
}

// MARK: - 途中保存

struct ChessSave: Codable {
    var meta: SaveMeta
    var position: ChessPosition
    var history: [ChessPosition]
    var moveList: [String]
    var aiLevel: Difficulty
    var lastMove: ChessMove?
}

extension ChessGameState {
    func makeSave() -> ChessSave {
        ChessSave(meta: SaveMeta(savedAt: Date(), title: "\(moveList.count)手目"),
                  position: position,
                  history: history,
                  moveList: moveList.map { $0.text },
                  aiLevel: aiLevel,
                  lastMove: lastMove)
    }

    func restore(from save: ChessSave) {
        moveToken += 1
        aiThinking = false
        position = save.position
        history = save.history
        moveList = save.moveList.enumerated().map { KifuEntry(id: $0.offset + 1, text: $0.element) }
        aiLevel = save.aiLevel
        lastMove = save.lastMove
        selected = nil
        legalTargets = []
        hintMove = nil
        promotionPending = nil
        result = .ongoing
        message = "保存した局面から再開します(\(save.moveList.count)手目)。"
        checkGameEnd()
        if result == .ongoing, position.sideToMove != humanColor {
            scheduleAIMove()
        }
    }
}
