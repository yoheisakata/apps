import Foundation

/// リンクの提供元サイト。プレイリスト行のバッジ表示や解決ロジックの分岐に使う。
enum SiteKind: String, Codable, CaseIterable {
    case youtube
    case suno
    case musicCreator
    case musicGpt
    case oneDrive // OneDrive 共有フォルダ内の音声ファイル
    case direct   // .mp3 などへの直リンク
    case other    // og:audio が拾えた汎用サイト

    var label: String {
        switch self {
        case .youtube: return "YouTube"
        case .suno: return "Suno"
        case .musicCreator: return "MusicCreator"
        case .musicGpt: return "MusicGPT"
        case .oneDrive: return "OneDrive"
        case .direct: return "直リンク"
        case .other: return "Web"
        }
    }

    var symbolName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .suno, .musicCreator, .musicGpt: return "waveform"
        case .oneDrive: return "cloud.fill"
        case .direct: return "link"
        case .other: return "globe"
        }
    }
}

/// OneDrive 共有フォルダ内の1ファイルを指す情報。`audioURL`(tempauth 署名付き)は1時間程度で
/// 失効し `playlist.json` に保存したものは次回起動時にはたいてい使えないため、再生直前に
/// この3点から取り直す(`OneDriveShareClient.freshDownloadURL`)。
struct OneDriveRef: Codable, Equatable {
    var shareURL: String
    var driveId: String
    var itemId: String
    /// 共有フォルダのルート名(サイドバーのソース見出しに使う)。
    /// フォルダ表示より前のバージョンで追加した曲には入っていないため Optional
    /// ― 同じリンクを再スキャンすれば埋まる(`PlaylistStore.scanOneDriveShare`)。
    var sourceName: String?
}

/// プレイリストの1曲。
/// `audioURL` は再生に使う最終的な URL 文字列で、YouTube はダウンロード済みローカルファイルの
/// `file://` パス、それ以外は解決先サイトが返す直リンクの mp3 URL(ストリーミング再生)。
struct Track: Identifiable, Codable, Equatable {
    let id: UUID
    var sourceURL: String
    var title: String
    var site: SiteKind
    var artworkURL: String?
    var audioURL: String
    /// OneDrive 共有フォルダ由来の曲だけ非 nil(既存の `playlist.json` にはこのキーが無いが、
    /// Optional なので追加後も従来のデータをそのままデコードできる)。
    var oneDrive: OneDriveRef?
    /// 共有フォルダのルートから見た、この曲が入っているフォルダのパス(ルート直下なら `[]`)。
    /// サイドバーのフォルダツリー(`LibraryTree`)はこの値だけから組み立てる。
    var folderPath: [String]

    /// プレイリスト内での同一曲判定に使うキー。OneDrive は `audioURL` が再取得のたびに
    /// 変わるため、代わりに安定した driveId/itemId を使う。
    var dedupeKey: String {
        guard let ref = oneDrive else { return audioURL }
        return "onedrive:\(ref.driveId)/\(ref.itemId)"
    }

    /// 曲リストの2行目に出す補足(フォルダ階層、無ければサイト名)。
    var subtitle: String {
        folderPath.isEmpty ? site.label : folderPath.joined(separator: " / ")
    }

    init(
        id: UUID = UUID(), sourceURL: String, title: String, site: SiteKind,
        artworkURL: String? = nil, audioURL: String, oneDrive: OneDriveRef? = nil,
        folderPath: [String] = []
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = title
        self.site = site
        self.artworkURL = artworkURL
        self.audioURL = audioURL
        self.oneDrive = oneDrive
        self.folderPath = folderPath
    }

    private enum CodingKeys: String, CodingKey {
        case id, sourceURL, title, site, artworkURL, audioURL, oneDrive, folderPath
    }

    /// `folderPath` は後から足したフィールドのため、`decodeIfPresent` + 旧データの移行を
    /// 自前で書いている(合成される `init(from:)` は、プロパティに既定値があっても
    /// キーが無いとデコードに失敗するため)。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        sourceURL = try container.decode(String.self, forKey: .sourceURL)
        title = try container.decode(String.self, forKey: .title)
        site = try container.decode(SiteKind.self, forKey: .site)
        artworkURL = try container.decodeIfPresent(String.self, forKey: .artworkURL)
        audioURL = try container.decode(String.self, forKey: .audioURL)
        oneDrive = try container.decodeIfPresent(OneDriveRef.self, forKey: .oneDrive)
        if let stored = try container.decodeIfPresent([String].self, forKey: .folderPath) {
            folderPath = stored
        } else if oneDrive != nil, title.contains("/") {
            // フォルダツリー導入前は「フォルダ名/曲名」をそのままタイトルにしていた。
            // 保存済みのその形式を分解して、階層とタイトルに移し替える。
            var components = title.components(separatedBy: "/")
            title = components.removeLast()
            folderPath = components
        } else {
            folderPath = []
        }
    }
}
