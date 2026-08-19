import Foundation

/// YouTubeプレイリスト(単発動画のURLも可 ― yt-dlpは1本だけの「プレイリスト」として扱う)を
/// `yt-dlp --flat-playlist --dump-json` で軽量にスキャンし、`VideoItem`一覧を得るクライアント。
/// `--flat-playlist`は各動画の実際の配信フォーマットを解決しない(=個々の動画ページを
/// 開かない)ため、数百本規模のプレイリストでも数秒〜十数秒で列挙できる
/// (`downloader/Sources/Downloader/YtDlpManager.fetchTitle`が単発タイトル取得に使っているのと
/// 同じ考え方)。実際のダウンロード(動画+音声の取得・結合)は`DownloadStore`が再生時に
/// 別途yt-dlpを起動して行う ― ここでは一覧の取得だけを担当する。
enum YouTubePlaylistClient {
    private struct FlatEntry: Decodable {
        let id: String
        let title: String?
        let duration: Double?
        let playlistTitle: String?
    }

    static func fetchPlaylist(url: String) async throws -> (sourceName: String, videos: [VideoItem]) {
        let start = DispatchTime.now()
        let result = try await fetchPlaylistImpl(url: url)
        Log.scan.info("YouTubePlaylistClient.fetchPlaylist(\(result.sourceName, privacy: .public)): \(result.videos.count)件 (\(Log.elapsedMs(since: start), format: .fixed(precision: 1))ms)")
        return result
    }

    private static func fetchPlaylistImpl(url: String) async throws -> (sourceName: String, videos: [VideoItem]) {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw YouTubePlaylistError.invalidURL }
        guard let ytdlp = ToolLocator.locate("yt-dlp") else { throw YouTubePlaylistError.toolNotFound }

        return try await Task.detached(priority: .userInitiated) {
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: ytdlp)
            // `--ignore-errors`: プレイリスト中の非公開・削除済み動画1本のエラーで
            // 全体の取得が失敗しないようにする(取得できた分だけ返す)。
            proc.arguments = ["--flat-playlist", "--dump-json", "--no-warnings", "--ignore-errors", trimmed]
            // `Core/DownloadStore.swift`の`startYouTubeDownload`と同じ理由で明示的な`PATH`を
            // 渡す(2026-08-14追加) ― `--flat-playlist`はフォーマット解決(JSチャレンジ解決が
            // 必要になる経路)を通常スキップするため影響は小さいはずだが、念のため揃えている。
            var environment = ProcessInfo.processInfo.environment
            let homebrewPaths = "/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/bin"
            environment["PATH"] = homebrewPaths + ":" + (environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            proc.environment = environment

            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            do {
                try proc.run()
            } catch {
                throw YouTubePlaylistError.launchFailed(error.localizedDescription)
            }
            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            proc.waitUntilExit()

            let lines = (String(data: outData, encoding: .utf8) ?? "")
                .split(separator: "\n")
                .map(String.init)

            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            var videos: [VideoItem] = []
            var playlistTitle: String?
            for line in lines {
                guard let data = line.data(using: .utf8),
                      let entry = try? decoder.decode(FlatEntry.self, from: data) else { continue }
                if playlistTitle == nil { playlistTitle = entry.playlistTitle }
                videos.append(VideoItem(
                    url: URL(string: "https://www.youtube.com/watch?v=\(entry.id)")!,
                    title: entry.title ?? entry.id,
                    channel: "",
                    modifiedDate: nil,
                    fileExtension: "mp4",
                    folderPath: [],
                    remoteID: entry.id,
                    remoteKind: .youtube,
                    thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(entry.id)/hqdefault.jpg"),
                    knownDurationSeconds: entry.duration
                ))
            }

            guard !videos.isEmpty else {
                let errText = String(data: errData, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                throw YouTubePlaylistError.empty(errText.isEmpty ? "動画が見つかりませんでした" : errText)
            }
            return (playlistTitle ?? videos[0].title, videos)
        }.value
    }
}

enum YouTubePlaylistError: LocalizedError {
    case invalidURL
    case toolNotFound
    case launchFailed(String)
    case empty(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URLが空です"
        case .toolNotFound:
            return "yt-dlpが見つかりません(brew install yt-dlpでインストールしてください)"
        case .launchFailed(let message):
            return "yt-dlpの起動に失敗しました(\(message))"
        case .empty(let message):
            return "YouTubeから読み込めませんでした(\(message))"
        }
    }
}
