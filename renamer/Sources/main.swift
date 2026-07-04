import SwiftUI
import AppKit
import UniformTypeIdentifiers
import ImageIO
import AVFoundation

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

// MARK: - 状態

final class AppState: ObservableObject {
    @Published var items: [FileItem] = []
    @Published var rules: [RenameRule] = []
    @Published var undoBatches: [[(from: URL, to: URL)]] = []
    @Published var presets: [Preset] = []
    @Published var statusMessage = ""
    @Published var errorMessage: String?

    private var metaCache: [URL: FileMetadata] = [:]

    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "heic", "heif", "png", "tiff", "tif", "gif", "bmp", "webp",
        "arw", "crw", "cr2", "cr3", "nef", "raf", "orf", "mrw", "dng", "pef", "srf", "srw", "rw2", "thm",
    ]
    static let mediaExtensions: Set<String> = [
        "mp3", "m4a", "aac", "flac", "wav", "aiff", "aif", "caf", "m4v", "mp4", "mov",
    ]

    init() {
        loadPresets()
    }

    // MARK: 保存先

    private var supportDir: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Renamer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var presetsFile: URL { supportDir.appendingPathComponent("presets.json") }
    var historyFile: URL { supportDir.appendingPathComponent("history.log") }

    // MARK: ファイル追加

    func addURLs(_ urls: [URL]) {
        let fm = FileManager.default
        for url in urls {
            let std = url.standardizedFileURL
            guard !items.contains(where: { $0.url == std }) else { continue }
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: std.path, isDirectory: &isDir) else { continue }
            let values = try? std.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
            items.append(FileItem(url: std,
                                  isDirectory: isDir.boolValue,
                                  modDate: values?.contentModificationDate ?? Date(),
                                  createDate: values?.creationDate ?? Date()))
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "追加"
        if panel.runModal() == .OK {
            addURLs(panel.urls)
        }
    }

    func sortByName(ascending: Bool) {
        items.sort {
            let r = $0.name.localizedStandardCompare($1.name)
            return ascending ? r == .orderedAscending : r == .orderedDescending
        }
    }

    func sortByDate(newestFirst: Bool) {
        items.sort { newestFirst ? $0.modDate > $1.modDate : $0.modDate < $1.modDate }
    }

    // MARK: ルール操作

    func addRule(_ kind: RuleKind) {
        rules.append(RenameRule(kind: kind))
    }

    func removeRule(_ id: UUID) {
        rules.removeAll { $0.id == id }
    }

    func moveRule(_ id: UUID, up: Bool) {
        guard let i = rules.firstIndex(where: { $0.id == id }) else { return }
        let j = up ? i - 1 : i + 1
        guard rules.indices.contains(j) else { return }
        rules.swapAt(i, j)
    }

    // MARK: プリセット

    func loadPresets() {
        guard let data = try? Data(contentsOf: presetsFile),
              let loaded = try? JSONDecoder().decode([Preset].self, from: data) else { return }
        presets = loaded
    }

    private func persistPresets() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(presets) {
            try? data.write(to: presetsFile)
        }
    }

    func savePreset(named name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !rules.isEmpty else { return }
        presets.removeAll { $0.name == trimmed }
        presets.append(Preset(name: trimmed, rules: rules))
        presets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        persistPresets()
        statusMessage = "プリセット「\(trimmed)」を保存しました"
    }

    func applyPreset(_ preset: Preset) {
        rules = preset.rules.map { rule in
            var r = rule
            r.id = UUID()
            return r
        }
        statusMessage = "プリセット「\(preset.name)」を適用しました"
    }

    func deletePreset(_ preset: Preset) {
        presets.removeAll { $0.id == preset.id }
        persistPresets()
    }

    func exportPresets() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "renamer-presets.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        do {
            let data = try encoder.encode(presets)
            try data.write(to: url)
            statusMessage = "プリセットを書き出しました"
        } catch {
            errorMessage = "書き出しに失敗しました: \(error.localizedDescription)"
        }
    }

    func importPresets() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            let imported = try JSONDecoder().decode([Preset].self, from: data)
            for p in imported {
                presets.removeAll { $0.name == p.name }
                presets.append(p)
            }
            presets.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            persistPresets()
            statusMessage = "\(imported.count) 件のプリセットを読み込みました"
        } catch {
            errorMessage = "読み込みに失敗しました: \(error.localizedDescription)"
        }
    }

    // MARK: メタデータ

    func metadata(for url: URL) -> FileMetadata {
        if let cached = metaCache[url] { return cached }
        var m = FileMetadata()
        let ext = url.pathExtension.lowercased()
        if Self.imageExtensions.contains(ext),
           let src = CGImageSourceCreateWithURL(url as CFURL, nil),
           let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            m.pixelWidth = props[kCGImagePropertyPixelWidth] as? Int
            m.pixelHeight = props[kCGImagePropertyPixelHeight] as? Int
            let exif = props[kCGImagePropertyExifDictionary] as? [CFString: Any]
            let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
            let dateString = exif?[kCGImagePropertyExifDateTimeOriginal] as? String
                ?? exif?[kCGImagePropertyExifDateTimeDigitized] as? String
                ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
            if let dateString {
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = "yyyy:MM:dd HH:mm:ss"
                m.exifDate = f.date(from: dateString)
            }
        } else if Self.mediaExtensions.contains(ext) {
            let asset = AVURLAsset(url: url)
            func common(_ id: AVMetadataIdentifier) -> String? {
                AVMetadataItem.metadataItems(from: asset.commonMetadata, filteredByIdentifier: id)
                    .first?.stringValue
            }
            m.title = common(.commonIdentifierTitle)
            m.artist = common(.commonIdentifierArtist)
            m.album = common(.commonIdentifierAlbumName)
            for item in asset.metadata {
                guard item.identifier == .id3MetadataTrackNumber
                    || item.identifier == .iTunesMetadataTrackNumber else { continue }
                if let s = item.stringValue, let n = Int(s.split(separator: "/").first ?? "") {
                    m.track = n
                } else if let n = item.numberValue {
                    m.track = n.intValue
                }
                if m.track != nil { break }
            }
        }
        metaCache[url] = m
        return m
    }

    // MARK: プレビュー

    func previews() -> [UUID: PreviewEntry] {
        let fm = FileManager.default
        let activeRules = rules.filter { $0.enabled }
        var result: [UUID: PreviewEntry] = [:]

        // 新しい名前を計算（連番はルールごとに、フィルタに合致したファイルだけを数える）
        var seqCounters: [UUID: Int] = [:]
        var newNames: [(item: FileItem, newName: String)] = []
        for item in items {
            var (base, ext) = item.splitName
            for rule in activeRules {
                guard rule.matchesFilter(ext: ext) else { continue }
                var seqIndex = 0
                if rule.kind == .sequence {
                    seqIndex = seqCounters[rule.id, default: 0]
                    seqCounters[rule.id] = seqIndex + 1
                }
                let meta = rule.needsMetadata ? metadata(for: item.url) : nil
                (base, ext) = rule.apply(base: base, ext: ext, seqIndex: seqIndex, item: item, meta: meta)
            }
            let newName = ext.isEmpty ? base : base + "." + ext
            newNames.append((item, newName))
        }

        // 同一フォルダ内の重複を検出
        var counts: [String: Int] = [:]
        for (item, newName) in newNames {
            let key = item.url.deletingLastPathComponent().path.lowercased() + "/" + newName.lowercased()
            counts[key, default: 0] += 1
        }

        let batchOriginals = Set(items.map { $0.url.path.lowercased() })

        for (item, newName) in newNames {
            let changed = newName != item.name
            let invalid = newName.isEmpty || newName == "." || newName == ".."
                || newName.contains("/") || newName.contains(":")
            var conflict = false
            let key = item.url.deletingLastPathComponent().path.lowercased() + "/" + newName.lowercased()
            if counts[key, default: 0] > 1 { conflict = true }
            if changed && !invalid && !conflict {
                let dest = item.url.deletingLastPathComponent().appendingPathComponent(newName)
                let destLower = dest.path.lowercased()
                // 移動先が既に存在し、それが自分自身（大文字小文字変更）でも
                // バッチ内の他ファイルでもない場合は衝突
                if fm.fileExists(atPath: dest.path)
                    && destLower != item.url.path.lowercased()
                    && !batchOriginals.contains(destLower) {
                    conflict = true
                }
                // バッチ内の他ファイルの元の名前と同じ（入れ替え）は逐次リネームでは
                // 安全に処理できないため衝突として扱う
                if destLower != item.url.path.lowercased() && batchOriginals.contains(destLower) {
                    conflict = true
                }
            }
            result[item.id] = PreviewEntry(newName: newName, changed: changed,
                                           conflict: conflict, invalid: invalid)
        }
        return result
    }

    // MARK: リネーム実行

    private func moveHandlingCase(from: URL, to: URL) throws {
        let fm = FileManager.default
        if from.path != to.path && from.path.lowercased() == to.path.lowercased() {
            // 大文字小文字のみの変更は一時名を経由する
            let tmp = from.deletingLastPathComponent()
                .appendingPathComponent(".rntmp-" + UUID().uuidString)
            try fm.moveItem(at: from, to: tmp)
            do {
                try fm.moveItem(at: tmp, to: to)
            } catch {
                try? fm.moveItem(at: tmp, to: from)
                throw error
            }
        } else {
            try fm.moveItem(at: from, to: to)
        }
    }

    /// フォルダのリネーム後、その中にあるアイテムの URL を付け替える
    private func fixupPaths(from: URL, to: URL) {
        let oldPrefix = from.path + "/"
        for i in items.indices {
            let p = items[i].url.path
            if p.hasPrefix(oldPrefix) {
                items[i].url = URL(fileURLWithPath: to.path + "/" + String(p.dropFirst(oldPrefix.count)))
            }
        }
    }

    private func appendHistory(_ renames: [(from: URL, to: URL)]) {
        let f = ISO8601DateFormatter()
        let stamp = f.string(from: Date())
        var text = ""
        for (from, to) in renames {
            text += "\(stamp)\t\(from.path)\t→\t\(to.path)\n"
        }
        guard let data = text.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: historyFile) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: historyFile)
        }
    }

    func openHistoryLog() {
        if !FileManager.default.fileExists(atPath: historyFile.path) {
            try? Data().write(to: historyFile)
        }
        NSWorkspace.shared.open(historyFile)
    }

    func performRename() {
        let previews = previews()
        var plan: [(itemID: UUID, from: URL, to: URL, isDir: Bool)] = []
        for item in items {
            guard let p = previews[item.id], p.changed, !p.conflict, !p.invalid else { continue }
            let to = item.url.deletingLastPathComponent().appendingPathComponent(p.newName)
            plan.append((item.id, item.url, to, item.isDirectory))
        }
        guard !plan.isEmpty else { return }
        // フォルダ内のアイテムを先に処理するため、深い順に並べる
        plan.sort { $0.from.pathComponents.count > $1.from.pathComponents.count }

        var done: [(from: URL, to: URL)] = []
        for step in plan {
            do {
                try moveHandlingCase(from: step.from, to: step.to)
            } catch {
                errorMessage = "「\(step.from.lastPathComponent)」をリネームできませんでした: \(error.localizedDescription)"
                break
            }
            done.append((step.from, step.to))
            if let i = items.firstIndex(where: { $0.id == step.itemID }) {
                items[i].url = step.to
            }
            if step.isDir {
                fixupPaths(from: step.from, to: step.to)
            }
        }
        if !done.isEmpty {
            undoBatches.append(done)
            appendHistory(done)
            statusMessage = "\(done.count) 件をリネームしました"
        }
    }

    func undo() {
        guard let batch = undoBatches.last else { return }
        var reverted = 0
        for (from, to) in batch.reversed() {
            do {
                try moveHandlingCase(from: to, to: from)
            } catch {
                errorMessage = "「\(to.lastPathComponent)」を元に戻せませんでした: \(error.localizedDescription)"
                break
            }
            reverted += 1
            if let i = items.firstIndex(where: { $0.url == to }) {
                items[i].url = from
            }
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: from.path, isDirectory: &isDir), isDir.boolValue {
                fixupPaths(from: to, to: from)
            }
        }
        if reverted == batch.count {
            undoBatches.removeLast()
            statusMessage = "元に戻しました"
        }
    }
}

// MARK: - アプリ

@main
struct RenamerApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
        }
        .defaultSize(width: 1040, height: 660)
    }
}

// MARK: - メインビュー

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var dropTargeted = false

    var body: some View {
        HSplitView {
            RulesPane()
                .frame(minWidth: 310, idealWidth: 340, maxWidth: 440)
            FilesPane(dropTargeted: $dropTargeted)
                .frame(minWidth: 480, maxWidth: .infinity)
        }
        .navigationTitle("Renamer")
        .alert("エラー", isPresented: Binding(
            get: { state.errorMessage != nil },
            set: { if !$0 { state.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}

// MARK: - ルールペイン

struct RulesPane: View {
    @EnvironmentObject var state: AppState
    @State private var showingSavePreset = false
    @State private var presetName = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("ルール")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("現在のルールを保存…") {
                        presetName = ""
                        showingSavePreset = true
                    }
                    .disabled(state.rules.isEmpty)
                    if !state.presets.isEmpty {
                        Divider()
                        ForEach(state.presets) { preset in
                            Button(preset.name) { state.applyPreset(preset) }
                        }
                        Divider()
                        Menu("削除") {
                            ForEach(state.presets) { preset in
                                Button(preset.name) { state.deletePreset(preset) }
                            }
                        }
                    }
                    Divider()
                    Button("書き出し…") { state.exportPresets() }
                        .disabled(state.presets.isEmpty)
                    Button("読み込み…") { state.importPresets() }
                } label: {
                    Label("プリセット", systemImage: "star")
                }
                .menuStyle(.borderedButton)
                .fixedSize()
                Menu {
                    ForEach(RuleKind.allCases) { kind in
                        Button {
                            state.addRule(kind)
                        } label: {
                            Label(kind.label, systemImage: kind.icon)
                        }
                    }
                } label: {
                    Label("追加", systemImage: "plus")
                }
                .menuStyle(.borderedButton)
                .fixedSize()
            }
            .padding(10)

            Divider()

            if state.rules.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary)
                    Text("「追加」からルールを作成してください")
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach($state.rules) { $rule in
                            RuleCard(rule: $rule)
                        }
                    }
                    .padding(10)
                }
                Text("ルールは上から順に適用されます")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.bottom, 8)
            }
        }
        .alert("プリセットを保存", isPresented: $showingSavePreset) {
            TextField("プリセット名", text: $presetName)
            Button("保存") { state.savePreset(named: presetName) }
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("現在のルール一式に名前を付けて保存します")
        }
    }
}

struct RuleCard: View {
    @EnvironmentObject var state: AppState
    @Binding var rule: RenameRule

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Toggle("", isOn: $rule.enabled)
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                Label(rule.kind.label, systemImage: rule.kind.icon)
                    .font(.system(.body, weight: .semibold))
                Spacer()
                Button { state.moveRule(rule.id, up: true) } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.borderless)
                Button { state.moveRule(rule.id, up: false) } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.borderless)
                Button { state.removeRule(rule.id) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }

            Group {
                switch rule.kind {
                case .replace:
                    TextField("検索文字列", text: $rule.searchText)
                    TextField("置換文字列", text: $rule.replaceText)
                    HStack {
                        Toggle("正規表現", isOn: $rule.useRegex)
                        Toggle("大小同一視", isOn: $rule.caseInsensitive)
                    }
                    .toggleStyle(.checkbox)
                    .font(.caption)
                case .addText:
                    TextField("追加するテキスト", text: $rule.insertText)
                    Picker("位置", selection: $rule.insertPosition) {
                        ForEach(InsertPosition.allCases) { p in
                            Text(p.label).tag(p)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if rule.insertPosition == .atIndex {
                        Stepper("挿入位置: \(rule.insertIndex) 文字目", value: $rule.insertIndex, in: 0...200)
                            .font(.caption)
                    }
                case .sequence:
                    Stepper("開始番号: \(rule.seqStart)", value: $rule.seqStart, in: 0...99999)
                    Stepper("増分: \(rule.seqStep)", value: $rule.seqStep, in: 1...100)
                    Stepper("桁数: \(rule.seqDigits)", value: $rule.seqDigits, in: 1...6)
                    TextField("区切り文字", text: $rule.seqSeparator)
                    Picker("位置", selection: $rule.seqPosition) {
                        Text("先頭").tag(InsertPosition.prefix)
                        Text("末尾").tag(InsertPosition.suffix)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                case .addDate:
                    Picker("日付", selection: $rule.dateSource) {
                        ForEach(DateSource.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    TextField("書式（例: yyyyMMdd）", text: $rule.dateFormat)
                    TextField("区切り文字", text: $rule.dateSeparator)
                    Picker("位置", selection: $rule.datePosition) {
                        Text("先頭").tag(InsertPosition.prefix)
                        Text("末尾").tag(InsertPosition.suffix)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if rule.dateSource == .exif {
                        Text("撮影日が取得できないファイルは変更されません")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                case .insertMetadata:
                    Picker("項目", selection: $rule.metaField) {
                        ForEach(MetadataField.allCases) { f in
                            Text(f.label).tag(f)
                        }
                    }
                    TextField("区切り文字", text: $rule.metaSeparator)
                    Picker("位置", selection: $rule.metaPosition) {
                        Text("先頭").tag(InsertPosition.prefix)
                        Text("末尾").tag(InsertPosition.suffix)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    Text("音楽タグ (MP3/M4A等) と画像 (EXIF) に対応。取得できない場合は変更されません")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .changeCase:
                    Picker("スタイル", selection: $rule.caseStyle) {
                        ForEach(CaseStyle.allCases) { s in
                            Text(s.label).tag(s)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                case .removeChars:
                    Stepper("削除する文字数: \(rule.removeCount)", value: $rule.removeCount, in: 1...100)
                    Picker("方向", selection: $rule.removeFrom) {
                        ForEach(RemoveFrom.allCases) { d in
                            Text(d.label).tag(d)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                case .truncate:
                    Stepper("残す文字数: \(rule.truncateKeep)", value: $rule.truncateKeep, in: 1...200)
                    Picker("残す位置", selection: $rule.truncateFrom) {
                        Text("先頭を残す").tag(RemoveFrom.start)
                        Text("末尾を残す").tag(RemoveFrom.end)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                case .cleanup:
                    Toggle("前後の空白を削除", isOn: $rule.cleanTrim)
                    Toggle("連続する空白を 1 つに", isOn: $rule.cleanCollapse)
                    Toggle("アンダースコアを空白に", isOn: $rule.cleanUnderscoreToSpace)
                    Toggle("空白をアンダースコアに", isOn: $rule.cleanSpaceToUnderscore)
                case .windowsSafe:
                    TextField("置換文字（空で削除）", text: $rule.winReplacement)
                    Text("< > : \" / \\ | ? * を置換し、末尾のドット・空白を削除します")
                        .font(.caption)
                        .foregroundColor(.secondary)
                case .changeExtension:
                    TextField("新しい拡張子（空で削除）", text: $rule.newExtension)
                }
            }
            .textFieldStyle(.roundedBorder)
            .font(.callout)
            .disabled(!rule.enabled)
            .opacity(rule.enabled ? 1 : 0.5)

            TextField("対象拡張子で絞り込み（例: jpg, png / 空=すべて）", text: $rule.filterExtensions)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .disabled(!rule.enabled)
                .opacity(rule.enabled ? 1 : 0.5)
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - ファイルペイン

struct FilesPane: View {
    @EnvironmentObject var state: AppState
    @Binding var dropTargeted: Bool

    var body: some View {
        let previews = state.previews()
        let changedCount = state.items.filter { previews[$0.id]?.changed == true }.count
        let problemCount = state.items.filter {
            let p = previews[$0.id]
            return p?.conflict == true || p?.invalid == true
        }.count

        VStack(spacing: 0) {
            HStack {
                Button {
                    state.openPanel()
                } label: {
                    Label("ファイルを追加", systemImage: "plus")
                }
                Button("クリア") {
                    state.items.removeAll()
                    state.statusMessage = ""
                }
                .disabled(state.items.isEmpty)
                Menu("並べ替え") {
                    Button("名前（昇順）") { state.sortByName(ascending: true) }
                    Button("名前（降順）") { state.sortByName(ascending: false) }
                    Divider()
                    Button("変更日（新しい順）") { state.sortByDate(newestFirst: true) }
                    Button("変更日（古い順）") { state.sortByDate(newestFirst: false) }
                }
                .fixedSize()
                .disabled(state.items.isEmpty)
                Spacer()
                Text("\(state.items.count) 件")
                    .foregroundColor(.secondary)
                    .font(.callout)
            }
            .padding(10)

            Divider()

            if state.items.isEmpty {
                Spacer()
                VStack(spacing: 10) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("ここにファイルやフォルダをドラッグ＆ドロップ")
                        .foregroundColor(.secondary)
                }
                Spacer()
            } else {
                List {
                    ForEach(state.items) { item in
                        FileRow(item: item, preview: previews[item.id])
                            .contextMenu {
                                Button("リストから削除") {
                                    state.items.removeAll { $0.id == item.id }
                                }
                            }
                    }
                    .onMove { from, to in
                        state.items.move(fromOffsets: from, toOffset: to)
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            HStack {
                Menu {
                    Button("履歴ログを開く") { state.openHistoryLog() }
                } label: {
                    Image(systemName: "clock")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                if problemCount > 0 {
                    Label("\(problemCount) 件の名前が衝突しています", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.callout)
                } else {
                    Text(state.statusMessage)
                        .foregroundColor(.secondary)
                        .font(.callout)
                }
                Spacer()
                Button(state.undoBatches.count > 1 ? "元に戻す（残り \(state.undoBatches.count)）" : "元に戻す") {
                    state.undo()
                }
                .disabled(state.undoBatches.isEmpty)
                Button("リネーム実行（\(changedCount) 件）") {
                    state.performRename()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(changedCount == 0 || problemCount > 0)
            }
            .padding(10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(dropTargeted ? Color.accentColor : Color.clear, lineWidth: 3)
                .padding(3)
        )
        .onDrop(of: [UTType.fileURL], isTargeted: $dropTargeted) { providers in
            for provider in providers {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    var url: URL?
                    if let data = item as? Data {
                        url = URL(dataRepresentation: data, relativeTo: nil)
                    } else if let u = item as? URL {
                        url = u
                    }
                    if let url {
                        DispatchQueue.main.async {
                            state.addURLs([url])
                        }
                    }
                }
            }
            return true
        }
    }
}

struct FileRow: View {
    let item: FileItem
    let preview: PreviewEntry?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder.fill" : "doc.fill")
                .foregroundColor(item.isDirectory ? .cyan : .secondary)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let preview, preview.changed {
                Image(systemName: "arrow.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
                HStack(spacing: 4) {
                    if preview.conflict || preview.invalid {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    Text(preview.newName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .foregroundColor(preview.conflict || preview.invalid ? .red : .accentColor)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 2)
        .help(item.url.path)
    }
}
