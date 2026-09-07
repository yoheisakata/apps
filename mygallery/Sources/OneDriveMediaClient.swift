import Foundation
import os

// MyGallery に OneDrive 共有リンクからの写真・動画ストリーミングを追加するための
// クライアント。`myslideshow/Sources/MySlideshow/Core/OneDriveMediaClient.swift` から
// ほぼそのまま移植したもの(認証フロー自体はさらに遡って mytube の
// `Core/OneDriveShareClient.swift` に由来する、非公開の内部API依存で予告なく仕様変更・
// 遮断される可能性がある点も同じ)。
//
// **移植時に絶対に落としてはいけない設計**(myslideshow/CLAUDE.md に記録された失敗の
// 経緯を踏まえたもの):
// - `scan(shareURL:onlyTopLevelFolders:)` を使うこと — 選択したフォルダだけをルート
//   直下で絞り込んでから`walk`で深く辿る。「まず全階層スキャンしてから事後的に絞り込む」
//   設計に戻すと、年/月/日と深くネストした実際のライブラリで著しく遅くなる。
// - サブフォルダの並列`walk`(`TaskGroup` + `ConcurrencyLimiter`で同時8リクエストに制限)
//   も維持する — 逐次`walk`に戻すと同様に遅くなる。
// - `scanWithRetry`の一時的ネットワークエラー自動リトライも維持する。

/// unified logging(Console.appと同じ仕組み)の共通ロガー。GUIを起動して目視確認できない
/// 制約があるため、`log show --predicate 'subsystem == "com.yosakata.mygallery"'`で
/// 後から読める形にしてある(myslideshow/mytubeの`Core/Log.swift`と同じ方針)。
enum GalleryLog {
    static let oneDrive = Logger(subsystem: "com.yosakata.mygallery", category: "onedrive")
}

/// 写真か動画かの種別。
enum MediaKind: Hashable, Codable {
    case photo
    case video
}

/// OneDrive共有フォルダから見つかった1件の写真・動画。
struct MediaItem: Identifiable, Hashable {
    /// `remoteID`を識別子にする ― `downloadURL`は署名付きURLで再スキャンのたびに変わる。
    var id: String { remoteID }

    let remoteID: String
    let downloadURL: URL
    let name: String
    /// 共有フォルダのルートから見た、このファイルを含むフォルダのパスコンポーネント。
    let folderPath: [String]
    let modifiedDate: Date?
    let kind: MediaKind
    /// バイト単位のファイルサイズ。APIレスポンスに`size`が無い場合のみ0
    /// (通常のOneDriveアイテムには必ず付いてくる)。
    let size: Int64
    /// OneDriveがサーバー側で生成済みの小さいサムネイル画像(`large`、写真・動画とも
    /// 数百px程度のJPEG)のURL。あれば`ThumbnailLoader`はこちらを使う ― `downloadURL`
    /// (元ファイルそのもの、数MB〜数十MB)を毎回グリッド用に丸ごとダウンロードする
    /// 必要がなくなる(2026-09-07追加、詳細は`CLAUDE.md`参照)。取得できなかった場合
    /// (APIがまだ生成していない等)は`nil`で、呼び出し側は`downloadURL`にフォールバック
    /// する。
    let thumbnailURL: URL?
}

enum OneDriveMediaClient {
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp",
    ]
    static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp",
    ]

    private static func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .networkConnectionLost || urlError.code == .timedOut
    }

    // MARK: - フォルダ構造だけを先に取得する2段階ロード(2026-09-06追加、同日中に
    // Year/Monthの2階層固定・トップフォルダごとのストリーミング表示へ改修)
    //
    // 以前は`scan(shareURL:onlyTopLevelFolders:)`が「選んだ年フォルダの中身(実際の
    // 写真・動画)まで全部集め終わってから返す」1回のスキャンだった。ユーザー要望
    // 「タブを開いたらまずディレクトリ(年/月)だけ先に表示し、チェックされている
    // フォルダのサムネイルを後から適宜表示したい」に対応するため、フェーズ1
    // (`scanFolderStructureStream` ― フォルダ階層だけを高速に取得)とフェーズ2
    // (`scanLeafFolders` ― チェック済みの葉フォルダだけを個別に、取得できたものから
    // 順に取得)の2段階に分割した(2026-09-06)。旧`scan`/`scanWithRetry`/`walk`/
    // `fetchItem`はこの2段階に置き換わり、呼び出し側が無くなったため削除済み。
    //
    // 実際のライブラリはYear/Month/Dayの3階層(日付フォルダ)まで存在するが、
    // フォルダツリーでの表示・チェックはYear/Monthの2階層までで十分、というユーザー
    // 判断により、フェーズ1は**Monthより深くは辿らない**(サブフォルダの有無を
    // 判定するための「1ページだけ覗く」往復リクエストも不要になった ― 常に
    // Monthを葉として扱う)。Day以下に実際にぶら下がっているファイルはフェーズ2の
    // `scanLeafFolderItems`がMonthフォルダ配下を再帰的に辿って回収する(下記参照)。
    // フォルダ階層が浅くなった分フェーズ1自体も速くなったが、それでも年フォルダが
    // 複数あると体感できる待ち時間が残るため、**年フォルダ1つ分の解決が終わるたびに
    // `AsyncThrowingStream`で随時返す**(全年フォルダぶん揃うまで待たせない ―
    // 「レイヤーごとに徐々に表示してほしい」というユーザー要望への対応)。

    /// スキャン結果から見つかったフォルダ1つ(まだ中の写真・動画は取得していない)。
    /// `driveId`/`itemId`を持っているので、後から`scanLeafFolders`でこのフォルダだけを
    /// 個別に(再スキャンせず)取得できる。
    struct OneDriveFolderRef: Hashable {
        let driveId: String
        let itemId: String
        let name: String
        /// ルートから見たパスコンポーネント(例: ["2026", "09"])。
        let pathComponents: [String]
        var children: [OneDriveFolderRef]

        static func == (a: OneDriveFolderRef, b: OneDriveFolderRef) -> Bool { a.itemId == b.itemId }
        func hash(into hasher: inout Hasher) { hasher.combine(itemId) }
    }

    /// **フェーズ1**: フォルダ階層(Year/Monthの2階層のみ)を、年フォルダが1つ解決する
    /// たびに随時返すストリーム。`sourceName`(ルート名)が最初のイベントとして届き、
    /// 以降は年フォルダ1つぶんの`OneDriveFolderRef`(Monthの子を含む)が届いた順に流れる。
    /// 呼び出し側(`MainWindowController.loadOneDriveFolderStructure`)は届いた年フォルダを
    /// その都度サイドバーのツリーに追加していく。
    static func scanFolderStructureStream(
        shareURL: String, onlyTopLevelFolders topLevelFolders: Set<String>
    ) -> AsyncThrowingStream<(sourceName: String, yearFolder: OneDriveFolderRef), Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let token = try await mintToken()
                    let root = try await resolveShare(shareURL: shareURL, token: token)
                    guard root.folder != nil else { continuation.finish(); return }

                    var matchingFolders: [DriveItemChild] = []
                    var nextURLString: String? = childrenURL(driveId: root.driveId, itemId: root.itemId)
                    while let current = nextURLString {
                        var request = URLRequest(url: URL(string: current)!)
                        request.httpMethod = "GET"
                        request.cachePolicy = .reloadIgnoringLocalCacheData
                        applyCommonHeaders(&request, token: token)
                        let (data, response) = try await URLSession.shared.data(for: request)
                        try checkOK(response, data: data)
                        let page = try decode(ChildrenResponse.self, from: data)
                        for child in page.value where child.folder != nil {
                            guard topLevelFolders.contains(child.name) else { continue }
                            matchingFolders.append(child)
                        }
                        nextURLString = page.nextLink
                    }

                    try await withThrowingTaskGroup(of: OneDriveFolderRef.self) { group in
                        for child in matchingFolders {
                            group.addTask {
                                try await walkYearFolderWithRetry(
                                    driveId: root.driveId, itemId: child.id, name: child.name,
                                    pathComponents: [child.name], token: token)
                            }
                        }
                        for try await yearFolder in group {
                            continuation.yield((root.name, yearFolder))
                        }
                    }
                    GalleryLog.oneDrive.notice("scanFolderStructureStream完了: \(root.name, privacy: .public) トップフォルダ数=\(matchingFolders.count)")
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 年フォルダ直下の1ページ目(Month相当のサブフォルダのみ)を取得する。**Monthより
    /// 深くは辿らない**(Day以下があっても`children: []`のまま葉として扱う ―
    /// 実ファイルの回収はフェーズ2の`scanLeafFolderItems`が担う)。
    private static func walkYearFolder(
        driveId: String, itemId: String, name: String, pathComponents: [String], token: String
    ) async throws -> OneDriveFolderRef {
        var months: [DriveItemChild] = []
        var nextURLString: String? = childrenURL(driveId: driveId, itemId: itemId)
        while let current = nextURLString {
            var request = URLRequest(url: URL(string: current)!)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            applyCommonHeaders(&request, token: token)

            await concurrencyLimiter.acquire()
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                await concurrencyLimiter.release()
                throw error
            }
            await concurrencyLimiter.release()
            try checkOK(response, data: data)
            let page = try decode(ChildrenResponse.self, from: data)
            months += page.value.filter { $0.folder != nil }
            nextURLString = page.nextLink
        }

        let children = months.map { month in
            OneDriveFolderRef(driveId: driveId, itemId: month.id, name: month.name,
                               pathComponents: pathComponents + [month.name], children: [])
        }
        return OneDriveFolderRef(driveId: driveId, itemId: itemId, name: name, pathComponents: pathComponents, children: children)
    }

    private static func walkYearFolderWithRetry(
        driveId: String, itemId: String, name: String, pathComponents: [String], token: String
    ) async throws -> OneDriveFolderRef {
        do {
            return try await walkYearFolder(driveId: driveId, itemId: itemId, name: name, pathComponents: pathComponents, token: token)
        } catch {
            guard isTransientNetworkError(error) else { throw error }
            return try await walkYearFolder(driveId: driveId, itemId: itemId, name: name, pathComponents: pathComponents, token: token)
        }
    }

    /// **フェーズ2**: フェーズ1で見つかった葉フォルダのうち、指定したものだけを並列に
    /// (`ConcurrencyLimiter`で同時実行数を絞りつつ)取得し、**取得できたものから順に**
    /// `AsyncThrowingStream`で返す ― 全フォルダぶん揃うまで待たせず、チェックボックスで
    /// チェックされているフォルダのサムネイルを「適宜」順次表示できるようにするため。
    ///
    /// **`shareURL`を受け取って`resolveShare(shareURL:token:)`(`Prefer: autoredeem`)を
    /// 呼ぶことが必須**(2026-09-06、実機で「フォルダ一覧は出るのにサムネイル取得の
    /// 段になるとAccess deniedになる」不具合を確認して発覚)。フェーズ1
    /// (`scanFolderStructureStream`)はmintTokenの直後に必ずresolveShareを呼んで
    /// トークンを共有リンクに対して「redeem」してから使っているが、フェーズ2は
    /// 独立してフレッシュな匿名トークンを`mintToken()`するだけで、そのトークンを
    /// 一度もこの共有リンクに対してredeemしていなかった ― 未redeemのトークンで
    /// `driveId`/`itemId`へ直接アクセスするとAPIがAccess deniedを返す。フェーズ1の
    /// トークンをそのまま使い回さない(=フェーズ2独自にトークンを取り直す)設計は
    /// 変えず、取り直したトークンを使う前に必ずこの共有リンクへredeemすること。
    static func scanLeafFolders(shareURL: String, folders: [OneDriveFolderRef]) -> AsyncThrowingStream<(folder: OneDriveFolderRef, items: [MediaItem]), Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    guard !folders.isEmpty else {
                        continuation.finish()
                        return
                    }
                    let token = try await mintToken()
                    _ = try await resolveShare(shareURL: shareURL, token: token)
                    try await withThrowingTaskGroup(of: (OneDriveFolderRef, [MediaItem]).self) { group in
                        for folder in folders {
                            group.addTask {
                                let items = try await scanLeafFolderItems(
                                    driveId: folder.driveId, itemId: folder.itemId,
                                    pathComponents: folder.pathComponents, token: token)
                                return (folder, items)
                            }
                        }
                        for try await (folder, items) in group {
                            continuation.yield((folder, items))
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 1つの葉フォルダ(Monthフォルダ)配下の写真・動画を取得する。フォルダツリーの
    /// 表示・チェックはYear/Monthまでだが、実データはさらに下のDayフォルダに
    /// 入っているため、**サブフォルダがあれば再帰的に辿って**回収する(2026-09-06、
    /// Year/Month/Dayの3階層運用に合わせて再帰化 ― 以前はMonth直下にファイルが
    /// 直接あるという前提で非再帰だったが、実際の運用はDayを挟むため直下だけ見ると
    /// 常に0件になっていた)。見つかった項目は実際の深さに関わらず、呼び出し元の
    /// Monthフォルダの`pathComponents`のまま`MediaItem.folderPath`に積む ―
    /// フォルダツリー・チェックボックスの絞り込みはMonth単位までしか無いため、
    /// Day単位の内訳をそのまま持たせても意味が無い(むしろ`filteredItems`の
    /// プレフィックス一致判定やグリッドの並べ替えがMonth単位のグループ化を前提に
    /// している ― 個々のファイルに実際のDayパスを持たせると整合しなくなる)。
    private static func scanLeafFolderItems(
        driveId: String, itemId: String, pathComponents: [String], token: String
    ) async throws -> [MediaItem] {
        var results: [MediaItem] = []
        var subfolders: [DriveItemChild] = []
        var nextURLString: String? = childrenURL(driveId: driveId, itemId: itemId, expandThumbnails: true)
        while let current = nextURLString {
            await concurrencyLimiter.acquire()
            let data: Data
            let response: URLResponse
            do {
                var request = URLRequest(url: URL(string: current)!)
                request.httpMethod = "GET"
                request.cachePolicy = .reloadIgnoringLocalCacheData
                applyCommonHeaders(&request, token: token)
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                await concurrencyLimiter.release()
                throw error
            }
            await concurrencyLimiter.release()
            try checkOK(response, data: data)
            let page = try decode(ChildrenResponse.self, from: data)
            for child in page.value {
                if let media = makeMediaItem(child, pathComponents: pathComponents) {
                    results.append(media)
                } else if child.folder != nil {
                    subfolders.append(child)
                }
            }
            nextURLString = page.nextLink
        }

        guard !subfolders.isEmpty else { return results }
        let nested = try await withThrowingTaskGroup(of: [MediaItem].self) { group -> [MediaItem] in
            for sub in subfolders {
                group.addTask {
                    try await scanLeafFolderItems(driveId: driveId, itemId: sub.id, pathComponents: pathComponents, token: token)
                }
            }
            var collected: [MediaItem] = []
            for try await items in group { collected += items }
            return collected
        }
        return results + nested
    }

    // MARK: - 1. 匿名トークン発行

    private static let appId = "00000000-0000-0000-0000-0000481710a4"
    private static let origin = "https://onedrive.live.com"

    private struct TokenResponse: Decodable { let token: String }

    private static func mintToken() async throws -> String {
        var request = URLRequest(url: URL(string: "https://api-badgerp.svc.ms/v1.0/token")!)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json;odata=verbose", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1141147648", forHTTPHeaderField: "AppId")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["appId": appId])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkOK(response, data: data)
        return try decode(TokenResponse.self, from: data).token
    }

    // MARK: - 2. 共有リンクの解決(+redeem)

    private struct ResolvedRoot {
        let driveId: String
        let itemId: String
        let name: String
        let folder: FolderFacet?
    }
    private struct DriveItemResolved: Decodable {
        struct ParentReference: Decodable { let driveId: String }
        let id: String
        let name: String
        let parentReference: ParentReference
        let folder: FolderFacet?
    }
    private struct FolderFacet: Decodable {}

    private static func resolveShare(shareURL: String, token: String) async throws -> ResolvedRoot {
        guard let encoded = encodeShareURL(shareURL) else { throw OneDriveMediaError.invalidShareURL }
        var components = URLComponents(
            string: "https://my.microsoftpersonalcontent.com/_api/v2.0/shares/\(encoded)/driveitem"
        )!
        components.queryItems = [URLQueryItem(name: "$select", value: "id,name,parentReference,folder")]

        var request = URLRequest(url: components.url!)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        applyCommonHeaders(&request, token: token)
        request.setValue("autoredeem", forHTTPHeaderField: "Prefer")
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data()

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkOK(response, data: data)
        let item = try decode(DriveItemResolved.self, from: data)
        return ResolvedRoot(driveId: item.parentReference.driveId, itemId: item.id, name: item.name, folder: item.folder)
    }

    /// 共有URL文字列をMicrosoft独自の`u!<base64url、パディング無し>`形式にエンコードする。
    private static func encodeShareURL(_ shareURL: String) -> String? {
        guard let data = shareURL.data(using: .utf8) else { return nil }
        let base64url = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "u!\(base64url)"
    }

    // MARK: - 3. フォルダの中身一覧(再帰) / 単体ファイル取得

    private struct ChildrenResponse: Decodable {
        let value: [DriveItemChild]
        let nextLink: String?
        enum CodingKeys: String, CodingKey {
            case value
            case nextLink = "@odata.nextLink"
        }
    }
    private struct DriveItemChild: Decodable {
        let id: String
        let name: String
        let lastModifiedDateTime: String?
        let folder: FolderFacet?
        let downloadURL: String?
        let size: Int64?
        /// `expand=thumbnails(select=large)`を付けたリクエストでのみ入る(付けなければ
        /// 常に`nil`)。フェーズ1のフォルダ一覧取得ではサムネイルが要らないので付けず、
        /// フェーズ2の`scanLeafFolderItems`(実ファイル一覧)でだけ付ける
        /// (`childrenURL(driveId:itemId:expandThumbnails:)`参照)。
        let thumbnails: [ThumbnailSet]?
        enum CodingKeys: String, CodingKey {
            case id, name, lastModifiedDateTime, folder, size, thumbnails
            case downloadURL = "@content.downloadUrl"
        }
    }
    private struct ThumbnailSet: Decodable {
        let large: ThumbnailSize?
    }
    private struct ThumbnailSize: Decodable {
        let url: String
    }

    private static func makeMediaItem(_ item: DriveItemChild, pathComponents: [String]) -> MediaItem? {
        guard item.folder == nil else { return nil }
        // "._IMG_0001.jpg"のようなAppleDoubleファイル(Finder経由のアップロード/同期時にmacOSが
        // 自動生成する隠しファイル)は拡張子だけでは弾けないため名前で明示的に除外する。
        guard !item.name.hasPrefix(".") else { return nil }
        let ext = (item.name as NSString).pathExtension.lowercased()
        let kind: MediaKind
        if videoExtensions.contains(ext) {
            kind = .video
        } else if photoExtensions.contains(ext) {
            kind = .photo
        } else {
            return nil
        }
        guard let downloadURLString = item.downloadURL, let downloadURL = URL(string: downloadURLString) else {
            return nil
        }
        let modifiedDate = item.lastModifiedDateTime.flatMap { ISO8601DateFormatter().date(from: $0) }
        let thumbnailURL = item.thumbnails?.first?.large.flatMap { URL(string: $0.url) }
        return MediaItem(
            remoteID: item.id, downloadURL: downloadURL, name: item.name,
            folderPath: pathComponents, modifiedDate: modifiedDate, kind: kind, size: item.size ?? 0,
            thumbnailURL: thumbnailURL
        )
    }

    /// `walkYearFolder`/`scanLeafFolderItems`の同時HTTPリクエスト数を絞るための
    /// actorベースのセマフォ。
    private actor ConcurrencyLimiter {
        private let limit: Int
        private var current = 0
        private var waiters: [CheckedContinuation<Void, Never>] = []

        init(limit: Int) { self.limit = limit }

        func acquire() async {
            if current < limit {
                current += 1
                return
            }
            await withCheckedContinuation { waiters.append($0) }
            current += 1
        }

        func release() {
            current -= 1
            if !waiters.isEmpty {
                waiters.removeFirst().resume()
            }
        }
    }

    private static let concurrencyLimiter = ConcurrencyLimiter(limit: 8)

    /// `expandThumbnails: true`で`&expand=thumbnails(select=large)`を付ける ―
    /// OneDriveがサーバー側で生成済みの小さいサムネイル(`large`、数百px)を同じ
    /// 1リクエストで一緒に返してもらう。フェーズ2(`scanLeafFolderItems`、実ファイル
    /// 一覧)でだけ付ける ― フェーズ1(`walkYearFolder`、フォルダ構造だけ)には不要な
    /// 追加コストなので付けない。
    private static func childrenURL(driveId: String, itemId: String, expandThumbnails: Bool = false) -> String {
        var url = "https://my.microsoftpersonalcontent.com/_api/v2.0/drives/\(driveId)/items/\(itemId)/children?%24top=200&select=*"
        if expandThumbnails {
            url += "&expand=thumbnails(select=large)"
        }
        return url
    }

    // MARK: - 共通処理

    private static func applyCommonHeaders(_ request: inout URLRequest, token: String) {
        request.setValue("Badger \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // このAPIは`Origin`/`Referer`が`onedrive.live.com`であることをサーバー側で検証している。
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("\(origin)/", forHTTPHeaderField: "Referer")
    }

    private static func checkOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw OneDriveMediaError.apiError(envelope.error.message)
            }
            throw OneDriveMediaError.apiError("HTTP \(status)")
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw OneDriveMediaError.apiError(envelope.error.message)
            }
            throw OneDriveMediaError.decodingFailed
        }
    }

    private struct APIErrorEnvelope: Decodable {
        struct ErrorBody: Decodable { let code: String; let message: String }
        let error: ErrorBody
    }
}

enum OneDriveMediaError: LocalizedError {
    case invalidShareURL
    case apiError(String)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidShareURL:
            return "共有リンクの形式が正しくありません"
        case .apiError(let message):
            return "OneDriveから読み込めませんでした(\(message))。リンクが無効か、共有が解除されている可能性があります"
        case .decodingFailed:
            return "OneDriveの応答を解析できませんでした(APIの仕様が変わった可能性があります)"
        }
    }
}
