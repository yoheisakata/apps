import Foundation

/// 写真か動画かの種別。`MediaItem.kind`でスライドショー本体(`Views/SlideshowView.swift`)が
/// 表示方法(静止画タイマー送り/動画は最後まで再生してから送り)を分岐する。
/// `Hashable`は`HardcodedLink.kindFilter`との比較(`item.kind == kindFilter`)に必要。
enum MediaKind: Hashable {
    case photo
    case video
}

/// OneDrive共有フォルダから見つかった1件の写真・動画。ローカルスキャンは持たない(このアプリは
/// OneDrive共有リンク専用 ― `Core/OneDriveMediaClient.swift`参照)ため、mytubeの`VideoItem`と
/// 違い`remoteID`は必須(常にOneDriveのアイテムID)。
struct MediaItem: Identifiable, Hashable {
    /// `remoteID`を識別子にする ― `downloadURL`(`@content.downloadUrl`)は署名付きURLで
    /// 再スキャンのたびに変わるため`id`には使えない。
    var id: String { remoteID }

    let remoteID: String
    let downloadURL: URL
    /// 拡張子込みのファイル名。
    let name: String
    /// 共有フォルダのルートから見た、このファイルを含むフォルダのパスコンポーネント。
    let folderPath: [String]
    let modifiedDate: Date?
    let kind: MediaKind

    /// ファイル名から推測した撮影日(`Core/FilenameDateParser.swift`)。見つからなければnil
    /// (`modifiedDate`へのフォールバックはしない ― OneDriveの更新日時は撮影日と限らないため、
    /// 分からないときは日付自体を表示しない方が誤解を招かない)。
    var capturedDate: Date? { FilenameDateParser.date(from: name) }
}

/// スライドショーの表示モード(2026-08-30、「スライドショーには3つのモードがほしい」
/// という要望への対応)。`Views/HomeView.swift`のセグメントピッカーで選び、
/// `Core/Settings.swift`に永続化する。**`.pip`だけは`ContentView`が`SlideshowView`を
/// メインウィンドウへ表示する通常経路を使わず、`Core/PIPWindowController.swift`が
/// 別の小さな常時最前面パネルとしてホストする**(メインウィンドウはホーム画面を
/// 表示したまま裏に残る)ため、`.windowed`/`.fullScreen`とは分岐の入り口が異なる ―
/// 詳しくは`ContentView.start()`と`PIPWindowController`を参照。
enum PlaybackMode: String, CaseIterable, Identifiable, Codable {
    /// 通常のウィンドウ内で再生(リサイズ可能な大きめウィンドウに広げる)。
    case windowed
    /// macOSネイティブのフルスクリーン(既定 ― 従来からの挙動)。
    case fullScreen
    /// 自前の小さな常時最前面(他アプリの上にも出る)浮動パネルで再生。
    case pip

    var id: String { rawValue }

    var label: String {
        switch self {
        case .windowed: return "ウィンドウ内"
        case .fullScreen: return "全画面"
        case .pip: return "PIP"
        }
    }
}

/// アプリにハードコードされたOneDriveリンク1件(名前+URL+対象メディア種別+年フォルダの
/// 選択肢)。追加・削除UIは持たない(2026-08-29、「リンクはめったにかわらないので、
/// ハードコードのままでいい」という要望への対応) ― 増やす・変える場合は
/// `ContentView.links`の配列を直接編集する。
///
/// **`availableFolders`(年別チェックボックスの選択肢)もハードコードで、OneDriveを
/// スキャンして動的に取得することはしない**(2026-08-29、「写真は2020から2026まで
/// チェックボックスを決め打ちにして。動画は2020から2021に。リンクからはとらない」
/// という要望への対応 ― 以前は起動時に両リンクをスキャンして実際に存在するフォルダ名を
/// 動的に拾っていたが、年/月/日と深くネストしたライブラリでは起動時のスキャン自体が
/// 重く、しかも「まず年の一覧が知りたいだけなのに実データまで取りに行ってしまう」という
/// ミスマッチがあった。年の範囲は今後もめったに変わらないため、チェックボックスの選択肢
/// 自体をハードコードし、実データの取得(OneDriveスキャン)は「スライドショー開始」を
/// 押した瞬間まで遅延させることにした ― `ContentView.start()`参照)。
struct HardcodedLink: Identifiable, Hashable {
    /// URLは変わらない前提のためこれ自体を安定した識別子として使う
    /// (`Settings.folderSelections`のキーにも同じ値を使う)。
    var id: String { url }
    let name: String
    let url: String
    /// 対象を絞る場合のメディア種別(nilなら写真・動画どちらも対象)。例:
    /// 「動画」リンクは動画だけ、「写真」リンクは写真だけを対象にする。
    let kindFilter: MediaKind?
    /// 年別チェックボックスの選択肢(ハードコード)。
    let availableFolders: [String]
}
