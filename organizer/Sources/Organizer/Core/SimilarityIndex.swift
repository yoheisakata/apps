import Foundation

struct SimilarityMatch {
    let url: URL
    let date: Date
}

/// 「候補フォルダ(例: 2020年・2021年)の中から、本物のTIFF/EXIF撮影日を持つ写真」だけを集めた
/// 参照インデックス。誤配置修正(PhotoVerifier)がEXIF等どの情報源からも撮影日が分からず
/// mtimeフォールバックになったファイルに対し、「見た目が近い、EXIF付きの写真」から日付を
/// 借用するために使う。
struct SimilarityIndex {
    private struct Candidate {
        let url: URL
        let dhash: UInt64
        let date: Date
    }

    private let candidates: [Candidate]
    private let threshold: Int

    /// しきい値以内でハミング距離が最小の候補を返す。同距離の場合はcandidates配列の並び順
    /// (=ファイル列挙順)で先に見つかったものを採用する(concurrentPerformの完了順ではなく
    /// 列挙順で決定的に並べてあるため、実行のたびに結果が変わらない)。
    func closestMatch(for dhash: UInt64) -> SimilarityMatch? {
        var best: (candidate: Candidate, distance: Int)?
        for c in candidates {
            let distance = (c.dhash ^ dhash).nonzeroBitCount
            guard distance <= threshold else { continue }
            if best == nil || distance < best!.distance {
                best = (c, distance)
            }
        }
        return best.map { SimilarityMatch(url: $0.candidate.url, date: $0.candidate.date) }
    }

    /// roots配下を再帰列挙し、MediaDateResolver.fromSips(url)が非nilを返すファイル
    /// (=本物のTIFF/EXIF撮影日を持つファイル。フォルダ名/ファイル名/mtimeなどの推定は信用しない)
    /// だけを候補として集める。sipsをファイルごとに同期呼び出しするため候補数が多いと遅く、
    /// DupPhotosViewModel.scan()と同じ「[T?](repeating:nil) + concurrentPerform + 各iterationが
    /// 自分のindexだけに書く」パターンで並列化する(共有配列へのappendは並行安全ではないため)。
    static func build(
        roots: [URL],
        extensions: Set<String>,
        threshold: Int,
        progress: @escaping (String) -> Void,
        checkCancel: () throws -> Void
    ) throws -> SimilarityIndex {
        let fm = FileManager.default
        var urls: [URL] = []
        for root in roots {
            try checkCancel()
            guard let e = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else { continue }
            for case let url as URL in e {
                guard extensions.contains(url.pathExtension.lowercased()) else { continue }
                urls.append(url)
            }
        }
        try checkCancel()
        progress("類似写真の参照インデックスを構築中: \(urls.count) 件をスキャン…")

        var results = [Candidate?](repeating: nil, count: urls.count)
        results.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                let url = urls[i]
                guard let resolved = MediaDateResolver.fromSips(url), let hash = PerceptualHash.dHash(of: url) else { return }
                buf[i] = Candidate(url: url, dhash: hash, date: resolved.date)
            }
        }
        try checkCancel()

        let candidates = results.compactMap { $0 }
        progress("類似写真の参照候補: \(candidates.count) 件(EXIF/TIFF付き)\n")
        return SimilarityIndex(candidates: candidates, threshold: threshold)
    }
}

/// 実際にレスキューが必要になるまでSimilarityIndexのビルドを遅延する(候補年を設定していても、
/// mtimeフォールバックが一度も発生しなければコストゼロにするため。sipsをファイルごとに呼ぶため
/// 候補年が多いと遅い)。PhotoVerifier.runは複数の対象(年・月)に対して繰り返し呼ばれるが、
/// 同じインスタンスを使い回すことでビルドは最初の1回だけになる。
final class LazySimilarityIndex {
    private let makeIndex: () throws -> SimilarityIndex
    private var cached: SimilarityIndex?

    init(build: @escaping () throws -> SimilarityIndex) {
        self.makeIndex = build
    }

    func get() throws -> SimilarityIndex {
        if let cached { return cached }
        let index = try makeIndex()
        cached = index
        return index
    }
}
