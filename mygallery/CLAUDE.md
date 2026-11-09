# CLAUDE.md — mygallery

Photos.app 風のローカルフォルダ・フォトギャラリー。**SPM パッケージではない** —
`Sources/main.swift`(+ 2026-09-02 追加の3ファイル、下記)を `build.sh` が直接
`swiftc` でコンパイルする、単一バイナリの Swift + AppKit アプリ。`swift build` は使えない。

機能・キーボード操作の一覧は [README.md](README.md) を参照。ここでは実装上の設計判断と、
今後変更するときに踏みやすい落とし穴を記録する。

**iPad版 `mygallery-ipad/`(MyGallery Pad)が2026-09-07に追加された** ―
OneDrive共有リンクのブラウズ専用の縮小版(ローカルフォルダ・Visionベースの
画質順ソート・重複検出・回転・削除は対象外)。`Core/OneDriveMediaClient.swift`は
このアプリの`Sources/OneDriveMediaClient.swift`から移植したもの(mytube-ipad/
myslideshow-ipadと同様、pure Foundationのため無変更で動く)。**別コードベースで
自動的には同期しない** ― OneDrive関連(認証フロー・スキャン性能)に手を入れたら
`mygallery-ipad/CLAUDE.md`を見て同じ修正が必要か確認すること。詳細は
`mygallery-ipad/CLAUDE.md`参照。

## ファイル構成(2026-09-02、OneDrive+スライドショー機能の統合で複数ファイルへ分割)

それまで `Sources/main.swift` 一本(3583行)だった構成に、MySlideshow(廃止済み、下記)の
機能を統合するにあたって3ファイルを追加した:

- `Sources/main.swift` — 元からのローカルブラウズ本体。`PhotoItem`/`PhotoStore`/
  `ThumbnailLoader`/`GridViewController`/`SidebarViewController`/`ViewerOverlay`/
  `MainWindowController`/`AppDelegate` 等。
- `Sources/OneDriveMediaClient.swift` — OneDrive共有リンクのスキャン(認証・ページング・
  並列walk)。`myslideshow/Sources/MySlideshow/Core/OneDriveMediaClient.swift` から
  ほぼそのまま移植。
- `Sources/OneDriveSidebarViewController.swift` — 決め打ち2リンク(動画・画像)の
  年/月フォルダツリー、サイドバーのローカル/動画(OD)/画像(OD)モード切替コンテナ、
  `GallerySettings`(UserDefaults)。
- `Sources/SlideshowController.swift` — 自動連続再生スライドショーの状態機械+
  コントロールバー・日付ラベルのオーバーレイビュー。`FilenameDateParser`もここに同居。

`build.sh` の `swiftc` 呼び出しはこの4ファイルを明示的に列挙している(グロブではない)。
**新しい `.swift` ファイルを追加したら `build.sh` の `build()`/`needs_build()` 両方に
追記すること** — 追記を忘れるとファイルが存在するのにコンパイル対象に入らず、
`swiftc` が未定義シンボルで失敗するか、最悪コンパイルは通るが変更が反映されない
(`needs_build`のタイムスタンプ比較が新ファイルを見ていないと`./build.sh`が
再ビルドをスキップしてしまう)。

**`build.sh`は`swiftc`に`-target arm64-apple-macosx${MIN_MACOS}`(現在26.0)を明示している
(2026-10-15)** ― macOS 27(Darwin 27)に上げた後、無指定の`swiftc`の既定ターゲットが
`macosx28.0`になり(Darwin N→macOS N+1と換算するため)、ビルドしたアプリが`minos 28.0`に
なって「このバージョンのmacOSでは使えません」と起動を拒否された。SPMアプリは
`Package.swift`の`platforms`で明示しているので影響しないが、`swiftc`直叩きのアプリ
(このアプリと`mymarkdown/`)は同じ罠を踏む。この`-target`指定は外さないこと。

## OneDrive + スライドショー機能(2026-09-02、旧MySlideshowから機能統合)

「MySlideshowの機能をMyGalleryに追加してほしい」というユーザー要望への対応。
MySlideshow(Mac版、`myslideshow/`)はこの統合の完了後に**削除済み**
(ルート`CLAUDE.md`参照)。iPad版`myslideshow-ipad/`はこの統合とは無関係に
2026-09-07にユーザーの明示的な依頼で削除された(ルート`CLAUDE.md`参照)。

### 移植した範囲・移植しなかった範囲

- **移植した**: OneDrive共有リンクからの写真・動画ストリーミング、自動連続再生
  スライドショー(写真は秒数タイマー、動画は最後まで再生してから自動送り)、
  ランダム再生、時間制限(5分刻み・無制限)、マウス移動で3秒だけ現れる
  コントロールバー(前へ/一時停止・再開/次へ/終了)、ファイル名から撮影日を
  推測する右下の日付ラベル(`FilenameDateParser`)。
- **移植しなかった(意図的)**:
  - **表示モードは全画面のみ**。MySlideshowの「ウィンドウ内固定サイズ」
    「PIP(常時最前面浮動パネル)」は、MyGalleryの単一ウィンドウ+オーバーレイ
    ビューアという構造とは相性が悪く、実装コストに見合わないと判断してユーザーに
    確認の上スコープ外にした。PIPは`NSPanel`を一から作る大きな作業になる。
  - **ハイライト再生(動画の一部だけ再生)は無い**。これはMySlideshowで一度
    実装されたが2026-08-29に完全に撤去された機能で、現在のMySlideshowのコードにも
    存在しない ― 移植時に誤って「復活」させないよう注意。
- **リンクの追加・削除UIは一度作って、2026-09-06に廃止した**。当初は「MyGalleryは
  汎用ギャラリーアプリなので、リンクをUIから自由に追加・削除できる方が自然」という
  判断で`OneDriveLinkPickerViewController`(リンク一覧+追加/削除+読み込み前の
  年フォルダ選択+「読み込み」ボタン)を実装したが、実際には動画専用「動画」・
  画像専用「画像」の2リンクしか使っておらず、「ローカル/OneDriveの2択→OneDrive内で
  さらにリンクを選んで読み込む」という2段階の操作が煩雑という指摘を受け、
  MySlideshow時代と同じ「決め打ち2リンク、UIから追加・削除できない」設計に戻した
  (ユーザー承認済み)。`OneDriveLinkPickerViewController`・リンクの`Codable`永続化
  (`GallerySettings.oneDriveLinks`)・スキャン範囲を絞る年フォルダの事前選択UI
  (`GallerySettings.folderSelections`)は全部削除済み ― 再度似た要望が来ても、
  git履歴から復元するより今の「決め打ちリンク+年/月フォルダツリーで絞り込む」
  設計に机能を足す方を先に検討すること。今は`OneDriveLinks.video`/`.photo`という
  固定定数(`OneDriveSidebarViewController.swift`)が唯一のリンクで、サイドバーは
  「ローカル」/「動画(OD)」/「画像(OD)」の3タブ(下記参照)。

### データモデル: `PhotoItem`とローカル/OneDriveの二刀流

`PhotoItem`(main.swift）は元々ローカルファイル専用だったが、OneDriveアイテムも
表せるよう拡張した:

- `source: PhotoSource`(`.local` / `.oneDrive(linkID:)`)、`remoteID: String?`、
  `folderPath: [String]`を追加。
- **`name: String`(元ファイル名)を追加した(2026-09-07)**。ローカルは`url`が実ファイル
  パスなので`url.lastPathComponent`で常に正しいが、OneDriveは`url`が署名付き
  ダウンロードURL(`@content.downloadUrl`、拡張子もファイル名も反映しない)のため、
  `url.lastPathComponent`はゴミ(URLパスの最後のセグメント)になる。`init`は
  `name: String? = nil`を取り、省略時は従来通り`url.lastPathComponent`にフォール
  バックする(ローカルの呼び出し元は変更不要)。OneDrive側の`PhotoItem`生成
  (`MainWindowController.loadOneDriveLeaves`)だけ`MediaItem.name`(API応答の実ファイル名)
  を明示的に渡す。追加のきっかけは「動画再生中にファイル名から日付を表示したい」
  というユーザー要望で、`FilenameDateParser`(元はスライドショー専用)が正しい
  ファイル名を必要としたため。**この`name`追加以前は、OneDriveアイテムに対する
  ファイル名依存の処理(スライドショーの日付ラベル、名前順ソート、グリッドの
  ツールチップ)が軒並み`url.lastPathComponent`を使っていて実質壊れていた** ―
  `SlideshowController.showCurrent`・`resortOneDriveGrid`の`.name`ケース・
  `PhotoCell.configure`のツールチップは`photo.name`を使うよう合わせて修正済み。
  新しくファイル名を使うコードを書くときは`photo.url.lastPathComponent`ではなく
  必ず`photo.name`を使うこと。
- `cacheKey: String`(`remoteID ?? url.path`)を導入し、`Equatable`・
  `ThumbnailLoader`のキャッシュキー・`ViewerOverlay`/`PhotoCell`の非同期コールバック
  照合はすべて`url.path`ではなく`cacheKey`を使うよう変更した。**理由**: OneDriveの
  署名付きダウンロードURL(`@content.downloadUrl`)は再スキャンのたびにクエリの
  署名トークンが変わる。`url.path`をキーにすると、サムネイル/フルサイズキャッシュが
  再スキャンのたびに全部ミスヒットしてしまう(`remoteID`は再スキャンしても不変)。
  副次効果として、`ThumbnailLoader`のディスクキャッシュ(SHA-256ハッシュのファイル名)
  も`cacheKey`ベースになったため、OneDriveの同じ写真は**アプリを再起動しても
  再ダウンロードせずディスクキャッシュがヒットする**(MySlideshow自身の
  `ImageLoader`は署名URLの失効を理由にディスクキャッシュを持たなかったが、
  こちらはハッシュキーが`remoteID`なので失効の影響を受けない)。
- `isVideo`を**計算プロパティから格納プロパティに変更**した。理由:
  ローカルの動画拡張子セット(`videoExtensions` = mp4/mov/m4vのみ、
  「AVFoundationが確実に再生・フレーム抽出できるコンテナに絞る」という既存の
  設計判断)と、`OneDriveMediaClient.videoExtensions`(mkv/webm/wmv等も含む、
  より広い)は範囲が異なる。単一のグローバル拡張子セットでは両方を正しく
  判定できないため、`isVideo`は呼び出し側(`PhotoStore.rescan`はローカルの
  `videoExtensions`で、OneDrive変換コードは`MediaItem.kind`で)が判定した結果を
  そのまま格納する設計にした。**この2つの拡張子セットは意図的に別物** ―
  将来どちらかを広げる/狭める場合、もう片方に影響しないことを確認すること。
- **`ThumbnailLoader.generateCG`は写真/動画の分岐を`item.isVideo`で行う(`url.pathExtension`
  では判定しない)**(2026-09-06 修正)。OneDriveアイテムの`url`は`@content.downloadUrl`
  (署名付きダウンロードURL)で拡張子を含まないため、`url.pathExtension`で判定すると
  OneDriveの動画が常に「写真」経路(`CGImageSourceCreateThumbnailAtIndex`)に流れて
  サムネイルが生成できず(nilを返すだけで無音に失敗する)、グリッドに動画アイコンだけが
  出てサムネイル画像が出ない不具合になっていた。`request`/`generate`は`PhotoItem.isVideo`
  (または呼び出し側が明示する`isVideo`引数)をそのまま`generateCG`に渡すこと。
- **チェックボックスの`target`/`action`は1系統だけにすること**。廃止済みの
  `OneDriveLinkPickerViewController`時代に、`NSOutlineView`自体にも`target`/`action`を
  持たせて「行のどこをクリックしても切り替わる」作りにしたところ、チェックボックス
  自体をクリックすると「チェックボックス自身のaction」と「行クリックによるoutline側の
  action」の**両方**が発火し、同じフォルダのトグルが2回走って選択状態が壊れる
  (実機で`UserDefaults`が`["2020"]`や`[]`という意図しない値になっているのを確認した)
  不具合を踏んだ。今の`OneDriveFolderTreeViewController.checkboxToggled(_:)`は
  チェックボックス自身の`target`/`action`だけで、`outline`側には`target`/`action`を
  持たせていない ― 将来また「行のどこでもクリックできるように」という要望が来ても、
  この二重発火の踏み方だけは繰り返さないこと。
- **`NSOutlineView`の唯一のカラムは、`viewDidLayout()`で毎回明示的に幅を
  実サイズへ同期させる(`NSOutlineView.syncSingleColumnWidthToBounds()`、
  2026-09-06修正)**。デフォルトの`columnAutoresizingStyle`
  (`.lastColumnOnlyAutoresizingStyle`)は「テーブル自身のフレーム変更イベント」に
  追従して差分を配分する方式で、サイドバーの実サイズが確定するタイミング次第では
  反映されないことがある。年/月フォルダツリーを実機で確認したところ、サイドバーの
  右側に余白がたっぷり残っているのに`すべて (1944)`のようなラベルが
  `すべて (19`で`lineBreakMode`により途切れる、という症状で発覚した ―
  カラム自体が古い(狭い)幅のまま止まっていて、セルはその狭い幅の中で正しく
  truncateしていただけだった。ローカルの`SidebarViewController`も同じ
  `NSOutlineView`パターンなので、同じ不具合が潜在している可能性が高いと判断し
  予防的に同じ修正を入れてある。新しく`NSOutlineView`を使うサイドバーを追加する
  ときは、単一カラムなら必ずこの`viewDidLayout()`パターンを使うこと ―
  `autoresizesOutlineColumn = true`や既定の`columnAutoresizingStyle`だけに
  頼らないこと。
- **上の`viewDidLayout()`修正だけでは直らなかった ― 真因は`NSScrollView`/
  `contentContainer`が乗っている垂直`NSStackView`側にあった(2026-09-06、
  実機で再確認して発覚)**。垂直`NSStackView`の既定の`alignment`は`.centerX`で、
  アレンジ済みサブビューをスタックの幅いっぱいに広げてはくれない ―
  明示的な幅制約が無いサブビューは自分の intrinsic content size(＝中身なりの幅)
  にセンタリングされるだけ。`NSScrollView`自体は幅について強い意見を持たない
  (`NSViewNoIntrinsicMetric`)ため、この場合の「intrinsic width」は結局中の
  `NSOutlineView`の列幅から逆算される ― つまり
  `scroll.widthAnchor`を`container`(スタック本体)に明示的に揃えない限り、
  「列幅をスクロールビューの実際の幅に同期する」`viewDidLayout()`の修正と
  「スクロールビューの幅は列幅から逆算される」という関係が堂々巡りになり、
  サイドバーの右側に余白が残ったまま列幅だけ古い(狭い)値で安定してしまう。
  影響箇所は2箇所:
  - `OneDriveFolderTreeViewController.loadView()`の`scroll`
  - `SidebarModeContainerViewController.loadView()`の`contentContainer`
    (「ローカル」/「動画(OD)」/「画像(OD)」3タブすべての中身が乗る一番外側の
    コンテナ ― ここが直っていないと配下の`viewDidLayout()`修正だけでは絶対に効かない)
  いずれも`◯◯.widthAnchor.constraint(equalTo: container.widthAnchor).isActive = true`
  を追加して解消した。**垂直`NSStackView`にスクロール可能な子ビュー
  (特に`NSOutlineView`/`NSTableView`を積んだ`NSScrollView`)を入れるときは、
  必ず明示的な幅制約を張ること** ― `alignment`の既定値に幅を埋める効果は無い、
  という前提で書くこと。

### ローカル/動画(OD)/画像(OD)の3タブ切り替え(2026-09-06、決め打ちリンクへ回帰)

`SidebarModeContainerViewController`(`OneDriveSidebarViewController.swift`)が
サイドバー上部の3セグメントコントロールと、選択に応じて中身を差し替えるコンテナ。
子ビューコントローラーは3つ: `localVC`(既存の`SidebarViewController`、一切変更なし)・
`videoVC`・`photoVC`(どちらも`OneDriveFolderTreeViewController`、それぞれ
`OneDriveLinks.video`/`.photo`という固定リンクを1つだけ受け持つ)。

**タブを開いたら自動で読み込む**(「読み込み」ボタンを押す手順は無い):
`MainWindowController.onModeChanged`が動画(OD)/画像(OD)への切り替えを検知すると
`activateOneDriveTab(_:)`を呼び、`MainWindowController.oneDriveCache`
(`[OneDriveLink.id: [PhotoItem]]`、セッション中のメモリキャッシュ)にまだ無ければ
その場でスキャンする(`loadOneDrive(vc:)`)。すでにこのセッションで読み込み済みなら
ネットワークへは行かず、キャッシュを再フィルタして即座にグリッドへ出す ―
タブを行き来するたびに毎回スキャンし直すのは無駄なため。

**フォルダツリーのチェック状態は`UserDefaults`(`GallerySettings
.folderTreeSelections`、リンクIDごと)に永続化し、次にそのタブを開いたときに
自動で復元する** ― 「動画(OD)を開いたら前回選んでいたものを自動でロードしたい」
というユーザー要望への対応。`OneDriveFolderTreeViewController.setRoot(_:)`が
読み込み完了のたびに保存済みの選択(無ければ全フォルダ)を復元し、
`checkboxToggled(_:)`がトグルのたびに保存し直す。パスの配列(`[String]`)は
`Set`のCodable保存に向かないため、`/`区切り文字列にエンコードしてから保存する
(`OneDriveFolderTreeViewController.encode(_:)`/`decode(_:)`)。

`MainWindowController.isOneDriveMode`がローカル以外の2タブを反映し、ローカル専用機能
(回転・ゴミ箱・Finder表示・コピー・重複検出・Visionベースの人物/種類フィルター・
画質順ソート)を`validateMenuItem`で無効化する。**`reloadGrid()`自体も
`isOneDriveMode`の間はno-opにしている** ― 動画(OD)/画像(OD)ブラウズ中に⌘Oで
ローカルフォルダを開こうとした場合は`setRoot(_:)`の冒頭で`sidebarContainerVC.
switchToLocal()`を呼んでローカルモードへ強制的に戻してから処理する(戻さないと
`reloadGrid()`がno-opのまま「読み込み中…」から進まなくなる)。

**既知の粗さ**: ツールバーのフィルター/並び替えポップオーバーの表示・操作自体は
OneDriveタブ中も無効化していない(押せてしまう)。フィルター(人物・種類)は
ローカル専用のVision解析が前提のため、選んでも実際にグリッドが書き換わることはない
(`reloadGrid()`がOneDriveモード中はno-opなので素通りする)。ボタン自体を
グレーアウトするには`NSToolbarItemValidation`の実装が必要で、今回はスコープ外にした。
**並び替えポップオーバーだけは2026-09-07に修正済み** ― `toggleSortPopover`の
`onSelect`が常に`reloadGrid()`(OneDriveでno-op)を呼んでいたため、OneDriveタブで
ツールバーからサイズ順等を選んでも反映されない不具合があった。メニュー経由の
`changeSort(_:)`と同じく`isOneDriveMode`なら`resortOneDriveGrid()`を呼ぶよう分岐した
ので、名前順・日付順・サイズ順はツールバー側からも機能する(画質順は上記の理由で
そのまま無効)。

### 再読み込みボタン(2026-09-07)

「ネットワーク切れでサムネが取得されないときがある」というユーザー要望への対応。
ツールバーに`arrow.clockwise`アイコンの「再読み込み」ボタン(`reloadItemID`)を
`.toggleSidebar`の直後に追加し、既存の`refresh(_:)`(ファイルメニュー「再読み込み」、
元はローカル専用)にそのまま繋いだ。`refresh(_:)`は`isOneDriveMode`で分岐する:

- ローカル: 従来通り`store.rescan()`(全体再スキャン)。
- OneDrive: `sidebarContainerVC.currentMode`(2026-09-07追加のプロパティ、
  `modeChanged()`が更新)で今どちらのタブ(ビデオ/写真)を見ているか判定し、
  対応する`videoVC`/`photoVC`に対して`loadOneDriveFolderStructure(vc:)`を
  もう一度呼ぶ ― タブを開き直したときとまったく同じ経路(フェーズ1から
  やり直し、`oneDriveCache[link.id]`を空にしてフェーズ2も再取得)。フォルダ
  構成自体は変わっていないことが多いため体感はフェーズ1がほぼ一瞬で終わり、
  フェーズ2(サムネイル取得)だけが実質的に再試行される形になる ―
  個々のサムネイルの取得失敗(`ThumbnailLoader.request`)はそもそも失敗結果を
  キャッシュしない設計なので、グリッドの再描画だけでも実は再試行されるが、
  フォルダ一覧の取得自体がネットワーク切れで丸ごと失敗していたケース
  (`loadOneDriveFolderStructure`が「読み込みに失敗しました」エラーで
  終わった場合)はこの再読み込みボタンでフェーズ1からやり直さないと復旧しない。
  `validateMenuItem`のメニュー版「再読み込み」も同じ理由でOneDriveモード中は
  有効にした(以前はローカル専用だった)。

**動画の再生自体は`ViewerOverlay`/`openViewer`/`stepViewer`に一切手を入れていない**
― これらは元々`gridVC.items`が何であるか(ローカルかOneDriveか、どうフィルタ
されているか)を意識しない作りなので、フォルダツリーで月フォルダまで絞り込めば
そのままダブルクリックで1本ずつ再生でき、次へ/前へも絞り込んだ範囲内を移動する。

### 読み込みの2段階化: フォルダ構造 → チェック済みフォルダの中身(2026-09-06、
### 同日中にYear/Monthの2階層固定・年フォルダごとのストリーミング表示へ改修)

「OneDriveのタブを開いたら、まずディレクトリ(年/月)だけ先に表示し、その後で
チェックされているフォルダのサムネイルを適宜(順次)表示してほしい」という
ユーザー要望への対応。以前は`OneDriveMediaClient.scan(shareURL:onlyTopLevelFolders:)`
1回で「選んだ年フォルダの中身(実際の写真・動画ファイル)まで全部集め終わってから
返す」設計だった。写真・動画が多い月フォルダがあると、フォルダツリーがサイドバーに
出るまでですら長く待たされる(何百件ものファイルのページングが終わるまで、木構造の
土台となる年/月フォルダの一覧すら分からない)のがボトルネックだった。

**実際のライブラリはYear/Month/Dayの3階層(日付フォルダ)まであるが、フォルダツリー
での表示・チェックはYear/Monthの2階層までで十分**というユーザー判断により、
フェーズ1は常にMonthを葉として扱い、それより深くは辿らない(下記)。

- **フェーズ1** `OneDriveMediaClient.scanFolderStructureStream(shareURL:onlyTopLevelFolders:)`
  ― フォルダ階層をYear/Monthの2階層だけ取得する`AsyncThrowingStream`。ルート直下の
  年フォルダ(`onlyTopLevelFolders`＝`link.availableFolders`で絞り込み済み)ごとに
  `walkYearFolderWithRetry`→`walkYearFolder`がMonthフォルダの一覧(`OneDriveFolderRef`、
  `children`はMonthノードで打ち止め、実体は無し)を1件取得するたびに、**その年フォルダ
  1つぶんを`(sourceName, yearFolder)`としてストリームへ流す**(全年フォルダぶん揃うまで
  待たせない ― 「レイヤーごとに徐々に表示してほしい」というユーザー要望への対応)。
  Monthより深く(Day以下)は覗きに行かない ― 以前あった「最初の1ページだけ見て
  サブフォルダの有無を判定し、無ければ葉とみなす」`walkFolderStructure`の可変深さ探索は
  廃止し、「常にYear→Monthの2ホップで打ち切る」固定深さに単純化した。
  `MainWindowController.loadOneDriveFolderStructure`が`for try await`でこのストリームを
  消費し、最初の1件が届いた時点で`vc.beginIncrementalLoad(rootName:)`(空のルートだけ
  即座にサイドバーへ出す)を呼び、以降は届くたびに`vc.addTopLevelFolder(_:)`で
  ルート直下へ追加(名前順に並べ直し、`OneDriveFolderTreeViewController.nodesByPath`へ
  索引)していく。全年フォルダが届き終わったら`vc.finishIncrementalLoad()`(保存済みの
  チェック選択がどれとも一致しなかった場合の「全選択に戻す」フォールバックのみ、
  下記参照)。
- **フェーズ2** `OneDriveMediaClient.scanLeafFolders(shareURL:folders:)` ― フェーズ1で
  見つかった葉(＝Month)フォルダのうち、**現在チェックされていてまだ取得していないもの**
  (`OneDriveFolderTreeViewController.uncachedCheckedLeaves()`)だけを`TaskGroup`で
  並列に取得し、`AsyncThrowingStream`で**取得できたものから順に**返す。実データの
  取得を担う`scanLeafFolderItems`は**Monthフォルダ配下を再帰的に辿る**(Day以下の
  サブフォルダがあっても`children`を追って集め、見つかった項目はすべてMonthの
  `pathComponents`のまま`MediaItem.folderPath`に積む ― Day単位の内訳は表示・チェックの
  対象外なので保持しない)。`MainWindowController.loadOneDriveLeaves`が1フォルダぶん
  届くたびに`oneDriveCache`へ追記し、`vc.recordLoadedItems(count:at:)`でそのフォルダ(と
  祖先)の件数表示を更新し、`refreshOneDriveGrid`でグリッドを再描画する ―
  全フォルダぶん揃うまで待たせず、届いた分から順にサムネイルが増えていく。
  葉フォルダの`(件数)`表示は、チェック済みなのにまだ`itemsLoaded`でなければ
  `…`(読み込み中)を出す(`OneDriveFolderTreeViewController.countLabel(for:)`)。
- **フェーズ2は「フェーズ1が全部届き終わってから1回だけ」起動する**
  (`loadOneDriveFolderStructure`が`vc.finishIncrementalLoad()`の直後に1回だけ
  `loadOneDriveLeaves`を呼ぶ)。**年フォルダが1つ届くたびに毎回呼んではいけない** ―
  `uncachedCheckedLeaves()`は「取得中(in-flight)」を追跡しておらず「取得済み
  (`itemsLoaded`)」しか見ていないため、フェーズ1のストリーム中に何度も呼ぶと同じ
  Monthフォルダに対して複数のフェーズ2タスクが並行して走り、`oneDriveCache`に
  同じ写真が重複して積まれる(2026-09-06、レイヤーごとの随時表示を実装した際に
  踏みかけた不具合 ― 実装時に気づいて1回だけ呼ぶ設計に修正済み)。
- **チェックボックスをトグルしたとき**(`oneDriveCheckedChanged`)も同じ
  `loadOneDriveLeaves`を再利用する ― 新しくチェックが入ったのに未取得の葉があれば
  そのぶんだけ追加でフェーズ2を走らせる(いつチェックしても、その場で埋まる)。
  タブを離れている間にフェーズ2が世代カウンタ(`oneDriveLoadGeneration`、下記)で
  打ち切られていた場合も、`activateOneDriveTab`がタブへ戻ってきたタイミングで
  同じ`loadOneDriveLeaves`を「取りこぼしの自己修復」として呼ぶ(`uncachedCheckedLeaves()`
  が空なら何もしない安全な呼び出しなので、無条件に呼んでよい)。
- **`MainWindowController.oneDriveLoadGeneration`は「新しくタブを開いてフェーズ1を
  やり直す」ときだけ**インクリメントする(`loadOneDriveFolderStructure`内)。
  チェックボックスのトグルやタブ再訪問時の「取りこぼし自己修復」はインクリメント
  **しない** ― 同じ世代のまま追加のフェーズ2を積めるので、動画(OD)タブのフェーズ2が
  流れている最中に画像(OD)タブを初めて開いても、互いの世代番号を潰し合わない
  (画像(OD)側のフェーズ1だけが新しい世代になり、動画(OD)側の進行中フェーズ2は
  そのまま生き続ける)。
  - **この「gen を増分しない」設計が、2026-09-07に踏んだ実際のバグの原因だった**
    ― 「動画タブを押したのに写真タブに移動してしまう(実際はグリッドの中身だけ
    写真に戻る)」という症状で発覚。写真タブを見ている間にフェーズ2がまだ
    実行中の状態で動画タブ(**すでにこのセッションでキャッシュ済み**)へ切り替えると、
    `activateOneDriveTab`はgenを増分せずそのまま`loadOneDriveLeaves`を呼ぶ ―
    つまり写真タブの古いフェーズ2タスクも動画タブの新しいフェーズ2タスクも
    **同じ世代番号を共有したまま**両方生き続ける。写真タブの古いタスクが後から
    結果を届けたとき、`oneDriveLoadGeneration == gen`のガードだけでは
    「タブそのものは切り替わった」ことを検出できず、`refreshOneDriveGrid`が
    全タブ共有の`gridVC.items`を写真の内容で上書きしてしまっていた。
    修正は`MainWindowController.isActiveOneDriveVC(_:)`(`sidebarContainerVC
    .currentMode`と比較して、渡された`vc`が今まさに表示中のタブ本人かどうかを
    見る)を追加し、`refreshOneDriveGrid`の冒頭と、`loadOneDriveFolderStructure`
    内で`gridVC`を直接触っている箇所(`setEmptyState`)すべてに、gen チェックとは
    **別に**このチェックを重ねること。gen は「この非同期タスクの結果がまだ有効か
    (新しい読み込みで上書きされていないか)」だけを見るもので、「今どのタブを
    見ているか」とは別の軸 ― 両方を混同しないこと。`vc`のサイドバー内部状態
    (`beginIncrementalLoad`/`addTopLevelFolder`/`recordLoadedItems`等)や
    `oneDriveCache[link.id]`への追記はタブが非表示でも継続してよい(次にそのタブを
    開いたときのために先読みしておける)ので、**ガードするのは`gridVC`(全タブ
    共有の唯一のグリッドビュー)への書き込みだけ**に絞ってあることに注意
    ― 無関係な内部状態更新まで止めると「タブを開き直すたびに再読み込みが
    必要になる」という別の退化を招く。
- 並べ替え: `PhotoItem`はOneDriveの元ファイル名を保持しない(`url`が署名付き
  ダウンロードURLで、元のファイル名を反映しない)ため、`refreshOneDriveGrid`は
  `folderPath`(月フォルダ単位でグループ化)→`mtime`の順でソートする。フェーズ2は
  フォルダが完了した順(ネットワークの応答順であって日付順ではない)に届くため、
  グリッドを更新するたびに並べ直す必要がある。
- **フェーズ2のトークンは必ず`resolveShare(shareURL:token:)`で一度この共有リンクへ
  「redeem」してから使うこと**(2026-09-06、実機で「フォルダ一覧(フェーズ1)は
  出るのに、サムネイル取得(フェーズ2)の段になるとAccess deniedになる」不具合を
  確認して発覚)。フェーズ1は`mintToken()`の直後に必ず`resolveShare(shareURL:token:)`
  (`Prefer: autoredeem`)を呼んでから同じトークンを使い回している。フェーズ2は
  性能上の理由からフェーズ1のトークンを使い回さず独自に`mintToken()`で取り直す
  設計になっているが、取り直しただけの匿名トークンはこの共有リンクに対して
  一度もredeemされていないため、`driveId`/`itemId`へ直接`children`リクエストを
  投げるとAPIがAccess deniedを返す。`scanLeafFolders(shareURL:folders:)`が
  `mintToken()`の直後に`resolveShare(shareURL:token:)`を(結果を使わず)必ず
  呼んでいるのはこのため ― この呼び出しを「無駄な往復」と見て削らないこと。

`OneDriveFolderTreeViewController`自体(年/月のチェックボックスツリー)はローカルの
`SidebarViewController`とほぼ同じ設計(`FolderNode`→`OneDriveFolderNode`、
`checkedPaths: Set<String>`→`Set<[String]>`、チェックは親→子に伝播、既定は全チェック)。
`beginIncrementalLoad(rootName:)`/`addTopLevelFolder(_:)`/`finishIncrementalLoad()`の
3つで年フォルダごとの随時追加を行う(一括版の`setRoot(_:)`は使われなくなったため
削除済み)。チェック絞り込みは**すでに取得済みの全件(`MainWindowController.oneDriveCache`)を
ローカルでフィルタして`gridVC.items`に反映するだけ**で、ローカルモードの
`PhotoStore.photos(checkedPaths:order:)`と同じ「チェック済みパスが祖先(または
自分自身)なら含める」判定を`folderPath`配列のプレフィックス一致で行う
(`OneDriveFolderTreeViewController.filteredItems(from:)`)。

### サムネイルはOneDriveのサーバー側生成済み画像を使う(2026-09-07)

「サムネの取得にスピードアップ方法ないか?」というユーザー要望への対応。それまで
`ThumbnailLoader.generateCG`は、OneDriveアイテムでも`item.url`(`@content.downloadUrl`
＝元ファイルそのもの、写真で数MB・動画で数十MB)をローカルに丸ごとダウンロードして
から`CGImageSourceCreateThumbnailAtIndex`/`AVAssetImageGenerator`で縮小しており、
512px程度のグリッドサムネイル1枚のためだけに毎回フルサイズの転送が発生していた
(これがユーザー体感の遅さの主因)。

実機のOneDrive共有リンクに対して`curl`で直接検証したところ(トークン取得
→`resolveShare`→`children`一覧という、このアプリの認証フローをそのまま踏襲)、
`children`一覧取得時に**`&expand=thumbnails(select=large)`を付けるだけで、写真・
動画どちらのアイテムにも`thumbnails[0].large.url`という、OneDrive側がサーバーで
生成済みの数百px・数十KBのJPEGサムネイルURLが同じレスポンスに一緒に返ってくる**
ことを確認した(動画も静止画のポスターフレームとして返る)。追加のAPI呼び出しは
不要 ― フェーズ2(`scanLeafFolderItems`、実ファイル一覧)の`children`リクエストに
このクエリを足すだけで済む。

- `OneDriveMediaClient.childrenURL(driveId:itemId:expandThumbnails:)`が
  `expandThumbnails: true`のとき`&expand=thumbnails(select=large)`を付ける。
  **フェーズ1(`walkYearFolder`、フォルダ構造だけ)には付けない**(フォルダの
  サムネイルは不要な追加コストのため) ― `scanLeafFolderItems`(フェーズ2)だけが
  `expandThumbnails: true`で呼ぶ。
  - なお`@odata.nextLink`(2ページ目以降のURL)はサーバーが元のクエリを保持したまま
    発行するため、`expand`パラメータを手動で足し直す必要はない(未検証だが
    OData の一般的な挙動として妥当と判断 ― もし2ページ目以降でサムネイルが
    抜ける不具合を見つけたら、まずここを疑うこと)。
- `MediaItem.thumbnailURL: URL?`(`makeMediaItem`が`item.thumbnails?.first?.large`
  から生成、無ければ`nil`)→`PhotoItem.thumbnailURL`とバケツリレーする。
- `ThumbnailLoader.request(_:completion:)`が`item.thumbnailURL ?? item.url`を
  フェッチ元に使う。**サムネイルURLを使うときは`isVideo`を`false`扱いにする**
  (`item.thumbnailURL == nil && item.isVideo`) ― OneDriveのサムネイルは動画でも
  常に静止画JPEGとして返るため、`generateCG`を写真の経路(`CGImageSource`、軽い)に
  流す。`isVideo`を`true`のままにすると`AVAssetImageGenerator`に静止画JPEGの
  URLを渡すことになり動作しない。
- ローカルアイテムは`thumbnailURL`が常に`nil`なので、`item.url`(実ファイル)に
  フォールバックする従来通りの経路のまま ― ローカル側の速度・挙動は変わらない。
- **ビューアのフルサイズ表示(`ViewerOverlay.show`、`ThumbnailLoader.generate(url:
  isVideo:maxPixel:4096)`)は意図的にこの変更の対象外** ― `photo.url`(元ファイル)を
  そのまま使い続ける。`large`サムネイルは数百pxしかなく、実際に写真を見るときの
  画質には全く足りないため、グリッドサムネイル生成だけをこの軽量経路に切り替えた。

### OneDriveスキャンの必須パフォーマンス設計(退化させるとリグレッションになる)

`myslideshow/`(削除済み)の`CLAUDE.md`に記録されていた、実際に踏んだ失敗の経緯を
踏まえて`OneDriveMediaClient.swift`に移植済み。**以下を退化させると
「年/月/日と深くネストした実際のOneDriveライブラリで著しく遅くなる」という
過去に実証済みの不具合が再発する**:

- `scanFolderStructureStream(shareURL:onlyTopLevelFolders:)`を使うこと ― 選択した
  フォルダだけをルート直下で絞り込んでから`walkYearFolder`でMonthまで辿る。「まず
  全階層スキャンしてから事後的に絞り込む」設計に戻さないこと。`onlyTopLevelFolders`には
  常に`link.availableFolders`(決め打ちの全年フォルダ)を渡している ―
  「ユーザーに選ばせるUIを廃止した」だけで、スキャン範囲を絞る仕組み自体は
  そのまま生きている。
- フェーズ1がMonthより深く(Day以下)を辿らないのは意図的な仕様(表示・チェックは
  Year/Monthまでで十分というユーザー判断) ― ただし実データはDay以下にあるため、
  フェーズ2の`scanLeafFolderItems`は**Monthフォルダ配下を再帰的に**辿って回収する
  設計を維持すること。フェーズ2側を「Month直下だけ見る」非再帰に戻すと、実際の
  Year/Month/Day運用では常に0件になる。
- サブフォルダの並列探索(`TaskGroup` + `ConcurrencyLimiter`で同時8リクエストに
  制限)を維持すること ― `walkYearFolder`・`scanLeafFolders`・
  `scanLeafFolderItems`の再帰とも同じ`concurrencyLimiter`を共有している。逐次探索に
  戻さないこと。
- `walkYearFolderWithRetry`の一時的ネットワークエラー(`.networkConnectionLost`/
  `.timedOut`)自動リトライを維持すること。

### スライドショーの実装方針: `ViewerOverlay`を拡張、新しい別ビューは作らない

`SlideshowController`は既存の`ViewerOverlay`(グリッドに被せるオーバーレイ、
写真表示+`AVPlayerView`)をそのまま流用する。`ViewerOverlay`への変更は最小限に
絞った:

- `slideshowMode: Bool`フラグ、`onVideoFinished`/`onTogglePause`クロージャを追加。
- `keyDown`のSpaceキー分岐: `slideshowMode`のときは一時停止/再開、通常時は
  従来通り(写真のみ閉じる、動画は無視)。
- 動画再生時、`slideshowMode`なら`.AVPlayerItemDidPlayToEndTime`を観測して
  `onVideoFinished`を呼ぶ(通常の手動視聴では観測しない)。あわせて
  `playerView.controlsStyle`を`slideshowMode`時は`.none`にする ― 自前の
  コントロールバーとAVKit標準コントロールを二重に持たせないため。

コントロールバー(前へ/一時停止・再開/次へ/終了)と日付ラベルは`ViewerOverlay`を
直接いじらず、**別の`SlideshowControlsView`を`ViewerOverlay`の上に重ねて追加する**
という設計にした(Swiftのextensionは別ファイルからstored propertyを追加できない
制約があるため、というのが直接の理由だが、既存の手動視聴コードパスに触れずに
済むという副次的なメリットもある)。`SlideshowControlsView.hitTest(_:)`は
コントロールバー・日付ラベルの実際のフレーム外ではクリックを`nil`にして
下の`ViewerOverlay`(ダブルクリックで閉じる等)へそのまま通す ―
`NSTrackingArea`によるマウス移動検知はhitTestとは独立した仕組みなので、
この`hitTest`オーバーライドがあってもマウス移動での表示/自動非表示は影響を受けない。

マウス移動でのコントロールバー表示に`window.acceptsMouseMovedEvents = true`が
必要 ― `SlideshowController.start()`内で一度trueにするが、スライドショー終了時に
falseへ戻す処理はしていない(他の画面がmouseMovedを実装していないため実害はない、
という判断)。

終了(✕ボタン/Esc)後、MySlideshowは「ホーム画面に戻る」動作だったが、MyGalleryは
**ビューアを開いたまま最後に見ていた写真の位置に留まる**(スライドショーの
タイマー・コントロールバーだけ止まる)。MyGalleryは元々ブラウジングアプリで
「ホーム画面」に相当する概念が無いため、この方が自然と判断した意図的な差異。

`gridVC.items`(現在サイドバーの選択・フィルターの結果表示されているもの)を
そのままスライドショーの対象にする ― ローカル・OneDriveどちらでブラウズ中でも
同じ`startSlideshow(_:)`が動く。

### 通常視聴ビューアでの動画ファイル名日付表示(2026-09-07)

「ファイル名から年月日を出して、動画再生時に表示してほしい」というユーザー要望
への対応。スライドショー専用だった`FilenameDateParser`(`SlideshowController.swift`、
ファイル名から`YYYYMMDD`パターンを拾う)を、通常の(スライドショーでない)手動視聴
ビューアでも使うようにした。`ViewerOverlay.show(photo:index:total:)`の`infoLabel`
(画面上部の「ファイル名 — index/total」表示、常時表示でスライドショー専用ではない)
に、**動画のときだけ**パース結果を追記する(写真では出さない ― スライドショーの
日付ラベルと役割が重複するため、あえて動画に絞った)。日付フォーマットは
`SlideshowControlsView`の`dateFormatter`(`.medium`)と同じ体裁を`ViewerOverlay`側にも
複製している(private staticなので共有できない ― 同じ体裁を保つことだけ意識すれば
よく、共通化するほどの重複ではないと判断)。

### サムネイル一覧の年月区切り線(2026-09-07)

「サムネイル一覧側に、年、月ごとに水平線みたいなものを表示できないか」という
ユーザー要望への対応。`NSCollectionViewFlowLayout`の**セクション**機能を使った
― セクションが変わると自動的に改行される(前グループの残りが同じ行に混ざらない)
ため、区切り線をセクションヘッダーとして描く設計にした。`DateSectionHeaderView`
(`NSView`、タイトルラベル+`NSBox(.boxType = .separator)`の水平線)を
`NSCollectionView.elementKindSectionHeader`として登録し、
`GridViewController.collectionView(_:viewForSupplementaryElementOfKind:at:)`で
返す。

- `GridViewController.groupingEnabled: Bool`(既定`true`)を
  `MainWindowController`が`sortOrder`のdidSetから`sortOrder.isDateOrder`
  (新しい順/古い順のときだけ`true`)で設定する。日付順以外(名前順/サイズ順/
  画質順)では常に1グループに固定し、ヘッダーの高さも`.zero`にして完全に
  非表示にする ― 名前順等で日付グルーピングしても表示順と噛み合わないため。
- `recomputeGroups()`が`items`(現在の表示順のまま)を`PhotoItem.sortDate`の
  年月が変わる境界で連続run分割する ― 表示順に使っているソートキーと同じ
  基準(ファイル名優先の撮影日時、`mtime`ではない)でグルーピングしないと
  境界がずれるため。`items`が変わるたび(`didSet`)と`groupingEnabled`が変わる
  たびに呼ぶ。1グループしかない場合(全部が同じ月等)はヘッダーを出さない
  (`groups.count > 1`のときだけ`headerReferenceSize`を非ゼロにする)。

**このセクション分割は表示専用の派生データで、`items`(フラットな1本の配列)が
唯一の真実の順序という設計は崩していない** ― `MainWindowController`側
(`viewerIndex`・`stepViewer`・`openViewer(at:)`・スライドショー等)は
`gridVC.items`をそのままフラットなインデックスで扱い続けており、**一切変更
していない**。セクション分割の影響を受けるのは`GridViewController`と
`GridCollectionView`の内部だけに閉じ込めてある:

- `GridViewController`に`flatIndex(for indexPath:) -> Int`/
  `indexPath(forFlatIndex flat:) -> IndexPath`という相互変換ヘルパーを追加した
  (セクションごとの件数を線形に足し引きするだけ、O(セクション数))。
  `selectedItems`・`select(index:)`・`firstSelectedIndex`
  (`MainWindowController.startSlideshow`が使う)・`pasteboardWriterForItemAt`
  はすべてこの変換を経由するよう書き換えた。
- `GridCollectionView`(キーボード矢印での範囲選択・⇧クリック・⌘A・ダブル
  クリックで開く等、選択まわりの自前ロジックを持つクラス)は、**内部の算術は
  すべてフラットな`Int`のまま**(`keyboardAnchor`/`keyboardFocus`を
  `IndexPath?`から`Int?`に変更済み)にして、実際の`IndexPath`が必要になる瞬間
  (`selectItems(at:)`等のNSCollectionView APIを呼ぶ直前)だけ
  `indexPathForFlatIndex`/`flatIndexForIndexPath`という注入されたクロージャで
  変換する。`GridViewController.loadView()`がこれらのクロージャを配線する。
  **新しく`IndexPath(item:section: 0)`を直接組み立てるコードを書かないこと**
  ― セクションが1つとは限らないため、必ずこの変換ヘルパー/クロージャ経由にする。

### 「新しい順/古い順」はファイル名の日付時刻を優先する(2026-09-07)

「デフォルトの並び順は日付時間順にしてほしい」というユーザー要望への対応。確認
したところ実際の意図は「mtimeではなく、ファイル名に埋め込まれた撮影日時で
並べたい」だった ― `mtime`(ローカルはファイルの更新日時、OneDriveは
`lastModifiedDateTime`)は、OneDriveだとアップロード/同期日時であって撮影日時
ではないことが多く、ローカルでもコピー・バックアップ経由で書き換わりうるため、
「新しい順」で並べても実際の撮影順とズレることがある(この不信感は元々
`FilenameDateParser`のコメントに書かれていた前提で、月日バッジ・動画再生中の
日付表示・スライドショーの日付ラベルはすでにファイル名優先だった ― 並び替えだけ
`mtime`のままだったのが今回の対応漏れ)。

- `FilenameDateParser`(`SlideshowController.swift`)に`dateTime(from:)`を追加した。
  既存の`date(from:)`(日付のみ、`YYYYMMDD`)とは別に、`YYYYMMDD`に続けて
  `HHMMSS`(区切り文字はあってもなくてもよい)まで拾えるかを試す
  `dateTimeRegex`を使う ― `2024_0101_191824.jpeg`のようなカメラ標準の命名
  (年月日_時分秒)が主なターゲット。時刻部分が数字的に不正/末尾に余分な数字が
  続く場合は正規表現の否定先読み(`(?![0-9])`)によって自動的に「時刻なし
  (日付のみ)」の一致へバックトラックする ― 誤った時刻を拾うより「時刻なし」の
  方が安全という判断。`date(from:)`(バッジ表示用)は変更していない ― 呼び出し元
  (`monthDayText`等)は日付だけで十分なため。
- `PhotoItem.sortDate`という計算プロパティを追加: `FilenameDateParser
  .dateTime(from: name) ?? mtime`(ファイル名から拾えなければ`mtime`に
  フォールバック ― ファイル名にパターンが無い写真でも並び替え自体は破綻しない)。
- `PhotoStore.photos(checkedPaths:order:)`の`.dateDesc`/`.dateAsc`と
  `MainWindowController.sortedForOneDrive(_:)`の同ケースを、`mtime`ではなく
  `sortDate`で比較するよう変更した。**「新しい順/古い順」という並び替え自体の
  意味が変わった**(以前:更新日時順、現在:撮影日時(取れなければ更新日時)順)ので、
  今後この並び替えに触るときは`mtime`に戻さないよう注意すること。

### OneDriveグリッドの並び替えを`sortOrder`に統一(2026-09-07)

「再生モードで、次のファイル、前のファイルに行けるようにしたい。その時にソート
された並び順で。デフォルトでは、日付順に並ばせたい」というユーザー要望への対応。
ビューアの次へ/前へ(←→キー、`ViewerOverlay.keyDown`→`onStep`→
`MainWindowController.stepViewer(_:)`)自体は既存機能で、`gridVC.items`(現在
表示中の配列)をそのまま辿るだけの実装だった。**問題は`gridVC.items`の中身側**
にあった: `refreshOneDriveGrid`(OneDriveのフェーズ2が1バッチ届くたびに呼ばれる、
つまりOneDriveタブでは実質「グリッドの並び順を最終的に決めている」関数)が
`folderPath`(月フォルダ単位)→`mtime`というハードコードされた順序で、ツールバー/
メニューの並び替え設定`sortOrder`(既定は`.dateDesc`＝新しい順、まさに
「デフォルトでは日付順」)を無視していた。ユーザーが並び替えを手動で変更しても
(`resortOneDriveGrid`、当時は`gridVC.items`をその場でin-placeソートするだけの
別実装)、直後にフェーズ2の続きが届いて`refreshOneDriveGrid`が呼ばれると、
選んだばかりの並び順が上書きされて元に戻ってしまう不具合もあった。

修正: `sortedForOneDrive(_ items:) -> [PhotoItem]`という単一の変換関数に統一し、
`refreshOneDriveGrid`と`resortOneDriveGrid`の両方がこれを経由するようにした。
`resortOneDriveGrid`は`gridVC.items`を直接いじるのをやめ、`refreshOneDriveGrid`
(キャッシュから絞り込み直す経路)を呼ぶだけに簡略化した ― 「どちらの経路でも
同じ`sortOrder`ベースの並び替えを通る」ことを構造的に保証し、上書き不具合の
再発を防ぐ。ローカル側は元々`PhotoStore.photos(checkedPaths:order:)`が
`sortOrder`に従っていたので今回の対象外(元々正しかった)。

### サムネイルの月日/ファイルサイズバッジ(2026-09-07、2スロット design に改修)

「サムネに月日を表示できる? 月日の表示はトグルにしたい」→「ファイルサイズの
表示トグルボタンもお願い。サイズソートのときは強制表示で。月日は左上にして、
ファイルサイズと重ならないように。あと1/1じゃなくてJan 1みたいにして」という
一連のユーザー要望への対応。**サムネイル1枚に左上/右下2つの独立したバッジ
スロットがある**(`PhotoCell`に`dateLabel`(左上)と`sizeLabel`(右下、既存)の
2つの`NSTextField`、`videoIcon`は左下なので重ならない):

- **左上 = 月日バッジ**。`GridViewController.showDateBadge: Bool`が単独で
  on/offを持つ(排他の相手がいない独立スロット)。`MainWindowController
  .showDateBadge`(`defaultsDateBadgeKey`で`UserDefaults`永続化)を、メニュー
  「表示 > サムネイルに月日を表示」(チェックマーク)とツールバーの`calendar`
  アイコンボタン(`dateBadgeItemID`、`.pushOnPushOff`で押し込み状態が残る見た目 ―
  「トグルはボタン式にしてほしい」への対応)の両方から`toggleDateBadge(_:)`経由で
  操作する。ボタンの`state`は`showDateBadge`のdidSetで毎回明示的に同期している
  (`dateBadgeButton`がweak参照、`.pushOnPushOff`自体のクリック時自動反転には
  頼っていない ― `showDateBadge`が唯一のsource of truth)。
  - 表示形式は`"MMM d"`(例: `Jan 1`)、`locale`を`en_US_POSIX`に固定した
    `DateFormatter`(`GridViewController.monthDayFormatter`) ― アプリ全体は
    日本語UIだが、この日付表記だけ意図的に英語(「1/1じゃなくてJan 1」という
    ユーザー指定)。
  - 日付の算出(`GridViewController.monthDayText(for:)`)は
    `FilenameDateParser.date(from: photo.name)`(ファイル名の`YYYYMMDD`パターン)を
    まず試し、拾えなければ`photo.mtime`にフォールバックする ― 動画再生中の
    日付表示・スライドショーの日付ラベルと同じ考え方(OneDriveの更新日時は
    アップロード/同期日時であって撮影日ではないことが多いため)。
- **右下 = サイズ/画質バッジ**(`GridViewController.thumbnailBadge:
  .none/.fileSize/.quality`、1スロットなので排他)。画質順ソート中は画質を
  最優先、それ以外は`MainWindowController.showSizeBadge`(トグルボタン
  `sizeBadgeItemID`、`scalemass`アイコン、`defaultsSizeBadgeKey`で永続化)が
  onならサイズ、**または`sortOrder.showsFileSize`(サイズ順ソート中)なら
  トグルの状態に関わらず強制的にサイズを表示する**(「サイズソートのときは
  強制表示で」への対応)。この優先順位の一本化ロジックが
  `MainWindowController.updateThumbnailBadge()`(`sortOrder`/`showSizeBadge`
  どちらのdidSetからも呼ばれる):
  ```
  画質順ソート中        → .quality
  showSizeBadge==true   → .fileSize
    またはサイズ順ソート中 → .fileSize (強制、トグルの状態は無視)
  それ以外              → .none
  ```
  月日バッジ(`showDateBadge`)はこのロジックの対象外 ― 独立スロットなので
  混ぜないこと。
- どちらのバッジもローカル・OneDrive両方で有効(`validateMenuItem`で
  無効化していない) ― サイズ順/画質順ソート自体は画質順だけOneDriveで無効化
  されているが、`PhotoItem.name`/`mtime`/`fileSize`はどちらのソースでも
  意味を持つ実値が入っているため、バッジ表示自体を制限する理由が無い。
- `PhotoCell.configure(with:badgeText:dateText:)`が2つの引数を取るように
  なった(旧`badgeText`単独から変更) ― 新しく`PhotoCell`を呼ぶコードを書くときは
  両方渡すこと(不要なら`nil`)。

**既知の不具合と保険的な対処(2026-09-07)**: 「起動時、月日トグルはONなのに
サムネイルにバッジが表示されない。手動で一度OFF→ONにすると表示される」という
ユーザー報告があった。`showDateBadge`/`thumbnailBadge`の値自体は
(`UserDefaults`からの復元・`gridVC`への反映まで)コード上は正しく`true`に
なっていることを確認済みで、AppKit側の挙動が原因と推測している ―
OneDriveタブはフェーズ2が届くたびに`gridVC.items`を(既存インデックスの要素を
保ったまま件数だけ増やして)何度も再代入するため、`NSCollectionView
.reloadData()`が**既存のインデックスパスに対応する画面上のセルビューを
使い回し、`itemForRepresentedObjectAt`を呼び直さない**(＝新しいバッジ状態が
反映されない)ケースに遭遇している可能性がある(ローカルは1回の代入で完結する
ため症状が出なかったと推測 ― ただし未確定)。根本原因を完全に特定できていない
ため、**保険として**`GridViewController.refreshVisibleBadges()`を追加し、
`items`/`thumbnailBadge`/`showDateBadge`いずれかが変わるたびに
`reloadData()`に加えて`collectionView.visibleItems()`を直接歩いて`configure`
し直すようにした(`itemForRepresentedObjectAt`とロジックを共有する
`configure(_:at:)`ヘルパーに統一済み)。**この不具合が再発した場合、まずこの
保険的対処が実際に効いているか(`refreshVisibleBadges`が呼ばれているか)を
確認すること** ― もし効いていなければ、真因はまだ別にある。

### 通常視聴ビューアでの動画自動連続再生トグル(2026-09-07)

「次の動画に自動再生、トグルボタンを作って」というユーザー要望への対応。既存の
スライドショー機能(`slideshowMode`、専用モードでタイマー・一時停止状態を持つ)
とは別に、もっと軽い「普段のブラウジング中に動画が終わったら次へ進むだけ」の
機能として`ViewerOverlay.autoplayNext: Bool`を追加した。動画の
`.AVPlayerItemDidPlayToEndTime`監視は`slideshowMode`(→`onVideoFinished`)と
`autoplayNext`(→新設の`onAutoAdvance`)の**どちらか一方**だけを条件分岐で登録する
(両方trueになる状況は無い想定だが、if/elseで排他にしてあるので万一重複しても
二重発火はしない)。`MainWindowController.openViewer`が
`v.onAutoAdvance = { [weak self] in self?.stepViewer(1) }`を配線している ―
次のアイテムが動画ならそのまま自動再生が続き、写真ならそこで静止する(スライド
ショーのような写真用タイマーは無い、単に「動画が終わったら次へ進む」だけ)。
最後のアイテムで動画が終わった場合は`stepViewer(1)`が範囲外で何もしないので、
そのまま自然に止まる(ラップアラウンドはしない)。

`MainWindowController.autoplayNextVideo`(`defaultsAutoplayNextKey`で
`UserDefaults`永続化)を、ツールバーの`forward.circle`アイコンボタン
(`autoplayNextItemID`、月日/サイズバッジと同じ`.pushOnPushOff`パターン)と
メニュー「表示 > 動画を自動再生」の両方から`toggleAutoplayNext(_:)`経由で
操作する。ローカル・OneDriveどちらでも制限なく使える(`ViewerOverlay`自体が
写真のソースを意識しない作りのため)。

### 動画再生失敗時のエラー表示(2026-09-07)

「サムネは取得できているファイルが再生できないときがある。何のエラーが表示して
コピペできるようにしてほしい」というユーザー要望への対応。それまで`ViewerOverlay`
は`AVPlayer(url:)`を作って`play()`を呼ぶだけで、失敗を一切観測していなかった
(再生ボタンを押しても無音で何も起きないように見えていた)。

- `AVPlayerItem.status`を`observe(\.status:)`でKVO観測(`statusObservation`)し、
  `.failed`になったら`item.error`を拾う ― 再生"開始前"の失敗(コーデック非対応、
  OneDriveの署名付きURLが期限切れ等)を検出する。
- `.AVPlayerItemFailedToPlayToEndTime`通知(`failedToPlayObserver`)も観測する ―
  いったん再生が始まった"後"にネットワーク切断等で失敗するケースは`.status`の
  KVOでは拾えないため、この通知が必要。
- どちらも`showPlaybackError(_:photoName:)`を呼ぶ。`NSAlert`の本文(`informativeText`)
  は選択・コピーできるとは限らないため、**「コピー」ボタンで確実に
  `NSPasteboard.general`へ全文コピーできるようにしてある** ― これがユーザーの
  「コピペできるようにしてほしい」という要望への直接の対応。表示内容は
  `NSError`の`localizedDescription`・`domain`/`code`・`localizedFailureReason`・
  `NSUnderlyingErrorKey`まで拾って並べる(原因の切り分け情報をできるだけ削らない)。
- どちらの監視も`show(photo:)`の冒頭(`videoEndObserver`の解除と同じ場所)と
  `viewDidMoveToSuperview()`(ビューアが閉じられたとき)の両方で解除している ―
  次の写真/動画に切り替わった後に古い監視のコールバックが誤発火しないよう、
  `currentPath`(`photo.cacheKey`)が一致するかも合わせてチェックしている
  (他の非同期コールバックと同じガード方針)。

### ローカルスキャンでもAppleDoubleファイルを名前ベースで除外する(2026-09-07)

`PhotoStore.rescan`は元々`FileManager.enumerator`の`.skipsHiddenFiles`オプションだけで
`._IMG_0001.MOV`のようなAppleDoubleファイルを弾いていたが、これはUF_HIDDENフラグ
ベースの判定で、SMB/NAS/外部ボリューム等ドットファイルにこのフラグが立たない
ボリュームでは取りこぼす ― 実機で「動画グリッドに`._`始まりのファイルが表示される」
不具合を確認して発覚した。OneDriveの`OneDriveMediaClient.makeMediaItem`は元々
`item.name.hasPrefix(".")`という名前ベースの明示チェックを持っていた(同じ理由で
`.skipsHiddenFiles`相当のOS機構に頼れないため)ので、ローカル側もそれに合わせて
`u.lastPathComponent.hasPrefix(".")`の明示チェックを追加した。`.skipsHiddenFiles`は
残したまま(通常ボリュームでの早期フィルタとして無害)、名前ベースのチェックを
保険として重ねている。

## 璃央フィルター(2026-11-09、v1.5)

「息子(璃央)の写真とそれ以外を分けたい」という要望への対応。`Sources/RioMatcher.swift`
(`build.sh`の`RIO_SRC`に追加済み)に`RioFilter`/`RioReferenceStore`/`RioFaceAnalyzer`/
`RioCache`。Visionに顔の個人識別APIは無いため、**ユーザーが登録した参照顔の
`VNGenerateImageFeaturePrintRequest`特徴量との距離**で近似している(顔認識専用ではなく
汎用の画像類似度なので精度は限定的。成長・向き・照明差に弱く、登録枚数を増やすほど安定)。

- 登録: 表示メニュー「選択中の写真を璃央として登録」(右クリックの「璃央として登録」でも可)(選択写真ごとに最大の顔1つ)/
  「璃央の登録をリセット」。参照は`~/Library/Application Support/MyGallery/rio-refs.dat`
  (NSKeyedArchiver、個人データなのでリポジトリには入れない)。
- 判定: フィルターポップオーバーの「璃央」(すべて/璃央/璃央以外)。写真内の全ての顔を
  特徴量化し参照との**最小距離をキャッシュ**(`RioCache`、参照変更時に`reset()`)。
  閾値(`PhotoFilter.rioThreshold`、既定0.5、スライダー0.2〜1.0)との比較だけなので、
  スライダー調整は再解析なしで即時反映。**既定値0.5は実データ未検証の仮値** ―
  実写真で調整が要る。
- パイプライン: 人物 → 種類 → **璃央** → 画質ソートの順(`applyRioFilter`)。人物/種類と
  同じく静止画・ローカル専用(動画は除外、OneDriveではno-op)。

## その他の既存アーキテクチャ

回転・重複検出・人物/種類フィルター・画質順ソートの詳しい実装は
[README.md](README.md)の「How it works」を参照(このCLAUDE.mdでは重複させない)。
