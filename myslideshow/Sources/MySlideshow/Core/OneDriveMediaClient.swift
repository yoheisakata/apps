import Foundation

/// OneDrive(個人)の「リンクを知っている全員が閲覧可能」共有フォルダ/ファイルを、
/// ブラウザにサインインせずスキャンして写真・動画混在の`MediaItem`一覧を得るクライアント。
///
/// 認証フロー(匿名Badgerトークン発行 → 共有リンクの解決[+redeem] → children一覧の再帰取得)は
/// mytubeの`Core/OneDriveShareClient.swift`からそのまま移植したもの(ブラウザの開発者ツールでの
/// 通信解析で判明した非公開の内部APIで、予告なく仕様変更・遮断される可能性がある点も同じ)。
/// 違いは対象拡張子を動画だけでなく画像にも広げたことと、`VideoItem`ではなく写真/動画どちらも
/// 表せる`MediaItem`(`kind`で区別)を返すこと ― 詳しい経緯・注意点はmytube側のコメントを参照。
enum OneDriveMediaClient {
    /// 1階層目のサブフォルダを持たない(ルート直下に置かれた)写真・動画のフォルダラベル。
    /// `ContentView`の年別チェックボックス(`HardcodedLink.availableFolders`)はこの値を
    /// 選択肢に含めていないため、`scan(shareURL:onlyTopLevelFolders:)`はルート直下の
    /// ファイルを既定では対象外にする(このラベル自体が`topLevelFolders`に含まれない限り)。
    static let rootFolderLabel = "(ルート)"

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp",
    ]
    static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp",
    ]

    /// フォルダ構造を全階層たどる(mytubeの`OneDriveShareClient.scan`と同じ、深さ制限なし)。
    /// **`ContentView`は直接これを呼ばず、`scanWithRetry(shareURL:)`経由で呼ぶこと**
    /// (下記参照) ― 深いフォルダ階層(年/月/日等)を持つ大きいライブラリでは、フォルダ数の
    /// ぶんだけ逐次HTTPリクエストが発生し、途中のどこかで一時的な接続断を踏む確率が
    /// 上がる。`walk`は例外を投げるとそこまでの結果ごと丸ごと捨てて呼び出し元へ伝播するため、
    /// リトライ無しで一度でも失敗するとスキャン全体が「何も出てこない」ように見える
    /// (2026-08-29、「動画・写真の年フォルダが出てこない/再ロードしてもでてこない」という
    /// 報告の原因。**一時期`maxDepth`引数で1階層目だけに制限する高速化を試みたが、
    /// このユーザーのOneDriveライブラリは実際には年/月/日と3階層以上ネストしており、
    /// 1階層目には直下にファイルがほぼ無かったため「フォルダは見えるのに中身が0件」という
    /// 別の不具合を生んだ。「MyTubeを参考にして」という指示を受け、深さ制限を撤去して
    /// mytube版と同じ全階層走査+リトライだけにする方針に戻した**)。
    static func scan(shareURL: String) async throws -> (sourceName: String, items: [MediaItem]) {
        let token = try await mintToken()
        let root = try await resolveShare(shareURL: shareURL, token: token)
        Log.scan.notice("resolveShare: name=\(root.name, privacy: .public) isFolder=\(root.folder != nil) driveId=\(root.driveId, privacy: .public) itemId=\(root.itemId, privacy: .public)")

        if root.folder == nil {
            // 共有リンクがフォルダではなく写真/動画ファイル単体を指している場合。
            let item = try await fetchItem(driveId: root.driveId, itemId: root.itemId, token: token)
            guard let media = makeMediaItem(item, pathComponents: []) else { return (root.name, []) }
            return (root.name, [media])
        }

        let results = try await walk(driveId: root.driveId, itemId: root.itemId, pathComponents: [], token: token)
        Log.scan.notice("scan完了: \(root.name, privacy: .public) 総件数=\(results.count)")
        return (root.name, results)
    }

    /// `scan(shareURL:)`を、一時的なネットワークエラー(`URLError.networkConnectionLost`/
    /// `.timedOut`)だけ自動で1回リトライするラッパー。mytubeの
    /// `ContentView.scanOneDriveWithRetry(shareURL:)`と同じロジックをそのまま移植したもの
    /// (`ContentView`はこちらを呼ぶこと、`scan(shareURL:)`を直接呼ばない)。
    static func scanWithRetry(shareURL: String) async throws -> (sourceName: String, items: [MediaItem]) {
        do {
            return try await scan(shareURL: shareURL)
        } catch {
            guard isTransientNetworkError(error) else { throw error }
            Log.scan.notice("scanWithRetry: 一時的なネットワークエラーのため再試行します: \(String(describing: error), privacy: .public)")
            return try await scan(shareURL: shareURL)
        }
    }

    private static func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .networkConnectionLost || urlError.code == .timedOut
    }

    /// `scan(shareURL:)`と違い、**ルート直下のうち`topLevelFolders`に名前が一致する
    /// フォルダだけ**を深く辿る(一致しないフォルダは中に入らず丸ごとスキップする)。
    /// 2026-08-29、「スライドショーがなかなか始まらない」という報告への対応 ―
    /// `ContentView.start()`は選んだ年(`selectedFolders`)だけが対象のはずなのに、
    /// これまでは`scan(shareURL:)`でリンク全体(選んでいない年、さらに「璃央のカメラ」の
    /// ような年フォルダ以外のフォルダも含む)を丸ごとスキャンしてから事後的に
    /// `items.filter`で絞り込んでいたため、選んだ年が少なくてもスキャン時間は
    /// 変わらなかった。ルート直下だけ`walk`と同じページングで列挙し、名前が一致した
    /// フォルダだけ`walk(...)`で深く辿ることで、選んでいない年のツリーへは一切
    /// アクセスしなくなる。ルート直下に直接置かれたファイル(フォルダ構造を持たない
    /// リンク向け)は`topLevelFolders`によるフィルタの対象外として常に含める。
    static func scan(shareURL: String, onlyTopLevelFolders topLevelFolders: Set<String>) async throws -> (sourceName: String, items: [MediaItem]) {
        let token = try await mintToken()
        let root = try await resolveShare(shareURL: shareURL, token: token)
        Log.scan.notice("resolveShare(絞込): name=\(root.name, privacy: .public) isFolder=\(root.folder != nil) 対象フォルダ=\(topLevelFolders.sorted().joined(separator: ","), privacy: .public)")

        if root.folder == nil {
            let item = try await fetchItem(driveId: root.driveId, itemId: root.itemId, token: token)
            guard let media = makeMediaItem(item, pathComponents: []) else { return (root.name, []) }
            return (root.name, [media])
        }

        var rootLevelMedia: [MediaItem] = []
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

            for child in page.value {
                if child.folder != nil {
                    guard topLevelFolders.contains(child.name) else { continue }
                    matchingFolders.append(child)
                } else if let media = makeMediaItem(child, pathComponents: []) {
                    guard topLevelFolders.contains(Self.rootFolderLabel) else { continue }
                    rootLevelMedia.append(media)
                }
            }
            nextURLString = page.nextLink
        }

        // 選んだ年フォルダどうしも並列に(下記`walk`のコメント参照、`ConcurrencyLimiter`が
        // 全体の同時実行数を抑えるのでここで並列にしても実行数が際限なく増えることはない)。
        var results = rootLevelMedia
        if !matchingFolders.isEmpty {
            let nested = try await withThrowingTaskGroup(of: [MediaItem].self) { group -> [MediaItem] in
                for child in matchingFolders {
                    group.addTask {
                        try await walk(driveId: root.driveId, itemId: child.id, pathComponents: [child.name], token: token)
                    }
                }
                var collected: [MediaItem] = []
                for try await items in group { collected += items }
                return collected
            }
            results += nested
        }
        Log.scan.notice("scan完了(絞込): \(root.name, privacy: .public) 総件数=\(results.count)")
        return (root.name, results)
    }

    /// `scan(shareURL:onlyTopLevelFolders:)`の一時的ネットワークエラー自動リトライ版
    /// (`scanWithRetry(shareURL:)`と同じロジック)。
    static func scanWithRetry(shareURL: String, onlyTopLevelFolders topLevelFolders: Set<String>) async throws -> (sourceName: String, items: [MediaItem]) {
        do {
            return try await scan(shareURL: shareURL, onlyTopLevelFolders: topLevelFolders)
        } catch {
            guard isTransientNetworkError(error) else { throw error }
            Log.scan.notice("scanWithRetry(絞込): 一時的なネットワークエラーのため再試行します: \(String(describing: error), privacy: .public)")
            return try await scan(shareURL: shareURL, onlyTopLevelFolders: topLevelFolders)
        }
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
        enum CodingKeys: String, CodingKey {
            case id, name, lastModifiedDateTime, folder
            case downloadURL = "@content.downloadUrl"
        }
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
        return MediaItem(
            remoteID: item.id, downloadURL: downloadURL, name: item.name,
            folderPath: pathComponents, modifiedDate: modifiedDate, kind: kind
        )
    }

    /// フォルダ1つぶんの中身を取得し、サブフォルダは`TaskGroup`で並列に`walk`する
    /// (2026-08-29、「スライドショーがなかなか始まらない」「まだ遅い」という報告への
    /// 対応 ― フォルダの絞り込み(`onlyTopLevelFolders`)だけでは、選んだ年フォルダ自体が
    /// 年/月/日と深くネストしていると、その中の月・日フォルダぶんの逐次HTTPリクエストは
    /// 変わらず残る。以前は`inout`配列へ直接追記する完全に逐次的な実装だったが、
    /// 兄弟フォルダ(同じ月の中の日フォルダ等)を並列に取得できるよう、戻り値ベース
    /// (`inout`は並行タスク間で安全に共有できないため)+`TaskGroup`に書き換えた。
    /// `ConcurrencyLimiter`で同時実行数を絞っているため、フォルダ数が多くても
    /// リクエストが際限なく同時に飛ぶことはない(OneDrive側のレート制限を避けるため)。
    private static func walk(
        driveId: String, itemId: String, pathComponents: [String], token: String
    ) async throws -> [MediaItem] {
        var results: [MediaItem] = []
        var subfolders: [DriveItemChild] = []
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

            var mediaCount = 0
            var skippedCount = 0
            for child in page.value {
                if child.folder != nil {
                    subfolders.append(child)
                } else if let media = makeMediaItem(child, pathComponents: pathComponents) {
                    mediaCount += 1
                    results.append(media)
                } else {
                    skippedCount += 1
                }
            }
            let pathLabel = pathComponents.isEmpty ? "(ルート)" : pathComponents.joined(separator: "/")
            Log.scan.notice("walk[\(pathLabel, privacy: .public)]: children=\(page.value.count) folders=\(subfolders.count) media=\(mediaCount) skipped=\(skippedCount) hasNextLink=\(page.nextLink != nil)")
            nextURLString = page.nextLink
        }

        guard !subfolders.isEmpty else { return results }
        let nested = try await withThrowingTaskGroup(of: [MediaItem].self) { group -> [MediaItem] in
            for child in subfolders {
                group.addTask {
                    try await walk(driveId: driveId, itemId: child.id, pathComponents: pathComponents + [child.name], token: token)
                }
            }
            var collected: [MediaItem] = []
            for try await items in group { collected += items }
            return collected
        }
        results += nested
        return results
    }

    /// `walk`の同時HTTPリクエスト数を絞るためのactorベースのセマフォ。フォルダ1つに
    /// つきリクエスト1回かかるため、`TaskGroup`で兄弟フォルダを無制限に並列実行すると
    /// 大きいツリー(月×日フォルダ等)で一瞬に数百リクエストが飛びかねない ―
    /// myorganizerが`DispatchSemaphore`でffmpeg/ffprobeの同時実行数を絞っているのと
    /// 同じ考え方をSwift Concurrency(actor)で実装したもの。
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

    private static func fetchItem(driveId: String, itemId: String, token: String) async throws -> DriveItemChild {
        var components = URLComponents(
            string: "https://my.microsoftpersonalcontent.com/_api/v2.0/drives/\(driveId)/items/\(itemId)"
        )!
        components.queryItems = [URLQueryItem(name: "select", value: "*")]
        var request = URLRequest(url: components.url!)
        request.httpMethod = "GET"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        applyCommonHeaders(&request, token: token)

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkOK(response, data: data)
        return try decode(DriveItemChild.self, from: data)
    }

    private static func childrenURL(driveId: String, itemId: String) -> String {
        "https://my.microsoftpersonalcontent.com/_api/v2.0/drives/\(driveId)/items/\(itemId)/children?%24top=200&select=*"
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
