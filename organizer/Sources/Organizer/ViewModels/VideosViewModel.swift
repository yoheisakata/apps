import Foundation
import AppKit

@MainActor
final class VideosViewModel: ObservableObject {
    @Published var srcPath: String
    @Published var destPath: String
    @Published var dryRun = false
    @Published var skipEncode = false
    @Published var crf: Double = 23
    @Published var preset: String = "slow"

    static let videoExtensions: Set<String> = ["mov", "mp4", "m4v", "mkv", "avi", "mts", "m2ts"]

    private static let defaultSrc = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Desktop/photos_video_export").path
    private static let defaultDest = "/Volumes/backup1/leo_video"

    init() {
        srcPath = UserDefaults.standard.string(forKey: "videos.src") ?? Self.defaultSrc
        destPath = UserDefaults.standard.string(forKey: "videos.dest") ?? Self.defaultDest
    }

    func pickSrc() {
        guard let url = choose() else { return }
        srcPath = url.path
        UserDefaults.standard.set(srcPath, forKey: "videos.src")
    }

    func pickDest() {
        guard let url = choose() else { return }
        destPath = url.path
        UserDefaults.standard.set(destPath, forKey: "videos.dest")
    }

    private func choose() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    var sourceExists: Bool { FileManager.default.fileExists(atPath: srcPath) }
    var destExists: Bool { FileManager.default.fileExists(atPath: destPath) }

    var canRun: Bool { sourceExists && destExists }

    /// 整理(移動)と同時に、移動が完了したファイルからその場でH.265エンコードする。
    /// (以前は「全部移動し終えてからdestPath全体を再スキャンしてエンコード」という2パス構成だったが、
    /// 移動直後に1ファイルずつエンコードする1パス構成に変更した)
    func run() {
        UserDefaults.standard.set(srcPath, forKey: "videos.src")
        UserDefaults.standard.set(destPath, forKey: "videos.dest")

        let destRoot = URL(fileURLWithPath: destPath)
        if MediaOrganizer.looksLikeYearFolder(destRoot) {
            showYearFolderAlert(destName: destRoot.lastPathComponent)
            return
        }

        let organizeConfig = OrganizerConfig(
            sourceRoot: URL(fileURLWithPath: srcPath),
            destRoot: destRoot,
            extensions: Self.videoExtensions,
            dateSources: [MediaDateResolver.fromFfprobeQuickTime],
            convertHEICToJPG: false,
            dryRun: dryRun
        )
        let doEncode = !skipEncode
        let crfValue = Int(crf)
        let presetValue = preset
        let dryRunValue = dryRun

        JobRunner.shared.run(kind: .videos, title: dryRun ? "動画整理 (DRY RUN)" : "動画整理") { handle in
            var encodeResult = EncodeResult()

            _ = try await MediaOrganizer.run(
                config: organizeConfig,
                progress: { handle.appendLog($0) },
                setProgress: { handle.setProgress($0) },
                setDetail: { handle.setDetail($0) },
                afterMove: doEncode ? { movedFile in
                    let (outcome, sizeMB, detail) = await H265Encoder.processFile(
                        movedFile,
                        label: movedFile.lastPathComponent,
                        crf: crfValue, preset: presetValue, remuxOnly: false,
                        minSizeMB: 0, dryRun: dryRunValue,
                        progress: { handle.appendLog($0) },
                        setProgress: { handle.setProgress($0) },
                        setDetail: { handle.setDetail($0) },
                        onCancel: { handle.onCancel($0) }
                    )
                    encodeResult.add(outcome, sizeMB: sizeMB, detail: detail)
                } : nil,
                checkCancel: { try Task.checkCancellation() }
            )

            if doEncode {
                handle.appendLog("")
                handle.appendLog("=== エンコード結果 ===")
                handle.appendLog("  スキップ: \(encodeResult.skipped)件")
                handle.appendLog("  コンテナ変換のみ: \(encodeResult.remuxed)件")
                handle.appendLog("  H.265エンコード: \(encodeResult.encoded)件")
                handle.appendLog("  失敗: \(encodeResult.failed)件")
                handle.appendLog("  エラースキップ: \(encodeResult.errorSkipped)件")
                if encodeResult.encoded > 0 {
                    handle.appendLog("  エンコード対象の合計サイズ(元サイズ): \(ByteFmt.string(Int64(encodeResult.encodedSizeMB * 1024 * 1024)))")
                }
                if !encodeResult.errorDetails.isEmpty {
                    handle.appendLog("  失敗/エラーの詳細:")
                    for line in encodeResult.errorDetails {
                        handle.appendLog("    - \(line)")
                    }
                }
            }
        }
    }
}
