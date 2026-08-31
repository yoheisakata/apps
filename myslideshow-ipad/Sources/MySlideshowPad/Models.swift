import Foundation

/// 写真か動画かの種別。`MediaItem.kind`でスライドショー本体(`Views/SlideshowView.swift`)が
/// 表示方法(静止画タイマー送り/動画は最後まで再生してから送り)を分岐する。
/// `Hashable`は`HardcodedLink.kindFilter`との比較(`item.kind == kindFilter`)に必要。
enum MediaKind: Hashable {
    case photo
    case video
}

/// OneDrive共有フォルダから見つかった1件の写真・動画。myslideshow(Mac版)の`MediaItem`から
/// そのまま移植 ― `PlaybackMode`(ウィンドウ内/全画面/PIP)はmacOSのウィンドウ管理専用の
/// 概念でiPadには対応物が無いため移植していない(下記`CLAUDE.md`参照)。
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

/// アプリにハードコードされたOneDriveリンク1件(名前+URL+対象メディア種別+年フォルダの
/// 選択肢)。myslideshow(Mac版)と同じく追加・削除UIは持たない ― `ContentView.links`の配列を
/// 直接編集する。
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
