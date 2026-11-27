import Foundation
import Vision

struct FeatureMatch {
    let url: URL
    let date: Date
    let distance: Float
}

/// 「日付推定」ペインの参照インデックス。SimilarityIndex(誤配置修正の類似写真フォールバック)と
/// 同じ「候補フォルダ配下の、本物のEXIF撮影日を持つ写真だけを集める」という構築方法だが、
/// dHashの代わりにFaceFocusedFeaturePrintの特徴量を使い、1件に決め打ちせず上位k件を
/// 距離昇順で返す(自動確定はせず、人が候補から選ぶ前提のため)。
struct FeaturePrintIndex {
    private struct Candidate {
        let url: URL
        let observation: VNFeaturePrintObservation
        let date: Date
    }

    private let candidates: [Candidate]

    /// 距離が近い順に上位k件を返す(SimilarityIndex.closestMatchと違い、1件には絞らない)。
    func nearestMatches(for observation: VNFeaturePrintObservation, k: Int) -> [FeatureMatch] {
        var scored: [(Candidate, Float)] = []
        scored.reserveCapacity(candidates.count)
        for c in candidates {
            var distance: Float = 0
            guard (try? observation.computeDistance(&distance, to: c.observation)) != nil else { continue }
            scored.append((c, distance))
        }
        return scored.sorted { $0.1 < $1.1 }.prefix(k).map {
            FeatureMatch(url: $0.0.url, date: $0.0.date, distance: $0.1)
        }
    }

    /// roots配下を再帰列挙し、MediaDateResolver.fromSips(url)が非nilを返すファイル
    /// (=本物のEXIF撮影日を持つファイル)だけを候補にする。SimilarityIndex.buildと同じ
    /// 「[T?](repeating:nil) + concurrentPerform + 各iterationが自分のindexだけに書く」
    /// パターンで並列化する(Vision推論は1枚ずつの同期呼び出しになるため、候補数が多いと遅い)。
    static func build(
        roots: [URL],
        extensions: Set<String>,
        progress: @escaping (String) -> Void,
        checkCancel: () throws -> Void
    ) throws -> FeaturePrintIndex {
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
        progress("参照インデックスを構築中: \(urls.count) 件をスキャン…")

        // Vision推論(顔検出+特徴量計算)はワーカースレッドごとに内部バッファを持つため、
        // concurrentPerformのスレッド数に任せて候補全件を一気に処理するとメモリを使い果たす
        // (VideoDupViewModelのffmpeg/ffprobe並列実行と同じ理由で、同時実行数を絞る)。
        let maxConcurrent = max(1, min(4, ProcessInfo.processInfo.activeProcessorCount))
        let throttle = DispatchSemaphore(value: maxConcurrent)
        var results = [Candidate?](repeating: nil, count: urls.count)
        results.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: urls.count) { i in
                throttle.wait()
                defer { throttle.signal() }
                let url = urls[i]
                guard let resolved = MediaDateResolver.fromSips(url),
                      let observation = FaceFocusedFeaturePrint.compute(for: url) else { return }
                buf[i] = Candidate(url: url, observation: observation, date: resolved.date)
            }
        }
        try checkCancel()

        let candidates = results.compactMap { $0 }
        progress("参照候補: \(candidates.count) 件(EXIF付き)\n")
        return FeaturePrintIndex(candidates: candidates)
    }
}
