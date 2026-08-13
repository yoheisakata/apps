import Foundation
import AppKit

struct DateEstimateItem: Identifiable {
    let id = UUID()
    let url: URL
    let matches: [FeatureMatch]
}

/// 「日付推定」ペイン。撮影日が分からない写真(通常は誤配置修正が作るUnknown/フォルダ)を、
/// 候補年(参照元、EXIF付き写真)と見た目で比較し、上位候補の日付を提示する。誤配置修正の
/// 類似写真フォールバック(SimilarityIndex、dHashベース・自動確定)と違い、こちらは
/// FeaturePrintIndex(Vision特徴量ベース)で複数候補を出し、人が選んで確定する対話式のペイン。
@MainActor
final class DateEstimateViewModel: ObservableObject {
    @Published var unknownFolderPath: String {
        didSet { UserDefaults.standard.set(unknownFolderPath, forKey: "dateEstimate.unknownFolder") }
    }
    @Published var libraryRootPath: String {
        didSet {
            UserDefaults.standard.set(libraryRootPath, forKey: "dateEstimate.libraryRoot")
            scanYears()
        }
    }
    @Published private(set) var years: [String] = []
    @Published var candidateYears: Set<String> = []
    @Published private(set) var items: [DateEstimateItem] = []
    @Published private(set) var applyLog: [LogLine] = []
    @Published var errorMessage: String?

    private var nextLogID = 0
    private static let topK = 5
    private static let defaultRoot = "/Users/yohei/Library/CloudStorage/OneDrive-Personal/s-leo/photo"

    init() {
        unknownFolderPath = UserDefaults.standard.string(forKey: "dateEstimate.unknownFolder") ?? Self.defaultRoot + "/Unknown"
        libraryRootPath = UserDefaults.standard.string(forKey: "dateEstimate.libraryRoot") ?? Self.defaultRoot
        scanYears()
    }

    var unknownFolderExists: Bool { FileManager.default.fileExists(atPath: unknownFolderPath) }
    var libraryRootExists: Bool { FileManager.default.fileExists(atPath: libraryRootPath) }

    func pickUnknownFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        unknownFolderPath = url.path
    }

    func pickLibraryRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        libraryRootPath = url.path
    }

    /// libraryRootPath直下の"YYYY"な名前のフォルダを候補年一覧として拾い直す
    /// (MisplacedFixViewModel.scanYearsと同じパターン)。
    func scanYears() {
        let root = URL(fileURLWithPath: libraryRootPath)
        guard let entries = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            years = []
            candidateYears = []
            return
        }
        let found = entries.compactMap { url -> String? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let name = url.lastPathComponent
            return name.fullyMatches(#"\d{4}"#) ? name : nil
        }
        years = found.sorted(by: >)
        candidateYears = candidateYears.intersection(years)
    }

    func selectAllCandidateYears() { candidateYears = Set(years) }
    func selectNoneCandidateYears() { candidateYears = [] }

    func scan() {
        guard !JobRunner.shared.isRunning, !candidateYears.isEmpty else { return }
        let root = URL(fileURLWithPath: libraryRootPath)
        let unknownFolder = URL(fileURLWithPath: unknownFolderPath)
        let extensions = PhotosViewModel.photoExtensions
        let roots = candidateYears.map { root.appendingPathComponent($0) }
        let topK = Self.topK
        items = []

        JobRunner.shared.run(kind: .dateEstimate, title: "日付推定") { [weak self] handle in
            let task = Task.detached(priority: .userInitiated) {
                let index = try FeaturePrintIndex.build(
                    roots: roots,
                    extensions: extensions,
                    progress: { handle.appendLog($0) },
                    checkCancel: { try Task.checkCancellation() }
                )

                let fm = FileManager.default
                guard let e = fm.enumerator(at: unknownFolder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
                    handle.appendLog("対象フォルダが読み込めません: \(unknownFolder.path)")
                    return
                }
                var targets: [URL] = []
                for case let url as URL in e {
                    guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                    targets.append(url)
                }
                try Task.checkCancellation()
                handle.appendLog("対象: \(targets.count) 件を解析中…")

                // FeaturePrintIndex.buildと同じ理由で、Vision推論の同時実行数を絞る
                // (絞らないと対象枚数が多いときメモリを使い果たす)。
                let maxConcurrent = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
                let throttle = DispatchSemaphore(value: maxConcurrent)
                var results = [DateEstimateItem?](repeating: nil, count: targets.count)
                let counter = DateEstimateCounter()
                let total = targets.count
                results.withUnsafeMutableBufferPointer { buf in
                    DispatchQueue.concurrentPerform(iterations: total) { i in
                        throttle.wait()
                        defer { throttle.signal() }
                        let url = targets[i]
                        if let observation = FaceFocusedFeaturePrint.compute(for: url) {
                            let matches = index.nearestMatches(for: observation, k: topK)
                            buf[i] = DateEstimateItem(url: url, matches: matches)
                        }
                        let done = counter.increment()
                        handle.setProgress(Double(done) / Double(max(1, total)))
                    }
                }
                try Task.checkCancellation()
                let items = results.compactMap { $0 }
                await MainActor.run { self?.items = items }
                handle.appendLog("\n完了: \(items.count) / \(targets.count) 件で候補を提示しました")
            }
            handle.onCancel { task.cancel() }
            _ = try await task.value
        }
    }

    /// 候補チップのクリック、または手動指定した日付でファイルを移動する。
    func apply(_ item: DateEstimateItem, date: Date) {
        let ext = item.url.pathExtension.lowercased()
        let base = URL(fileURLWithPath: libraryRootPath)
        let dest = PhotoVerifier.standardDest(base: base, date: date, ext: ext)
        do {
            let (finalDest, isDuplicate) = try PhotoVerifier.safeMove(from: item.url, to: dest, fm: FileManager.default)
            items.removeAll { $0.id == item.id }
            if isDuplicate {
                appendLog("SKIP(同一): \(item.url.lastPathComponent)")
            } else {
                appendLog("移動: \(item.url.lastPathComponent) → \(relativePath(finalDest, base: base))")
            }
        } catch {
            errorMessage = "移動に失敗しました: \(error.localizedDescription)"
        }
    }

    func skip(_ item: DateEstimateItem) {
        items.removeAll { $0.id == item.id }
    }

    private func appendLog(_ text: String) {
        applyLog.append(LogLine(id: nextLogID, text: text))
        nextLogID += 1
    }

    private func relativePath(_ url: URL, base: URL) -> String {
        let baseComps = base.standardizedFileURL.pathComponents
        let comps = url.standardizedFileURL.pathComponents
        guard comps.starts(with: baseComps) else { return url.path }
        return comps.dropFirst(baseComps.count).joined(separator: "/")
    }
}

/// concurrentPerform 用のスレッドセーフなカウンタ(VideoDupViewModelのCounterと同じパターン)。
private final class DateEstimateCounter {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
