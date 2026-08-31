import Foundation

/// OneDrive(個人)の「リンクを知っている全員が閲覧可能」共有フォルダ/ファイルを、
/// サインインせずスキャンして`VideoItem`一覧を得るクライアント。
///
/// mytube(Mac版)の`Core/OneDriveShareClient.swift`から、OneDrive専用の3ステップ
/// (匿名トークン発行→共有リンク解決→children一覧取得)をそのまま移植したもの ―
/// 中身はFoundation(`URLSession`/`JSONDecoder`)のみに依存するため、AppKit/macOS固有の
/// ものは使っておらず無変更でiOS/iPadOSでも動く。**この移植が成立する理由が今回の
/// 肝**: このAPIはリクエストの`Origin`/`Referer`ヘッダーが`https://onedrive.live.com`で
/// あることをサーバー側で検証しており(単なるブラウザCORSの制約ではなくcurlでも欠けると
/// accessDeniedになることをMac版で確認済み)、`URLSession`(ネイティブアプリ)はこの2つを
/// 自由に設定できるが、ブラウザのJS `fetch()`はこの2つを`forbidden header`としてスクリプトから
/// 設定できない仕様のため、ブラウザ上で動く静的PWAでは同じ手順を直接再現できない ―
/// だからこそこの機能が欲しい場合はネイティブアプリとして作る必要があった。
///
/// 手順の詳細・既知の制限(非公式API・`@content.downloadUrl`の期限が短い等)は
/// Mac版のコメント(`mytube/Sources/MyTube/Core/OneDriveShareClient.swift`)を参照。
enum OneDriveShareClient {
    static let videoExtensions: Set<String> = [
        "mp4", "mov", "m4v", "avi", "mkv", "webm", "wmv", "flv", "mpg", "mpeg", "3gp",
    ]
    static let rootChannelLabel = "(ルート)"

    struct RemoteVideo {
        let downloadURL: URL
        let name: String
        let channel: String
        let folderPath: [String]
        let modifiedDate: Date?
        let remoteID: String
        let size: Int64?
    }

    static func scan(shareURL: String) async throws -> (sourceName: String, videos: [VideoItem]) {
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
            title: (video.name as NSString).deletingPathExtension,
            channel: video.channel,
            folderPath: video.folderPath,
            modifiedDate: video.modifiedDate,
            downloadURL: video.downloadURL,
            remoteID: video.remoteID,
            size: video.size,
            fileExtension: (video.name as NSString).pathExtension.lowercased()
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
        let size: Int64?
        enum CodingKeys: String, CodingKey {
            case id, name, lastModifiedDateTime, folder, size
            case downloadURL = "@content.downloadUrl"
        }
    }

    private static func makeRemoteVideo(_ item: DriveItemChild, pathComponents: [String]) -> RemoteVideo? {
        guard item.folder == nil else { return nil }
        // "._video.mp4"のようなAppleDoubleファイルを名前で除外する(Mac版と同じ理由)。
        guard !item.name.hasPrefix(".") else { return nil }
        let ext = (item.name as NSString).pathExtension.lowercased()
        guard videoExtensions.contains(ext) else { return nil }
        guard let downloadURLString = item.downloadURL, let downloadURL = URL(string: downloadURLString) else {
            return nil
        }
        let modifiedDate = item.lastModifiedDateTime.flatMap { ISO8601DateFormatter().date(from: $0) }
        return RemoteVideo(
            downloadURL: downloadURL, name: item.name,
            channel: pathComponents.first ?? rootChannelLabel, folderPath: pathComponents,
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

            for child in page.value {
                if child.folder != nil {
                    try await walk(driveId: driveId, itemId: child.id, pathComponents: pathComponents + [child.name], token: token, into: &results)
                } else if let video = makeRemoteVideo(child, pathComponents: pathComponents) {
                    results.append(video)
                }
            }
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
        // ネイティブアプリだからこそ設定できるヘッダー(ファイル冒頭のコメント参照)。
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
