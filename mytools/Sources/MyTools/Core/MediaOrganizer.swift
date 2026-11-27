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
    /// 整理先に同名ファイルがありMD5が違うとき、見た目で同じ写真か確かめて画質を比べる(写真整理のみ)。
    /// 同じ写真でソースが高画質なら整理先を置き換え、画質がほぼ同じ/整理先が上ならスキップしてソースを削除する。
    var compareImageQuality = false
}

struct OrganizerResult {
    var moved = 0
    var skippedDuplicate = 0
    var renamed = 0
    var convertedHEIC = 0
    var replaced = 0
    var failed = 0
    var total: Int { moved + skippedDuplicate + renamed + convertedHEIC + replaced }
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
            do {
                try await processOne(file, config: config, fm: fm, result: &result, progress: progress, afterMove: afterMove)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                result.failed += 1
                progress("  [ERROR] \(file.lastPathComponent): \(describe(error))")
            }
        }
        setProgress(total > 0 ? 1.0 : nil)

        if !config.dryRun {
            setDetail("空フォルダを削除中...")
            removeEmptySubfolders(of: config.sourceRoot, fm: fm)
        }

        let heicPart = config.convertHEICToJPG ? "  HEIC→JPG\(config.dryRun ? "予定" : ""): \(result.convertedHEIC)件" : ""
        let replacePart = config.compareImageQuality ? "  高画質で置換\(config.dryRun ? "予定" : ""): \(result.replaced)件" : ""
        progress("")
        if config.dryRun {
            progress("=============================== DRY RUN")
            progress("  移動予定: \(result.moved)件\(heicPart)  スキップ予定(重複): \(result.skippedDuplicate)件  リネーム予定: \(result.renamed)件\(replacePart)")
        } else {
            progress("===============================")
            progress("  移動: \(result.moved)件\(heicPart)  スキップ(重複): \(result.skippedDuplicate)件  リネーム: \(result.renamed)件\(replacePart)")
            if result.failed > 0 {
                progress("  失敗: \(result.failed)件（詳細は上記の[ERROR]行を参照）")
            }
            progress("  整理先: \(config.destRoot.path)")
            progress("===============================")
        }
        return result
    }

    /// エラーの説明文。localizedDescriptionだけだと原因(権限・空き容量不足等)が
    /// 省かれることがあるため、localizedFailureReasonを補って表示する。
    private static func describe(_ error: Error) -> String {
        let ns = error as NSError
        let desc = ns.localizedDescription
        if let reason = ns.localizedFailureReason, !reason.isEmpty, !desc.contains(reason) {
            return "\(desc) \(reason)"
        }
        return desc
    }

    /// removeItemはエラーを投げないまま実際には削除できていないことがある(使用中のファイル等)ため、
    /// FileRemover.moveToTrashと同様に消えたかどうかを必ず確認し、失敗はresult.failedとログに残す。
    private static func removeSource(
        _ file: URL,
        reason: String,
        fm: FileManager,
        result: inout OrganizerResult,
        progress: @escaping (String) -> Void
    ) {
        do {
            try fm.removeItem(at: file)
        } catch {
            result.failed += 1
            progress("  [ERROR] ソース削除に失敗(\(reason)): \(file.lastPathComponent): \(describe(error))")
            return
        }
        if fm.fileExists(atPath: file.path) {
            result.failed += 1
            progress("  [ERROR] ソース削除が完了しませんでした(\(reason)、使用中の可能性): \(file.lastPathComponent)")
        }
    }

    /// 整理先に同名ファイルが既にあるときの扱い
    private enum Collision {
        case duplicate(String)  // 同じ写真 → スキップしてソース削除
        case replace(String)    // 同じ写真でソースが高画質 → 整理先を置き換える
        case rename             // 別の写真 → _N を付けて追加
    }

    private static func decideCollision(source: URL, dest: URL, config: OrganizerConfig) -> Collision {
        // 整理先がOneDriveのクラウド専用ファイルだと、ここでの読み込みがダウンロードを起こす。
        // 読めなかった(オフライン・タイムアウト等)ときに nil == nil で「重複」扱いになりソースを
        // 消してしまわないよう、両方読めたときだけ比較する。読めなければ安全側で _N 追加に倒す。
        guard let srcHash = try? FileHasher.md5(of: source),
              let destHash = try? FileHasher.md5(of: dest) else { return .rename }
        if srcHash == destHash {
            return .duplicate("完全一致")
        }
        guard config.compareImageQuality else { return .rename }
        switch ImageQuality.compare(source: source, dest: dest) {
        case .differentPhoto: return .rename
        case .sourceBetter(let detail): return .replace(detail)
        case .sameOrWorse(let detail): return .duplicate("同じ写真・画質同等以下: \(detail)")
        }
    }

    private static func nextFreeName(in dir: URL, ts: String, ext: String, fm: FileManager) -> URL {
        var n = 1
        var candidate = dir.appendingPathComponent("\(ts)_\(n).\(ext)")
        while fm.fileExists(atPath: candidate.path) {
            n += 1
            candidate = dir.appendingPathComponent("\(ts)_\(n).\(ext)")
        }
        return candidate
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
                switch decideCollision(source: actualFile, dest: destFile, config: config) {
                case .duplicate(let why):
                    result.skippedDuplicate += 1
                    progress("  SKIP予定 (重複のため・\(why)): \(file.lastPathComponent)")
                case .replace(let detail):
                    result.replaced += 1
                    progress("  REPLACE予定 (高画質で置換・\(detail)): \(tag)\(file.lastPathComponent) -> \(year)/\(month)/\(mmdd)/\(newName)")
                case .rename:
                    let candidate = nextFreeName(in: destDir, ts: ts, ext: ext, fm: fm)
                    result.renamed += 1
                    progress("  RENAME予定: \(tag)\(file.lastPathComponent) -> \(year)/\(month)/\(mmdd)/\(candidate.lastPathComponent)  [\(resolved.source)]")
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
            switch decideCollision(source: actualFile, dest: destFile, config: config) {
            case .duplicate(let why):
                removeSource(file, reason: "重複", fm: fm, result: &result, progress: progress)
                result.skippedDuplicate += 1
                progress("  SKIP (重複のため・\(why)): \(file.lastPathComponent)")
            case .replace(let detail):
                // 古い方は完全削除せずゴミ箱へ(復元できるように)
                try fm.trashItem(at: destFile, resultingItemURL: nil)
                if fm.fileExists(atPath: destFile.path) {
                    result.failed += 1
                    progress("  [ERROR] 整理先をゴミ箱へ移動できませんでした(使用中の可能性): \(destFile.lastPathComponent)")
                    return
                }
                try fm.moveItem(at: actualFile, to: destFile)
                if heicTemp != nil { removeSource(file, reason: "HEIC変換", fm: fm, result: &result, progress: progress) }
                result.replaced += 1
                progress("  REPLACED (高画質で置換・\(detail)): \(file.lastPathComponent) -> \(year)/\(month)/\(mmdd)/\(newName)  [旧ファイルはゴミ箱へ]")
                await afterMove?(destFile)
            case .rename:
                let candidate = nextFreeName(in: destDir, ts: ts, ext: ext, fm: fm)
                try fm.moveItem(at: actualFile, to: candidate)
                if heicTemp != nil { removeSource(file, reason: "HEIC変換", fm: fm, result: &result, progress: progress) }
                result.renamed += 1
                progress("  RENAMED: \(file.lastPathComponent) -> \(year)/\(month)/\(mmdd)/\(candidate.lastPathComponent)  [\(resolved.source)]")
                await afterMove?(candidate)
            }
        } else {
            try fm.moveItem(at: actualFile, to: destFile)
            if heicTemp != nil {
                removeSource(file, reason: "HEIC変換", fm: fm, result: &result, progress: progress)
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
