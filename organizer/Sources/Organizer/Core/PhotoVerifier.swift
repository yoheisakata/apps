import Foundation

enum VerifyMode { case report, dryRun, fix }

struct VerifyIssue {
    let kind: String
    let file: URL
    let expected: URL
    let dateSource: String
}

struct VerifyResult {
    var issues: [VerifyIssue] = []
    var okCount = 0
    var fixed = 0
    var skippedDuplicate = 0
}

enum PhotoVerifierError: Error, LocalizedError {
    case rootNotFound(URL)
    var errorDescription: String? {
        switch self {
        case .rootNotFound(let url): return "フォルダが見つかりません: \(url.path)"
        }
    }
}

/// verify-photos.sh の移植。想定構造 <root>/<MM>/<MMDD>/YYYY_MMDD_HHMMSS.<ext> を検証・修正する。
/// rootは年フォルダ（例: .../0_Photo/2026）を渡す想定。
enum PhotoVerifier {
    private static let expectedNamePattern = #"^\d{4}_\d{4}_\d{6}(_\d+)?\."#
    private static let suffixedPattern = #"^(\d{4}_\d{4}_\d{6})_\d+(\..+)$"#

    static func run(
        root: URL,
        mode: VerifyMode,
        extensions: Set<String>,
        progress: @escaping (String) -> Void,
        setDetail: @escaping (String) -> Void = { _ in },
        checkCancel: () throws -> Void
    ) throws -> VerifyResult {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDir), isDir.boolValue else {
            throw PhotoVerifierError.rootNotFound(root)
        }

        let base = root.deletingLastPathComponent()
        var result = VerifyResult()

        progress("スキャン中: \(root.path)")
        progress("モード: \(modeLabel(mode))\n")

        guard let monthDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return result
        }

        for monthDir in monthDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try checkCancel()
            guard (try? monthDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard !monthDir.lastPathComponent.hasPrefix("."), monthDir.lastPathComponent.fullyMatches(#"\d{2}"#) else { continue }

            guard let items = try? fm.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }

            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try checkCancel()
                if item.lastPathComponent.hasPrefix(".") { continue }

                let isItemDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

                // MM直下にある写真ファイル(MMDDフォルダの下にない)
                if !isItemDir, extensions.contains(item.pathExtension.lowercased()) {
                    setDetail(item.lastPathComponent)
                    let resolved = MediaDateResolver.resolve(for: item, primarySources: [MediaDateResolver.fromSips])
                    let expectedDir = base
                        .appendingPathComponent(resolved.date.formatted("yyyy"))
                        .appendingPathComponent(resolved.date.formatted("MM"))
                        .appendingPathComponent(resolved.date.formatted("MMdd"))
                    let newName = "\(resolved.date.formatted("yyyy_MMdd_HHmmss")).\(item.pathExtension.lowercased())"
                    result.issues.append(VerifyIssue(kind: "MM直下ファイル", file: item, expected: expectedDir.appendingPathComponent(newName), dateSource: resolved.source))
                    continue
                }

                guard isItemDir, !item.lastPathComponent.isEmpty, item.lastPathComponent.first!.isNumber else { continue }

                guard let files = enumerateFiles(in: item, extensions: extensions) else { continue }
                for file in files.sorted(by: { $0.path < $1.path }) {
                    try checkCancel()
                    setDetail(file.lastPathComponent)
                    let resolved = MediaDateResolver.resolve(for: file, primarySources: [MediaDateResolver.fromSips])
                    let year = resolved.date.formatted("yyyy")
                    let month = resolved.date.formatted("MM")
                    let mmdd = resolved.date.formatted("MMdd")
                    let ts = resolved.date.formatted("yyyy_MMdd_HHmmss")
                    let ext = file.pathExtension.lowercased()
                    let newName = "\(ts).\(ext)"
                    let expectedDir = base.appendingPathComponent(year).appendingPathComponent(month).appendingPathComponent(mmdd)

                    let nameOK = file.lastPathComponent.range(of: expectedNamePattern, options: .regularExpression) != nil
                    let folderOK = file.deletingLastPathComponent().standardizedFileURL == expectedDir.standardizedFileURL

                    if let g = file.lastPathComponent.firstMatchGroups(suffixedPattern), g.count == 2, folderOK {
                        let baseName = g[0] + g[1].lowercased()
                        let baseCandidate = file.deletingLastPathComponent().appendingPathComponent(baseName)
                        if !fm.fileExists(atPath: baseCandidate.path) {
                            result.issues.append(VerifyIssue(kind: "suffix除去", file: file, expected: baseCandidate, dateSource: resolved.source))
                            continue
                        } else {
                            result.okCount += 1
                            continue
                        }
                    }

                    if nameOK && folderOK {
                        result.okCount += 1
                        continue
                    }

                    var kinds: [String] = []
                    if !nameOK { kinds.append("名前") }
                    if !folderOK { kinds.append("フォルダ") }
                    result.issues.append(VerifyIssue(kind: kinds.joined(separator: "+"), file: file, expected: expectedDir.appendingPathComponent(newName), dateSource: resolved.source))
                }
            }
        }

        progress(String(repeating: "=", count: 50))
        progress("  問題あり: \(result.issues.count) 件 / 正常: \(result.okCount) 件")
        progress(String(repeating: "=", count: 50) + "\n")

        switch mode {
        case .report:
            for issue in result.issues.prefix(50) {
                progress("  [\(issue.kind)] \(relativePath(issue.file, base: base))")
                progress("    → \(relativePath(issue.expected, base: base))  (\(issue.dateSource))")
            }
            if result.issues.count > 50 {
                progress("\n  ...他 \(result.issues.count - 50) 件（Dry runまたは修正実行で全件確認）")
            }

        case .dryRun:
            for issue in result.issues {
                progress("  [\(issue.kind)] \(relativePath(issue.file, base: base))")
                progress("    → \(relativePath(issue.expected, base: base))  (\(issue.dateSource))")
            }
            progress("\n処理予定: \(result.issues.count) 件")

        case .fix:
            for issue in result.issues {
                try checkCancel()
                let (dst, isDuplicate) = safeMove(from: issue.file, to: issue.expected, fm: fm)
                if isDuplicate {
                    progress("  SKIP(同一): \(issue.file.lastPathComponent)")
                    result.skippedDuplicate += 1
                } else {
                    progress("  FIX [\(issue.kind)]: \(issue.file.lastPathComponent) -> \(relativePath(dst, base: base))  (\(issue.dateSource))")
                    result.fixed += 1
                }
            }
            removeEmptySubfolders(of: root, fm: fm)
            progress("\n修正: \(result.fixed) 件  スキップ: \(result.skippedDuplicate) 件")
        }

        return result
    }

    private static func modeLabel(_ mode: VerifyMode) -> String {
        switch mode {
        case .report: return "report"
        case .dryRun: return "dry-run"
        case .fix: return "fix"
        }
    }

    private static func relativePath(_ url: URL, base: URL) -> String {
        let baseComps = base.standardizedFileURL.pathComponents
        let urlComps = url.standardizedFileURL.pathComponents
        guard urlComps.starts(with: baseComps) else { return url.path }
        return urlComps.dropFirst(baseComps.count).joined(separator: "/")
    }

    private static func enumerateFiles(in dir: URL, extensions: Set<String>) -> [URL]? {
        guard let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { return nil }
        var files: [URL] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
            guard extensions.contains(url.pathExtension.lowercased()) else { continue }
            files.append(url)
        }
        return files
    }

    /// 重複を考慮して移動する。既に同一ファイルが存在すれば元を削除してSKIP、内容が違えばsuffixを付けて移動。
    private static func safeMove(from src: URL, to dst: URL, fm: FileManager) -> (URL, Bool) {
        if fm.fileExists(atPath: dst.path) {
            let same = (try? FileHasher.md5(of: src)) == (try? FileHasher.md5(of: dst))
            if same {
                try? fm.removeItem(at: src)
                return (dst, true)
            }
            let stem = dst.deletingPathExtension().lastPathComponent
            let ext = dst.pathExtension
            var n = 1
            var candidate = dst.deletingLastPathComponent().appendingPathComponent("\(stem)_\(n).\(ext)")
            while fm.fileExists(atPath: candidate.path) {
                n += 1
                candidate = dst.deletingLastPathComponent().appendingPathComponent("\(stem)_\(n).\(ext)")
            }
            try? fm.createDirectory(at: candidate.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: src, to: candidate)
            return (candidate, false)
        } else {
            try? fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.moveItem(at: src, to: dst)
            return (dst, false)
        }
    }

    private static func removeEmptySubfolders(of root: URL, fm: FileManager) {
        guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return }
        var dirs: [URL] = []
        for case let url as URL in enumerator {
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                dirs.append(url)
            }
        }
        for dir in dirs.sorted(by: { $0.pathComponents.count > $1.pathComponents.count }) {
            if let contents = try? fm.contentsOfDirectory(atPath: dir.path), contents.isEmpty {
                try? fm.removeItem(at: dir)
            }
        }
    }
}
