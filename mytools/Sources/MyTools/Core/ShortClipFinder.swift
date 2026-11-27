import Foundation
import AppKit

struct ShortClip: Identifiable {
    var id: String { url.path }
    let url: URL
    let duration: Double
    let sizeMB: Double
}

/// find_short_videos.py の移植。フォルダ内の短い動画を洗い出し、レポートやM3Uプレイリストを作る。
enum ShortClipFinder {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "mts", "m2ts"]
    private static let players = ["iina", "mpv", "vlc"]

    static func find(
        folder: URL,
        maxSeconds: Double,
        progress: @escaping (String) -> Void,
        checkCancel: () throws -> Void
    ) throws -> [ShortClip] {
        let files = MediaOrganizer.collectFiles(in: folder, extensions: videoExtensions)
        progress("対象フォルダ: \(folder.path)")
        progress("閾値: \(maxSeconds) 秒以下")
        progress("動画ファイル数: \(files.count)\n")

        var short: [ShortClip] = []
        for (i, file) in files.enumerated() {
            try checkCancel()
            progress("解析中... [\(i + 1)/\(files.count)] \(file.lastPathComponent)")
            guard let duration = H265Encoder.getDurationSec(file) else { continue }
            if duration <= maxSeconds {
                short.append(ShortClip(url: file, duration: duration, sizeMB: H265Encoder.fileSizeMB(file)))
            }
        }

        progress("")
        if short.isEmpty {
            progress("\(maxSeconds) 秒以下の動画は見つかりませんでした。")
        } else {
            progress("\(short.count) 件見つかりました。")
        }
        return short
    }

    static func buildReportText(maxSeconds: Double, clips: [ShortClip]) -> String {
        var lines = ["\(maxSeconds) 秒以下の動画: \(clips.count) 件", ""]
        for clip in clips {
            lines.append(String(format: "  %5.2f秒  %6.1f MB  %@", clip.duration, clip.sizeMB, clip.url.path))
        }
        return lines.joined(separator: "\n")
    }

    static func buildM3U(clips: [ShortClip]) -> String {
        var lines = ["#EXTM3U"]
        for clip in clips {
            lines.append("#EXTINF:\(Int(clip.duration)),\(clip.url.lastPathComponent)")
            lines.append(clip.url.path)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func findPlayer() -> String? {
        players.first { ToolLocator.isAvailable($0) }
    }

    /// プレイリスト(.m3u)にも単体の動画ファイルにも使える。iina/mpv/vlcのいずれも
    /// 引数に渡されたパスが単体ファイルかプレイリストかを自分で判別して再生する。
    static func play(_ url: URL) {
        if let player = findPlayer(), let path = ToolLocator.resolve(player) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = [url.path]
            try? process.run()
        } else {
            NSWorkspace.shared.open(url)
        }
    }
}
