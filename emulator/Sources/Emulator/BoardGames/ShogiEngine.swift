// Engine.swift — 将棋のルールエンジン(盤面、合法手生成、王手・詰み判定)
//
// 座標系:
//   row 0 が盤の上端(後手陣)、row 8 が下端(先手陣)。
//   col 0 が左端。表示上の「筋」は右から 1..9 なので file = 9 - col。
//   先手(人間)は下から上へ(row が減る方向へ)進む。

import Foundation

enum Player: Int, Equatable, Codable {
    case sente = 0   // 先手(人間、下側)
    case gote = 1    // 後手(AI、上側)

    var opponent: Player { self == .sente ? .gote : .sente }
}

enum PieceType: Int, CaseIterable, Equatable, Codable {
    case pawn = 0    // 歩
    case lance       // 香
    case knight      // 桂
    case silver      // 銀
    case gold        // 金
    case bishop      // 角
    case rook        // 飛
    case king        // 玉

    var canPromote: Bool {
        switch self {
        case .gold, .king: return false
        default: return true
        }
    }
}

struct Piece: Equatable, Codable {
    var type: PieceType
    var player: Player
    var promoted: Bool = false
}

struct Square: Hashable, Codable {
    var row: Int
    var col: Int

    var isValid: Bool { row >= 0 && row < 9 && col >= 0 && col < 9 }
    var index: Int { row * 9 + col }
    /// 表示用の筋(右から 1..9)
    var file: Int { 9 - col }
    /// 表示用の段(上から 1..9)
    var rank: Int { row + 1 }
}

struct Move: Equatable, Codable {
    var from: Square?          // nil なら持ち駒を打つ
    var to: Square
    var pieceType: PieceType   // 動かす/打つ駒の種類(打つ場合は不成の種類)
    var promote: Bool = false

    var isDrop: Bool { from == nil }
}

/// 駒落ちの種類
enum Handicap: String, CaseIterable, Identifiable, Codable {
    case even       = "平手"
    case lance1     = "香落ち"
    case bishop1    = "角落ち"
    case rook1      = "飛車落ち"
    case twoPiece   = "二枚落ち"
    case fourPiece  = "四枚落ち"
    case sixPiece   = "六枚落ち"
    case eightPiece = "八枚落ち"

    var id: String { rawValue }

    /// 後手(上手 = AI)から取り除く駒の位置(row, col)
    var removedSquares: [Square] {
        switch self {
        case .even:       return []
        case .lance1:     return [Square(row: 0, col: 8)]                      // 1一香
        case .bishop1:    return [Square(row: 1, col: 7)]                      // 2二角
        case .rook1:      return [Square(row: 1, col: 1)]                      // 8二飛
        case .twoPiece:   return [Square(row: 1, col: 1), Square(row: 1, col: 7)]
        case .fourPiece:  return Handicap.twoPiece.removedSquares +
                                 [Square(row: 0, col: 0), Square(row: 0, col: 8)]
        case .sixPiece:   return Handicap.fourPiece.removedSquares +
                                 [Square(row: 0, col: 1), Square(row: 0, col: 7)]
        case .eightPiece: return Handicap.sixPiece.removedSquares +
                                 [Square(row: 0, col: 2), Square(row: 0, col: 6)]
        }
    }

    /// 駒落ちでは上手(AI = 後手側)が先に指す
    var goteMovesFirst: Bool { self != .even }
}

struct Position: Codable {
    /// 81 マス。index = row * 9 + col
    var board: [Piece?]
    /// 持ち駒の枚数 [player][pieceType]
    var hands: [[Int]]
    var sideToMove: Player

    subscript(_ sq: Square) -> Piece? {
        get { board[sq.index] }
        set { board[sq.index] = newValue }
    }

    func handCount(_ player: Player, _ type: PieceType) -> Int {
        hands[player.rawValue][type.rawValue]
    }

    // MARK: - 初期局面

    static func initial(handicap: Handicap = .even) -> Position {
        var board = [Piece?](repeating: nil, count: 81)

        let backRank: [PieceType] = [.lance, .knight, .silver, .gold, .king,
                                     .gold, .silver, .knight, .lance]
        for c in 0..<9 {
            board[0 * 9 + c] = Piece(type: backRank[c], player: .gote)
            board[8 * 9 + c] = Piece(type: backRank[c], player: .sente)
            board[2 * 9 + c] = Piece(type: .pawn, player: .gote)
            board[6 * 9 + c] = Piece(type: .pawn, player: .sente)
        }
        board[1 * 9 + 1] = Piece(type: .rook,   player: .gote)   // 8二飛
        board[1 * 9 + 7] = Piece(type: .bishop, player: .gote)   // 2二角
        board[7 * 9 + 1] = Piece(type: .bishop, player: .sente)  // 8八角
        board[7 * 9 + 7] = Piece(type: .rook,   player: .sente)  // 2八飛

        for sq in handicap.removedSquares {
            board[sq.index] = nil
        }

        return Position(board: board,
                        hands: [[Int]](repeating: [Int](repeating: 0, count: 8), count: 2),
                        sideToMove: handicap.goteMovesFirst ? .gote : .sente)
    }

    // MARK: - 駒の動き

    struct Vector {
        var dr: Int
        var dc: Int
        var slide: Bool
    }

    static func vectors(for piece: Piece) -> [Vector] {
        let f = piece.player == .sente ? -1 : 1   // 前方向

        func goldVectors() -> [Vector] {
            [Vector(dr: f, dc: -1, slide: false), Vector(dr: f, dc: 0, slide: false),
             Vector(dr: f, dc: 1, slide: false),  Vector(dr: 0, dc: -1, slide: false),
             Vector(dr: 0, dc: 1, slide: false),  Vector(dr: -f, dc: 0, slide: false)]
        }

        switch piece.type {
        case .pawn:
            return piece.promoted ? goldVectors() : [Vector(dr: f, dc: 0, slide: false)]
        case .lance:
            return piece.promoted ? goldVectors() : [Vector(dr: f, dc: 0, slide: true)]
        case .knight:
            return piece.promoted ? goldVectors()
                : [Vector(dr: 2 * f, dc: -1, slide: false), Vector(dr: 2 * f, dc: 1, slide: false)]
        case .silver:
            return piece.promoted ? goldVectors()
                : [Vector(dr: f, dc: -1, slide: false), Vector(dr: f, dc: 0, slide: false),
                   Vector(dr: f, dc: 1, slide: false),  Vector(dr: -f, dc: -1, slide: false),
                   Vector(dr: -f, dc: 1, slide: false)]
        case .gold:
            return goldVectors()
        case .bishop:
            var v = [Vector(dr: -1, dc: -1, slide: true), Vector(dr: -1, dc: 1, slide: true),
                     Vector(dr: 1, dc: -1, slide: true),  Vector(dr: 1, dc: 1, slide: true)]
            if piece.promoted {
                v += [Vector(dr: -1, dc: 0, slide: false), Vector(dr: 1, dc: 0, slide: false),
                      Vector(dr: 0, dc: -1, slide: false), Vector(dr: 0, dc: 1, slide: false)]
            }
            return v
        case .rook:
            var v = [Vector(dr: -1, dc: 0, slide: true), Vector(dr: 1, dc: 0, slide: true),
                     Vector(dr: 0, dc: -1, slide: true), Vector(dr: 0, dc: 1, slide: true)]
            if piece.promoted {
                v += [Vector(dr: -1, dc: -1, slide: false), Vector(dr: -1, dc: 1, slide: false),
                      Vector(dr: 1, dc: -1, slide: false),  Vector(dr: 1, dc: 1, slide: false)]
            }
            return v
        case .king:
            return [Vector(dr: -1, dc: -1, slide: false), Vector(dr: -1, dc: 0, slide: false),
                    Vector(dr: -1, dc: 1, slide: false),  Vector(dr: 0, dc: -1, slide: false),
                    Vector(dr: 0, dc: 1, slide: false),   Vector(dr: 1, dc: -1, slide: false),
                    Vector(dr: 1, dc: 0, slide: false),   Vector(dr: 1, dc: 1, slide: false)]
        }
    }

    // MARK: - 成り

    static func inPromotionZone(_ row: Int, _ player: Player) -> Bool {
        player == .sente ? row <= 2 : row >= 6
    }

    /// 行き所のない駒になるため必ず成る必要があるか
    static func mustPromote(type: PieceType, toRow: Int, player: Player) -> Bool {
        switch type {
        case .pawn, .lance:
            return player == .sente ? toRow == 0 : toRow == 8
        case .knight:
            return player == .sente ? toRow <= 1 : toRow >= 7
        default:
            return false
        }
    }

    // MARK: - 疑似合法手(自玉の王手放置チェックなし)

    private func movesWithPromotionVariants(piece: Piece, from: Square, to: Square) -> [Move] {
        let base = Move(from: from, to: to, pieceType: piece.type)
        guard !piece.promoted, piece.type.canPromote else { return [base] }

        if Position.mustPromote(type: piece.type, toRow: to.row, player: piece.player) {
            return [Move(from: from, to: to, pieceType: piece.type, promote: true)]
        }
        if Position.inPromotionZone(from.row, piece.player) || Position.inPromotionZone(to.row, piece.player) {
            return [base, Move(from: from, to: to, pieceType: piece.type, promote: true)]
        }
        return [base]
    }

    func pseudoBoardMoves(from: Square) -> [Move] {
        guard let piece = self[from], piece.player == sideToMove else { return [] }
        var result: [Move] = []
        for v in Position.vectors(for: piece) {
            var r = from.row + v.dr
            var c = from.col + v.dc
            while r >= 0, r < 9, c >= 0, c < 9 {
                let to = Square(row: r, col: c)
                if let occupant = self[to] {
                    if occupant.player != piece.player {
                        result += movesWithPromotionVariants(piece: piece, from: from, to: to)
                    }
                    break
                }
                result += movesWithPromotionVariants(piece: piece, from: from, to: to)
                if !v.slide { break }
                r += v.dr
                c += v.dc
            }
        }
        return result
    }

    /// 指定の筋に自分の不成の歩があるか(二歩チェック用)
    func hasUnpromotedPawn(player: Player, col: Int) -> Bool {
        for r in 0..<9 {
            if let p = board[r * 9 + col], p.player == player, p.type == .pawn, !p.promoted {
                return true
            }
        }
        return false
    }

    func pseudoDropMoves() -> [Move] {
        let player = sideToMove
        var result: [Move] = []
        for type in PieceType.allCases where type != .king {
            guard hands[player.rawValue][type.rawValue] > 0 else { continue }
            for r in 0..<9 {
                // 行き所のない駒は打てない
                if type == .pawn || type == .lance {
                    if player == .sente && r == 0 { continue }
                    if player == .gote && r == 8 { continue }
                }
                if type == .knight {
                    if player == .sente && r <= 1 { continue }
                    if player == .gote && r >= 7 { continue }
                }
                for c in 0..<9 {
                    let sq = Square(row: r, col: c)
                    guard self[sq] == nil else { continue }
                    if type == .pawn && hasUnpromotedPawn(player: player, col: c) { continue }
                    result.append(Move(from: nil, to: sq, pieceType: type))
                }
            }
        }
        return result
    }

    func pseudoMoves() -> [Move] {
        var result: [Move] = []
        for r in 0..<9 {
            for c in 0..<9 {
                let sq = Square(row: r, col: c)
                if let p = self[sq], p.player == sideToMove {
                    result += pseudoBoardMoves(from: sq)
                }
            }
        }
        result += pseudoDropMoves()
        return result
    }

    // MARK: - 手の適用

    func applying(_ m: Move) -> Position {
        var next = self
        if let from = m.from {
            guard var piece = next[from] else { return next }
            next[from] = nil
            if let captured = next[m.to] {
                next.hands[piece.player.rawValue][captured.type.rawValue] += 1
            }
            if m.promote { piece.promoted = true }
            next[m.to] = piece
        } else {
            next.hands[sideToMove.rawValue][m.pieceType.rawValue] -= 1
            next[m.to] = Piece(type: m.pieceType, player: sideToMove)
        }
        next.sideToMove = sideToMove.opponent
        return next
    }

    // MARK: - 王手・利き

    func kingSquare(of player: Player) -> Square? {
        for r in 0..<9 {
            for c in 0..<9 {
                if let p = board[r * 9 + c], p.type == .king, p.player == player {
                    return Square(row: r, col: c)
                }
            }
        }
        return nil
    }

    /// sq に player の駒の利きがあるか(利いている駒の位置を返す)
    func attackers(of sq: Square, by player: Player) -> [Square] {
        var result: [Square] = []
        for r in 0..<9 {
            for c in 0..<9 {
                guard let p = board[r * 9 + c], p.player == player else { continue }
                let from = Square(row: r, col: c)
                for v in Position.vectors(for: p) {
                    var rr = from.row + v.dr
                    var cc = from.col + v.dc
                    while rr >= 0, rr < 9, cc >= 0, cc < 9 {
                        if rr == sq.row && cc == sq.col {
                            result.append(from)
                            break
                        }
                        if board[rr * 9 + cc] != nil { break }
                        if !v.slide { break }
                        rr += v.dr
                        cc += v.dc
                    }
                }
            }
        }
        return result
    }

    func isAttacked(_ sq: Square, by player: Player) -> Bool {
        !attackers(of: sq, by: player).isEmpty
    }

    func isInCheck(_ player: Player) -> Bool {
        guard let king = kingSquare(of: player) else { return false }
        return isAttacked(king, by: player.opponent)
    }

    // MARK: - 合法手

    /// 完全な合法手(王手放置・打ち歩詰めを除外)
    func legalMoves(checkUchifuzume: Bool = true) -> [Move] {
        var result: [Move] = []
        for m in pseudoMoves() {
            let next = applying(m)
            if next.isInCheck(sideToMove) { continue }   // 自玉の王手放置
            if checkUchifuzume, m.isDrop, m.pieceType == .pawn,
               next.isInCheck(next.sideToMove) {
                // 打ち歩詰め: 歩を打った王手で相手に応手がなければ反則
                if next.legalMoves(checkUchifuzume: false).isEmpty { continue }
            }
            result.append(m)
        }
        return result
    }

    func legalMoves(from: Square) -> [Move] {
        legalMoves().filter { $0.from == from }
    }

    func legalDrops(of type: PieceType) -> [Move] {
        legalMoves().filter { $0.isDrop && $0.pieceType == type }
    }
}

// MARK: - 表記

enum Notation {
    static let fullWidthDigits = ["０", "１", "２", "３", "４", "５", "６", "７", "８", "９"]
    static let rankKanji = ["一", "二", "三", "四", "五", "六", "七", "八", "九"]

    static func kanji(for piece: Piece) -> String {
        if piece.promoted {
            switch piece.type {
            case .pawn:   return "と"
            case .lance:  return "杏"
            case .knight: return "圭"
            case .silver: return "全"
            case .bishop: return "馬"
            case .rook:   return "龍"
            default:      return "?"
            }
        }
        switch piece.type {
        case .pawn:   return "歩"
        case .lance:  return "香"
        case .knight: return "桂"
        case .silver: return "銀"
        case .gold:   return "金"
        case .bishop: return "角"
        case .rook:   return "飛"
        case .king:   return piece.player == .sente ? "玉" : "王"
        }
    }

    static func baseKanji(for type: PieceType) -> String {
        kanji(for: Piece(type: type, player: .sente))
    }

    /// ▲７六歩 のような棋譜表記
    static func describe(_ move: Move, in position: Position) -> String {
        let mark = position.sideToMove == .sente ? "▲" : "△"
        let square = fullWidthDigits[move.to.file] + rankKanji[move.to.rank - 1]
        let pieceName: String
        if let from = move.from, let piece = position[from] {
            pieceName = kanji(for: piece)
        } else {
            pieceName = baseKanji(for: move.pieceType)
        }
        var suffix = ""
        if move.promote { suffix = "成" }
        if move.isDrop { suffix = "打" }
        return mark + square + pieceName + suffix
    }
}

// MARK: - 駒の説明(学習用)

enum PieceGuide {
    static func text(for piece: Piece) -> String {
        if piece.promoted {
            switch piece.type {
            case .pawn:   return "と金: 成った歩。金と同じ動きができます。取られても相手には「歩」としてしか使えないのでとても得な駒です。"
            case .lance:  return "成香: 金と同じ動きができます。"
            case .knight: return "成桂: 金と同じ動きができます。"
            case .silver: return "成銀: 金と同じ動きができます。"
            case .bishop: return "馬: 角の動きに加えて上下左右に1マス動けます。攻守に強い駒です。"
            case .rook:   return "龍: 飛車の動きに加えて斜めに1マス動けます。最強の駒です。"
            default:      return ""
            }
        }
        switch piece.type {
        case .pawn:   return "歩: 前に1マスだけ進めます。同じ筋に2枚打つ「二歩」は反則です。敵陣で成ると「と金」になります。"
        case .lance:  return "香車: 前にまっすぐ何マスでも進めます。後ろには戻れないので突っ込みすぎに注意。"
        case .knight: return "桂馬: 前方に2マス進んだ左右どちらかへ跳べます。駒を飛び越せる唯一の駒。後ろには戻れません。"
        case .silver: return "銀: 前と斜めに1マス動けます。横と真後ろには動けません。攻めの主役になりやすい駒です。"
        case .gold:   return "金: 前・横・斜め前・後ろに1マス動けます。斜め後ろには動けません。玉を守る要の駒です。"
        case .bishop: return "角: 斜めに何マスでも進めます。敵陣で成ると「馬」になります。"
        case .rook:   return "飛車: 縦横に何マスでも進めます。敵陣で成ると「龍」になります。攻めの大黒柱です。"
        case .king:   return "玉: 全方向に1マス動けます。取られたら負けなので、囲いを作って守りましょう。"
        }
    }
}
