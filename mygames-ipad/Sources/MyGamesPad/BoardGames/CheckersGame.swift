// CheckersGame.swift — チェッカー(エンジン + AI + 対局管理)
//
// 8x8盤の暗いマス32個だけを使うアメリカンチェッカー。
// 通常のコマは前方斜めにしか動けない・取れない、キングは4方向に1マス。
// 相手のコマを飛び越えて取る手が可能なときは必ず取らなければならない
// (捕獲優先ルール)。連続して取れる場合は同じコマでその場で続けて取る。

import Foundation
import SwiftUI

struct CheckersPiece: Equatable, Codable {
    var owner: Disc
    var isKing: Bool = false
}

struct CheckersMove: Equatable, Codable {
    var from: Int
    var to: Int
    var captured: Int?   // 飛び越えて取った駒のマス(通常移動ならnil)
}

struct CheckersPosition: Codable {
    static let size = 8

    var board: [CheckersPiece?]   // 64マス、index = row*8+col。使うのは(row+col)が奇数のマスのみ
    var sideToMove: Disc

    static func initial() -> CheckersPosition {
        var board = [CheckersPiece?](repeating: nil, count: size * size)
        for row in 0..<3 {
            for col in 0..<size where (row + col) % 2 == 1 {
                board[row * size + col] = CheckersPiece(owner: .black)
            }
        }
        for row in (size - 3)..<size {
            for col in 0..<size where (row + col) % 2 == 1 {
                board[row * size + col] = CheckersPiece(owner: .white)
            }
        }
        return CheckersPosition(board: board, sideToMove: .black)
    }

    /// black は上(row0)からrowが増える方向へ、white は下(row7)からrowが減る方向へ進む
    private func directions(for piece: CheckersPiece) -> [(Int, Int)] {
        if piece.isKing { return [(1, 1), (1, -1), (-1, 1), (-1, -1)] }
        return piece.owner == .black ? [(1, 1), (1, -1)] : [(-1, 1), (-1, -1)]
    }

    private func inBounds(_ r: Int, _ c: Int) -> Bool {
        r >= 0 && r < Self.size && c >= 0 && c < Self.size
    }

    /// 指定した1コマ(from)の、飛び越えて取る手(1回分)
    func captureMoves(from: Int) -> [CheckersMove] {
        guard let piece = board[from] else { return [] }
        let r = from / Self.size, c = from % Self.size
        var moves: [CheckersMove] = []
        for (dr, dc) in directions(for: piece) {
            let mr = r + dr, mc = c + dc
            let lr = r + dr * 2, lc = c + dc * 2
            guard inBounds(lr, lc), inBounds(mr, mc) else { continue }
            let mi = mr * Self.size + mc, li = lr * Self.size + lc
            if let mid = board[mi], mid.owner != piece.owner, board[li] == nil {
                moves.append(CheckersMove(from: from, to: li, captured: mi))
            }
        }
        return moves
    }

    /// player 側の全コマの捕獲手(1手分)
    func allCaptureMoves(for player: Disc) -> [CheckersMove] {
        var moves: [CheckersMove] = []
        for i in 0..<board.count {
            guard let piece = board[i], piece.owner == player else { continue }
            moves.append(contentsOf: captureMoves(from: i))
        }
        return moves
    }

    private func simpleMoves(for player: Disc) -> [CheckersMove] {
        var moves: [CheckersMove] = []
        for i in 0..<board.count {
            guard let piece = board[i], piece.owner == player else { continue }
            let r = i / Self.size, c = i % Self.size
            for (dr, dc) in directions(for: piece) {
                let nr = r + dr, nc = c + dc
                guard inBounds(nr, nc) else { continue }
                let ni = nr * Self.size + nc
                if board[ni] == nil {
                    moves.append(CheckersMove(from: i, to: ni))
                }
            }
        }
        return moves
    }

    /// player 側の合法手(捕獲手があるときはそれのみ = 捕獲優先ルール)
    func legalMoves(for player: Disc) -> [CheckersMove] {
        let captures = allCaptureMoves(for: player)
        return captures.isEmpty ? simpleMoves(for: player) : captures
    }

    func applying(_ move: CheckersMove) -> CheckersPosition {
        var next = self
        guard var piece = next.board[move.from] else { return next }
        next.board[move.from] = nil
        if let captured = move.captured { next.board[captured] = nil }
        let toRow = move.to / Self.size
        if !piece.isKing, (piece.owner == .black && toRow == Self.size - 1)
            || (piece.owner == .white && toRow == 0) {
            piece.isKing = true
        }
        next.board[move.to] = piece
        return next
    }

    func pieceCount(_ player: Disc) -> Int {
        board.compactMap { $0 }.filter { $0.owner == player }.count
    }

    func squareName(_ index: Int) -> String {
        let r = index / Self.size, c = index % Self.size
        let file = Character(UnicodeScalar(65 + c)!)
        return "\(file)\(Self.size - r)"
    }
}

// MARK: - AI

struct CheckersAI {
    var level: Difficulty

    func chooseMove(in position: CheckersPosition) -> CheckersMove? {
        let moves = position.legalMoves(for: position.sideToMove)
        guard !moves.isEmpty else { return nil }

        switch level {
        case .easy:
            return moves.randomElement()
        case .normal:
            return best(position: position, moves: moves, depth: 1, noise: 30)
        case .hard:
            return best(position: position, moves: moves, depth: 2, noise: 8)
        }
    }

    private func best(position: CheckersPosition, moves: [CheckersMove], depth: Int, noise: Int) -> CheckersMove? {
        let me = position.sideToMove
        var bestMove: CheckersMove?
        var bestScore = Int.min
        for m in moves.shuffled() {
            var next = position.applying(m)
            // 連続捕獲がまだ残っていれば手番はそのまま(評価だけ先に進める)
            if m.captured != nil, !next.captureMoves(from: m.to).isEmpty {
                next.sideToMove = me
            } else {
                next.sideToMove = me.opponent
            }
            var score = -negamax(next, depth: depth - 1, for: me.opponent)
            if noise > 0 { score += Int.random(in: -noise...noise) }
            if score > bestScore {
                bestScore = score
                bestMove = m
            }
        }
        return bestMove
    }

    private func negamax(_ position: CheckersPosition, depth: Int, for color: Disc) -> Int {
        if depth <= 0 { return Self.evaluate(position, for: color) }
        let moves = position.legalMoves(for: color)
        if moves.isEmpty { return -1_000_000 }   // 手なし = 負け
        var best = Int.min
        for m in moves {
            var next = position.applying(m)
            let sameTurn = m.captured != nil && !next.captureMoves(from: m.to).isEmpty
            next.sideToMove = sameTurn ? color : color.opponent
            let score = sameTurn
                ? negamax(next, depth: depth, for: color)
                : -negamax(next, depth: depth - 1, for: color.opponent)
            if score > best { best = score }
        }
        return best
    }

    static func evaluate(_ position: CheckersPosition, for color: Disc) -> Int {
        var score = 0
        for cell in position.board {
            guard let piece = cell else { continue }
            let v = piece.isKing ? 300 : 100
            score += piece.owner == color ? v : -v
        }
        return score
    }
}

// MARK: - 対局管理

enum CheckersResult: Equatable {
    case ongoing
    case humanWin(String)
    case humanLose(String)
}

@MainActor
final class CheckersGameState: ObservableObject {
    @Published var position = CheckersPosition.initial()
    @Published var selected: Int?
    @Published var legalTargets: Set<Int> = []
    @Published var lastMove: CheckersMove?
    @Published var moveList: [KifuEntry] = []
    @Published var result: CheckersResult = .ongoing
    @Published var aiThinking = false
    /// スタートボタンを押して対局が始まったか(falseの間はセットアップ画面を出す)
    @Published var hasStarted = false
    @Published var message = "あなたが黒番です。斜め前へ進みます。相手を飛び越えられるときは必ず取らなければなりません。"
    @Published var hintMove: CheckersMove?
    @Published var aiLevel: Difficulty = .easy
    @Published var opponentMode: OpponentMode = .ai {
        didSet {
            guard opponentMode != oldValue else { return }
            if opponentMode == .human {
                moveToken += 1
                aiThinking = false
            } else if result == .ongoing, position.sideToMove != humanDisc {
                scheduleAIMove()
            }
        }
    }

    /// 連続捕獲の途中で、このマスのコマだけが動ける(nilなら制限なし)
    @Published var forcedContinuation: Int?

    private var history: [CheckersPosition] = []
    private var moveToken = 0

    let humanDisc: Disc = .black

    var isHumanTurn: Bool {
        result == .ongoing && !aiThinking
            && (opponentMode == .human || position.sideToMove == humanDisc)
    }

    /// セットアップ画面に戻る(盤面はそのまま。スタートを押すと newGame() が呼ばれる)
    func goToSetup() {
        hasStarted = false
        #if os(iOS)
        OrientationLock.apply(.all)
        #endif
    }

    func newGame() {
        moveToken += 1
        aiThinking = false
        hasStarted = true
        position = CheckersPosition.initial()
        selected = nil
        legalTargets = []
        lastMove = nil
        moveList = []
        history = []
        result = .ongoing
        hintMove = nil
        forcedContinuation = nil
        message = "対局開始。斜め前へ1マス進めます。相手を飛び越えて取れるときは必ず取りましょう。"
    }

    func undo() {
        guard !aiThinking else { return }
        let maxSteps = opponentMode == .human ? 1 : 2
        var steps = 0
        while let prev = history.last, steps < maxSteps {
            history.removeLast()
            if !moveList.isEmpty { moveList.removeLast() }
            position = prev
            steps += 1
            if opponentMode == .human || position.sideToMove == humanDisc { break }
        }
        moveToken += 1
        selected = nil
        legalTargets = []
        lastMove = nil
        hintMove = nil
        forcedContinuation = nil
        result = .ongoing
        message = "一手戻しました。"
    }

    // MARK: - 操作

    func tapCell(_ index: Int) {
        guard isHumanTurn else { return }
        if let from = selected {
            if index == from {
                selected = nil
                legalTargets = []
                return
            }
            if legalTargets.contains(index) {
                let moves = movesFor(from) .filter { $0.to == index }
                if let move = moves.first { commit(move) }
                return
            }
        }
        trySelect(index)
    }

    private func movesFor(_ index: Int) -> [CheckersMove] {
        if let forced = forcedContinuation {
            return index == forced ? position.captureMoves(from: forced) : []
        }
        return position.legalMoves(for: position.sideToMove).filter { $0.from == index }
    }

    private func trySelect(_ index: Int) {
        if forcedContinuation != nil {
            selected = nil
            legalTargets = []
            return
        }
        guard let piece = position.board[index], piece.owner == position.sideToMove else {
            selected = nil
            legalTargets = []
            return
        }
        let moves = movesFor(index)
        if moves.isEmpty {
            selected = nil
            legalTargets = []
            return
        }
        selected = index
        legalTargets = Set(moves.map { $0.to })
    }

    private func commit(_ move: CheckersMove) {
        let mover = position.sideToMove
        apply(move)
        selected = nil
        legalTargets = []
        hintMove = nil

        if move.captured != nil, !position.captureMoves(from: move.to).isEmpty {
            // 連続捕獲: 手番はそのまま、同じコマだけ動かせる
            forcedContinuation = move.to
            selected = move.to
            legalTargets = Set(position.captureMoves(from: move.to).map { $0.to })
            message = "続けて取れます。もう一度同じコマをタップして進めましょう。"
            return
        }

        forcedContinuation = nil
        position.sideToMove = mover.opponent
        if checkEnd() { return }
        message = opponentMode == .human ? "\(mover.opponent.name)の番です。" : "相手の番です。"
        scheduleAIMove()
    }

    private func apply(_ move: CheckersMove) {
        history.append(position)
        let mark = position.sideToMove == .black ? "黒" : "白"
        let verb = move.captured != nil ? "取り" : "歩み"
        moveList.append(KifuEntry(id: moveList.count + 1,
                                  text: "\(mark) \(position.squareName(move.from))→\(position.squareName(move.to))(\(verb))"))
        position = position.applying(move)
        lastMove = move
    }

    private func checkEnd() -> Bool {
        let mover = position.sideToMove
        if position.pieceCount(mover.opponent) == 0 || position.legalMoves(for: mover).isEmpty {
            if opponentMode == .human {
                result = .humanWin("\(mover.opponent.name)が動けなくなりました。\(mover.name)の勝ちです!")
            } else if mover == humanDisc {
                result = .humanLose("動ける手がありません。相手の勝ちです。")
            } else {
                result = .humanWin("相手が動けなくなりました!あなたの勝ちです。")
            }
            return true
        }
        return false
    }

    private func scheduleAIMove() {
        guard opponentMode == .ai, result == .ongoing, position.sideToMove != humanDisc else { return }
        aiThinking = true
        moveToken += 1
        let token = moveToken
        let snapshot = position
        let ai = CheckersAI(level: aiLevel)
        Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let move = ai.chooseMove(in: snapshot)
            await MainActor.run { self.finishAIMove(move, token: token) }
        }
    }

    private func finishAIMove(_ move: CheckersMove?, token: Int) {
        guard token == moveToken else { return }
        aiThinking = false
        guard result == .ongoing, let move else {
            aiThinking = false
            _ = checkEnd()
            return
        }
        let mover = position.sideToMove
        apply(move)
        if move.captured != nil, !position.captureMoves(from: move.to).isEmpty {
            // AIの連続捕獲はそのまま自動で続ける
            aiThinking = true
            moveToken += 1
            let token2 = moveToken
            let snapshot = position
            let ai = CheckersAI(level: aiLevel)
            Task.detached(priority: .userInitiated) {
                try? await Task.sleep(nanoseconds: 350_000_000)
                let next = ai.chooseMove(in: snapshot)
                await MainActor.run { self.finishAIMove(next, token: token2) }
            }
            return
        }
        position.sideToMove = mover.opponent
        _ = checkEnd()
    }

    func showHint() {
        guard opponentMode == .ai, isHumanTurn else { return }
        let snapshot = position
        aiThinking = true
        Task.detached(priority: .userInitiated) {
            let move = CheckersAI(level: .hard).chooseMove(in: snapshot)
            await MainActor.run {
                self.aiThinking = false
                guard let move else { return }
                self.hintMove = move
                let reason = move.captured != nil ? "相手を取れます。" : "良さそうな一手です。"
                self.message = "ヒント: \(snapshot.squareName(move.from))→\(snapshot.squareName(move.to)) — \(reason)"
            }
        }
    }
}

// MARK: - 途中保存

struct CheckersSave: Codable {
    var meta: SaveMeta
    var position: CheckersPosition
    var history: [CheckersPosition]
    var moveList: [String]
    var aiLevel: Difficulty
    var lastMove: CheckersMove?
    var opponentMode: OpponentMode?   // 旧セーブとの互換のためoptional(nilならAI対戦)
}

extension CheckersGameState {
    func makeSave() -> CheckersSave {
        CheckersSave(meta: SaveMeta(savedAt: Date(),
                                    title: "\(moveList.count)手目 · 黒\(position.pieceCount(.black))-白\(position.pieceCount(.white))"),
                    position: position,
                    history: history,
                    moveList: moveList.map { $0.text },
                    aiLevel: aiLevel,
                    lastMove: lastMove,
                    opponentMode: opponentMode)
    }

    func restore(from save: CheckersSave) {
        moveToken += 1
        aiThinking = false
        hasStarted = true
        position = save.position
        history = save.history
        moveList = save.moveList.enumerated().map { KifuEntry(id: $0.offset + 1, text: $0.element) }
        aiLevel = save.aiLevel
        lastMove = save.lastMove
        opponentMode = save.opponentMode ?? .ai
        selected = nil
        legalTargets = []
        hintMove = nil
        forcedContinuation = nil
        result = .ongoing
        message = "保存した局面から再開します(\(save.moveList.count)手目)。"
        if !checkEnd(), position.sideToMove != humanDisc {
            scheduleAIMove()
        }
    }
}
