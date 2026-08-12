import Foundation
import AppKit

/// 「OneDrive同期」ペイン用。汎用の「同期」ペイン(2つのHDD間の丸ごとミラーリング)と違い、
/// OneDrive直下には同期不要な巨大フォルダ(動画アーカイブ等)も混在するため丸ごと同期には
/// 向かない。ソース直下のサブフォルダをチェックボックスで選び、選んだサブフォルダだけを
/// 1つずつRsyncSyncにかける(誤配置修正のTarget配列+ループと同じパターン)。
///
/// シングルトン(`shared`)にしている理由: `ContentView`のサイドバー切り替えは選択中の
/// ペインを`switch`で出し分けており、他のペインに切り替えて戻ると`OneDriveSyncView`自体が
/// 作り直される。以前は`@StateObject`でこのクラスを直接生成していたため、そのたびに
/// `results`(直近の差分確認結果)が空に戻ってしまっていた。`JobRunner.shared`と同じ
/// パターンでインスタンスをアプリ全体で1つに固定し、Viewが作り直されても状態が
/// 生き続けるようにする。
@MainActor
final class OneDriveSyncViewModel: ObservableObject {
    static let shared = OneDriveSyncViewModel()

    struct FolderDiffResult: Identifiable, Codable {
        var id: String { name }
        let name: String
        let diff: SyncDiff
        /// 差分確認、または同期成功でこの結果が確定した時刻(UIに「同期済み (HH:mm)」等で表示する)。
        let checkedAt: Date
        /// ソース/ターゲットそれぞれのフォルダ合計サイズ(バイト)とファイル数。差分確認の
        /// たびに実測し、rsyncの差分検出結果を待たず目視でも「だいたい同じ量か」を
        /// 確認できるようにする。
        var sourceSizeBytes: Int64 = 0
        var targetSizeBytes: Int64 = 0
        var sourceFileCount: Int = 0
        var targetFileCount: Int = 0
    }

    /// 差分確認1件分(追加/更新/削除いずれか1ファイル)。ジョブログへのテキスト出力とは別に、
    /// UI側で色分け・整形したテーブル表示を作るために保持する。
    struct FileChange: Identifiable, Codable {
        enum Kind: Codable { case added, modified, deleted }

        let id: UUID
        let folder: String
        let kind: Kind
        let path: String
        /// 更新(.modified)のときだけ`RsyncSync.changeReason(from:)`の結果が入る。
        let reason: String?

        init(folder: String, kind: Kind, path: String, reason: String?) {
            self.id = UUID()
            self.folder = folder
            self.kind = kind
            self.path = path
            self.reason = reason
        }
    }

    @Published var sourceRoot: String {
        didSet {
            UserDefaults.standard.set(sourceRoot, forKey: "oneDriveSync.source")
            scanSubfolders()
            results = []
        }
    }
    @Published var targetRoot: String {
        didSet {
            UserDefaults.standard.set(targetRoot, forKey: "oneDriveSync.target")
            results = []
        }
    }
    @Published private(set) var subfolders: [String] = []
    @Published var selectedSubfolders: Set<String> {
        didSet { UserDefaults.standard.set(Array(selectedSubfolders), forKey: "oneDriveSync.selected") }
    }
    /// アプリを終了して再起動しても直近の差分確認結果を表示したままにするため、
    /// 変更のたびにUserDefaultsへJSONで永続化する(`sourceRoot`/`selectedSubfolders`等の
    /// 設定はもともと永続化されていたのに、肝心の結果だけメモリ上限りだったための対応)。
    @Published var results: [FolderDiffResult] = [] {
        didSet { Self.saveResults(results) }
    }
    /// 直近の差分確認で見つかった追加/更新/削除ファイルの一覧(表示用)。フォルダをまたいで
    /// フラットに保持し、Viewの「変更ファイル」テーブルがこれをそのまま描画する。
    @Published var fileChanges: [FileChange] = [] {
        didSet { Self.saveFileChanges(fileChanges) }
    }
    @Published var showConfirm = false
    /// ONにするとrsyncに`--size-only`を渡し、サイズだけで比較して更新日時の違いは無視する。
    /// OneDriveは中身が同じファイルでも同期のたびにローカルmtimeがズレることがあり、既定の
    /// サイズ+mtime比較だと実質差分のないファイルが大量に「更新」として出てしまうための対策。
    @Published var sizeOnly: Bool {
        didSet {
            UserDefaults.standard.set(sizeOnly, forKey: "oneDriveSync.sizeOnly")
            results = []
        }
    }

    private static let defaultSource = ("~/Library/CloudStorage/OneDrive-Personal" as NSString).expandingTildeInPath
    private static let defaultTarget = "/Volumes/backup1/onedrive_backup"

    /// falseなら、まだ選択が一度も保存されていない(初回起動)ことを表す。scanSubfolders()が
    /// 「見つかった全サブフォルダ」を既定選択にする。
    /// 一度でも選択を保存すれば(空集合になっても)以降はそちらを尊重する。
    private let hasSavedSelection: Bool

    init() {
        sourceRoot = UserDefaults.standard.string(forKey: "oneDriveSync.source") ?? Self.defaultSource
        targetRoot = UserDefaults.standard.string(forKey: "oneDriveSync.target") ?? Self.defaultTarget
        if let saved = UserDefaults.standard.array(forKey: "oneDriveSync.selected") as? [String] {
            selectedSubfolders = Set(saved)
            hasSavedSelection = true
        } else {
            selectedSubfolders = []
            hasSavedSelection = false
        }
        sizeOnly = UserDefaults.standard.bool(forKey: "oneDriveSync.sizeOnly")
        results = Self.loadResults()
        fileChanges = Self.loadFileChanges()
        scanSubfolders()
    }

    private static let resultsKey = "oneDriveSync.results"
    private static let fileChangesKey = "oneDriveSync.fileChanges"

    private static func saveResults(_ results: [FolderDiffResult]) {
        guard let data = try? JSONEncoder().encode(results) else { return }
        UserDefaults.standard.set(data, forKey: resultsKey)
    }

    private static func loadResults() -> [FolderDiffResult] {
        guard let data = UserDefaults.standard.data(forKey: resultsKey),
              let decoded = try? JSONDecoder().decode([FolderDiffResult].self, from: data) else { return [] }
        return decoded
    }

    private static func saveFileChanges(_ changes: [FileChange]) {
        guard let data = try? JSONEncoder().encode(changes) else { return }
        UserDefaults.standard.set(data, forKey: fileChangesKey)
    }

    private static func loadFileChanges() -> [FileChange] {
        guard let data = UserDefaults.standard.data(forKey: fileChangesKey),
              let decoded = try? JSONDecoder().decode([FileChange].self, from: data) else { return [] }
        return decoded
    }

    var sourceExists: Bool { FileManager.default.fileExists(atPath: sourceRoot) }
    var targetExists: Bool { FileManager.default.fileExists(atPath: targetRoot) }

    var totalAdd: Int { results.reduce(0) { $0 + $1.diff.addCount } }
    var totalMod: Int { results.reduce(0) { $0 + $1.diff.modCount } }
    var totalDel: Int { results.reduce(0) { $0 + $1.diff.delCount } }
    var hasChanges: Bool { totalAdd + totalMod + totalDel > 0 }

    func pickSource() {
        guard let url = choose() else { return }
        sourceRoot = url.path
    }

    func pickTarget() {
        guard let url = choose() else { return }
        targetRoot = url.path
    }

    private func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// フォルダ合計サイズ・ファイル数の実測(`FileScanner.sizeAndCount(of:)`)は数千ファイル
    /// 規模だと数秒かかりうる同期的な処理のため、`nonisolated`にした上で`Task.detached`で
    /// MainActorから明示的に外して実行する(このViewModel自体は`@MainActor`なので、外さないと
    /// JobRunnerのジョブクロージャ内で呼んだ際にUI更新をブロックしてしまう)。
    nonisolated private static func folderStats(_ url: URL) async -> (size: Int64, count: Int) {
        await Task.detached(priority: .userInitiated) {
            // excludeSyncJunk: true — RsyncSyncの比較対象(.DS_Store/._*を除く)と揃えないと、
            // 「同期済み」なのにサイズ/件数表示だけズレて見える不整合が起きるため。
            // preferLogicalSize: true — OneDriveのクラウド専用(未ダウンロード)ファイルは
            // totalFileAllocatedSize(ローカル実使用量)がほぼ0になり、フォルダサイズが
            // 実際よりはるかに小さく表示されてしまうため、fileSize(論理サイズ)を優先する。
            FileScanner.sizeAndCount(of: url, excludeSyncJunk: true, preferLogicalSize: true)
        }.value
    }

    /// sourceRoot直下のフォルダ一覧を拾い直す。ルートを変更した際、もう存在しない
    /// サブフォルダの選択は落とす。
    func scanSubfolders() {
        let root = URL(fileURLWithPath: sourceRoot)
        guard let items = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            subfolders = []
            selectedSubfolders = []
            return
        }
        let found = items.compactMap { url -> String? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            return url.lastPathComponent
        }
        subfolders = found.sorted()
        if hasSavedSelection {
            selectedSubfolders = selectedSubfolders.intersection(subfolders)
        } else {
            selectedSubfolders = Set(subfolders)
        }
    }

    func selectAll() { selectedSubfolders = Set(subfolders) }
    func selectNone() { selectedSubfolders = [] }

    func checkDiff() {
        let names = subfolders.filter { selectedSubfolders.contains($0) }
        guard !names.isEmpty else { return }
        results = []
        fileChanges = []
        let source = URL(fileURLWithPath: sourceRoot)
        let target = URL(fileURLWithPath: targetRoot)
        let sizeOnly = self.sizeOnly

        JobRunner.shared.run(kind: .oneDriveSync, title: "OneDrive同期差分確認") { [weak self] handle in
            var collected: [FolderDiffResult] = []
            var changes: [FileChange] = []
            for name in names {
                try Task.checkCancellation()
                handle.appendLog("\n### \(name) ###")
                let diff = try await RsyncSync.checkDiff(
                    source: source.appendingPathComponent(name),
                    target: target.appendingPathComponent(name),
                    sizeOnly: sizeOnly,
                    progress: { handle.appendLog($0) },
                    onCancel: { handle.onCancel($0) },
                    checkCancel: { try Task.checkCancellation() }
                )
                for line in diff.addedLines {
                    if let path = RsyncSync.extractPath(from: line) {
                        handle.appendLog("  + \(path)")
                        changes.append(FileChange(folder: name, kind: .added, path: path, reason: nil))
                    }
                }
                for line in diff.modifiedLines {
                    if let path = RsyncSync.extractPath(from: line) {
                        let reason = RsyncSync.changeReason(from: line)
                        handle.appendLog("  ~ \(path)" + (reason.isEmpty ? "" : "  (\(reason))"))
                        changes.append(FileChange(folder: name, kind: .modified, path: path, reason: reason.isEmpty ? nil : reason))
                    }
                }
                for line in diff.deletedLines {
                    if let path = RsyncSync.extractPath(from: line) {
                        handle.appendLog("  - \(path)")
                        changes.append(FileChange(folder: name, kind: .deleted, path: path, reason: nil))
                    }
                }
                handle.appendLog("差分: 追加=\(diff.addCount) 更新=\(diff.modCount) 削除=\(diff.delCount)")

                async let sourceStats = Self.folderStats(source.appendingPathComponent(name))
                async let targetStats = Self.folderStats(target.appendingPathComponent(name))
                let (src, dst) = await (sourceStats, targetStats)
                handle.appendLog("サイズ: ソース=\(ByteFmt.string(src.size))(\(src.count)件) / ターゲット=\(ByteFmt.string(dst.size))(\(dst.count)件)")

                collected.append(FolderDiffResult(
                    name: name, diff: diff, checkedAt: Date(),
                    sourceSizeBytes: src.size, targetSizeBytes: dst.size,
                    sourceFileCount: src.count, targetFileCount: dst.count
                ))
            }
            let totalAdd = collected.reduce(0) { $0 + $1.diff.addCount }
            let totalMod = collected.reduce(0) { $0 + $1.diff.modCount }
            let totalDel = collected.reduce(0) { $0 + $1.diff.delCount }
            handle.appendLog("\n=== 合計 === 追加=\(totalAdd) 更新=\(totalMod) 削除=\(totalDel)")
            await MainActor.run {
                self?.results = collected
                self?.fileChanges = changes
            }
        }
    }

    /// 差分確認済みであることが前提。確認ダイアログを開く。
    func requestSync() {
        guard !results.isEmpty else { return }
        showConfirm = true
    }

    func confirmSync() {
        showConfirm = false
        let source = URL(fileURLWithPath: sourceRoot)
        let target = URL(fileURLWithPath: targetRoot)
        // 差分確認時に対象とした(=ユーザーが確認ダイアログで見た)サブフォルダのみを同期する。
        let names = results.map { $0.name }
        let sizeOnly = self.sizeOnly

        JobRunner.shared.run(kind: .oneDriveSync, title: "OneDrive同期実行") { [weak self] handle in
            var failedNames: [String] = []
            for name in names {
                try Task.checkCancellation()
                handle.appendLog("\n### \(name) ###")
                let exitCode = try await RsyncSync.sync(
                    source: source.appendingPathComponent(name),
                    target: target.appendingPathComponent(name),
                    sizeOnly: sizeOnly,
                    progress: { handle.appendLog($0) },
                    onCancel: { handle.onCancel($0) }
                )
                // exitCode 0 は全ファイル転送成功。OneDriveのクラウド専用ファイルはrsyncが
                // 読もうとした瞬間にダウンロードが走るため、ダウンロードが間に合わないと
                // 「read errors mapping ... Operation timed out」で一部ファイルだけ転送失敗し、
                // rsyncはそれでも他のファイルは転送を続けたうえでexitCode 23(部分転送エラー)で
                // 終わる。これを無視して一律「同期済み」にすると、実際には転送できていない
                // ファイルが残っているのに緑チェックが出てしまう(2026-08-10に発覚した不具合)。
                // そのため成功した場合だけ差分表示を空にし、失敗時は既存の差分表示(差分あり)を
                // そのまま残して警告ログを出す。
                if exitCode == 0 {
                    await MainActor.run {
                        guard let self, let idx = self.results.firstIndex(where: { $0.name == name }) else { return }
                        // 転送成功後はターゲットもソースと同じ内容になっているはずなので、
                        // サイズ・件数表示は直前に実測したソース側の値をそのまま両方に引き継ぐ
                        // (ここで実測し直すと大きいフォルダではまた数秒かかるため)。
                        let sourceBytes = self.results[idx].sourceSizeBytes
                        let sourceCount = self.results[idx].sourceFileCount
                        self.results[idx] = FolderDiffResult(
                            name: name, diff: SyncDiff(), checkedAt: Date(),
                            sourceSizeBytes: sourceBytes, targetSizeBytes: sourceBytes,
                            sourceFileCount: sourceCount, targetFileCount: sourceCount
                        )
                        self.fileChanges.removeAll { $0.folder == name }
                    }
                } else {
                    failedNames.append(name)
                    handle.appendLog("⚠️ \(name): 一部ファイルを転送できませんでした(exit code \(exitCode))。「同期済み」にはしていません。もう一度「差分を確認」→「同期を実行」を試してください。")
                }
            }
            if !failedNames.isEmpty {
                handle.appendLog("\n=== 転送できなかったフォルダ: \(failedNames.joined(separator: ", ")) ===")
            }
        }
    }

    func saveReport() {
        guard !results.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "onedrive_sync_report_\(Date().formatted("yyyyMMdd_HHmmss")).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let source = URL(fileURLWithPath: sourceRoot)
        let target = URL(fileURLWithPath: targetRoot)
        let text = results.map { result in
            RsyncSync.buildReportText(
                source: source.appendingPathComponent(result.name),
                target: target.appendingPathComponent(result.name),
                diff: result.diff
            )
        }.joined(separator: "\n\n" + String(repeating: "=", count: 40) + "\n\n")
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
