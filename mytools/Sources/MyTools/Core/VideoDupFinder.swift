import Foundation

struct VideoCandidate: Identifiable, Hashable {
    let id = UUID()
    let url: URL
    let fileSize: Int64
    let codec: String?
    /// 開始5秒以内のサンプル地点(秒)ごとのdHash。抽出できなかった地点は含まれない。
    let frameHashes: [Double: UInt64]

    var isH265: Bool { H265Encoder.isH265(codec) }
    var name: String { url.lastPathComponent }
}

struct VideoDupGroup: Identifiable {
    let id = UUID()
    var videos: [VideoCandidate]

    /// キープ判定: H.265があればそれを残す(複数あればサイズ最大)。無ければ全体でサイズ最大を残す。
    var keeper: VideoCandidate? {
        let h265 = videos.filter(\.isH265)
        if !h265.isEmpty {
            return h265.max { $0.fileSize < $1.fileSize }
        }
        return videos.max { $0.fileSize < $1.fileSize }
    }

    /// グループ内で重複している分のサイズ（keeperを残した場合に節約できる量）
    var wastedBytes: Int64 {
        let total = videos.reduce(0) { $0 + $1.fileSize }
        let keep = keeper?.fileSize ?? 0
        return total - keep
    }
}

/// 拡張子を除いたファイル名が同じ動画同士、またはファイル名が違っても長さ(秒)が一致する動画同士を
/// 候補にし、開始5秒以内の数フレームのdHashで比較して「実際に同じ内容か」を確認し、重複グループを
/// 作る。キープ判定はH.265優先・同条件ならファイルサイズ最大(`VideoDupGroup.keeper`)。
enum VideoDupFinder {
    static let videoExtensions = H265Encoder.videoExtensions
    static let sampleSeconds: [Double] = [1, 4]
    /// 長さ(秒)をこの単位で丸めて一致するものを候補とみなす(再エンコードでの微小な誤差を許容する)。
    static let durationBucketSeconds: Double = 1.0

    /// 対象フォルダ配下の動画ファイルを再帰列挙する(拡張子フィルタのみ、まだグループ化はしない)。
    static func allVideoFiles(in folders: [URL]) -> [URL] {
        let fm = FileManager.default
        var files: [URL] = []
        for folder in folders {
            guard let e = fm.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else { continue }
                guard videoExtensions.contains(url.pathExtension.lowercased()) else { continue }
                files.append(url)
            }
        }
        return files
    }

    /// 拡張子を除いたファイル名が同じもの同士でグループ化する(2本以上あるものだけ)。
    /// この段階ではまだ内容の比較はしない(軽量な下準備)。
    static func collectStemGroups(in folders: [URL]) -> [[URL]] {
        var byStem: [String: [URL]] = [:]
        for url in allVideoFiles(in: folders) {
            byStem[url.deletingPathExtension().lastPathComponent, default: []].append(url)
        }
        return byStem.values.filter { $0.count > 1 }.sorted { ($0.first?.path ?? "") < ($1.first?.path ?? "") }
    }

    /// 同名グループと、長さ(秒、`durationBucketSeconds`単位で丸め)が一致するグループをUnion-Findで
    /// まとめ、ファイル名が違っても長さが同じ動画も解析候補にする。`durations`は事前に
    /// `H265Encoder.getDurationSec`で取得済みのもの(呼び出し側が並列・進捗表示付きで用意する。
    /// ここでは統合ロジックのみを担う)。実際に同じ内容かどうかはまだ確認しない
    /// (次段の`analyze`+`isSameVideo`任せ、安全側に倒す)。
    static func mergeCandidateGroups(files: [URL], durations: [URL: Double]) -> [[URL]] {
        guard files.count > 1 else { return [] }
        var uf = UnionFind(files.count)

        var byStem: [String: [Int]] = [:]
        for (i, url) in files.enumerated() {
            byStem[url.deletingPathExtension().lastPathComponent, default: []].append(i)
        }
        for group in byStem.values where group.count > 1 {
            for i in group.dropFirst() { uf.union(group[0], i) }
        }

        var byDuration: [Int: [Int]] = [:]
        for (i, url) in files.enumerated() {
            guard let d = durations[url] else { continue }
            byDuration[Int((d / durationBucketSeconds).rounded()), default: []].append(i)
        }
        for group in byDuration.values where group.count > 1 {
            for i in group.dropFirst() { uf.union(group[0], i) }
        }

        var clusters: [Int: [URL]] = [:]
        for i in 0..<files.count {
            clusters[uf.find(i), default: []].append(files[i])
        }
        return clusters.values.filter { $0.count > 1 }.sorted { ($0.first?.path ?? "") < ($1.first?.path ?? "") }
    }

    /// 1本の動画のサイズ・コーデック・サンプルフレームのdHashを取得する(ffprobe/ffmpegを呼ぶため重い。
    /// 同名 or 同じ長さの候補にだけ行うので、ライブラリ全体に対して行うわけではない)。
    static func analyze(_ url: URL) -> VideoCandidate? {
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return nil }
        let codec = H265Encoder.getVideoCodec(url)
        var hashes: [Double: UInt64] = [:]
        for t in sampleSeconds {
            if let h = extractFrameHash(of: url, atSeconds: t) { hashes[t] = h }
        }
        return VideoCandidate(url: url, fileSize: Int64(size), codec: codec, frameHashes: hashes)
    }

    /// -ss を -i より前に置くことで高速シーク(キーフレーム単位、多少不正確)にしている
    /// (数フレームの比較用途なので十分。動画全体をデコードする必要はない)。
    private static func extractFrameHash(of url: URL, atSeconds: Double) -> UInt64? {
        guard let ffmpeg = ToolLocator.resolve("ffmpeg") else { return nil }
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("organizer-frame-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: tempURL) }
        let args = ["-y", "-ss", String(atSeconds), "-i", url.path, "-frames:v", "1", "-q:v", "4", tempURL.path]
        guard (try? SyncExec.run(ffmpeg, args, timeout: 15)) != nil else { return nil }
        guard FileManager.default.fileExists(atPath: tempURL.path) else { return nil }
        return PerceptualHash.dHash(of: tempURL)
    }

    /// 両者に共通して抽出できたサンプル地点だけを比較する。1地点も比較できなければ
    /// 「同じとは判定しない」(安全側に倒す — 誤って別の動画を同一と扱うより、
    /// 重複を見逃す方がまし)。
    static func isSameVideo(_ a: VideoCandidate, _ b: VideoCandidate, threshold: Int) -> Bool {
        let commonTimes = Set(a.frameHashes.keys).intersection(b.frameHashes.keys)
        guard !commonTimes.isEmpty else { return false }
        for t in commonTimes {
            if (a.frameHashes[t]! ^ b.frameHashes[t]!).nonzeroBitCount > threshold { return false }
        }
        return true
    }

    /// 同名グループ内をUnion-Findでクラスタリングし、実際に同じ内容と確認できた2本以上の
    /// クラスタだけを重複グループとして返す(3本以上が同名の場合にも対応)。
    static func cluster(_ candidates: [VideoCandidate], threshold: Int) -> [VideoDupGroup] {
        guard candidates.count > 1 else { return [] }
        var uf = UnionFind(candidates.count)
        for i in 0..<candidates.count {
            for j in (i + 1)..<candidates.count {
                if isSameVideo(candidates[i], candidates[j], threshold: threshold) {
                    uf.union(i, j)
                }
            }
        }
        var clusters: [Int: [VideoCandidate]] = [:]
        for i in 0..<candidates.count {
            clusters[uf.find(i), default: []].append(candidates[i])
        }
        return clusters.values.filter { $0.count > 1 }.map { VideoDupGroup(videos: $0) }
    }
}
