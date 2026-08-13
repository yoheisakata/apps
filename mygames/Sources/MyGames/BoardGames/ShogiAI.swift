// AI.swift — 学習用のコンピュータ対戦相手
//
// 強い将棋 AI ではなく、初心者の練習相手になる程度の簡易探索。
// レベルごとに探索の深さとランダム性を変える。

import Foundation

enum AILevel: String, CaseIterable, Identifiable, Codable {
    case beginner = "入門(ほぼランダム)"
    case easy     = "初級(駒得だけ考える)"
    case normal   = "中級(2手先を読む)"

    var id: String { rawValue }
}

enum Evaluation {
    /// 駒の基本価値(歩=100 基準)
    static func pieceValue(_ piece: Piece) -> Int {
        let base: Int
        switch piece.type {
        case .pawn:   base = 100
        case .lance:  base = 300
        case .knight: base = 350
        case .silver: base = 500
        case .gold:   base = 550
        case .bishop: base = 800
        case .rook:   base = 950
        case .king:   base = 100_000
        }
        if piece.promoted {
            switch piece.type {
            case .pawn:           return 600
            case .lance, .knight: return 550
            case .silver:         return 550
            case .bishop:         return 1100
            case .rook:           return 1250
            default:              return base
            }
        }
        return base
    }

    static func handValue(_ type: PieceType) -> Int {
        pieceValue(Piece(type: type, player: .sente))
    }

    /// player 視点の駒割り評価
    static func material(_ position: Position, for player: Player) -> Int {
        var score = 0
        for cell in position.board {
            guard let p = cell else { continue }
            score += p.player == player ? pieceValue(p) : -pieceValue(p)
        }
        for type in PieceType.allCases where type != .king {
            let mine = position.handCount(player, type)
            let theirs = position.handCount(player.opponent, type)
            score += (mine - theirs) * handValue(type)
        }
        return score
    }
}

struct ShogiAI {
    var level: AILevel

    /// 現局面での指し手を選ぶ(合法手がなければ nil = 投了)
    func chooseMove(in position: Position) -> Move? {
        let moves = position.legalMoves()
        guard !moves.isEmpty else { return nil }

        switch level {
        case .beginner:
            return chooseBeginner(position: position, moves: moves)
        case .easy:
            return chooseBest(position: position, moves: moves, depth: 1, noise: 60)
        case .normal:
            return chooseBest(position: position, moves: moves, depth: 2, noise: 20)
        }
    }

    /// 入門: 基本ランダム。ただしタダ取りできる駒があればたまに取る。
    private func chooseBeginner(position: Position, moves: [Move]) -> Move? {
        let captures = moves.filter { position[$0.to] != nil }
        if !captures.isEmpty && Int.random(in: 0..<100) < 50 {
            return captures.randomElement()
        }
        return moves.randomElement()
    }

    /// depth 手読みの単純ミニマックス + ノイズ
    private func chooseBest(position: Position, moves: [Move], depth: Int, noise: Int) -> Move? {
        let me = position.sideToMove
        var best: (move: Move, score: Int)?
        for m in moves.shuffled() {
            let next = position.applying(m)
            var score = -negamax(next, depth: depth - 1, for: me.opponent,
                                 alpha: Int.min / 2, beta: Int.max / 2)
            if noise > 0 { score += Int.random(in: -noise...noise) }
            if best == nil || score > best!.score {
                best = (m, score)
            }
        }
        return best?.move
    }

    private func negamax(_ position: Position, depth: Int, for player: Player,
                         alpha: Int, beta: Int) -> Int {
        if depth <= 0 {
            return Evaluation.material(position, for: player)
        }
        let moves = position.legalMoves(checkUchifuzume: false)
        if moves.isEmpty {
            // 手がない = 詰まされている
            return -1_000_000 - depth
        }
        var alpha = alpha
        var best = Int.min / 2
        for m in moves {
            let next = position.applying(m)
            let score = -negamax(next, depth: depth - 1, for: player.opponent,
                                 alpha: -beta, beta: -alpha)
            if score > best { best = score }
            if best > alpha { alpha = best }
            if alpha >= beta { break }
        }
        return best
    }
}

// MARK: - 学習アドバイス(悪手検出・ヒント)

enum Coach {
    /// 指す前の局面 before と指し手 move から、初心者向けの注意を返す(問題なければ nil)
    static func warning(for move: Move, before: Position) -> String? {
        let me = before.sideToMove
        let after = before.applying(move)

        // 動かした駒がタダで取られるか(取り返せない)
        let enemyAttackers = after.attackers(of: move.to, by: me.opponent)
        if !enemyAttackers.isEmpty, let moved = after[move.to], moved.type != .king {
            let defenders = after.attackers(of: move.to, by: me)
            let movedValue = Evaluation.pieceValue(moved)
            if defenders.isEmpty {
                let captured = before[move.to].map { Evaluation.pieceValue($0) } ?? 0
                if captured < movedValue {
                    return "その\(Notation.kanji(for: moved))は相手の駒の利きにあり、タダで取られてしまいます。"
                }
            } else {
                // 一番安い駒で取られたときに交換損になるか
                let cheapest = enemyAttackers
                    .compactMap { after[$0] }
                    .map { Evaluation.pieceValue($0) }
                    .min() ?? 0
                let captured = before[move.to].map { Evaluation.pieceValue($0) } ?? 0
                if movedValue > cheapest + captured + 150 {
                    return "その\(Notation.kanji(for: moved))は安い駒と交換になりそうです。駒損に注意しましょう。"
                }
            }
        }

        // 自玉が相手の駒の利きから見て危なくなっていないか
        if after.isInCheck(me) {
            return nil   // 王手放置は合法手生成で除外済みなのでここには来ない
        }

        return nil
    }

    /// 現局面のおすすめ手を理由付きで返す
    static func hint(for position: Position) -> (move: Move, reason: String)? {
        let moves = position.legalMoves()
        guard !moves.isEmpty else { return nil }
        let me = position.sideToMove

        // 1. 詰みがあるなら最優先
        for m in moves {
            let next = position.applying(m)
            if next.isInCheck(next.sideToMove), next.legalMoves(checkUchifuzume: false).isEmpty {
                return (m, "この手で相手玉が詰みます。")
            }
        }

        // 2. 王手されているなら、それを解消しつつ一番評価の良い手
        if position.isInCheck(me) {
            let best = bestByMaterial(position: position, moves: moves)
            return (best.map { ($0, "王手がかかっています。この手で王手を防げます。") })!
        }

        // 3. タダ取り(取っても取り返されない駒)
        var bestCapture: (move: Move, gain: Int)?
        for m in moves {
            guard let target = position[m.to], m.from != nil else { continue }
            let after = position.applying(m)
            let recapture = after.isAttacked(m.to, by: me.opponent)
            let gain = Evaluation.pieceValue(target)
                - (recapture ? Evaluation.pieceValue(after[m.to]!) : 0)
            if gain > 100, gain > (bestCapture?.gain ?? 0) {
                bestCapture = (m, gain)
            }
        }
        if let capture = bestCapture, let target = position[capture.move.to] {
            return (capture.move, "相手の\(Notation.kanji(for: target))を得できます。駒得は将棋の基本です。")
        }

        // 4. 自分の駒が取られそうなら逃げる/守る
        for r in 0..<9 {
            for c in 0..<9 {
                let sq = Square(row: r, col: c)
                guard let p = position[sq], p.player == me, p.type != .king else { continue }
                let attacked = position.isAttacked(sq, by: me.opponent)
                let defended = position.isAttacked(sq, by: me)
                if attacked && !defended && Evaluation.pieceValue(p) >= 300 {
                    // この駒を動かす手の中で一番良いものを提案
                    let escapes = moves.filter { $0.from == sq }
                    if let escape = bestByMaterial(position: position, moves: escapes) {
                        return (escape, "\(Notation.kanji(for: p))が取られそうです。逃げるか守りましょう。")
                    }
                }
            }
        }

        // 5. それ以外は 2 手読みで一番良い手
        if let best = ShogiAI(level: .normal).chooseMove(in: position) {
            return (best, "駒の働きを良くする手です。飛車・角の道を開けたり、玉を守る駒組みを進めましょう。")
        }
        return nil
    }

    private static func bestByMaterial(position: Position, moves: [Move]) -> Move? {
        let me = position.sideToMove
        var best: (move: Move, score: Int)?
        for m in moves {
            let next = position.applying(m)
            var score = Evaluation.material(next, for: me)
            // 相手が最善で取り返してくる分を 1 手だけ考慮
            let replies = next.legalMoves(checkUchifuzume: false)
            var worst = score
            for reply in replies {
                let after = next.applying(reply)
                let s = Evaluation.material(after, for: me)
                if s < worst { worst = s }
            }
            score = worst
            if best == nil || score > best!.score {
                best = (m, score)
            }
        }
        return best?.move
    }
}
