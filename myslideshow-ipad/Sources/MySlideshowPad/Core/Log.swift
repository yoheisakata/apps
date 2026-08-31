import os

/// unified logging(Console.appと同じ仕組み)の共通ロガー。サブシステムは
/// `com.yoheisakata.myslideshowpad`固定(Mac版の`com.yoheisakata.myslideshow`とは別) ―
/// `log show --predicate 'subsystem == "com.yoheisakata.myslideshowpad"'`で絞り込める。
enum Log {
    static let scan = Logger(subsystem: "com.yoheisakata.myslideshowpad", category: "scan")
}
