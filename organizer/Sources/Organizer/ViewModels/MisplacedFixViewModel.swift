import Foundation
import AppKit

/// 「誤配置修正」ペイン用。写真ライブラリのルート(年フォルダの親、例: .../s-leo/photo)を指定し、
/// 直下の年フォルダをチェックボックスで選び、選んだ年(または、選んだ年の中の月)だけ
/// PhotoVerifierを順番にかける。過去にMediaDateResolverのフォールバック不具合で大量に
/// 誤配置された写真を、年単位・月単位で少しずつ手動修正するための一時的な復旧ツール。
enum FixGranularity: String, CaseIterable {
    case year, month
}

@MainActor
final class MisplacedFixViewModel: ObservableObject {
    @Published var rootPath: String {
        didSet { scanYears() }
    }
    @Published var mode: VerifyMode = .report
    /// fixモードで一度の実行で実際に移動する件数の上限(選んだ対象全体を通しての合計に対して適用)。
    /// 検出件数が多い場合に一気に大量のファイルを動かさず、少しずつ実行できるようにする。
    @Published var maxFixCount: Int {
        didSet { UserDefaults.standard.set(maxFixCount, forKey: "misplacedFix.maxFixCount") }
    }
    @Published var granularity: FixGranularity = .year {
        didSet { scanMonths() }
    }
    @Published private(set) var years: [String] = []
    @Published var selectedYears: Set<String> = [] {
        didSet { scanMonths() }
    }
    /// "YYYY-MM" 形式(複数年をまたいでも一意になるように年を含める)。
    @Published private(set) var months: [String] = []
    @Published var selectedMonths: Set<String> = []

    /// EXIF/mdls/フォルダ名/ファイル名のどこからも撮影日が分からずmtimeフォールバックになった
    /// ファイルについて、見た目が近い(dHash)・EXIF付きの写真を「候補年」から探して日付を借用する
    /// 機能のON/OFF。誤マッチのリスクがあるため既定はOFF。
    @Published var similarityFallbackEnabled: Bool {
        didSet { UserDefaults.standard.set(similarityFallbackEnabled, forKey: "misplacedFix.similarityFallbackEnabled") }
    }
    /// 類似写真フォールバックの参照元として検索する年(`years`を流用する別選択。fix対象の
    /// selectedYears/selectedMonthsとは独立)。
    @Published var candidateYears: Set<String> = []
    /// dHashのハミング距離のしきい値。既定は最も厳しい`.exact`(距離0)。誤マッチ=誤った年フォルダへの
    /// 移動+ファイル名への日付捏造は、ゴミ箱行き(復元可能)より取り返しがつきにくい失敗モードのため、
    /// 緩めるのはユーザーが確認のみ/Dry runで様子を見てから。
    @Published var similarityMatchLevel: MatchLevel {
        didSet { UserDefaults.standard.set(similarityMatchLevel.rawValue, forKey: "misplacedFix.similarityMatchLevel") }
    }

    private static let defaultRoot = "/Users/yohei/Library/CloudStorage/OneDrive-Personal/s-leo/photo"
    private static let defaultMaxFixCount = 50

    init() {
        rootPath = UserDefaults.standard.string(forKey: "misplacedFix.root") ?? Self.defaultRoot
        let savedMax = UserDefaults.standard.integer(forKey: "misplacedFix.maxFixCount")
        maxFixCount = savedMax > 0 ? savedMax : Self.defaultMaxFixCount
        similarityFallbackEnabled = UserDefaults.standard.bool(forKey: "misplacedFix.similarityFallbackEnabled")
        let savedMatchLevel = UserDefaults.standard.object(forKey: "misplacedFix.similarityMatchLevel") as? Int
        similarityMatchLevel = savedMatchLevel.flatMap(MatchLevel.init(rawValue:)) ?? .exact
        scanYears()
    }

    var rootExists: Bool {
        FileManager.default.fileExists(atPath: rootPath)
    }

    func pickRoot() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootPath = url.path
        UserDefaults.standard.set(rootPath, forKey: "misplacedFix.root")
    }

    /// rootPath直下の"YYYY"な名前のフォルダを年一覧として拾い直す。
    /// ルートを変更した際に、もう存在しない年の選択は落とす。
    func scanYears() {
        let root = URL(fileURLWithPath: rootPath)
        guard let items = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey]) else {
            years = []
            selectedYears = []
            return
        }
        let found = items.compactMap { url -> String? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return nil }
            let name = url.lastPathComponent
            return name.fullyMatches(#"\d{4}"#) ? name : nil
        }
        years = found.sorted(by: >)
        selectedYears = selectedYears.intersection(years)
        candidateYears = candidateYears.intersection(years)
        scanMonths()
    }

    /// 選択中の年それぞれの直下の"MM"な名前のフォルダを月一覧として拾い直す
    /// ("YYYY-MM"のキーで保持し、複数年をまたいで選んでも一意にする)。
    /// 年単位のときは呼んでも無駄働きになるだけなので何もしない。
    func scanMonths() {
        guard granularity == .month else {
            months = []
            selectedMonths = []
            return
        }
        let root = URL(fileURLWithPath: rootPath)
        let fm = FileManager.default
        var found: [String] = []
        for year in years where selectedYears.contains(year) {
            let yearDir = root.appendingPathComponent(year)
            guard let items = try? fm.contentsOfDirectory(at: yearDir, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for url in items {
                guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { continue }
                let name = url.lastPathComponent
                guard name.fullyMatches(#"\d{2}"#) else { continue }
                found.append("\(year)-\(name)")
            }
        }
        months = found.sorted(by: >)
        selectedMonths = selectedMonths.intersection(months)
    }

    func selectAll() { selectedYears = Set(years) }
    func selectNone() { selectedYears = [] }

    func selectAllMonths() { selectedMonths = Set(months) }
    func selectNoneMonths() { selectedMonths = [] }

    func selectAllCandidateYears() { candidateYears = Set(years) }
    func selectNoneCandidateYears() { candidateYears = [] }

    private struct Target {
        let label: String
        let yearRoot: URL
        let monthFilter: String?
    }

    func run() {
        UserDefaults.standard.set(rootPath, forKey: "misplacedFix.root")
        let root = URL(fileURLWithPath: rootPath)
        let mode = self.mode
        let maxFixCount = self.maxFixCount
        let extensions = PhotosViewModel.photoExtensions
        let similarityFallbackEnabled = self.similarityFallbackEnabled
        let candidateYears = self.candidateYears
        let similarityMatchLevel = self.similarityMatchLevel

        let targets: [Target]
        let unitLabel: String
        let targetYears: Set<String>
        switch granularity {
        case .year:
            targets = years.filter { selectedYears.contains($0) }.map { year in
                Target(label: "\(year)年", yearRoot: root.appendingPathComponent(year), monthFilter: nil)
            }
            unitLabel = "年"
            targetYears = selectedYears
        case .month:
            targets = months.filter { selectedMonths.contains($0) }.map { ym in
                let parts = ym.split(separator: "-", maxSplits: 1).map(String.init)
                return Target(label: "\(ym)月", yearRoot: root.appendingPathComponent(parts[0]), monthFilter: parts[1])
            }
            unitLabel = "月"
            targetYears = Set(selectedMonths.compactMap { $0.split(separator: "-", maxSplits: 1).first.map(String.init) })
        }
        guard !targets.isEmpty else { return }
        let overlapYears = candidateYears.intersection(targetYears)

        let title: String
        switch mode {
        case .report: title = "誤配置修正 (確認のみ)"
        case .dryRun: title = "誤配置修正 (Dry run)"
        case .fix: title = "誤配置修正 (修正実行)"
        }

        JobRunner.shared.run(kind: .misplacedFix, title: title) { handle in
            let scan = Task.detached(priority: .userInitiated) {
                // 類似写真フォールバック: 実際にmtimeフォールバックへ落ちるファイルが出るまで
                // ビルドを遅延する(候補年を設定しても、レスキューが一度も発生しなければコストゼロ)。
                // 対象(年・月)をまたいで同じインスタンスを使い回すので、ビルドは最大でも1回だけ。
                let similarityIndex: LazySimilarityIndex? = (similarityFallbackEnabled && !candidateYears.isEmpty)
                    ? LazySimilarityIndex {
                        try SimilarityIndex.build(
                            roots: candidateYears.map { root.appendingPathComponent($0) },
                            extensions: extensions,
                            threshold: similarityMatchLevel.threshold,
                            progress: { handle.appendLog($0) },
                            checkCancel: { try Task.checkCancellation() }
                        )
                    }
                    : nil
                if similarityFallbackEnabled, !overlapYears.isEmpty {
                    handle.appendLog("※候補年に今回の対象年が含まれています(\(overlapYears.sorted().joined(separator: ", "))): 候補写真自体がこの実行で移動される可能性があります。\n")
                }

                // 全体の進捗バー用に、選んだ対象全体のファイル数を先に軽く数えておく
                // (EXIF/mdls呼び出しがない分、本処理よりずっと速い)。
                var totalCount = 0
                for target in targets {
                    try Task.checkCancellation()
                    totalCount += PhotoVerifier.estimateFileCount(root: target.yearRoot, extensions: extensions, monthFilter: target.monthFilter)
                }
                var processedCount = 0
                if totalCount > 0 { handle.setProgress(0) }

                // fixモードでは選んだ対象全体を通して最大maxFixCount件までしか実際に移動しない。
                // 上限に達したら残りの対象は次回以降に回す(未処理のまま打ち切る)。
                var remainingBudget = mode == .fix ? max(0, maxFixCount) : Int.max

                var totalIssues = 0, totalOK = 0, totalFixed = 0, totalSkipped = 0, totalFailed = 0, totalSimilarityMatched = 0
                var skippedTargets: [String] = []
                for target in targets {
                    try Task.checkCancellation()
                    if mode == .fix, remainingBudget <= 0 {
                        skippedTargets.append(target.label)
                        continue
                    }
                    handle.appendLog("\n### \(target.label) ###")
                    let result = try PhotoVerifier.run(
                        root: target.yearRoot,
                        mode: mode,
                        extensions: extensions,
                        monthFilter: target.monthFilter,
                        maxFixCount: mode == .fix ? remainingBudget : nil,
                        similarityIndex: similarityIndex,
                        onFileProcessed: {
                            processedCount += 1
                            if totalCount > 0 {
                                handle.setProgress(Double(processedCount) / Double(totalCount))
                            }
                        },
                        progress: { handle.appendLog($0) },
                        setDetail: { handle.setDetail("[\(target.label)] \($0)") },
                        checkCancel: { try Task.checkCancellation() }
                    )
                    totalIssues += result.issues.count
                    totalOK += result.okCount
                    totalFixed += result.fixed
                    totalSkipped += result.skippedDuplicate
                    totalFailed += result.failed
                    totalSimilarityMatched += result.similarityMatched
                    if mode == .fix { remainingBudget -= result.fixed }
                }
                handle.appendLog("\n=============================== 全\(unitLabel)合計")
                handle.appendLog("  問題あり: \(totalIssues) 件 / 正常: \(totalOK) 件")
                if totalSimilarityMatched > 0 {
                    handle.appendLog("  うち類似写真から日付を推定: \(totalSimilarityMatched) 件")
                }
                if mode == .fix {
                    handle.appendLog("  修正: \(totalFixed) 件  スキップ(同一): \(totalSkipped) 件  失敗: \(totalFailed) 件")
                    if totalFailed > 0 {
                        handle.appendLog("  ※失敗したファイルは移動されていません。OneDrive等のクラウド同期フォルダの場合、ファイルが未ダウンロード(プレースホルダー)状態だと移動に失敗することがあります。")
                    }
                    if !skippedTargets.isEmpty {
                        handle.appendLog("  上限(\(maxFixCount)件)に達したため未処理: \(skippedTargets.joined(separator: ", "))")
                    }
                }
            }
            handle.onCancel { scan.cancel() }
            _ = try await scan.value
        }
    }
}
