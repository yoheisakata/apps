import Foundation

/// OneDrive(個人)の「リンクを知っている全員が閲覧可能」共有フォルダ/ファイルを、
/// ブラウザにサインインせずスキャンして音声ファイル一覧を得るクライアント。
/// mytube の `Core/OneDriveShareClient.swift` の移植版(あちらは動画、こちらは音声を拾う)。
///
/// ブラウザの開発者ツールでの通信解析(mytube 側、2026-08-04)で判明した3ステップ:
/// 1. `POST https://api-badgerp.svc.ms/v1.0/token` に固定の appId(公開値、秘密情報ではない
///    ― OneDrive Web クライアント自身の JS バンドルにハードコードされている)を渡すと、
///    完全に匿名の短命トークン(JWT、"Badger" スキーム)が発行される。
/// 2. そのトークンを `Authorization: Badger <token>` として、共有 URL を Microsoft 独自の
///    `u!<base64url>` 形式にエンコードした `/shares/{encoded}/driveitem` へ `Prefer: autoredeem`
///    付きで POST すると、その共有アイテムの `driveId`/`itemId` が返る。同時にこの呼び出しが
///    「このトークンをこの共有に対して読み取り許可する」という副作用(redeem)を持つため、
///    以降の API 呼び出しは必ず同じトークンを使い回す必要がある(別トークンだと accessDenied)。
/// 3. `/drives/{driveId}/items/{itemId}/children` を GET するとフォルダの中身一覧が
///    `@content.downloadUrl`(tempauth 署名付き、追加認証なしで直接ストリーミングできる URL、
///    有効期限は実測1時間程度)付きで返る。
///
/// いずれも Microsoft が第三者向けに公開している Graph API ではなく OneDrive Web クライアント
/// 自身が使う内部 API のため、**予告なく仕様変更・遮断される可能性がある**(公式サポート対象外)。
///
/// **`@content.downloadUrl` の有効期限が短い**のがプレイリスト用途では重要 ― MyMusic は
/// `playlist.json` に URL を永続化するため、保存した URL は次回起動時にはたいてい失効している。
/// そのため `Track.oneDrive`(共有 URL + driveId + itemId)を持たせておき、再生直前に
/// `freshDownloadURL` で取り直す(`PlaylistStore.refreshedTrack`)。
enum OneDriveShareClient {
    /// 共有フォルダから見つかった音声ファイル1件。
    struct AudioItem {
        let name: String
        let itemId: String
        let driveId: String
        /// 共有フォルダのルートから見た、このファイルを含むフォルダのパスコンポーネント
        /// (ルート直下なら `[]`)。表示タイトルの前置きに使う。
        let folderPath: [String]
        let downloadURL: String

        /// プレイリストに出す表示名。サブフォルダにある曲は「フォルダ/曲名」の形にして、
        /// 同名ファイルやアーティスト別フォルダを見分けられるようにする。
        var displayTitle: String {
            let base = (name as NSString).deletingPathExtension
            return folderPath.isEmpty ? base : (folderPath.joined(separator: "/") + "/" + base)
        }
    }

    /// AVPlayer で再生できる音声ファイルの拡張子(`LinkResolver` の直リンク判定より広め ―
    /// フォルダ内の全ファイルから拾う都合上、画像やテキストを弾く側の判定として使う)。
    static let audioExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "alac", "m4b", "caf"]

    /// 貼り付けられた URL が OneDrive の共有リンクか。
    static func isShareLink(_ urlString: String) -> Bool {
        guard let host = URL(string: urlString)?.host?.lowercased() else { return false }
        return host.contains("1drv.ms") || host.contains("onedrive.live.com")
    }

    // MARK: - スキャン

    /// 共有 URL(フォルダまたはファイル単体)を再帰的にスキャンし、音声ファイルだけを返す。
    /// `sourceName` は共有元フォルダ/ファイルの名前(UI のメッセージ表示用)。
    static func scanAudio(shareURL: String) async throws -> (sourceName: String, items: [AudioItem]) {
        let session = try await Session.shared.entry(for: shareURL)

        if !session.isFolder {
            let item = try await fetchItem(driveId: session.driveId, itemId: session.itemId, token: session.token)
            guard let audio = makeAudioItem(item, driveId: session.driveId, folderPath: []) else {
                return (session.name, [])
            }
            return (session.name, [audio])
        }

        var results: [AudioItem] = []
        try await walk(
            driveId: session.driveId, itemId: session.itemId, folderPath: [],
            token: session.token, into: &results
        )
        return (session.name, results)
    }

    /// 保存済みトラックの署名付き URL を取り直す。トークンが失効していた場合は1度だけ
    /// 発行・redeem からやり直す(`Session` のキャッシュを捨てて再取得する)。
    static func freshDownloadURL(shareURL: String, driveId: String, itemId: String) async throws -> String {
        do {
            return try await downloadURL(shareURL: shareURL, driveId: driveId, itemId: itemId)
        } catch {
            await Session.shared.invalidate(shareURL)
            return try await downloadURL(shareURL: shareURL, driveId: driveId, itemId: itemId)
        }
    }

    private static func downloadURL(shareURL: String, driveId: String, itemId: String) async throws -> String {
        let session = try await Session.shared.entry(for: shareURL)
        let item = try await fetchItem(driveId: driveId, itemId: itemId, token: session.token)
        guard let url = item.downloadURL else { throw OneDriveShareError.apiError("再生用 URL が取得できませんでした") }
        return url
    }

    // MARK: - トークン発行 + 共有リンクの解決(セッション単位でキャッシュ)

    /// 発行したトークンと解決済みの共有ルートを共有 URL ごとに保持する。
    /// トークン自体が短命なため、`maxAge` を過ぎたら作り直す(再生のたびに3リクエスト
    /// 投げないための最適化 ― キャッシュが生きていれば `fetchItem` の1回だけで済む)。
    private actor Session {
        static let shared = Session()

        struct Entry {
            let token: String
            let driveId: String
            let itemId: String
            let name: String
            let isFolder: Bool
            let mintedAt: Date
        }

        private static let maxAge: TimeInterval = 20 * 60
        private var entries: [String: Entry] = [:]

        func entry(for shareURL: String) async throws -> Entry {
            if let cached = entries[shareURL], Date().timeIntervalSince(cached.mintedAt) < Self.maxAge {
                return cached
            }
            let token = try await mintToken()
            let root = try await resolveShare(shareURL: shareURL, token: token)
            let entry = Entry(
                token: token, driveId: root.driveId, itemId: root.itemId,
                name: root.name, isFolder: root.isFolder, mintedAt: Date()
            )
            entries[shareURL] = entry
            return entry
        }

        func invalidate(_ shareURL: String) {
            entries[shareURL] = nil
        }
    }

    private static let appId = "00000000-0000-0000-0000-0000481710a4"
    private static let origin = "https://onedrive.live.com"

    private struct TokenResponse: Decodable { let token: String }

    private static func mintToken() async throws -> String {
        var request = URLRequest(url: URL(string: "https://api-badgerp.svc.ms/v1.0/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json;odata=verbose", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("1141147648", forHTTPHeaderField: "AppId")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["appId": appId])

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkOK(response, data: data)
        return try decode(TokenResponse.self, from: data).token
    }

    private struct ResolvedRoot {
        let driveId: String
        let itemId: String
        let name: String
        let isFolder: Bool
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
        applyCommonHeaders(&request, token: token)
        request.setValue("autoredeem", forHTTPHeaderField: "Prefer")
        request.setValue("text/plain;charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data()

        let (data, response) = try await URLSession.shared.data(for: request)
        try checkOK(response, data: data)
        let item = try decode(DriveItemResolved.self, from: data)
        return ResolvedRoot(
            driveId: item.parentReference.driveId, itemId: item.id,
            name: item.name, isFolder: item.folder != nil
        )
    }

    /// 共有 URL 文字列を Microsoft 独自の `u!<base64url、パディング無し>` 形式にエンコードする。
    private static func encodeShareURL(_ shareURL: String) -> String? {
        guard let data = shareURL.data(using: .utf8) else { return nil }
        let base64url = data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        return "u!\(base64url)"
    }

    // MARK: - フォルダの中身一覧(再帰)/ 単体アイテム取得

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
        let folder: FolderFacet?
        let downloadURL: String?
        enum CodingKeys: String, CodingKey {
            case id, name, folder
            case downloadURL = "@content.downloadUrl"
        }
    }

    private static func makeAudioItem(_ item: DriveItemChild, driveId: String, folderPath: [String]) -> AudioItem? {
        guard item.folder == nil else { return nil }
        // "._song.mp3" のような AppleDouble ファイル(Finder 経由のアップロード時に macOS が
        // 自動生成する隠しファイル)は拡張子だけでは弾けないため名前で除外する。
        guard !item.name.hasPrefix(".") else { return nil }
        guard audioExtensions.contains((item.name as NSString).pathExtension.lowercased()) else { return nil }
        guard let downloadURL = item.downloadURL else { return nil }
        return AudioItem(
            name: item.name, itemId: item.id, driveId: driveId,
            folderPath: folderPath, downloadURL: downloadURL
        )
    }

    private static func walk(
        driveId: String, itemId: String, folderPath: [String], token: String, into results: inout [AudioItem]
    ) async throws {
        var nextURLString: String? = childrenURL(driveId: driveId, itemId: itemId)
        while let current = nextURLString {
            var request = URLRequest(url: URL(string: current)!)
            request.httpMethod = "GET"
            applyCommonHeaders(&request, token: token)

            let (data, response) = try await URLSession.shared.data(for: request)
            try checkOK(response, data: data)
            let page = try decode(ChildrenResponse.self, from: data)

            for child in page.value {
                if child.folder != nil {
                    try await walk(
                        driveId: driveId, itemId: child.id, folderPath: folderPath + [child.name],
                        token: token, into: &results
                    )
                } else if let audio = makeAudioItem(child, driveId: driveId, folderPath: folderPath) {
                    results.append(audio)
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
        // この API は `Origin`/`Referer` が `onedrive.live.com` であることをサーバー側で検証している
        // (単なるブラウザ CORS の制約ではなく、curl でも欠けると accessDenied になる)。
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
            return "共有リンクの形式が正しくありません。"
        case .apiError(let message):
            return "OneDrive から読み込めませんでした(\(message))。リンクが無効か、共有が解除されている可能性があります。"
        case .decodingFailed:
            return "OneDrive の応答を解析できませんでした(API の仕様が変わった可能性があります)。"
        }
    }
}
