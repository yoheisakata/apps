import Foundation

enum OrganizerError: Error, LocalizedError {
    case sourceNotFound(URL)
    case destNotFound(URL)

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let url): return "ソースフォルダが見つかりません: \(url.path)"
        case .destNotFound(let url): return "整理先が見つかりません: \(url.path)"
        }
    }
}

struct OrganizerConfig {
    let sourceRoot: URL
    let destRoot: URL
    let extensions: Set<String>              // 小文字、ドットなし
    let dateSources: [(URL) -> ResolvedDate?] // 一次日付ソース（EXIF/QuickTime等）。共有フォールバックはMediaDateResolver側で付与
    let convertHEICToJPG: Bool
    let dryRun: Bool
}

struct OrganizerResult {
    var moved = 0
    var skippedDuplicate = 0
    var renamed = 0
    var convertedHEIC = 0
    var total: Int { moved + skippedDuplicate + renamed + convertedHEIC }
}

/// backup-photos.sh / backup-videos.sh の「整理」ステップに相当する共通エンジン。
/// 対象拡張子・日付リゾルバ・HEIC変換有無だけが写真/動画で異なるため、ここに一本化した。
enum MediaOrganizer {
    /// - Parameter afterMove: ファイルが整理先に実配置された直後(dry-run時・重複スキップ時は呼ばれない)に
    ///   最終URLを渡して呼ばれるフック。動画整理で「移動と同時にエンコードする」ために使う。
    static func run(
        config: OrganizerConfig,
        progress: @escaping (String) -> Void,
        setProgress: @escaping (Double?) -> Void = { _ in },
        setDetail: @escaping (String) -> Void = { _ in },
        afterMove: ((URL) async -> Void)? = nil,
        checkCancel: () throws -> Void
    ) async throws -> OrganizerResult {
        let fm = FileManager.default
        var result = OrganizerResult()

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: config.sourceRoot.path, isDirectory: &isDir), isDir.boolValue else {
            throw OrganizerError.sourceNotFound(config.sourceRoot)
        }
        guard fm.fileExists(atPath: config.destRoot.path, isDirectory: &isDir), isDir.boolValue else {
            throw OrganizerError.destNotFound(config.destRoot)
        }

        let files = collectFiles(in: config.sourceRoot, extensions: config.extensions)
        progress("対象フォルダ: \(config.sourceRoot.path)")
        progress("ファイル数: \(files.count)\n")

        let total = files.count
        for (i, file) in files.enumerated() {
            try checkCancel()
            setProgress(total > 0 ? Double(i) / Double(total) : nil)
            setDetail("[\(i + 1)/\(total)] \(file.lastPathComponent)")
            try await processOne(file, config: config, fm: fm, result: &result, progress: progress, afterMove: afterMove)
        }
        setProgress(total > 0 ? 1.0 : nil)

        if !config.dryRun {
            setDetail("空フォルダを削除中...")
            removeEmptySubfolders(of: config.sourceRoot, fm: fm)
        }

        let heicPart = config.convertHEICToJPG ? "  HEIC→JPG\(config.dryRun ? "予定" : ""): \(result.convertedHEIC)件" : ""
        progress("")
        if config.dryRun {
            progress("=============================== DRY RUN")
            progress("  移動予定: \(result.moved)件\(heicPart)  スキップ予定(重複): \(result.skippedDuplicate)件  リネーム予定: \(result.renamed)件")
        } else {
            progress("===============================")
            progress("  移動: \(result.moved)件\(heicPart)  スキップ(重複): \(result.skippedDuplicate)件  リネーム: \(result.renamed)件")
            progress("  整理先: \(config.destRoot.path)")
            progress("===============================")
        }
        return result
    }

    private static func processOne(
        _ file: URL,
        config: OrganizerConfig,
        fm: FileManager,
        result: inout OrganizerResult,
        progress: @escaping (String) -> Void,
        afterMove: ((URL) async -> Void)?
    ) async throws {
        let resolved = MediaDateResolver.resolve(for: file, primarySources: config.dateSources)
        let year = resolved.date.formatted("yyyy")
        let month = resolved.date.formatted("MM")
        let mmdd = resolved.date.formatted("MMdd")
        let ts = resolved.date.formatted("yyyy_MMdd_HHmmss")
        var ext = file.pathExtension.lowercased()

        var actualFile = file
        var heicTemp: URL?
        if config.convertHEICToJPG, ext == "heic" || ext == "heif" {
            if let converted = HEICConverter.convertToJPG(file) {
                heicTemp = converted
                actualFile = converted
                ext = "jpg"
            }
        }
        defer { if let heicTemp { HEICConverter.cleanup(heicTemp) } }

        let newName = "\(ts).\(ext)"
        let destDir = config.destRoot
            .appendingPathComponent(year)
            .appendingPathComponent(month)
            .appendingPathComponent(mmdd)
        let destFile = destDir.appendingPathComponent(newName)

        if config.dryRun {
            let tag = heicTemp != nil ? "HEIC→JPG " : ""
            if fm.fileExists(atPath: destFile.path) {
                let same = (try? FileHasher.md5(of: actualFile)) == (try? FileHasher.md5(of: destFile))
                if same {
                    result.skippedDuplicate += 1
                    progress("  SKIP予定 (重複のため): \(file.lastPathComponent)")
                } else {
                    var n = 1
                    var candidate = destDir.appendingPathComponent("\(ts)_\(n).\(ext)")
                    while fm.fileExists(atPath: candidate.path) {
                        n += 1
                        candidate = destDir.appendingPathComponent("\(ts)_\(n).\(ext)")
                    }
                    result.renamed += 1
                    progress("  RENAME予定: \(tag)\(file.lastPathComponent) -> \(candidate.lastPathComponent)  [\(resolved.source)]")
                }
            } else if heicTemp != nil {
                result.convertedHEIC += 1
                progress("  [\(resolved.source)] \(tag)\(file.lastPathComponent) -> \(year)/\(month)/\(mmdd)/\(newName)")
            } else {
                result.moved += 1
                progress("  [\(resolved.source)] \(file.lastPathComponent) -> \(year)/\(month)/\(mmdd)/\(newName)")
            }
            return
        }

        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        if fm.fileExists(atPath: destFile.path) {
            let same = (try? FileHasher.md5(of: actualFile)) == (try? FileHasher.md5(of: destFile))
            if same {
                try? fm.removeItem(at: file)
                result.skippedDuplicate += 1
                progress("  SKIP (重複のため): \(file.lastPathComponent)")
            } else {
                var n = 1
                var candidate = destDir.appendingPathComponent("\(ts)_\(n).\(ext)")
                while fm.fileExists(atPath: candidate.path) {
                    n += 1
                    candidate = destDir.appendingPathComponent("\(ts)_\(n).\(ext)")
                }
                try fm.moveItem(at: actualFile, to: candidate)
                if heicTemp != nil { try? fm.removeItem(at: file) }
                result.renamed += 1
                progress("  RENAMED: \(file.lastPathComponent) -> \(candidate.lastPathComponent)  [\(resolved.source)]")
                await afterMove?(candidate)
            }
        } else {
            try fm.moveItem(at: actualFile, to: destFile)
            if heicTemp != nil {
                try? fm.removeItem(at: file)
                result.convertedHEIC += 1
                progress("  OK: \(file.lastPathComponent) -> \(year)/\(month)/\(mmdd)/\(newName)  [HEIC→JPG, \(resolved.source)]")
            } else {
                result.moved += 1
                progress("  OK: \(file.lastPathComponent) -> \(year)/\(month)/\(mmdd)/\(newName)  [\(resolved.source)]")
            }
            await afterMove?(destFile)
        }
    }

    /// 整理先の末尾が年フォルダ(4桁の数字)っぽいかどうか。年/月/日フォルダは自動作成されるため、
    /// 年フォルダそのものを整理先に指定すると二重ネスト・重複判定漏れの原因になる。
    static func looksLikeYearFolder(_ destRoot: URL) -> Bool {
        let name = destRoot.lastPathComponent
        return name.count == 4 && name.allSatisfy(\.isNumber)
    }

    static func collectFiles(in root: URL, extensions: Set<String>) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            guard !url.lastPathComponent.hasPrefix(".") else { continue }
            files.append(url)
        }
        return files.sorted { $0.path < $1.path }
    }

    /// srcRoot配下の空サブフォルダを削除する（ルート自体は残す）。中身が空のディレクトリしか消さない。
    private static func removeEmptySubfolders(of root: URL, fm: FileManager) {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        var dirs: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                dirs.append(url)
            }
        }
        // 深い階層から処理（子が空になってから親を判定するため）
        for dir in dirs.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            if let contents = try? fm.contentsOfDirectory(atPath: dir.path), contents.isEmpty {
                try? fm.removeItem(at: dir)
            }
        }
    }
}
