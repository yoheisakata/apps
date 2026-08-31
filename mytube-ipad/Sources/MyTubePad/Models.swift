import Foundation

/// OneDrive共有フォルダから見つかった1本の動画。
/// mytube(Mac版)の`VideoItem`から、OneDrive専用に必要なフィールドだけを残した縮小版
/// (ローカルフォルダ・YouTubeは扱わないため`remoteKind`等は不要)。
struct VideoItem: Identifiable, Hashable, Codable {
    /// OneDriveのアイテムID。再スキャンしても変わらない安定したキー。
    var id: String { remoteID }

    let title: String
    /// 共有フォルダ直下のサブフォルダ名(無ければ`OneDriveShareClient.rootChannelLabel`)。
    let channel: String
    let folderPath: [String]
    let modifiedDate: Date?
    /// tempauth署名付きの直リンク。有効期限は実測1時間程度(mytube Mac版と同じ制限)。
    let downloadURL: URL
    let remoteID: String
    let size: Int64?
    /// 拡張子(ドット無し、小文字)。`DownloadStore`がローカル保存ファイル名
    /// (`<remoteID>.<fileExtension>`)を組み立てるのに使う ― `downloadURL`(tempauth署名付き
    /// URL)はパス自体が`_layouts/15/download.aspx`のような固定文字列で拡張子を含まないため
    /// (mytube Mac版の`VideoItem.fileExtension`と同じ理由)、`item.name`から別途保持する。
    let fileExtension: String
}

/// ダウンロード済み動画のメタデータ(2026-08-27追加、「ローカルに保存した動画の一覧も
/// ほしい」という要望への対応)。`DownloadStore`がダウンロード開始時に`Settings`へ永続化
/// する ― `VideoItem`自体は永続化せず都度のOneDriveスキャンで作られる実行時の値のため、
/// アプリを再起動しても(元の共有リンクを再スキャンしなくても)「ローカル保存済み」一覧に
/// タイトル・チャンネル等を表示できるよう、必要なフィールドだけ複製して持つ。
struct DownloadedVideoInfo: Codable {
    let remoteID: String
    let title: String
    let channel: String
    let fileExtension: String
    let size: Int64?
    let modifiedDate: Date?
}

/// 登録済みのOneDrive共有リンク(名前+URL)。UserDefaultsにJSONで永続化する。
struct SharedLinkBookmark: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: String
}

/// 現在開いている1つのOneDrive共有リンクの実行時状態(スキャン結果・読み込み中フラグ等)。
struct RemoteSource {
    var name: String
    var shareURL: String
    var videos: [VideoItem] = []
    var isLoading = false
    var errorMessage: String?
}

/// `SourceGridView`の表示形式(2026-08-27追加、「ハイブリッドビューモードでタグフィルタ
/// したい」という要望への対応 ― mytube(Mac版)の`HomeViewMode`(grid/hybrid)に相当するが、
/// iPad版はFinder風の`Table`が使えないため、リスト表示は`List`ベースの単純な行(小さい
/// サムネイル+タイトル+タグ+サイズ)にした)。`Settings.homeViewMode`に永続化する。
enum HomeViewMode: String, CaseIterable, Identifiable {
    case grid
    case list

    var id: String { rawValue }
    var systemImage: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        }
    }
}
