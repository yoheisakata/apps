import Foundation

/// OneDrive(個人)の「リンクを知っている全員が閲覧可能」共有フォルダ/ファイルを、
/// ブラウザにサインインせずスキャンして`VideoItem`一覧を得るクライアント。
///
/// ブラウザの開発者ツールでの通信解析(2026-08-04)で判明した3ステップ:
/// 1. `POST https://api-badgerp.svc.ms/v1.0/token` に固定のappId(公開値、秘密情報ではない
///    ― OneDrive Webクライアント自身のJSバンドルにハードコードされている)を渡すと、
///    完全に匿名の短命トークン(JWT、"Badger"スキーム)が発行される。アカウントへの
///    サインインは一切不要で、共有リンクの情報すら渡さない汎用的な発行リクエスト。
/// 2. そのトークンを`Authorization: Badger <token>`として、共有URLをMicrosoft独自の
///    `u!<base64url>`形式にエンコードした`/shares/{encoded}/driveitem`へ`Prefer: autoredeem`
///    付きでPOSTすると、その共有アイテムの`driveId`/`itemId`が返る。同時にこの呼び出しが
///    「このトークンをこの共有に対して読み取り許可する」という副作用(redeem)を持つため、
///    以降のAPI呼び出しは必ず同じトークンを使い回す必要がある(別トークンだとaccessDenied)。
/// 3. `/drives/{driveId}/items/{itemId}/children`をGETすると、フォルダの中身一覧が
///    `@content.downloadUrl`(tempauth署名付き、追加認証なしで直接ストリーミング/
///    ダウンロード可能なURL、有効期限は短め・実測で1時間程度)付きで返る。
///
/// いずれも`api-badgerp.svc.ms`/`my.microsoftpersonalcontent.com`という、Microsoftが
/// サードパーティ向けに公開しているGraph APIではなくOneDrive Webクライアント自身が使う
/// 内部APIのため、**予告なく仕様変更・遮断される可能性がある**(公式サポート対象外)。
/// また`@content.downloadUrl`の有効期限が短いため、フォルダ読み込みから1時間以上経ってからの
/// 再生は失敗する可能性がある(既知の制限。再生直前に再取得するリトライは未実装)。
///
/// **全リクエストに`cachePolicy = .reloadIgnoringLocalCacheData`を付けている**(2026-08-20追加、
/// 「タイトルが実際のファイル名と全く違う古い名前になる」というユーザー報告への対応 ―
/// `URLSession.shared`は既定で`URLCache.shared`を使うため、`children`一覧取得のGETリクエストは
/// 同じフォルダなら毎回同一URLになり、サーバーがキャッシュ可能なレスポンスを返していた場合、
/// OneDrive側でファイルを追加・削除・リネームした後にサイドバーの🔄「再スキャン」を押しても、
/// ネットワークへ問い合わせず`URLCache`に残っていた古いレスポンスがそのまま返っていた可能性が
/// ある。再スキャンが名実ともに「最新を取り直す」操作になるよう、全リクエストでローカル
/// キャッシュを無視するようにした。
enum OneDriveShareClient {
    struct RemoteVideo {
        let downloadURL: URL
        let name: String
        /// ルート直下の最初のサブフォルダ名(表示ラベル用、`folderPath.first`と同じ値)。
        let channel: String
        /// 共有フォルダのルートから見た、この動画を含むフォルダのパスコンポーネント
        /// (`VideoScanner`のローカル版と同じ規約。ルート直下なら`[]`)。
        let folderPath: [String]
        let modifiedDate: Date?
        let remoteID: String
        /// APIレスポンスに含まれるファイルサイズ(2026-08-14復活、`VideoItem.knownFileSize`
        /// のドキュメント参照)。ダウンロード前でもサイズを表示できるようにするため。
        let size: Int64?
    }

    /// 共有URLからフォルダ(またはファイル単体)を再帰的にスキャンし、対応拡張子の動画だけを
    /// `VideoItem`として返す。フォルダ階層は`folderPath`にそのまま保持する(`VideoScanner`の
    /// ローカル版と同じ規約)。`sourceName`は共有元フォルダ/ファイルの名前で、UI上のフォルダ名
    /// 表示に使う。
    static func scan(shareURL: String) async throws -> (sourceName: String, videos: [VideoItem]) {
        let start = DispatchTime.now()
        let result = try await scanImpl(shareURL: shareURL)
        Log.scan.info("OneDriveShareClient.scan(\(result.sourceName, privacy: .public)): \(result.videos.count)件 (\(Log.elapsedMs(since: start), format: .fixed(precision: 1))ms)")
        return result
    }

    private static func scanImpl(shareURL: String) async throws -> (sourceName: String, videos: [VideoItem]) {
        let token = try await mintToken()
        let root = try await resolveShare(shareURL: shareURL, token: token)

        if root.folder == nil {
            // 共有リンクがフォルダではなく動画ファイル単体を指している場合。
            let item = try await fetchItem(driveId: root.driveId, itemId: root.itemId, token: token)
            guard let video = makeRemoteVideo(item, pathComponents: []) else { return (root.name, []) }
            return (root.name, [toVideoItem(video)])
        }

        var results: [RemoteVideo] = []
        try await walk(driveId: root.driveId, itemId: root.itemId, pathComponents: [], token: token, into: &results)
        return (root.name, results.map(toVideoItem))
    }

    private static func toVideoItem(_ video: RemoteVideo) -> VideoItem {
        VideoItem(
            url: video.downloadURL,
            title: (video.name as NSString).deletingPathExtension,
            channel: video.channel,
            modifiedDate: video.modifiedDate,
            fileExtension: (video.name as NSString).pathExtension.lowercased(),
            folderPath: video.folderPath,
            remoteID: video.remoteID,
            remoteKind: .oneDrive,
            knownFileSize: video.size
        )
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
        guard let encoded = encodeShareURL(shareURL) else { throw OneDriveShareError.invalidShareURL }
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
        /// `select=*`のレスポンスに含まれるファイルサイズ(2026-08-14復活、
        /// `VideoItem.knownFileSize`のドキュメント参照)。
        let size: Int64?
        enum CodingKeys: String, CodingKey {
            case id, name, lastModifiedDateTime, folder, size
            case downloadURL = "@content.downloadUrl"
        }
    }

    private static func makeRemoteVideo(_ item: DriveItemChild, pathComponents: [String]) -> RemoteVideo? {
        guard item.folder == nil else { return nil }
        // "._video.mp4"のようなAppleDoubleファイル(Finder経由のアップロード/同期時にmacOSが
        // 自動生成する、リソースフォーク等を格納した隠しファイル)は拡張子だけでは弾けないため
        // 名前で明示的に除外する。ローカルスキャン(`VideoScanner`)は`.skipsHiddenFiles`で
        // 同種のファイルを自動的に除外しているが、こちらはAPI経由の一覧のためその仕組みが無い。
        guard !item.name.hasPrefix(".") else { return nil }
        let ext = (item.name as NSString).pathExtension.lowercased()
        guard VideoScanner.videoExtensions.contains(ext) else { return nil }
        guard let downloadURLString = item.downloadURL, let downloadURL = URL(string: downloadURLString) else {
            return nil
        }
        let modifiedDate = item.lastModifiedDateTime.flatMap { ISO8601DateFormatter().date(from: $0) }
        return RemoteVideo(
            downloadURL: downloadURL, name: item.name,
            channel: pathComponents.first ?? VideoScanner.rootChannelLabel, folderPath: pathComponents,
            modifiedDate: modifiedDate, remoteID: item.id, size: item.size
        )
    }

    private static func walk(
        driveId: String, itemId: String, pathComponents: [String], token: String, into results: inout [RemoteVideo]
    ) async throws {
        var nextURLString: String? = childrenURL(driveId: driveId, itemId: itemId)
        while let current = nextURLString {
            var request = URLRequest(url: URL(string: current)!)
            request.httpMethod = "GET"
            request.cachePolicy = .reloadIgnoringLocalCacheData
            applyCommonHeaders(&request, token: token)

            let (data, response) = try await URLSession.shared.data(for: request)
            try checkOK(response, data: data)
            let page = try decode(ChildrenResponse.self, from: data)

            var folderCount = 0
            var videoCount = 0
            var skippedCount = 0
            for child in page.value {
                if child.folder != nil {
                    folderCount += 1
                    // フォルダに降りるたびに名前を積み上げる(`VideoScanner.folderPathComponents`
                    // と同じ規約 ― 以前は1階層目のサブフォルダ名だけを引き継ぎ、2階層目以降の
                    // 階層情報を失っていた)。
                    try await walk(driveId: driveId, itemId: child.id, pathComponents: pathComponents + [child.name], token: token, into: &results)
                } else if let video = makeRemoteVideo(child, pathComponents: pathComponents) {
                    videoCount += 1
                    results.append(video)
                } else {
                    skippedCount += 1
                }
            }
            // 「アニメ」リンクでサブフォルダが表示されなくなった不具合(2026-08-11報告)の調査用
            // ログ ― この非公式APIがフォルダ階層を期待通りに`folder`ファセット付きで返している
            // かをフォルダ単位で確認できるようにする(Console.appで
            // `subsystem:com.yoheisakata.mytube category:scan`を見る)。
            let pathLabel = pathComponents.isEmpty ? "(ルート)" : pathComponents.joined(separator: "/")
            Log.scan.debug("walk[\(pathLabel, privacy: .public)]: children=\(page.value.count) folders=\(folderCount) videos=\(videoCount) skipped=\(skippedCount) hasNextLink=\(page.nextLink != nil)")
            nextURLString = page.nextLink
        }
    }

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
        // このAPIは`Origin`/`Referer`が`onedrive.live.com`であることをサーバー側で検証している
        // (単なるブラウザCORSの制約ではなく、curlでも欠けるとaccessDeniedになることを確認済み)。
        request.setValue(origin, forHTTPHeaderField: "Origin")
        request.setValue("\(origin)/", forHTTPHeaderField: "Referer")
    }

    private static func checkOK(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw OneDriveShareError.apiError(envelope.error.message)
            }
            throw OneDriveShareError.apiError("HTTP \(status)")
        }
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            if let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: data) {
                throw OneDriveShareError.apiError(envelope.error.message)
            }
            throw OneDriveShareError.decodingFailed
        }
    }

    private struct APIErrorEnvelope: Decodable {
        struct ErrorBody: Decodable { let code: String; let message: String }
        let error: ErrorBody
    }
}

enum OneDriveShareError: LocalizedError {
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
