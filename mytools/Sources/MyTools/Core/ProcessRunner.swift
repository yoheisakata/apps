import Foundation

enum ProcessRunnerError: Error, LocalizedError {
    case launchFailed(String)

    var errorDescription: String? {
        switch self {
        case .launchFailed(let reason):
            return "コマンドを起動できませんでした: \(reason)"
        }
    }
}

/// 外部コマンド(ffmpeg/ffprobe/rsync/sips/mdls等)を実行し、標準出力/標準エラーを1行ずつ通知する。
/// 呼び出し元が保持して cancel() を呼べば実行中のプロセスを終了できる。
final class ProcessRunner {
    private var process: Process?

    @discardableResult
    func run(
        _ executable: String,
        _ arguments: [String],
        onLine: @escaping (String) -> Void = { _ in }
    ) async throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.process = process

        // stdout/stderrのreadabilityHandlerはそれぞれ別スレッドから呼ばれ得るため、
        // onLineの呼び出しは1本のシリアルキューに通して呼び出し元での競合を防ぐ。
        let outputQueue = DispatchQueue(label: "ProcessRunner.output")

        @Sendable func handle(_ data: Data) {
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            // ffmpegの進捗表示など \r 区切りの上書き行も別行として扱う
            let normalized = chunk.replacingOccurrences(of: "\r", with: "\n")
            let lines = normalized.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            outputQueue.async {
                for line in lines { onLine(line) }
            }
        }

        stdoutPipe.fileHandleForReading.readabilityHandler = { fh in handle(fh.availableData) }
        stderrPipe.fileHandleForReading.readabilityHandler = { fh in handle(fh.availableData) }

        do {
            try process.run()
        } catch {
            // readabilityHandlerを設定済みのままpipeを放置するとファイルディスクリプタが
            // 解放されない(GCDのディスパッチソースがFileHandleを生かし続けるため、ARCの
            // dealloc任せでは閉じない)。起動失敗のたびにfd 4つがリークし、積み重なると
            // 後続の起動が`posix_spawn`失敗経由の未捕捉例外でクラッシュし得るため、
            // 成功パスと同様にここでも明示的に閉じる。
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            try? stdoutPipe.fileHandleForReading.close()
            try? stderrPipe.fileHandleForReading.close()
            try? stdoutPipe.fileHandleForWriting.close()
            try? stderrPipe.fileHandleForWriting.close()
            throw ProcessRunnerError.launchFailed(error.localizedDescription)
        }
        // 子プロセスに複製された後、親側が持つ書き込み端の複製は不要になる。SyncExec.runと
        // 同じ理由(閉じないとファイルディスクリプタが積み上がる)でここでも明示的に閉じる。
        try? stdoutPipe.fileHandleForWriting.close()
        try? stderrPipe.fileHandleForWriting.close()

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { p in
                stdoutPipe.fileHandleForReading.readabilityHandler = nil
                stderrPipe.fileHandleForReading.readabilityHandler = nil
                try? stdoutPipe.fileHandleForReading.close()
                try? stderrPipe.fileHandleForReading.close()
                continuation.resume(returning: p.terminationStatus)
            }
        }
    }

    func cancel() {
        process?.terminate()
    }
}
