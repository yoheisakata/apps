// GoEngine.swift — 囲碁のルールエンジンと簡易 AI
//
// 石の色は Disc(OthelloEngine.swift)を共用。
// 取り(呼吸点ゼロの石の除去)、自殺手の禁止、コウ(直前の盤面の再現禁止)、
// パス2回で終局、中国ルール(石+地)での数え上げに対応。

import Foundation

struct GoPosition: Codable {
    var size: Int                     // 9 or 13
    var board: [Disc?]                // size*size。index = row * size + col
    var sideToMove: Disc
    /// 直前の着手の「前」の盤面(コウの判定用)
    var koBoard: [Disc?]?
    var consecutivePasses: Int = 0
    /// アゲハマ(取った石の数)[black, white]
    var captures: [Int] = [0, 0]

    static func initial(size: Int) -> GoPosition {
        GoPosition(size: size,
                   board: [Disc?](repeating: nil, count: size * size),
                   sideToMove: .black,
                   koBoard: nil)
    }

    func neighbors(of index: Int) -> [Int] {
        let r = index / size, c = index % size
        var result: [Int] = []
        if r > 0 { result.append(index - size) }
        if r < size - 1 { result.append(index + size) }
        if c > 0 { result.append(index - 1) }
        if c < size - 1 { result.append(index + 1) }
        return result
    }

    /// index の石が属する連(グループ)と呼吸点の数
    func group(at index: Int) -> (stones: Set<Int>, liberties: Int) {
        guard let color = board[index] else { return ([], 0) }
        var stones: Set<Int> = [index]
        var liberties: Set<Int> = []
        var stack = [index]
        while let cur = stack.popLast() {
            for n in neighbors(of: cur) {
                if board[n] == color, !stones.contains(n) {
                    stones.insert(n)
                    stack.append(n)
                } else if board[n] == nil {
                    liberties.insert(n)
                }
            }
        }
        return (stones, liberties.count)
    }

    /// index に打った結果の盤面(違法手なら nil)。取った石の数も返す
    func placing(at index: Int) -> (position: GoPosition, captured: Int)? {
        guard board[index] == nil else { return nil }
        var next = self
        let me = sideToMove
        next.board[index] = me

        // 相手の連で呼吸点が無くなったものを取る
        var captured = 0
        for n in neighbors(of: index) where next.board[n] == me.opponent {
            let g = next.group(at: n)
            if g.liberties == 0 {
                captured += g.stones.count
                for s in g.stones { next.board[s] = nil }
            }
        }
        // 自殺手の禁止
        if captured == 0, next.group(at: index).liberties == 0 {
            return nil
        }
        // コウ: 直前の盤面をそのまま再現する手は禁止
        if let ko = koBoard, next.board == ko {
            return nil
        }
        next.captures[me.rawValue] += captured
        next.koBoard = board
        next.sideToMove = me.opponent
        next.consecutivePasses = 0
        return (next, captured)
    }

    func passing() -> GoPosition {
        var next = self
        next.koBoard = board
        next.sideToMove = sideToMove.opponent
        next.consecutivePasses += 1
        return next
    }

    func isLegal(_ index: Int) -> Bool {
        placing(at: index) != nil
    }

    func legalMoves() -> [Int] {
        (0..<size * size).filter { isLegal($0) }
    }

    /// 完全な「自分の眼」か(埋めるべきでない点)
    func isOwnEye(_ index: Int, for color: Disc) -> Bool {
        guard board[index] == nil else { return false }
        for n in neighbors(of: index) where board[n] != color { return false }
        // 斜めもほぼ自分の石なら眼とみなす
        let r = index / size, c = index % size
        var enemyDiag = 0, offBoard = 0
        for (dr, dc) in [(-1, -1), (-1, 1), (1, -1), (1, 1)] {
            let rr = r + dr, cc = c + dc
            if rr < 0 || rr >= size || cc < 0 || cc >= size {
                offBoard += 1
            } else if board[rr * size + cc] == color.opponent {
                enemyDiag += 1
            }
        }
        return offBoard > 0 ? enemyDiag == 0 : enemyDiag <= 1
    }

    // MARK: - 数え上げ(中国ルール: 石 + 地)

    /// (黒の得点, 白の得点(コミ込み), 説明)
    func score(komi: Double) -> (black: Double, white: Double, detail: String) {
        var blackArea = 0
        var whiteArea = 0
        var visited = Set<Int>()

        for i in 0..<size * size {
            if board[i] == .black { blackArea += 1; continue }
            if board[i] == .white { whiteArea += 1; continue }
            guard !visited.contains(i) else { continue }
            // 空点の領域を洗い出し、接している色を調べる
            var region: Set<Int> = [i]
            var stack = [i]
            var bordersBlack = false
            var bordersWhite = false
            while let cur = stack.popLast() {
                for n in neighbors(of: cur) {
                    switch board[n] {
                    case .black: bordersBlack = true
                    case .white: bordersWhite = true
                    case nil:
                        if !region.contains(n) {
                            region.insert(n)
                            stack.append(n)
                        }
                    }
                }
            }
            visited.formUnion(region)
            if bordersBlack && !bordersWhite { blackArea += region.count }
            if bordersWhite && !bordersBlack { whiteArea += region.count }
        }

        let black = Double(blackArea)
        let white = Double(whiteArea) + komi
        let detail = "黒 \(blackArea) — 白 \(whiteArea) + コミ \(komi)"
        return (black, white, detail)
    }

    /// "C3" のような表記(I は欠番にしない簡易版)
    func name(of index: Int) -> String {
        let col = index % size
        let row = index / size
        let letter = Character(UnicodeScalar(65 + col)!)
        return "\(letter)\(size - row)"
    }
}

// MARK: - AI

struct GoAI {
    var level: Difficulty

    /// 指し手(nil はパス)
    func chooseMove(in position: GoPosition) -> Int? {
        let me = position.sideToMove
        // 自分の眼を埋める手は除外
        let moves = position.legalMoves().filter { !position.isOwnEye($0, for: me) }
        guard !moves.isEmpty else { return nil }

        switch level {
        case .easy:
            // 取れる手があればたまに取る、あとはランダム
            let captures = moves.filter { m in
                (position.placing(at: m)?.captured ?? 0) > 0
            }
            if !captures.isEmpty && Int.random(in: 0..<100) < 60 {
                return captures.randomElement()
            }
            return moves.randomElement()
        case .normal:
            return best(position: position, moves: moves, noise: 25)
        case .hard:
            return best(position: position, moves: moves, noise: 8)
        }
    }

    private func best(position: GoPosition, moves: [Int], noise: Int) -> Int? {
        let me = position.sideToMove
        var bestMove: Int?
        var bestScore = Int.min

        // 打つ前に、アタリになっている自分の連を把握
        var myAtariGroups: [Set<Int>] = []
        var seen = Set<Int>()
        for i in 0..<position.size * position.size {
            guard position.board[i] == me, !seen.contains(i) else { continue }
            let g = position.group(at: i)
            seen.formUnion(g.stones)
            if g.liberties == 1 { myAtariGroups.append(g.stones) }
        }

        for m in moves.shuffled() {
            guard let (next, captured) = position.placing(at: m) else { continue }
            var score = captured * 100

            // 打った石の連の呼吸点
            let myGroup = next.group(at: m)
            if myGroup.liberties <= 1 {
                score -= 90                     // 自分からアタリに入らない
            } else if myGroup.liberties == 2 {
                score -= 10
            } else {
                score += myGroup.liberties * 2
            }

            // アタリの味方を救えたか
            for g in myAtariGroups {
                if let stone = g.first, next.board[stone] == me,
                   next.group(at: stone).liberties > 1 {
                    score += 90
                }
            }

            // 相手の連をアタリにできたか
            for n in next.neighbors(of: m) where next.board[n] == me.opponent {
                if next.group(at: n).liberties == 1 { score += 35 }
            }

            // 位置: 2〜3線を好み、一線を避ける(序盤ほど効く)
            let stonesOnBoard = position.board.compactMap { $0 }.count
            if stonesOnBoard < position.size * position.size / 3 {
                let r = m / position.size, c = m % position.size
                let edge = min(min(r, position.size - 1 - r), min(c, position.size - 1 - c))
                switch edge {
                case 0:  score -= 25
                case 1:  score += 5
                case 2, 3: score += 15
                default: score += 8
                }
            }

            score += Int.random(in: -noise...noise)
            if score > bestScore {
                bestScore = score
                bestMove = m
            }
        }
        // ろくな手がなければパス
        if bestScore < -50 { return nil }
        return bestMove
    }
}
