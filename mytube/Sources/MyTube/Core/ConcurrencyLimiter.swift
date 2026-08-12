import Foundation

/// 同時実行数を制限する軽量な async セマフォ。サムネイル生成(AVAssetImageGenerator)を
/// 大量の動画に対して一斉に走らせるとメモリ・CPU を圧迫するため、`ThumbnailStore` から使う。
actor ConcurrencyLimiter {
    private let limit: Int
    private var running = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) {
        self.limit = max(1, limit)
    }

    func acquire() async {
        if running < limit {
            running += 1
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        running += 1
    }

    func release() {
        running -= 1
        if !waiters.isEmpty {
            waiters.removeFirst().resume()
        }
    }
}
