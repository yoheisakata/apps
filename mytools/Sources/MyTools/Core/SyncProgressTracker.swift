import Foundation

/// 同期実行中の全体進捗・転送速度・残り時間を推定する。
///
/// 差分確認(dry-run)で得た転送予定ファイル(追加+更新)のサイズをソース側で実測して総量とし、
/// `rsync --progress`の出力(ファイル名だけの行と「 30,000,000 100%  697.05MB/s ...」形式の
/// 進捗行)から転送済みバイトを積み上げる。差分確認後にファイルが変わった場合や、更新ファイルの
/// 差分転送などで実際の転送量とはずれるため、値はあくまで推定。
///
/// `feed`はProcessRunnerの出力キュー(シリアル)から呼ばれるが、念のためロックで守る。
final class SyncProgressTracker {
    struct Snapshot {
        let fraction: Double
        let doneFiles: Int
        let totalFiles: Int
        let doneBytes: Int64
        let totalBytes: Int64
        let bytesPerSecond: Double?
        let remainingSeconds: Double?
        let currentFile: String?
        let currentFraction: Double?

        var overallDetail: String {
            var parts = ["\(doneFiles) / \(totalFiles)件"]
            if totalBytes > 0 {
                parts.append("\(ByteFmt.string(doneBytes)) / \(ByteFmt.string(totalBytes))")
            }
            if let bytesPerSecond {
                parts.append("\(ByteFmt.string(Int64(bytesPerSecond)))/s")
            }
            if let remainingSeconds {
                parts.append("残り約\(H265Encoder.formatETA(remainingSeconds))")
            }
            return parts.joined(separator: " · ")
        }
    }

    private let lock = NSLock()
    /// フォルダ名(汎用「同期」ペインは"") → (ソースからの相対パス → バイト数)。未完了分のみ残す。
    private var pending: [String: [String: Int64]] = [:]
    private let totalFiles: Int
    private let totalBytes: Int64
    private var doneFiles = 0
    private var doneBytes: Int64 = 0
    private var folder = ""
    private var current: (path: String, size: Int64)?
    private var currentBytes: Int64 = 0
    private let startedAt = Date()
    private var lastReportAt = Date.distantPast

    /// `items`は(フォルダ名, そのフォルダのソースURL, 差分)の組。
    init(items: [(folder: String, source: URL, diff: SyncDiff)]) {
        var files = 0
        var bytes: Int64 = 0
        for item in items {
            var sizes: [String: Int64] = [:]
            for line in item.diff.addedLines + item.diff.modifiedLines {
                guard let path = RsyncSync.extractPath(from: line) else { continue }
                let attrs = try? FileManager.default.attributesOfItem(
                    atPath: item.source.appendingPathComponent(path).path
                )
                let size = (attrs?[.size] as? NSNumber)?.int64Value ?? 0
                sizes[path] = size
                files += 1
                bytes += size
            }
            pending[item.folder, default: [:]].merge(sizes) { $1 }
        }
        totalFiles = files
        totalBytes = bytes
    }

    /// 次にrsyncへかけるフォルダを切り替える(複数フォルダを順に同期するOneDrive同期用)。
    func beginFolder(_ name: String) {
        lock.lock(); defer { lock.unlock() }
        finishCurrent()
        folder = name
    }

    /// 1フォルダ分のrsyncが終わったら呼ぶ。出力から拾えなかった(転送失敗・スキップ等)残りも
    /// 処理済みとして数え、全体の進捗が途中で止まったままにならないようにする。
    func endFolder() -> Snapshot {
        lock.lock(); defer { lock.unlock() }
        finishCurrent()
        for size in (pending[folder] ?? [:]).values {
            doneFiles += 1
            doneBytes += size
        }
        pending[folder] = [:]
        return makeSnapshot()
    }

    /// rsyncの出力1行を取り込む。UI更新を間引くため、前回の報告から0.5秒以上経ったときだけ
    /// Snapshotを返す。
    func feed(_ line: String) -> Snapshot? {
        lock.lock(); defer { lock.unlock() }
        if let match = line.firstMatch(of: #/^\s*([\d,]+)\s+(\d+)%/#) {
            if let current {
                let bytes = Int64(match.1.replacingOccurrences(of: ",", with: "")) ?? 0
                currentBytes = min(bytes, current.size)
                // "(xfr#N, to-chk=...)"が付くのはそのファイルの転送完了行
                if line.contains("xfr#") { finishCurrent() }
            }
        } else if let size = pending[folder]?[line] {
            finishCurrent()
            current = (line, size)
            currentBytes = 0
        }

        let now = Date()
        guard now.timeIntervalSince(lastReportAt) >= 0.5 else { return nil }
        lastReportAt = now
        return makeSnapshot()
    }

    private func finishCurrent() {
        guard let current else { return }
        pending[folder]?[current.path] = nil
        doneFiles += 1
        doneBytes += current.size
        self.current = nil
        currentBytes = 0
    }

    private func makeSnapshot() -> Snapshot {
        let transferred = doneBytes + currentBytes
        let fraction: Double
        if totalBytes > 0 {
            fraction = Double(transferred) / Double(totalBytes)
        } else {
            fraction = totalFiles > 0 ? Double(doneFiles) / Double(totalFiles) : 1
        }

        // 開始直後は速度が安定しないため、数秒経つまでは速度・残り時間を出さない。
        let elapsed = Date().timeIntervalSince(startedAt)
        var rate: Double?
        var remaining: Double?
        if elapsed >= 3, transferred > 0 {
            let r = Double(transferred) / elapsed
            rate = r
            remaining = Double(max(totalBytes - transferred, 0)) / r
        } else if elapsed >= 3, totalBytes == 0, doneFiles > 0 {
            remaining = elapsed / Double(doneFiles) * Double(totalFiles - doneFiles)
        }

        return Snapshot(
            fraction: min(max(fraction, 0), 1),
            doneFiles: doneFiles,
            totalFiles: totalFiles,
            doneBytes: transferred,
            totalBytes: totalBytes,
            bytesPerSecond: rate,
            remainingSeconds: remaining,
            currentFile: current?.path,
            currentFraction: current.map { $0.size > 0 ? Double(currentBytes) / Double($0.size) : 0 }
        )
    }
}

extension SyncProgressTracker.Snapshot {
    func report(to handle: JobRunner.Handle) {
        handle.setOverallProgress(fraction)
        handle.setOverallDetail(overallDetail)
        handle.setProgress(currentFraction)
        handle.setDetail(currentFile ?? "")
    }
}
