// DiamondGame.swift — ダイヤモンドゲーム(エンジン + AI + 対局管理)
//
// 六芒星の盤(121マス)で遊ぶ 2 人版。自分の 10 個のコマを
// 隣への1歩、またはコマを跳び越すジャンプ(連続可)で動かし、
// 先に向かい側の三角形を全部埋めた方が勝ち。
//
// 座標系: y は 0(上端)〜16(下端)。x は横位置で、同じ行のマスは 2 おき。
// 隣接 6 方向 = (±2, 0), (±1, ±1)。

import Foundation
import SwiftUI

struct DPoint: Hashable, Codable {
    var x: Int
    var y: Int
}

enum DiamondPlayer: Int, Codable {
    case south = 0    // 人間(下側、上を目指す)
    case north = 1    // AI(上側、下を目指す)

    var opponent: DiamondPlayer { self == .south ? .north : .south }
    var name: String { self == .south ? "赤" : "黄" }
}

struct DiamondPosition: Codable {
    var south: Set<DPoint>
    var north: Set<DPoint>
    var sideToMove: DiamondPlayer

    // MARK: - 盤の形

    /// 全マス(六芒星、121マス)
    static let allCells: Set<DPoint> = {
        var cells = Set<DPoint>()
        // 上向き三角(頂点が上端 y=0、下へ広がる)
        for y in 0...12 {
            var x = -y
            while x <= y { cells.insert(DPoint(x: x, y: y)); x += 2 }
        }
        // 下向き三角(頂点が下端 y=16、上へ広がる)
        for y in 4...16 {
            let w = 16 - y
            var x = -w
            while x <= w { cells.insert(DPoint(x: x, y: y)); x += 2 }
        }
        return cells
    }()

    /// 上の三角形(AI の陣地 = 人間のゴール)
    static let northHome: Set<DPoint> = allCells.filter { $0.y <= 3 }
    /// 下の三角形(人間の陣地 = AI のゴール)
    static let southHome: Set<DPoint> = allCells.filter { $0.y >= 13 }

    static let directions = [(2, 0), (-2, 0), (1, 1), (-1, 1), (1, -1), (-1, -1)]

    static func initial() -> DiamondPosition {
        DiamondPosition(south: southHome, north: northHome, sideToMove: .south)
    }

    // MARK: - 状態

    var occupied: Set<DPoint> { south.union(north) }

    func occupant(_ p: DPoint) -> DiamondPlayer? {
        if south.contains(p) { return .south }
        if north.contains(p) { return .north }
        return nil
    }

    func pieces(of player: DiamondPlayer) -> Set<DPoint> {
        player == .south ? south : north
    }

    func target(of player: DiamondPlayer) -> Set<DPoint> {
        player == .south ? Self.northHome : Self.southHome
    }

    func hasWon(_ player: DiamondPlayer) -> Bool {
        pieces(of: player).isSubset(of: target(of: player))
    }

    // MARK: - 移動

    /// p のコマが行けるマス(1歩 + 連続ジャンプ)
    func destinations(from p: DPoint) -> Set<DPoint> {
        var result = Set<DPoint>()
        let occ = occupied.subtracting([p])   // 移動中は元の位置は空とみなす

        // 1歩
        for (dx, dy) in Self.directions {
            let step = DPoint(x: p.x + dx, y: p.y + dy)
            if Self.allCells.contains(step), !occ.contains(step) {
                result.insert(step)
            }
        }
        // 連続ジャンプ(幅優先)
        var frontier = [p]
        var visited: Set<DPoint> = [p]
        while let cur = frontier.popLast() {
            for (dx, dy) in Self.directions {
                let over = DPoint(x: cur.x + dx, y: cur.y + dy)
                let land = DPoint(x: cur.x + dx * 2, y: cur.y + dy * 2)
                guard Self.allCells.contains(land),
                      occ.contains(over),
                      !occ.contains(land),
                      !visited.contains(land) else { continue }
                visited.insert(land)
                result.insert(land)
                frontier.append(land)
            }
        }
        return result
    }

    func legalMoves(for player: DiamondPlayer) -> [(from: DPoint, to: DPoint)] {
        var result: [(DPoint, DPoint)] = []
        for p in pieces(of: player) {
            for d in destinations(from: p) {
                result.append((p, d))
            }
        }
        return result
    }

    func applying(from: DPoint, to: DPoint) -> DiamondPosition {
        var next = self
        if next.south.contains(from) {
            next.south.remove(from)
            next.south.insert(to)
        } else if next.north.contains(from) {
            next.north.remove(from)
            next.north.insert(to)
        }
        next.sideToMove = sideToMove.opponent
        return next
    }
}

// MARK: - AI

struct DiamondAI {
    var level: Difficulty

    func chooseMove(in position: DiamondPosition) -> (from: DPoint, to: DPoint)? {
        let me = position.sideToMove
        let moves = position.legalMoves(for: me)
        guard !moves.isEmpty else { return nil }

        switch level {
        case .easy:
            // 前進する手からランダム
            let forward = moves.filter { progress($0, for: me) > 0 }
            return (forward.isEmpty ? moves : forward).randomElement()
        case .normal:
            return best(position: position, moves: moves, noise: 4)
        case .hard:
            return best(position: position, moves: moves, noise: 1)
        }
    }

    /// 前進量(自分のゴール方向に何行進むか)
    private func progress(_ move: (from: DPoint, to: DPoint), for player: DiamondPlayer) -> Int {
        player == .north ? move.to.y - move.from.y : move.from.y - move.to.y
    }

    private func best(position: DiamondPosition, moves: [(from: DPoint, to: DPoint)],
                      noise: Int) -> (from: DPoint, to: DPoint)? {
        let me = position.sideToMove
        let target = position.target(of: me)
        var bestMove: (from: DPoint, to: DPoint)?
        var bestScore = Int.min

        for m in moves.shuffled() {
            var score = progress(m, for: me) * 10

            // ゴールに入る手は加点、ゴールから出る手は大減点
            let fromIn = target.contains(m.from)
            let toIn = target.contains(m.to)
            if !fromIn && toIn { score += 25 }
            if fromIn && !toIn { score -= 200 }
            if fromIn && toIn {
                // ゴール内では奥(行き止まり側)へ詰める
                score += progress(m, for: me) * 5
            }

            // 後ろに取り残されたコマを動かすのを好む
            let rearness = me == .north ? (16 - m.from.y) : m.from.y
            score += rearness / 4

            // 中央寄りを好む(端で詰まりにくい)
            score += (8 - abs(m.to.x)) / 2 - (8 - abs(m.from.x)) / 2

            if noise > 0 { score += Int.random(in: -noise...noise) }
            if score > bestScore {
                bestScore = score
                bestMove = m
            }
        }
        return bestMove
    }
}

// MARK: - 対局管理

enum DiamondResult: Equatable {
    case ongoing
    case humanWin(String)
    case humanLose(String)
}

@MainActor
final class DiamondGameState: ObservableObject {
    @Published var position = DiamondPosition.initial()
    @Published var selected: DPoint?
    @Published var legalTargets: Set<DPoint> = []
    @Published var lastMove: (from: DPoint, to: DPoint)?
    @Published var moveList: [KifuEntry] = []
    @Published var result: DiamondResult = .ongoing
    @Published var aiThinking = false
    @Published var message = "あなたが赤(下側)です。コマを選ぶと行けるマスが光ります。跳び越しは連続でできます。"
    @Published var hintMove: (from: DPoint, to: DPoint)?
    @Published var aiLevel: Difficulty = .easy

    private var history: [DiamondPosition] = []
    private var moveToken = 0

    let humanPlayer: DiamondPlayer = .south

    var isHumanTurn: Bool {
        result == .ongoing && !aiThinking && position.sideToMove == humanPlayer
    }

    func newGame() {
        moveToken += 1
        aiThinking = false
        position = DiamondPosition.initial()
        selected = nil
        legalTargets = []
        lastMove = nil
        moveList = []
        history = []
        result = .ongoing
        hintMove = nil
        message = "対局開始。コマ同士を近づけて「跳び越しの連鎖」を作ると一気に進めます。"
    }

    func undo() {
        guard !aiThinking else { return }
        var steps = 0
        while let prev = history.last, steps < 2 {
            history.removeLast()
            if !moveList.isEmpty { moveList.removeLast() }
            position = prev
            steps += 1
            if position.sideToMove == humanPlayer { break }
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

    func tapCell(_ p: DPoint) {
        guard isHumanTurn else { return }

        if let from = selected {
            if p == from {
                selected = nil
                legalTargets = []
                return
            }
            if legalTargets.contains(p) {
                commitHumanMove(from: from, to: p)
                return
            }
        }
        if position.occupant(p) == humanPlayer {
            selected = p
            legalTargets = position.destinations(from: p)
            if legalTargets.isEmpty {
                message = "そのコマは今動けません。"
            }
        } else {
            selected = nil
            legalTargets = []
        }
    }

    private func commitHumanMove(from: DPoint, to: DPoint) {
        apply(from: from, to: to)
        selected = nil
        legalTargets = []
        hintMove = nil
        if position.hasWon(humanPlayer) {
            result = .humanWin("全部のコマが向かい側に入りました。あなたの勝ちです!")
            return
        }
        message = "相手の番です。"
        scheduleAIMove()
    }

    private func apply(from: DPoint, to: DPoint) {
        history.append(position)
        let mark = position.sideToMove.name
        let jumped = abs(to.y - from.y) > 1 || abs(to.x - from.x) > 2
        moveList.append(KifuEntry(id: moveList.count + 1,
                                  text: "\(mark) \(jumped ? "ジャンプ" : "1歩")(\(from.y)段→\(to.y)段)"))
        position = position.applying(from: from, to: to)
        lastMove = (from, to)
    }

    private func scheduleAIMove() {
        guard result == .ongoing, position.sideToMove != humanPlayer else { return }
        aiThinking = true
        moveToken += 1
        let token = moveToken
        let snapshot = position
        let ai = DiamondAI(level: aiLevel)
        Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let move = ai.chooseMove(in: snapshot)
            await MainActor.run { self.finishAIMove(move, token: token) }
        }
    }

    private func finishAIMove(_ move: (from: DPoint, to: DPoint)?, token: Int) {
        guard token == moveToken else { return }
        aiThinking = false
        guard result == .ongoing, let move else { return }
        apply(from: move.from, to: move.to)
        if position.hasWon(humanPlayer.opponent) {
            result = .humanLose("相手のコマが全部ゴールしてしまいました。跳び越しの連鎖を活用しましょう。")
        }
    }

    func showHint() {
        guard isHumanTurn else { return }
        let snapshot = position
        aiThinking = true
        Task.detached(priority: .userInitiated) {
            let move = DiamondAI(level: .hard).chooseMove(in: snapshot)
            await MainActor.run {
                self.aiThinking = false
                guard let move else { return }
                self.hintMove = move
                let dist = abs(move.to.y - move.from.y)
                self.message = dist >= 2
                    ? "ヒント: オレンジのコマをジャンプで一気に進められます。"
                    : "ヒント: オレンジのコマを1歩進めるのが良さそうです。"
            }
        }
    }
}

// MARK: - 途中保存

struct DiamondSave: Codable {
    var meta: SaveMeta
    var position: DiamondPosition
    var history: [DiamondPosition]
    var moveList: [String]
    var aiLevel: Difficulty
}

extension DiamondGameState {
    func makeSave() -> DiamondSave {
        DiamondSave(meta: SaveMeta(savedAt: Date(), title: "\(moveList.count)手目"),
                    position: position,
                    history: history,
                    moveList: moveList.map { $0.text },
                    aiLevel: aiLevel)
    }

    func restore(from save: DiamondSave) {
        moveToken += 1
        aiThinking = false
        position = save.position
        history = save.history
        moveList = save.moveList.enumerated().map { KifuEntry(id: $0.offset + 1, text: $0.element) }
        aiLevel = save.aiLevel
        selected = nil
        legalTargets = []
        lastMove = nil
        hintMove = nil
        result = .ongoing
        message = "保存した局面から再開します(\(save.moveList.count)手目)。"
        if position.hasWon(humanPlayer) {
            result = .humanWin("全部のコマが向かい側に入りました。あなたの勝ちです!")
        } else if position.hasWon(humanPlayer.opponent) {
            result = .humanLose("相手のコマが全部ゴールしています。")
        } else if position.sideToMove != humanPlayer {
            scheduleAIMove()
        }
    }
}
