# CLAUDE.md — mytube

フォルダ配下の動画を再帰スキャンし、YouTube 風のグリッド/サイドバー UI で閲覧・再生する
SwiftUI + SPM 製の動画プレイヤー。ローカルフォルダは既存ファイルをそのまま再生するだけだが、
OneDrive共有リンク(2026-08-04〜)・YouTubeプレイリスト(2026-08-05〜)というリモート
ソースも同じライブラリとして開ける ― どちらも`DownloadStore`が裏でローカルにキャッシュする
(下記`Core/DownloadStore.swift`の項、OneDriveとYouTubeでダウンロード方式もキャッシュ後の
扱いも異なる)。使い方は `README.md` を参照。

## ビルド / デプロイ

```bash
swift build         # コンパイル確認のみ(GUI 起動・目視確認は禁止 — ルート CLAUDE.md 参照)
./build_app.sh       # MyTube.app を生成
./install.sh         # ビルド → /Applications/MyApplications へインストール
```

`MyTube.app` `.build/` `AppIcon.icns` `AppIcon.iconset/` は .gitignore 済み・スクリプトから
再生成される成果物。コミットしない。

- **バージョンは `Sources/MyTube/Main.swift` の `appVersion` が唯一の定義**
  (myorganizer と同じ方式)。`build_app.sh` が Info.plist に反映する。
- **`Package.swift` の `linkerSettings: [.linkedFramework("AVKit")]` を外さないこと。**
  `AVKit.VideoPlayer`(`PlayerPaneView.swift`)は、AVKit.framework がバイナリに明示的にリンクされて
  いない状態で Xcode デバッガ無し(Finder からのダブルクリック、`open MyTube.app` 等)に
  起動すると、`_AVKit_SwiftUI` 内部が `AVPlayerView` のスーパークラスを demangle できず
  `getSuperclassMetadata` で `abort()` する既知の macOS バグ(FB8928032、"failed to demangle
  superclass of VideoPlayerView from mangled name 'So12AVPlayerViewC'")を実機で踏んだ
  (`swift build`/`swift run` では再現せず、`./install.sh` でインストールした `.app` を
  Launchpad から起動して初めて発生した — デバッガに繋がっていると再現しないバグのため)。
  Xcode プロジェクトなら「Link Binary With Libraries」に AVKit.framework を追加するのが
  定番の回避策だが、SPM の `executableTarget` には相当する GUI 設定が無いため、
  `linkerSettings` で同じことを明示的に行っている。
- **通常の SwiftUI `App`/`WindowGroup` 構成**(downloader/mymusic と違いメニューバー常駐ではない)。
  動画再生を裏で継続する必要がないため、ウィンドウを閉じればアプリごと終了してよい
  (myorganizer と同じ構成)。
- **非サンドボックス**: `Package.swift` に entitlements は無く、`Settings.openLocalFolders` は
  素の絶対パス文字列の配列を UserDefaults に保存するだけで済む(security-scoped bookmark は不要)。
  デスクトップ/書類/ダウンロード等 TCC 保護下のフォルダを指定された場合のみ、
  フルディスクアクセス権限が必要になることがある(README 参照)。

- **フォルダのドラッグ&ドロップ読み込み**(`ContentView.handleDrop(providers:)`): メインコンテンツ
  領域(サイドバー+グリッド/視聴画面の `HStack`)に `.onDrop(of: [.fileURL], ...)` を仕込み、
  `chooseFolder()` の `NSOpenPanel` と同じ `openFolder(_:)` を呼ぶ。複数ドロップされた場合は
  最初に見つかった有効なフォルダだけを使う(`NSOpenPanel` の `allowsMultipleSelection = false`
  と挙動を揃える)。`NSItemProvider.loadObject(ofClass: URL.self)` は非同期コールバックで
  メインスレッド外から呼ばれるため、`isDirectory` チェックと `openFolder(_:)` 呼び出しは
  `DispatchQueue.main.async` で包む。ドラッグ中は `isDropTargeted` で枠線をオーバーレイ表示する。

## アーキテクチャ

- **`ContentView.swift`** — トップレベル。`TopBarView`(検索欄+フォルダ選択、常時表示)+
  `HStack { SidebarView; VStack { PlayerPaneView または HomeVideosView } }`。
  `NavigationSplitView` は使わず素の `HStack`/`VStack` で組んでいる(YouTube のヘッダーが
  サイドバーの上まで横断するレイアウトを再現するため — `NavigationSplitView` だと
  ツールバー領域がサイドバー/detail で分断されてしまう)。
  **`selectedVideo`の有無で`PlayerPaneView`/`HomeVideosView`を切り替える**
  (`if let selectedVideo { PlayerPaneView(...) } else { HomeVideosView(...) }`)。
  この「切り替える/常に両方見せる」の方針は2026-08-05〜06で2回変わっている:
  当初(WatchView時代)は独立した「視聴ページ」への画面切り替えで、「戻る」ボタンでしか
  グリッドへ戻れなかった。2026-08-05に「YouTubeのように1ページにしたい」(視聴中でも
  グリッドから他の動画を探したい)という要望で、`HomeVideosView`を常に表示しその上に
  `PlayerPaneView`を重ねる形へ変えた。その後2026-08-06、`upNextList`(次の動画、下記
  `Views/PlayerPaneView.swift`の項参照)を追加した後に「再生中は一旦Grid消したら
  どうなる?」「やってみて」という流れで実際に試した結果、グリッドを隠しても`playerArea`
  自体は大きくならない(横幅で頭打ちのため)一方、`upNextList`が画面下まで使えるように
  なりYouTubeの視聴ページに近づくと判断し、**動画選択中は`HomeVideosView`を出さない**
  現在の形に戻した(「視聴中でもグリッドから探せる」という2026-08-05の前提は撤回 ―
  動画を探すには`upNextList`を使うか、✕で閉じてグリッドへ戻る)。「戻る」ボタン
  (`TopBarView.showsBackButton`/`onBack`)自体は2026-08-05に廃止したまま ―
  `PlayerPaneView`右上の✕ボタンで閉じると`selectedVideo`が`nil`に戻り、自動的に
  `HomeVideosView`へ切り替わる。`filteredVideos`(チャンネル/
  長さ/検索の絞り込み後、実際にグリッド・オートプレイのキューに渡す一覧)の並び順は
  `TopBarView`の「並び替え」メニュー(`SortOption`、`Models.swift`)で選ぶ
  (2026-08-05、「期間のフィルタはいらない。かわりにソート機能をつけて」という要望に対応 ―
  以前あった期間フィルター(`TimeFilter`、更新日時で絞り込むメニュー)を廃止し、絞り込みでは
  なく並び替えに置き換えた)。既定は`titleAscending`(`title.localizedStandardCompare`による
  ファイル名昇順、以前の固定ソートと同じ結果)、他に`titleDescending`/`dateNewest`/
  `dateOldest`があり、`SortOption.areInIncreasingOrder(_:_:)`を`filteredVideos`が
  `videos.sorted(by:)`にそのまま渡す。日時順ソートで`modifiedDate`が`nil`の動画
  (OneDrive/YouTubeの一部)は末尾に固定する。

  **動画を開くとフォルダツリーサイドバーを自動的に隠す**(2026-08-06追加、「再生プレーヤーの
  下のリストを削除したら、画面がもう少し大きくなるのでは?」というユーザーの提案への回答 ―
  実際にはデフォルトウィンドウ幅では`PlayerPaneView`は横幅で頭打ちになっており(`playerArea`の
  ドキュメント参照)、下の`HomeVideosView`のグリッドではなく左の`SidebarView`(幅220〜260pt)を
  隠す方が効くと判断し、そちらを実装した)。`@State private var isSidebarCollapsed`を
  `.onChange(of: selectedVideo) { newValue in isSidebarCollapsed = newValue != nil }`で
  動画選択の有無に連動させ、`true`の間は`body`の`HStack`から`SidebarView`ごと(`if
  !isSidebarCollapsed { SidebarView(...); Divider() }`)取り除く。`TopBarView`左端の
  `sidebar.left`アイコンのボタン(`isSidebarCollapsed`を直接トグル)でいつでも手動でも
  表示・非表示を切り替えられる ― 動画を見ながら別のフォルダに切り替えたい場合の手動復帰用。
  **`if`で条件分岐しているため、隠すたびに`SidebarView`自体が破棄・再生成される**
  ―`FolderTreeRow`の展開状態(`SidebarView.expandedNodeIDs`、`@State`)はサイドバー内で
  完結しているため、再表示のたびに全ノード折りたたみの初期状態にリセットされる(展開状態を
  `ContentView`側へ持ち上げて維持する、という作りにはしていない ― 単純さを優先した)。

  **`TopBarView`左上の「MyTube」ロゴはホームに戻るボタン**(2026-08-06追加、「一番左上の
  MyTubeアイコンを押したら、起動直後のPlayerの無い画面(ホーム画面)に戻りたい」という
  要望への対応。YouTubeのロゴクリックと同じ発想)。`TopBarView`の`onGoHome: () -> Void`を
  `ContentView`が`{ selectedVideo = nil }`として渡すだけ ― `PlayerPaneView`右上の✕
  (`onClose`)と全く同じ効果だが、プレイヤーを閉じる操作の入り口をもう1つ増やした形。
  ロゴ自体は元々ただの`HStack`(アイコン+テキスト)だったのを`Button(action:
  onGoHome).buttonStyle(.plain)`で包んだだけで、見た目は変えていない。

  **複数ソースの同時オープン**(2026-08-04、「開いたものは明示的に閉じるまでロードした
  ままにしたい」という要望への対応。当初は単一のローカルフォルダ⇔単一の共有リンクが排他
  ―後にローカル1つ+リモート1つの同時表示―という変遷を経て、最終的に「ローカル・リモート
  ともに複数同時に開ける」形に落ち着いた): `localSources: [LocalSource]`/
  `remoteSources: [RemoteSource]`(`Models.swift`、ともに`Identifiable`)という2つの配列で
  持ち、`allVideos`は`localSources.flatMap(\.videos) + remoteSources.flatMap(\.videos)`で
  合算する計算プロパティ(`@State`の生配列ではない)。`openFolder(_:)`/
  `openRemote(name:shareURL:)`は、それぞれ`LocalSource.id`(パス文字列)/`RemoteSource.id`
  (URL文字列)で重複排除する ― 既に開いているものを再度開こうとした場合は追加ではなく
  そのソースだけを再スキャン/再読み込みする(他のソースには一切影響しない)。閉じるのは
  `closeLocalSource(_:)`/`closeRemoteSource(_:)`(配列から`removeAll`する。閉じたソースが
  サイドバーで選択中だった場合は`selectedNode`も`nil`に戻す ― 存在しないソースを選択した
  ままにしないため)。
  `persistOpenSources()`が両配列をまるごと`Settings.openLocalFolders`(パス文字列の配列)/
  `Settings.openRemoteLinks`(`SharedLinkBookmark`型を流用した名前+URLの配列、複数件の
  JSON)に書き戻し、`open*`/`close*`の呼び出しのたびに呼ばれる。起動時は
  `restoreOpenSources()`がこの2つの永続化リストを順に`openFolder`/`openRemote`へ渡して
  復元する ― 「ローカルとリモートは独立」「片方の読み込みがもう片方を消さない」という
  以前からの方針を、単一値から配列に拡張しても維持している。**加えて、登録済みの共有リンク
  ブックマーク(`Settings.sharedLinkBookmarks`)も毎回自動で開く**(2026-08-04〜、「登録した
  リンクは起動時にロードしてほしい」という要望に対応。以前は前回終了時に開いていたリンクだけが
  復元され、登録だけして閉じていたリンクは手動で選ぶまで開かれなかった)。ブックマークと
  「前回開いていたリンク」でURLが重複する場合は`seenURLs`でde-dupeし(ブックマーク優先)、
  ブックマークに無い単発リンクも従来通り復元する。開いているソースを個別に閉じるUIは
  `Views/SidebarView.swift`の`FolderTreeRow`各ルート行(`FolderTreeNode.folderPath.isEmpty`の
  行だけ)にホバー中だけ出る✕ボタン(`ContentView.unloadSource(id:)`が
  `localSources`/`remoteSources`のどちらのIDか判定して`closeLocalSource(_:)`/
  `closeRemoteSource(_:)`に振り分ける薄いラッパー)。**以前は`TopBarView`にも
  「Videos + 実家PC」のようなフォルダ名の連結表示があり、押すと`OpenSourcesPopover`
  (ローカル/リモート双方を列挙し行ごとに✕ボタンを持つポップオーバー)が開く、という
  もう1つの入口があった**が、2026-08-05に「長さとフォルダの選択の間のライブラリの表示は
  いらない」という要望を受けて削除した(サイドバーの✕ボタンだけで用が足りる ―
  `TopBarView.folderName`/`onManageSources`パラメータと`ContentView.sourceLabel`/
  `showsSourcesPopover`、`Views/OpenSourcesPopover.swift`自体を丸ごと削除済み。
  再度追加しないこと)。
  リモート動画の`channel`には登録名を`"\(name) / \(元のchannel)"`の形でプレフィックスする
  (ローカルの同名サブフォルダや、複数の共有リンクを同時に開いた際のチャンネル名衝突を
  避けるため ― `OneDriveShareClient`自体はプレフィックスを付けず、`ContentView.openRemote`側で
  付与する)。**ただし元の`channel`が`VideoScanner.rootChannelLabel`(「(ルート)」、共有
  フォルダ直下でサブフォルダに入っていない動画のフォールバック値)のときはプレフィックスせず
  登録名だけにする**(2026-08-05、「チャンネルの 映画 / (ルート) の ルートの部分はいらない」
  という要望に対応 ― 「(ルート)」自体は情報を持たない固定文字列なので、付けても
  「映画 / (ルート)」のように冗長になるだけだった)。

  **YouTubeプレイリストの追加**(2026-08-05〜、「Local/OneDrive/YouTubeでグループ分け」
  「YouTube Playlistのインポート」という要望への対応): OneDriveの`RemoteSource`/
  `openRemote`のインフラをそのまま流用し、`Models.swift`に追加した`RemoteKind`(`.oneDrive`/
  `.youtube`)で分岐する形にした ― `RemoteSource.kind`/`VideoItem.remoteKind`を追加し、
  `openRemote(name:shareURL:kind:)`が`kind`に応じて`OneDriveShareClient.scan`と
  `YouTubePlaylistClient.fetchPlaylist`のどちらを呼ぶかを切り替える(下記
  `Core/YouTubePlaylistClient.swift`の項)。永続化は`SharedLinkBookmark`型(名前+URLのみ、
  種別を持たない)をそのまま使い回しつつ、**キー自体をOneDriveと完全に分ける**
  (`Settings.openYouTubePlaylists`/`Settings.youtubePlaylistBookmarks` ―
  `openRemoteLinks`/`sharedLinkBookmarks`のYouTube版)ことで後方互換のデコード処理を
  書かずに済ませている(`SharedLinkBookmark`に種別フィールドを足すと、既存の保存済み
  OneDriveブックマークJSONにそのフィールドが無いためデコードの後方互換対応が必要になる ―
  キーを分ける方が単純)。`restoreOpenSources()`/`persistOpenSources()`も
  OneDrive用・YouTube用の対をそれぞれ独立に処理する(前回開いていたURLと登録済み
  ブックマークのde-dupeロジックはOneDrive/YouTubeそれぞれで完結し、互いに影響しない)。
  トップバーの「OneDrive Link」/「Youtube Playlist」は共通の
  `Views/OpenRemoteLinkSheet.swift`(旧`OpenShareLinkSheet.swift`を`title`/
  `urlPlaceholder`パラメータ化して汎用化したもの)を使う ― 登録済み一覧+新規登録フォームという
  構造が完全に同じなため。

  **YouTubeは名前欄が無く、プレイリストのタイトルを自動取得する**(2026-08-05〜、
  「名前は自動取得してほしい」という要望への対応。当初はOneDriveと同じくユーザーが名前を
  手入力する仕様だったが、YouTube側は既にプレイリスト自体にタイトルがあるため入力を省いた):
  `OpenRemoteLinkSheet(showsNameField: false)`(YouTubeの呼び出し側だけ指定)は名前の
  `TextField`自体を出さず、`canAdd`もURLの非空だけを見る。`addYouTubeBookmarkAndLoad(name:
  url:)`に渡ってくる`name`は常に空文字になるため、その場ではまだ`SharedLinkBookmark`を
  作らず`openRemote(name: "", shareURL:kind: .youtube, registerBookmarkOnSuccess: true)`に
  委譲する(名前が確定していないブックマークを保存できないため)。`openRemote`側は`name`が
  空文字なら`RemoteSource`の表示名を一旦URL文字列そのもの(プレースホルダー)にしておき、
  `YouTubePlaylistClient.fetchPlaylist`の結果(`sourceName` = プレイリストのタイトル、
  無ければ1本目の動画タイトル)が返り次第それで置き換える。`registerBookmarkOnSuccess`が
  `true`のときはこのタイミングで確定した名前で`SharedLinkBookmark`を新規作成・永続化する
  (取得に失敗した場合はブックマークを作らない ― 名前が分からないものを登録しても仕方ないため)。
  ブックマークから選ぶ場合(`bookmark.name`は既に確定済み)や起動時の自動復元は、この
  自動取得パスを通らず従来通り即座に名前を使う。
- **`Core/Log.swift`**(2026-08-06追加、「パフォーマンスが悪いので処理をログに出してほしい」
  という要望への対応) — `os.Logger`をカテゴリ別(`scan`/`thumbnail`/`download`/`sidebar`)に
  用意した共通ロガー。サブシステムは`com.yoheisakata.mytube`固定 ― Console.appの検索欄で
  `subsystem:com.yoheisakata.mytube category:thumbnail`のように絞り込める。`elapsedMs(since:)`
  (`DispatchTime`ベース)と、それを使った同期/非同期版の`measure(_:_:_:)`ヘルパーを持つが、
  実際の呼び出し側は「開始時刻を取って処理後に差分をログに出す」形を手書きしている箇所が
  ほとんど(結果の件数など、経過時間以外の情報もメッセージに含めたいケースが大半だったため)。
  計測を仕込んだ箇所: `VideoScanner.scan`/`OneDriveShareClient.scan`/
  `YouTubePlaylistClient.fetchPlaylist`(いずれもスキャン1回ぶんの所要時間+件数)、
  `ThumbnailStore.generate`(サムネイル1枚の生成時間 ― 150ms超は`.notice`、以下は`.debug`
  (既定では非表示)に分けて、遅い生成だけ拾いやすくしている)、`DownloadStore`
  (ダウンロードの開始/完了/失敗、`primeStates`のバッチ確認時間)、`SidebarView`
  (`rebuildGroups()`=フォルダツリー再構築の所要時間)。パフォーマンス調査時はConsole.appで
  これらのカテゴリを見れば、スキャン・サムネイル生成・ダウンロード・サイドバー再構築の
  どこに時間がかかっているか切り分けられる。
- **`Core/VideoScanner.swift`** — `FileManager.enumerator` で指定フォルダ配下を再帰列挙し、
  対応拡張子のファイルだけ `VideoItem` にする純粋関数。`VideoItem.folderPath`(ルートから見た、
  動画を含むフォルダの全パスコンポーネント)を`folderPathComponents(for:root:)`で計算し、
  カード/視聴画面に出す「チャンネル」ラベル(`VideoItem.channel`)はその先頭要素
  (無ければ `VideoScanner.rootChannelLabel`)を使う ― 表示用の`channel`はルート直下の
  1階層目のサブフォルダ名だけだが、`folderPath`は階層をすべて保持する(下記
  `Core/FolderTree.swift`のツリー構築・フィルタ専用)。同期関数のため呼び出し側
  (`ContentView.openFolder(_:)`)が `Task.detached` でバックグラウンド実行し、完了後
  `MainActor.run` で該当`LocalSource.videos` に反映する(数千本規模のフォルダでもスキャン中に
  UI がフリーズしないようにするため)。`Core/OneDriveShareClient.swift`の`walk`も同じ規約で
  `folderPath`を積み上げる(以前はローカル・リモートとも1階層目のサブフォルダ名だけを
  「チャンネル」にし、2階層目以降のネストを1階層目の名前に丸め込んでいた ―
  2026-08-04、「サブフォルダのサブフォルダもうまく表示したい」という要望を受けて`folderPath`
  を導入し、階層情報を失わないようにした)。
  **初回ロードのパフォーマンス改善**(2026-08-05、「最初のローディングのパフォーマンスが悪い」
  という要望に対応): `includingPropertiesForKeys`/`resourceValues(forKeys:)`から
  `.fileSizeKey`を外した ― `VideoItem.fileSize`はUI側に表示箇所が無い完全な不使用
  フィールドだったため`Models.swift`ごと削除した(`OneDriveShareClient`の`RemoteVideo.size`/
  `DriveItemChild.size`も同様に削除)。要求するリソースキーが減るほど`enumerator`が
  ファイルごとに取得するメタデータも減り、特に1属性ごとのコストが高いファイルシステム
  (ネットワークドライブ等)で大量のファイルを持つフォルダのスキャンが速くなる。また
  `folderPathComponents(for:root:)`が**ファイルごとに**`root.standardizedFileURL.pathComponents`
  を再計算していた無駄を無くし、スキャン全体で不変な`rootComponents`をループの外で1回だけ
  計算するように変更した(関数シグネチャを`folderPathComponents(for:rootComponents:)`に変更)。
- **`Core/FolderTree.swift`**(2026-08-04追加) — サイドバーのネストしたフォルダツリー
  (`Views/SidebarView.swift`の`FolderTreeRow`)1本分を`VideoItem.folderPath`から組み立てる
  `FolderTreeNode`(参照型、`Identifiable`)+ `FolderTree.build(sourceID:sourceName:
  videos:)`。`LocalSource`/`RemoteSource`ごとに1本ずつルートノードを作る(`ContentView`の
  `SidebarView`呼び出し側ではなく`SidebarView`自身が`localSources`/`remoteSources`から
  都度構築する計算プロパティ)ため、同名サブフォルダが別ソースにあっても`sourceID`で区別され
  混ざらない。`SidebarSelection`(`Models.swift`、`sourceID`+`folderPath`)がサイドバーの
  選択状態を表し、`ContentView.filteredVideos`は選択中ソースの`videos`を
  `folderPath.starts(with: selection.folderPath)`で絞り込む(祖先フォルダを選べば配下も
  全部含む、Finder風エクスプローラーと同じ挙動)。**`SidebarView`のツリーはローカル/
  OneDrive/YouTubeの3グループに分ける**(2026-08-05追加、「Local/OneDrive/YouTubeで
  グループ分けしてほしい」という要望に対応 ― 以前は`localSources`と`remoteSources`の
  ノードを1本のフラットな配列に連結して単一のツリーに流していた)。`localGroups`/
  `oneDriveGroups`/`youtubeGroups`という3つの`@State`(`remoteSources`は
  `RemoteSource.kind`でfilterする)、それぞれ`sourceGroup(title:groups:showsDownloadAll:)`
  (グループ見出し+ツリー、ノードが0件のグループは見出しごと出さない)経由で描画する。
  各要素は`(node: FolderTreeNode, videos: [VideoItem])`のタプル(単に`[FolderTreeNode]`
  ではない ― 下記「配下をすべてダウンロード」参照)。
  **この3つは計算プロパティではなく`@State`にキャッシュし、`rebuildGroups()`で
  `onAppear`/`onChange(of: localSources)`/`onChange(of: remoteSources)`のときだけ
  組み直す**(2026-08-06、「パフォーマンスが悪い」という報告への対応 ― 元は計算プロパティ
  だったため、検索欄への入力や並び替え変更など`SidebarView`と無関係な`ContentView`の
  `@State`が変わって`body`が再評価されるたびに`FolderTree.build`(動画ごとに木を辿って
  ノードを組み立てる)がフルに再実行されており、動画数が多い(数百〜数千本)ライブラリでは
  検索欄に1文字打つたびに体感できるラグになっていた。`onChange`で実際のデータ変化に
  紐付けるには`LocalSource`/`RemoteSource`の`Equatable`合成が必要になったため
  `Models.swift`に追加した)。`Core/Log.swift`の項の通り`rebuildGroups()`の所要時間は
  `Log.sidebar`に出る。

  **フォルダの右クリックメニュー「配下をすべてダウンロード」**(2026-08-05追加、「左の
  サイドバーでフォルダを右クリック、そのフォルダ配下をすべてDLする機能」という要望への
  対応)。`FolderTreeNode`自体は`folderPath`しか持たず`VideoItem`を保持しないため、
  `FolderTreeRow`に`sourceVideos: [VideoItem]`(そのソース全体の動画一覧、再帰呼び出しでは
  深さに関わらず同じ配列をそのまま子へ渡す)を追加で持たせ、`videosInSubtree`
  (`sourceVideos.filter { $0.folderPath.starts(with: node.folderPath) }`、
  `ContentView.filteredVideos`と同じ絞り込み規約)を右クリック時に計算する。
  メニュー項目は`showsDownloadAll: Bool`(`sourceGroup`が「ローカル」グループには`false`、
  「OneDrive」「YouTube」グループには`true`を渡す ― ローカル動画は既にローカルにあり
  ダウンロードという概念が無いため)が`true`のときだけ出す。実行すると`videosInSubtree`の
  各動画へ`DownloadStore.shared.startDownloadIfNeeded(for:)`を呼ぶだけ ―
  同メソッドはダウンロード中/済みなら何もしないガードを内蔵しているため、同じフォルダに
  何度メニューを実行しても安全(重複ダウンロードは起きない)。並列数を絞るキュー等は
  設けていない(個人利用が前提のため、フォルダ単位で一気に始めても実用上問題ないと判断)。

  **木構造の描画は`OutlineGroup`を使わない自前の再帰ビュー(`FolderTreeRow`)**
  (2026-08-05、当初は`NavigationSplitView`/`List`を避けつつディスクロージャだけ得るため
  `OutlineGroup`を使っていたが撤去した ― 「サブフォルダはもう少しずらしてほしい」
  「同じ階層のサブフォルダは同じ横の位置にしてほしい」という要望に対応する過程で、
  `OutlineGroup`は子を持つノードの前にだけ開閉矢印ぶんの幅を自動確保するため、同じ階層でも
  子の有無でインデント量がずれてしまい、インデント幅をこちらから正確に制御できないことが
  判明したため)。`FolderTreeRow`は`node`/`depth`/`expandedNodeIDs`(`SidebarView`が
  `@State`で持つ`Set<FolderTreeNode.id>`)を受け取り、①`CGFloat(depth) * indentUnit`
  (`indentUnit` = 20pt)ぶんの空白 ②子の有無に関わらず常に`chevronSlotWidth`(14pt)を
  確保する開閉矢印スロット(葉ノードは透明な`Color.clear`プレースホルダー)③
  `folder.fill`アイコン(青色)+フォルダ名、の順で1行を描画し、`isExpanded`なら
  `node.children`を`depth + 1`で再帰的に自分自身(`FolderTreeRow`)へ渡す。
  インデント・矢印スロットの幅を完全に自前計算することで、同じ階層のノードは子の有無に
  関わらず必ず同じ横位置に揃う。展開状態の既定は全ノード折りたたみ(旧`OutlineGroup`
  実装のデフォルト挙動を踏襲)。「すべての動画」行はツリーの外(`SidebarView.body`の
  トップ)にあり、ディスクロージャ・インデントを持たない専用の`SidebarRow`(`folder.fill`
  ではなく`house.fill`)で描画する ― ツリー行(`FolderTreeRow`)とは別コンポーネント。

  **フォルダ名左のアイコンは`folder.fill`を青色で表示する**(2026-08-05、当日中に2度
  方針が変わった箇所 ― 最初は「Libraryのフォルダ名左のアイコンはいらない」という要望で
  外していたが、実際にサイドバーを見た上で「Finderのアウトライン表示(フォルダアイコン+
  階層インデント)のような見た目にしたい」という要望が来て復活させた)。
  **「ライブラリ」という共通見出しは出さない**(2026-08-05、「ライブラリという表示は
  いらないかも」という要望に対応 ― 以前は3グループの上に`Text("ライブラリ")`という親見出しを
  出していたが、各グループ自身の見出し(「ローカル」/「OneDrive」/「YouTube」)だけで
  区別できるため冗長と判断し削除した)。
  **インデントガイド線は無い**(2026-08-05、「サイドバーをもう少し階層的に表示してほしい」
  という要望を受けていったんVS Code風の縦のインデントガイド線を追加したが、実際に見た上で
  「インデントガイドライン線はいらない」と撤回されたため削除済み ― 再度追加しないこと。
  階層の見やすさは上記のフォルダアイコン + `depth`ベースのインデントだけで表現する)。
  **行の縦方向は詰め気味**(2026-08-05、「縦の空間をもっと詰めてほしい」という要望に対応):
  各行の`.padding(.vertical, 3)`、グループ見出し(`sourceGroup`の`Text(title)`)の上下
  パディングも`6/1`、`ScrollView`の`.padding(.top, 6)`と、いずれも詰めてある。
- **`Core/ThumbnailStore.swift`** — 動画の数秒地点のフレームと長さを非同期取得し、
  メモリ(`NSCache`)+ ディスク(`~/Library/Caches/MyTube/thumbnails/*.jpg`)にキャッシュする
  シングルトン。キャッシュキーは `SHA256("<パス>|<更新日時>")` — ファイルが更新されると
  キーが変わり自動的に再生成される(手動の無効化処理は持たない)。
  メモリキャッシュは `countLimit`(400枚、保険)に加えて `totalCostLimit`(150MB相当、
  実バイト数=幅×高さ×4で計算)で管理し、枚数ではなく実メモリ使用量で枯渇を防ぐ。
  さらに `DispatchSource.makeMemoryPressureSource` でシステムのメモリ逼迫通知を購読し、
  `.warning`/`.critical` を受けたら `memoryCache.removeAllObjects()` で即座に解放する
  (ディスクキャッシュは影響を受けないため、再表示時はディスクから読み直すだけで済む)。
  `loadDuration(for:)` はサムネイル画像を生成せず長さだけを取得する軽量版 ―
  `ContentView` の長さフィルターが有効な間、全動画分をバックグラウンドで先読みするために使う
  (画像デコードを伴わないため負荷は低いが、`limiter` はサムネイル生成と共有しているので
  同時実行数は変わらず4に抑えられる)。`durationCache`(NSCache)は既にヒットしていれば
  再フェッチしない。**生成失敗は`failedUntil`で10分間キャッシュし、同じキーへの再試行を
  抑止する**(2026-08-05追加 ― 以前は失敗を全くキャッシュしておらず、グリッドのスクロールで
  セルが再表示されるたびに`.task(id:)`が発火して同じリモート動画への失敗リクエストが際限なく
  繰り返されていたため、無駄なリトライの連打を防ぐガードを追加した)。
  **YouTube動画は`AVAssetImageGenerator`でのフレーム抽出をしない**(2026-08-05追加):
  未ダウンロードのYouTube動画は`VideoItem.url`が再生不可能なwatchページURLのため、そのまま
  `AVURLAsset`に渡しても失敗するだけ ― 代わりに`VideoItem.thumbnailURL`
  (`YouTubePlaylistClient`が設定する`https://i.ytimg.com/vi/<id>/hqdefault.jpg`)が
  非nilならそちらを`URLSession`で直接フェッチする(`fetchRemoteThumbnail`)。
  長さも同様に`VideoItem.knownDurationSeconds`(yt-dlpのプレイリストメタデータから
  取得済み)があればそれをそのまま使い、AVAssetでのプロービングを`loadDuration(for:)`ごと
  スキップする。ダウンロード完了後もサムネイルは公式画像のままで構わないため、この分岐は
  ダウンロード状態を見ない(常に`thumbnailURL`の有無だけで判定する)。
  **ディスクI/O・画像デコード・JPEGエンコードはメインスレッドで行わない**(2026-08-05、
  「最初のローディングのパフォーマンスが悪い」という要望に対応): `ThumbnailStore`自体は
  `@MainActor`(`NSCache`/状態の一貫性のため)だが、素朴に`Data(contentsOf:)`や
  `NSImage(data:)`、`NSBitmapImageRep.representation(using:properties:)`、
  `Data.write(to:)`を`@MainActor`なメソッドの中で直接呼ぶと、そのI/O・デコード・エンコード
  処理自体がメインスレッド上で同期的に実行されてしまう。特にディスクキャッシュの読み込みは
  アプリ再起動のたびに(ダウンロード等と違い`limiter`の外・無制限に)必ず通る経路で、
  グリッドへ一斉に表示される数十枚のキャッシュ済みサムネイルを読み込む際にメインスレッドが
  詰まり、初回ロード時の「もたつき」の主要因になっていた。`loadDiskImage`/`writeJPEG`/
  `decodeImage`/`writeData`という4つの`private static func`ヘルパーを追加し、実際の
  ファイルI/O・デコード・エンコードはすべて`Task.detached`のクロージャの中で行う
  (`Task.detached`は呼び出し元のアクターと無関係なスレッドで実行されるため、
  `@MainActor`なメソッドから呼んでも中身は確実にメインスレッド外で動く)。
  `NSImage`は`Sendable`適合がmacOS 14+限定(このアプリの最低ラインは`.macOS(.v13)`)なため、
  `Task.detached`のクロージャから直接返すとSendable警告が出る ― `ImageBox`
  (`@unchecked Sendable`な薄いラッパー、複数スレッドから同時にmutateしない用途に限定)で
  包んで警告を抑えている。メモリ使用量は増えない(既存のディスク/メモリキャッシュの構造その
  ものは変えず、処理を実行するスレッドを変えただけ)。**`generate(for:key:)`は所要時間を
  計測してログに出す**(2026-08-06追加、`Core/Log.swift`参照 ― ディスクキャッシュ読み込みも
  含めた1回ぶんの所要時間で、150ms超は`.notice`(体感できる遅さの目安)、以下は`.debug`
  (既定では非表示)に分けている。実際に生成が発生している(ディスクにもまだ無い)動画が
  多いフォルダを開くと、ここが最も時間のかかる処理になりやすい)。
- **長さフィルター**(`TopBarView` の「長さ」ボタン→ `Views/LengthFilterPopover.swift`):
  最小/最大秒数をテキスト入力で1秒単位に指定する。`ContentView.ensureDurationsLoaded()` が
  フィルター有効時に `allVideos` のうち長さ未取得の動画を `withTaskGroup` で並列に
  `ThumbnailStore.loadDuration` へ投げ、判明した端から `videoDurations`(`[URL: TimeInterval]`)
  に反映する ― `NSCache` ではなく通常の Dictionary で保持しているのは、メモリ逼迫時に
  `ThumbnailStore.durationCache` 側が破棄されてもフィルター結果の動画が消えないようにするため。
  `AVAssetImageGenerator.image(at:)` の async API(macOS 13+)を使い、生成の同時実行数は
  `Core/ConcurrencyLimiter.swift`(actor ベースの async セマフォ)で4に制限している
  (myorganizer の `VideoDupFinder`/`H265Encoder` が `DispatchSemaphore` で ffmpeg/ffprobe の
  同時実行数を絞っているのと同じ理由 — 制限なしだとグリッド表示時に大量の動画が
  一斉にデコードされてメモリを圧迫する)。同一動画への同時呼び出しは `inFlight` 辞書で
  1つの `Task` にまとめ、重複生成を避ける。デコードに失敗した動画(非対応コーデック等)は
  `image: nil` を返すだけでクラッシュしない — `VideoCardView`/`VideoTableView` は
  プレースホルダー(`film` シンボル)を表示し、それでも再生自体は試みられる(AVPlayer 側の
  対応コーデック判定はサムネイル生成とは独立)。
- **`Core/PlayerEngine.swift`** — `AVPlayer` の薄いラッパー。mymusic の
  `PlayerEngine.swift` と同じ設計方針(再生キューの中身は一切知らず、1本の再生と
  `onFinished` コールバックだけを持つ)。`load(url:)` は同じ URL が既に再生中なら
  何もしない(`PlayerPaneView` の `onChange(of: video)` が同一動画で再入した場合の
  無駄な再読み込み・再生位置リセットを防ぐ)。
  **再生失敗をポップアップで通知する**(2026-08-07追加、「再生できない場合があるけど、
  可能な限りポップアップでエラーを通知してほしい」という要望への対応 ― それまでは
  再生失敗が完全に無音で、映像が黒いまま止まる以外に手がかりが無かった)。`onError:
  ((String) -> Void)?` コールバックを追加し、2つの失敗経路をカバーする: ①再生を開始
  できない失敗(コーデック非対応・ファイル破損・ファイルが見つからない等)は
  `item.publisher(for: \.status)` を `load(url:)` ごとに(Combine で)購読し直し、
  `.failed` に遷移した瞬間 `item.error?.localizedDescription` を渡す ②一度再生が
  始まった後の失敗(ネットワーク切断でのストリーミング中断等、OneDrive の
  `@content.downloadUrl` の期限切れ等)は `.AVPlayerItemFailedToPlayToEndTime` 通知を
  購読し、`userInfo[AVPlayerItemFailedToPlayToEndTimeErrorKey]` からエラーを取り出す
  ― `.failed` ステータスだけでは①のケースしか拾えないため両方必要。いずれも
  `item`(`AVPlayerItem`)ごとに購読し直す必要があり、`load(url:)` の冒頭で前回の
  `itemFailedObserver`(`NotificationCenter`)/`itemStatusCancellable`(Combine)を
  破棄してから新しい `item` に対して張り直す(`itemEndObserver` の既存パターンを踏襲)。
  `PlayerPaneView` は `onAppear` で `engine.onError = { message in
  playbackErrorMessage = message }` を1回だけ設定し(`video`/`queue` を捕捉しないため
  `setupAutoplayNext()` と違って動画切り替えのたびに組み直す必要はない)、`.alert` で
  ポップアップ表示する(`deleteLocalCopyErrorMessage` の既存 alert と同じ
  `Binding(get:set:)` パターン)。
  **①②だけでは足りず、実際にリリース後すぐ「OneDrive系が全部再生できなくなってる」
  「(ポップアップは)今は何もでてない」という報告を受けた**(2026-08-07):
  OneDriveの署名付きURL(`@content.downloadUrl`)が期限切れ・アクセス拒否の場合、サーバーは
  HTTPエラー(403等、エラーページのボディ付き)を返すことが多いが、この応答は
  `AVPlayerItem.status`を`.failed`へ遷移させず`.unknown`のまま止まることがあり、かつ
  一度も再生が始まらないため`.AVPlayerItemFailedToPlayToEndTime`も発火しない ―
  ①②いずれの経路にも引っかからず、ポップアップが一切出ないまま黒画面で止まっていた。
  これに対応して2つ追加した: ③`.AVPlayerItemNewErrorLogEntry`通知(`errorLog()`が
  HTTPレベルのエラーで更新されるたびに飛ぶ)を購読し、最新の`errorLog()?.events.last`
  (`errorStatusCode`/`errorComment`)をメッセージ化する。④それでも拾えない場合の最後の
  保険として、`load(url:)`のたびに`Task`で15秒後に`item.status`を確認し、`player.currentItem`
  がまだその`item`(＝差し替えられていない)かつ`.unknown`のまま(＝readyToPlay/failed
  どちらにも進んでいない)なら「読み込みタイムアウト」としてエラー通知する
  (`readyTimeoutTask`、`weak item`で保持しリークしない)。①〜④の4経路すべてが
  `load(url:)`の冒頭で前回`item`ぶんのobserver/cancellable/Taskを破棄してから
  新しい`item`に対して張り直す(既存の`itemEndObserver`と同じパターン)。
  **失敗ポップアップの「再読み込み」ボタン**(2026-08-07追加、「通知してそのあと、どのように
  更新すればいい?」という質問への回答): OneDriveの再生失敗はほとんどが署名付きURLの期限切れ
  なので、通知するだけでなくその場で直せた方がよい。`PlayerPaneView`の`onError`ハンドラで
  `playbackErrorMessage`をセットするのに加え、失敗した`video`が`remoteKind == .oneDrive`
  なら alert に「再読み込み」ボタンを出す(YouTubeは対象外 ― 失敗原因が期限切れではなく
  ダウンロード失敗のため再スキャンでは直らない)。押すと`ContentView.retryPlayback(for:)`
  ([ContentView.swift](Sources/MyTube/ContentView.swift)参照)が呼ばれ、`video.remoteID`
  (再スキャンしても変わらない安定ID)から元の`RemoteSource`を逆引きし、既存の
  `openRemote(name:shareURL:kind:)`(「同じURLを再度開く=再スキャン」の経路、下記
  `ContentView.swift`の項参照)をそのまま呼んで新しい署名付きURLを取得する。完了後
  (`openRemote`に追加した`onComplete`コールバック経由)、同じ`remoteID`を持つ更新後の
  `VideoItem`で`selectedVideo`を差し替えるだけで、`PlayerPaneView`の`onChange(of: video)`が
  自動的に新しいURLで再生を再開する(`PlayerPaneView`側は「動画が変わった」以上のことを
  知る必要がない)。
- **`Views/PlayerPaneView.swift`**(2026-08-05、`WatchView.swift`から改名) —
  メイン画面上部に常駐する動画プレイヤー。`@StateObject private var engine = PlayerEngine()`
  を持つが、**このビュー自体は動画切り替え時に作り直されない**ことに依存している
  ―`ContentView` 側は `selectedVideo`(同じ `PlayerPaneView` の `video` パラメータ)を
  更新するだけで `PlayerPaneView` の型・位置は変わらないため、SwiftUI は同一インスタンスとして
  扱い `@StateObject` の `engine` を保持し続ける(＝別の動画に切り替えても `AVPlayer`
  インスタンスは使い回され、プレイヤー全体が再マウントされるちらつきが起きない)。
  **「YouTubeのように1ページにしたい」(視聴画面をホーム画面に統合してほしい)という
  要望を受けて、独立した「視聴ページ」から「ホーム画面に常駐するプレイヤー」へ改名・
  再設計した**(2026-08-05、`WatchView.swift` → `PlayerPaneView.swift`)。「戻る」ボタンの
  代わりに、プレイヤー領域右上の✕(`onClose`、`ZStack(alignment: .topTrailing)`でプレイヤー
  映像に重ねる)でプレイヤー自体を閉じる ― これは一貫して変わっていない。

  **レイアウトは2026-08-05〜06で3段階変化した**(`ContentView.swift`の項に「常に両方
  見せる/切り替える」の方針の変遷も参照 ― こちらはプレイヤー自身の中の配置の変遷):
  1. 2026-08-05、「再生画像を大きくとりたいので、周りの表示を右に囲い込むように移動」という
     要望で、プレイヤー下の1列だったタイトル・チャンネル・ダウンロード状態・自動再生トグル・
     再生速度メニューを右の`infoSidebar`(固定幅280pt→220pt、縦積み)へ移し、`playerArea`の
     `maxHeight`を420→560→720へ拡大。
  2. 2026-08-06、「Playerをできるだけ大きくしたい。YouTubeのように、次の動画リストは右に」
     という要望で、`infoSidebar`は廃止しタイトル等を`metadataRow`としてプレイヤーの下
     (横一列、`playerArea`と同じ横幅をフルに使える)へ戻す一方、右列は`upNextList`
     (次の動画、`UpNextRow`)専用に置き換えた。この時点では`upNextList`の高さを
     `playerArea`+`metadataRow`の実測高さ(`GeometryReader`+`PreferenceKey`)に合わせて
     収めていた ― `ContentView`がまだ`HomeVideosView`を常に表示する方針だったため、
     グリッドを隠さないための配慮だった。
  3. 同じく2026-08-06、`ContentView`側で「動画選択中は`HomeVideosView`を隠す」方針に
     変更した(`ContentView.swift`の項参照)のに伴い、上記の高さ調整が不要になったため
     `upNextList`を単純に`.frame(maxHeight: .infinity)`で画面下まで伸ばす形にした
     (`GeometryReader`/`PreferenceKey`/`leftColumnHeight`は削除済み)。`playerArea`を
     含む`body`のHStack自体も`.frame(maxHeight: .infinity, alignment: .top)`にして、
     `ContentView`のVStackが空けた縦のスペースをこのビュー全体で受け取るようにしている。

  最終的な`body`の構造:
  ```
  HStack(spacing: 12) {
      VStack { playerArea; metadataRow }   // 左カラム、幅は可変(残りを全部使う)
      upNextList                            // 右カラム、幅240pt固定・高さは画面下まで
  }
  .frame(maxHeight: .infinity, alignment: .top)
  ```
  `onAppear`/`onChange`/`onDisappear`/`confirmationDialog`/`alert`はこの最外周`HStack`に
  付けたまま変わらない。`upNextList`の中身は`queue`(オートプレイのキューと同じ、
  `filteredVideos`由来)から現在の`video`より後ろだけを取った`upNextVideos`を
  `UpNextRow`(小さいサムネイル`VideoThumbnailView(width: 120)`+タイトル2行+チャンネル名の
  単純な`Button`、`VideoCardView`と同じ「カード全体を1つのButtonで覆う」作り)で並べ、
  リストがその高さに収まらない分は内部の`ScrollView`でスクロールする。
  **YouTube動画はダウンロード完了まで再生を待つ**(2026-08-05追加、`play(_:)`参照):
  OneDrive/ローカルは`downloadStore.playableURL(for:)`を即座に`engine.load`へ渡すが、
  `video.remoteKind == .youtube`かつ未ダウンロードの場合は`engine.load`を呼ばず
  `engine.stop()`だけして`downloadStore.startDownloadIfNeeded(for:)`を呼ぶに留める
  (`DownloadStore`のドキュメント参照 ― YouTubeは映像+音声が別ストリームで配信されることが
  多くAVPlayerでは合成再生できないため)。ダウンロード完了の検知は`onChange(of:
  downloadStore.state(for: video))`(`video`/`onChange(of: video)`とは別のモディファイア)で
  行い、新しい状態が`.downloaded`になった瞬間に`play(video)`を呼び直して初めて
  `engine.load`が実行される。待機中はプレイヤー領域に`ZStack`で`YouTubeDownloadingOverlay`
  (進捗バー+ラベル)を重ねる。
  **オートプレイ(次の動画への自動遷移)の実装に注意**: `engine.onFinished` に
  `video`/`queue`/`isAutoplayEnabled` を捕捉したクロージャを渡すが、これを `onAppear` 時の
  1回だけに設定すると、状態が切り替わった後もクロージャは最初の値を捕捉したままになり
  古い状態を参照し続けてしまう(View 構造体自体は再生成されても `onAppear` は初回しか
  呼ばれないため)。そのため `setupAutoplayNext()` を `onAppear` と `onChange(of: video)`
  に加え `onChange(of: queue)`(2026-08-04追加)・`onChange(of: isAutoplayEnabled)`
  (2026-08-05追加)からも呼び直し、クロージャを常に最新の状態で再構築している。
  `queue`だけの変化は、動画は変えずサイドバーでチャンネルを切り替えた場合に起きる
  (`ContentView`は`selectedChannel`が変わっても`selectedVideo`はもう nil にしない ―
  下記参照)。`onChange`/`onAppear` は macOS 13 対応のため2引数版(`{ newValue in ... }`)を
  使う(`{ old, new in ... }` 形式は macOS 14+ 限定で `Package.swift` の `.macOS(.v13)` と
  ビルドエラーになる)。
  **「自動再生」トグル**(2026-08-05追加、「自動再生モードを追加してほしい」という要望への
  対応): 動画情報行(`PlaybackSpeedMenu`の左)に`Toggle("自動再生", isOn:
  $isAutoplayEnabled)`(`.toggleStyle(.switch)`)を置く(「次の動画」カラムが廃止された
  ため、当初あった見出し横の配置から動画情報行へ移設した)。`isAutoplayEnabled`は
  `Settings.autoplayEnabled`に永続化(既定`true` ― 従来からの「最後まで再生したら次の
  動画へ進む」という挙動をそのまま初期値にするため、`UserDefaults.bool(forKey:)`ではなく
  `object(forKey:) as? Bool ?? true`で未設定時のデフォルトを`true`にしている)。
  `setupAutoplayNext()`内で`isAutoplayEnabled`が`false`なら`onFinished`が即returnし、
  次の動画へは進まない(動画は最後のフレームで一時停止したまま止まる)。
  **再生中のチャンネル切り替えで再生が止まっていた不具合**(2026-08-04): サイドバー
  (`SidebarView`)は`ContentView`の`HStack`内に常時表示されており、`PlayerPaneView`表示中も
  隠れない。以前は`ContentView`が`.onChange(of: selectedChannel) { _ in selectedVideo =
  nil }`を持っており、再生中にチャンネルを選ぶとホーム画面へ強制的に戻され、
  `WatchView.onDisappear`(当時の名称)の`engine.stop()`で再生が止まってしまっていた。
  この行を削除し、チャンネル変更は`filteredVideos`(グリッド・オートプレイのキュー
  双方の元)を絞り込むだけにした ― 再生中の動画そのものには触れない。
  **スペースキーでの再生/一時停止**(`installSpacebarMonitor()`): `AVPlayerView` 自身も
  スペースキーに反応する仕様だが、それはビュー(またはその子)が first responder のときだけ ―
  検索欄にフォーカスが残っている等の理由で効かないことがある。フォーカス状態に依存せず
  確実に動かすため、`PlayerPaneView` の表示中だけ `NSEvent.addLocalMonitorForEvents(matching:
  .keyDown)` でアプリ全体のキーイベントを監視し、space(keyCode 49)を検知したら
  `PlayerEngine.togglePlayPause()` を直接呼んでイベントを消費する(`nil` を返す)。
  ローカルモニターは責任範囲がレスポンダーチェーンより手前のため、`AVPlayerView` 側の
  標準ハンドラと二重発火することはない。ただしテキストフィールド編集中までスペースを
  奪ってしまうと検索欄にスペースが打てなくなるため、firstResponder が `NSText` の場合は
  素通し(イベントをそのまま返す)している。`onAppear`/`onDisappear` でモニターの
  設置/解除を行う(プレイヤーを✕で閉じると`PlayerPaneView`自体が破棄されるため、
  `onDisappear` で確実に解除しないとリークする)。
  **`NativeVideoPlayerView` に `.id(video.id)` が必須**(2026-08-02、ユーザー報告で発覚):
  「ホーム画面のグリッドから初めて動画をクリックすると、選んだのと違う動画(前に見ていた
  動画)が再生される」という不具合があった。タイトル等のテキスト表示は正しく新しい動画に
  切り替わるのに、映像だけ前の動画のまま止まる — `replaceCurrentItem` 自体は正しく
  呼ばれているが、AVKit-SwiftUI ブリッジ側がネイティブ再生ビューの再描画を取りこぼす
  既知の癖と見られる(この直前に踏んだ `_AVKit_SwiftUI` の demangle クラッシュ
  (FB8928032、上記)と同じ枠組みの不安定さの一種と推測)。`.id(video.id)` を付けて
  動画が変わるたびにネイティブビューそのものを作り直すことで解消した(根本原因の完全な
  特定はできていないが、実機で再現しなくなったことを確認済み)。
- **`Views/NativeVideoPlayerView.swift`** — `AVKit.VideoPlayer`(SwiftUI、
  `_AVKit_SwiftUI.framework` 経由)ではなく `AVPlayerView`(AppKit)を直接
  `NSViewRepresentable` でラップしている。理由は2つ:
  1. `showsFullScreenToggleButton`(既定 false)を true にしたい ―`VideoPlayer` はこの
     プロパティを公開する手段を持たない。true にするだけでコントロールバーに
     フルスクリーン切り替えボタンが現れ、実際の全画面遷移(専用ウィンドウでの表示)まで
     AVKit が内部で処理する。こちらで `NSWindow` のフルスクリーン制御を書く必要はない。
  2. `_AVKit_SwiftUI` を経由しない分、同フレームワークの不安定さ(下記クラッシュ、
     上記のフレーム描画の癖)を踏む経路自体が減る副次的なメリットもある。
  `Package.swift` の `linkerSettings: [.linkedFramework("AVKit")]` は
  `AVPlayerView` 自体(AVKit フレームワーク)の話であり、`VideoPlayer` を使わなくなった
  今も必要 — 外さないこと。
- **ミニプレーヤーモード**(2026-08-07追加、「常に最前面表示のミニプレーヤーモード」という
  要望への対応)。macOSネイティブのPicture-in-Picture(`AVPlayerView`が自動で提供するボタン)
  ではなく、**ウィンドウ自体を小さくして`NSWindow.level = .floating`にする**方式で実装した
  ― ネイティブPiPはmacOS上の`AVPlayerView`では有効化・トリガーを明示的にコードから
  制御するAPIが公開されておらず(iOSの`AVPlayerViewController.allowsPictureInPicturePlayback`
  に相当するものが無い)、確実に動く保証がなかったため。
  - **状態は`ContentView`の`@State private var isMiniPlayerMode`**(`PlayerPaneView`へは
    `Binding`で渡す)。オンの間、`ContentView.body`は`TopBarView`/`SidebarView`(+その間の
    `Divider`)を描画せず、`PlayerPaneView`を包む`VStack`の`.frame(maxWidth: .infinity,
    maxHeight: .infinity)`も外す。`PlayerPaneView.body`は`miniPlayerBody`
    (`NativeVideoPlayerView` + 拡大アイコン/✕の2ボタンのみ、下記のリサイズ可能な`.frame` +
    `aspectRatio(16/9)`)を返し、`metadataRow`/`upNextList`は描画しない。
  - **ミニプレーヤーへ入るボタンは`TopBarView`側にある**(2026-08-07、「トップバーにボタンを
    おいて」という要望への対応。当初はプレイヤー右上に`pip.enter`アイコンを重ねていたが、
    常時見えるトップバーの方が見つけやすいためこちらへ移した)。`TopBarView`は
    `isMiniPlayerAvailable: Bool`(`ContentView`が`selectedVideo != nil`を渡す ― 動画再生中
    しか意味を持たないボタンのため)と`onEnterMiniPlayer: () -> Void`
    (`{ isMiniPlayerMode = true }`)を受け取り、`sidebar.left`トグルの隣に`pip.enter`アイコンの
    ボタンを置く(未再生時は`.disabled`)。**ミニプレーヤーから元に戻すボタンは逆の場所には
    置けない**(ミニモード中は`TopBarView`ごと描画されていないため) ― `PlayerPaneView`の
    `miniPlayerBody`側、動画右上の拡大アイコンのボタン(下記参照)が担う。
  - **ウィンドウが自動的に縮む理由**: `Main.swift`の`.windowResizability(.contentSize)`が、
    SwiftUIツリーの ideal サイズの変化に`NSWindow`のフレームを追従させる仕組みを最初から
    使っている(通常モードの`1180×760`という`.defaultSize`もこれに乗っている)。上記の
    `.frame(maxWidth: .infinity, ...)`を外すことで`miniPlayerBody`の実サイズが
    そのままツリー全体の ideal サイズになり、手動で`NSWindow.setFrame`を呼ばなくても
    ウィンドウが動画サイズまで縮む。**`ContentView.body`の`VStack`/`HStack`階層自体は
    常に同じインスタンスのまま**(`if isMiniPlayerMode`で丸ごと差し替えたりはしない)
    ― `TopBarView`/`SidebarView`の描画有無だけを`if`で切り替えている。仮に`ContentView.body`
    トップレベルを`if isMiniPlayerMode { PlayerPaneView(...) } else { 通常のVStack }`のように
    丸ごと分岐させると、`VStack`に付いている`.onAppear { restoreOpenSources() }`等が
    モード切り替えのたびに再度発火し、開いているOneDrive/YouTubeソースをミニモードの
    出入りごとに毎回再スキャン・再取得してしまう ― 意図的にツリーを分岐させていない。
  - **ミニプレーヤーはサイズ変更可能**(2026-08-07、「ミニプレーヤーのサイズは変更可能に」
    という要望への対応)。`miniPlayerBody`の`.frame`は固定幅(旧`width: 360`)ではなく
    `minWidth: 240, idealWidth: 360, maxWidth: 960`という範囲を持つ ―
    `.windowResizability(.contentSize)`はこの範囲をそのままウィンドウの最小/理想/最大サイズに
    使うため、ウィンドウ端をドラッグしてこの範囲内で自由にリサイズできる。16:9比を保ったまま
    伸縮する見た目は`.aspectRatio(16/9, contentMode: .fit)`(SwiftUI側、ウィンドウサイズが
    変わるたびに再計算される)だけに任せている ― **`NSWindow.contentAspectRatio`は使わない**
    (2026-08-07、当初はAppKit側でも16:9を固定してドラッグ中の一瞬の黒帯を防いでいたが、
    ①ネイティブzoomアニメーションと組み合わせてクラッシュする、②通常モードに戻っても
    `.zero`が完全には効かずドラッグリサイズで高さが縮み続ける、という2つの実機不具合が出た
    ため撤去した。詳細は下記`WindowLevelAccessor`の項)。
  - **「常に最前面」・サイズ退避/復元はSwiftUIの`WindowGroup`に相当するAPIが無いため
    `WindowLevelAccessor`(`ContentView.swift`末尾の`private struct`、`NSViewRepresentable`)
    でAppKitへ橋渡しする**(`NativeVideoPlayerView`がAVKitを直接ラップしているのと同じ
    「無い機能はAppKitへ薄く橋渡しする」方針)。不可視の`NSView`を`ContentView`の
    `.background`に仕込み、`view.window`から実際の`NSWindow`を取得して`level`
    (`.floating`/`.normal`)・`collectionBehavior`(`.canJoinAllSpaces`/
    `.fullScreenAuxiliary`を足す ― 他のSpace・フルスクリーン中の別アプリの上にもミニ
    プレーヤーを表示したいため)を直接書き換える。`makeNSView`/`updateNSView`のどちらも
    `view.window`がまだ`nil`な瞬間があるため`DispatchQueue.main.async`越しに適用する。
    - **位置は通常モードからミニモードへ入った瞬間だけ**画面右下へ寄せる(2026-08-07、
      「ボリューム(デスクトップの外部ドライブ等のアイコン、右上に出る)と被ってる」という
      報告への対応 ― 当初は元の大きいウィンドウの位置をそのまま引き継いで縮むだけだったため、
      ウィンドウが画面上部にあると縮んだ後も上部に残り、デスクトップ右上のボリューム
      アイコンと重なっていた)。`.windowResizability(.contentSize)`によるサイズ追従が
      非同期に効くため、位置決め(`positionAtBottomRight`)は0.05秒遅延させて縮んだ後の
      サイズを基準にしている。
    - **サイズ・位置は`Coordinator.savedFrame`に退避し、ミニモード終了時に明示的に
      `setFrame`で復元する**(2026-08-07、「戻るときのサイズはミニプレーヤー前のサイズ」
      という要望への対応)。`.windowResizability(.contentSize)`に任せるだけだと、通常モードの
      `ContentView`は`.frame(maxWidth: .infinity, maxHeight: .infinity)`で「使える分だけ
      広げたい」という以上の具体的な ideal サイズを持たないため、縮んだウィンドウが元の
      大きさまで自動的に戻る保証がない ― 代わりに`window.level != .floating`(＝ミニモードへ
      入る遷移の瞬間)を判定条件にして`window.frame`をそのまま退避しておき、
      `window.level == .floating`から`.normal`へ戻る遷移の瞬間にその退避フレームを
      `setFrame(_:display:animate:)`で書き戻す。**`savedFrame`は`WindowLevelAccessor`
      struct自身ではなく`Coordinator`(`makeCoordinator()`が返す参照型、`updateNSView`を
      跨いで状態を保持できる)に持たせる**必要がある ― `WindowLevelAccessor`はSwiftUIが
      再描画のたびに作り直す値型のため、structのプロパティでは前回の値を跨いで覚えられない。
      いずれの判定も「既に同じモード中の再描画では何もしない」ようにしてある(そうしないと
      ユーザーが手動でウィンドウを動かしても次の再描画で退避時の位置に引き戻されてしまう)。
      **`setFrame`での復元自体は0.05秒遅延させている**(2026-08-07、「ミニプレーヤーから
      戻ってきたら、ウィンドウの高さが小さくなる」という報告への対応 ― 通常モードに戻った
      直後、`ContentView`が`.frame(maxWidth: .infinity, maxHeight: .infinity)`に戻った
      SwiftUIツリーに対して`.windowResizability(.contentSize)`が独自にウィンドウサイズを
      再計算・同期しようとすることがあり、即座に`setFrame`するとその直後にSwiftUI側の
      自動リサイズに上書きされて元より低い高さに縮んでしまう不具合が実機で確認された。
      `positionAtBottomRight`と同じ理由で、短い遅延を挟んでSwiftUI側の再計算を先に
      終わらせてから最後に退避しておいたフレームで上書きすることで解消した)。
    - **ネイティブzoom(緑ボタン・タイトルバーのダブルクリック)はミニプレーヤー中
      `NSWindowDelegate.windowShouldZoom(_:toFrame:)`で止める**(2026-08-07、「緑のボタンを
      押すとクラッシュします」→さらに「タイトルバーのダブルクリックでもクラッシュする」という
      2件のクラッシュレポートへの対応)。ミニプレーヤー中は当初有効にしていた
      `contentAspectRatio`(16:9固定)と`miniPlayerBody`の`.frame(minWidth: 240, maxWidth:
      960)`(`.windowResizability(.contentSize)`経由でウィンドウの最小/最大サイズにもなる)が
      同時に効いている状態で、標準のzoomを行うとAppKit純正の`-[NSWindow _zoomToScreen:
      isMoveToiPad:]`(画面いっぱいへズームするアニメーション)がこれらの制約と衝突し、
      `-[NSWindow _adjustNeedsDisplayRegionForNewFrame:]`内でクラッシュすることが実機の
      クラッシュレポート(EXC_BREAKPOINT/SIGTRAP、macOS 26.5.2)で確認された。**当初は
      `window.standardWindowButton(.zoomButton)`の`target`/`action`を乗っ取る方式だった
      が、タイトルバーのダブルクリックによるzoom(`-[NSTitledFrame
      _handlePossibleDoubleClickForEvent:onlyZoomInDragRegion:]`)はボタンを経由せず直接
      `_zoomToScreen:`を呼ぶため、ボタン側の乗っ取りだけでは防げないことが2件目のクラッシュ
      レポートで判明した。** `windowShouldZoom(_:toFrame:)`はzoomのトリガー経路(ボタン
      クリック・タイトルバーのダブルクリックのどちらでも)AppKitが実際にリサイズする**前**に
      必ず呼ぶ公式の関門のため、ここで`false`を返せばトリガー経路によらずクラッシュする
      ネイティブzoomアニメーション自体を確実に止められる。ミニプレーヤー中に`false`を返す
      ついでに`onZoomButtonClicked`(`ContentView`が`{ isMiniPlayerMode = false }`を渡す)を
      呼ぶことで、「zoomしようとしたらミニプレーヤーを解除する」という動作も実現している
      (結果として、緑ボタン・タイトルバーのダブルクリックのどちらでも動画右上の拡大
      アイコンのボタンと同じ「元のサイズに戻る」が実行される)。**`window.delegate`は他に何か
      (SwiftUIの内部実装など)が既に使っている可能性があるため、奪うのではなく
      `Coordinator`(`NSObject`を継承し`NSWindowDelegate`に準拠)を割り込ませて、
      `windowShouldZoom`以外のメソッドは`responds(to:)`/`forwardingTarget(for:)`
      (Objective-Cのメッセージ転送の仕組み)で元の`delegate`(`previousDelegate`に退避
      済み)へ転送する**。`window.delegate !== coordinator`のときだけ現在の`delegate`を
      `previousDelegate`に退避してから差し替える(何か他のものが割り込んで上書きしていた
      場合の保険も兼ねる。一度差し替えた後は`window.delegate === coordinator`なので
      再取得・再差し替えはしない)。同じ`Coordinator`が`savedFrame`(位置・サイズ退避)と
      `isMiniModeActive`(zoom可否の判定)の両方を持つため、`apply`の中で
      `coordinator.isMiniModeActive = isFloatingOnTop`を毎回更新している。
  - **プレイヤーを閉じたら自動でミニモードも解除する**: `miniPlayerBody`の✕ボタンは
    `isMiniPlayerMode = false`してから`onClose()`を呼ぶ。念のため`ContentView`の
    `.onChange(of: selectedVideo)`にも`newValue == nil`なら`isMiniPlayerMode = false`する
    保険を入れてある(他の経路―`TopBarView`の「MyTube」ロゴでホームに戻る等―で
    `selectedVideo`が`nil`になった場合でも、ミニモードのまま巨大な`HomeVideosView`が
    小さいウィンドウに押し込まれる事態を防ぐため)。
  - **`engine`(`PlayerEngine`)はミニモードの往復で失われない**: `PlayerPaneView`自体は
    `if isMiniPlayerMode`で内部の`body`を出し分けているだけで、ビュー自体は再生成されない
    ため`@StateObject private var engine`は保持され続け、モード切り替えの瞬間も再生が
    途切れない(`NativeVideoPlayerView`に付けている`.id(video.id)`は`miniPlayerBody`側にも
    同じく付けてあるが、モード切り替えでネイティブ再生ビュー自体は作り直される ―
    `AVPlayer`は共有されたまま繋ぎ直されるだけなので、瞬間的に映像が止まって見える程度で
    実害はない)。
- **`Core/PlayerEngine.swift` の再生速度(`playbackRate`)**: `AVPlayerView` 標準の
  再生/一時停止ボタンは、押されるたびに `player.rate` を無条件で `1.0` にリセットする
  仕様(AVKit 側の挙動で、こちらから変更できない)。そのため単純に `player.rate = 1.5` と
  設定するだけでは、ユーザーが標準ボタンで一時停止→再開した瞬間に速度が 1.0x に戻って
  しまう。`PlayerEngine.init` で `player.publisher(for: \.rate)`(Combine の KVO
  パブリッシャー)を購読し、`rate` が選択中の `playbackRate` 以外の非ゼロ値に変わったら
  即座に選択中の値へ書き戻すことで、標準ボタンを使っても速度設定が保たれるようにしている。
  `setPlaybackRate(_:)` は一時停止中に呼ばれた場合 `player.rate` を直接書き換えない
  (非ゼロを代入すると一時停止中でも再生が始まってしまうため)― 値だけ `playbackRate` に
  保存し、実際の適用は次に再生が始まったタイミング(上記の Combine 購読)に委ねる。
  `playbackRate` は動画を切り替えても(同一 `PlayerPaneView`/`engine` インスタンスが続く限り)
  保持される(YouTube と同じ「次の動画も同じ速度で再生される」挙動)。`PlaybackSpeedMenu.swift`
  がこの値を選ぶ UI(0.5x〜2.0x)。
- **`Core/OneDriveShareClient.swift`** — OneDriveの「リンクを知っている全員」共有リンクを、
  ブラウザにサインインせずスキャンして`VideoItem`一覧を得る(2026-08-04追加)。ブラウザの
  開発者ツールでの通信解析で判明した3ステップ: ①`api-badgerp.svc.ms/v1.0/token`に固定の
  appId(公開値、OneDrive Web クライアント自身のJSにハードコードされているもの)を渡すと、
  サインイン不要の匿名トークン("Badger"スキーム)が発行される ②共有URLを独自の
  `u!<base64url>`形式にエンコードして`my.microsoftpersonalcontent.com/_api/v2.0/shares/
  {encoded}/driveitem`に`Prefer: autoredeem`付きでPOSTすると`driveId`/`itemId`が返る
  (この呼び出し自体が「このトークンをこの共有に対して読み取り許可する」副作用を持つため、
  以降のAPI呼び出しは同じトークンを使い回す必要がある。別トークンだとaccessDenied) ③
  `/drives/{driveId}/items/{itemId}/children`をGETすると、`@content.downloadUrl`
  (tempauth署名付き、追加認証なしで直接ストリーミング可能なURL、有効期限は実測1時間程度)
  付きでフォルダの中身が返る。フォルダを再帰的に辿り、`VideoScanner`と同じ「共有フォルダ
  直下のサブフォルダ名=チャンネル」規約で`VideoItem`を組み立てる(共有リンクが動画ファイル
  単体を指している場合は`fetchItem`で単一アイテムを取得するフォールバックあり)。
  いずれのエンドポイントも、Microsoftが第三者向けに公開しているGraph APIではなくOneDrive
  Webクライアント自身が使う**内部API**(`Origin`/`Referer`が`onedrive.live.com`であることを
  サーバー側で検証しているのをcurlでの検証で確認済み、単なるブラウザCORSの制約ではない)
  のため、予告なく仕様変更・遮断される可能性がある。`@content.downloadUrl`の短い有効期限
  ゆえ、フォルダ読み込みから時間が経ってからの再生は失敗しうる(既知の制限。再生直前の
  再取得は未実装)。`VideoItem.remoteID`(このアイテムID)が非nilの動画はローカルファイルと
  区別され、`ThumbnailStore.cacheKey`はURLではなくこのIDを使う(`@content.downloadUrl`は
  トークン再発行のたびにクエリ文字列だけ変わり、`.path`も全ファイル共通の
  `_layouts/15/download.aspx`にしかならずキャッシュキーに使えないため)。`VideoCardView`は
  `remoteID`が非nilの動画には共有元ファイルの直接削除メニューを出さない(共有元のファイルを
  操作する手段がないため。代わりに`DownloadStore`のローカルコピー削除を出す ―
  `Core/DownloadStore.swift`の項参照)。UIは`Views/OpenRemoteLinkSheet.swift`
  (`TopBarView`の「OneDrive Link」ボタンから開くシート。旧`OpenShareLinkSheet.swift` ―
  2026-08-05にYouTube用と共用できるよう汎用化・改名した、下記参照)+
  `ContentView.openRemote(name:shareURL:kind:)`(複数の共有リンクを同時に開ける設計 ―
  `ContentView.swift`の項参照)。リンクの**登録**(保存して後から選べるようにする)と
  **オープン**(実際に読み込んで画面に表示する)は別概念: `SharedLinkBookmark`(名前+URL、
  `Models.swift`)として複数件`Settings.sharedLinkBookmarks`にJSON(UserDefaults)で
  永続化するのが登録一覧(renamerのpresets.jsonのような専用ファイルではなく、件数・構造とも
  単純なためUserDefaultsで十分と判断)。`OpenRemoteLinkSheet`は登録済み一覧(名前をクリックで
  そのまま`onSelect`→オープン、ゴミ箱アイコンで`onDelete`=登録解除)と、新規登録フォーム
  (名前+URL→「登録して開く」で`ContentView.addOneDriveBookmarkAndLoad(name:url:)`が登録と
  同時にオープンまで行う)を1つのシートにまとめている。表示名(`RemoteSource.name`、
  チャンネル名のプレフィックスにも使う)はOneDrive側の実際のフォルダ名
  (`OneDriveShareClient.scan`が返す`sourceName`)ではなく、ユーザーが登録時に付けた`name`を
  使う ― ユーザーが選ぶ手がかりは登録名の方であり、OneDrive側のフォルダ名(例えば共有元で
  後から改名されうる)と一致している保証がないため。
  **全リクエストに`cachePolicy = .reloadIgnoringLocalCacheData`を付けている**
  (2026-08-20追加、「タイトルが実際のファイル名と全く違う古い名前になる」というユーザー
  報告への対応 ― `URLSession.shared`は既定で`URLCache.shared`を使うため、`children`
  (フォルダ中身)取得のGETは同じフォルダなら毎回同一URLになり、サーバーがキャッシュ可能な
  レスポンスを返していた場合、OneDrive側でファイルを追加・削除・リネームした後に🔄
  「再スキャン」を押しても、ネットワークへ問い合わせずキャッシュに残っていた古い
  レスポンスがそのまま返っていた可能性がある。トークン発行・共有解決のPOSTを含む全4
  リクエストに付けて、再スキャンが名実ともに「最新を取り直す」操作になるようにした)。
- **`Core/RemoteListCache.swift`**(2026-08-20追加、上記のキャッシュ無効化とセットで
  対応 ― キャッシュを外した副作用として、起動のたびに`OneDriveShareClient.scan`/
  `YouTubePlaylistClient.fetchPlaylist`の実ネットワーク往復(大きいフォルダだと数十秒)が
  必ず発生するようになり、その間`SidebarView.sourceGroup`は動画0件のグループを見出し
  ごと出さない仕様のため「起動直後、OneDriveのセクションが丸ごと表示されない」という
  体感になっていた。「前回の一覧をキャッシュして再起動時にまず出し、裏で最新に
  リフレッシュしては」という提案への対応): `ContentView.openRemote`が新規にソースを
  開く(初回オープン)ときだけ使う、完全に別レイヤーのstale-while-revalidateキャッシュ。
  `~/Library/Caches/MyTube/remote-list-cache/<SHA256(共有URL)>.json`
  (`ThumbnailStore.cacheKey`と同じSHA256方式)に`sourceName`+`VideoItem`配列をJSONで
  保存するだけの薄いenum。`openRemote`は`RemoteSource`を新規追加する際、まず
  `RemoteListCache.load(for:)`があればそれを`videos`の初期値にして即座に表示し
  (`isLoadingWithNothingToShow`は`allVideos.isEmpty`が条件なので、この時点で
  `allVideos`が空でなくなり全画面ローディングにもならない)、その裏で今まで通り
  `scan()`/`fetchPlaylist()`を必ず実行する。成功したら`remoteSources[index].videos`を
  新しい結果で上書きするのと同時に(`Task.detached`でメインスレッド外から)
  `RemoteListCache.save(...)`を呼び直し、次回起動用に更新する ― 古いデータが表示され
  続けることはなく、スキャンにかかる数秒〜数十秒だけ前回の一覧が見える。**既に開いている
  ソースの再スキャン(🔄ボタン、`openRemote`の`if`ブランチ)ではこのキャッシュを触らない**
  (今表示中のものをそのまま残せば十分なため)。`VideoItem`/`RemoteKind`を`Codable`に
  適合させたのはこのため(`Models.swift`)。OneDrive動画の`url`(`@content.downloadUrl`)は
  署名付きURLで1時間程度で失効するため、キャッシュから復元した項目を新しいスキャン結果が
  上書きする前にユーザーが再生しようとすると失敗しうるが、その場合は既存の
  `PlayerEngine`の再生失敗検知+「再読み込み」ボタン(`Core/PlayerEngine.swift`の項参照)
  がカバーする。
- **`Core/ToolLocator.swift`**(2026-08-05追加) — `downloader/Sources/Downloader/
  ToolLocator.swift`をそのまま移植したもの(Homebrewの既知パス→ログインシェルの`which`の
  順で`yt-dlp`/`ffmpeg`を探索)。`Core/YouTubePlaylistClient.swift`のプレイリスト取得と
  `Core/DownloadStore.swift`のYouTubeダウンロードの両方が使う。
- **`Core/YouTubePlaylistClient.swift`**(2026-08-05追加) — `yt-dlp --flat-playlist
  --dump-json`でYouTubeプレイリスト(単体動画のURLでも「1件だけのプレイリスト」として同じ
  形で扱われる)を軽量にスキャンし`VideoItem`一覧を返す。`--flat-playlist`は各動画の実際の
  配信フォーマットを解決しない(=個々の動画ページを開かない)ため、数百本規模のプレイリスト
  でも数秒〜十数秒で列挙できる(`downloader`の`YtDlpManager.fetchTitle`が単発タイトル取得に
  使っているのと同じ考え方)。1行1JSONのNDJSON出力を`JSONDecoder`
  (`.convertFromSnakeCase`)で1行ずつデコードし、パースに失敗した行(コメント行や空行)は
  読み飛ばす。`--ignore-errors`でプレイリスト中の非公開・削除済み動画1本のエラーが
  全体の失敗にならないようにしている。ここで取得するのは一覧(id/タイトル/長さ/サムネURL)
  だけで、**実際のダウンロード(動画+音声の取得・結合)はしない**(下記
  `Core/DownloadStore.swift`が再生時に別途yt-dlpを起動する)。各`VideoItem`の
  `remoteID`はyt-dlpの動画ID、`url`は`https://www.youtube.com/watch?v=<id>`
  (未ダウンロード時は`PlayerPaneView`がこのURLを`PlayerEngine`に渡さないよう明示的にガードして
  いる ― 単なるwatchページで再生可能なストリームURLではないため。下記`Views/PlayerPaneView.swift`
  の項参照)、`thumbnailURL`は`https://i.ytimg.com/vi/<id>/hqdefault.jpg`
  (`ThumbnailStore`がフレーム抽出の代わりに直接フェッチする)、
  `knownDurationSeconds`はyt-dlpのメタデータの`duration`をそのまま使う。
- **`Core/DownloadStore.swift`**(2026-08-04追加、2026-08-05にYouTube対応・OneDriveの
  トグル化を追加) — リモート動画をローカルへダウンロードして保存する`@MainActor
  ObservableObject`シングルトン。**OneDriveとYouTubeでダウンロード方式・再生とダウンロードの
  関係が異なる**(`video.remoteKind`で`startHTTPDownload`/`startYouTubeDownload`に分岐):
  - **OneDrive**: 再生自体はダウンロード完了を待たず即座に始まる ―
    `@content.downloadUrl`への直接ストリーミングは変わらず、ダウンロードは並行して走るだけ。
    `URLSession.shared.downloadTask`(バックグラウンドセッションではない ― アプリを閉じれば
    中断される。`downloader`/`mymusic`のような常駐設計ではなくウィンドウを閉じれば
    アプリごと終了する`mytube`の性質上、これで十分と判断)で、完了時に一時ファイルを
    `FileManager.moveItem`で保存先へ移動する。**ダウンロードは自動では始まらない**
    (2026-08-05、「OneDriveの場合はローカルに保存はトグルにする。デフォルトでは
    ローカルダウンロードはOff」という要望への対応 ― 以前は`PlayerPaneView.play(_:)`が
    再生開始のたびに無条件で`startDownloadIfNeeded(for:)`を呼んでいたが、今は
    `Views/LocalSaveToggle.swift`のトグルをONにしたときだけ呼ぶ。再生自体は上記の通り
    ダウンロード状態と無関係にストリーミングで即座に始まるため、トグルをOFFのままでも
    視聴に支障はない)。トグルをOFFにする操作は`disableLocalSave(for:)`が受け、状態に
    応じて`cancelDownload(for:)`(ダウンロード中の`URLSessionDownloadTask`を`cancel()`
    してから`.notDownloaded`に戻す)か`deleteLocalCopy(for:)`(ダウンロード済みならゴミ箱へ)
    のどちらかに振り分ける ― 呼び出し元(`LocalSaveToggle`)が確認ダイアログでYesを選んだ
    後に呼ぶ。**`finishHTTPDownload`はHTTPステータスコードを検証する**(2026-08-05、
    ユーザー報告「トグルの表示サイズがFinderの実際のファイルサイズと合わない」で発覚・
    修正 ― `URLSession`はHTTPステータスが4xx/5xx(`@content.downloadUrl`の期限切れ・
    アクセス拒否等)でも`error`をnilのまま返す(ネットワーク層のエラーではないため)。
    修正前はステータスを見ずに受け取った`tempURL`をそのまま`destination`へ移動していたため、
    OneDriveが返す短いエラーレスポンス(HTML/JSON)を動画本体として保存してしまい、
    実際のダウンロードフォルダに数十バイトしかない`.mp4`が生成されていた。
    `response as? HTTPURLResponse`のステータスが200〜299の範囲外なら`.failed`にして
    保存自体を行わないようにした)。
  - **YouTube**: 映像+音声が別ストリームで配信されることが多くAVPlayerでは単純に合成
    再生できないため、`yt-dlp`(`Core/ToolLocator.swift`で探索)を`Process`として起動し、
    `bestvideo[vcodec^=avc1][height<=1080]+bestaudio[acodec^=mp4a]/best[vcodec^=avc1]
    [height<=1080]/best[vcodec^=avc1]/best`のフォーマットを`--merge-output-format mp4`で
    `ffmpeg`結合しながら`-o`で保存先へ直接書き出す(`downloader/Sources/Downloader/
    YtDlpManager`と同じ「`--newline`の進捗行を`[download]  42.1% of ...`の形からパースする」
    方式、`readabilityHandler`はバックグラウンドキューで呼ばれるため`parseDownloadPercent`は
    `nonisolated`にしている)。**`[vcodec^=avc1]`(H.264)を明示的に要求する必要がある**
    (2026-08-05、ユーザー報告「音は出るが映像が出ない」で発覚・修正 ― コーデック指定なしの
    `bestvideo`だと、YouTubeが同じ解像度でもVP9/AV1(webmコンテナ)の映像ストリームを
    「best」として返すことが多く、`--merge-output-format mp4`でコンテナをmp4に詰め直しても
    中身のコーデック自体はVP9/AV1のまま。`AVFoundation`/`AVPlayer`はVP9・AV1のデコードに
    対応していないため映像トラックだけデコードできず、音声(Opus/AAC、対応コーデック)だけ
    再生される状態になっていた)。
    `PlayerPaneView.play(_:)`は`.downloaded`になるまで`engine.load`を呼ばずに待機し、
    `onChange(of: downloadStore.state(for: video))`が`.downloaded`への遷移を検知して
    初めて再生を開始する(下記`Views/PlayerPaneView.swift`の項参照)。
  いずれの方式でも`states: [String: State]`(キーは`VideoItem.remoteID`)を`@Published`
  で持ち、`.notDownloaded`/`.downloading(progress:)`/`.downloaded`/`.failed`の4状態を
  `VideoCardView`(サムネイル左上のバッジのみ ― ダウンロード操作自体はグリッドには出さない、
  下記`Views/LocalSaveToggle.swift`の項参照)と`PlayerPaneView`(OneDriveは`LocalSaveToggle`・
  YouTubeは`DownloadStatusLabel`+プレイヤー領域の`YouTubeDownloadingOverlay`)が購読して
  表示する。

  **`state(for:)`は`states`へ書き込まない/`primeStates(for:)`でまとめて先読みする**
  (2026-08-06、「パフォーマンスが悪い」という報告への対応)。以前は`state(for:)`が
  キャッシュミス時に`FileManager.fileExists`でディスクを見て`states[remoteID] = .downloaded`と
  直接書き込んでいたが、この関数は`VideoThumbnailView.body`から(`.task`等を介さず)
  同期的に呼ばれる ― 前回のセッションでダウンロード済みのリモート動画がグリッドに多数
  並ぶ初回表示やスクロールのたびに、SwiftUIのビュー更新中に`@Published var states`を
  変更することになり(SwiftUIが警告する「Publishing changes from within view updates」)、
  `DownloadStore.shared`を`@ObservedObject`で購読している他の全セルの再描画をそのたびに
  連鎖的に誘発していた。ディスク上の既存ダウンロードの発見は`primeStates(for:)`
  (`ContentView.openRemote`がリモートソースの動画一覧を確定した直後に1回呼ぶ)へ移し、
  複数件見つかっても`states`への代入は最後に1回だけ(ローカル変数`updated`に集約してから
  丸ごと差し替える)行うことで`objectWillChange`の発火を1件ずつではなく1回に抑えている。
  `state(for:)`自体は読み取り専用になり、`primeStates`がまだ終わっていない一瞬だけ
  ディスクを直接見るフォールバック(書き込みはしない)を残してある。所要時間は
  `Log.download`(`Core/Log.swift`参照)に出る。保存先は
  `~/Library/Caches`ではなく`~/Library/Application Support/MyTube/downloads/`
  (`ThumbnailStore`のサムネイルと違い、ユーザーが明示的に保持したいデータであり、
  ディスク逼迫時にOSが気軽に破棄してよいCachesは不向きなため)。ファイル名は
  `<remoteID>.<拡張子>`(`VideoItem.fileExtension`、`OneDriveShareClient.toVideoItem`/
  `YouTubePlaylistClient.fetchPlaylist`/`VideoScanner.scan`いずれも設定 ―
  OneDriveの`url`=`@content.downloadUrl`はパス自体が`download.aspx`のような固定文字列で
  拡張子を含まないため、YouTubeは`--merge-output-format mp4`で拡張子が`mp4`固定のため、
  どちらも`url.pathExtension`に頼れず専用フィールドが必要だった)。`playableURL(for:)`は
  ダウンロード済みならローカルファイルのURLを、そうでなければ`video.url`(OneDriveなら
  ストリーミング用の署名付きURL)を返し、`PlayerPaneView`はOneDrive/ローカル動画では常にこれ経由で
  `engine.load(url:)`を呼ぶ(YouTubeは上記の通りダウンロード完了までそもそも呼ばない ―
  未ダウンロード時の`video.url`はwatchページURLで再生不可能なため)。副次効果として、
  ダウンロード済みのOneDrive動画は`@content.downloadUrl`の短い有効期限切れの影響を
  受けなくなり、ネットワーク無しでも再生できるようになる。失敗時(`.failed`)は明示的な
  リトライUIを持たず、次にその動画を再生した際に`startDownloadIfNeeded`が自動的に再試行する。
  `deleteLocalCopy(for:)`(2026-08-04追加)はローカルコピーだけを`FileManager.trashItem`
  でゴミ箱へ移動し(リポジトリ規約通りハード削除はしない)、共有元のOneDrive上のファイル/
  YouTube上の動画には一切影響しない ― 削除後は状態が`.notDownloaded`に戻るだけで、
  `VideoItem`自体は一覧に残る(`ContentView.deleteVideo`が呼ばれる通常のローカル動画削除とは
  別物 ― `VideoCardView`の`moveToTrash()`はリモート動画なら`onDelete`を呼ばずこちらに
  分岐する)。呼び出し元は`VideoCardView`(サムネイル右クリック「ローカルコピーを削除」、
  ダウンロード済みの場合のみメニューに出す。command+deleteも同条件で有効化)と`PlayerPaneView`
  (`DownloadStatusLabel`の「ローカルに保存済み」の横のゴミ箱ボタン)の2箇所、どちらも
  確認ダイアログを挟む。
  **`deleteAllLocalCopies()`/`localCacheSummary()`(2026-08-05追加)** ―
  「ローカルにDLしたキャッシュを一気に削除する機能」という要望への対応。動画ごとに
  `deleteLocalCopy(for:)`を繰り返すのではなく、`downloadsDir`フォルダ自体を`trashItem`で
  まるごとゴミ箱へ移動してから空フォルダを作り直す(`localFileURL(for:)`の命名規則
  (`<remoteID>.<拡張子>`)通り`downloadsDir`直下はフラットなので安全に丸ごと消せる ―
  ファイル数が多くても1回のファイル操作で済み、`states`も`removeAll()`で一括リセットできる)。
  フォルダ削除前に進行中のダウンロード(`URLSessionDownloadTask`/yt-dlpの`Process`)を
  すべて`cancel()`/`terminate()`する ― 削除直後にダウンロードが完了して宙に浮いたファイルが
  復活するのを防ぐため。`localCacheSummary()`は`downloadsDir`の`contentsOfDirectory`+
  `.fileSizeKey`で件数・合計サイズを返す軽量な同期関数(サブフォルダを持たないフラットな
  1フォルダなので全ライブラリのスキャンより遥かに軽い)― `Views/TopBarView.swift`の
  「キャッシュ」ボタンが押された瞬間に呼び、`Views/CacheSettingsPopover.swift`に合計サイズを
  渡す。呼び出し元(`TopBarView`)は`ContentView`を経由せず`DownloadStore.shared`を直接呼ぶ ―
  `VideoCardView`/`PlayerPaneView`の個別削除と同じ方針。
  **`enforceCacheLimit()`(2026-08-05追加)** ― 「ローカルにキャッシュしたトータルを
  表示してほしい」「ローカルキャッシュの最大値を設定したい。Defaultは5G。5Gを超えたら
  古いものを削除する」という要望への対応。合計サイズが`Settings.maxCacheBytes`(既定5GB、
  `Int64`バイト)を超えていたら、`downloadsDir`直下を`.contentModificationDateKey`で
  更新日時の古い順にソートし、上限を下回るまで先頭(＝最も古い)から`trashItem`で
  ゴミ箱へ送る(ハード削除はしない)。ちょうどダウンロードし終えたファイルは更新日時が
  最新のため、削除対象としての優先度が自然と最も低くなる(直近再生した動画から真っ先に
  消えることはない)。呼び出しタイミングは3箇所: ①`init`(起動時、前回セッション中に
  上限を引き下げていた場合の反映)②`finishHTTPDownload`/YouTubeダウンロードの
  `terminationHandler`(ダウンロード成功のたびに再チェック)③`Views/TopBarView.swift`の
  `maxCacheGBText`の`onChange`(ユーザーが上限を変更した瞬間に即座に反映)。削除した
  ファイルの`remoteID`(ファイル名から拡張子を除いた部分)ぶんだけ`states`を
  `.notDownloaded`に書き戻す。ファイルI/Oは`Task.detached`で行い、`states`の書き戻しだけ
  `MainActor.run`に戻す(既存の`deleteLocalCopy(for:)`/`deleteAllLocalCopies()`と同じ
  スレッド設計)。
- **`Views/LocalSaveToggle.swift`**(2026-08-05追加) — OneDrive動画専用の「ローカルに保存」
  トグル。「OneDriveの場合はローカルに保存はトグルにする。デフォルトではローカルダウンロードは
  Off。ダウンロード中やダウンロード後にトグルをOffにしたらPromptしてYesなら消す」という要望への
  対応。`video.remoteKind == .oneDrive`のときだけ`PlayerPaneView`の`infoSidebar`から使う
  (YouTubeは引き続き`DownloadStatusLabel`のまま ― ダウンロード必須という設計自体は変えて
  いないため)。**グリッド(`VideoCardView`)には出さない**(当初はカード下にも省スペース版
  (`compact`パラメータ)を出していたが、「グリッド表示のときはローカルDLのトグルは表示
  いらない」という要望を受けて撤回した ― `VideoCardView`は元の「カード全体を覆う1つの
  `Button`」構造に戻し、`compact`パラメータ自体も未使用になるため削除した。グリッド側の
  ダウンロード状態表示は`VideoThumbnailView`の`DownloadBadge`(サムネイル左上、状態を見る
  だけの非インタラクティブなバッジ)のみ)。専用の永続状態は持たず、`DownloadStore.
  state(for:)`をそのままトグルの見た目にする(`.notDownloaded`/`.failed`→OFF、
  `.downloading`/`.downloaded`→ON)。ONにする操作は`DownloadStore.startDownloadIfNeeded(for:)`
  を即座に呼ぶだけだが、OFFにする操作は`confirmationDialog`を挟み、Yesが選ばれて初めて
  `DownloadStore.disableLocalSave(for:)`(ダウンロード中なら中断、ダウンロード済みならゴミ箱へ)
  を呼ぶ ― キャンセルした場合は状態が変わらないため、トグルの`get`が再評価されて自動的にONへ
  戻る(明示的に戻す処理は不要)。
- **`Core/Settings.swift`の`maxCacheBytes`** ― `DownloadStore`のキャッシュ上限(`Int64`
  バイト、既定5,000,000,000＝5GB、10進 ― `ByteCountFormatter`の`.file`スタイル表示と
  桁を揃えている)。`Views/TopBarView.swift`の「キャッシュ」ポップオーバー
  (`Views/CacheSettingsPopover.swift`)がGB単位のテキストフィールドで編集する。
- **`Views/CacheSettingsPopover.swift`**(2026-08-05追加) — 「キャッシュ」ボタンから開く
  ポップオーバー。現在の合計サイズ・件数(`DownloadStore.localCacheSummary()`)の表示、
  上限(GB)のテキストフィールド(`LengthFilterPopover`と同じ「桁だけこのビュー内で
  フィルタする」方針)、「すべて削除」ボタン(`TopBarView`の既存の確認ダイアログ
  (`showsDeleteCacheConfirmation`)を開くだけで、削除の実処理自体はポップオーバーの外
  ― `TopBarView.deleteAllCache()`)、の3つをまとめている。以前は削除専用の
  「ローカルキャッシュを削除」ボタン1つだけだったが、合計サイズの常時表示と上限設定を
  追加するタイミングでポップオーバー形式に置き換えた。
- **`Views/HomeVideosView.swift`** — ホーム画面のコンテナ(2026-08-05、旧`HomeGridView.swift`
  を改名)。`viewMode: HomeViewMode`(`Models.swift`、`.grid`/`.hybrid`、
  `Settings.homeViewMode`に永続化。`TopBarView`のセグメントピッカーで切り替え、
  `ContentView`の`.onChange(of: homeViewMode)`が変更のたびに書き戻す)で`gridBody`
  (`LazyVGrid` + `VideoCardView`、既定のサムネイルグリッド)/`VideoTableView`(下記、
  Finder風の表形式)を切り替えるだけの薄いディスパッチャ。`ContentUnavailableView`
  (macOS 14+限定)は使わず、独自の`EmptyStateView`(private)でフォルダ未選択/スキャン中/
  該当なしの3状態を表示する(`.macOS(.v13)`を維持するため)。**`VideoTableView`だけ
  `ScrollView`に入れ子にしない**(`Table`自体がスクロール可能な`NSScrollView`を内包する
  ため、外側にも`ScrollView`を重ねると二重スクロールになる ― そのため`body`の`switch`は
  トップレベルに出し、`ScrollView`はグリッドの分岐にだけかぶせる)。

  表示形式は当初グリッド/一覧/ハイブリッドの3種類あった(2026-08-05、「MyTubeの動画の
  表示の仕方を増やしたい」という要望に対応)が、一覧(サムネイル無し)とハイブリッド
  (小さいサムネイル付き)がどちらもFinder風の`Table`に行き着いた結果ほぼ同じ見た目に
  なったため、「一覧は削除します」という要望を受けて一覧型を廃止し、`HomeViewMode`は
  `.grid`/`.hybrid`の2種類に整理した(永続化済みの`"list"`という値は
  `Settings.homeViewMode`の`?? .grid`フォールバックで安全に`grid`扱いになる)。

  - **`Views/VideoTableView.swift`** — 名前(小さいサムネイル+ファイル名)・長さ・
    ソース(`video.remoteKind?.displayName ?? "ローカル"` ― ローカル/OneDrive/YouTube)・
    チャンネルの4列を`TableColumn`で定義するだけで、ヘッダー行・交互の背景色・選択
    ハイライトといったFinderのリスト表示そのものの見た目がSwiftUI標準の`Table`
    (`NSTableView`のラッパー)から自動的に得られる(独自にストライプ背景等を描画する
    必要がない)。名前列のサムネイルは`VideoThumbnailView(width: 56, showsDurationBadge:
    false)`(一覧性を優先してごく小さく、長さバッジは狭いサムネイルに重なって見づらいため
    出さない)。「長さ」列は同ファイル内`private struct DurationCell`が
    `ThumbnailStore.cachedDuration(for:)`/`loadDuration(for:)`を`.task(id:)`で独自に
    呼ぶ(`VideoThumbnailView`側も同じキャッシュを参照するため、どちらが先に読み込んでも
    二重デコードにはならない)。列はクリックしてもソートされない(`TableColumn`に
    `sortUsing:`を渡していないため)― 並び順は`TopBarView`の「並び替え」メニュー
    (`SortOption`)がグリッドと共通で担うという既存の設計を崩さないための意図的な選択。
    単一選択(`selection: VideoItem.ID?`)の変化を`onChange`で拾って即`onSelect`を呼ぶ ―
    グリッドと同じ「1クリックで開く」操作感に揃えるため(Finder本来の「シングルクリックで
    選択・ダブルクリックで開く」とはあえて違えている)。右クリックメニュー・削除確認
    ダイアログは名前列のセルに`VideoActionsModifier`(下記)をそのまま適用して使い回すが、
    `isHovering`は常に`false`で渡す(`Table`の行のホバー状態を素直に拾えないため、
    command+deleteでの即時削除だけはこの形式では効かない ― 右クリック経由の削除は
    グリッド型と同じく使える)。
    ※上記は2026-08-05時点の説明で古い ― 2026-08-14に「サイズ」列とヘッダークリックでの
    ソート機能(`sortOrder`、`TopBarView`の「並び替え」メニューは撤去)が追加されている
    (`Row`/`KeyPathComparator`、詳細は未反映)。
  **「サイズ」列のソートは`VideoTableView`自身が全動画ぶんを先読みする**(2026-08-21修正、
  「サイズのソートがおかしい」というユーザー報告への対応)。以前は`SizeCell`が可視セルだけを
  個別に(セル内に閉じた`@State`で)`FileSizeStore.loadSize(for:)`を呼んでいたため、
  値が届いても`VideoTableView`の`rows`(＝ソート結果)を再計算させる手段が無く、画面外で
  まだ一度もセルが表示されていない動画は`fileSizeSortKey`が常に`.max`扱いのまま ―
  ソートしてもほとんどの行が「サイズ不明」として束ねられ、ソート自体が効いていないように
  見えていた。`VideoTableView`が`@State private var fileSizes: [VideoItem.ID: Int64]`を
  持ち、`.task(id: videos)`(`videos`が変わるたびに自動キャンセル・再実行、ビューが
  消えれば自動キャンセル)から`loadFileSizes()`を呼んで`withTaskGroup`で表示中の全動画ぶんを
  並行して`FileSizeStore.shared.loadSize(for:)`し、結果を`fileSizes`へ書き戻す ―
  この`@State`が更新されるたびに`body`が再評価され`rows`(`Row(video:fileSize:)`の
  `fileSize`は`fileSizes[video.id]`由来)が正しい順序に更新される。`SizeCell`自体は
  もう非同期取得を持たない純粋な表示コンポーネント(`fileSize: Int64?`を受け取るだけ)に
  縮小した。大きいライブラリで一斉に大量のファイルI/Oが走らないよう、
  `FileSizeStore`側に`ConcurrencyLimiter(limit: 8)`を追加してローカルファイルの
  `resourceValues`呼び出しを絞っている。
  **`fileSizes`への書き戻しは結果が届くたびではなく、揃うまでまとめて1回だけ行う**
  (2026-08-21再修正、「ハイブリッドモードで、ソートしたあと、再生できない」という
  ユーザー報告への対応 ― 上記の初回修正が生んだ副作用)。初回修正時は`for await`ループの
  中で1件解決するたびに`fileSizes[id] = size`していたため、「サイズ」列でソート中は
  届いた値のたびに`rows`が再計算されて`Table`の行が並び替わり続けた。特にサイズ列を
  ソートした直後は多くの動画がまだ`.max`(未取得)扱いで一斉に結果が届く期間と重なりやすく、
  そのタイミングでユーザーが行をクリックすると`Table`(`NSTableView`)側で行の入れ替え
  (`reloadData`相当)が起きてクリックが正しい行の選択として成立せず、`selection`が
  更新されないまま=再生が始まらない、という不具合になっていた。`loadFileSizes()`を
  結果をローカル変数`collected`に集めてから`fileSizes.merge(_:uniquingKeysWith:)`で
  1回だけ書き戻す形に変更し、この先読み1回につき`rows`の再計算・`Table`の再描画も1回に
  抑えた(トレードオフ: 1件ずつサイズが埋まっていく体感は無くなり、先読みが完了するまで
  対象のセルは「—」のまま)。**`@State`を先読みの書き戻し先に使う場合、複数件の非同期結果を
  `for await`ループの中で1件ずつ即座に書き込むと、`Table`/`List`等の並び替えを伴うビューで
  「ロード中は行が動き続けてクリックできない」症状を起こしうる ― ローカル変数に集めてから
  まとめて1回で書き戻すこと。**「長さ」列(`DurationCell`)は今のところ
  同種の不具合が報告されていない**ため未修正のまま(`ContentView.ensureDurationsLoaded()`が
  長さフィルター有効時に全動画分を先読みし、その結果が`ContentView`の`@State`更新経由で
  間接的に`VideoTableView`の再描画・再ソートを誘発するため、実用上は問題が顕在化しにくい)―
  もし同じ症状(「長さでソートしても効かない」)が報告されたら、この「サイズ」列と同じ
  パターン(`VideoTableView`自身が`@State`で先読みし、`DurationCell`を表示専用にする)で
  直すこと。
  **共通のロジックは2つのファイルに切り出してある**(重複を避けるため):
  - **`Views/VideoThumbnailView.swift`**(+ `DownloadBadge`) — 16:9のサムネイル本体
    (長さバッジ・ダウンロード状態バッジ込み)。`width`が`nil`ならグリッドのセル幅いっぱいに
    広がり(`.frame(maxWidth: .infinity)`)、指定すれば`VideoTableView`の名前列のように
    その幅に固定される(`.frame(width:)`)。`showsDurationBadge`(既定`true`)で右下の
    長さバッジの表示有無を切り替えられる ― `VideoTableView`は`false`を渡す(上記
    「長さ」列の項参照)。`.task(id: video.id)`でのサムネイル遅延ロードと
    `formatDuration(_:)`もここに集約されている(元は`VideoCardView`にあった実装)。
    **`DownloadBadge`の`.downloaded`はファイルサイズも表示する**(2026-08-05、
    「ローカルにDLしたサイズを各ビデオに表示してほしい」という要望に対応 ― 以前は
    緑のチェックマークだけの円形バッジだったが、`DownloadStore.localFileSize(for:)`
    (下記`Core/DownloadStore.swift`の項)から取得したバイト数を`ByteCountFormatter`で
    整形し、チェックマーク+サイズのカプセル型バッジ(`.downloading`の%表示と同じ
    見た目・角丸)にした。`PlayerPaneView`の`DownloadStatusLabel`(動画情報行、
    「ローカルに保存済み(42.3 MB)」)も同じ`localFileSize(for:)`を使う。
  - **`Views/VideoActionsModifier.swift`** — 右クリックメニュー(ローカル動画は「Finderで
    表示」のみ、リモート動画はダウンロード済みなら「ローカルコピーを削除」)・
    command+deleteでの即時削除(ホバー中かつダウンロード済みのリモート動画のみ)・確認
    ダイアログ・失敗時アラートをまとめた`ViewModifier`。`.videoActions(video:isHovering:)`
    という`View`拡張経由で各セルの`Button`(`VideoTableView`は名前列のセル)に適用する
    (元は`VideoCardView`にあった実装)。
  - **`Views/PointingHandCursor.swift`**(2026-08-05追加) — 「サムネイル/動画をクリック
    できる場所にきたらカーソルを手のマークにしてほしい。YouTubeのように」という要望への
    対応。`View.pointingHandOnHover()`という`View`拡張1つで、`VideoCardView`(グリッドの
    カード全体)・`VideoTableView`の名前列(サムネイル+タイトル)の両方に適用している。
    **`NSView.resetCursorRects()`をオーバーライドする`NSViewRepresentable`
    (`PointingHandCursorNSView`)を`.overlay(...)`で重ねる実装**(`.pointerStyle(_:)`は
    macOS 14+限定でこのアプリの最低ライン`.macOS(.v13)`と合わないため使えない)。
    当初は`.onHover`内で`NSCursor.pointingHand.push()`/`.pop()`を呼ぶだけの実装だったが、
    2段階の不具合を経てこの形に落ち着いた: ①`VideoCardView`の既存の`isHovering`用
    `.onHover`とは別にこのロジックをもう1つの`.onHover`として重ねたところ、ハイブリッド
    (`VideoTableView`)は効くのにグリッドだけ効かない不具合が起きた(SwiftUIは同じビューに
    複数の`.onHover`を重ねても両方が確実に発火するとは限らない)→ 1つの`.onHover`にまとめて
    `isHovering`更新と`NSCursor.push()`/`pop()`を両方行うよう修正 ②それでも
    `VideoCardView`だけ指差しにならない不具合が再発 ― `VideoCardView`は`Button`で
    全体を囲んでいるのに対し`VideoTableView`の名前列は`Button`の外(`Table`のセル)にあり、
    **SwiftUIの`Button`内側では`.onHover`ベースの`NSCursor.push()`/`pop()`が信頼できない**
    (push/pop自体は呼ばれていても、`Button`側のカーソル制御に上書きされて見た目に反映
    されないとみられる)と判明。`.onHover`+`push()`/`pop()`をやめ、AppKit本来のカーソル
    矩形システム(`NSView.addCursorRect(_:cursor:)`、クリックのヒットテストとは独立に
    ウィンドウがマウス移動のたびに参照する仕組み)に直接登録する現在の実装に切り替えて
    解消した ― `Button`の内外を問わず確実に効く。**同じ問題を踏まないよう、新規に
    ホバー時カーソル変更を実装する場合は`.onHover`+`NSCursor.push()`/`pop()`ではなく
    必ず`pointingHandOnHover()`を使うこと**(特に`Button`で囲んだビューでは`.onHover`
    方式は避ける)。
  **グリッドのコンパクト表示**(2026-08-05、「サムネイルの下にはファイル名だけでOK」
  「コンパクトに並べて」という要望に対応): カード下のテキストはファイル名(`video.title`、
  1行・末尾トランケート)だけで、チャンネル名・更新日は出さない。グリッドの列も
  `GridItem(.adaptive(minimum: 160, maximum: 200))`(以前は240〜320)+ 間隔12pt(以前20pt)
  に詰め、1画面に入るカード数を増やしている。

  README の表示形式の説明も、表示形式がグリッドとハイブリッド(Finder風の表: 名前/長さ/
  ソース/チャンネルの4列)の2種類であることを反映してある。表示形式を追加・変更する場合は
  `README.md`の該当箇所も更新すること。

## 変更時の注意

- サムネイル/動画一覧のスキャンは非破壊(読み取り専用)。移動・リネームを行う機能は
  持たない(それが必要なら myorganizer の該当ペインを使う)。**削除まわりの設計**
  (2026-08-04時点では「ワンクリックで実ファイルが消えるのはリスクが高い」というユーザー
  判断でローカル動画本体の削除を一度廃止していたが、2026-08-21に「ローカルの場合ファイルを
  削除できる機能がほしい。複数選択もほしい」という要望を受けて再度追加した ―
  以前の「ローカル動画本体には絶対に直接削除ボタンを出さない」という方針は撤回済み):
  - **ローカル動画本体も、確認ダイアログを挟んでゴミ箱へ移動できる**(2026-08-21再追加)。
    `Views/VideoActionsModifier.swift`が`onDeleteLocal: ((VideoItem) async throws -> Void)?`
    (`ContentView.deleteLocalVideoFile(_:)`が実体)を受け取り、右クリックの「ファイルを削除」
    メニュー・ホバー中のcommand+delete(グリッド型のみ ― ハイブリッド型`Table`は行のホバー
    状態を拾えないため右クリック経由のみ)の両方から呼ぶ。実処理は`FileManager.trashItem`
    (ハード削除はしない、リポジトリ規約通り)を`Task.detached`で行った後、
    `MainActor.run`で`localSources`から該当`VideoItem`を取り除く(削除後に一覧へ残り
    続けないように ― `DownloadStore.deleteLocalCopy(for:)`と違い、ローカル動画は
    `LocalSource.videos`という単一の真実の情報源しか持たないため、削除成功時は必ず
    そこから除去する)。「Finderで表示」メニューは引き続き並存する。
  - **複数選択モード**(2026-08-21追加、「複数選択もほしい」という要望への対応)。
    `TopBarView`の「選択」ボタン(`ContentView.isSelectionMode`、動画再生中は無効)で
    切り替える。オンの間、`VideoCardView`/`VideoTableView`の`NameCell`はタップ(グリッド)・
    クリック(ハイブリッド)を再生ではなく`ContentView.selectedVideoIDsForDeletion`
    (`Set<VideoItem.ID>`)へのトグルに差し替え、チェックマーク(グリッドは左上、
    ハイブリッドは名前列の先頭)で選択状態を示す。**選択・削除できるのはローカル動画だけ**
    ―リモート動画のカード/行は選択モード中`circle.dashed`アイコンを出すだけでタップに
    反応しない(リモート動画のローカルコピー削除は既存の個別操作(下記)のまま)。
    `HomeVideosView`が選択件数・「すべて解除」・「削除(ローカル件数)」・「完了」の
    ツールバーをコンテンツの上に出す。「削除」は`ContentView`の確認ダイアログを開き、
    確定後`deleteSelectedLocalVideos()`が対象を1件ずつ`deleteLocalVideoFile(_:)`へ渡す
    (1件の失敗が他の成功を巻き込まないよう、全件処理してから失敗分だけメッセージで
    まとめて通知する)。`VideoTableView`の`Table`標準選択(`selection: VideoItem.ID?`)は
    選択モード中もそのまま流用しているが、`onChange`内で1件処理するたびに`nil`へ戻す
    ことで同じ行への連続クリックを拾えるようにしている(値が変化しないと`onChange`が
    発火しないSwiftUIの制約への対処)。
    **チェックマーク自体は`Image`単体ではなく`Button`にする**(2026-08-21修正、
    「選択モードでラジオボタンを押しても選択されない」というユーザー報告への対応)。
    `VideoCardView`側は、非インタラクティブな`Image`をカード全体の`Button`の上に
    `.overlay`で重ねているだけだと、アイコンの不透明な背景円がヒットテストの最前面を
    占有してしまい、その領域をタップしても(アイコン自身にアクションが無いため)下の
    `Button`にもタップが伝わらない「死んだタップ領域」になっていた
    (`FavoriteButton`が兄弟`Button`として確実にタップを拾えているのと対照的)。
    `NameCell`側もチェックマークを独立した`Button`にし、`Table`のネイティブ行選択に
    頼らず直接`onToggleSelect(video)`を呼ぶようにした(行の他の部分をクリックした場合は
    引き続き`Table`のネイティブ選択→`onChange`経由でトグルされる)。新しく選択操作用の
    アイコン/オーバーレイを追加する場合は、必ず`Button`(または明示的なタップ
    ジェスチャー)でラップし、非インタラクティブな`Image`だけを重ねないこと。
  - **リモート(OneDrive共有/YouTubeプレイリスト)動画は、引き続き`DownloadStore`の
    ローカルコピーだけ**削除できる(元のOneDrive上のファイル/YouTube上の動画には一切
    触れない)。`VideoCardView`の右クリック
    「ローカルコピーを削除」(ダウンロード済みのときだけメニューに出す、確認ダイアログあり)
    とcommand+delete(ホバー中かつダウンロード済みのカードのみ、確認なしで即実行)、
    および`PlayerPaneView`の「ローカルに保存済み」横のゴミ箱ボタンの計3箇所。いずれも
    `DownloadStore.deleteLocalCopy(for:)`(`FileManager.trashItem`でゴミ箱へ)を呼ぶだけで、
    削除後も`VideoItem`自体は一覧に残る(`remoteSources`側からは取り除かない ― ダウンロード
    状態が`.notDownloaded`に戻るだけで、動画自体は共有元にまだ存在するため)。
- 対応拡張子を増やす場合は `VideoScanner.videoExtensions` の1箇所を直すだけでよい
  (`OneDriveShareClient`も同じ集合を参照するため、ローカル/リモート両方に反映される)。
- macOS 最低バージョンを上げる変更(`Package.swift`/`Info.plist` の `LSMinimumSystemVersion`)
  をする場合は、`onChange`/`ContentUnavailableView` 等の macOS 14+ 限定 API に
  置き換えてよいか確認すること(逆に上げない限りは 2 引数 `onChange` や
  `ContentUnavailableView` を使わない)。
- `yt-dlp`/`ffmpeg`は同梱しない(Homebrew前提、`downloader`と同じ方針)。見つからない場合は
  `DownloadStore.startYouTubeDownload`/`YouTubePlaylistClient.fetchPlaylist`が
  `.failed`/エラーを返すだけで、アプリ全体が落ちることはない。yt-dlpの引数
  (フォーマット文字列)を変える場合は`README.md`の画質に関する記述も更新する。
- **`Core/MainStoryDetector.swift`**(2026-08-22追加、「conanの動画の中で、メインストーリーが
  あったらそれだけを抽出したリストを作ってほしい」という要望への対応) ― サイドバー
  「お気に入り」「最近再生した動画」と同じ並びに追加した3つ目の横断チャンネル
  「コナンメインストーリー」(`SidebarView.swift`、`SpecialLibrarySelection.mainStory`、
  `Models.swift`。当初「メインストーリー」という汎用の名前で追加したが、同日中に
  「conan専用のヒューリスティックだと名前でも分かるようにしたい」という要望を受けて
  「コナンメインストーリー」に改名した ― enumのcase名`mainStory`・型名
  `MainStoryDetector`自体は変えていない)。「メインストーリー」の定義はユーザー確認済みで、
  黒の組織編に限らず
  **前編・後編/事件編・解決編のように複数話にまたがって1つの話が続く回すべて**。
  公式のエピソードデータは一切持たず、`名探偵コナン - 0130 - 競技場無差別脅迫事件 -
  前編.mp4`のような「番組名 - 話数 - タイトル[ - ラベル]」形式の**ファイル名の付け方だけ**
  から連続話を検出する純粋関数(`MainStoryDetector.keys(in:)`)― conan専用のロジックでは
  なく、同じ命名規則のファイルなら他のシリーズにも同様に働く。判定ルール・既知の限界は
  同ファイル冒頭のコメントを参照。
  `conan/tv`配下の実ファイル一覧(337本)に対して実際に走らせ、既知の連続話
  (競技場無差別脅迫事件・黒の組織との再会・NYの事件・緋色シリーズ・17年前の真相 等)が
  正しく含まれ、隣接話数だが無関係な単発回(0998/0999、1041/1042、1027/1028等)が
  誤って連結されないことを確認済み。`ContentView`は`MainStoryDetector.keys(in:)`
  (O(n²)、話数トークンを持つ動画どうしの総当たり)を`filteredVideos`から毎回呼ばず、
  `mainStoryKeys`(`@State`)に`SidebarView.localGroups`等と同じ理由でキャッシュし、
  `localSources`/`remoteSources`が実際に変わった時だけ`rebuildMainStoryKeys()`で
  組み直す。
  **「ウィキとか確認した?」というユーザーからの指摘を受けて実際にWikipedia/ファンサイトで
  裏取りした**(2026-08-22): タイトルの先頭が3文字未満しか共通しない連続話は元々の
  ルール1・2では検出できない既知の限界だったが、実例として疑わしかった2件(0578〜0581・
  0705〜0706)を検索したところ**両方とも実在の連続話だった**ため、`Entry.
  knownExceptionGroups`という手動の例外リストへ追加した(237/337本に増加)。ただし
  **この2件は疑わしい候補を2つ拾って調べただけで、残り約104本の除外分すべてを
  検証したわけではない**― 網羅的に検証するには各話の原作(コミックス)対応巻を突き合わせる
  必要があり、まだ行っていない。今後この機能を触る際、追加の連続話が見つかったら
  `knownExceptionGroups`に追記していく想定(検証済みの根拠をコメントに残すこと)。
- **`Core/ConanEpisodeTags.swift`**(2026-08-22追加、「各エピソードで関連のある項目を
  書いて(例、黒の組織、怪盗キッド、等)」という要望への対応) ― `MainStoryDetector`と同じ
  「公式データは持たずタイトル文字列だけで判定する」方針の姉妹機能。`video.title`に
  黒の組織/黒ずくめ・キッド・警察学校編・安室・京極真・工藤新一・工藤優作・灰原・平次と
  いった固有名詞キーワードが含まれていれば、対応するタグ(黒の組織/怪盗キッド/警察学校編/
  安室透/京極真/工藤新一/工藤優作/灰原哀/服部平次)を返す純粋関数`tags(for:)`。
  `VideoCardView`(タイトル下)・`VideoTableView.NameCell`(タイトルの右、共通の
  `Views/RelatedTagsRow.swift`)が`video.title`から都度計算して1個以上あるときだけ
  カプセル型のチップで表示する ― 「コナンメインストーリー」チャンネルに限らず、タイトルが
  マッチする動画ならどこに表示されていても出る(表示を絞り込むための追加の状態は持たせて
  いない)。
  **NFC正規化が必須**: macOSのファイル名はUnicode正規化形式D(NFD、濁点等を独立した
  結合文字として分解した形)で保存されていることが多く`VideoItem.title`もそれを引き継ぐが、
  ソースコード中のキーワード文字列リテラルは通常NFC(結合済み)のため、正規化せずに
  `contains`で比較すると見た目が同じ文字列でも一致しないことがある(実際に`grep`で
  「怪盗キッド」を含むファイル名が引っかからず、この不一致に気づいた)。両辺を
  `precomposedStringWithCanonicalMapping`でNFCに揃えてから比較している ―
  他の箇所でファイル名由来の文字列とソースコード中のリテラルを比較する場合も同じ注意が
  要る。`conan/tv`の実ファイル一覧に対して実際に走らせ、337本中54本にタグが付き、
  誤検出(無関係なキャラクターへの取り違え等)が無いことを確認済み。
  **タグフィルター**(2026-08-22追加、「タグでもフィルタをかけられるようにしたい」という
  要望への対応): `Views/RelatedTagsRow.swift`の`TagFilterRow`(押せる・選択状態を持つ
  チップ、カード側の非インタラクティブな`RelatedTagsRow`とは別コンポーネント)を
  `HomeVideosView`の`content`直前に条件付きで差し込む
  (`showsTagFilter: specialSelection == .mainStory`のときだけ)。`ContentView`が
  `selectedMainStoryTags`(`@State`)を持ち、`filteredVideos`の`.mainStory`ケースで
  1つ以上選ばれていれば選択タグのいずれかにマッチする話だけへさらに絞り込む(OR ―
  複数選んだ場合は「絞り込む」でなく「集める」動作)。フィルターUIに渡す選択肢一覧
  (`ContentView.mainStoryAvailableTags`)は**タグフィルター適用前**の「コナン
  メインストーリー」一覧から計算する ― 適用後の`filteredVideos`から計算すると、
  1つタグを選ぶたびに他のタグの選択肢がボタンごと消え、フィルターを組み合わせて
  広げる操作ができなくなるため。`specialSelection`が`.mainStory`以外に変わったら
  `onChange(of: specialSelection)`で`selectedMainStoryTags`をクリアする(他チャンネルに
  無言で絞り込みが残ると分かりにくいため)。
- **`Core/EpisodeTagStore.swift`**(2026-08-22追加、「手動で既存または新規のタグを
  エピソードに追加できる?」という要望への対応) ― `Core/FavoritesStore.swift`と同じ
  「シングルトン+`@Published`+即座にUserDefaultsへ永続化」の設計。`ConanEpisodeTags`の
  自動判定(タイトルのキーワードだけ、保存不要)を補い、`Settings.manualEpisodeTags`
  (`[String: Set<String>]`、`VideoItem.stableKey`→タグ名の集合)に手動で追加した分だけを
  持つ。**自動判定されたタグを取り消す(除外する)機能は無い** ― 要望が「追加」だったため、
  まずは追加・削除(手動分のみ)にスコープを絞っている。`allTags(for:)`が自動判定+手動タグを
  合わせた表示・フィルター用の一覧を返し、`VideoCardView`/`VideoTableView.NameCell`/
  `ContentView`はすべて`ConanEpisodeTags.tags(for:)`を直接呼ばずこちらを経由するように
  変更した(手動タグの追加・削除が即座に画面へ反映されるよう、いずれも`@ObservedObject`で
  購読する)。
  **UI**: `Views/EpisodeTagEditorView.swift`(シート) ― `VideoActionsModifier`の右クリック
  メニューに追加した「タグを編集...」(ローカル/リモート問わず、ファイル操作を伴わない
  メタデータのため常に出す)から開く。自動判定タグは削除不可のグレーのバッジ、手動タグは
  ✕ボタン付きで削除可、既存のタグ(定義済み9種+他の動画で使われた自由なタグ名)は
  タップで追加、テキストフィールドで全く新しい名前も作れる。タグチップの折り返しは
  `HStack`が幅をはみ出すため、同ファイル内に`Layout`プロトコル(macOS 13+)で組んだ
  最小限の`FlowLayout`を用意した。
- **`Core/ConanMainStoryReference.swift`**(2026-08-22追加、「これを参考にして」という
  要望への対応) ― ユーザーが直接提供した、黒の組織を中心とした「本筋」エピソードの
  参照データ(話数(Int)→関連タグの配列、124件)。ユーザー自身が内容を確認した上で
  「これはハードコードしちゃってOK」と明言したため、パースや検証を挟まずSwiftの
  リテラル(`tagsByEpisode`)としてそのまま持つ ― 値の言い回し(「灰原哀初登場」のように
  キャラクター名と出来事が1つの文字列に混ざっている等)もユーザー提供のまま変えていない。
  **2つの箇所から参照する単一の信頼できるデータソース**:
  1. `MainStoryDetector.keys(in:)`のルール0(2026-08-22拡張) ― このテーブルに載っている
     話数は、タイトルのパターンに関わらず無条件で「コナンメインストーリー」に含める
     (`Entry.knownExceptionGroups`と同じ位置づけだが、こちらは1件ずつ手動確認した
     少数の例外ではなく、ユーザー提供の包括的なデータ)。`conan/tv`の実ファイル一覧に
     対して実際に走らせ、237→241/337本に増えたことを確認済み(タイトルパターンだけでは
     検出できなかった話数 ― 例: エピソード1「小さくなった名探偵」、129
     「黒の組織から来た女」等の単発タイトルの話 ― がこのテーブル経由で新たに含まれる
     ようになった)。
  2. `Core/EpisodeTagStore.swift`の`allTags(for:)` ― `ConanEpisodeTags`のキーワード自動
     判定の後に、この話数別テーブルのタグを合流させる(重複除去)。`ConanEpisodeTags`の
     9種より遥かに多くの固有名詞(ベルモット/キール/FBI/赤井秀一/沖矢昴/世良真純/
     ラム編/緋色シリーズ等)がタグとして使えるようになった。
  **話数の特定は文字列一致ではなく数値一致**(`episodeRange(inTitle:)`が
  `名探偵コナン - 0130 - ...`の`0130`部分だけをパースする) ― そのためテーブル内の
  タイトル表記(ユーザーの手元の別ソース由来で、ライブラリの実際のファイル名と細部が
  微妙に異なることがある、例: 578話の括弧内表記が「前兆」なのに実ファイルは
  「オーメン」)は無視してよく、話数さえ合っていれば正しくタグ付けされる。
  **`conan/tv`ライブラリに存在しない話数(124件中40件)も含めたまま残してある**
  (今後エピソードが増えても調整不要にするため、意図的な設計)。
