import Foundation
import os

// MyGallery に OneDrive 共有リンクからの写真・動画ストリーミングを追加するための
// クライアント。`myslideshow/Sources/MySlideshow/Core/OneDriveMediaClient.swift` から
// ほぼそのまま移植したもの(認証フロー自体はさらに遡って mytube の
// `Core/OneDriveShareClient.swift` に由来する、非公開の内部API依存で予告なく仕様変更・
// 遮断される可能性がある点も同じ)。追加したのは `listTopLevelFolders(shareURL:)`
// (MyGallery だけの新機能である「リンク追加時に年フォルダ候補を自動取得する」ため)。
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
}

enum OneDriveMediaClient {
    /// 1階層目のサブフォルダを持たない(ルート直下に置かれた)写真・動画のフォルダラベル。
    static let rootFolderLabel = "(ルート)"

    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp",
    ]
    static let photoExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "gif", "bmp", "tiff", "tif", "webp",
    ]

    /// フォルダ構造を全階層たどる(深さ制限なし)。**呼び出し側はこれを直接呼ばず、
    /// `scanWithRetry(shareURL:)`経由で呼ぶこと** — 深いフォルダ階層(年/月/日等)を持つ
    /// 大きいライブラリでは、フォルダ数のぶんだけ逐次HTTPリクエストが発生し、途中の
    /// どこかで一時的な接続断を踏む確率が上がる。`walk`は例外を投げるとそこまでの結果ごと
    /// 丸ごと捨てて呼び出し元へ伝播するため、リトライ無しで一度でも失敗するとスキャン全体が
    /// 「何も出てこない」ように見える。
    static func scan(shareURL: String) async throws -> (sourceName: String, items: [MediaItem]) {
        let token = try await mintToken()
        let root = try await resolveShare(shareURL: shareURL, token: token)
        GalleryLog.oneDrive.notice("resolveShare: name=\(root.name, privacy: .public) isFolder=\(root.folder != nil) driveId=\(root.driveId, privacy: .public) itemId=\(root.itemId, privacy: .public)")

        if root.folder == nil {
            let item = try await fetchItem(driveId: root.driveId, itemId: root.itemId, token: token)
            guard let media = makeMediaItem(item, pathComponents: []) else { return (root.name, []) }
            return (root.name, [media])
        }

        let results = try await walk(driveId: root.driveId, itemId: root.itemId, pathComponents: [], token: token)
        GalleryLog.oneDrive.notice("scan完了: \(root.name, privacy: .public) 総件数=\(results.count)")
        return (root.name, results)
    }

    /// `scan(shareURL:)`を、一時的なネットワークエラー(`URLError.networkConnectionLost`/
    /// `.timedOut`)だけ自動で1回リトライするラッパー。
    static func scanWithRetry(shareURL: String) async throws -> (sourceName: String, items: [MediaItem]) {
        do {
            return try await scan(shareURL: shareURL)
        } catch {
            guard isTransientNetworkError(error) else { throw error }
            GalleryLog.oneDrive.notice("scanWithRetry: 一時的なネットワークエラーのため再試行します: \(String(describing: error), privacy: .public)")
            return try await scan(shareURL: shareURL)
        }
    }

    private static func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .networkConnectionLost || urlError.code == .timedOut
    }

    /// `scan(shareURL:)`と違い、**ルート直下のうち`topLevelFolders`に名前が一致する
    /// フォルダだけ**を深く辿る(一致しないフォルダは中に入らず丸ごとスキップする)。
    /// ルート直下に直接置かれたファイルは`topLevelFolders`によるフィルタの対象外として
    /// 常に含める(`rootFolderLabel`が`topLevelFolders`に含まれているときだけ)。
    static func scan(shareURL: String, onlyTopLevelFolders topLevelFolders: Set<String>) async throws -> (sourceName: String, items: [MediaItem]) {
        let token = try await mintToken()
        let root = try await resolveShare(shareURL: shareURL, token: token)
        GalleryLog.oneDrive.notice("resolveShare(絞込): name=\(root.name, privacy: .public) isFolder=\(root.folder != nil) 対象フォルダ=\(topLevelFolders.sorted().joined(separator: ","), privacy: .public)")

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

        // 選んだフォルダどうしも並列に(下記`walk`のコメント参照、`ConcurrencyLimiter`が
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
        GalleryLog.oneDrive.notice("scan完了(絞込): \(root.name, privacy: .public) 総件数=\(results.count)")
        return (root.name, results)
    }

    /// `scan(shareURL:onlyTopLevelFolders:)`の一時的ネットワークエラー自動リトライ版。
    static func scanWithRetry(shareURL: String, onlyTopLevelFolders topLevelFolders: Set<String>) async throws -> (sourceName: String, items: [MediaItem]) {
        do {
            return try await scan(shareURL: shareURL, onlyTopLevelFolders: topLevelFolders)
        } catch {
            guard isTransientNetworkError(error) else { throw error }
            GalleryLog.oneDrive.notice("scanWithRetry(絞込): 一時的なネットワークエラーのため再試行します: \(String(describing: error), privacy: .public)")
            return try await scan(shareURL: shareURL, onlyTopLevelFolders: topLevelFolders)
        }
    }

    /// ルート直下1ページだけを浅く列挙し、フォルダ名の一覧を返す(MyGalleryだけの新機能 —
    /// OneDriveリンク追加UIで、年フォルダ等の候補チェックボックスを自動取得するため。
    /// MySlideshowは`HardcodedLink.availableFolders`が決め打ち配列だったのでこの関数は無い)。
    /// ルート直下に直接置かれたファイルがあれば`rootFolderLabel`も候補に含める。
    static func listTopLevelFolders(shareURL: String) async throws -> [String] {
        let token = try await mintToken()
        let root = try await resolveShare(shareURL: shareURL, token: token)
        guard root.folder != nil else { return [] }

        var folders: [String] = []
        var hasRootLevelFile = false
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
                    folders.append(child.name)
                } else if makeMediaItem(child, pathComponents: []) != nil {
                    hasRootLevelFile = true
                }
            }
            nextURLString = page.nextLink
        }
        if hasRootLevelFile { folders.append(Self.rootFolderLabel) }
        return folders
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

    /// フォルダ1つぶんの中身を取得し、サブフォルダは`TaskGroup`で並列に`walk`する。
    /// `ConcurrencyLimiter`で同時実行数を絞っているため、フォルダ数が多くてもリクエストが
    /// 際限なく同時に飛ぶことはない(OneDrive側のレート制限を避けるため)。
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
            GalleryLog.oneDrive.notice("walk[\(pathLabel, privacy: .public)]: children=\(page.value.count) folders=\(subfolders.count) media=\(mediaCount) skipped=\(skippedCount) hasNextLink=\(page.nextLink != nil)")
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

    /// `walk`の同時HTTPリクエスト数を絞るためのactorベースのセマフォ。
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
