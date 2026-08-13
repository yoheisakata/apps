import Foundation

struct ImportSummary {
    var imported: Int
    var skipped: Int
}

/// RFC 4180 準拠の最小 CSV パーサーと、パスワード管理ソフトのエクスポート列名マッピング。
/// Chrome / Safari / 1Password / Bitwarden など、ヘッダー付き CSV を想定する。
enum CSV {
    /// CSV テキストを行×列に分解する。ダブルクォート囲み・エスケープ("")・改行(\n, \r\n)対応。
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var record: [String] = []
        var inQuotes = false
        // CRLF(\r\n)は Swift だと 1 つの書記素クラスターに結合され、Character 単位の
        // 比較では "\r" とも "\n" とも一致しない。Excel 等の CRLF 改行を確実に扱うため、
        // Unicode スカラー単位で走査する(結合を回避)。
        let chars = Array(text.unicodeScalars)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.unicodeScalars.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.unicodeScalars.append(c)
                }
            } else {
                switch c {
                case "\"":
                    inQuotes = true
                case ",":
                    record.append(field); field = ""
                case "\r":
                    if i + 1 < chars.count, chars[i + 1] == "\n" { i += 1 }
                    record.append(field); field = ""
                    rows.append(record); record = []
                case "\n":
                    record.append(field); field = ""
                    rows.append(record); record = []
                default:
                    field.unicodeScalars.append(c)
                }
            }
            i += 1
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            rows.append(record)
        }
        return rows
    }

    // 列名(小文字化・trim 済み)のエイリアス表。よくあるエクスポート形式を広めに拾う。
    static let titleAliases   = ["title", "name", "account", "サービス", "タイトル", "名前"]
    static let usernameAliases = ["username", "user", "login", "login_username", "login name", "email", "e-mail", "ユーザー名", "ログイン名", "メール", "メールアドレス", "ユーザ名"]
    static let passwordAliases = ["password", "pass", "login_password", "パスワード"]
    static let urlAliases     = ["url", "website", "web site", "login_uri", "uri", "link", "ウェブサイト", "サイト", "リンク"]
    static let noteAliases    = ["note", "notes", "memo", "comment", "comments", "メモ", "備考", "ノート"]
    static let hintAliases    = ["hint", "password hint", "ヒント"]
    static let categoryAliases = ["category", "folder", "group", "type", "grouping", "カテゴリ", "カテゴリー", "フォルダ", "グループ", "分類"]

    /// ヘッダー文字列を正規化(前後空白除去・小文字化・BOM 除去)。
    static func normalize(_ s: String) -> String {
        s.replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    /// CSV ファイルのバイト列を、エンコーディングを自動判定してテキストに変換する。
    /// Excel / Numbers / 各種パスワードマネージャーが書き出す日本語 CSV は UTF-8 決め打ちでは
    /// 読めない(UTF-16 だとヘッダーすら壊れ、Shift-JIS だと日本語が化ける)ため、
    /// BOM → UTF-8 妥当性 → Shift-JIS(CP932) → UTF-16 の順で判定する。
    static func decodeText(from data: Data) -> String {
        // 1) BOM による明示的判定
        if data.starts(with: [0xEF, 0xBB, 0xBF]) {
            return String(decoding: data.dropFirst(3), as: UTF8.self)
        }
        if data.starts(with: [0xFF, 0xFE]) {
            if let s = String(data: data, encoding: .utf16LittleEndian) { return stripBOM(s) }
        }
        if data.starts(with: [0xFE, 0xFF]) {
            if let s = String(data: data, encoding: .utf16BigEndian) { return stripBOM(s) }
        }
        // 2) BOM 無し: まず正しい UTF-8 かどうか(不正バイトがあれば別候補へ)
        if let s = String(data: data, encoding: .utf8) { return s }
        // 3) UTF-8 でないなら日本語 CSV でよくある Shift-JIS(CP932) を試す
        let cp932 = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosJapanese.rawValue))
        if let s = String(data: data, encoding: String.Encoding(rawValue: cp932)) { return s }
        if let s = String(data: data, encoding: .shiftJIS) { return s }
        // 4) BOM 無しの UTF-16(ヌルバイトが多い)を LE/BE 両方試す
        if let s = String(data: data, encoding: .utf16LittleEndian) { return stripBOM(s) }
        if let s = String(data: data, encoding: .utf16BigEndian) { return stripBOM(s) }
        // 5) 最終手段: 不正バイトは置換してでも UTF-8 として読む
        return String(decoding: data, as: UTF8.self)
    }

    private static func stripBOM(_ s: String) -> String {
        s.hasPrefix("\u{FEFF}") ? String(s.dropFirst()) : s
    }
}
