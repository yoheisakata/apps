import CryptoKit
import Foundation

/// OneDrive共有リンクのスキャン結果をローカルにキャッシュし、次回そのリンクを開いたときに
/// まず即座に表示する、stale-while-revalidate方式の薄いキャッシュ層(2026-08-28追加、
/// 「毎回OneDriveから一覧をとってくるのを効率よくできないか。一覧はローカルに保存して、
/// 起動時にバックグラウンドで更新するような」という要望への対応)。mytube(Mac版)の
/// `Core/RemoteListCache.swift`と同じ設計 ― `ContentView.loadSource(bookmark:)`が
/// 新規にそのリンクを開く際、まずここにキャッシュがあればそれを即座に表示し、その裏で
/// 必ず`OneDriveShareClient.scan`を実行して最新の結果で上書きする。古いデータが
/// 表示され続けることはなく、スキャンにかかる数秒〜数十秒だけ前回の一覧が見える。
///
/// **既知の注意点**(ユーザーに伝えること): キャッシュに入っている`VideoItem.downloadURL`
/// (tempauth署名付きURL)は実測1時間程度で失効する。バックグラウンドの再スキャンが
/// 完了する前に、キャッシュから復元した古いURLのまま再生しようとすると失敗しうる
/// (再スキャンが終われば新しいURLに置き換わる)。ダウンロード済みの動画は
/// `DownloadStore.playableURL(for:)`がローカルファイルを優先するため、この問題の
/// 影響を受けない。
enum RemoteListCache {
    private struct CachedSource: Codable {
        let sourceName: String
        let videos: [VideoItem]
    }

    private static let cacheDir: URL = {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("MyTubePad/remote-list-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static func fileURL(for shareURL: String) -> URL {
        let digest = SHA256.hash(data: Data(shareURL.utf8))
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(hex).json")
    }

    static func load(for shareURL: String) -> (sourceName: String, videos: [VideoItem])? {
        guard let data = try? Data(contentsOf: fileURL(for: shareURL)) else { return nil }
        guard let cached = try? JSONDecoder().decode(CachedSource.self, from: data) else { return nil }
        return (cached.sourceName, cached.videos)
    }

    static func save(shareURL: String, sourceName: String, videos: [VideoItem]) {
        let cached = CachedSource(sourceName: sourceName, videos: videos)
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: fileURL(for: shareURL))
    }
}
