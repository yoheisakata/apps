// MahjongEngine.swift — 麻雀のルールエンジン(入門ルール)
//
// 牌の種類 ID (0..33):
//   0..8   萬子 1〜9
//   9..17  筒子 1〜9
//   18..26 索子 1〜9
//   27..33 字牌(東南西北白發中)
//
// 入門ルールの簡略化:
//   - 鳴き(ポン・チー・カン)なし、リーチなし、ドラなし
//   - フリテンなし(学習用)
//   - 役がなくても和了できる(役は情報として表示)

import Foundation

enum MahjongTiles {
    static let honorNames = ["東", "南", "西", "北", "白", "發", "中"]

    static func name(_ t: Int) -> String {
        switch t {
        case 0..<9:   return "\(t + 1)萬"
        case 9..<18:  return "\(t - 8)筒"
        case 18..<27: return "\(t - 17)索"
        default:      return honorNames[t - 27]
        }
    }

    /// 数牌の数字(字牌は nil)
    static func number(_ t: Int) -> Int? {
        t < 27 ? t % 9 + 1 : nil
    }

    static func isHonor(_ t: Int) -> Bool { t >= 27 }
    static func isTerminal(_ t: Int) -> Bool {
        guard let n = number(t) else { return false }
        return n == 1 || n == 9
    }

    /// シャッフル済みの牌山(各34種×4枚 = 136枚)
    static func shuffledWall() -> [Int] {
        var wall: [Int] = []
        for t in 0..<34 { wall += [t, t, t, t] }
        return wall.shuffled()
    }
}

enum MahjongEngine {
    static func counts(of tiles: [Int]) -> [Int] {
        var c = [Int](repeating: 0, count: 34)
        for t in tiles { c[t] += 1 }
        return c
    }

    // MARK: - 和了判定

    /// 14枚(counts)が和了形か
    static func isWin(_ counts: [Int]) -> Bool {
        isStandardWin(counts) || isChiitoitsu(counts) || isKokushi(counts)
    }

    /// 4面子1雀頭
    static func isStandardWin(_ counts: [Int]) -> Bool {
        for pair in 0..<34 where counts[pair] >= 2 {
            var c = counts
            c[pair] -= 2
            if canFormMelds(&c, from: 0) { return true }
        }
        return false
    }

    private static func canFormMelds(_ c: inout [Int], from start: Int) -> Bool {
        var i = start
        while i < 34, c[i] == 0 { i += 1 }
        if i == 34 { return true }
        // 刻子
        if c[i] >= 3 {
            c[i] -= 3
            let ok = canFormMelds(&c, from: i)
            c[i] += 3
            if ok { return true }
        }
        // 順子(数牌のみ、スート境界を跨がない)
        if i < 27, i % 9 <= 6, c[i + 1] > 0, c[i + 2] > 0 {
            c[i] -= 1; c[i + 1] -= 1; c[i + 2] -= 1
            let ok = canFormMelds(&c, from: i)
            c[i] += 1; c[i + 1] += 1; c[i + 2] += 1
            if ok { return true }
        }
        return false
    }

    /// 七対子
    static func isChiitoitsu(_ counts: [Int]) -> Bool {
        var pairs = 0
        for c in counts {
            if c == 2 { pairs += 1 }
            else if c != 0 { return false }   // 4枚使い(同じ対子2組)は不可
        }
        return pairs == 7
    }

    /// 国士無双
    static func isKokushi(_ counts: [Int]) -> Bool {
        let orphans = [0, 8, 9, 17, 18, 26, 27, 28, 29, 30, 31, 32, 33]
        var hasPair = false
        for t in 0..<34 {
            if orphans.contains(t) {
                if counts[t] == 0 { return false }
                if counts[t] == 2 { hasPair = true }
                if counts[t] > 2 { return false }
            } else if counts[t] != 0 {
                return false
            }
        }
        return hasPair
    }

    /// 13枚の手牌の待ち(ツモ/ロンで和了できる牌)
    static func waits(of hand13: [Int]) -> [Int] {
        let base = counts(of: hand13)
        var result: [Int] = []
        for t in 0..<34 where base[t] < 4 {
            var c = base
            c[t] += 1
            if isWin(c) { result.append(t) }
        }
        return result
    }

    /// 聴牌か
    static func isTenpai(_ hand13: [Int]) -> Bool {
        !waits(of: hand13).isEmpty
    }

    // MARK: - 役判定(入門用サブセット)

    /// 和了形 counts(14枚)に対する役の一覧。(名前, 翻数)
    static func yakuList(counts: [Int], tsumo: Bool) -> [(name: String, han: Int)] {
        var result: [(String, Int)] = []

        if isKokushi(counts) {
            return [("国士無双(役満)", 13)]
        }

        if tsumo {
            result.append(("門前清自摸和(ツモ)", 1))
        }

        let chiitoi = isChiitoitsu(counts) && !isStandardWin(counts)
        if chiitoi {
            result.append(("七対子", 2))
        }

        // タンヤオ: 1・9・字牌なし
        var hasTerminalOrHonor = false
        for t in 0..<34 where counts[t] > 0 {
            if MahjongTiles.isHonor(t) || MahjongTiles.isTerminal(t) { hasTerminalOrHonor = true }
        }
        if !hasTerminalOrHonor {
            result.append(("断ヤオ九(タンヤオ)", 1))
        }

        // 役牌: 白發中の刻子(東は場風/自風の簡略扱いで加点)
        for t in 31...33 where counts[t] >= 3 {
            result.append(("役牌(\(MahjongTiles.honorNames[t - 27]))", 1))
        }
        if counts[27] >= 3 {
            result.append(("役牌(東)", 1))
        }

        // 対々和: 雀頭 + 刻子のみで構成できるか
        if !chiitoi {
            for pair in 0..<34 where counts[pair] >= 2 {
                var c = counts
                c[pair] -= 2
                if (0..<34).allSatisfy({ c[$0] % 3 == 0 }) {
                    result.append(("対々和(トイトイ)", 2))
                    break
                }
            }
        }

        // 混一色 / 清一色
        var suitsUsed = Set<Int>()
        var honorsUsed = false
        for t in 0..<34 where counts[t] > 0 {
            if t < 27 { suitsUsed.insert(t / 9) } else { honorsUsed = true }
        }
        if suitsUsed.count == 1 {
            result.append(honorsUsed ? ("混一色(ホンイツ)", 3) : ("清一色(チンイツ)", 6))
        }

        return result
    }

    /// 翻数 → だいたいの点数表示(入門用の簡略テーブル)
    static func pointsText(han: Int) -> String {
        switch han {
        case ..<1:  return "役なし(練習ルールなので和了OK)"
        case 1:     return "1翻 · 約1,000点"
        case 2:     return "2翻 · 約2,000点"
        case 3:     return "3翻 · 約3,900点"
        case 4:     return "4翻 · 約8,000点(満貫)"
        case 5:     return "5翻 · 8,000点(満貫)"
        case 6, 7:  return "\(han)翻 · 12,000点(跳満)"
        case 8...12: return "\(han)翻 · 16,000点(倍満)"
        default:    return "役満 · 32,000点"
        }
    }

    // MARK: - 打牌 AI

    /// 手牌の形の良さ(面子・対子・ターツを貪欲にカウント)
    static func handShapeScore(_ counts: [Int]) -> Int {
        var c = counts
        var score = 0
        // 刻子
        for i in 0..<34 where c[i] >= 3 { c[i] -= 3; score += 100 }
        // 順子
        for i in 0..<27 where i % 9 <= 6 {
            while c[i] > 0, c[i + 1] > 0, c[i + 2] > 0 {
                c[i] -= 1; c[i + 1] -= 1; c[i + 2] -= 1
                score += 100
            }
        }
        // 対子
        var pairUsed = false
        for i in 0..<34 where c[i] >= 2 {
            c[i] -= 2
            score += pairUsed ? 40 : 55    // 雀頭1つは大事、2つ目以降も価値あり
            pairUsed = true
        }
        // 両面・嵌張ターツ
        for i in 0..<27 where i % 9 <= 7 {
            while c[i] > 0, c[i + 1] > 0 {
                c[i] -= 1; c[i + 1] -= 1
                score += 35
            }
        }
        for i in 0..<27 where i % 9 <= 6 {
            while c[i] > 0, c[i + 2] > 0 {
                c[i] -= 1; c[i + 2] -= 1
                score += 28
            }
        }
        // 孤立した字牌・端牌はわずかに減点(自然に序盤に切られる)
        for i in 27..<34 where c[i] == 1 { score -= 8 }
        return score
    }

    /// 14枚から捨てる牌を選ぶ(hand14 はソート済みでなくて良い)
    static func chooseDiscard(hand14: [Int], level: Difficulty) -> Int {
        let unique = Array(Set(hand14))

        if level == .easy, Int.random(in: 0..<100) < 35 {
            // 入門: たまに適当に切る(ただし対子・刻子は温存)
            let c = counts(of: hand14)
            let singles = unique.filter { c[$0] == 1 }
            if let t = singles.randomElement() { return t }
            return hand14.randomElement()!
        }

        var bestTile = hand14[0]
        var bestScore = Int.min
        for t in unique {
            var c = counts(of: hand14)
            c[t] -= 1
            var score = handShapeScore(c)
            // 中級は聴牌チェックも(待ちが多い形を好む)
            if level == .hard {
                var remaining = hand14
                remaining.remove(at: remaining.firstIndex(of: t)!)
                let w = waits(of: remaining)
                if !w.isEmpty { score += 500 + w.count * 20 }
            }
            score += Int.random(in: 0...4)
            if score > bestScore {
                bestScore = score
                bestTile = t
            }
        }
        return bestTile
    }
}
