import Foundation

enum ResolverError: LocalizedError {
    case invalidURL
    case toolMissing(String)
    case network(String)
    case extraction(String)
    case ytdlpFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "URL を認識できません。"
        case .toolMissing(let name): return "\(name) が見つかりません(Homebrew でインストールしてください)。"
        case .network(let detail): return "ページの取得に失敗しました: \(detail)"
        case .extraction(let detail): return "音声リンクを検出できませんでした: \(detail)"
        case .ytdlpFailed(let detail): return "yt-dlp の実行に失敗しました: \(detail)"
        }
    }
}

/// 曲リンク(YouTube / Suno / MusicCreator.ai / MusicGPT / 直リンク mp3 等)を
/// 再生可能な Track に解決する。
enum LinkResolver {
    /// ブラウザからのアクセスに見せかけるための UA。一部サイトは既定の UA だと
    /// サーバレンダリングを簡略化したページを返すことがある。
    private static let browserUA =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15"

    static func resolve(urlString: String, ytdlpPath: String?, ffmpegPath: String?, cacheDir: URL) async throws -> Track {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let host = url.host?.lowercased() else {
            throw ResolverError.invalidURL
        }

        if host.contains("youtube.com") || host.contains("youtu.be") {
            return try await resolveYouTube(url: trimmed, ytdlpPath: ytdlpPath, ffmpegPath: ffmpegPath, cacheDir: cacheDir)
        }
        if host.contains("suno.com") || host.contains("suno.ai") {
            return try await resolveViaHTML(url: url, site: .suno, extractAudio: extractSunoAudioURL)
        }
        if host.contains("musiccreator.ai") {
            return try await resolveViaHTML(url: url, site: .musicCreator, extractAudio: extractOGAudioURL)
        }
        if host.contains("musicgpt.com") {
            return try await resolveViaHTML(url: url, site: .musicGpt, extractAudio: extractMusicGPTAudioURL)
        }
        if ["mp3", "m4a", "wav", "flac", "aac"].contains(url.pathExtension.lowercased()) {
            return Track(sourceURL: trimmed, title: url.lastPathComponent, site: .direct, audioURL: trimmed)
        }
        // 未対応サイトでも og:audio を持っていれば汎用的に再生できる可能性がある。
        return try await resolveViaHTML(url: url, site: .other, extractAudio: extractOGAudioURL)
    }

    // MARK: - HTML ベースの解決 (Suno / MusicCreator.ai / MusicGPT / 汎用)

    private static func resolveViaHTML(
        url: URL, site: SiteKind, extractAudio: (String) -> String?
    ) async throws -> Track {
        var request = URLRequest(url: url)
        request.setValue(browserUA, forHTTPHeaderField: "User-Agent")

        let data: Data
        do {
            let (d, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw ResolverError.network("HTTP エラー")
            }
            data = d
        } catch let error as ResolverError {
            throw error
        } catch {
            throw ResolverError.network(error.localizedDescription)
        }

        guard let html = String(data: data, encoding: .utf8) else {
            throw ResolverError.network("文字コードを判別できません")
        }
        guard let audioURL = extractAudio(html) else {
            throw ResolverError.extraction("\(site.label) のページ構造が想定と異なります")
        }
        let title = extractMeta(html, property: "og:title") ?? url.lastPathComponent
        let artwork = extractMeta(html, property: "og:image")
        return Track(sourceURL: url.absoluteString, title: title, site: site, artworkURL: artwork, audioURL: audioURL)
    }

    /// `<meta property="og:xxx" content="...">` (属性の順序違いにも対応)。
    private static func extractMeta(_ html: String, property: String) -> String? {
        let patterns = [
            #"<meta[^>]*(?:property|name)=["']"# + NSRegularExpression.escapedPattern(for: property) + #"["'][^>]*content=["']([^"']*)["']"#,
            #"<meta[^>]*content=["']([^"']*)["'][^>]*(?:property|name)=["']"# + NSRegularExpression.escapedPattern(for: property) + #"["']"#,
        ]
        for pattern in patterns {
            if let value = firstMatch(pattern, in: html) {
                return decodeHTMLEntities(value)
            }
        }
        return nil
    }

    /// musiccreator.ai は og:audio に直接 mp3 URL を出している。
    private static func extractOGAudioURL(_ html: String) -> String? {
        extractMeta(html, property: "og:audio")
    }

    /// suno.com は埋め込み JSON (`"audio_url":"https://cdn1.suno.ai/....mp3"`) にある。
    /// この JSON は Next.js の RSC ペイロード(`self.__next_f.push([1, "...文字列..."])`)の
    /// 文字列リテラルの中に丸ごと入っているため、実際のバイト列では各 `"` の前に `\` が付く
    /// (例: `\"audio_url\":\"https://...\"`)。バックスラッシュの有無どちらにも対応させる。
    private static func extractSunoAudioURL(_ html: String) -> String? {
        firstMatch(#"\\?"audio_url\\?"\s*:\s*\\?"(https:[^"\\]+\.mp3)"#, in: html)
    }

    /// musicgpt.com も同様に Next.js の RSC ペイロード内にエスケープされた JSON
    /// (`\"file_output_0\":\"https://....mp3\"`) として埋め込まれている。
    private static func extractMusicGPTAudioURL(_ html: String) -> String? {
        firstMatch(#"\\?"file_output_0\\?"\s*:\s*\\?"(https:[^"\\]+\.mp3)"#, in: html)
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range), match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func decodeHTMLEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    // MARK: - YouTube (yt-dlp でローカルに mp3 抽出してキャッシュ)

    private static func resolveYouTube(
        url: String, ytdlpPath: String?, ffmpegPath: String?, cacheDir: URL
    ) async throws -> Track {
        guard let ytdlp = ytdlpPath else { throw ResolverError.toolMissing("yt-dlp") }
        guard let ffmpeg = ffmpegPath else { throw ResolverError.toolMissing("ffmpeg") }
        try FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: ytdlp)
        proc.arguments = [
            "--no-playlist",
            "--restrict-filenames",
            "--quiet", "--no-warnings",
            "-x", "--audio-format", "mp3", "--audio-quality", "0",
            "--ffmpeg-location", ffmpeg,
            "-o", cacheDir.appendingPathComponent("%(id)s.%(ext)s").path,
            // タブ区切りの3フィールドだけを出力させる。`--print-json` はフォーマット一覧まで
            // 全部含むため OS のパイプバッファ(macOS は既定 64KB)を軽く超え、後述のデッドロックの
            // 引き金になりやすい。`after_move:` ステージを明示するのが必須 — 接頭辞なしの
            // `--print TEMPLATE` はこの yt-dlp バージョンでは実際のダウンロード/音声抽出そのものを
            // 行わずに(`[info] Downloading N format(s)` の行だけ出して)即終了してしまい、
            // ファイルが一切作られない不具合を実機で確認した。`after_move:` は「最終ファイルへの
            // 移動が完了した後」に評価されるステージなので、確実にダウンロード+音声抽出が
            // 終わってから出力される。
            "--print", "after_move:%(id)s\t%(title)s\t%(thumbnail)s",
            url,
        ]
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardOutput = outPipe
        proc.standardError = errPipe

        // 子プロセスの標準出力/標準エラーは OS のパイプバッファ(数万バイト程度)を超えて
        // 書き込もうとするとブロックする。terminationHandler の中で readDataToEndOfFile する
        // (=プロセスが終わるまで誰も読まない)実装だと、大量出力時に「子プロセスは write()
        // でブロックして終了できない → terminationHandler も呼ばれない」という相互待ちの
        // デッドロックに陥る(実際に --print-json で発生した不具合)。readabilityHandler で
        // 実行中から継続的に吸い出すことで根本的に回避する(downloader/YtDlpManager.swift と同じ方式)。
        let outBuffer = PipeBuffer()
        let errBuffer = PipeBuffer()
        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { outBuffer.append(data) }
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty { errBuffer.append(data) }
        }

        return try await withCheckedThrowingContinuation { continuation in
            proc.terminationHandler = { p in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                // プロセス終了後にまだパイプに残っている分(小さいはずだが念のため)を読み切る。
                let tailOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                let tailErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                if !tailOut.isEmpty { outBuffer.append(tailOut) }
                if !tailErr.isEmpty { errBuffer.append(tailErr) }

                guard p.terminationStatus == 0 else {
                    let errText = String(data: errBuffer.data, encoding: .utf8) ?? "unknown error"
                    continuation.resume(throwing: ResolverError.ytdlpFailed(String(errText.suffix(300))))
                    return
                }
                let outText = String(data: outBuffer.data, encoding: .utf8) ?? ""
                let line = outText
                    .split(whereSeparator: \.isNewline)
                    .last(where: { !$0.isEmpty }) ?? ""
                let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard let id = fields.first.map(String.init), !id.isEmpty else {
                    continuation.resume(throwing: ResolverError.ytdlpFailed("動画 ID を取得できませんでした"))
                    return
                }
                let title = fields.count > 1 ? String(fields[1]) : id
                let thumbnailField = fields.count > 2 ? String(fields[2]) : nil
                let thumbnail = (thumbnailField == "NA") ? nil : thumbnailField

                // `--print`/`--print-json` はどちらも音声抽出(-x)による post-process **前**の
                // 一時ファイル(webm 等)の情報しか持たず、変換後の最終 mp3 パスには追随しない。
                // 出力テンプレートは自分で指定している(`%(id)s.%(ext)s` + `--audio-format mp3`)ので、
                // 最終ファイルパスは yt-dlp の出力を信用せず `id` から組み立てる。
                let path = cacheDir.appendingPathComponent("\(id).mp3")
                guard FileManager.default.fileExists(atPath: path.path) else {
                    continuation.resume(throwing: ResolverError.ytdlpFailed("出力ファイルが見つかりません: \(path.lastPathComponent)"))
                    return
                }
                let track = Track(
                    sourceURL: url, title: title, site: .youtube,
                    artworkURL: thumbnail, audioURL: path.absoluteString
                )
                continuation.resume(returning: track)
            }
            do {
                try proc.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: ResolverError.ytdlpFailed(error.localizedDescription))
            }
        }
    }
}

/// `Process` の標準出力/標準エラーをバックグラウンドスレッド(readabilityHandler)から
/// 書き込みつつ、終了後にメインスレッドから読み出すための最小限のスレッドセーフなバッファ。
private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = Data()

    func append(_ chunk: Data) {
        lock.lock()
        storage.append(chunk)
        lock.unlock()
    }

    var data: Data {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
