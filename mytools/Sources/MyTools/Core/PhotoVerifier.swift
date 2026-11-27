import Foundation

enum VerifyMode { case report, dryRun, fix }

struct VerifyIssue {
    let kind: String
    let file: URL
    let expected: URL
    let dateSource: String
    /// 類似写真フォールバックで日付を借用した場合、借用元のファイル。それ以外は常にnil。
    let matchedFrom: URL?

    init(kind: String, file: URL, expected: URL, dateSource: String, matchedFrom: URL? = nil) {
        self.kind = kind
        self.file = file
        self.expected = expected
        self.dateSource = dateSource
        self.matchedFrom = matchedFrom
    }
}

struct VerifyResult {
    var issues: [VerifyIssue] = []
    var okCount = 0
    var fixed = 0
    var skippedDuplicate = 0
    var failed = 0
    /// 類似写真フォールバックで日付を借用できたファイルの件数(fixモードで実際に移動したかは問わない)。
    var similarityMatched = 0
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
/// monthFilterを渡すと、root直下の月フォルダのうち一致するもの(例: "07")だけを処理する
/// (MisplacedFixViewModelが月単位の修正で使う)。
/// maxFixCountを渡すと、fixモードでは問題が上限件数見つかった時点でスキャン自体を打ち切る
/// (EXIF/mdls呼び出しが主なコストなので、全件スキャンを待たずに済む。検出された問題が多い
/// 場合に一度の実行で大量のファイルを動かさないようにするための機能でもある。report/dryRun
/// モードでは全件を見せたいので上限を適用しない)。
/// similarityIndexを渡すと、EXIF/mdls/フォルダ名/ファイル名のどこからも撮影日が分からず
/// mtimeフォールバックになったファイルについて、見た目が近い(dHash)・EXIF付きの写真が
/// インデックス内にあればその日付を借用する(`類似写真(EXIF)`というdateSourceになる)。
/// 借用に使った元ファイルは`VerifyIssue.matchedFrom`に記録し、report/dryRun/fixのログに
/// 「類似元: ...」として出す(あいまいな根拠に基づく変更なので、実行前に確認できるようにする)。
enum PhotoVerifier {
    private static let expectedNamePattern = #"^\d{4}_\d{4}_\d{6}(_\d+)?\."#
    private static let suffixedPattern = #"^(\d{4}_\d{4}_\d{6})_\d+(\..+)$"#

    /// 進捗バー用に、対象ファイル数を軽量に数える(日付解決はしない。EXIF/mdls呼び出しがない分、
    /// 本処理よりずっと速い)。複数の対象(年・月)をまたいだ「全体の進捗」の分母を出すために使う。
    static func estimateFileCount(root: URL, extensions: Set<String>, monthFilter: String? = nil) -> Int {
        let fm = FileManager.default
        guard let monthDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else { return 0 }
        var count = 0
        for monthDir in monthDirs {
            guard (try? monthDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard !monthDir.lastPathComponent.hasPrefix("."), monthDir.lastPathComponent.fullyMatches(#"\d{2}"#) else { continue }
            if let monthFilter, monthDir.lastPathComponent != monthFilter { continue }
            guard let items = try? fm.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for item in items {
                if item.lastPathComponent.hasPrefix(".") { continue }
                let isItemDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if !isItemDir, extensions.contains(item.pathExtension.lowercased()) {
                    count += 1
                    continue
                }
                guard isItemDir, !item.lastPathComponent.isEmpty, item.lastPathComponent.first!.isNumber else { continue }
                count += enumerateFiles(in: item, extensions: extensions)?.count ?? 0
            }
        }
        return count
    }

    static func run(
        root: URL,
        mode: VerifyMode,
        extensions: Set<String>,
        monthFilter: String? = nil,
        maxFixCount: Int? = nil,
        similarityIndex: LazySimilarityIndex? = nil,
        onFileProcessed: (() -> Void)? = nil,
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
        var scanStoppedEarly = false

        // fixモードでmaxFixCountが指定されている場合、問題が上限件数見つかった時点でスキャン自体を
        // 打ち切る(EXIF/mdls呼び出しが主なコストのため、全件スキャンを待たずに済む)。
        func fixCapReached() -> Bool {
            guard mode == .fix, let maxFixCount else { return false }
            return result.issues.count >= maxFixCount
        }

        progress("スキャン中: \(root.path)")
        progress("モード: \(modeLabel(mode))\n")

        guard let monthDirs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return result
        }

        monthLoop: for monthDir in monthDirs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try checkCancel()
            guard (try? monthDir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
            guard !monthDir.lastPathComponent.hasPrefix("."), monthDir.lastPathComponent.fullyMatches(#"\d{2}"#) else { continue }
            if let monthFilter, monthDir.lastPathComponent != monthFilter { continue }

            guard let items = try? fm.contentsOfDirectory(at: monthDir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }

            for item in items.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try checkCancel()
                if item.lastPathComponent.hasPrefix(".") { continue }

                let isItemDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true

                // MM直下にある写真ファイル(MMDDフォルダの下にない)
                if !isItemDir, extensions.contains(item.pathExtension.lowercased()) {
                    setDetail(item.lastPathComponent)
                    defer { onFileProcessed?() }
                    var resolved = MediaDateResolver.resolve(for: item, primarySources: [MediaDateResolver.fromSips])
                    var matchedFrom: URL?
                    if resolved.source == "mtime", let similarityIndex,
                       let dhash = PerceptualHash.dHash(of: item),
                       let match = try similarityIndex.get().closestMatch(for: dhash) {
                        resolved = ResolvedDate(date: match.date, source: "類似写真(EXIF)")
                        matchedFrom = match.url
                        result.similarityMatched += 1
                    }
                    if resolved.source == "mtime" {
                        result.issues.append(VerifyIssue(kind: "Unknown", file: item, expected: unknownDest(for: item, base: base), dateSource: resolved.source))
                        if fixCapReached() { scanStoppedEarly = true; break monthLoop }
                        continue
                    }
                    let expected = standardDest(base: base, date: resolved.date, ext: item.pathExtension.lowercased())
                    result.issues.append(VerifyIssue(kind: "MM直下ファイル", file: item, expected: expected, dateSource: resolved.source, matchedFrom: matchedFrom))
                    if fixCapReached() { scanStoppedEarly = true; break monthLoop }
                    continue
                }

                guard isItemDir, !item.lastPathComponent.isEmpty, item.lastPathComponent.first!.isNumber else { continue }

                guard let files = enumerateFiles(in: item, extensions: extensions) else { continue }
                for file in files.sorted(by: { $0.path < $1.path }) {
                    try checkCancel()
                    setDetail(file.lastPathComponent)
                    defer { onFileProcessed?() }
                    var resolved = MediaDateResolver.resolve(for: file, primarySources: [MediaDateResolver.fromSips])
                    var matchedFrom: URL?

                    // EXIF/mdls/フォルダ名/ファイル名のいずれからも撮影日が分からず、mtimeまで
                    // フォールバックした場合、まず類似写真フォールバック(あれば)で復旧を試みる。
                    // それでも駄目なら、日付を捏造せずルート直下のUnknownへ元のファイル名のまま
                    // 退避する(誤った年月日フォルダへ誤配置する方が害が大きい)。
                    if resolved.source == "mtime", let similarityIndex,
                       let dhash = PerceptualHash.dHash(of: file),
                       let match = try similarityIndex.get().closestMatch(for: dhash) {
                        resolved = ResolvedDate(date: match.date, source: "類似写真(EXIF)")
                        matchedFrom = match.url
                        result.similarityMatched += 1
                    }
                    if resolved.source == "mtime" {
                        let dest = unknownDest(for: file, base: base)
                        if file.deletingLastPathComponent().standardizedFileURL == dest.deletingLastPathComponent().standardizedFileURL {
                            result.okCount += 1
                        } else {
                            result.issues.append(VerifyIssue(kind: "Unknown", file: file, expected: dest, dateSource: resolved.source))
                            if fixCapReached() { scanStoppedEarly = true; break monthLoop }
                        }
                        continue
                    }

                    let ext = file.pathExtension.lowercased()
                    let expectedDest = standardDest(base: base, date: resolved.date, ext: ext)
                    let expectedDir = expectedDest.deletingLastPathComponent()
                    let newName = expectedDest.lastPathComponent

                    let nameOK = file.lastPathComponent.range(of: expectedNamePattern, options: .regularExpression) != nil
                    let folderOK = file.deletingLastPathComponent().standardizedFileURL == expectedDir.standardizedFileURL

                    if let g = file.lastPathComponent.firstMatchGroups(suffixedPattern), g.count == 2, folderOK {
                        let baseName = g[0] + g[1].lowercased()
                        let baseCandidate = file.deletingLastPathComponent().appendingPathComponent(baseName)
                        if !fm.fileExists(atPath: baseCandidate.path) {
                            result.issues.append(VerifyIssue(kind: "suffix除去", file: file, expected: baseCandidate, dateSource: resolved.source, matchedFrom: matchedFrom))
                            if fixCapReached() { scanStoppedEarly = true; break monthLoop }
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
                    result.issues.append(VerifyIssue(kind: kinds.joined(separator: "+"), file: file, expected: expectedDir.appendingPathComponent(newName), dateSource: resolved.source, matchedFrom: matchedFrom))
                    if fixCapReached() { scanStoppedEarly = true; break monthLoop }
                }
            }
        }

        progress(String(repeating: "=", count: 50))
        if scanStoppedEarly {
            progress("  問題あり: \(result.issues.count) 件以上(上限に達したためスキャンを打ち切り、これ以降は未確認) / 正常: \(result.okCount) 件")
        } else {
            progress("  問題あり: \(result.issues.count) 件 / 正常: \(result.okCount) 件")
        }
        if result.similarityMatched > 0 {
            progress("  うち類似写真から日付を推定: \(result.similarityMatched) 件")
        }
        progress(String(repeating: "=", count: 50) + "\n")

        switch mode {
        case .report:
            for issue in result.issues.prefix(50) {
                progress("  [\(kindLabel(issue))] \(relativePath(issue.file, base: base))")
                progress("    → \(relativePath(issue.expected, base: base))  (\(issue.dateSource))")
                if let line = matchedFromLine(issue, base: base) { progress(line) }
            }
            if result.issues.count > 50 {
                progress("\n  ...他 \(result.issues.count - 50) 件（Dry runまたは修正実行で全件確認）")
            }

        case .dryRun:
            for issue in result.issues {
                progress("  [\(kindLabel(issue))] \(relativePath(issue.file, base: base))")
                progress("    → \(relativePath(issue.expected, base: base))  (\(issue.dateSource))")
                if let line = matchedFromLine(issue, base: base) { progress(line) }
            }
            progress("\n処理予定: \(result.issues.count) 件")

        case .fix:
            let issuesToFix = maxFixCount.map { Array(result.issues.prefix(max(0, $0))) } ?? result.issues
            for issue in issuesToFix {
                try checkCancel()
                do {
                    let (dst, isDuplicate) = try safeMove(from: issue.file, to: issue.expected, fm: fm)
                    if isDuplicate {
                        progress("  SKIP(同一): \(issue.file.lastPathComponent)")
                        if let line = matchedFromLine(issue, base: base) { progress(line) }
                        result.skippedDuplicate += 1
                    } else {
                        progress("  FIX [\(kindLabel(issue))]: \(issue.file.lastPathComponent) -> \(relativePath(dst, base: base))  (\(issue.dateSource))")
                        if let line = matchedFromLine(issue, base: base) { progress(line) }
                        result.fixed += 1
                    }
                } catch {
                    progress("  [ERROR] \(issue.file.lastPathComponent): \(error.localizedDescription)")
                    result.failed += 1
                }
            }
            if scanStoppedEarly, let maxFixCount {
                progress("\n上限(\(maxFixCount)件)に達したため、途中でスキャンを打ち切りました。残りは次回以降の実行で検出されます。")
            }
            let cleanupRoot = monthFilter.map { root.appendingPathComponent($0) } ?? root
            removeEmptySubfolders(of: cleanupRoot, fm: fm)
            progress("\n修正: \(result.fixed) 件  スキップ: \(result.skippedDuplicate) 件  失敗: \(result.failed) 件")
        }

        return result
    }

    /// 撮影日が全く分からないファイルの退避先。ルート(年フォルダ)の親、つまりライブラリ直下の
    /// Unknown/ に、元のファイル名のまま置く(捏造した日付でフォルダ名・ファイル名を作らない)。
    private static func unknownDest(for file: URL, base: URL) -> URL {
        base.appendingPathComponent("Unknown").appendingPathComponent(file.lastPathComponent)
    }

    /// 撮影日から正規の移動先パスを組み立てる: <base>/yyyy/MM/MMdd/yyyy_MMdd_HHmmss.<ext>。
    /// 日付推定ペイン(DateEstimateViewModel)からも、確定した推定日付の移動先を求めるのに使う
    /// (ここでの命名規則が2箇所以上に分散して食い違わないようにするための共有ヘルパー)。
    static func standardDest(base: URL, date: Date, ext: String) -> URL {
        base.appendingPathComponent(date.formatted("yyyy"))
            .appendingPathComponent(date.formatted("MM"))
            .appendingPathComponent(date.formatted("MMdd"))
            .appendingPathComponent("\(date.formatted("yyyy_MMdd_HHmmss")).\(ext)")
    }

    /// 類似写真フォールバックで日付を借用した場合に、借用元をログへ表示する行。
    private static func matchedFromLine(_ issue: VerifyIssue, base: URL) -> String? {
        guard let matchedFrom = issue.matchedFrom else { return nil }
        return "    類似元: \(relativePath(matchedFrom, base: base))"
    }

    /// ログの`[kind]`表示用。類似写真フォールバックで日付を借用した場合は一目でわかるよう
    /// タグを付ける(通常のEXIF/mdls等での解決と混ざって見えないようにするため)。
    private static func kindLabel(_ issue: VerifyIssue) -> String {
        issue.matchedFrom != nil ? "\(issue.kind)・類似写真" : issue.kind
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
    /// 以前は各操作を`try?`で握りつぶしていたため、OneDriveのプレースホルダー(未ダウンロード)ファイル等で
    /// 移動が実際には失敗していてもログ上は「FIX」と表示され続けるバグがあった。エラーは呼び出し側に
    /// 伝播させ、実際に成功した場合だけ`fixed`をカウントする。
    static func safeMove(from src: URL, to dst: URL, fm: FileManager) throws -> (URL, Bool) {
        if fm.fileExists(atPath: dst.path) {
            let same = (try? FileHasher.md5(of: src)) == (try? FileHasher.md5(of: dst))
            if same {
                try fm.removeItem(at: src)
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
            try fm.createDirectory(at: candidate.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: src, to: candidate)
            return (candidate, false)
        } else {
            try fm.createDirectory(at: dst.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.moveItem(at: src, to: dst)
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
