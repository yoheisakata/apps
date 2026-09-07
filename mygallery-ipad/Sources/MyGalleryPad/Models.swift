import Foundation

/// 写真か動画かの種別。`Hashable`は`HardcodedLink.kindFilter`との比較(`item.kind ==
/// kindFilter`)に必要。myslideshow-ipad(`Models.swift`)/mygallery(Mac版、
/// `OneDriveMediaClient.swift`)どちらにも同名の型があるが定義自体は同一のため、
/// このアプリでは単一の置き場所(ここ)にまとめてある。
enum MediaKind: Hashable {
    case photo
    case video
}

/// OneDrive共有フォルダから見つかった1件の写真・動画。mygallery(Mac版)の
/// `OneDriveMediaClient.swift`にある同名structを、`Core/OneDriveMediaClient.swift`から
/// このファイルへ切り出したもの(myslideshow-ipadの`Models.swift`と同じ置き場所の
/// 方針に合わせた)。mygallery版が持つ`size`/`thumbnailURL`(myslideshow-ipadの
/// `MediaItem`には無い、2026-09-07にmygalleryへ追加されたサーバー側生成サムネイル
/// 対応)をそのまま引き継いでいる ― グリッドのサムネイル読み込みを軽量化するのに必須。
struct MediaItem: Identifiable, Hashable {
    /// `remoteID`を識別子にする ― `downloadURL`(`@content.downloadUrl`)は署名付きURLで
    /// 再スキャンのたびに変わるため`id`には使えない。
    var id: String { remoteID }

    let remoteID: String
    let downloadURL: URL
    /// 拡張子込みのファイル名。
    let name: String
    /// 共有フォルダのルートから見た、このファイルを含む「月」フォルダまでのパス
    /// コンポーネント(例: ["2026", "09"])。mygallery(Mac版)と同じくDay階層は
    /// 畳み込んで持たない(下記`Core/OneDriveMediaClient.swift`参照)。
    let folderPath: [String]
    let modifiedDate: Date?
    let kind: MediaKind
    /// バイト単位のファイルサイズ。APIレスポンスに`size`が無い場合のみ0。
    let size: Int64
    /// OneDriveがサーバー側で生成済みの小さいサムネイル画像(`large`、数百px)のURL。
    /// あればグリッドのサムネイル読み込みはこちらを使う(`Core/ImageLoader.swift`) ―
    /// `downloadURL`(元ファイルそのもの)を毎回グリッド用に丸ごとダウンロードしなくて済む。
    let thumbnailURL: URL?

    /// ファイル名から推測した撮影日(`Core/FilenameDateParser.swift`)。見つからなければnil
    /// (`modifiedDate`へのフォールバックはしない ― OneDriveの更新日時は撮影日と限らないため)。
    var capturedDate: Date? { FilenameDateParser.date(from: name) }
}

/// アプリにハードコードされたOneDriveリンク1件(名前+URL+対象メディア種別+年フォルダの
/// 選択肢)。mygallery(Mac版)の`OneDriveLink`/myslideshow-ipadの`HardcodedLink`と同じ
/// 方針 ― 追加・削除UIは持たない。`ContentView.links`の配列を直接編集する。
struct HardcodedLink: Identifiable, Hashable {
    /// URLは変わらない前提のためこれ自体を安定した識別子として使う
    /// (`Settings.folderSelections`のキーにも同じ値を使う)。
    var id: String { url }
    let name: String
    let url: String
    /// 対象を絞る場合のメディア種別(nilなら写真・動画どちらも対象)。
    let kindFilter: MediaKind?
    /// 年別フォルダの選択肢(ハードコード)。フェーズ1(`OneDriveMediaClient
    /// .scanFolderStructureStream`)の探索範囲を絞るのに使う。
    let availableFolders: [String]
}
