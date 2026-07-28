import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
final class VideoMakerViewModel: ObservableObject {
    @Published var folderPath: String
    @Published var musicPath: String
    @Published var outputPath = ""
    @Published var videos: [URL] = []
    @Published var selectedVideos = Set<URL>()
    @Published var durationMode: DurationMode = .total
    @Published var qualityPreset: Int = 18 // CRF: 低いほど高画質
    @Published var clipSec: Int = 8
    @Published var totalSec: Int = 30
    @Published var offsetSec: Int = 3
    @Published var bgmVolume: Double = 0.3
    @Published var origVolume: Double = 0.7
    @Published var transitionSec: Double = 0.5
    @Published var titleText = ""
    @Published var maxFileCount: Int = 0
    @Published var useMaxFileCount = false
    @Published var randomMode = false
    @Published var showOverwriteConfirm = false

    init() {
        folderPath = UserDefaults.standard.string(forKey: "videoMaker.folder") ?? "/Volumes/backup1/leo_video"
        musicPath = UserDefaults.standard.string(forKey: "videoMaker.musicPath") ?? ""
    }

    var folderExists: Bool {
        FileManager.default.fileExists(atPath: folderPath)
    }

    var totalDisplay: String {
        let t = clipSec * videos.count
        return "\(t / 60)分\(String(format: "%02d", t % 60))秒"
    }

    var clipDisplay: String {
        guard !videos.isEmpty else { return "-" }
        let c = Double(totalSec) / Double(videos.count)
        return String(format: "%.1f秒", c)
    }

    func loadDefaults() {
        if outputPath.isEmpty {
            outputPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/まとめ動画.mp4").path
        }
        refreshVideos()
    }

    /// フォルダパス変更時(ピッカー・直接編集どちらでも)に動画一覧とタイトル初期値を再スキャンする。
    func refreshVideos() {
        guard folderExists else { videos = []; return }
        titleText = VideoMaker.detectTitle(from: folderPath)
        videos = VideoMaker.findVideos(in: URL(fileURLWithPath: folderPath))
        applyFileLimits()
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
        UserDefaults.standard.set(folderPath, forKey: "videoMaker.folder")
        refreshVideos()
    }

    func pickMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        musicPath = url.path
        UserDefaults.standard.set(musicPath, forKey: "videoMaker.musicPath")
    }

    func clearMusic() {
        musicPath = ""
        UserDefaults.standard.removeObject(forKey: "videoMaker.musicPath")
    }

    func pickOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mp4")!]
        panel.nameFieldStringValue = "まとめ動画.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputPath = url.path
    }

    func removeSelected() {
        videos.removeAll { selectedVideos.contains($0) }
        selectedVideos.removeAll()
    }

    func revealInFinder() {
        NSWorkspace.shared.selectFile(outputPath, inFileViewerRootedAtPath: "")
    }

    func playOutput() {
        NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
    }

    func applyFileLimits() {
        var list = videos
        if randomMode {
            list.shuffle()
        } else {
            list.sort { $0.path < $1.path }
        }
        if useMaxFileCount, maxFileCount > 0, list.count > maxFileCount {
            list = Array(list.prefix(maxFileCount))
        }
        videos = list
    }

    func generate() {
        if FileManager.default.fileExists(atPath: outputPath) {
            showOverwriteConfirm = true
            return
        }
        startGenerate()
    }

    func startGenerate() {
        let config = VideoMakerConfig(
            videos: videos,
            titleText: titleText,
            musicPath: musicPath,
            outputPath: outputPath,
            durationMode: durationMode,
            clipSec: clipSec,
            totalSec: totalSec,
            offsetSec: offsetSec,
            bgmVolume: bgmVolume,
            origVolume: origVolume,
            transitionSec: transitionSec,
            qualityPreset: qualityPreset
        )
        JobRunner.shared.run(kind: .videoMaker, title: "まとめ動画を作成") { handle in
            try await VideoMaker.generate(
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
