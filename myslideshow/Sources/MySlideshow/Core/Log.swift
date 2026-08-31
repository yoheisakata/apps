import os

/// unified logging(Console.appと同じ仕組み)の共通ロガー。サブシステムは
/// `com.yoheisakata.myslideshow`固定 ― `log show --predicate
/// 'subsystem == "com.yoheisakata.myslideshow"'`で絞り込める。mytubeの`Core/Log.swift`と
/// 同じ方針(2026-08-29、「サブディレクトリが出てこない」原因調査用に追加)。
enum Log {
    static let scan = Logger(subsystem: "com.yoheisakata.myslideshow", category: "scan")
}
