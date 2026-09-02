# CLAUDE.md — mytube-ipad

mytube(Mac版)の「iPadでも近いものを使いたい」という要望(2026-08-26)から生まれた、
**OneDrive共有リンクの再生専用**の縮小版アプリ。ローカルフォルダ・YouTubeプレイリストは
意図的に対象外(この2つはiPadの制約が理由でそもそも成立しない/成立させる価値が薄いため、
下記「なぜこの形になったか」参照)。

## リポジトリ内で唯一のXcodeプロジェクト製アプリ

他のSwiftUIネイティブアプリ(mynetworth/myorganizer/mydownloader/mytube/mygames/
mypass)はすべてSwift Package Manager(`Package.swift` + `swift build`/`build_app.sh`)だが、
**このアプリだけはXcodeプロジェクト**(`.xcodeproj`)が必要 ― iOS/iPadOS向けの`.app`
(実機にインストール可能な形)はSPMのコマンドラインビルドだけでは生成できず、Xcodeの
署名・プロビジョニングの仕組みが要るため。

- **`.xcodeproj`はコミットしない**(`.gitignore`済み)。[xcodegen](https://github.com/yonaskolb/XcodeGen)
  (Homebrewで`brew install xcodegen`)が`project.yml`から毎回生成する ― pbxprojの
  マージコンフリクトを避けるための標準的なプラクティス。`project.yml`を変更したら
  `xcodegen generate`を再実行すること。
- ビルド/実機インストールの手順は`README.md`参照。**GUIアプリを起動しないこと」という
  ルート`CLAUDE.md`の制約はXcodeでの実機ビルド・実行そのものには適用されない**(ユーザー
  自身がXcodeで実行する前提の運用のため)が、このリポジトリからは`swift build`相当の
  コンパイル確認までに留める。コンパイル確認は`swift build`が使えない(SPMではないため)
  ― 代わりに以下でSwiftのタイプチェックだけ行える(実機/シミュレータのビルドには
  Xcodeの「iOS Platform」コンポーネントのダウンロードが必要な場合があるため、それが
  無い環境でもこちらで型エラーは検出できる):
  ```bash
  xcrun -sdk iphoneos swiftc -target arm64-apple-ios17.0 -typecheck \
    Sources/MyTubePad/*.swift Sources/MyTubePad/Views/*.swift
  ```

## なぜOneDriveだけなのか(mytube Mac版との比較で検討した経緯)

- **YouTube**: mytube Mac版は`yt-dlp`/`ffmpeg`をサブプロセスとして呼び出すが、iOS/iPadOSの
  アプリサンドボックスは任意プロセスの実行を許可しない。Macが代わりにダウンロードした
  ファイルをiPadへ渡す経路(ローカルサーバー等)が必要になり、複雑さに見合わないため
  スコープ外にした。
- **ローカルフォルダ**: iOSは自由なファイルシステムアクセスができず、`UIDocumentPicker`+
  security-scoped bookmarkでの都度選択が必要になり、Mac版のような「フォルダを開いたままに
  しておく」体験からは離れる。今回は要望が「OneDriveだけでOK」だったため見送った。
- **OneDrive**: `Core/OneDriveShareClient.swift`(mytube Mac版から移植、下記)は
  `URLSession`(Foundationのみ)で完結しており、iOS上でも無変更で動く。これが
  「OneDriveだけなら作れる」と判断した最大の理由。

## アーキテクチャ

mytube(Mac版)のOneDrive関連コードを、必要な範囲だけ移植・簡略化したもの。

- **`Sources/MyTubePad/OneDriveShareClient.swift`** — `mytube/Sources/MyTube/Core/
  OneDriveShareClient.swift`からほぼそのまま移植。匿名トークン発行→共有リンク解決→
  children一覧取得、の3ステップは完全に同じ。`RemoteKind`(OneDrive/YouTubeの区別)は
  削除し、`videoExtensions`/`rootChannelLabel`(元は`VideoScanner.swift`にあった定数)は
  このファイル内にインライン化した(`VideoScanner.swift`自体はローカルスキャン専用のため
  移植していない)。
  **このAPIがネイティブアプリでしか使えない理由**(ファイル冒頭のコメントにも記載):
  `Origin`/`Referer`ヘッダーが`https://onedrive.live.com`であることをサーバー側で検証して
  いるが、ブラウザのJS `fetch()`はこの2つを`forbidden header`としてスクリプトから設定
  できない仕様のため、静的Webページ(PWA)からは同じ手順を再現できない。だからこそ
  「iPadでOneDriveだけ再生したい」にはネイティブアプリが要る、という結論に至った経緯が
  ある(Mac版と同じ理屈が、ブラウザではなくネイティブアプリだからこそ通用する)。
- **`Sources/MyTubePad/Models.swift`** — `VideoItem`(タイトル・チャンネル・
  フォルダパス・更新日時・`downloadURL`・OneDriveアイテムID・サイズのみを持つ縮小版)、
  `SharedLinkBookmark`(名前+URL、Mac版と同じ形)、`RemoteSource`(実行時状態)。
  Mac版と異なり**「開いているリンク」と「登録済みブックマーク」を分けていない** ―
  登録した共有リンクは常に`Settings.sharedLinkBookmarks`に永続化されたままで、選択時に
  都度スキャンする(Mac版の`Settings.openRemoteLinks`に相当するものは無い)。個人利用の
  MVPとして単純さを優先した設計判断。
- **`Sources/MyTubePad/Settings.swift`** — `UserDefaults`キーは`mytubepad.`プレフィックス
  (Mac版の`mytube.`と衝突しないよう、別アプリなので当然だが明示)。`sharedLinkBookmarks`
  のみ(Mac版にある`openLocalFolders`/`homeViewMode`等はすべて対象外機能のため無い)。
- **`Sources/MyTubePad/ContentView.swift`** — `NavigationSplitView`(サイドバー=登録済み
  リンク一覧、detail=選択中リンクのグリッド)。Mac版のようなフォルダツリー・複数ソース
  同時オープンは無く、**1つのリンクを選ぶと即座にそのリンクだけをスキャンする**単純な
  マスター・ディテール構成。`sources: [String: RemoteSource]`(キーは
  `SharedLinkBookmark.id.uuidString`)がスキャン結果のキャッシュを兼ねる ― 同じリンクを
  選び直してもスキャン済みなら再スキャンしない(手動更新は下記のプルダウン)。
- **`Sources/MyTubePad/Views/SourceGridView.swift`** — サムネイル無しの`LazyVGrid`。
  Mac版の`ThumbnailStore`(`AVAssetImageGenerator`でのフレーム抽出、ディスクキャッシュ)は
  移植していない ― リモートURLへの都度アクセスが必要になり、MVPの複雑さに見合わないため
  意図的に省略した(タイトル・フォルダ名・ファイルサイズのみ表示)。`.refreshable`
  (プルダウン)で`OneDriveShareClient.scan`を呼び直せる ― tempauth URLの期限切れ
  (実測1時間程度)対策はこれで十分とした(Mac版のような自動リトライ・エラー種別ごとの
  ハンドリングは持たない)。
- **`Sources/MyTubePad/Views/PlayerView.swift`** — `AVKit.VideoPlayer`(iOS版、macOS版と
  違い`AVPlayerView`のAppKitラップは不要 ― iOSの`VideoPlayer`はフルスクリーン切り替え等
  すでに標準機能として持っている)。`video.downloadURL`を直接`AVPlayer`に渡すだけで、
  ダウンロード・ローカルキャッシュは行わない(Mac版の`DownloadStore`に相当するものは無い
  ― ストリーミング再生のみ)。再生失敗時の詳細なエラーハンドリング(Mac版の
  `PlayerEngine`の4経路の失敗検知)も持たない ― 失敗したら閉じてグリッドを再読み込みする
  という単純な運用を想定している。
  **自動再生(2026-08-27追加、「次の動画に自動で進むようにしてほしい」という要望への
  対応)**: `queue: [VideoItem]`(タップした時点で`SourceGridView`が表示していた
  `filteredVideos`、フォルダタブ・タグフィルター適用後のもの ― `ContentView`の
  `playingQueue`を経由してそのまま渡る)を受け取り、`video`が`queue`内で何番目かを
  `currentIndex`として開始する。`.AVPlayerItemDidPlayToEndTime`通知を監視し、最後まで
  再生し終えるたびに`currentIndex`を進めて`AVPlayerItem`を差し替える ― `AVPlayer`
  インスタンス自体(`@State private var player`)は使い回し、`replaceCurrentItem`で
  次の動画のURLに繋ぎ直すだけ(mytube Mac版の`PlayerEngine`と同じ「1つのplayerを
  使い回す」設計)。`queue`の最後まで到達したら`onClose()`を呼んで画面を閉じる。
  **オン/オフを切り替えるトグルは持たない**(Mac版の「自動再生」トグルに相当するものは
  無い ― MVPとしての単純さを優先し、常時オンにした)。

- **`Sources/MyTubePad/ConanEpisodeTags.swift`** + **`ConanMainStoryReference.swift`**
  (2026-08-27追加、「ネイティブ版のように、コナンのタグ機能を追加してほしい」という
  要望への対応) — mytube(Mac版)の`Core/ConanEpisodeTags.swift`(タイトルのキーワード
  自動判定)・`Core/ConanMainStoryReference.swift`(話数別の参照データ、`tagsByEpisode`
  テーブルは丸ごとそのまま移植)から、このアプリのフラットなファイル構成
  (`Core/`サブフォルダ無し)に合わせて移植したもの。**当初は自動タグ表示のみのスコープ**
  だった(Mac版の`EpisodeTagStore`(手動タグ)・`Views/EpisodeTagEditorView.swift`
  (編集シート)は今も移植していない)が、同日中に「タグフィルタしたい」という追加要望を
  受けて`TagFilterRow`(押せる絞り込みUI、下記参照)は後から追加した。`ConanEpisodeTags.
  allTags(for:)`がキーワード判定+話数別参照データを合わせて返し、`definedTagNames`
  (キーワードルールの7種、タグフィルターの選択肢順序に使う)を持つ。
  `Views/RelatedTagsRow.swift`の`RelatedTagsRow`(表示専用チップ)が`SourceGridView.swift`の
  `VideoCardView`/`VideoRowView`でタイトル下にカプセル型チップとして描画する(1件以上
  あるときだけ)。**`ConanMainStoryReference.tagsByEpisode`はMac版と別々に管理・手動同期**
  ― どちらかを編集したら、話数データの追加・修正は両方に反映すること(自動で同期する
  仕組みは無い)。
- **`Sources/MyTubePad/ConanContentKind.swift`**(2026-08-27追加、mytube(Mac版)の
  `Core/ConanContentKind.swift`から移植) — タイトルの話数トークンからTV本編/劇場版を
  判定する`classify(title:)`。**当初は`SourceGridView`上部の「すべて/TV/映画」セグメント
  ピッカーのフィルター条件として使っていたが、同日中に撤去した**(「アニメ」共有リンクで
  無関係なTV/映画タブが誤って出てしまう報告を受け、下記「フォルダタブ」(物理フォルダ
  ベース)に置き換えたため)。現在は`displayTitle(for:)`(表示用にタイトル先頭の冗長な
  番組名/「映画」トークンを取り除く、下記参照)のためだけに`classify(title:)`を使っている。
- **`displayTitle(for:)`**(`ConanContentKind.swift`、2026-08-27追加、「TVでは名探偵コナンを
  非表示、映画では名探偵コナン 映画を非表示にしたい」という要望への対応) — TV本編は
  タイトル先頭の番組名だけを、劇場版は番組名+「映画」(またはcrossoverの`"Movie"`)トークンを
  まとめて取り除いた表示用文字列を返す。**あくまで表示専用**(`SourceGridView`の`Text`にだけ
  使う)― `ConanEpisodeTags`/`ConanMainStoryReference`のタグ判定・話数パースは元の
  `video.title`をそのまま使い続ける。
- **フォルダタブ**(`SourceGridView.swift`の`ChannelTabRow`、2026-08-27追加、「アニメも
  ドラマも、フォルダごとにタブにして」という要望への対応 ― 上記の通り、TV/映画の種類
  フィルターから置き換えたもの) — `video.channel`(共有フォルダ直下のサブフォルダ名、
  タイトルの命名規則に依存しない実際の物理フォルダ構造)ごとに「すべて」+実在する
  チャンネル名をカプセルボタンの単一選択タブとして横スクロール表示する。`localizedStandardCompare`
  で自然順ソート(`0001-0799`→`0800-0899`のような範囲名フォルダが数値順に並ぶ)。
  チャンネルが1種類しか無ければ(例: 「映画」共有リンクのように全動画が「(ルート)」1本の
  場合)タブ自体を出さない。Mac版のサイドバーの横断チャンネルとは異なり、**選択中の
  共有リンク1本の中でのフィルター**として実装した(mytube-ipadには複数ソース横断の
  チャンネル概念が無く、1つの共有リンク=1画面という単純な構成のため)。
- **タグフィルター・表示形式(グリッド/リスト)・サムネイル**(2026-08-27追加、「タグフィルタが
  できない」「ハイブリッドビューモードでタグフィルタしたい」「サムネイルも表示したい」
  という一連の要望への対応 ― 当初のMVPスコープ(サムネイル無し、表示形式の切り替え無し、
  タグフィルター無し)から、ユーザーの明示的な要望で拡張した) —
  - `Views/RelatedTagsRow.swift`の`TagFilterRow`(Mac版から移植、AppKit依存が無いため
    無変更でiOSでも動く)を`SourceGridView`の`content`の上に表示。母集団は
    `channelFilteredVideos`(フォルダタブ適用後)― `filteredVideos`(タグフィルター適用後)
    から選択肢を計算すると絞り込むたびに他の選択肢が消えてしまうため、Mac版と同じく
    適用前から計算する。
  - `Models.swift`の`HomeViewMode`(grid/list、`Settings.homeViewMode`に永続化)を
    ナビゲーションバー右のセグメントピッカーで切り替える。iOSには`Table`が無いため、
    Mac版の`VideoTableView`相当は`Views/VideoLibraryView.swift`内の`VideoRowView`
    (単純な`HStack`の行、タイトル+タグ+サイズ)として実装した。
  - `ThumbnailStore.swift`(2026-08-27新規) — `AVAssetImageGenerator`でリモートURL
    (`video.downloadURL`)から3秒地点のフレームを非同期取得し、`remoteID`をキーに
    `NSCache`だけでメモリキャッシュする(Mac版の`ThumbnailStore`と違い**ディスクキャッシュは
    持たない** ― MVPの単純さを優先し、アプリ再起動でキャッシュが消えても再スキャン時に
    再取得されるだけなので実用上問題ないと判断)。tempauth URLの期限切れ(1時間程度)で
    生成に失敗した場合は`nil`を返しプレースホルダーアイコン(`play.circle.fill`)を表示する
    だけで、明示的なエラー通知・リトライは持たない。**`VideoRowView`(リスト/ハイブリッド
    表示)はこのストアを使わない**(2026-08-28追加、「ハイブリッドモードでサムネイル
    取得しなくて良い」という要望への対応 ― 行数が多いライブラリ(数百話)をリスト表示すると
    スクロールのたびに行の数だけリモートURLへのフレーム取得が走り、ネットワーク・
    デコード負荷になっていたため、プレースホルダーアイコンの固定表示に置き換えて
    まるごと無くした)。`VideoCardView`(グリッド表示)は従来通りサムネイルを取得する
    ― グリッドは元々サムネイルが主役の表示形式のため対象外。
  - `SourceGridView`の各`@State`(表示形式以外)は`ContentView`が`.id(bookmark.id)`を
    付けて呼ぶため、別のリンクに切り替えると自動的にリセットされる ― Mac版のように
    `onChange`で明示的にクリアする処理は不要。

- **`Sources/MyTubePad/DownloadStore.swift`**(2026-08-27追加、「Local DL機能追加してほしい」
  という要望への対応) — mytube(Mac版)の`Core/DownloadStore.swift`のOneDrive側と同じ
  設計方針の`@MainActor ObservableObject`シングルトン。再生自体はダウンロード完了を待たず
  ストリーミングで即座に始まり、ダウンロードは`URLSessionDownloadTask`で並行して進む。
  保存先は`~/Library/Application Support/MyTubePad/downloads/<remoteID>.<fileExtension>`
  (`Caches`ではなく`Application Support` ― ユーザーが明示的に保持したいデータのため)。
  `fileExtension`は`VideoItem`に追加したフィールド(`OneDriveShareClient.toVideoItem`が
  `item.name`のpathExtensionから設定)― `downloadURL`(tempauth署名付きURL)はパス自体が
  固定文字列で拡張子を含まないため、別途保持する必要がある(Mac版の`VideoItem.fileExtension`
  と同じ理由)。**HTTPステータスコードを検証してから保存する**(Mac版の
  `finishHTTPDownload`と同じ教訓 ― `URLSession`はHTTPステータスが4xx/5xxでも`error`を
  nilのまま返すため、検証しないとtempauth URL期限切れ時のOneDriveのエラーレスポンスを
  動画本体として保存してしまう)。`primeStates()`が起動時にダウンロード済みディレクトリを
  スキャンして`states`を復元する(ファイル名の`<remoteID>`部分をキーとして逆算)。
  **Mac版のOneDrive用「ローカルに保存」トグル・容量上限・自動削除は無い** ― 「ダウンロード」/
  「キャンセル」/「ローカルコピーを削除」の単発操作に加え、2026-08-28に「複数保存」
  「複数削除」「全件削除」を追加した(下記`VideoLibraryView`/`LocalDownloadsView`参照)。
  `deleteAllLocalCopies()`(進行中のダウンロードもすべてキャンセルしてから保存先
  フォルダの中身をまるごと削除、`states`/`Settings.downloadedVideoInfos`もクリア)と
  `totalDownloadedBytes()`(`localVideos()`の`size`合計、「保存済み」画面のストレージ表示用)
  を追加した。
  - **UI**: `Views/VideoLibraryView.swift`の`videoDownloadContextMenu(video:)`(`View`拡張)を
    グリッド・リスト両方の動画ボタンに適用 ― カード/行全体が再生用の`Button`のラベルに
    なっているため、ダウンロード操作はタップ(再生)と衝突しない長押しコンテキスト
    メニューにした(状態に応じて「ローカルにダウンロード」/「ダウンロードをキャンセル」/
    「ローカルコピーを削除」を出し分ける)。状態表示は`DownloadBadge`(サムネイル左上、
    ダウンロード中は%表示、完了はチェックマーク、失敗は!マーク、`.notDownloaded`は
    何も出さない)― `VideoCardView`/`VideoRowView`とも`@ObservedObject private var
    downloadStore = DownloadStore.shared`で購読し、ダウンロード進捗のたびに再描画される。
  - `Views/PlayerView.swift`は`DownloadStore.shared.playableURL(for:)`(ダウンロード済み
    ならローカルファイル、そうでなければ`video.downloadURL`)経由でURLを取得するよう変更 ―
    ダウンロード済みの動画はtempauth URLの期限切れの影響を受けなくなり、オフラインでも
    再生できる。
  - **`Settings.downloadedVideoInfos`(`DownloadedVideoInfo`、`Models.swift`)** ―
    ダウンロード開始時に`VideoItem`のタイトル・チャンネル・拡張子・サイズ・更新日時を
    複製して永続化する。`localVideos()`がこれと`states`(実際にファイルが存在するかの
    確認)を突き合わせて`[VideoItem]`を再構成する ― これにより「保存済み」一覧が
    アプリ再起動後や元の共有リンクを再スキャンしなくても正しく表示できる。ダウンロードの
    キャンセル・削除・失敗のいずれでも対応するメタデータを`removeMetadata(remoteID:)`で
    削除し、実体の無いエントリが残らないようにしている。

- **`Views/VideoLibraryView.swift`**(2026-08-27追加、「ローカルに保存した動画の一覧も
  ほしい」という要望への対応で`SourceGridView.swift`から切り出した) — グリッド/リストの
  表示形式・フォルダタブ(`ChannelTabRow`)・タグフィルター・状態表示・
  `videoDownloadContextMenu`・`DownloadBadge`・`VideoCardView`/`VideoRowView`など、
  動画一覧画面の中身を丸ごと持つ再利用可能なビュー。`videos: [VideoItem]`と
  `isLoading`/`errorMessage`/`emptyMessage`/`onPlay`さえ渡せば動く ― `RemoteSource`や
  共有リンクの概念には一切依存しない。
  **複数選択(2026-08-28追加、「複数保存」「複数削除」という要望への対応)**:
  `selectionAction: LibrarySelectionAction`(`.download`/`.delete`、呼び出し元が指定する
  必須パラメータ)を持つ。ツールバー左の「選択」で`isSelectionMode`に入ると、動画を
  タップしても再生せず選択のトグルになる(mytube Mac版の`HomeVideosView`の複数選択
  モードと同じ発想 ― `VideoCardView`/`VideoRowView`にも`isSelectionMode`/`isSelected`を
  追加し、グリッドはサムネイル右上に`SelectionBadge`、リストは行末にチェックマークを
  出す)。選択中は上部に件数・「すべて選択/解除」・一括操作ボタンを出す ―
  `.download`なら選択分すべてに`DownloadStore.startDownloadIfNeeded(for:)`、`.delete`なら
  確認ダイアログの後に選択分すべてへ`deleteLocalCopy(for:)`。2つの呼び出し元:
  - **`Views/SourceGridView.swift`** — 選択中の共有リンクのスキャン結果を`selectionAction:
    .download`で渡す薄いラッパー(共有リンクのスキャン(`onLoad`/`.refreshable`/
    `.task(id:)`)とナビゲーションタイトルだけを担当)。
  - **`Views/LocalDownloadsView.swift`**(新規) — `DownloadStore.shared.localVideos()`を
    `selectionAction: .delete, showsFullTitle: true`で渡す薄いラッパー。`ContentView`の
    サイドバーで、共有リンクの一覧とは別枠の「保存済み」という特別な行(`Button`、
    `List(selection:)`の`SharedLinkBookmark.ID`タグ体系には乗せていない。2026-08-28に
    一時的に「アイコンだけでOK」(`Image`のみ+`.accessibilityLabel`)にしたが、同日中に
    「アイコンじゃなくて、保存済みという表示に変えて」と撤回されたため`Text("保存済み")`
    表示に戻した)として選べる ― `ContentView.isLocalDownloadsSelected`
    (`selectedBookmarkID`とは排他)で管理する。どの共有リンクからダウンロードしたかに
    関わらず、端末に保存済みの動画を横断して一覧できる。表示名は当初「ローカル保存済み」
    だったが、2026-08-28に「『ローカル』という表示はいらない」という要望を受けて
    「保存済み」に短縮した(コード内の識別子・ファイル名は変えていない)。
    **`showsFullTitle: true`**(2026-08-28追加、「保存済みの一覧では、ファイル名全部
    出して」という要望への対応) ― `VideoLibraryView`(下記)の`ConanContentKind.
    displayTitle(for:)`による番組名省略をせず、`video.title`(ファイル名そのまま)を
    `lineLimit`無しで全文表示する。複数の共有リンク・フォルダを横断する一覧のため、
    どのファイルか一意に分かるよう省略しない方が実用的と判断した(`SourceGridView`側は
    従来通り`showsFullTitle: false`のまま、省略表示を維持)。**全件削除**は複数選択を
    経由しない専用のツールバー
    ボタン(ゴミ箱アイコン、確認ダイアログ付き、`DownloadStore.deleteAllLocalCopies()`を
    呼ぶだけ)― 2026-08-28追加、「全件削除を入れてほしい」という要望への対応。全部消したい
    ときに毎回「すべて選択」を押させるのは冗長なため、複数選択モードとは別に単独で用意した。
    **端末ストレージ状況**(2026-08-28追加、「Ipadの全体のストレージ状況も示してほしい」
    という要望への対応)も`VideoLibraryView`の上に`StorageSummaryRow`として常時表示する
    (スクロールでは隠れない位置 ― `VStack { StorageSummaryRow; Divider; VideoLibraryView }`
    という構成で、`VideoLibraryView`内部の`ScrollView`の外に置いている)。
    「このアプリの保存容量」(`DownloadStore.totalDownloadedBytes()`)と「端末の空き容量」
    (`Sources/MyTubePad/DeviceStorage.swift`(新規)の`totalAndFreeBytes()`、
    `URL.resourceValues(forKeys:)`の`.volumeTotalCapacityKey`/
    `.volumeAvailableCapacityForImportantUsageKey`から取得)を並べて出す ―
    「あとどれくらいダウンロードして大丈夫か」の目安になるようにした。

- **`Sources/MyTubePad/RemoteListCache.swift`**(2026-08-28追加、「毎回OneDriveから一覧を
  とってくるのを効率よくできないか。一覧はローカルに保存して、起動時にバックグラウンドで
  更新するような」という要望への対応) — mytube(Mac版)の`Core/RemoteListCache.swift`と
  同じstale-while-revalidate方式のキャッシュ。`~/Library/Caches/MyTubePad/
  remote-list-cache/<SHA256(共有URL)>.json`に`sourceName`+`[VideoItem]`をJSONで保存する
  だけの薄いenum(`VideoItem`は`Codable`に適合させた)。`ContentView.loadSource(bookmark:)`が
  新規にそのリンクを開く(`sources[key] == nil`)ときだけ使う ― まずキャッシュがあれば
  それを`RemoteSource.videos`の初期値にして即座に表示し、その裏で必ず
  `OneDriveShareClient.scan`(`scanWithRetry`経由)を実行して最新の結果で上書きする
  (成功したら`RemoteListCache.save`で次回起動用に更新)。既に開いているソースの
  再スキャン(プルダウン更新)ではこのキャッシュを触らない(今表示中のものをそのまま
  残せば十分なため)。`SourceGridView`はバックグラウンド更新中(キャッシュ済みの一覧を
  表示しながら裏でスキャン中、`source.isLoading == true`)、ツールバー左に控えめな
  `ProgressView`を出す ― `VideoLibraryView`の「一覧が空のときだけの全画面スピナー」
  分岐はキャッシュがある間は通らないため、代わりの進捗表示として追加した。
  **既知の注意点**: キャッシュ内の`VideoItem.downloadURL`(tempauth署名付きURL)は
  実測1時間程度で失効する。バックグラウンドの再スキャンが完了する前に、キャッシュから
  復元した古いURLのまま再生しようとすると失敗しうる(再スキャンが終われば新しいURLに
  置き換わる)。ダウンロード済みの動画は`DownloadStore.playableURL(for:)`がローカル
  ファイルを優先するため、この問題の影響を受けない。
  **プルダウン更新のキャンセルで一覧が消えるバグ**(2026-08-28修正、「プルダウンしたら
  ローディングマークが出て一覧が消えた」というバグ報告への対応): `loadSource(bookmark:)`
  のキャンセル処理(`Self.isCancellation(error)`分岐、「ローディングがcancelledに
  なったら再ロードできない」バグの修正で導入したもの)は、当初キャンセルなら常に
  `sources`からエントリを丸ごと削除していた ― 新規の初回読み込みがキャンセルされた
  場合はこれで正しいが、**既に一覧を表示できている状態でのプルダウン更新がキャンセル
  された場合も同じ処理が走ってしまい**、表示中の動画一覧までまっさらに消えていた。
  スキャン開始前に`hadExistingVideos`(その時点で`videos`が空でなかったか)を控えて
  おき、キャンセル時に真なら`isLoading`を戻すだけで`videos`はそのまま残す・偽なら
  従来通りエントリごと削除する、という2分岐にして修正した。

- **アプリアイコン**(2026-08-27追加、同日中に意匠を2回変更) — `make-icon.swift`
  (`swift make-icon.swift`で実行)が`Sources/MyTubePad/Assets.xcassets/AppIcon.appiconset/
  icon-1024.png`(1024x1024、アルファチャンネル無し)を生成する。白背景+単色シルエットと
  いう構図([[app-icon-style]]の自作アプリ共通デザイン)はmytube(Mac版)の
  `make-icon.swift`と共通。**モチーフ・色の変遷**: ①当初はMac版と同じ「濃い赤`#B30010`の
  横長の角丸プレート+白い再生三角形」だったが、これがYouTubeのロゴと形が酷似しており
  「アイコンがyoutubeっぽすぎる」という指摘を受けたため、「縦長のタブレット本体の
  シルエット(下端に白いホームボタンの丸)+中に白い再生三角形」というiPadらしい
  モチーフに変更した。②その後「形は戻して、シルエットは青にして」という要望を受け、
  **形はMac版と同じ横長プレート+三角形に戻し、色を赤から青`#1B5E9E`(以前mytube/
  mygallery(と、当時存在したmymusic)が使っていた青系シルエットと同じ値、2026-08-12に
  全アプリ赤へ統一される前の色)に変更した**(最終形、`silhouetteBlue`)― mytube-ipadだけ他の自作アプリと
  色を変えることで、Mac版の実機・Dock上でも見分けやすくする狙い。iOS向けの技術的な
  制約は2点: ①**角丸を自分で描かない** ― iOSはシステム側が自動で角丸マスクをかけるため、
  正方形いっぱいに白を塗るだけでよい(自前で角丸にすると二重角丸になる)。②**PNGに
  アルファチャンネルを持たせない** ― iOSのApp IconはXcode/App Store Connectがアルファ
  入りPNGを拒否するため、`CGContext`で`.noneSkipLast`の不透明画像に変換してから書き出す
  (mytube Mac版の`.icns`/`iconutil`方式とは異なり、iOS 17+のXcodeが対応する「1024pxを
  1枚だけ用意すればよい」単一サイズApp Icon方式を使っている ―
  `AppIcon.appiconset/Contents.json`の`idiom: universal`がそれ)。`project.yml`の
  `ASSETCATALOG_COMPILER_APPICON_NAME: AppIcon`がこのアセットカタログをApp Iconとして
  使うようXcodeに指示する。アイコンを変更する場合は`make-icon.swift`を編集して
  再実行するだけでよい(`Assets.xcassets`自体は`Sources/MyTubePad`配下にあるため、
  `xcodegen generate`をしなくても既存の`.xcodeproj`が自動的に拾う ― フォルダ参照ではなく
  個別ファイル列挙のため、フォルダ自体が既にプロジェクトに存在すれば中身の画像差し替えは
  再生成不要。ただし`AppIcon.appiconset`フォルダ自体が今回のように新規追加の場合は
  1回`xcodegen generate`が必要)。

- **Picture in Picture(2026-08-27追加、「最前面表示モード(PIP?)機能を追加してほしい」
  という要望への対応)** — `Views/NativeVideoPlayerView.swift`(新規) が
  `AVKit.VideoPlayer`(SwiftUI)ではなく`AVPlayerViewController`を直接
  `UIViewControllerRepresentable`でラップする(mytube Mac版が`AVPlayerView`を直接
  ラップしているのと同じ「無い機能はAVKit/AppKitへ薄く橋渡しする」方針) ― `VideoPlayer`
  はPiP関連のプロパティ(`allowsPictureInPicturePlayback`/
  `canStartPictureInPictureAutomaticallyFromInline`)を設定する手段を公開していないため。
  `canStartPictureInPictureAutomaticallyFromInline = true`にしているので、ユーザーが
  ホームに戻る/他アプリへ切り替えるだけで自動的にフローティングのPiPウィンドウへ移行する
  (iOS標準のシステムPiP ― 他アプリの上にも常に最前面で表示される、明示的にPiPボタンを
  押す必要は無い)。`Views/PlayerView.swift`は`VideoPlayer`をこれに差し替えただけ。
  **バックグラウンドでも再生を継続するために2箇所の設定が必要**(片方だけでは、アプリを
  離れた瞬間にPiPが停止する): ①`MyTubePadApp.init()`で`AVAudioSession`のカテゴリを
  `.playback`に設定・有効化する。②`project.yml`のInfo.plistプロパティに
  `UIBackgroundModes: [audio]`を追加する(バックグラウンドオーディオ再生の権限)。
  **`setActive(true)`はメインスレッドで直接呼ばない**(2026-08-28、実機で「...siveness
  if called on the main thread. Consider using the asynchronous activate/deactivate
  API instead for calls from the main thread.」という警告と共にクラッシュした報告への
  対応)。`init()`はメインスレッドで呼ばれるが、同期版`setActive`はブロッキングしうると
  Appleが警告している ― 非同期版`activate(options:completionHandler:)`も存在するが
  **iOSでは`unavailable`(macOS専用)でビルドが通らない**ため、代わりに
  `DispatchQueue.global().async`でバックグラウンドキューへ逃がしてメインスレッドを
  ブロックしないようにした。

## 今後拡張する場合のメモ

- サムネイル表示を足すなら、`AVAssetImageGenerator`をリモートURLに対して使うだけで動く
  はず(Mac版の`ThumbnailStore`と同じAPI)だが、tempauth URLが1時間で失効するため
  キャッシュキー設計に注意(Mac版は`remoteID`をキーにしてURL自体はキーに使っていない ―
  同じ方針を踏襲すること)。
- ダウンロード・オフライン再生を足すなら、`URLSession`の`downloadTask`で
  `Application Support`配下に保存する形がMac版の`DownloadStore`(OneDrive側)と同じ設計。
- 複数の共有リンクを横断した「すべての動画」ビューが欲しくなったら、Mac版の
  `allVideos`(`flatMap`で合算する計算プロパティ)と同じパターンで足せる。
