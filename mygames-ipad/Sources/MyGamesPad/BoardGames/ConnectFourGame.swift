// ConnectFourGame.swift — コネクトフォー(エンジン + AI + 対局管理)
//
// 7列×6段。列をタップすると一番下の空きマスに落ち、縦・横・斜めのどれかに
// 先に4つ並べた方が勝ち。

import Foundation
import SwiftUI

/// コネクトフォーは共有の`Disc`(黒/白)をそのまま使うが、盤上では黒同士より
/// 見分けやすい色にするため(2026-09-09、ユーザー指示「色がわかりづらいので、
/// 青と黄色にして」)、表示名だけこの盤に限りローカルに上書きする。
extension Disc {
    var connectFourName: String { self == .black ? "青" : "黄" }
}

struct ConnectFourPosition: Codable {
    static let cols = 7
    static let rows = 6

    var board: [Disc?]           // rows*cols, index = row*cols+col, row0が最上段
    var sideToMove: Disc

    static func initial() -> ConnectFourPosition {
        ConnectFourPosition(board: [Disc?](repeating: nil, count: rows * cols), sideToMove: .black)
    }

    func isColumnFull(_ col: Int) -> Bool { board[col] != nil }   // 最上段(row0)が埋まっていれば満杯

    /// 落とせる行(一番下の空きマス)。満杯なら nil
    func dropRow(_ col: Int) -> Int? {
        for r in stride(from: Self.rows - 1, through: 0, by: -1) {
            if board[r * Self.cols + col] == nil { return r }
        }
        return nil
    }

    var legalColumns: [Int] { (0..<Self.cols).filter { !isColumnFull($0) } }

    func applying(column: Int) -> ConnectFourPosition? {
        guard let row = dropRow(column) else { return nil }
        var next = self
        next.board[row * Self.cols + column] = sideToMove
        next.sideToMove = sideToMove.opponent
        return next
    }

    static let directions = [(0, 1), (1, 0), (1, 1), (1, -1)]

    func lineLength(at index: Int, for disc: Disc) -> Int {
        let r = index / Self.cols, c = index % Self.cols
        var best = 0
        for (dr, dc) in Self.directions {
            var count = 1
            var rr = r + dr, cc = c + dc
            while rr >= 0, rr < Self.rows, cc >= 0, cc < Self.cols, board[rr * Self.cols + cc] == disc {
                count += 1; rr += dr; cc += dc
            }
            rr = r - dr; cc = c - dc
            while rr >= 0, rr < Self.rows, cc >= 0, cc < Self.cols, board[rr * Self.cols + cc] == disc {
                count += 1; rr -= dr; cc -= dc
            }
            best = max(best, count)
        }
        return best
    }

    func isWinningMove(_ col: Int, for disc: Disc) -> Bool {
        guard let row = dropRow(col) else { return false }
        var copy = self
        copy.board[row * Self.cols + col] = disc
        return copy.lineLength(at: row * Self.cols + col, for: disc) >= 4
    }

    var isFull: Bool { !board.contains(where: { $0 == nil }) }

    func columnName(_ col: Int) -> String { "\(col + 1)列目" }
}

// MARK: - AI

struct ConnectFourAI {
    var level: Difficulty

    func chooseMove(in position: ConnectFourPosition) -> Int? {
        let columns = position.legalColumns
        guard !columns.isEmpty else { return nil }
        let me = position.sideToMove

        // 勝てるならすぐ勝つ / 相手の即勝ちは必ず止める(全レベル共通)
        if let win = columns.first(where: { position.isWinningMove($0, for: me) }) {
            return win
        }
        if let block = columns.first(where: { position.isWinningMove($0, for: me.opponent) }) {
            return block
        }

        switch level {
        case .easy:
            return columns.randomElement()
        case .normal:
            return best(position: position, columns: columns, defense: 0.6, noise: 40)
        case .hard:
            return best(position: position, columns: columns, defense: 0.9, noise: 8)
        }
    }

    private func best(position: ConnectFourPosition, columns: [Int],
                      defense: Double, noise: Int) -> Int? {
        let me = position.sideToMove
        var bestCol: Int?
        var bestScore = Int.min
        for col in columns.shuffled() {
            guard let row = position.dropRow(col) else { continue }
            let index = row * ConnectFourPosition.cols + col
            var mine = position
            mine.board[index] = me
            let offense = Self.cellScore(position: mine, index: index, for: me)

            var theirs = position
            theirs.board[index] = me.opponent
            let defenseScore = Self.cellScore(position: theirs, index: index, for: me.opponent)

            // 中央の列を少し優遇(コネクトフォーの定石)
            let centerBonus = (3 - abs(col - 3)) * 4

            var score = offense + Int(Double(defenseScore) * defense) + centerBonus
            if noise > 0 { score += Int.random(in: -noise...noise) }
            if score > bestScore {
                bestScore = score
                bestCol = col
            }
        }
        return bestCol
    }

    /// index に disc を置いたときの4方向パターン評価(五目並べと同じ考え方)
    static func cellScore(position: ConnectFourPosition, index: Int, for disc: Disc) -> Int {
        let cols = ConnectFourPosition.cols, rows = ConnectFourPosition.rows
        let r = index / cols, c = index % cols
        var total = 0
        for (dr, dc) in ConnectFourPosition.directions {
            var count = 1
            var openEnds = 0
            var rr = r + dr, cc = c + dc
            while rr >= 0, rr < rows, cc >= 0, cc < cols, position.board[rr * cols + cc] == disc {
                count += 1; rr += dr; cc += dc
            }
            if rr >= 0, rr < rows, cc >= 0, cc < cols, position.board[rr * cols + cc] == nil { openEnds += 1 }
            rr = r - dr; cc = c - dc
            while rr >= 0, rr < rows, cc >= 0, cc < cols, position.board[rr * cols + cc] == disc {
                count += 1; rr -= dr; cc -= dc
            }
            if rr >= 0, rr < rows, cc >= 0, cc < cols, position.board[rr * cols + cc] == nil { openEnds += 1 }

            switch (count, openEnds) {
            case (4..., _): total += 100_000
            case (3, 2):    total += 5_000
            case (3, 1):    total += 800
            case (2, 2):    total += 300
            case (2, 1):    total += 60
            default:        break
            }
        }
        return total
    }
}

// MARK: - 対局管理

enum ConnectFourResult: Equatable {
    case ongoing
    case humanWin(String)
    case humanLose(String)
    case draw(String)
}

@MainActor
final class ConnectFourGameState: ObservableObject {
    @Published var position = ConnectFourPosition.initial()
    @Published var lastMove: Int?
    @Published var moveList: [KifuEntry] = []
    @Published var result: ConnectFourResult = .ongoing
    @Published var aiThinking = false
    /// スタートボタンを押して対局が始まったか(falseの間はセットアップ画面を出す)
    @Published var hasStarted = false
    @Published var message = "あなたが青番です。列をタップすると一番下に落ちます。縦・横・斜めのどれかに4つ並べたら勝ちです。"
    @Published var hintColumn: Int?
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

    private var history: [ConnectFourPosition] = []
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
        position = ConnectFourPosition.initial()
        lastMove = nil
        moveList = []
        history = []
        result = .ongoing
        hintColumn = nil
        message = "対局開始。中央の列から始めると有利です。相手の3つ並びは早めに止めましょう。"
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
        lastMove = nil
        hintColumn = nil
        result = .ongoing
        message = "一手戻しました。"
    }

    func tapColumn(_ col: Int) {
        guard isHumanTurn, let row = position.dropRow(col) else { return }
        let mover = position.sideToMove
        apply(col, row: row)
        hintColumn = nil
        if checkEnd(after: row * ConnectFourPosition.cols + col) { return }
        message = opponentMode == .human ? "\(mover.opponent.connectFourName)の番です。" : "相手の番です。"
        scheduleAIMove()
    }

    private func apply(_ col: Int, row: Int) {
        history.append(position)
        let mark = position.sideToMove.connectFourName
        moveList.append(KifuEntry(id: moveList.count + 1, text: "\(mark) \(position.columnName(col))"))
        position = position.applying(column: col) ?? position
        lastMove = row * ConnectFourPosition.cols + col
    }

    /// 直前の着手(index)で終局したか
    private func checkEnd(after index: Int) -> Bool {
        let placed = position.sideToMove.opponent
        if position.lineLength(at: index, for: placed) >= 4 {
            if opponentMode == .human {
                result = .humanWin("\(placed.connectFourName)が4つ並べて勝ちです!")
            } else if placed == humanDisc {
                result = .humanWin("4つ並びました!あなたの勝ちです。")
            } else {
                result = .humanLose("相手に4つ並べられてしまいました。相手の3つ並びは早めに止めましょう。")
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
        guard opponentMode == .ai, result == .ongoing, position.sideToMove != humanDisc else { return }
        aiThinking = true
        moveToken += 1
        let token = moveToken
        let snapshot = position
        let ai = ConnectFourAI(level: aiLevel)
        Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 400_000_000)
            let col = ai.chooseMove(in: snapshot)
            await MainActor.run { self.finishAIMove(col, token: token) }
        }
    }

    private func finishAIMove(_ col: Int?, token: Int) {
        guard token == moveToken else { return }
        aiThinking = false
        guard result == .ongoing, let col, let row = position.dropRow(col) else { return }
        apply(col, row: row)
        _ = checkEnd(after: row * ConnectFourPosition.cols + col)
    }

    func showHint() {
        guard opponentMode == .ai, isHumanTurn else { return }
        let snapshot = position
        aiThinking = true
        Task.detached(priority: .userInitiated) {
            let col = ConnectFourAI(level: .hard).chooseMove(in: snapshot)
            await MainActor.run {
                self.aiThinking = false
                guard let col else { return }
                self.hintColumn = col
                if snapshot.isWinningMove(col, for: self.humanDisc) {
                    self.message = "ヒント: \(snapshot.columnName(col)) に落とすと4つ並んで勝ちです!"
                } else if snapshot.isWinningMove(col, for: self.humanDisc.opponent) {
                    self.message = "ヒント: \(snapshot.columnName(col)) に落とさないと相手が4つ並んでしまいます。"
                } else {
                    self.message = "ヒント: \(snapshot.columnName(col)) が攻守のバランスの良い手です。"
                }
            }
        }
    }
}

// MARK: - 途中保存

struct ConnectFourSave: Codable {
    var meta: SaveMeta
    var position: ConnectFourPosition
    var history: [ConnectFourPosition]
    var moveList: [String]
    var aiLevel: Difficulty
    var lastMove: Int?
    var opponentMode: OpponentMode?   // 旧セーブとの互換のためoptional(nilならAI対戦)
}

extension ConnectFourGameState {
    func makeSave() -> ConnectFourSave {
        ConnectFourSave(meta: SaveMeta(savedAt: Date(), title: "\(moveList.count)手目"),
                        position: position,
                        history: history,
                        moveList: moveList.map { $0.text },
                        aiLevel: aiLevel,
                        lastMove: lastMove,
                        opponentMode: opponentMode)
    }

    func restore(from save: ConnectFourSave) {
        moveToken += 1
        aiThinking = false
        hasStarted = true
        position = save.position
        history = save.history
        moveList = save.moveList.enumerated().map { KifuEntry(id: $0.offset + 1, text: $0.element) }
        aiLevel = save.aiLevel
        lastMove = save.lastMove
        opponentMode = save.opponentMode ?? .ai
        hintColumn = nil
        result = .ongoing
        message = "保存した局面から再開します(\(save.moveList.count)手目)。"
        if let last = save.lastMove { _ = checkEnd(after: last) }
        if result == .ongoing, position.sideToMove != humanDisc {
            scheduleAIMove()
        }
    }
}
