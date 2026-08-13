// GomokuGame.swift — 五目並べ(エンジン + AI + 対局管理)
//
// 15路盤。先に縦・横・斜めのどれかに5つ以上並べた方が勝ち。
// 禁じ手(三三など)は採用しない入門ルール。

import Foundation
import SwiftUI

struct GomokuPosition: Codable {
    static let size = 15
    var board: [Disc?]                 // 15*15
    var sideToMove: Disc

    static func initial() -> GomokuPosition {
        GomokuPosition(board: [Disc?](repeating: nil, count: size * size),
                       sideToMove: .black)
    }

    static let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]

    /// index を含む最長の並びの長さ(色 disc)
    func lineLength(at index: Int, for disc: Disc) -> Int {
        let n = Self.size
        let r = index / n, c = index % n
        var best = 0
        for (dr, dc) in Self.directions {
            var count = 1
            var rr = r + dr, cc = c + dc
            while rr >= 0, rr < n, cc >= 0, cc < n, board[rr * n + cc] == disc {
                count += 1; rr += dr; cc += dc
            }
            rr = r - dr; cc = c - dc
            while rr >= 0, rr < n, cc >= 0, cc < n, board[rr * n + cc] == disc {
                count += 1; rr -= dr; cc -= dc
            }
            best = max(best, count)
        }
        return best
    }

    /// index に打つと disc の勝ちになるか
    func isWinningMove(_ index: Int, for disc: Disc) -> Bool {
        var copy = self
        copy.board[index] = disc
        return copy.lineLength(at: index, for: disc) >= 5
    }

    var isFull: Bool { !board.contains(where: { $0 == nil }) }

    func applying(move index: Int) -> GomokuPosition {
        var next = self
        next.board[index] = sideToMove
        next.sideToMove = sideToMove.opponent
        return next
    }

    func name(of index: Int) -> String {
        let n = Self.size
        let letter = Character(UnicodeScalar(65 + index % n)!)
        return "\(letter)\(n - index / n)"
    }
}

// MARK: - AI

struct GomokuAI {
    var level: Difficulty

    func chooseMove(in position: GomokuPosition) -> Int? {
        let n = GomokuPosition.size
        let empties = (0..<n * n).filter { position.board[$0] == nil }
        guard !empties.isEmpty else { return nil }

        // 初手は中央付近
        if position.board.compactMap({ $0 }).isEmpty {
            return (n / 2) * n + n / 2
        }

        // 石の近く(2マス以内)だけを候補にする
        var candidates = empties.filter { near($0, in: position, distance: 2) }
        if candidates.isEmpty { candidates = empties }

        let me = position.sideToMove

        // 勝てるならすぐ勝つ / 相手の即勝ちは必ず止める(全レベル共通)
        if let win = candidates.first(where: { position.isWinningMove($0, for: me) }) {
            return win
        }
        if let block = candidates.first(where: { position.isWinningMove($0, for: me.opponent) }) {
            return block
        }

        switch level {
        case .easy:
            return candidates.randomElement()
        case .normal:
            return best(position: position, candidates: candidates, defense: 0.7, noise: 300)
        case .hard:
            return best(position: position, candidates: candidates, defense: 0.95, noise: 40)
        }
    }

    private func near(_ index: Int, in position: GomokuPosition, distance: Int) -> Bool {
        let n = GomokuPosition.size
        let r = index / n, c = index % n
        for dr in -distance...distance {
            for dc in -distance...distance {
                let rr = r + dr, cc = c + dc
                if rr >= 0, rr < n, cc >= 0, cc < n, position.board[rr * n + cc] != nil {
                    return true
                }
            }
        }
        return false
    }

    private func best(position: GomokuPosition, candidates: [Int],
                      defense: Double, noise: Int) -> Int? {
        let me = position.sideToMove
        var bestMove: Int?
        var bestScore = Int.min
        for m in candidates.shuffled() {
            let offense = Self.cellScore(position: position, index: m, for: me)
            let defenseScore = Self.cellScore(position: position, index: m, for: me.opponent)
            var score = offense + Int(Double(defenseScore) * defense)
            if noise > 0 { score += Int.random(in: -noise...noise) }
            if score > bestScore {
                bestScore = score
                bestMove = m
            }
        }
        return bestMove
    }

    /// index に disc を置いたときの4方向パターン評価
    static func cellScore(position: GomokuPosition, index: Int, for disc: Disc) -> Int {
        let n = GomokuPosition.size
        let r = index / n, c = index % n
        var total = 0
        for (dr, dc) in GomokuPosition.directions {
            var count = 1
            var openEnds = 0
            // 正方向
            var rr = r + dr, cc = c + dc
            while rr >= 0, rr < n, cc >= 0, cc < n, position.board[rr * n + cc] == disc {
                count += 1; rr += dr; cc += dc
            }
            if rr >= 0, rr < n, cc >= 0, cc < n, position.board[rr * n + cc] == nil { openEnds += 1 }
            // 逆方向
            rr = r - dr; cc = c - dc
            while rr >= 0, rr < n, cc >= 0, cc < n, position.board[rr * n + cc] == disc {
                count += 1; rr -= dr; cc -= dc
            }
            if rr >= 0, rr < n, cc >= 0, cc < n, position.board[rr * n + cc] == nil { openEnds += 1 }

            switch (count, openEnds) {
            case (5..., _):  total += 1_000_000
            case (4, 2):     total += 100_000
            case (4, 1):     total += 15_000
            case (3, 2):     total += 8_000
            case (3, 1):     total += 1_200
            case (2, 2):     total += 600
            case (2, 1):     total += 150
            case (1, 2):     total += 50
            default:         break
            }
        }
        return total
    }
}

// MARK: - 対局管理

enum GomokuResult: Equatable {
    case ongoing
    case humanWin(String)
    case humanLose(String)
    case draw(String)
}

@MainActor
final class GomokuGameState: ObservableObject {
    @Published var position = GomokuPosition.initial()
    @Published var lastMove: Int?
    @Published var moveList: [KifuEntry] = []
    @Published var result: GomokuResult = .ongoing
    @Published var aiThinking = false
    @Published var message = "あなたが黒番です。縦・横・斜めのどれかに先に5つ並べたら勝ちです。"
    @Published var hintMove: Int?
    @Published var aiLevel: Difficulty = .easy

    private var history: [GomokuPosition] = []
    private var moveToken = 0

    let humanDisc: Disc = .black

    var isHumanTurn: Bool {
        result == .ongoing && !aiThinking && position.sideToMove == humanDisc
    }

    func newGame() {
        moveToken += 1
        aiThinking = false
        position = GomokuPosition.initial()
        lastMove = nil
        moveList = []
        history = []
        result = .ongoing
        hintMove = nil
        message = "対局開始。中央付近から始めましょう。「両端が空いた3(活三)」を作ると攻めが続きます。"
    }

    func undo() {
        guard !aiThinking else { return }
        var steps = 0
        while let prev = history.last, steps < 2 {
            history.removeLast()
            if !moveList.isEmpty { moveList.removeLast() }
            position = prev
            steps += 1
            if position.sideToMove == humanDisc { break }
        }
        moveToken += 1
        lastMove = nil
        hintMove = nil
        result = .ongoing
        message = "一手戻しました。"
    }

    func tapCell(_ index: Int) {
        guard isHumanTurn, position.board[index] == nil else { return }
        apply(index)
        hintMove = nil
        if checkEnd(after: index) { return }
        message = "相手の番です。"
        scheduleAIMove()
    }

    private func apply(_ index: Int) {
        history.append(position)
        let mark = position.sideToMove == .black ? "黒" : "白"
        moveList.append(KifuEntry(id: moveList.count + 1,
                                  text: "\(mark) \(position.name(of: index))"))
        position = position.applying(move: index)
        lastMove = index
    }

    /// 直前に index へ打った手で終局したか
    private func checkEnd(after index: Int) -> Bool {
        // applying 後なので打った色は「今の手番の反対」
        let placed = position.sideToMove.opponent
        if position.lineLength(at: index, for: placed) >= 5 {
            if placed == humanDisc {
                result = .humanWin("5つ並びました!あなたの勝ちです。")
            } else {
                result = .humanLose("相手に5つ並べられてしまいました。相手の「活三」は早めに止めましょう。")
            }
            return true
        }
        if position.isFull {
            result = .draw("盤が埋まりました。引き分けです。")
            return true
        }
        return false
    }

    private func scheduleAIMove() {
        guard result == .ongoing, position.sideToMove != humanDisc else { return }
        aiThinking = true
        moveToken += 1
        let token = moveToken
        let snapshot = position
        let ai = GomokuAI(level: aiLevel)
        Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let move = ai.chooseMove(in: snapshot)
            await MainActor.run { self.finishAIMove(move, token: token) }
        }
    }

    private func finishAIMove(_ move: Int?, token: Int) {
        guard token == moveToken else { return }
        aiThinking = false
        guard result == .ongoing, let move else { return }
        apply(move)
        _ = checkEnd(after: move)
    }

    func showHint() {
        guard isHumanTurn else { return }
        let snapshot = position
        aiThinking = true
        Task.detached(priority: .userInitiated) {
            let move = GomokuAI(level: .hard).chooseMove(in: snapshot)
            await MainActor.run {
                self.aiThinking = false
                guard let move else { return }
                self.hintMove = move
                if snapshot.isWinningMove(move, for: self.humanDisc) {
                    self.message = "ヒント: \(snapshot.name(of: move)) で5つ並んで勝ちです!"
                } else if snapshot.isWinningMove(move, for: self.humanDisc.opponent) {
                    self.message = "ヒント: \(snapshot.name(of: move)) に打たないと相手が5つ並んでしまいます。"
                } else {
                    self.message = "ヒント: \(snapshot.name(of: move)) が攻守のバランスの良い手です。"
                }
            }
        }
    }
}

// MARK: - 途中保存

struct GomokuSave: Codable {
    var meta: SaveMeta
    var position: GomokuPosition
    var history: [GomokuPosition]
    var moveList: [String]
    var aiLevel: Difficulty
    var lastMove: Int?
}

extension GomokuGameState {
    func makeSave() -> GomokuSave {
        GomokuSave(meta: SaveMeta(savedAt: Date(), title: "\(moveList.count)手目"),
                   position: position,
                   history: history,
                   moveList: moveList.map { $0.text },
                   aiLevel: aiLevel,
                   lastMove: lastMove)
    }

    func restore(from save: GomokuSave) {
        moveToken += 1
        aiThinking = false
        position = save.position
        history = save.history
        moveList = save.moveList.enumerated().map { KifuEntry(id: $0.offset + 1, text: $0.element) }
        aiLevel = save.aiLevel
        lastMove = save.lastMove
        hintMove = nil
        result = .ongoing
        message = "保存した局面から再開します(\(save.moveList.count)手目)。"
        if let last = save.lastMove { _ = checkEnd(after: last) }
        if result == .ongoing, position.sideToMove != humanDisc {
            scheduleAIMove()
        }
    }
}
