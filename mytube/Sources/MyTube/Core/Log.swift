import Foundation
import os

/// 「パフォーマンスが悪い」という報告(2026-08-06)を受けて追加した、処理時間を
/// Console.app(サブシステム`com.yoheisakata.mytube`、カテゴリでフィルタ可能)で
/// 確認するための共通ロガー。カテゴリごとに分けているのは、Console.appの検索欄で
/// `subsystem:com.yoheisakata.mytube category:thumbnail`のように絞り込めるようにするため。
enum Log {
    static let scan = Logger(subsystem: "com.yoheisakata.mytube", category: "scan")
    static let thumbnail = Logger(subsystem: "com.yoheisakata.mytube", category: "thumbnail")
    static let download = Logger(subsystem: "com.yoheisakata.mytube", category: "download")
    static let sidebar = Logger(subsystem: "com.yoheisakata.mytube", category: "sidebar")

    /// 処理の所要時間をミリ秒で計測してログに出す(同期処理用)。
    static func measure<T>(_ logger: Logger, _ label: String, _ body: () -> T) -> T {
        let start = DispatchTime.now()
        let result = body()
        logger.info("\(label) (\(Self.elapsedMs(since: start), format: .fixed(precision: 1))ms)")
        return result
    }

    /// 処理の所要時間をミリ秒で計測してログに出す(非同期処理用)。
    static func measure<T>(_ logger: Logger, _ label: String, _ body: () async throws -> T) async rethrows -> T {
        let start = DispatchTime.now()
        let result = try await body()
        logger.info("\(label) (\(Self.elapsedMs(since: start), format: .fixed(precision: 1))ms)")
        return result
    }

    static func elapsedMs(since start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }
}
