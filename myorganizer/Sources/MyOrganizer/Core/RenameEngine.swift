import Foundation

// MARK: - ルール定義

enum RuleKind: String, CaseIterable, Identifiable, Codable {
    case replace, addText, sequence, addDate, insertMetadata
    case changeCase, removeChars, truncate, cleanup, windowsSafe, changeExtension
    var id: String { rawValue }

    var label: String {
        switch self {
        case .replace: return "検索と置換"
        case .addText: return "テキストを追加"
        case .sequence: return "連番を追加"
        case .addDate: return "日付を追加"
        case .insertMetadata: return "メタデータを挿入"
        case .changeCase: return "大文字・小文字"
        case .removeChars: return "文字を削除"
        case .truncate: return "名前を切り詰め"
        case .cleanup: return "クリーンアップ"
        case .windowsSafe: return "Windows互換名に変換"
        case .changeExtension: return "拡張子を変更"
        }
    }

    var icon: String {
        switch self {
        case .replace: return "magnifyingglass"
        case .addText: return "textformat"
        case .sequence: return "number"
        case .addDate: return "calendar"
        case .insertMetadata: return "music.note"
        case .changeCase: return "textformat.size"
        case .removeChars: return "scissors"
        case .truncate: return "arrow.right.to.line"
        case .cleanup: return "sparkles"
        case .windowsSafe: return "pc"
        case .changeExtension: return "doc.badge.gearshape"
        }
    }
}

enum InsertPosition: String, CaseIterable, Identifiable, Codable {
    case prefix, suffix, atIndex
    var id: String { rawValue }
    var label: String {
        switch self {
        case .prefix: return "先頭"
        case .suffix: return "末尾"
        case .atIndex: return "位置指定"
        }
    }
}

enum CaseStyle: String, CaseIterable, Identifiable, Codable {
    case lower, upper, capitalized
    var id: String { rawValue }
    var label: String {
        switch self {
        case .lower: return "すべて小文字"
        case .upper: return "すべて大文字"
        case .capitalized: return "単語の先頭を大文字"
        }
    }
}

enum RemoveFrom: String, CaseIterable, Identifiable, Codable {
    case start, end
    var id: String { rawValue }
    var label: String { self == .start ? "先頭から" : "末尾から" }
}

enum DateSource: String, CaseIterable, Identifiable, Codable {
    case modified, created, exif, now
    var id: String { rawValue }
    var label: String {
        switch self {
        case .modified: return "変更日"
        case .created: return "作成日"
        case .exif: return "EXIF撮影日"
        case .now: return "現在日時"
        }
    }
}

enum MetadataField: String, CaseIterable, Identifiable, Codable {
    case title, artist, album, track, pixelSize
    var id: String { rawValue }
    var label: String {
        switch self {
        case .title: return "曲名・タイトル"
        case .artist: return "アーティスト"
        case .album: return "アルバム"
        case .track: return "トラック番号"
        case .pixelSize: return "画像サイズ (幅x高さ)"
        }
    }
}

struct FileMetadata {
    var exifDate: Date?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var title: String?
    var artist: String?
    var album: String?
    var track: Int?
}

struct RenameRule: Identifiable, Equatable, Codable {
    var id = UUID()
    var kind: RuleKind
    var enabled = true

    /// このルールの適用対象を拡張子で絞り込む（カンマ区切り、空 = すべて）
    var filterExtensions = ""

    // 検索と置換
    var searchText = ""
    var replaceText = ""
    var useRegex = false
    var caseInsensitive = false

    // テキストを追加
    var insertText = ""
    var insertPosition: InsertPosition = .prefix
    var insertIndex = 0

    // 連番
    var seqStart = 1
    var seqStep = 1
    var seqDigits = 2
    var seqPosition: InsertPosition = .suffix
    var seqSeparator = "_"

    // 日付
    var dateSource: DateSource = .modified
    var dateFormat = "yyyyMMdd"
    var datePosition: InsertPosition = .prefix
    var dateSeparator = "_"

    // メタデータ
    var metaField: MetadataField = .title
    var metaPosition: InsertPosition = .suffix
    var metaSeparator = "_"

    // 大文字・小文字
    var caseStyle: CaseStyle = .lower

    // 文字を削除
    var removeCount = 1
    var removeFrom: RemoveFrom = .start

    // 名前を切り詰め
    var truncateKeep = 10
    var truncateFrom: RemoveFrom = .start

    // クリーンアップ
    var cleanTrim = true
    var cleanCollapse = true
    var cleanUnderscoreToSpace = false
    var cleanSpaceToUnderscore = false

    // Windows互換名
    var winReplacement = "_"

    // 拡張子
    var newExtension = ""

    var needsMetadata: Bool {
        kind == .insertMetadata || (kind == .addDate && dateSource == .exif)
    }

    func matchesFilter(ext: String) -> Bool {
        let f = filterExtensions.trimmingCharacters(in: .whitespaces)
        guard !f.isEmpty else { return true }
        let set = Set(f.lowercased()
            .split(whereSeparator: { $0 == "," || $0 == " " })
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : String($0) })
        return set.contains(ext.lowercased())
    }

    /// base(拡張子を除く名前) と ext に対してルールを適用する
    func apply(base: String, ext: String, seqIndex: Int, item: FileItem, meta: FileMetadata?) -> (String, String) {
        var base = base
        var ext = ext
        switch kind {
        case .replace:
            guard !searchText.isEmpty else { break }
            if useRegex {
                var options: NSRegularExpression.Options = []
                if caseInsensitive { options.insert(.caseInsensitive) }
                if let re = try? NSRegularExpression(pattern: searchText, options: options) {
                    let range = NSRange(base.startIndex..., in: base)
                    base = re.stringByReplacingMatches(in: base, options: [], range: range, withTemplate: replaceText)
                }
            } else {
                let options: String.CompareOptions = caseInsensitive ? [.caseInsensitive] : []
                base = base.replacingOccurrences(of: searchText, with: replaceText, options: options)
            }
        case .addText:
            guard !insertText.isEmpty else { break }
            switch insertPosition {
            case .prefix: base = insertText + base
            case .suffix: base = base + insertText
            case .atIndex:
                let i = min(max(0, insertIndex), base.count)
                let idx = base.index(base.startIndex, offsetBy: i)
                base.insert(contentsOf: insertText, at: idx)
            }
        case .sequence:
            let n = seqStart + seqIndex * seqStep
            let num = String(format: "%0\(max(1, seqDigits))d", n)
            if seqPosition == .prefix {
                base = num + seqSeparator + base
            } else {
                base = base + seqSeparator + num
            }
        case .addDate:
            let maybeDate: Date?
            switch dateSource {
            case .modified: maybeDate = item.modDate
            case .created: maybeDate = item.createDate
            case .now: maybeDate = Date()
            case .exif: maybeDate = meta?.exifDate
            }
            guard let date = maybeDate else { break }
            let f = DateFormatter()
            f.dateFormat = dateFormat.isEmpty ? "yyyyMMdd" : dateFormat
            let s = f.string(from: date)
            base = datePosition == .prefix ? s + dateSeparator + base : base + dateSeparator + s
        case .insertMetadata:
            guard let meta else { break }
            var value: String?
            switch metaField {
            case .title: value = meta.title
            case .artist: value = meta.artist
            case .album: value = meta.album
            case .track:
                if let t = meta.track { value = String(format: "%02d", t) }
            case .pixelSize:
                if let w = meta.pixelWidth, let h = meta.pixelHeight { value = "\(w)x\(h)" }
            }
            guard var v = value, !v.isEmpty else { break }
            // ファイル名に使えない文字を除去
            v = v.replacingOccurrences(of: "/", with: "-")
                 .replacingOccurrences(of: ":", with: "-")
            base = metaPosition == .prefix ? v + metaSeparator + base : base + metaSeparator + v
        case .changeCase:
            switch caseStyle {
            case .lower: base = base.lowercased()
            case .upper: base = base.uppercased()
            case .capitalized: base = base.capitalized
            }
        case .removeChars:
            let n = max(0, removeCount)
            base = removeFrom == .start ? String(base.dropFirst(n)) : String(base.dropLast(n))
        case .truncate:
            let n = max(1, truncateKeep)
            base = truncateFrom == .start ? String(base.prefix(n)) : String(base.suffix(n))
        case .cleanup:
            if cleanUnderscoreToSpace { base = base.replacingOccurrences(of: "_", with: " ") }
            if cleanCollapse {
                while base.contains("  ") { base = base.replacingOccurrences(of: "  ", with: " ") }
            }
            if cleanTrim { base = base.trimmingCharacters(in: .whitespaces) }
            if cleanSpaceToUnderscore { base = base.replacingOccurrences(of: " ", with: "_") }
        case .windowsSafe:
            let illegal: Set<Character> = ["<", ">", ":", "\"", "/", "\\", "|", "?", "*"]
            var out = ""
            for ch in base {
                if illegal.contains(ch) {
                    out += winReplacement
                } else if let ascii = ch.asciiValue, ascii < 0x20 {
                    continue
                } else {
                    out.append(ch)
                }
            }
            while out.hasSuffix(".") || out.hasSuffix(" ") { out.removeLast() }
            base = out
        case .changeExtension:
            if !item.isDirectory {
                var e = newExtension.trimmingCharacters(in: .whitespaces)
                if e.hasPrefix(".") { e.removeFirst() }
                ext = e
            }
        }
        return (base, ext)
    }
}

// MARK: - プリセット

struct Preset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var rules: [RenameRule]
}

// MARK: - ファイルモデル

struct FileItem: Identifiable, Equatable {
    let id = UUID()
    var url: URL
    var isDirectory: Bool
    var modDate: Date
    var createDate: Date

    var name: String { url.lastPathComponent }

    /// 名前を base と ext に分割（".gitignore" のような隠しファイルは分割しない）
    var splitName: (base: String, ext: String) {
        let name = url.lastPathComponent
        if isDirectory { return (name, "") }
        guard let dotIndex = name.lastIndex(of: "."), dotIndex != name.startIndex else {
            return (name, "")
        }
        return (String(name[name.startIndex..<dotIndex]), String(name[name.index(after: dotIndex)...]))
    }
}

struct PreviewEntry {
    var newName: String
    var changed: Bool
    var conflict: Bool
    var invalid: Bool
}
