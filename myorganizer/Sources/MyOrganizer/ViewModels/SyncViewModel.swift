import Foundation
import AppKit

@MainActor
final class SyncViewModel: ObservableObject {
    @Published var sourcePath: String
    @Published var targetPath: String
    @Published var lastDiff: SyncDiff?
    @Published var showConfirm = false
    @Published var errorMessage: String?

    init() {
        sourcePath = UserDefaults.standard.string(forKey: "sync.source") ?? "/Volumes/backup1"
        targetPath = UserDefaults.standard.string(forKey: "sync.target") ?? "/Volumes/backup2"
    }

    var sourceExists: Bool { FileManager.default.fileExists(atPath: sourcePath) }
    var targetExists: Bool { FileManager.default.fileExists(atPath: targetPath) }

    func pickSource() {
        guard let url = choose() else { return }
        sourcePath = url.path
        UserDefaults.standard.set(sourcePath, forKey: "sync.source")
        lastDiff = nil
    }

    func pickTarget() {
        guard let url = choose() else { return }
        targetPath = url.path
        UserDefaults.standard.set(targetPath, forKey: "sync.target")
        lastDiff = nil
    }

    private func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    func checkDiff() {
        UserDefaults.standard.set(sourcePath, forKey: "sync.source")
        UserDefaults.standard.set(targetPath, forKey: "sync.target")
        lastDiff = nil
        errorMessage = nil
        let source = URL(fileURLWithPath: sourcePath)
        let target = URL(fileURLWithPath: targetPath)

        JobRunner.shared.run(kind: .sync, title: "同期差分確認") { [weak self] handle in
            let diff = try await RsyncSync.checkDiff(
                source: source, target: target,
                progress: { handle.appendLog($0) },
                onCancel: { handle.onCancel($0) },
                checkCancel: { try Task.checkCancellation() }
            )
            handle.appendLog("\n差分: 追加=\(diff.addCount) 更新=\(diff.modCount) 削除=\(diff.delCount)")
            await MainActor.run { self?.lastDiff = diff }
        }
    }

    /// 差分確認済みであることが前提。確認ダイアログを開く。
    func requestSync() {
        guard lastDiff != nil else { return }
        showConfirm = true
    }

    func confirmSync() {
        showConfirm = false
        let source = URL(fileURLWithPath: sourcePath)
        let target = URL(fileURLWithPath: targetPath)

        JobRunner.shared.run(kind: .sync, title: "同期実行") { handle in
            _ = try await RsyncSync.sync(
                source: source, target: target,
                progress: { handle.appendLog($0) },
                onCancel: { handle.onCancel($0) }
            )
        }
    }

    func saveReport() {
        guard let diff = lastDiff else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "sync_backups_report_\(Date().formatted("yyyyMMdd_HHmmss")).txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = RsyncSync.buildReportText(
            source: URL(fileURLWithPath: sourcePath),
            target: URL(fileURLWithPath: targetPath),
            diff: diff
        )
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }
}
