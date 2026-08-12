import Foundation

struct SyncDiff: Codable {
    var addCount = 0
    var modCount = 0   // 追加を除く更新
    var delCount = 0
    var addedLines: [String] = []
    var modifiedLines: [String] = []
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
        sizeOnly: Bool = false,
        progress: @escaping (String) -> Void,
        onCancel: (@escaping () -> Void) -> Void,
        checkCancel: () throws -> Void
    ) async throws -> SyncDiff {
        try validate(source: source, target: target)
        guard let rsync = ToolLocator.resolve("rsync") else { throw SyncError.rsyncMissing }

        progress("差分を確認中...")
        let mismatchExcludes = normalizationMismatchExcludes(source: source, target: target)
        if !mismatchExcludes.isEmpty {
            progress("※ファイル名のUnicode正規化違い(NFC/NFD)により \(mismatchExcludes.count / 2) 件を比較対象から除外しました(内容は一致しているとみなします)")
        }
        var args = baseArgs(rsync: rsync, sizeOnly: sizeOnly, extraExcludes: mismatchExcludes)
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
                diff.modifiedLines.append(line)
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
        sizeOnly: Bool = false,
        progress: @escaping (String) -> Void,
        onCancel: (@escaping () -> Void) -> Void
    ) async throws -> Int32 {
        try validate(source: source, target: target)
        guard let rsync = ToolLocator.resolve("rsync") else { throw SyncError.rsyncMissing }

        let mismatchExcludes = normalizationMismatchExcludes(source: source, target: target)
        if !mismatchExcludes.isEmpty {
            progress("※ファイル名のUnicode正規化違い(NFC/NFD)により \(mismatchExcludes.count / 2) 件を同期対象から除外しました")
        }
        var args = baseArgs(rsync: rsync, sizeOnly: sizeOnly, extraExcludes: mismatchExcludes)
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

    /// `sizeOnly`はrsyncの`--size-only`を付け、サイズだけで比較して更新日時の違いは無視する
    /// (OneDriveは中身が同じファイルでも同期のたびにローカルmtimeがズレることがあり、既定の
    /// サイズ+mtime比較だと実質差分のない大量のファイルが「更新」として検出されてしまうため)。
    /// `extraExcludes`は`normalizationMismatchExcludes`が検出したUnicode正規化違いのパス
    /// (先頭に"/"を付けて転送ルートからの相対パスとして厳密にアンカーする)。
    private static func baseArgs(rsync: String, sizeOnly: Bool = false, extraExcludes: [String] = []) -> [String] {
        var args = ["-rlt", "--delete", "--modify-window=2"]
        if sizeOnly {
            args += ["--size-only"]
        }
        for pattern in excludePatterns {
            args += ["--exclude=\(pattern)"]
        }
        for path in extraExcludes {
            args += ["--exclude=/\(path)"]
        }
        return args
    }

    /// ソース/ターゲット双方を直接列挙し、見た目は同じだがUnicode正規化(NFC/NFD)が異なる
    /// ために互いに「相手には存在しない」と誤判定される相対パスの一覧を返す(NFC形・実際の
    /// バイト表現の両方を含む — どちらの形でrsyncの`--exclude`にマッチさせる必要があるか
    /// 事前には分からないため)。
    ///
    /// 発端(2026-08-10): OneDriveは常にNFC(結合済み)でファイル名を返すが、一部の外付け
    /// exFATボリュームはmacOSが書き込み時に自動でNFD(分解形、濁点/半濁点付きかな等が
    /// 「基底文字+結合文字」に分かれる)へ正規化して格納する。ファイル名を明示的にNFCへ
    /// リネームしてもこの自動正規化により元に戻ってしまうため(実機で確認済み)、
    /// リネームでは恒久的に直せない。rsyncは`--iconv`でこの種の文字コード差を吸収できる
    /// 場合があるが、送受信とも同一ホスト上のローカルパス同士(リモート接続なし)の
    /// 転送ではワイヤプロトコル上のiconv変換が働かず効果がなかった(実機で確認済み)。
    /// そのため比較・転送の対象からこのアプリ側で明示的に除外する方式を取っている。
    /// 「名探偵コナン」フォルダで実際に112件(内容は完全に一致)発覚し、放置すると
    /// `--delete`付きの実同期でこれらのファイルが誤って削除される(誤検出ではなく実害)
    /// ところだった。
    static func normalizationMismatchExcludes(source: URL, target: URL) -> [String] {
        let sourceRaw = relativePaths(under: source)
        let targetRaw = relativePaths(under: target)
        let sourceNFCSet = Set(sourceRaw.map { $0.precomposedStringWithCanonicalMapping })
        let targetNFCSet = Set(targetRaw.map { $0.precomposedStringWithCanonicalMapping })

        var excludes: Set<String> = []
        for raw in targetRaw {
            let nfc = raw.precomposedStringWithCanonicalMapping
            if !bytesEqual(raw, nfc), sourceNFCSet.contains(nfc) {
                excludes.insert(raw)
                excludes.insert(nfc)
            }
        }
        for raw in sourceRaw {
            let nfc = raw.precomposedStringWithCanonicalMapping
            if !bytesEqual(raw, nfc), targetNFCSet.contains(nfc) {
                excludes.insert(raw)
                excludes.insert(nfc)
            }
        }
        return Array(excludes)
    }

    /// SwiftのStringの`==`/`!=`はUnicode正規化を考慮した等価性比較(canonical equivalence)を
    /// 行うため、NFCとNFDのように正規化形式だけが異なる文字列は(バイト列が違っても)
    /// `==`で真になってしまう。rsyncはファイル名をバイト単位で比較するため、この関数では
    /// あえてUTF-8バイト列同士を比較し、正規化形式が実際に異なるかどうかを判定する
    /// (2026-08-11に発覚: `raw != nfc`という素朴な比較のせいで`normalizationMismatchExcludes`が
    /// 常に空を返しており、除外が一度も効いていなかった不具合の修正)。
    private static func bytesEqual(_ a: String, _ b: String) -> Bool {
        Array(a.utf8) == Array(b.utf8)
    }

    /// root配下のファイル(ディレクトリを除く)を、rootからの相対パスのまま(正規化しない、
    /// OSがreaddirで返す生のバイト表現のまま)再帰列挙する。
    private static func relativePaths(under root: URL) -> [String] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles],
            errorHandler: { _, _ in true }
        ) else { return [] }

        let rootPath = root.path
        var result: [String] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else { continue }
            var rel = url.path
            if rel.hasPrefix(rootPath) {
                rel = String(rel.dropFirst(rootPath.count))
                if rel.hasPrefix("/") { rel.removeFirst() }
            }
            result.append(rel)
        }
        return result
    }

    private static func trailingSlash(_ url: URL) -> String {
        url.path.hasSuffix("/") ? url.path : url.path + "/"
    }

    /// 例: ">f+++++++++ path/to/file" / "*deleting   path/to/file" からpath部分だけ取り出す。
    static func extractPath(from itemizeLine: String) -> String? {
        guard let range = itemizeLine.range(of: #"\s+"#, options: .regularExpression) else { return nil }
        return String(itemizeLine[range.upperBound...])
    }

    /// itemize-changesの更新行(例: ">f..t......")から、何が変わったために更新扱いになったかを
    /// 日本語で説明する文字列を作る。先頭2文字(">f")の次の9文字がcstpoguax相当のフラグで、
    /// '.'や' '以外の文字が立っている属性だけを拾う。このアプリの同期は`-rlt`(チェックサム比較
    /// なし)のため、実運用でよく見るのは's'(サイズ)と't'(更新日時)。OneDriveはファイルの中身が
    /// 同じでも同期のたびにローカルmtimeがズレることがあり、その場合は't'だけが立つ
    /// (=見た目上は「更新」だが実質タイムスタンプ差のみ、ということがログから判別できる)。
    static func changeReason(from itemizeLine: String) -> String {
        guard itemizeLine.count > 11 else { return "" }
        let flags = itemizeLine.prefix(11).dropFirst(2)
        let labels: [Character: String] = [
            "c": "内容", "s": "サイズ", "t": "更新日時",
            "p": "権限", "o": "所有者", "g": "グループ", "a": "ACL", "x": "拡張属性",
        ]
        let reasons = flags.compactMap { labels[$0] }
        return reasons.isEmpty ? "" : reasons.joined(separator: "・") + "変更"
    }
}
