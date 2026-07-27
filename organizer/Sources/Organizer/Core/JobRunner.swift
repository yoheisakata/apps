import Foundation

/// 実行ボタンを持つ各ペインに対応するジョブの種別。ログは種別ごとに保持し、
/// 各ペインの実行ログセクションは自分の種別のログだけを表示する。
enum JobKind: String {
    case photos, videos, encode, verify, sync, shortClips
}

/// アプリ全体で同時に1本しかジョブを走らせないための実行キュー。
/// 実行中はシステムスリープを防止し（caffeinate相当）、下部のステータスバーに進捗を出す。
@MainActor
final class JobRunner: ObservableObject {
    static let shared = JobRunner()

    struct Handle {
        let appendLog: (String) -> Void
        let setProgress: (Double?) -> Void
        let setDetail: (String) -> Void
        let onCancel: (@escaping () -> Void) -> Void
    }

    @Published private(set) var isRunning = false
    @Published private(set) var title = ""
    @Published private(set) var detail = ""
    @Published private(set) var progress: Double?
    @Published private(set) var currentKind: JobKind?
    @Published private(set) var logsByKind: [JobKind: [String]] = [:]

    private var activity: NSObjectProtocol?
    private var task: Task<Void, Never>?
    private var cancelHandler: (() -> Void)?

    private init() {}

    func logLines(for kind: JobKind) -> [String] {
        logsByKind[kind] ?? []
    }

    func run(kind: JobKind, title: String, _ work: @escaping (Handle) async throws -> Void) {
        guard !isRunning else { return }
        isRunning = true
        currentKind = kind
        self.title = title
        detail = ""
        progress = nil
        logsByKind[kind] = []
        cancelHandler = nil
        activity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleSystemSleepDisabled],
            reason: title
        )

        task = Task { [self] in
            let handle = Handle(
                appendLog: { line in
                    Task { @MainActor in self.appendLog(line) }
                },
                setProgress: { pct in
                    Task { @MainActor in self.progress = pct }
                },
                setDetail: { text in
                    Task { @MainActor in self.detail = text }
                },
                onCancel: { handler in
                    Task { @MainActor in self.cancelHandler = handler }
                }
            )
            do {
                try await work(handle)
                await self.finish(with: "完了しました")
            } catch is CancellationError {
                await self.finish(with: "中止しました")
            } catch {
                await self.finish(with: "エラー: \(error.localizedDescription)")
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        cancelHandler?()
        task?.cancel()
    }

    private func appendLog(_ line: String) {
        guard let kind = currentKind else { return }
        logsByKind[kind, default: []].append(line)
        if let count = logsByKind[kind]?.count, count > 3000 {
            logsByKind[kind]?.removeFirst(1000)
        }
    }

    private func finish(with message: String) async {
        appendLog(message)
        isRunning = false
        title = ""
        detail = ""
        progress = nil
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        task = nil
        cancelHandler = nil
    }
}
