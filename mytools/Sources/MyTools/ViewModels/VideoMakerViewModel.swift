import Foundation
import AppKit
import UniformTypeIdentifiers

enum PlayOrder: String, CaseIterable {
    case fileOrder, random

    var title: String {
        switch self {
        case .fileOrder: return "ファイル順"
        case .random: return "ランダム"
        }
    }
}

@MainActor
final class VideoMakerViewModel: ObservableObject {
    @Published var folderPath: String
    @Published var musicPath: String
    @Published var outputPath = ""
    @Published var videos: [URL] = []
    @Published var selectedVideos = Set<URL>()
    @Published var qualityPreset: Int = 18 // CRF: 低いほど高画質
    @Published var clipSec: Int = 3
    @Published var offsetSec: Int = 3
    @Published var bgmVolume: Double = 0.6
    @Published var origVolume: Double = 0.4
    @Published var transitionSec: Double = 0.5
    @Published var titleText = ""
    /// 使用する動画の本数の上限。常に`1...totalScannedCount`にクランプされ、スライダーが
    /// 最大値(=読み込んだ全本数)のときは実質「上限なし」になる(チェックボックスは持たない)。
    @Published var maxFileCount: Int = 0
    @Published var playOrder: PlayOrder = .fileOrder
    @Published var showOverwriteConfirm = false
    /// 選択中のBGMファイルの長さ(秒)。`musicPath`が変わるたびに`refreshMusicDuration()`で更新する。
    @Published private(set) var musicDurationSec: Double?
    /// `startGenerate()`が手動設定(`currentConfig`)と自動生成(`buildAutoConfig()`)の
    /// どちらを使うかを覚えておくためのフラグ。上書き確認ダイアログを挟んでも
    /// どちらのボタンが押されたかを保持できるよう、`generate()`/`autoGenerate()`側で設定する。
    private var isAutoMode = false

    /// フォルダをスキャンして見つかった全動画(除外・上限を反映しない)。`videos`はこれを
    /// 元に`applyFileLimits()`が導出する — `videos`自体を直接削って上限をかけると、
    /// 後から上限本数を増やしても一度削った分を復元できなくなるため、常にこちらを
    /// 元データとして保持する。
    private var allVideos: [URL] = []
    /// 「選択した動画を除外」で明示的に除外された動画。上限本数を変更しても除外状態は保つ。
    private var excludedVideos = Set<URL>()

    init() {
        folderPath = UserDefaults.standard.string(forKey: "videoMaker.folder") ?? "/Volumes/backup1/leo_video"
        musicPath = UserDefaults.standard.string(forKey: "videoMaker.musicPath") ?? ""
        refreshMusicDuration()
    }

    var folderExists: Bool {
        FileManager.default.fileExists(atPath: folderPath)
    }

    /// BGMの長さの表示用文字列(例: "3:45")。長さが取得できない・未選択のときはnil。
    var musicDurationDisplay: String? {
        guard let sec = musicDurationSec else { return nil }
        let t = Int(sec.rounded())
        return "\(t / 60):\(String(format: "%02d", t % 60))"
    }

    private func refreshMusicDuration() {
        musicDurationSec = musicPath.isEmpty ? nil : VideoMaker.mediaDurationSec(musicPath)
    }

    /// フォルダから見つかった動画の総数(除外・上限を反映しない)。「上限ファイル数」スライダーの上限に使う。
    var totalScannedCount: Int {
        allVideos.count
    }

    /// 本数・1本あたりの秒数・トランジションの重なり・タイトルカード・末尾の黒みまで
    /// 織り込んだ、実際に生成される動画の予想合計時間(`VideoMaker.estimateTotalSec`と同じ計算式)。
    var estimatedTotalDisplay: String {
        guard !videos.isEmpty else { return "-" }
        let t = Int(VideoMaker.estimateTotalSec(config: currentConfig).rounded())
        return "\(t / 60)分\(String(format: "%02d", t % 60))秒"
    }

    private var currentConfig: VideoMakerConfig {
        VideoMakerConfig(
            videos: videos,
            titleText: titleText,
            musicPath: musicPath,
            outputPath: outputPath,
            clipSec: clipSec,
            offsetSec: offsetSec,
            bgmVolume: bgmVolume,
            origVolume: origVolume,
            transitionSec: transitionSec,
            qualityPreset: qualityPreset
        )
    }

    /// 「自動作成」ボタンの有効条件: 除外・選択中を除いた対象動画が1本以上あり、
    /// BGM(長さが取得できているもの)と出力先が揃っていること。全動画を選択/除外して
    /// 対象が0本になった場合はここで無効化される(`buildAutoConfig()`が黙ってnilを返し
    /// ボタンを押しても何も起きない、という分かりにくい状態を避けるため)。
    var canAutoGenerate: Bool {
        allVideos.contains { !excludedVideos.contains($0) && !selectedVideos.contains($0) }
            && !musicPath.isEmpty && musicDurationSec != nil && !outputPath.isEmpty
    }

    func loadDefaults() {
        if outputPath.isEmpty {
            outputPath = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Desktop/まとめ動画.mp4").path
        }
        refreshVideos()
    }

    /// フォルダパス変更時(ピッカー・直接編集どちらでも)に動画一覧とタイトル初期値を再スキャンする。
    func refreshVideos() {
        guard folderExists else { allVideos = []; excludedVideos = []; videos = []; return }
        titleText = VideoMaker.detectTitle(from: folderPath)
        allVideos = VideoMaker.findVideos(in: URL(fileURLWithPath: folderPath))
        excludedVideos = []
        selectedVideos = []
        // 「上限ファイル数」スライダーは1...totalScannedCountの範囲しか表せないため、
        // 未設定(0)なら全件を初期値にし、既存の設定値も新しい総数に収まるよう丸める。
        if maxFileCount <= 0 {
            maxFileCount = allVideos.count
        }
        maxFileCount = min(max(maxFileCount, 1), max(1, allVideos.count))
        applyFileLimits()
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderPath = url.path
        UserDefaults.standard.set(folderPath, forKey: "videoMaker.folder")
        refreshVideos()
    }

    func pickMusic() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio, .mp3]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        musicPath = url.path
        UserDefaults.standard.set(musicPath, forKey: "videoMaker.musicPath")
        refreshMusicDuration()
    }

    func clearMusic() {
        musicPath = ""
        UserDefaults.standard.removeObject(forKey: "videoMaker.musicPath")
        refreshMusicDuration()
    }

    func pickOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "mp4")!]
        panel.nameFieldStringValue = "まとめ動画.mp4"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputPath = url.path
    }

    func removeSelected() {
        excludedVideos.formUnion(selectedVideos)
        selectedVideos.removeAll()
        applyFileLimits()
    }

    func revealInFinder() {
        NSWorkspace.shared.selectFile(outputPath, inFileViewerRootedAtPath: "")
    }

    func playOutput() {
        NSWorkspace.shared.open(URL(fileURLWithPath: outputPath))
    }

    /// `allVideos`(除外済みを除く)から、再生順・上限本数を適用して`videos`を再計算する。
    /// 上限本数や再生順を何度切り替えても`allVideos`自体は変わらないので、
    /// 上限を後から増やせば除かれていた動画も戻ってくる。
    func applyFileLimits() {
        var list = allVideos.filter { !excludedVideos.contains($0) }
        switch playOrder {
        case .random:
            list.shuffle()
        case .fileOrder:
            list.sort { $0.path < $1.path }
        }
        if maxFileCount > 0, list.count > maxFileCount {
            list = Array(list.prefix(maxFileCount))
        }
        videos = list
    }

    func generate() {
        isAutoMode = false
        if FileManager.default.fileExists(atPath: outputPath) {
            showOverwriteConfirm = true
            return
        }
        startGenerate()
    }

    /// 「自動作成」: 手動の各設定(上限ファイル数・再生順・1動画あたりの秒数)は使わず、
    /// BGMの長さに合わせてクリップ秒数(2秒/3秒)と使用する動画を自動選択して生成する。
    func autoGenerate() {
        isAutoMode = true
        if FileManager.default.fileExists(atPath: outputPath) {
            showOverwriteConfirm = true
            return
        }
        startGenerate()
    }

    func startGenerate() {
        guard let config = isAutoMode ? buildAutoConfig() : currentConfig else { return }
        JobRunner.shared.run(kind: .videoMaker, title: isAutoMode ? "自動でまとめ動画を作成" : "まとめ動画を作成") { handle in
            try await VideoMaker.generate(
                config: config,
                progress: { handle.appendLog($0) },
                setProgress: { handle.setProgress($0) },
                setDetail: { handle.setDetail($0) },
                onCancel: { handle.onCancel($0) },
                checkCancel: { try Task.checkCancellation() }
            )
        }
    }

    /// 自動モード用の設定を組み立てる。手動の`videos`(除外・上限・再生順を反映したリスト)は使わず、
    /// 除外設定と現在リストで選択中の動画を引き継いだ`allVideos`から、BGMの長さに合う
    /// クリップ数をバランスよく選ぶ。`selectedVideos`(「除外」ボタンをまだ押していない、
    /// リスト上でハイライトしているだけの動画)も対象外にする ― 「自動作成では選択した
    /// ファイルを含めないでほしい」という要望に対応するため、明示的な除外操作を経ずとも
    /// 選択するだけで自動作成の対象から外せるようにする。
    private func buildAutoConfig() -> VideoMakerConfig? {
        let pool = allVideos
            .filter { !excludedVideos.contains($0) && !selectedVideos.contains($0) }
            .sorted { $0.path < $1.path }
        guard !pool.isEmpty, let musicDur = musicDurationSec, !outputPath.isEmpty else { return nil }

        // BGMはタイトルカードを含めた区間(withTitle)全体に敷かれるため、タイトルカード分を
        // 差し引いた残りをメインクリップ区間の目標尺にする。
        let titleCardDur = titleText.isEmpty ? 0.0 : VideoMaker.titleCardDurationSec
        let targetMainDur = max(2.0, musicDur - titleCardDur)

        let clipDurations = Self.buildAutoClipDurations(
            targetMainDur: targetMainDur, transitionSec: transitionSec, maxClips: pool.count
        )
        let selected = Self.balancedSelection(from: pool, count: clipDurations.count)

        return VideoMakerConfig(
            videos: selected,
            titleText: titleText,
            musicPath: musicPath,
            outputPath: outputPath,
            clipSec: clipDurations.first ?? clipSec,
            offsetSec: offsetSec,
            bgmVolume: bgmVolume,
            origVolume: origVolume,
            transitionSec: transitionSec,
            qualityPreset: qualityPreset,
            perClipSeconds: clipDurations
        )
    }

    /// BGMの目標尺に達するまで、クリップごとに2秒/3秒をランダムに選んで積み上げる
    /// (ディゾルブの重なり分を差し引いた実効長で判定する)。使える動画の本数(`maxClips`)を超えない。
    private static func buildAutoClipDurations(targetMainDur: Double, transitionSec: Double, maxClips: Int) -> [Int] {
        guard targetMainDur > 0, maxClips > 0 else { return [] }
        var durations: [Int] = []
        var cumulative = 0.0
        while durations.count < maxClips {
            let d = Bool.random() ? 2 : 3
            let transDur = durations.isEmpty ? 0 : min(transitionSec, Double(min(d, durations.last!)) / 2)
            let added = Double(d) - transDur
            if !durations.isEmpty, cumulative + added > targetMainDur {
                break
            }
            durations.append(d)
            cumulative += added
        }
        if durations.isEmpty { durations.append(2) }
        return durations
    }

    /// `pool`(ファイル順にソート済み)から`count`本を、先頭〜末尾まで均等な間隔になるよう選ぶ。
    /// 単純に先頭から`count`本取ると大きなフォルダでは常に最初の方のファイルしか使われないため、
    /// フォルダ全体からバランスよく(それでいてファイル順を保って)抽出する。
    private static func balancedSelection(from pool: [URL], count: Int) -> [URL] {
        guard count > 0, !pool.isEmpty else { return [] }
        if count >= pool.count { return pool }
        if count == 1 { return [pool[0]] }
        return (0..<count).map { i in
            let idx = Int((Double(i) * Double(pool.count - 1) / Double(count - 1)).rounded())
            return pool[idx]
        }
    }
}
