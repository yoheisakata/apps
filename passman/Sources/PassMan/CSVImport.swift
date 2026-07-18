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
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count, chars[i + 1] == "\"" {
                        field.append("\"")
                        i += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(c)
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
                    field.append(c)
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
}
