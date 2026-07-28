import Foundation
import AppKit
import AVFoundation

/// 「動画重複」ペイン用。拡張子を除いたファイル名が同じ動画、またはファイル名が違っても
/// 長さ(秒)が一致する動画同士を集め、開始5秒以内の数フレームのdHashで実際に同じ内容かを
/// 確認してグループ化する(`VideoDupFinder`)。
/// キープ判定は固定ルール(H.265優先、同条件ならサイズ最大)で、`DupPhotosViewModel`と
/// 同様にグループ単位のチェックボックスで対象/対象外を切り替えられる。`JobRunner`は使わない
/// (重複写真パインと同様、自前のisWorking/progressで進捗を出す)。
final class VideoDupViewModel: ObservableObject {
    @Published var folders: [URL] = []
    /// 同名候補ごとの解析済みリスト(フレームハッシュを含む、まだクラスタリング前)。
    /// matchLevelを変えたときはこれを使い回して再クラスタリングするだけで済む
    /// (ffmpeg/ffprobeの再実行はしない)。
    @Published private(set) var candidateGroups: [[VideoCandidate]] = []
    @Published var groups: [VideoDupGroup] = []
    @Published var selection: Set<UUID> = []
    /// 削除対象として扱う(=チェックの入った)グループのid。DupPhotosViewModelと同じ意味。
    @Published var enabledGroups: Set<UUID> = []
    @Published var isWorking = false
    @Published var progress: Double = 0
    @Published var progressText = ""
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var matchLevel: MatchLevel = .strict {
        didSet { if !candidateGroups.isEmpty { regroup() } }
    }

    private var cancelRequested = false
    private let workQueue = DispatchQueue(label: "organizer.videodup.work", qos: .userInitiated)

    // MARK: フォルダ

    func addFolders(_ urls: [URL]) {
        for url in urls {
            let std = url.standardizedFileURL
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: std.path, isDirectory: &isDir),
                  isDir.boolValue,
                  !folders.contains(std) else { continue }
            folders.append(std)
        }
    }

    func openPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "追加"
        if panel.runModal() == .OK {
            addFolders(panel.urls)
        }
    }

    func removeFolder(_ url: URL) {
        folders.removeAll { $0 == url }
    }

    // MARK: スキャン

    func cancel() { cancelRequested = true }

    func scan() {
        guard !isWorking, !folders.isEmpty else { return }
        isWorking = true
        cancelRequested = false
        progress = 0
        progressText = "動画を探しています…"
        statusMessage = ""
        candidateGroups = []
        groups = []
        selection = []
        let folders = self.folders

        // ffmpeg/ffprobeはプロセスごとにメモリを食うため、同時に立ち上がる本数を絞る
        // (concurrentPerformのワーカースレッド数に任せると候補が多いときに一気に
        // 大量のプロセスが起動し、メモリ逼迫でOSに強制終了されるおそれがあるため)。
        let maxConcurrent = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))

        workQueue.async { [weak self] in
            guard let self else { return }
            let allFiles = VideoDupFinder.allVideoFiles(in: folders)
            if self.cancelRequested {
                DispatchQueue.main.async { self.finishCancelled() }
                return
            }

            // ①ファイル名が違っても同じ動画を検知できるよう、全ファイルの長さ(秒)を先に確認する
            // (ffprobeで長さだけを見るのでフレーム抽出より軽いが、ライブラリ全体を走査するため
            // 同名グループ抽出だけの旧実装より時間がかかる)。
            let durationTotal = allFiles.count
            var durationResults = [Double?](repeating: nil, count: durationTotal)
            let durationCounter = Counter()
            let durationThrottle = DispatchSemaphore(value: maxConcurrent)
            durationResults.withUnsafeMutableBufferPointer { buf -> Void in
                DispatchQueue.concurrentPerform(iterations: durationTotal) { i in
                    if self.cancelRequested { return }
                    durationThrottle.wait()
                    defer { durationThrottle.signal() }
                    buf[i] = H265Encoder.getDurationSec(allFiles[i])
                    let done = durationCounter.increment()
                    DispatchQueue.main.async {
                        self.progress = Double(done) / Double(max(1, durationTotal)) * 0.5
                        self.progressText = "長さを確認中… (\(done) / \(durationTotal))"
                    }
                }
            }
            if self.cancelRequested {
                DispatchQueue.main.async { self.finishCancelled() }
                return
            }

            var durations: [URL: Double] = [:]
            for (i, d) in durationResults.enumerated() {
                if let d { durations[allFiles[i]] = d }
            }
            // ②同名グループ + 長さ一致グループをまとめた候補グループ(実際に同じ内容かはまだ未確認)
            let candidates = VideoDupFinder.mergeCandidateGroups(files: allFiles, durations: durations)

            let flatURLs = candidates.flatMap { $0 }
            let total = flatURLs.count
            DispatchQueue.main.async { self.progressText = "0 / \(total) 本を解析中…" }

            var flatResults = [VideoCandidate?](repeating: nil, count: total)
            let counter = Counter()
            let throttle = DispatchSemaphore(value: maxConcurrent)
            flatResults.withUnsafeMutableBufferPointer { buf -> Void in
                DispatchQueue.concurrentPerform(iterations: total) { i in
                    if self.cancelRequested { return }
                    throttle.wait()
                    defer { throttle.signal() }
                    buf[i] = VideoDupFinder.analyze(flatURLs[i])
                    let done = counter.increment()
                    DispatchQueue.main.async {
                        self.progress = 0.5 + Double(done) / Double(max(1, total)) * 0.5
                        self.progressText = "\(done) / \(total) 本を解析中…"
                    }
                }
            }
            if self.cancelRequested {
                DispatchQueue.main.async { self.finishCancelled() }
                return
            }

            // 候補グループの構造に戻す(解析に失敗したファイルは除く)
            var index = 0
            var rebuilt: [[VideoCandidate]] = []
            for group in candidates {
                let slice = (index..<(index + group.count)).compactMap { flatResults[$0] }
                index += group.count
                if slice.count > 1 { rebuilt.append(slice) }
            }

            DispatchQueue.main.async {
                self.candidateGroups = rebuilt
                self.regroup()
            }
        }
    }

    private func finishCancelled() {
        isWorking = false
        progressText = ""
        statusMessage = "キャンセルしました"
    }

    /// candidateGroups(解析済み・ハッシュ算出済み)を現在のmatchLevelで再クラスタリングする。
    /// ffmpeg/ffprobeは呼び直さないので一瞬で終わる。
    func regroup() {
        let level = matchLevel
        let sorted = candidateGroups
            .flatMap { VideoDupFinder.cluster($0, threshold: level.threshold) }
            .sorted { $0.wastedBytes > $1.wastedBytes }
        groups = sorted
        enabledGroups = Set(sorted.map(\.id))
        isWorking = false
        progress = 1
        progressText = ""
        let dupCount = sorted.reduce(0) { $0 + $1.videos.count - 1 }
        statusMessage = sorted.isEmpty
            ? "重複は見つかりませんでした"
            : "\(sorted.count) グループ・重複 \(dupCount) 本が見つかりました"
        autoSelect()
    }

    // MARK: 選択

    /// keeper以外を選択する(チェックを外したグループは対象外)
    func autoSelect() {
        var sel: Set<UUID> = []
        for group in groups where enabledGroups.contains(group.id) {
            sel.formUnion(autoSelectIDs(for: group))
        }
        selection = sel
    }

    /// グループ単位の「このグループの重複を削除するか」チェックボックス用(DupPhotosViewModelと同じ)。
    func setGroupEnabled(_ group: VideoDupGroup, enabled: Bool) {
        if enabled {
            enabledGroups.insert(group.id)
            selection.formUnion(autoSelectIDs(for: group))
        } else {
            enabledGroups.remove(group.id)
            selection.subtract(group.videos.map(\.id))
        }
    }

    private func autoSelectIDs(for group: VideoDupGroup) -> Set<UUID> {
        guard let keeper = group.keeper else { return [] }
        return Set(group.videos.filter { $0.id != keeper.id }.map(\.id))
    }

    func enableAllGroups() {
        enabledGroups = Set(groups.map(\.id))
        autoSelect()
    }

    func disableAllGroups() {
        enabledGroups = []
        selection = []
    }

    func toggle(_ video: VideoCandidate) {
        if selection.contains(video.id) {
            selection.remove(video.id)
        } else {
            selection.insert(video.id)
        }
    }

    var selectedVideos: [VideoCandidate] {
        groups.flatMap(\.videos).filter { selection.contains($0.id) }
    }

    var selectedBytes: Int64 {
        selectedVideos.reduce(0) { $0 + $1.fileSize }
    }

    // MARK: 削除（ゴミ箱へ移動）

    func trashSelected() {
        let targets = selectedVideos
        guard !targets.isEmpty else { return }
        let fm = FileManager.default
        var moved = 0
        var movedBytes: Int64 = 0
        var failed: [String] = []
        for video in targets {
            do {
                try fm.trashItem(at: video.url, resultingItemURL: nil)
                moved += 1
                movedBytes += video.fileSize
            } catch {
                failed.append(video.name)
            }
        }
        let trashedIDs = Set(targets.prefix(moved).map(\.id))
        candidateGroups = candidateGroups
            .map { $0.filter { !trashedIDs.contains($0.id) } }
            .filter { $0.count > 1 }
        var newGroups: [VideoDupGroup] = []
        for var g in groups {
            g.videos.removeAll { selection.contains($0.id) && !failed.contains($0.name) }
            if g.videos.count > 1 { newGroups.append(g) }
        }
        groups = newGroups
        enabledGroups = enabledGroups.intersection(newGroups.map(\.id))
        selection = []
        statusMessage = "\(moved) 本をゴミ箱へ移動しました（\(ByteFmt.string(movedBytes)) を回収）"
        if !failed.isEmpty {
            errorMessage = "移動できなかったファイル: " + failed.prefix(5).joined(separator: ", ")
                + (failed.count > 5 ? " ほか \(failed.count - 5) 件" : "")
        }
        autoSelect()
    }
}

/// 動画サムネイル読み込み(重複写真の`ThumbLoader`と同じNSCacheパターン)。写真と違い
/// ImageIOでは読めないため、AVFoundationの`AVAssetImageGenerator`で開始1秒地点のフレームを
/// 取り出す(ffmpegの別プロセス起動より軽い。`VideoDupFinder.analyze`の`extractFrameHash`は
/// クラスタリング判定用の別経路で、こちらはUI表示専用)。
enum VideoThumbLoader {
    static let cache: NSCache<NSURL, NSImage> = {
        let c = NSCache<NSURL, NSImage>()
        c.countLimit = 500
        c.totalCostLimit = 300 << 20 // 約300MB分(ThumbLoaderと同じ考え方)
        return c
    }()

    static func load(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        if let img = cache.object(forKey: url as NSURL) {
            completion(img)
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 320, height: 320)
            var result: NSImage?
            if let cg = try? generator.copyCGImage(at: CMTime(seconds: 1, preferredTimescale: 600), actualTime: nil) {
                let img = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                let cost = cg.width * cg.height * 4
                cache.setObject(img, forKey: url as NSURL, cost: cost)
                result = img
            }
            DispatchQueue.main.async { completion(result) }
        }
    }
}

/// concurrentPerform 用のスレッドセーフなカウンタ(DupPhotosViewModel内のものと同一実装。
/// トップレベルprivateはファイル単位のスコープなので衝突しない)。
private final class Counter {
    private var value = 0
    private let lock = NSLock()
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}
