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
    /// `action == .error`のときだけ非nil。「コーデック取得失敗」だけでは原因(ffprobeが
    /// 見つからない/実行できない/出力が読めない等)が分からず診断しづらいため保持する。
    var errorReason: String? = nil
}

/// `getVideoCodec`の内部実装。失敗理由を区別できるようにする(ffprobe自体が見つからない/
/// 起動できない/タイムアウトした/出力に映像ストリームが無い、などを一括りに`nil`にすると
/// 「なぜ失敗したか」が分からず診断できない — 実際にFull Disk Access権限が原因で
/// 全ファイルのコーデック取得が失敗する不具合の切り分けに使った)。
enum CodecProbeResult {
    case success(String)
    case failure(String)

    var codec: String? {
        if case .success(let c) = self { return c }
        return nil
    }
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
    /// 実際にH.265へ再エンコードした(dry-runでは「する予定」の)ファイルの元サイズ合計(MB)。
    /// remux(コンテナ変換のみ)やskipは対象外 — 「エンコードにどれだけの元サイズが
    /// 必要か」を知るための集計なので、実際に時間のかかる再エンコードだけを数える。
    var encodedSizeMB: Double = 0
    /// 失敗/エラースキップしたファイルの「ファイル名: 理由」一覧。実行ログ本文は
    /// `JobRunner`が3000行を超えると古い方から破棄する(数千ファイル規模の一括実行では
    /// 序盤のログが完了時には既に消えている)ため、件数だけでなく詳細も末尾の結果サマリーに
    /// 残しておかないと「何がどう失敗したか」を辿れなくなる不具合があった。サマリーは
    /// 常にログの最後に追記されるため、ジョブがどれだけ大きくても切り捨てられない。
    var errorDetails: [String] = []

    mutating func add(_ outcome: FileOutcome, sizeMB: Double, detail: String? = nil) {
        switch outcome {
        case .skipped: skipped += 1
        case .remuxed: remuxed += 1
        case .encoded: encoded += 1; encodedSizeMB += sizeMB
        case .failed:
            failed += 1
            if let detail { errorDetails.append(detail) }
        case .errorSkipped:
            errorSkipped += 1
            if let detail { errorDetails.append(detail) }
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

    /// 数千ファイル規模の一括処理では、ディスクI/Oが一瞬詰まる等の理由で
    /// ごく稀に(実績: 9332件中2件)ffprobeの出力取得が一時的に失敗することがある
    /// (該当ファイルを個別に確認すると正常なhevc/mp4だった)。1回失敗しただけで
    /// 「コーデック取得失敗」として本来エンコード不要なファイルをスキップ扱いに
    /// してしまわないよう、間を置いて1回だけ再試行する。
    static func probeVideoCodec(_ url: URL) -> CodecProbeResult {
        let first = probeVideoCodecOnce(url)
        if case .success = first { return first }
        Thread.sleep(forTimeInterval: 0.3)
        return probeVideoCodecOnce(url)
    }

    private static func probeVideoCodecOnce(_ url: URL) -> CodecProbeResult {
        guard let ffprobe = ToolLocator.resolve("ffprobe") else {
            return .failure("ffprobeが見つかりません（brew install ffmpeg でインストールしてください）")
        }
        let output: String
        do {
            output = try SyncExec.run(ffprobe, [
                "-v", "quiet", "-print_format", "json",
                "-show_streams", "-select_streams", "v:0", url.path,
            ])
        } catch {
            return .failure("ffprobeの実行に失敗（\(error.localizedDescription)）。フルディスクアクセス権限を確認してください")
        }
        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return .failure("ffprobeの出力が読めません（出力が空、または権限エラーの可能性）")
        }
        guard let streams = json["streams"] as? [[String: Any]], let first = streams.first else {
            return .failure("映像ストリームが見つかりません（音声のみ、または壊れたファイルの可能性）")
        }
        guard let codec = first["codec_name"] as? String else {
            return .failure("codec_nameが取得できません")
        }
        return .success(codec.lowercased())
    }

    static func getVideoCodec(_ url: URL) -> String? {
        probeVideoCodec(url).codec
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

    static func formatETA(_ seconds: Double) -> String {
        if seconds < 60 { return "1分未満" }
        let totalMin = Int((seconds / 60).rounded())
        let hours = totalMin / 60
        let min = totalMin % 60
        return hours > 0 ? "\(hours)時間\(min)分" : "\(min)分"
    }

    static func collectVideoFiles(in folder: URL) -> [URL] {
        MediaOrganizer.collectFiles(in: folder, extensions: videoExtensions)
            .filter { !$0.deletingPathExtension().lastPathComponent.contains("_h265") }
    }

    /// `processFile`と同じ判定順序(H.265+mp4→skip、サイズ未満→skip、H.265のみ→remux、
    /// remuxOnly→skip、それ以外→encode)をffmpegを呼ばずに再現する。「スキャン」表示用に
    /// 実際の`run`と結果がずれないよう、判定ロジックを分岐ごと重複させず追従させること。
    static func analyze(
        files: [URL], minSizeMB: Double, remuxOnly: Bool,
        onProgress: (Int, Int) -> Void = { _, _ in }
    ) -> [EncodeCandidate] {
        var results: [EncodeCandidate] = []
        for (i, url) in files.enumerated() {
            onProgress(i + 1, files.count)
            let probeResult = probeVideoCodec(url)
            let sizeMB = fileSizeMB(url)
            guard let codec = probeResult.codec else {
                let reason: String
                if case .failure(let message) = probeResult { reason = message } else { reason = "不明なエラー" }
                results.append(EncodeCandidate(url: url, codec: nil, action: .error, sizeMB: sizeMB, errorReason: reason))
                continue
            }
            let alreadyMp4 = url.pathExtension.lowercased() == "mp4"
            let isH265Flag = isH265(codec)
            let action: EncodeAction
            if isH265Flag && alreadyMp4 {
                action = .skip
            } else if minSizeMB > 0 && sizeMB < minSizeMB {
                action = .skip
            } else if isH265Flag && !alreadyMp4 {
                action = .remux
            } else if remuxOnly {
                action = .skip
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
        setOverallProgress: @escaping (Double?) -> Void = { _ in },
        setOverallDetail: @escaping (String) -> Void = { _ in },
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
        progress("動画ファイル: \(files.count)件")

        // ジョブ全体の進捗は「今処理中の1件のffmpeg進捗」(setProgress、ファイルごとにリセット)
        // とは別に、「実際に再エンコードが必要な件数のうち何件終わったか」を出す
        // (スキップ/リマックスは一瞬で終わるため、全ファイル数を分母にすると
        // 実際の作業量とかけ離れた%になってしまう)。判定は`analyze`(processFileと同じ
        // 判定ロジック)を先に1回通して求める。
        try checkCancel()
        progress("エンコード対象を確認中…")
        let candidates = analyze(files: files, minSizeMB: config.minSizeMB, remuxOnly: config.remuxOnly)
        let encodeTargets = Set(candidates.filter { $0.action == .encode }.map(\.url))
        let encodeTotal = encodeTargets.count
        progress(encodeTotal > 0 ? "エンコード対象: \(encodeTotal)件\n" : "エンコードが必要なファイルはありません\n")
        if encodeTotal > 0 {
            setOverallProgress(0)
            setOverallDetail("0 / \(encodeTotal)件（エンコード対象）")
        }
        var encodeDone = 0
        // 残り時間は「エンコード対象の処理を開始してからの経過時間 ÷ 完了件数」を
        // 1件あたりの平均所要時間とみなし、残り件数に掛けて見積もる(ダウンロードの
        // 残り時間表示等でよく使われる単純な線形外挿)。ファイルごとの長さ・解像度で
        // 実際の所要時間はばらつくため目安に過ぎない。1件も終わっていない段階では
        // 見積もりようがないので出さない。
        let encodeStartTime = Date()

        for (i, url) in files.enumerated() {
            try checkCancel()
            setProgress(nil)
            progress("[\(i + 1)/\(files.count)] \(url.lastPathComponent)")

            let (outcome, sizeMB, detail) = await processFile(
                url,
                label: "[\(i + 1)/\(files.count)] \(url.lastPathComponent)",
                crf: config.crf, preset: config.preset, remuxOnly: config.remuxOnly,
                minSizeMB: config.minSizeMB, dryRun: config.dryRun,
                progress: progress, setProgress: setProgress, setDetail: setDetail, onCancel: onCancel
            )
            result.add(outcome, sizeMB: sizeMB, detail: detail)

            if encodeTargets.contains(url) {
                encodeDone += 1
                setOverallProgress(Double(encodeDone) / Double(encodeTotal))
                let remaining = encodeTotal - encodeDone
                if remaining > 0 {
                    let elapsed = Date().timeIntervalSince(encodeStartTime)
                    let etaSec = elapsed / Double(encodeDone) * Double(remaining)
                    setOverallDetail("\(encodeDone) / \(encodeTotal)件（エンコード対象） - 残り約\(formatETA(etaSec))")
                } else {
                    setOverallDetail("\(encodeDone) / \(encodeTotal)件（エンコード対象）")
                }
            }
        }

        progress("\n=== エンコード結果 ===")
        progress("  スキップ: \(result.skipped)件")
        progress("  コンテナ変換のみ: \(result.remuxed)件")
        progress("  H.265エンコード: \(result.encoded)件")
        progress("  失敗: \(result.failed)件")
        progress("  エラースキップ: \(result.errorSkipped)件")
        if result.encoded > 0 {
            progress("  エンコード対象の合計サイズ(元サイズ): \(ByteFmt.string(Int64(result.encodedSizeMB * 1024 * 1024)))")
        }
        if !result.errorDetails.isEmpty {
            progress("  失敗/エラーの詳細:")
            for line in result.errorDetails {
                progress("    - \(line)")
            }
        }
        return result
    }

    /// 1ファイル分の判定(skip/remux/encode)と実行。`run`（フォルダ一括）と、動画整理の移動直後フックの
    /// 両方から呼ばれる共通処理。戻り値の`sizeMB`は元ファイルのサイズ(`EncodeResult.encodedSizeMB`の
    /// 集計に使う。呼び出し側で改めて`fileSizeMB`を呼び直さなくて済むようここで一緒に返す)。
    static func processFile(
        _ url: URL,
        label: String,
        crf: Int, preset: String, remuxOnly: Bool, minSizeMB: Double, dryRun: Bool,
        progress: @escaping (String) -> Void,
        setProgress: @escaping (Double?) -> Void,
        setDetail: @escaping (String) -> Void,
        onCancel: (@escaping () -> Void) -> Void
    ) async -> (outcome: FileOutcome, sizeMB: Double, detail: String?) {
        let sizeMB = fileSizeMB(url)
        let probeResult = probeVideoCodec(url)
        guard let codec = probeResult.codec else {
            let reason: String
            if case .failure(let message) = probeResult { reason = message } else { reason = "不明なエラー" }
            progress("  [SKIP] コーデック取得失敗: \(reason)")
            return (.errorSkipped, sizeMB, "\(url.lastPathComponent): コーデック取得失敗 - \(reason)")
        }
        let alreadyMp4 = url.pathExtension.lowercased() == "mp4"
        let isH265Flag = isH265(codec)
        progress("  コーデック: \(codec), 拡張子: .\(url.pathExtension.lowercased())")

        if isH265Flag && alreadyMp4 {
            progress("  → スキップ（H.265かつ.mp4）")
            return (.skipped, sizeMB, nil)
        }

        if minSizeMB > 0 && sizeMB < minSizeMB {
            progress("  → スキップ（\(String(format: "%.1f", sizeMB)) MB < 最小 \(minSizeMB) MB）")
            return (.skipped, sizeMB, nil)
        }

        let tmpDst = url.deletingLastPathComponent()
            .appendingPathComponent(url.deletingPathExtension().lastPathComponent + "_h265.mp4")

        if isH265Flag && !alreadyMp4 {
            progress("  → .mp4にコンテナ変換（再エンコードなし）")
            setDetail("\(label) - コンテナ変換中")
            do {
                try await remux(src: url, dst: tmpDst, dryRun: dryRun, progress: progress, setProgress: setProgress, onCancel: onCancel)
                finalize(src: url, tmpDst: tmpDst, dryRun: dryRun, progress: progress)
                return (.remuxed, sizeMB, nil)
            } catch {
                progress("  [ERROR] \(error.localizedDescription)")
                return (.failed, sizeMB, "\(url.lastPathComponent): \(error.localizedDescription)")
            }
        } else if remuxOnly {
            progress("  → スキップ（H.265でないためエンコードが必要、remux-onlyモード）")
            return (.skipped, sizeMB, nil)
        } else {
            progress("  → H.265に再エンコード")
            setDetail("\(label) - エンコード中")
            do {
                try await encode(src: url, dst: tmpDst, crf: crf, preset: preset, dryRun: dryRun, progress: progress, setProgress: setProgress, onCancel: onCancel)
                finalize(src: url, tmpDst: tmpDst, dryRun: dryRun, progress: progress)
                return (.encoded, sizeMB, nil)
            } catch {
                progress("  [ERROR] \(error.localizedDescription)")
                return (.failed, sizeMB, "\(url.lastPathComponent): \(error.localizedDescription)")
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
