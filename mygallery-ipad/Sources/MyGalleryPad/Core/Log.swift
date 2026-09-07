import os

/// unified logging(Console.appと同じ仕組み)の共通ロガー。サブシステムは
/// `com.yoheisakata.mygalleryipad`固定(mygallery Mac版の`com.yosakata.mygallery`とは
/// 別、myslideshow-ipad/mytube-ipadと同じ「アプリごとに専用サブシステム」方針) ―
/// `log show --predicate 'subsystem == "com.yoheisakata.mygalleryipad"'`で絞り込める。
enum Log {
    static let scan = Logger(subsystem: "com.yoheisakata.mygalleryipad", category: "scan")
}
