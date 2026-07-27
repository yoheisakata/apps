import Foundation
import AppKit

@MainActor
final class EncodeViewModel: ObservableObject {
    @Published var folderPath: String
    @Published var crf: Double = 20
    @Published var preset: String = "slow"
    @Published var remuxOnly = false
    @Published var minSizeMB: Double = 0
    @Published var dryRun = false

    static let presets = ["ultrafast", "superfast", "veryfast", "faster", "fast", "medium", "slow", "slower", "veryslow"]

    init() {
        folderPath = UserDefaults.standard.string(forKey: "encode.folder") ?? "/Volumes/backup1/leo_video"
    }

    var folderExists: Bool {
        FileManager.default.fileExists(atPath: folderPath)
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
        UserDefaults.standard.set(folderPath, forKey: "encode.folder")
    }

    func run() {
        UserDefaults.standard.set(folderPath, forKey: "encode.folder")
        let config = EncodeConfig(
            folder: URL(fileURLWithPath: folderPath),
            crf: Int(crf),
            preset: preset,
            remuxOnly: remuxOnly,
            minSizeMB: minSizeMB,
            dryRun: dryRun
        )

        JobRunner.shared.run(kind: .encode, title: dryRun ? "エンコード (DRY RUN)" : "エンコード") { handle in
            _ = try await H265Encoder.run(
                config: config,
                progress: { handle.appendLog($0) },
                setProgress: { handle.setProgress($0) },
                setDetail: { handle.setDetail($0) },
                onCancel: { handle.onCancel($0) },
                checkCancel: { try Task.checkCancellation() }
            )
        }
    }
}
