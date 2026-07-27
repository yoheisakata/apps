import Foundation
import AppKit

@MainActor
final class ShortClipsViewModel: ObservableObject {
    @Published var folderPath: String
    @Published var maxSeconds: Double = 3
    @Published var clips: [ShortClip] = []

    init() {
        folderPath = UserDefaults.standard.string(forKey: "shortclips.folder") ?? "/Volumes/backup1/leo_video"
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
        UserDefaults.standard.set(folderPath, forKey: "shortclips.folder")
    }

    func run() {
        UserDefaults.standard.set(folderPath, forKey: "shortclips.folder")
        clips = []
        let folder = URL(fileURLWithPath: folderPath)
        let threshold = maxSeconds

        JobRunner.shared.run(kind: .shortClips, title: "短い動画検索") { [weak self] handle in
            let found = try ShortClipFinder.find(
                folder: folder,
                maxSeconds: threshold,
                progress: { handle.appendLog($0) },
                checkCancel: { try Task.checkCancellation() }
            )
            await MainActor.run { self?.clips = found }
        }
    }

    func saveReport() {
        guard !clips.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "short_videos_report.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ShortClipFinder.buildReportText(maxSeconds: maxSeconds, clips: clips)
            .write(to: url, atomically: true, encoding: .utf8)
    }

    func savePlaylist(andPlay: Bool) {
        guard !clips.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "short_videos.m3u"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? ShortClipFinder.buildM3U(clips: clips).write(to: url, atomically: true, encoding: .utf8)
        if andPlay {
            ShortClipFinder.play(playlist: url)
        }
    }
}
