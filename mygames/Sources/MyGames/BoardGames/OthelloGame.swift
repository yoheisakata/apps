// OthelloGame.swift — オセロの対局管理

import Foundation
import SwiftUI

enum OthelloResult: Equatable {
    case ongoing
    case humanWin(String)
    case humanLose(String)
    case draw(String)
}

@MainActor
final class OthelloGameState: ObservableObject {
    @Published var position = OthelloPosition.initial()
    @Published var lastMove: Int?
    @Published var moveList: [KifuEntry] = []
    @Published var result: OthelloResult = .ongoing
    @Published var aiThinking = false
    @Published var message = "あなたが黒番(先手)です。緑の印のマスに置けます。角(すみ)を取ると有利になります。"
    @Published var hintMove: Int?
    @Published var aiLevel: Difficulty = .easy

    private var history: [OthelloPosition] = []
    private var moveToken = 0

    let humanDisc: Disc = .black

    var isHumanTurn: Bool {
        result == .ongoing && !aiThinking && position.sideToMove == humanDisc
    }

    var legalTargets: Set<Int> {
        guard isHumanTurn else { return [] }
        return Set(position.legalMoves(for: humanDisc))
    }

    func newGame() {
        moveToken += 1
        aiThinking = false
        position = OthelloPosition.initial()
        lastMove = nil
        moveList = []
        history = []
        result = .ongoing
        hintMove = nil
        message = "対局開始。あなたが黒番です。角(すみ)を取ると有利、角の斜め隣(×打ち)は危険、が基本です。"
    }

    func undo() {
        guard !aiThinking else { return }
        var steps = 0
        while let prev = history.last, steps < 4 {
            history.removeLast()
            if !moveList.isEmpty { moveList.removeLast() }
            position = prev
            steps += 1
            // パスが挟まることがあるので「自分の手番かつ置ける」まで戻す
            if position.sideToMove == humanDisc,
               !position.legalMoves(for: humanDisc).isEmpty { break }
        }
        moveToken += 1
        lastMove = nil
        hintMove = nil
        result = .ongoing
        message = "一手戻しました。"
    }

    // MARK: - 操作

    func tapCell(_ index: Int) {
        guard isHumanTurn else { return }
        guard !position.flips(at: index, for: humanDisc).isEmpty else { return }
        apply(index)
        hintMove = nil
        advanceTurn()
    }

    private func apply(_ index: Int) {
        history.append(position)
        let mark = position.sideToMove == .black ? "黒" : "白"
        moveList.append(KifuEntry(id: moveList.count + 1,
                                  text: "\(mark) \(OthelloPosition.name(of: index))"))
        position = position.applying(move: index)
        lastMove = index
    }

    /// 手番を進める。置けない側はパス。両者置けなければ終局。
    private func advanceTurn() {
        if position.isGameOver {
            finishGame()
            return
        }
        if position.legalMoves(for: position.sideToMove).isEmpty {
            // パス
            let passer = position.sideToMove
            position.sideToMove = passer.opponent
            message = "\(passer.name)は置ける場所がないのでパスです。"
        }
        if position.sideToMove != humanDisc {
            scheduleAIMove()
        } else if !message.hasPrefix("白は") {
            message = "あなたの番です。"
        }
    }

    private func finishGame() {
        let mine = position.count(humanDisc)
        let theirs = position.count(humanDisc.opponent)
        let detail = "黒 \(position.count(.black)) - 白 \(position.count(.white))"
        if mine > theirs {
            result = .humanWin("\(detail) であなたの勝ちです!")
        } else if mine < theirs {
            result = .humanLose("\(detail) で負けてしまいました。")
        } else {
            result = .draw("\(detail) の引き分けです。")
        }
    }

    private func scheduleAIMove() {
        guard result == .ongoing, position.sideToMove != humanDisc else { return }
        aiThinking = true
        moveToken += 1
        let token = moveToken
        let snapshot = position
        let ai = OthelloAI(level: aiLevel)
        Task.detached(priority: .userInitiated) {
            try? await Task.sleep(nanoseconds: 500_000_000)
            let move = ai.chooseMove(in: snapshot)
            await MainActor.run { self.finishAIMove(move, token: token) }
        }
    }

    private func finishAIMove(_ move: Int?, token: Int) {
        guard token == moveToken else { return }
        aiThinking = false
        guard result == .ongoing else { return }
        guard let move else {
            advanceTurn()
            return
        }
        apply(move)
        advanceTurn()
    }

    func showHint() {
        guard isHumanTurn else { return }
        let snapshot = position
        aiThinking = true
        Task.detached(priority: .userInitiated) {
            let move = OthelloAI(level: .hard).chooseMove(in: snapshot)
            await MainActor.run {
                self.aiThinking = false
                guard let move else { return }
                self.hintMove = move
                let flips = snapshot.flips(at: move, for: snapshot.sideToMove).count
                var reason = "\(flips)枚返せます。"
                if [0, 7, 56, 63].contains(move) { reason = "角を取れます!角の石は絶対にひっくり返されません。" }
                self.message = "ヒント: \(OthelloPosition.name(of: move)) — \(reason)"
            }
        }
    }
}

// MARK: - 途中保存

struct OthelloSave: Codable {
    var meta: SaveMeta
    var position: OthelloPosition
    var history: [OthelloPosition]
    var moveList: [String]
    var aiLevel: Difficulty
    var lastMove: Int?
}

extension OthelloGameState {
    func makeSave() -> OthelloSave {
        OthelloSave(meta: SaveMeta(savedAt: Date(),
                                   title: "\(moveList.count)手目 · 黒\(position.count(.black))-白\(position.count(.white))"),
                    position: position,
                    history: history,
                    moveList: moveList.map { $0.text },
                    aiLevel: aiLevel,
                    lastMove: lastMove)
    }

    func restore(from save: OthelloSave) {
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
        if position.isGameOver {
            advanceTurn()
        } else if position.sideToMove != humanDisc {
            scheduleAIMove()
        }
    }
}
