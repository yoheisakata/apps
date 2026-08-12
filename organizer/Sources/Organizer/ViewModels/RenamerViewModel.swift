import AppKit
import AVFoundation
import Foundation
import ImageIO

final class RenamerViewModel: ObservableObject {
    @Published var items: [FileItem] = []
    @Published var rules: [RenameRule] = []
    @Published var undoBatches: [[(from: URL, to: URL)]] = []
    @Published var presets: [Preset] = []
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var includeSubfolderFiles = false

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
            .appendingPathComponent("Organizer")
            .appendingPathComponent("Renamer")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private var presetsFile: URL { supportDir.appendingPathComponent("presets.json") }
    var historyFile: URL { supportDir.appendingPathComponent("history.log") }

    // MARK: ファイル追加

    func addURLs(_ urls: [URL]) {
        let fm = FileManager.default
        var expanded: [URL] = []
        for url in urls {
            let std = url.standardizedFileURL
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: std.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue && includeSubfolderFiles {
                expanded.append(contentsOf: filesRecursively(under: std))
            } else {
                expanded.append(std)
            }
        }
        for std in expanded {
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

    /// フォルダ配下のファイルのみを再帰的に列挙する（サブフォルダ自体は対象に含めない）
    private func filesRecursively(under folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder,
                                             includingPropertiesForKeys: [.isDirectoryKey],
                                             options: [.skipsHiddenFiles]) else { return [] }
        var result: [URL] = []
        for case let fileURL as URL in enumerator {
            let isDir = (try? fileURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if !isDir {
                result.append(fileURL.standardizedFileURL)
            }
        }
        return result
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
