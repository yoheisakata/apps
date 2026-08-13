// ChessEngine.swift — チェスのルールエンジン
//
// 座標系: row 0 が盤の上端(黒陣)、row 7 が下端(白陣)。col 0 が左端 = a ファイル。
// 白(人間)は row が減る方向へ進む。キャスリング・アンパッサン・プロモーション対応。

import Foundation

enum ChessColor: Int, Equatable, Codable {
    case white = 0
    case black = 1

    var opponent: ChessColor { self == .white ? .black : .white }
    var name: String { self == .white ? "白" : "黒" }
}

enum ChessPieceKind: Int, CaseIterable, Equatable, Codable {
    case pawn = 0, knight, bishop, rook, queen, king

    var glyph: String {
        switch self {
        case .pawn:   return "♟"
        case .knight: return "♞"
        case .bishop: return "♝"
        case .rook:   return "♜"
        case .queen:  return "♛"
        case .king:   return "♚"
        }
    }

    var japaneseName: String {
        switch self {
        case .pawn:   return "ポーン"
        case .knight: return "ナイト"
        case .bishop: return "ビショップ"
        case .rook:   return "ルーク"
        case .queen:  return "クイーン"
        case .king:   return "キング"
        }
    }
}

struct ChessPiece: Equatable, Codable {
    var kind: ChessPieceKind
    var color: ChessColor
    var hasMoved: Bool = false
}

struct ChessSquare: Hashable, Codable {
    var row: Int
    var col: Int

    var isValid: Bool { row >= 0 && row < 8 && col >= 0 && col < 8 }
    var index: Int { row * 8 + col }
    /// "e4" のような代数表記
    var name: String {
        let file = Character(UnicodeScalar(97 + col)!)   // a-h
        return "\(file)\(8 - row)"
    }
}

struct ChessMove: Equatable, Codable {
    var from: ChessSquare
    var to: ChessSquare
    var promotion: ChessPieceKind? = nil
}

struct ChessPosition: Codable {
    var board: [ChessPiece?]           // 64 マス。index = row * 8 + col
    var sideToMove: ChessColor
    /// 直前の 2 マス進みで通過したマス(アンパッサンで取れる位置)
    var enPassantTarget: ChessSquare?

    subscript(_ sq: ChessSquare) -> ChessPiece? {
        get { board[sq.index] }
        set { board[sq.index] = newValue }
    }

    static func initial() -> ChessPosition {
        var board = [ChessPiece?](repeating: nil, count: 64)
        let back: [ChessPieceKind] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for c in 0..<8 {
            board[0 * 8 + c] = ChessPiece(kind: back[c], color: .black)
            board[1 * 8 + c] = ChessPiece(kind: .pawn, color: .black)
            board[6 * 8 + c] = ChessPiece(kind: .pawn, color: .white)
            board[7 * 8 + c] = ChessPiece(kind: back[c], color: .white)
        }
        return ChessPosition(board: board, sideToMove: .white, enPassantTarget: nil)
    }

    // MARK: - 利き

    private static let knightOffsets = [(-2, -1), (-2, 1), (-1, -2), (-1, 2),
                                        (1, -2), (1, 2), (2, -1), (2, 1)]
    private static let kingOffsets = [(-1, -1), (-1, 0), (-1, 1), (0, -1),
                                      (0, 1), (1, -1), (1, 0), (1, 1)]
    private static let bishopDirs = [(-1, -1), (-1, 1), (1, -1), (1, 1)]
    private static let rookDirs = [(-1, 0), (1, 0), (0, -1), (0, 1)]

    /// sq に color の駒の利きがあるか
    func isAttacked(_ sq: ChessSquare, by color: ChessColor) -> Bool {
        // ポーン
        let pawnDir = color == .white ? 1 : -1   // 攻撃元は sq から見て pawnDir 側にいる
        for dc in [-1, 1] {
            let from = ChessSquare(row: sq.row + pawnDir, col: sq.col + dc)
            if from.isValid, let p = self[from], p.color == color, p.kind == .pawn {
                return true
            }
        }
        // ナイト
        for (dr, dc) in Self.knightOffsets {
            let from = ChessSquare(row: sq.row + dr, col: sq.col + dc)
            if from.isValid, let p = self[from], p.color == color, p.kind == .knight {
                return true
            }
        }
        // キング
        for (dr, dc) in Self.kingOffsets {
            let from = ChessSquare(row: sq.row + dr, col: sq.col + dc)
            if from.isValid, let p = self[from], p.color == color, p.kind == .king {
                return true
            }
        }
        // 斜めの走り(ビショップ・クイーン)
        for (dr, dc) in Self.bishopDirs {
            var r = sq.row + dr, c = sq.col + dc
            while r >= 0, r < 8, c >= 0, c < 8 {
                if let p = board[r * 8 + c] {
                    if p.color == color && (p.kind == .bishop || p.kind == .queen) { return true }
                    break
                }
                r += dr; c += dc
            }
        }
        // 縦横の走り(ルーク・クイーン)
        for (dr, dc) in Self.rookDirs {
            var r = sq.row + dr, c = sq.col + dc
            while r >= 0, r < 8, c >= 0, c < 8 {
                if let p = board[r * 8 + c] {
                    if p.color == color && (p.kind == .rook || p.kind == .queen) { return true }
                    break
                }
                r += dr; c += dc
            }
        }
        return false
    }

    func kingSquare(of color: ChessColor) -> ChessSquare? {
        for i in 0..<64 {
            if let p = board[i], p.kind == .king, p.color == color {
                return ChessSquare(row: i / 8, col: i % 8)
            }
        }
        return nil
    }

    func isInCheck(_ color: ChessColor) -> Bool {
        guard let king = kingSquare(of: color) else { return false }
        return isAttacked(king, by: color.opponent)
    }

    // MARK: - 疑似合法手

    private func pawnMoves(from: ChessSquare, piece: ChessPiece, into result: inout [ChessMove]) {
        let dir = piece.color == .white ? -1 : 1
        let startRow = piece.color == .white ? 6 : 1
        let promoRow = piece.color == .white ? 0 : 7

        func add(_ to: ChessSquare) {
            if to.row == promoRow {
                for kind: ChessPieceKind in [.queen, .rook, .bishop, .knight] {
                    result.append(ChessMove(from: from, to: to, promotion: kind))
                }
            } else {
                result.append(ChessMove(from: from, to: to))
            }
        }

        // 前進
        let one = ChessSquare(row: from.row + dir, col: from.col)
        if one.isValid, self[one] == nil {
            add(one)
            let two = ChessSquare(row: from.row + 2 * dir, col: from.col)
            if from.row == startRow, self[two] == nil {
                result.append(ChessMove(from: from, to: two))
            }
        }
        // 斜め取り(アンパッサン含む)
        for dc in [-1, 1] {
            let to = ChessSquare(row: from.row + dir, col: from.col + dc)
            guard to.isValid else { continue }
            if let target = self[to], target.color != piece.color {
                add(to)
            } else if self[to] == nil, to == enPassantTarget {
                result.append(ChessMove(from: from, to: to))
            }
        }
    }

    func pseudoMoves(from: ChessSquare) -> [ChessMove] {
        guard let piece = self[from], piece.color == sideToMove else { return [] }
        var result: [ChessMove] = []

        switch piece.kind {
        case .pawn:
            pawnMoves(from: from, piece: piece, into: &result)
        case .knight, .king:
            let offsets = piece.kind == .knight ? Self.knightOffsets : Self.kingOffsets
            for (dr, dc) in offsets {
                let to = ChessSquare(row: from.row + dr, col: from.col + dc)
                guard to.isValid else { continue }
                if let target = self[to], target.color == piece.color { continue }
                result.append(ChessMove(from: from, to: to))
            }
            if piece.kind == .king { castlingMoves(from: from, piece: piece, into: &result) }
        case .bishop, .rook, .queen:
            let dirs: [(Int, Int)]
            switch piece.kind {
            case .bishop: dirs = Self.bishopDirs
            case .rook:   dirs = Self.rookDirs
            default:      dirs = Self.bishopDirs + Self.rookDirs
            }
            for (dr, dc) in dirs {
                var r = from.row + dr, c = from.col + dc
                while r >= 0, r < 8, c >= 0, c < 8 {
                    let to = ChessSquare(row: r, col: c)
                    if let target = self[to] {
                        if target.color != piece.color {
                            result.append(ChessMove(from: from, to: to))
                        }
                        break
                    }
                    result.append(ChessMove(from: from, to: to))
                    r += dr; c += dc
                }
            }
        }
        return result
    }

    private func castlingMoves(from: ChessSquare, piece: ChessPiece, into result: inout [ChessMove]) {
        guard !piece.hasMoved, !isInCheck(piece.color) else { return }
        let row = from.row
        let enemy = piece.color.opponent

        // キングサイド(右)
        if let rook = self[ChessSquare(row: row, col: 7)],
           rook.kind == .rook, rook.color == piece.color, !rook.hasMoved,
           board[row * 8 + 5] == nil, board[row * 8 + 6] == nil,
           !isAttacked(ChessSquare(row: row, col: 5), by: enemy),
           !isAttacked(ChessSquare(row: row, col: 6), by: enemy) {
            result.append(ChessMove(from: from, to: ChessSquare(row: row, col: 6)))
        }
        // クイーンサイド(左)
        if let rook = self[ChessSquare(row: row, col: 0)],
           rook.kind == .rook, rook.color == piece.color, !rook.hasMoved,
           board[row * 8 + 1] == nil, board[row * 8 + 2] == nil, board[row * 8 + 3] == nil,
           !isAttacked(ChessSquare(row: row, col: 3), by: enemy),
           !isAttacked(ChessSquare(row: row, col: 2), by: enemy) {
            result.append(ChessMove(from: from, to: ChessSquare(row: row, col: 2)))
        }
    }

    func pseudoMoves() -> [ChessMove] {
        var result: [ChessMove] = []
        for i in 0..<64 {
            if let p = board[i], p.color == sideToMove {
                result += pseudoMoves(from: ChessSquare(row: i / 8, col: i % 8))
            }
        }
        return result
    }

    // MARK: - 適用

    func applying(_ m: ChessMove) -> ChessPosition {
        var next = self
        guard var piece = next[m.from] else { return next }
        next[m.from] = nil

        // アンパッサン: 斜めに動いて行き先が空ならポーンを除去
        if piece.kind == .pawn, m.to.col != m.from.col, next[m.to] == nil {
            next[ChessSquare(row: m.from.row, col: m.to.col)] = nil
        }
        // キャスリング: キングが 2 マス動いたらルークも動かす
        if piece.kind == .king, abs(m.to.col - m.from.col) == 2 {
            let row = m.from.row
            if m.to.col == 6 {
                var rook = next[ChessSquare(row: row, col: 7)]
                rook?.hasMoved = true
                next[ChessSquare(row: row, col: 7)] = nil
                next[ChessSquare(row: row, col: 5)] = rook
            } else {
                var rook = next[ChessSquare(row: row, col: 0)]
                rook?.hasMoved = true
                next[ChessSquare(row: row, col: 0)] = nil
                next[ChessSquare(row: row, col: 3)] = rook
            }
        }

        // 次のアンパッサン対象
        if piece.kind == .pawn, abs(m.to.row - m.from.row) == 2 {
            next.enPassantTarget = ChessSquare(row: (m.from.row + m.to.row) / 2, col: m.from.col)
        } else {
            next.enPassantTarget = nil
        }

        piece.hasMoved = true
        if let promo = m.promotion { piece.kind = promo }
        next[m.to] = piece
        next.sideToMove = sideToMove.opponent
        return next
    }

    // MARK: - 合法手

    func legalMoves() -> [ChessMove] {
        pseudoMoves().filter { !applying($0).isInCheck(sideToMove) }
    }

    func legalMoves(from: ChessSquare) -> [ChessMove] {
        pseudoMoves(from: from).filter { !applying($0).isInCheck(sideToMove) }
    }

    /// 駒数が極端に少ない場合のドロー(K vs K、K+B/N vs K)
    var isInsufficientMaterial: Bool {
        var minors = 0
        for p in board.compactMap({ $0 }) {
            switch p.kind {
            case .king: continue
            case .bishop, .knight: minors += 1
            default: return false
            }
        }
        return minors <= 1
    }
}

// MARK: - 表記

enum ChessNotation {
    /// "♘ g1→f3" / "♟ e5×d4" のような簡易表記
    static func describe(_ m: ChessMove, in position: ChessPosition) -> String {
        guard let piece = position[m.from] else { return "?" }
        let mark = piece.color == .white ? "白" : "黒"
        let isCapture = position[m.to] != nil
            || (piece.kind == .pawn && m.to.col != m.from.col)
        let sep = isCapture ? "×" : "→"
        var s = "\(mark)\(piece.kind.glyph) \(m.from.name)\(sep)\(m.to.name)"
        if piece.kind == .king && abs(m.to.col - m.from.col) == 2 {
            s = "\(mark) \(m.to.col == 6 ? "O-O(キャスリング)" : "O-O-O(キャスリング)")"
        }
        if let promo = m.promotion {
            s += "=\(promo.glyph)"
        }
        return s
    }
}

// MARK: - 駒の説明(学習用)

enum ChessPieceGuide {
    static func text(for piece: ChessPiece) -> String {
        switch piece.kind {
        case .pawn:   return "ポーン: 前に1マス(初期位置からは2マス)進みます。取るときだけ斜め前。昇格とアンパッサンという特殊ルールがあります。"
        case .knight: return "ナイト: 2+1 の L 字に跳びます。駒を飛び越せる唯一の駒。将棋の桂馬と違い8方向へ動けます。"
        case .bishop: return "ビショップ: 斜めに何マスでも。同じ色のマスから移動できないので2枚で補い合います。"
        case .rook:   return "ルーク: 縦横に何マスでも。キングとの入れ替わり(キャスリング)で守りにも使えます。"
        case .queen:  return "クイーン: 縦横斜めに何マスでも動ける最強の駒。序盤から出しすぎると狙われるので注意。"
        case .king:   return "キング: 全方向に1マス。チェックメイトされたら負け。キャスリングで安全地帯へ移しましょう。"
        }
    }
}
