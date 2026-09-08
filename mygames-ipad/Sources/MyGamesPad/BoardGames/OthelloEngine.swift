// OthelloEngine.swift — オセロ(リバーシ)のルールエンジンと簡易 AI

import Foundation

enum Disc: Int, Equatable, Codable {
    case black = 0
    case white = 1

    var opponent: Disc { self == .black ? .white : .black }
    var name: String { self == .black ? "黒" : "白" }
}

struct OthelloPosition: Codable {
    var board: [Disc?]        // 64 マス。index = row * 8 + col
    var sideToMove: Disc

    static func initial() -> OthelloPosition {
        var board = [Disc?](repeating: nil, count: 64)
        board[3 * 8 + 3] = .white
        board[3 * 8 + 4] = .black
        board[4 * 8 + 3] = .black
        board[4 * 8 + 4] = .white
        return OthelloPosition(board: board, sideToMove: .black)
    }

    static let directions = [(-1, -1), (-1, 0), (-1, 1), (0, -1),
                             (0, 1), (1, -1), (1, 0), (1, 1)]

    /// index に disc を置いたときに裏返る石の index 一覧(置けなければ空)
    func flips(at index: Int, for disc: Disc) -> [Int] {
        guard board[index] == nil else { return [] }
        let row = index / 8, col = index % 8
        var result: [Int] = []
        for (dr, dc) in Self.directions {
            var line: [Int] = []
            var r = row + dr, c = col + dc
            while r >= 0, r < 8, c >= 0, c < 8 {
                let i = r * 8 + c
                if board[i] == disc.opponent {
                    line.append(i)
                } else if board[i] == disc {
                    result += line
                    break
                } else {
                    break
                }
                r += dr; c += dc
            }
        }
        return result
    }

    func legalMoves(for disc: Disc) -> [Int] {
        (0..<64).filter { !flips(at: $0, for: disc).isEmpty }
    }

    func applying(move index: Int) -> OthelloPosition {
        var next = self
        let disc = sideToMove
        let flipped = flips(at: index, for: disc)
        guard !flipped.isEmpty else { return next }
        next.board[index] = disc
        for i in flipped { next.board[i] = disc }
        next.sideToMove = disc.opponent
        return next
    }

    func count(_ disc: Disc) -> Int {
        board.reduce(0) { $0 + ($1 == disc ? 1 : 0) }
    }

    var isGameOver: Bool {
        legalMoves(for: .black).isEmpty && legalMoves(for: .white).isEmpty
    }

    /// "f5" のような表記
    static func name(of index: Int) -> String {
        let file = Character(UnicodeScalar(97 + index % 8)!)
        return "\(file)\(index / 8 + 1)"
    }
}

// MARK: - AI

struct OthelloAI {
    var level: Difficulty

    /// 位置の重み(角が最重要、角の隣は危険)
    static let weights: [Int] = [
        120, -20,  20,   5,   5,  20, -20, 120,
        -20, -40,  -5,  -5,  -5,  -5, -40, -20,
         20,  -5,  15,   3,   3,  15,  -5,  20,
          5,  -5,   3,   3,   3,   3,  -5,   5,
          5,  -5,   3,   3,   3,   3,  -5,   5,
         20,  -5,  15,   3,   3,  15,  -5,  20,
        -20, -40,  -5,  -5,  -5,  -5, -40, -20,
        120, -20,  20,   5,   5,  20, -20, 120,
    ]

    static func evaluate(_ position: OthelloPosition, for disc: Disc) -> Int {
        var score = 0
        for i in 0..<64 {
            guard let d = position.board[i] else { continue }
            score += d == disc ? weights[i] : -weights[i]
        }
        // 打てる場所の多さ(手番の自由度)も少し評価
        score += (position.legalMoves(for: disc).count
                  - position.legalMoves(for: disc.opponent).count) * 8
        return score
    }

    func chooseMove(in position: OthelloPosition) -> Int? {
        let moves = position.legalMoves(for: position.sideToMove)
        guard !moves.isEmpty else { return nil }
        switch level {
        case .easy:
            return moves.randomElement()
        case .normal:
            // 一番多く裏返せる手(角があれば角)
            let corner = moves.first { [0, 7, 56, 63].contains($0) }
            if let corner { return corner }
            return moves.max { a, b in
                position.flips(at: a, for: position.sideToMove).count
                    < position.flips(at: b, for: position.sideToMove).count
            }
        case .hard:
            return best(position: position, moves: moves, depth: 3)
        }
    }

    private func best(position: OthelloPosition, moves: [Int], depth: Int) -> Int? {
        let me = position.sideToMove
        var bestMove: Int?
        var bestScore = Int.min
        for m in moves.shuffled() {
            let next = position.applying(move: m)
            let score = -negamax(next, depth: depth - 1, for: me.opponent,
                                 alpha: Int.min / 2, beta: Int.max / 2)
            if score > bestScore {
                bestScore = score
                bestMove = m
            }
        }
        return bestMove
    }

    private func negamax(_ position: OthelloPosition, depth: Int, for disc: Disc,
                         alpha: Int, beta: Int) -> Int {
        if position.isGameOver {
            let diff = position.count(disc) - position.count(disc.opponent)
            return diff > 0 ? 100_000 + diff : (diff < 0 ? -100_000 + diff : 0)
        }
        if depth <= 0 {
            return Self.evaluate(position, for: disc)
        }
        let moves = position.legalMoves(for: disc)
        if moves.isEmpty {
            // パス
            var passed = position
            passed.sideToMove = disc.opponent
            return -negamax(passed, depth: depth - 1, for: disc.opponent,
                            alpha: -beta, beta: -alpha)
        }
        var alpha = alpha
        var best = Int.min / 2
        for m in moves {
            var next = position
            next.sideToMove = disc
            next = next.applying(move: m)
            let score = -negamax(next, depth: depth - 1, for: disc.opponent,
                                 alpha: -beta, beta: -alpha)
            if score > best { best = score }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }
        return best
    }
}
