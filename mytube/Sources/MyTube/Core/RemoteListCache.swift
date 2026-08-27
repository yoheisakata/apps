import Foundation
import CryptoKit

/// OneDrive/YouTubeの一覧取得結果をディスクへ永続化し、次回起動時に「前回の一覧を即座に
/// 表示しつつ、裏で最新のスキャン結果に差し替える」ためのプレースホルダーとして使う
/// (2026-08-20追加、「起動直後、フォルダの再帰スキャンが終わるまでOneDriveのセクションが
/// 丸ごと表示されない(`SidebarView.sourceGroup`は動画0件のグループを見出しごと出さない
/// ため)」というユーザー報告への対応)。
///
/// **`OneDriveShareClient`/`YouTubePlaylistClient`側のHTTPレスポンスキャッシュ
/// (`URLCache`)は引き続き無効化したまま**(`cachePolicy = .reloadIgnoringLocalCacheData`、
/// 「タイトルが実際のファイル名と全く違う古い名前になる」バグの修正)― こちらは完全に
/// 別レイヤーのキャッシュで、「フレッシュな結果が返ってくるまでの間、何も無いより前回の
/// 一覧を見せておく」ためだけのもの。`ContentView.openRemote`は毎回必ず実際のスキャンを
/// 実行し、成功次第この一覧を新しい内容で上書きする ― 古いデータが表示され続けることは
/// ない(スキャンにかかる数秒〜数十秒だけ、前回の一覧が見える)。
enum RemoteListCache {
    private struct CachedList: Codable {
        let sourceName: String
        let videos: [VideoItem]
    }

    private static var cacheDir: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent("MyTube/remote-list-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// 共有URL文字列からキャッシュファイル名を作る(`ThumbnailStore.cacheKey`と同じ
    /// SHA256方式 ― URL自体をファイル名にすると記号のエスケープが煩雑なため)。
    private static func fileURL(for shareURL: String) -> URL {
        let digest = SHA256.hash(data: Data(shareURL.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent("\(key).json")
    }

    /// 前回保存済みの一覧を読む(無ければ`nil`)。`ContentView.openRemote`が新規オープン時に
    /// 呼び、取得できればそれを`RemoteSource.videos`の初期値にする。同期I/Oだが、対象は
    /// 起動時に開く数件のソース分だけの小さいJSONファイルであり、`ThumbnailStore`のような
    /// 高頻度呼び出しではないため許容している。
    static func load(for shareURL: String) -> (sourceName: String, videos: [VideoItem])? {
        guard let data = try? Data(contentsOf: fileURL(for: shareURL)) else { return nil }
        guard let cached = try? JSONDecoder().decode(CachedList.self, from: data) else { return nil }
        return (cached.sourceName, cached.videos)
    }

    /// スキャン成功のたびに呼び、最新の一覧で上書き保存する。呼び出し側
    /// (`ContentView.openRemote`)は`Task.detached`経由でこれを呼ぶため、ここでの
    /// ファイルI/Oがメインスレッドを塞ぐことはない。
    static func save(sourceName: String, videos: [VideoItem], for shareURL: String) {
        let cached = CachedList(sourceName: sourceName, videos: videos)
        guard let data = try? JSONEncoder().encode(cached) else { return }
        try? data.write(to: fileURL(for: shareURL), options: .atomic)
    }
}
