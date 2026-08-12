import Foundation
import AppKit

enum GameSystem: String, CaseIterable, Identifiable {
    case nes = "NES"
    case snes = "SNES"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .nes: return "ファミコン"
        case .snes: return "スーパーファミコン"
        }
    }

    var thumbnailRepo: String {
        switch self {
        case .nes: return "Nintendo_-_Nintendo_Entertainment_System"
        case .snes: return "Nintendo_-_Super_Nintendo_Entertainment_System"
        }
    }

    var romExtensions: [String] {
        switch self {
        case .nes: return ["nes"]
        case .snes: return ["sfc", "smc"]
        }
    }

    static func detect(extension ext: String) -> GameSystem? {
        let lower = ext.lowercased()
        for system in allCases {
            if system.romExtensions.contains(lower) { return system }
        }
        return nil
    }
}

struct ScannedROM: Identifiable, Hashable {
    let id: String
    let url: URL
    let displayName: String
    let system: GameSystem
    let category: String
    let thumbnailCandidates: [String]

    init(url: URL) {
        self.url = url
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension.lowercased()
        self.system = GameSystem.detect(extension: ext) ?? .nes
        self.id = "\(system.rawValue)_\(filename)"
        self.displayName = Self.cleanDisplayName(filename)
        self.category = url.deletingLastPathComponent().lastPathComponent
        self.thumbnailCandidates = Self.thumbnailCandidates(for: filename, system: system)
    }

    // libretro-thumbnails は No-Intro 形式のファイル名で地域別の箱絵を持つ。
    // 日本版の箱絵を優先し、無ければ元の地域にフォールバックする。
    // リポジトリのファイル名はローマ字化されているため、日本語(CJK)タイトルは
    // TitleMap(日本語→ローマ字対照表)を経由し、表に無ければ候補なしとする。
    private static func thumbnailCandidates(for filename: String, system: GameSystem) -> [String] {
        var effective = filename
        if containsCJK(filename) {
            // まずファイル名そのまま、無ければタグ(「(Japan)」等)を除いた名前で引く
            guard let mapped = TitleMap.romanized(system: system, japaneseTitle: filename)
                ?? TitleMap.romanized(system: system, japaneseTitle: cleanDisplayName(filename)) else {
                return []
            }
            effective = mapped
        }
        let base = cleanDisplayName(effective)
        var candidates: [String] = []
        if effective.contains("(Japan") {
            candidates.append(effective)
        }
        candidates.append("\(base) (Japan)")
        candidates.append("\(base) (Japan, USA)")
        candidates.append("\(base) (World)")
        candidates.append(effective)
        candidates.append("\(base) (USA)")
        candidates.append("\(base) (Europe)")

        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func containsCJK(_ s: String) -> Bool {
        s.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value) ||   // ひらがな・カタカナ
            (0x4E00...0x9FFF).contains(scalar.value) ||   // CJK 漢字
            (0xFF66...0xFF9D).contains(scalar.value)      // 半角カナ
        }
    }

    private static func cleanDisplayName(_ filename: String) -> String {
        var name = filename
        // Remove common tags like (USA), (Japan), (Rev 1), [!], etc for display
        let pattern = #"\s*[\(\[][^\)\]]*[\)\]]"#
        if let regex = try? NSRegularExpression(pattern: pattern) {
            name = regex.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: "")
        }
        return name.trimmingCharacters(in: .whitespaces)
    }
}

final class ROMScanner: ObservableObject {
    @Published var roms: [ScannedROM] = []
    @Published var romDirectory: URL?
    @Published var isScanning = false
    @Published var scanStatus: String?
    @Published var scanError: String?

    private let romDirKey = "romDirectory"

    init() {
        if let saved = UserDefaults.standard.string(forKey: romDirKey) {
            let url = URL(fileURLWithPath: saved)
            if FileManager.default.fileExists(atPath: url.path) {
                romDirectory = url
                scan(directory: url)
            }
        }
    }

    func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.title = "ROMフォルダを選択"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        guard panel.runModal() == .OK, let url = panel.url else { return }
        romDirectory = url
        UserDefaults.standard.set(url.path, forKey: romDirKey)
        scan(directory: url)
    }

    func rescan() {
        guard let dir = romDirectory else { return }
        scan(directory: dir)
    }

    private func scan(directory: URL) {
        isScanning = true
        scanStatus = "スキャン中…"
        scanError = nil
        let validExtensions = Set(GameSystem.allCases.flatMap(\.romExtensions))

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            var found: [ScannedROM] = []
            var accessErrors = 0
            let fm = FileManager.default

            // enumerator はサブフォルダを再帰的に辿る。アクセス拒否(TCC 等)は
            // errorHandler でカウントして UI に出す。
            if let enumerator = fm.enumerator(at: directory,
                                               includingPropertiesForKeys: [.isRegularFileKey],
                                               options: [.skipsHiddenFiles],
                                               errorHandler: { _, _ in accessErrors += 1; return true }) {
                for case let fileURL as URL in enumerator {
                    if validExtensions.contains(fileURL.pathExtension.lowercased()) {
                        found.append(ScannedROM(url: fileURL))
                    }
                }
            }

            found.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }

            DispatchQueue.main.async {
                self.roms = found
                self.isScanning = false
                self.scanStatus = nil
                if found.isEmpty && accessErrors > 0 {
                    self.scanError = "フォルダにアクセスできませんでした。システム設定 > プライバシーとセキュリティ > ファイルとフォルダ で RetroGames にアクセスを許可してください。"
                } else if accessErrors > 0 {
                    self.scanError = "\(accessErrors) 個のフォルダにアクセスできませんでした。"
                }
            }
        }
    }

    /// 選択したタイトルの ROM ファイルをゴミ箱へ移動する。
    func moveToTrash(_ targets: [ScannedROM]) {
        guard !targets.isEmpty else { return }
        scanStatus = "ゴミ箱に移動中…"

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self else { return }
            let fm = FileManager.default
            var deletedIds = Set<String>()
            var failures = 0

            for rom in targets {
                do {
                    try fm.trashItem(at: rom.url, resultingItemURL: nil)
                    deletedIds.insert(rom.id)
                } catch {
                    // 失敗した ROM はファイルが残っているので、ライブラリにも残す
                    failures += 1
                }
            }

            DispatchQueue.main.async {
                self.roms.removeAll { deletedIds.contains($0.id) }
                ThumbnailLoader.shared.removeCached(ids: deletedIds)
                self.scanStatus = nil
                self.scanError = failures > 0 ? "\(failures) 件をゴミ箱に移動できませんでした。" : nil
            }
        }
    }

}
