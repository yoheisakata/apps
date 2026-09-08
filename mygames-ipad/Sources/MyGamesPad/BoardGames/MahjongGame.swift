// MahjongGame.swift — 麻雀の局進行管理
//
// 席順: 0 = あなた(東・下)、1 = 南(右)、2 = 西(上)、3 = 北(左)。
// ツモ番は 0 → 1 → 2 → 3 → 0 …。

import Foundation
import SwiftUI

enum MahjongPhase: Equatable {
    case humanTurn          // 人間がツモって打牌待ち
    case aiPlaying          // AI が順番に打っている
    case ronOffer(tile: Int, discarder: Int)   // 人間がロンできる(ロン/スルー選択待ち)
    case finished
}

enum MahjongResult: Equatable {
    case ongoing
    /// winner: 0 = 人間。yaku は表示用文字列
    case win(winner: Int, tsumo: Bool, tile: Int, yaku: [String], points: String)
    case exhaustiveDraw(tenpaiPlayers: [Int])
}

@MainActor
final class MahjongGameState: ObservableObject {
    /// 各家の手牌(常にソート済み、人間=0)
    @Published var hands: [[Int]] = [[], [], [], []]
    /// 各家の河(捨て牌)
    @Published var rivers: [[Int]] = [[], [], [], []]
    @Published var wall: [Int] = []
    /// 人間がツモった牌(打牌するまで手牌とは別に表示)
    @Published var drawnTile: Int?
    @Published var phase: MahjongPhase = .finished
    @Published var result: MahjongResult = .ongoing
    @Published var message = "「新しい局」で配牌します。"
    @Published var canTsumo = false
    @Published var hintTile: Int?
    @Published var aiLevel: Difficulty = .easy
    /// 現在ツモっている家(演出用)
    @Published var activePlayer = 0

    private var moveToken = 0

    static let seatNames = ["あなた(東)", "南家", "西家", "北家"]

    var isHumanTurn: Bool { phase == .humanTurn && result == .ongoing }

    // MARK: - 局の開始

    func newGame() {
        moveToken += 1
        var w = MahjongTiles.shuffledWall()
        hands = (0..<4).map { _ in
            let hand = Array(w.suffix(13)).sorted()
            w.removeLast(13)
            return hand
        }
        wall = w
        rivers = [[], [], [], []]
        drawnTile = nil
        result = .ongoing
        hintTile = nil
        message = "配牌しました。牌をクリックすると捨てられます。同じ種類を集めて「3枚1組×4 + 対子」を目指しましょう。"
        humanDraw()
    }

    // MARK: - 人間の手番

    private func humanDraw() {
        activePlayer = 0
        guard let t = drawFromWall() else {
            finishExhaustiveDraw()
            return
        }
        drawnTile = t
        canTsumo = MahjongEngine.isWin(MahjongEngine.counts(of: hands[0] + [t]))
        phase = .humanTurn
        if canTsumo {
            message = "ツモ和了できます!「ツモ」ボタンでもいいし、続けることもできます。"
        }
    }

    /// 手牌 or ツモ牌をタップして捨てる
    func humanDiscard(_ tile: Int) {
        guard isHumanTurn else { return }
        var all = hands[0] + (drawnTile.map { [$0] } ?? [])
        guard let idx = all.firstIndex(of: tile) else { return }
        all.remove(at: idx)
        hands[0] = all.sorted()
        drawnTile = nil
        canTsumo = false
        hintTile = nil
        rivers[0].append(tile)

        // AI のロン(和了)チェック
        for p in 1...3 {
            if MahjongEngine.isWin(MahjongEngine.counts(of: hands[p] + [tile])) {
                finishWin(winner: p, tsumo: false, tile: tile)
                return
            }
        }
        runAITurns(from: 1)
    }

    func humanTsumo() {
        guard isHumanTurn, canTsumo, let t = drawnTile else { return }
        finishWin(winner: 0, tsumo: true, tile: t)
    }

    // MARK: - ロンの選択

    func acceptRon() {
        guard case .ronOffer(let tile, _) = phase else { return }
        finishWin(winner: 0, tsumo: false, tile: tile)
    }

    func declineRon() {
        guard case .ronOffer(_, let discarder) = phase else { return }
        runAITurns(from: discarder + 1)
    }

    // MARK: - AI の手番

    private func runAITurns(from start: Int) {
        phase = .aiPlaying
        moveToken += 1
        let token = moveToken
        let level = aiLevel
        Task { @MainActor in
            var player = start
            while player <= 3 {
                guard token == self.moveToken else { return }
                self.activePlayer = player
                try? await Task.sleep(nanoseconds: 550_000_000)
                guard token == self.moveToken else { return }

                guard let drawn = self.drawFromWall() else {
                    self.finishExhaustiveDraw()
                    return
                }
                let hand14 = self.hands[player] + [drawn]
                // ツモ和了
                if MahjongEngine.isWin(MahjongEngine.counts(of: hand14)) {
                    self.hands[player] = hand14.sorted()
                    self.finishWin(winner: player, tsumo: true, tile: drawn)
                    return
                }
                // 打牌
                let discard = MahjongEngine.chooseDiscard(hand14: hand14, level: level)
                var rest = hand14
                rest.remove(at: rest.firstIndex(of: discard)!)
                self.hands[player] = rest.sorted()
                self.rivers[player].append(discard)

                // 人間のロンチェック
                if MahjongEngine.isWin(MahjongEngine.counts(of: self.hands[0] + [discard])) {
                    self.phase = .ronOffer(tile: discard, discarder: player)
                    self.message = "\(Self.seatNames[player])の \(MahjongTiles.name(discard)) でロンできます!"
                    return
                }
                player += 1
            }
            guard token == self.moveToken else { return }
            self.humanDraw()
        }
    }

    private func drawFromWall() -> Int? {
        guard !wall.isEmpty else { return nil }
        return wall.removeLast()
    }

    // MARK: - 終局

    private func finishWin(winner: Int, tsumo: Bool, tile: Int) {
        moveToken += 1
        let handTiles: [Int]
        if winner == 0 {
            handTiles = hands[0] + [tile]          // ツモ牌もロン牌もまだ手牌に未合流
        } else if tsumo {
            handTiles = hands[winner]              // AI ツモは合流済み
        } else {
            handTiles = hands[winner] + [tile]     // AI ロンは捨て牌を加える
        }
        let c = MahjongEngine.counts(of: handTiles)
        let yaku = MahjongEngine.yakuList(counts: c, tsumo: tsumo)
        let totalHan = yaku.reduce(0) { $0 + $1.han }
        let points = MahjongEngine.pointsText(han: totalHan)
        let names = yaku.map { "\($0.name) \($0.han)翻" }

        // 表示用に和了牌を手牌へ合流させる
        if winner == 0 {
            hands[0] = (hands[0] + [tile]).sorted()
            drawnTile = nil
        } else if !tsumo {
            hands[winner] = (hands[winner] + [tile]).sorted()
        }
        phase = .finished
        result = .win(winner: winner, tsumo: tsumo, tile: tile,
                      yaku: names.isEmpty ? ["(役なし)"] : names,
                      points: points)
        canTsumo = false
    }

    private func finishExhaustiveDraw() {
        moveToken += 1
        let tenpai = (0..<4).filter { MahjongEngine.isTenpai(hands[$0]) }
        phase = .finished
        drawnTile = nil
        result = .exhaustiveDraw(tenpaiPlayers: tenpai)
    }

    // MARK: - ヒント

    func showHint() {
        guard isHumanTurn else { return }
        let hand14 = hands[0] + (drawnTile.map { [$0] } ?? [])
        guard hand14.count == 14 else { return }
        let snapshot = hand14
        Task.detached(priority: .userInitiated) {
            let discard = MahjongEngine.chooseDiscard(hand14: snapshot, level: .hard)
            var rest = snapshot
            rest.remove(at: rest.firstIndex(of: discard)!)
            let waits = MahjongEngine.waits(of: rest)
            await MainActor.run {
                self.hintTile = discard
                if waits.isEmpty {
                    self.message = "ヒント: \(MahjongTiles.name(discard)) を切るのが良さそうです。3枚1組(順子か刻子)になりにくい牌から捨てましょう。"
                } else {
                    let names = waits.map { MahjongTiles.name($0) }.joined(separator: "・")
                    self.message = "ヒント: \(MahjongTiles.name(discard)) を切ると聴牌!待ちは \(names) です。"
                }
            }
        }
    }
}

// MARK: - 途中保存

struct MahjongSave: Codable {
    var meta: SaveMeta
    var hands: [[Int]]
    var rivers: [[Int]]
    var wall: [Int]
    var drawnTile: Int?
    var aiLevel: Difficulty
}

extension MahjongGameState {
    /// 自分の打牌待ちのときだけ保存できる
    func makeSave() -> MahjongSave? {
        guard isHumanTurn else { return nil }
        return MahjongSave(meta: SaveMeta(savedAt: Date(),
                                          title: "捨て牌\(rivers[0].count)枚 · 山\(wall.count)枚"),
                           hands: hands,
                           rivers: rivers,
                           wall: wall,
                           drawnTile: drawnTile,
                           aiLevel: aiLevel)
    }

    func restore(from save: MahjongSave) {
        moveTokenBump()
        hands = save.hands
        rivers = save.rivers
        wall = save.wall
        drawnTile = save.drawnTile
        aiLevel = save.aiLevel
        hintTile = nil
        result = .ongoing
        activePlayer = 0
        canTsumo = drawnTile.map {
            MahjongEngine.isWin(MahjongEngine.counts(of: hands[0] + [$0]))
        } ?? false
        phase = .humanTurn
        message = "保存した局面から再開します。あなたの打牌からです。"
    }

    private func moveTokenBump() {
        moveToken += 1
    }
}
