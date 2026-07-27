import Foundation

struct SyncDiff {
    var addCount = 0
    var modCount = 0   // 追加を除く更新
    var delCount = 0
    var addedLines: [String] = []
    var deletedLines: [String] = []
    var raw: [String] = []

    var hasChanges: Bool { addCount + modCount + delCount > 0 }
}

enum SyncError: Error, LocalizedError {
    case sourceNotFound(URL)
    case targetNotFound(URL)
    case samePath
    case sourceEmpty(URL)
    case rsyncMissing

    var errorDescription: String? {
        switch self {
        case .sourceNotFound(let url): return "ソースが見つかりません: \(url.path)"
        case .targetNotFound(let url): return "ターゲットが見つかりません: \(url.path)"
        case .samePath: return "ソースとターゲットが同じパスです"
        case .sourceEmpty(let url): return "ソースが空です（マウントされていない可能性があります）: \(url.path)"
        case .rsyncMissing: return "rsync が見つかりません"
        }
    }
}

/// sync-backups.sh の移植。ExFAT HDD間の片方向ミラーリング（ソースを正としてターゲットを合わせる、
/// ターゲット側の余分なファイルは削除）。実削除を伴うため、呼び出し側は必ずdry-runで差分を見せてから
/// ユーザーの明示的な確認を取ったうえでsync(execute:)を呼ぶこと。
enum RsyncSync {
    private static let excludePatterns = [
        ".DS_Store", "._*", ".Spotlight-V100/", ".Trashes/", ".TemporaryItems/", ".fseventsd/",
    ]

    static func validate(source: URL, target: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue else {
            throw SyncError.sourceNotFound(source)
        }
        guard FileManager.default.fileExists(atPath: target.path, isDirectory: &isDir), isDir.boolValue else {
            throw SyncError.targetNotFound(target)
        }
        let sourceReal = source.resolvingSymlinksInPath().standardizedFileURL.path
        let targetReal = target.resolvingSymlinksInPath().standardizedFileURL.path
        guard sourceReal != targetReal else { throw SyncError.samePath }

        let contents = try? FileManager.default.contentsOfDirectory(atPath: source.path)
        guard let contents, !contents.isEmpty else { throw SyncError.sourceEmpty(source) }
    }

    static func checkDiff(
        source: URL, target: URL,
        progress: @escaping (String) -> Void,
        onCancel: (@escaping () -> Void) -> Void,
        checkCancel: () throws -> Void
    ) async throws -> SyncDiff {
        try validate(source: source, target: target)
        guard let rsync = ToolLocator.resolve("rsync") else { throw SyncError.rsyncMissing }

        progress("差分を確認中...")
        var args = baseArgs(rsync: rsync)
        args += ["--dry-run", "--itemize-changes", trailingSlash(source), trailingSlash(target)]

        let runner = ProcessRunner()
        onCancel { runner.cancel() }

        var diff = SyncDiff()
        _ = try await runner.run(rsync, args) { line in
            diff.raw.append(line)
            if line.hasPrefix(">f+++++++++") {
                diff.addCount += 1
                diff.addedLines.append(line)
            } else if line.hasPrefix(">f") {
                diff.modCount += 1
            } else if line.hasPrefix("*deleting") {
                diff.delCount += 1
                diff.deletedLines.append(line)
            }
        }
        try checkCancel()
        return diff
    }

    /// 実際の同期を実行する。呼び出し側が確認済みであることが前提。
    static func sync(
        source: URL, target: URL,
        progress: @escaping (String) -> Void,
        onCancel: (@escaping () -> Void) -> Void
    ) async throws -> Int32 {
        try validate(source: source, target: target)
        guard let rsync = ToolLocator.resolve("rsync") else { throw SyncError.rsyncMissing }

        var args = baseArgs(rsync: rsync)
        args += ["--progress", trailingSlash(source), trailingSlash(target)]

        let runner = ProcessRunner()
        onCancel { runner.cancel() }
        return try await runner.run(rsync, args, onLine: progress)
    }

    static func buildReportText(source: URL, target: URL, diff: SyncDiff) -> String {
        var lines: [String] = []
        lines.append("sync-backups 差分レポート")
        lines.append("生成日時 : \(Date().formatted("yyyy-MM-dd HH:mm:ss"))")
        lines.append("source   : \(source.path)")
        lines.append("target   : \(target.path)")
        lines.append("差分     : 追加=\(diff.addCount) 更新=\(diff.modCount) 削除=\(diff.delCount)")
        lines.append("")

        var folderStats: [String: (add: Int, upd: Int, del: Int)] = [:]
        for line in diff.raw {
            guard let path = extractPath(from: line) else { continue }
            let folder = (path as NSString).deletingLastPathComponent
            var stat = folderStats[folder] ?? (0, 0, 0)
            if line.hasPrefix(">f+++++++++") { stat.add += 1 }
            else if line.hasPrefix(">f") { stat.upd += 1 }
            else if line.hasPrefix("*deleting") { stat.del += 1 }
            folderStats[folder] = stat
        }

        lines.append("=== 差分があるフォルダ ===")
        if folderStats.isEmpty {
            lines.append("  （なし）")
        } else {
            for (folder, stat) in folderStats.sorted(by: { $0.key < $1.key }) {
                lines.append("  \(folder)  (追加=\(stat.add) 更新=\(stat.upd) 削除=\(stat.del))")
            }
        }

        lines.append("")
        lines.append("=== ソースにしかないファイル（ターゲットに追加される） ===")
        lines.append(contentsOf: diff.addedLines.compactMap { extractPath(from: $0).map { "  " + $0 } })

        lines.append("")
        lines.append("=== ターゲットにしかないファイル（削除される） ===")
        lines.append(contentsOf: diff.deletedLines.compactMap { extractPath(from: $0).map { "  " + $0 } })

        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    private static func baseArgs(rsync: String) -> [String] {
        var args = ["-rlt", "--delete", "--modify-window=2"]
        for pattern in excludePatterns {
            args += ["--exclude=\(pattern)"]
        }
        return args
    }

    private static func trailingSlash(_ url: URL) -> String {
        url.path.hasSuffix("/") ? url.path : url.path + "/"
    }

    private static func extractPath(from itemizeLine: String) -> String? {
        // 例: ">f+++++++++ path/to/file" / "*deleting   path/to/file"
        guard let range = itemizeLine.range(of: #"\s+"#, options: .regularExpression) else { return nil }
        return String(itemizeLine[range.upperBound...])
    }
}
