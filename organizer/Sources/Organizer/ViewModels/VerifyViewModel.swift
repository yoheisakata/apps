import Foundation
import AppKit

@MainActor
final class VerifyViewModel: ObservableObject {
    @Published var rootPath: String
    @Published var mode: VerifyMode = .report

    private static let defaultRoot = "/Users/yohei/Library/CloudStorage/OneDrive-Personal/s-leo/0_Photo/2026"

    init() {
        rootPath = UserDefaults.standard.string(forKey: "verify.root") ?? Self.defaultRoot
    }

    var rootExists: Bool {
        FileManager.default.fileExists(atPath: rootPath)
    }

    func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootPath = url.path
        UserDefaults.standard.set(rootPath, forKey: "verify.root")
    }

    func run() {
        UserDefaults.standard.set(rootPath, forKey: "verify.root")
        let root = URL(fileURLWithPath: rootPath)
        let mode = self.mode
        let extensions = PhotosViewModel.photoExtensions
        let title: String
        switch mode {
        case .report: title = "写真検証 (確認のみ)"
        case .dryRun: title = "写真検証 (Dry run)"
        case .fix: title = "写真検証 (修正実行)"
        }

        JobRunner.shared.run(kind: .verify, title: title) { handle in
            // PhotoVerifier.runは同期・ブロッキング(sips/mdlsをファイルごとに同期実行)なので、
            // MainActor上のこのTaskで直接呼ぶとスキャン中ずっとUIが固まる(「ハングしたように見える」原因)。
            // Task.detachedでバックグラウンドに逃がし、中止はhandle.onCancelで明示的に伝播する。
            let scan = Task.detached(priority: .userInitiated) {
                try PhotoVerifier.run(
                    root: root,
                    mode: mode,
                    extensions: extensions,
                    progress: { handle.appendLog($0) },
                    setDetail: { handle.setDetail($0) },
                    checkCancel: { try Task.checkCancellation() }
                )
            }
            handle.onCancel { scan.cancel() }
            _ = try await scan.value
        }
    }
}
