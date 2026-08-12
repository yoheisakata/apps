import Foundation
import AppKit

/// 「スキャン」ボタンの結果。実際にエンコード(再エンコード)が必要な残り件数・
/// 合計サイズを、ffmpegを呼ばず`H265Encoder.analyze`のffprobe判定だけで見積もる。
struct EncodeScanSummary {
    let total: Int
    let toEncode: Int
    let toEncodeSizeMB: Double
    let toRemux: Int
    let alreadyDone: Int
    let errorCount: Int
    /// エラーになったファイルの理由(先頭数件のみ)。「コーデック取得失敗」が
    /// 何件あるかだけでなく、なぜ失敗しているか(ffprobeが無い/権限エラー等)を
    /// スキャン結果からその場で分かるようにするため保持する。
    let errorSamples: [String]
}

@MainActor
final class EncodeViewModel: ObservableObject {
    @Published var folderPath: String {
        didSet { scanResult = nil }
    }
    @Published var crf: Double = 23
    @Published var preset: String = "slow"
    @Published var remuxOnly = false {
        didSet { scanResult = nil }
    }
    @Published var minSizeMB: Double = 0 {
        didSet { scanResult = nil }
    }
    @Published var dryRun = false

    @Published private(set) var isScanning = false
    @Published private(set) var scanProgressText = ""
    @Published private(set) var scanResult: EncodeScanSummary?

    /// スキャンのバックグラウンドキューから読むため、`@MainActor`隔離を受けない
    /// ロック付きのフラグとして持つ(単純な`Bool`だと actor-isolated プロパティを
    /// 非isolatedコンテキストから触ることになりコンパイラ警告が出る)。
    private let scanCancelFlag = CancelFlag()
    private let scanQueue = DispatchQueue(label: "organizer.encode.scan", qos: .userInitiated)

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

    /// ffmpegを呼ばず、対象フォルダ配下の動画をffprobeだけで判定して
    /// 「あとどれだけエンコードが必要か」を見積もる(実際の変換は行わない)。
    func scan() {
        guard !isScanning, folderExists else { return }
        isScanning = true
        scanCancelFlag.set(false)
        scanProgressText = "ファイルを探しています…"
        scanResult = nil
        let folder = URL(fileURLWithPath: folderPath)
        let minSizeMB = self.minSizeMB
        let remuxOnly = self.remuxOnly
        let cancelFlag = scanCancelFlag

        scanQueue.async { [weak self] in
            let files = H265Encoder.collectVideoFiles(in: folder)
            let candidates = H265Encoder.analyze(files: files, minSizeMB: minSizeMB, remuxOnly: remuxOnly) { done, total in
                if cancelFlag.get() { return }
                DispatchQueue.main.async { self?.scanProgressText = "\(done) / \(total) 件を確認中…" }
            }
            guard let self else { return }
            if cancelFlag.get() {
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.scanProgressText = ""
                }
                return
            }
            let toEncode = candidates.filter { $0.action == .encode }
            let errors = candidates.filter { $0.action == .error }
            let summary = EncodeScanSummary(
                total: candidates.count,
                toEncode: toEncode.count,
                toEncodeSizeMB: toEncode.reduce(0) { $0 + $1.sizeMB },
                toRemux: candidates.filter { $0.action == .remux }.count,
                alreadyDone: candidates.filter { $0.action == .skip }.count,
                errorCount: errors.count,
                errorSamples: errors.prefix(3).map { "\($0.url.lastPathComponent): \($0.errorReason ?? "不明なエラー")" }
            )
            DispatchQueue.main.async {
                self.scanResult = summary
                self.isScanning = false
                self.scanProgressText = ""
            }
        }
    }

    func cancelScan() {
        scanCancelFlag.set(true)
    }

    func run() {
        UserDefaults.standard.set(folderPath, forKey: "encode.folder")
        if !dryRun { scanResult = nil }
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
                setOverallProgress: { handle.setOverallProgress($0) },
                setOverallDetail: { handle.setOverallDetail($0) },
                onCancel: { handle.onCancel($0) },
                checkCancel: { try Task.checkCancellation() }
            )
        }
    }
}

/// スキャンのキャンセル要求フラグ。バックグラウンドキューとメインアクターの両方から
/// 触るため、`@MainActor`隔離を受けない独立した型としてロックで保護する
/// (`VideoDupViewModel`等の`Counter`と同じ考え方)。
private final class CancelFlag: @unchecked Sendable {
    private var value = false
    private let lock = NSLock()
    func set(_ v: Bool) { lock.lock(); value = v; lock.unlock() }
    func get() -> Bool { lock.lock(); defer { lock.unlock() }; return value }
}
