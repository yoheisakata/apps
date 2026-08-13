// GameState.swift — 対局の進行管理(選択、手番、待った、ヒント、AI 呼び出し)

import Foundation
import SwiftUI

enum Selection: Equatable {
    case none
    case board(Square)
    case hand(PieceType)
}

enum GameResult: Equatable {
    case ongoing
    case humanWin(String)
    case humanLose(String)
}

struct KifuEntry: Identifiable {
    let id: Int
    let text: String
}

@MainActor
final class ShogiGameState: ObservableObject {
    @Published var position: Position
    @Published var selection: Selection = .none
    @Published var legalTargets: Set<Square> = []
    @Published var lastMove: Move?
    @Published var kifu: [KifuEntry] = []
    @Published var result: GameResult = .ongoing
    @Published var aiThinking = false

    // 学習サポート
    @Published var coachMessage: String = "駒をクリックすると動かせるマスが光ります。まずは一手指してみましょう。"
    @Published var guideText: String = ""
    @Published var guidePiece: Piece?
    @Published var hintMove: Move?
    @Published var learningMode = true      // 悪手の注意を表示するか

    // 設定
    @Published var aiLevel: AILevel = .beginner
    @Published var handicap: Handicap = .even

    // 成り確認ダイアログ
    @Published var promotionChoice: (promote: Move, stay: Move)?

    /// 待った用の履歴(各手を指す前の局面)
    private var history: [Position] = []
    /// 局面世代。newGame/undo/restore で進め、思考中の AI の指し手が古い局面に適用されるのを防ぐ
    private var moveToken = 0

    let humanPlayer: Player = .sente

    init() {
        position = Position.initial()
    }

    var isHumanTurn: Bool {
        result == .ongoing && !aiThinking && position.sideToMove == humanPlayer
            && promotionChoice == nil
    }

    // MARK: - 対局操作

    func newGame() {
        moveToken += 1
        aiThinking = false
        position = Position.initial(handicap: handicap)
        selection = .none
        legalTargets = []
        lastMove = nil
        kifu = []
        history = []
        result = .ongoing
        hintMove = nil
        promotionChoice = nil
        coachMessage = handicap == .even
            ? "対局開始。あなたが先手です。▲７六歩(角道を開ける)や▲２六歩(飛車先を伸ばす)が定番の初手です。"
            : "\(handicap.rawValue)で対局開始。相手の駒が少ないので、飛車と角を活躍させて攻めを覚えましょう。"
        if position.sideToMove != humanPlayer {
            scheduleAIMove()
        }
    }

    func undo() {
        guard result == .ongoing || !history.isEmpty else { return }
        guard !aiThinking else { return }
        // 人間の手番に戻るまで巻き戻す(通常は 2 手 = 自分の手 + AI の手)
        var steps = 0
        while let prev = history.last, steps < 2 {
            history.removeLast()
            if !kifu.isEmpty { kifu.removeLast() }
            position = prev
            steps += 1
            if position.sideToMove == humanPlayer { break }
        }
        selection = .none
        legalTargets = []
        lastMove = nil
        hintMove = nil
        result = .ongoing
        coachMessage = "一手戻しました。別の手を考えてみましょう。"
    }

    // MARK: - 盤面クリック

    func tapSquare(_ sq: Square) {
        guard result == .ongoing, !aiThinking, promotionChoice == nil else { return }

        // 駒ガイドは常に更新(相手の駒でも学べるように)
        if let piece = position[sq] {
            guideText = PieceGuide.text(for: piece)
            guidePiece = piece
        }

        guard position.sideToMove == humanPlayer else { return }

        switch selection {
        case .board(let from):
            if sq == from {
                clearSelection()
                return
            }
            if legalTargets.contains(sq) {
                performHumanMove(from: from, to: sq)
                return
            }
            trySelect(sq)
        case .hand(let type):
            if legalTargets.contains(sq) {
                let move = Move(from: nil, to: sq, pieceType: type)
                commitHumanMove(move)
                return
            }
            trySelect(sq)
        case .none:
            trySelect(sq)
        }
    }

    func tapHandPiece(_ type: PieceType) {
        guard isHumanTurn else { return }
        guard position.handCount(humanPlayer, type) > 0 else { return }
        if case .hand(let current) = selection, current == type {
            clearSelection()
            return
        }
        selection = .hand(type)
        let drops = position.legalDrops(of: type)
        legalTargets = Set(drops.map { $0.to })
        guideText = PieceGuide.text(for: Piece(type: type, player: humanPlayer))
        guidePiece = Piece(type: type, player: humanPlayer)
        if drops.isEmpty {
            coachMessage = "その駒は今どこにも打てません。"
        }
    }

    private func trySelect(_ sq: Square) {
        if let piece = position[sq], piece.player == humanPlayer {
            selection = .board(sq)
            legalTargets = Set(position.legalMoves(from: sq).map { $0.to })
            if legalTargets.isEmpty {
                coachMessage = "その駒は今動かせるマスがありません。"
            }
        } else {
            clearSelection()
        }
    }

    private func clearSelection() {
        selection = .none
        legalTargets = []
    }

    // MARK: - 指し手の実行

    private func performHumanMove(from: Square, to: Square) {
        let candidates = position.legalMoves(from: from).filter { $0.to == to }
        guard !candidates.isEmpty else { return }
        if candidates.count == 2 {
            // 成り/不成の選択
            let promote = candidates.first { $0.promote }!
            let stay = candidates.first { !$0.promote }!
            promotionChoice = (promote, stay)
            return
        }
        commitHumanMove(candidates[0])
    }

    func resolvePromotion(promote: Bool) {
        guard let choice = promotionChoice else { return }
        promotionChoice = nil
        commitHumanMove(promote ? choice.promote : choice.stay)
    }

    private func commitHumanMove(_ move: Move) {
        // 学習モード: 指す前に悪手チェック
        var warning: String?
        if learningMode {
            warning = Coach.warning(for: move, before: position)
        }

        apply(move)
        clearSelection()
        hintMove = nil

        if let warning {
            coachMessage = "注意: \(warning)"
        } else if position.isInCheck(humanPlayer.opponent) {
            coachMessage = "王手!相手玉に迫っています。"
        } else {
            coachMessage = "良い調子です。相手の狙いにも気を配りましょう。"
        }

        checkGameEnd()
        if result == .ongoing {
            scheduleAIMove()
        }
    }

    private func apply(_ move: Move) {
        history.append(position)
        kifu.append(KifuEntry(id: kifu.count + 1,
                              text: Notation.describe(move, in: position)))
        position = position.applying(move)
        lastMove = move
    }

    private func checkGameEnd() {
        guard position.legalMoves().isEmpty else {
            if position.isInCheck(position.sideToMove), position.sideToMove == humanPlayer {
                coachMessage = "王手をかけられています!玉を逃がすか、合駒するか、王手している駒を取りましょう。"
            }
            return
        }
        if position.sideToMove == humanPlayer {
            result = .humanLose("詰まされました。振り返りで敗因を確認しましょう。")
        } else {
            result = .humanWin("詰み!あなたの勝ちです。")
        }
    }

    // MARK: - AI

    private func scheduleAIMove() {
        guard result == .ongoing, position.sideToMove != humanPlayer else { return }
        aiThinking = true
        moveToken += 1
        let token = moveToken
        let snapshot = position
        let ai = ShogiAI(level: aiLevel)
        Task.detached(priority: .userInitiated) {
            // 少し間を置いて人間らしく
            try? await Task.sleep(nanoseconds: 400_000_000)
            let move = ai.chooseMove(in: snapshot)
            await MainActor.run {
                self.finishAIMove(move, token: token)
            }
        }
    }

    private func finishAIMove(_ move: Move?, token: Int) {
        guard token == moveToken else { return }   // 古い局面への指し手は捨てる
        aiThinking = false
        guard result == .ongoing else { return }
        guard let move else {
            result = .humanWin("相手に指す手がありません。あなたの勝ちです。")
            return
        }
        apply(move)
        if position.isInCheck(humanPlayer) {
            coachMessage = "王手!玉を逃がす・合駒する・王手駒を取る、のどれかで防ぎましょう。"
        }
        checkGameEnd()
    }

    // MARK: - ヒント

    func showHint() {
        guard isHumanTurn else { return }
        let snapshot = position
        aiThinking = true
        Task.detached(priority: .userInitiated) {
            let hint = Coach.hint(for: snapshot)
            await MainActor.run {
                self.aiThinking = false
                guard let hint else {
                    self.coachMessage = "指せる手がありません。"
                    return
                }
                self.hintMove = hint.move
                self.coachMessage = "ヒント: \(Notation.describe(hint.move, in: snapshot)) — \(hint.reason)"
            }
        }
    }
}

// MARK: - 途中保存

struct ShogiSave: Codable {
    var meta: SaveMeta
    var position: Position
    var history: [Position]
    var kifu: [String]
    var handicap: Handicap
    var aiLevel: AILevel
    var learningMode: Bool
    var lastMove: Move?
}

extension ShogiGameState {
    func makeSave() -> ShogiSave {
        ShogiSave(meta: SaveMeta(savedAt: Date(),
                                 title: "\(kifu.count)手目 · \(handicap.rawValue)"),
                  position: position,
                  history: history,
                  kifu: kifu.map { $0.text },
                  handicap: handicap,
                  aiLevel: aiLevel,
                  learningMode: learningMode,
                  lastMove: lastMove)
    }

    func restore(from save: ShogiSave) {
        moveTokenBump()
        position = save.position
        history = save.history
        kifu = save.kifu.enumerated().map { KifuEntry(id: $0.offset + 1, text: $0.element) }
        handicap = save.handicap
        aiLevel = save.aiLevel
        learningMode = save.learningMode
        lastMove = save.lastMove
        selection = .none
        legalTargets = []
        hintMove = nil
        promotionChoice = nil
        result = .ongoing
        coachMessage = "保存した局面から再開します(\(save.kifu.count)手目)。"
        checkGameEnd()
        if result == .ongoing, position.sideToMove != humanPlayer {
            scheduleAIMove()
        }
    }

    private func moveTokenBump() {
        moveToken += 1
        aiThinking = false
    }
}
