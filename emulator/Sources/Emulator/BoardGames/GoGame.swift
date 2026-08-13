// GoGame.swift — 囲碁の対局管理

import Foundation
import SwiftUI

enum GoResult: Equatable {
    case ongoing
    case humanWin(String)
    case humanLose(String)
    case draw(String)
}

@MainActor
final class GoGameState: ObservableObject {
    @Published var position = GoPosition.initial(size: 9)
    @Published var lastMove: Int?
    @Published var moveList: [KifuEntry] = []
    @Published var result: GoResult = .ongoing
    @Published var aiThinking = false
    @Published var message = "あなたが黒番です。石で相手の石を囲むと取れます。まずは隅(すみ)の近くから打つのがコツです。"
    @Published var hintMove: Int?
    @Published var aiLevel: Difficulty = .easy
    @Published var boardSize = 9        // 9 or 13(新規対局時に反映)

    let komi = 6.5

    private var history: [GoPosition] = []
    private var moveToken = 0

    let humanColor: Disc = .black

    var isHumanTurn: Bool {
        result == .ongoing && !aiThinking && position.sideToMove == humanColor
    }

    func newGame() {
        moveToken += 1
        aiThinking = false
        position = GoPosition.initial(size: boardSize)
        lastMove = nil
        moveList = []
        history = []
        result = .ongoing
        hintMove = nil
        message = "対局開始。あなたが黒番です。隅→辺→中央の順に価値が高いのが囲碁の基本です。"
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
        lastMove = nil
        hintMove = nil
        result = .ongoing
        message = "一手戻しました。"
    }

    // MARK: - 操作

    func tapPoint(_ index: Int) {
        guard isHumanTurn else { return }
        guard let (next, captured) = position.placing(at: index) else {
            message = "そこには打てません(自殺手、またはコウの直後です)。"
            return
        }
        history.append(position)
        moveList.append(KifuEntry(id: moveList.count + 1,
                                  text: "黒 \(position.name(of: index))"))
        position = next
        lastMove = index
        hintMove = nil
        message = captured > 0 ? "\(captured)子(し)取りました!" : "相手の番です。"
        scheduleAIMove()
    }

    func humanPass() {
        guard isHumanTurn else { return }
        history.append(position)
        moveList.append(KifuEntry(id: moveList.count + 1, text: "黒 パス"))
        position = position.passing()
        lastMove = nil
        hintMove = nil
        if position.consecutivePasses >= 2 {
            finishGame()
        } else {
            message = "パスしました。相手もパスすると終局して数え上げます。"
            scheduleAIMove()
        }
    }

    private func finishGame() {
        let s = position.score(komi: komi)
        let mine = humanColor == .black ? s.black : s.white
        let theirs = humanColor == .black ? s.white : s.black
        let detail = "\(s.detail)。"
        if mine > theirs {
            result = .humanWin("\(detail)\(mine - theirs)目勝ちです!")
        } else if mine < theirs {
            result = .humanLose("\(detail)\(theirs - mine)目負けでした。")
        } else {
            result = .draw("\(detail)持碁(引き分け)です。")
        }
    }

    // MARK: - AI

    private func scheduleAIMove() {
        guard result == .ongoing, position.sideToMove != humanColor else { return }
        aiThinking = true
        moveToken += 1
        let token = moveToken
        let snapshot = position
        let ai = GoAI(level: aiLevel)
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
        history.append(position)
        if let move, let (next, captured) = position.placing(at: move) {
            moveList.append(KifuEntry(id: moveList.count + 1,
                                      text: "白 \(position.name(of: move))"))
            position = next
            lastMove = move
            if captured > 0 {
                message = "相手に\(captured)子取られました。囲まれかけの石は早めに逃げるか捨てる判断を。"
            }
        } else {
            moveList.append(KifuEntry(id: moveList.count + 1, text: "白 パス"))
            position = position.passing()
            lastMove = nil
            if position.consecutivePasses >= 2 {
                finishGame()
                return
            }
            message = "相手はパスしました。あなたもパスすると終局します。取れる石があるなら先に取り切りましょう。"
        }
    }

    func showHint() {
        guard isHumanTurn else { return }
        let snapshot = position
        aiThinking = true
        Task.detached(priority: .userInitiated) {
            let move = GoAI(level: .hard).chooseMove(in: snapshot)
            await MainActor.run {
                self.aiThinking = false
                guard let move else {
                    self.message = "ヒント: もう良い手が残っていません。パスして終局しましょう。"
                    return
                }
                self.hintMove = move
                self.message = "ヒント: \(snapshot.name(of: move)) あたりが良さそうです。"
            }
        }
    }
}

// MARK: - 途中保存

struct GoSave: Codable {
    var meta: SaveMeta
    var position: GoPosition
    var history: [GoPosition]
    var moveList: [String]
    var aiLevel: Difficulty
    var lastMove: Int?
}

extension GoGameState {
    func makeSave() -> GoSave {
        GoSave(meta: SaveMeta(savedAt: Date(),
                              title: "\(moveList.count)手目 · \(position.size)路盤"),
               position: position,
               history: history,
               moveList: moveList.map { $0.text },
               aiLevel: aiLevel,
               lastMove: lastMove)
    }

    func restore(from save: GoSave) {
        moveToken += 1
        aiThinking = false
        position = save.position
        boardSize = save.position.size
        history = save.history
        moveList = save.moveList.enumerated().map { KifuEntry(id: $0.offset + 1, text: $0.element) }
        aiLevel = save.aiLevel
        lastMove = save.lastMove
        hintMove = nil
        result = .ongoing
        message = "保存した局面から再開します(\(save.moveList.count)手目)。"
        if position.consecutivePasses >= 2 {
            finishGame()
        } else if position.sideToMove != humanColor {
            scheduleAIMove()
        }
    }
}
