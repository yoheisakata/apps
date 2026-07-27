import Foundation

enum EncodeAction {
    case skip     // 既にH.265+mp4
    case remux    // H.265だが.mov等 → コンテナ変換のみ
    case encode   // H.265以外 → 再エンコード
    case error    // コーデック取得失敗
}

struct EncodeCandidate {
    let url: URL
    let codec: String?
    let action: EncodeAction
    let sizeMB: Double
}

struct EncodeConfig {
    let folder: URL
    let crf: Int
    let preset: String
    let remuxOnly: Bool
    let minSizeMB: Double
    let dryRun: Bool
}

struct EncodeResult {
    var skipped = 0       // 既にH.265+mp4、またはサイズ不足でスキップ
    var remuxed = 0
    var encoded = 0
    var failed = 0
    var errorSkipped = 0

    mutating func add(_ outcome: FileOutcome) {
        switch outcome {
        case .skipped: skipped += 1
        case .remuxed: remuxed += 1
        case .encoded: encoded += 1
        case .failed: failed += 1
        case .errorSkipped: errorSkipped += 1
        }
    }
}

enum FileOutcome {
    case skipped
    case remuxed
    case encoded
    case failed
    case errorSkipped
}

enum EncodeError: Error, LocalizedError {
    case folderNotFound(URL)
    case ffmpegMissing
    case ffmpegFailed(String)

    var errorDescription: String? {
        switch self {
        case .folderNotFound(let url): return "フォルダが見つかりません: \(url.path)"
        case .ffmpegMissing: return "ffmpeg が見つかりません。brew install ffmpeg でインストールしてください"
        case .ffmpegFailed(let tail): return "ffmpeg 失敗:\n\(tail)"
        }
    }
}

/// encode_h265.py / backup-videos.shの「H.265エンコード & mp4統一」ロジックの共通実装。
/// H.265以外→再エンコード、H.265だが.mov→コンテナ変換のみ、H.265+mp4→スキップ。
enum H265Encoder {
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "mkv", "avi", "mts", "m2ts"]

    // MARK: - 解析

    static func getVideoCodec(_ url: URL) -> String? {
        guard let ffprobe = ToolLocator.resolve("ffprobe") else { return nil }
        guard let output = try? SyncExec.run(ffprobe, [
            "-v", "quiet", "-print_format", "json",
            "-show_streams", "-select_streams", "v:0", url.path,
        ]) else { return nil }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let streams = json["streams"] as? [[String: Any]],
              let first = streams.first,
              let codec = first["codec_name"] as? String else { return nil }
        return codec.lowercased()
    }

    static func isH265(_ codec: String?) -> Bool {
        codec == "hevc" || codec == "h265"
    }

    static func getDurationSec(_ url: URL) -> Double? {
        guard let ffprobe = ToolLocator.resolve("ffprobe") else { return nil }
        guard let output = try? SyncExec.run(ffprobe, [
            "-v", "quiet", "-print_format", "json", "-show_format", url.path,
        ]) else { return nil }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let format = json["format"] as? [String: Any],
              let durationStr = format["duration"] as? String else { return nil }
        return Double(durationStr)
    }

    static func fileSizeMB(_ url: URL) -> Double {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return Double(size) / 1024 / 1024
    }

    static func collectVideoFiles(in folder: URL) -> [URL] {
        MediaOrganizer.collectFiles(in: folder, extensions: videoExtensions)
            .filter { !$0.deletingPathExtension().lastPathComponent.contains("_h265") }
    }

    static func analyze(files: [URL], minSizeMB: Double, onProgress: (Int, Int) -> Void = { _, _ in }) -> [EncodeCandidate] {
        var results: [EncodeCandidate] = []
        for (i, url) in files.enumerated() {
            onProgress(i + 1, files.count)
            let codec = getVideoCodec(url)
            let alreadyMp4 = url.pathExtension.lowercased() == "mp4"
            let sizeMB = fileSizeMB(url)
            let action: EncodeAction
            if codec == nil {
                action = .error
            } else if isH265(codec) && alreadyMp4 {
                action = .skip
            } else if isH265(codec) {
                action = .remux
            } else {
                action = .encode
            }
            results.append(EncodeCandidate(url: url, codec: codec, action: action, sizeMB: sizeMB))
        }
        return results
    }

    // MARK: - 実行

    static func run(
        config: EncodeConfig,
        progress: @escaping (String) -> Void,
        setProgress: @escaping (Double?) -> Void,
        setDetail: @escaping (String) -> Void = { _ in },
        onCancel: (@escaping () -> Void) -> Void,
        checkCancel: () throws -> Void
    ) async throws -> EncodeResult {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: config.folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw EncodeError.folderNotFound(config.folder)
        }
        guard ToolLocator.isAvailable("ffmpeg") else {
            throw EncodeError.ffmpegMissing
        }

        let files = collectVideoFiles(in: config.folder)
        var result = EncodeResult()

        progress("対象フォルダ: \(config.folder.path)")
        progress("モード: \(config.dryRun ? "DRY-RUN" : "実行")")
        if config.remuxOnly {
            progress("コンテナ変換のみ（エンコードなし）")
        } else {
            progress("品質(CRF): \(config.crf), 速度: \(config.preset)")
        }
        progress("動画ファイル: \(files.count)件\n")

        for (i, url) in files.enumerated() {
            try checkCancel()
            setProgress(nil)
            progress("[\(i + 1)/\(files.count)] \(url.lastPathComponent)")

            let outcome = await processFile(
                url,
                label: "[\(i + 1)/\(files.count)] \(url.lastPathComponent)",
                crf: config.crf, preset: config.preset, remuxOnly: config.remuxOnly,
                minSizeMB: config.minSizeMB, dryRun: config.dryRun,
                progress: progress, setProgress: setProgress, setDetail: setDetail, onCancel: onCancel
            )
            result.add(outcome)
        }

        progress("\n=== エンコード結果 ===")
        progress("  スキップ: \(result.skipped)件")
        progress("  コンテナ変換のみ: \(result.remuxed)件")
        progress("  H.265エンコード: \(result.encoded)件")
        progress("  失敗: \(result.failed)件")
        progress("  エラースキップ: \(result.errorSkipped)件")
        return result
    }

    /// 1ファイル分の判定(skip/remux/encode)と実行。`run`（フォルダ一括）と、動画整理の移動直後フックの
    /// 両方から呼ばれる共通処理。
    static func processFile(
        _ url: URL,
        label: String,
        crf: Int, preset: String, remuxOnly: Bool, minSizeMB: Double, dryRun: Bool,
        progress: @escaping (String) -> Void,
        setProgress: @escaping (Double?) -> Void,
        setDetail: @escaping (String) -> Void,
        onCancel: (@escaping () -> Void) -> Void
    ) async -> FileOutcome {
        guard let codec = getVideoCodec(url) else {
            progress("  [SKIP] コーデック取得失敗")
            return .errorSkipped
        }
        let alreadyMp4 = url.pathExtension.lowercased() == "mp4"
        let isH265Flag = isH265(codec)
        progress("  コーデック: \(codec), 拡張子: .\(url.pathExtension.lowercased())")

        if isH265Flag && alreadyMp4 {
            progress("  → スキップ（H.265かつ.mp4）")
            return .skipped
        }

        let sizeMB = fileSizeMB(url)
        if minSizeMB > 0 && sizeMB < minSizeMB {
            progress("  → スキップ（\(String(format: "%.1f", sizeMB)) MB < 最小 \(minSizeMB) MB）")
            return .skipped
        }

        let tmpDst = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_h265.mp4")

        if isH265Flag && !alreadyMp4 {
            progress("  → .mp4にコンテナ変換（再エンコードなし）")
            setDetail("\(label) - コンテナ変換中")
            do {
                try await remux(src: url, dst: tmpDst, dryRun: dryRun, progress: progress, setProgress: setProgress, onCancel: onCancel)
                finalize(src: url, tmpDst: tmpDst, dryRun: dryRun, progress: progress)
                return .remuxed
            } catch {
                progress("  [ERROR] \(error.localizedDescription)")
                return .failed
            }
        } else if remuxOnly {
            progress("  → スキップ（H.265でないためエンコードが必要、remux-onlyモード）")
            return .skipped
        } else {
            progress("  → H.265に再エンコード")
            setDetail("\(label) - エンコード中")
            do {
                try await encode(src: url, dst: tmpDst, crf: crf, preset: preset, dryRun: dryRun, progress: progress, setProgress: setProgress, onCancel: onCancel)
                finalize(src: url, tmpDst: tmpDst, dryRun: dryRun, progress: progress)
                return .encoded
            } catch {
                progress("  [ERROR] \(error.localizedDescription)")
                return .failed
            }
        }
    }

    private static func remux(
        src: URL, dst: URL, dryRun: Bool,
        progress: @escaping (String) -> Void,
        setProgress: @escaping (Double?) -> Void,
        onCancel: (@escaping () -> Void) -> Void
    ) async throws {
        if dryRun {
            progress("  [DRY-RUN] remux → \(dst.lastPathComponent)")
            return
        }
        guard let ffmpeg = ToolLocator.resolve("ffmpeg") else { throw EncodeError.ffmpegMissing }
        let args = [
            "-i", src.path,
            "-c", "copy",
            "-tag:v", "hvc1",
            "-map_metadata", "0",
            "-movflags", "+faststart",
            "-y", "-progress", "pipe:1", "-nostats",
            dst.path,
        ]
        try await runFFmpegWithProgress(ffmpeg, args, label: "コンテナ変換中", totalSec: getDurationSec(src), progress: progress, setProgress: setProgress, onCancel: onCancel, failureCleanup: dst)
    }

    private static func encode(
        src: URL, dst: URL, crf: Int, preset: String, dryRun: Bool,
        progress: @escaping (String) -> Void,
        setProgress: @escaping (Double?) -> Void,
        onCancel: (@escaping () -> Void) -> Void
    ) async throws {
        if dryRun {
            progress("  [DRY-RUN] encode H.265 → \(dst.lastPathComponent)")
            return
        }
        guard let ffmpeg = ToolLocator.resolve("ffmpeg") else { throw EncodeError.ffmpegMissing }
        progress("  H.265エンコード開始 (libx265, CRF=\(crf))")
        let args = [
            "-i", src.path,
            "-c:v", "libx265",
            "-crf", String(crf),
            "-preset", preset,
            "-c:a", "aac",
            "-b:a", "128k",
            "-tag:v", "hvc1",
            "-map_metadata", "0",
            "-movflags", "+faststart",
            "-y", "-progress", "pipe:1", "-nostats",
            dst.path,
        ]
        try await runFFmpegWithProgress(ffmpeg, args, label: "エンコード中", totalSec: getDurationSec(src), progress: progress, setProgress: setProgress, onCancel: onCancel, failureCleanup: dst)
    }

    private static func runFFmpegWithProgress(
        _ executable: String, _ arguments: [String], label: String, totalSec: Double?,
        progress: @escaping (String) -> Void,
        setProgress: @escaping (Double?) -> Void,
        onCancel: (@escaping () -> Void) -> Void,
        failureCleanup: URL
    ) async throws {
        let runner = ProcessRunner()
        onCancel { runner.cancel() }

        var lastPct = -1
        var errorTail: [String] = []

        let exitCode = try await runner.run(executable, arguments) { line in
            if line.hasPrefix("out_time_ms=") {
                let msStr = line.dropFirst("out_time_ms=".count)
                if let ms = Int(msStr), let total = totalSec, total > 0 {
                    let pct = min(Double(ms) / (total * 1_000_000), 0.99)
                    if Int(pct * 100) != lastPct {
                        lastPct = Int(pct * 100)
                        setProgress(pct)
                    }
                }
            } else if line.hasPrefix("progress=end") {
                setProgress(1.0)
            } else {
                errorTail.append(line)
                if errorTail.count > 20 { errorTail.removeFirst() }
            }
        }

        progress("  \(label): 完了")
        if exitCode != 0 {
            try? FileManager.default.removeItem(at: failureCleanup)
            throw EncodeError.ffmpegFailed(errorTail.suffix(10).joined(separator: "\n"))
        }
    }

    private static func finalize(src: URL, tmpDst: URL, dryRun: Bool, progress: @escaping (String) -> Void) {
        if dryRun { return }
        let fm = FileManager.default
        let final = src.deletingPathExtension().appendingPathExtension("mp4")
        try? fm.removeItem(at: src)
        if tmpDst != final {
            if fm.fileExists(atPath: final.path) {
                let sizeMB = fileSizeMB(tmpDst)
                progress("  完了 (名前衝突のため \(tmpDst.lastPathComponent) として保存, \(String(format: "%.1f", sizeMB)) MB)")
                return
            }
            try? fm.moveItem(at: tmpDst, to: final)
        }
        let sizeMB = fileSizeMB(final)
        progress("  完了 (\(String(format: "%.1f", sizeMB)) MB)")
    }
}
