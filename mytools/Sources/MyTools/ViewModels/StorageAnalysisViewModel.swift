import Foundation
import AppKit

/// 「ストレージ分析」ペイン用。任意フォルダ配下を再帰スキャンし、直下フォルダ別の内訳
/// (横棒グラフ表示)と、大きいファイル一覧(複数選択してゴミ箱へ移動)を提供する。
@MainActor
final class StorageAnalysisViewModel: ObservableObject {
    @Published var rootPath: String {
        didSet {
            UserDefaults.standard.set(rootPath, forKey: "storageAnalysis.root")
            if hasScanned {
                hasScanned = false
                breakdown = []
                largeFiles = []
                totalSize = 0
                status = ""
            }
        }
    }
    @Published var breakdown: [StorageBreakdownItem] = []
    @Published var largeFiles: [LargeFileItem] = []
    @Published var totalSize: Int64 = 0
    @Published var isScanning = false
    @Published var isDeleting = false
    @Published var hasScanned = false
    @Published var status = ""
    /// 削除に失敗した項目があるときのエラーダイアログ用メッセージ。
    @Published var errorMessage: String?

    private static let defaultRoot = FileManager.default.homeDirectoryForCurrentUser.path

    init() {
        rootPath = UserDefaults.standard.string(forKey: "storageAnalysis.root") ?? Self.defaultRoot
    }

    var rootExists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: rootPath, isDirectory: &isDir) && isDir.boolValue
    }

    var selectedFiles: [LargeFileItem] { largeFiles.filter { $0.isSelected } }
    var selectedSize: Int64 { selectedFiles.reduce(0) { $0 + $1.size } }
    var hasSelection: Bool { !selectedFiles.isEmpty }

    func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootPath = url.path
    }

    func scan() async {
        guard rootExists else {
            status = "フォルダが見つかりません。"
            return
        }
        isScanning = true
        status = ""
        let root = URL(fileURLWithPath: rootPath)
        let result = await Task.detached(priority: .userInitiated) {
            StorageAnalyzer.scan(root: root)
        }.value
        breakdown = result.breakdown
        largeFiles = result.largeFiles
        totalSize = result.totalSize
        hasScanned = true
        isScanning = false
        if largeFiles.isEmpty {
            status = "\(ByteFmt.string(StorageAnalyzer.largeFileThresholdBytes)) 以上の大きいファイルは見つかりませんでした。"
        }
    }

    func deleteSelected() async {
        isDeleting = true
        let urls = selectedFiles.map { $0.url }
        var result = await Task.detached(priority: .userInitiated) {
            FileRemover.moveToTrash(urls)
        }.value
        // 権限エラーなどで失敗した分は Finder 経由で再試行する
        if !result.failures.isEmpty {
            result = FileRemover.retryWithFinder(result)
        }
        let trashedSet = Set(result.trashed)
        largeFiles.removeAll { trashedSet.contains($0.url) }
        isDeleting = false

        status = "\(result.trashed.count) 件をゴミ箱に移動しました。"
        if var detail = result.failureMessage() {
            detail += "\n\n使用中のファイルや、フルディスクアクセスの許可が必要な場所は移動できないことがあります。"
            errorMessage = detail
        }
    }

    func setAllSelected(_ value: Bool) {
        for index in largeFiles.indices {
            largeFiles[index].isSelected = value
        }
    }
}
