import Foundation

/// リンクの提供元サイト。プレイリスト行のバッジ表示や解決ロジックの分岐に使う。
enum SiteKind: String, Codable, CaseIterable {
    case youtube
    case suno
    case musicCreator
    case musicGpt
    case direct   // .mp3 などへの直リンク
    case other    // og:audio が拾えた汎用サイト

    var label: String {
        switch self {
        case .youtube: return "YouTube"
        case .suno: return "Suno"
        case .musicCreator: return "MusicCreator"
        case .musicGpt: return "MusicGPT"
        case .direct: return "直リンク"
        case .other: return "Web"
        }
    }

    var symbolName: String {
        switch self {
        case .youtube: return "play.rectangle.fill"
        case .suno, .musicCreator, .musicGpt: return "waveform"
        case .direct: return "link"
        case .other: return "globe"
        }
    }
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

    init(id: UUID = UUID(), sourceURL: String, title: String, site: SiteKind, artworkURL: String? = nil, audioURL: String) {
        self.id = id
        self.sourceURL = sourceURL
        self.title = title
        self.site = site
        self.artworkURL = artworkURL
        self.audioURL = audioURL
    }
}
