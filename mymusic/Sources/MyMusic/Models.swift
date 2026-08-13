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

    /// プレイリスト内での同一曲判定に使うキー。OneDrive は `audioURL` が再取得のたびに
    /// 変わるため、代わりに安定した driveId/itemId を使う。
    var dedupeKey: String {
        guard let ref = oneDrive else { return audioURL }
        return "onedrive:\(ref.driveId)/\(ref.itemId)"
    }

    init(
        id: UUID = UUID(), sourceURL: String, title: String, site: SiteKind,
        artworkURL: String? = nil, audioURL: String, oneDrive: OneDriveRef? = nil
    ) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = title
        self.site = site
        self.artworkURL = artworkURL
        self.audioURL = audioURL
        self.oneDrive = oneDrive
    }
}
