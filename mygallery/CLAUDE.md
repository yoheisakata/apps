# CLAUDE.md — mygallery

Photos.app 風のローカルフォルダ・フォトギャラリー。**SPM パッケージではない** —
`Sources/*.swift`(下記)を `build.sh` が直接
`swiftc` でコンパイルする、単一バイナリの Swift + AppKit アプリ。`swift build` は使えない。

機能・キーボード操作の一覧は [README.md](README.md) を参照。ここでは実装上の設計判断と、
今後変更するときに踏みやすい落とし穴を記録する。

**iPad版 `mygallery-ipad/`(MyGallery Pad)が2026-09-07に追加された** ―
OneDrive共有リンクのブラウズ専用の縮小版(ローカルフォルダ・Visionベースの
画質順ソート・重複検出・回転・削除は対象外)。`Core/OneDriveMediaClient.swift`は
このアプリのかつての`Sources/OneDriveMediaClient.swift`(2026-11-09削除)から移植したもの(mytube-ipad/
myslideshow-ipadと同様、pure Foundationのため無変更で動く)。**別コードベース**で、Mac版のOneDrive機能は削除されたため同期元は無い。詳細は
`mygallery-ipad/CLAUDE.md`参照。

## ファイル構成

`Sources/main.swift`を中心に、`build.sh`が次の4ファイルを`swiftc`で直接コンパイルする:

- `Sources/main.swift` — ローカルブラウズ本体。`PhotoItem`/`PhotoStore`/`ThumbnailLoader`/
  `GridViewController`/`SidebarViewController`/`ViewerOverlay`/`MainWindowController`/
  `AppDelegate` 等。
- `Sources/GallerySettings.swift` — スライドショー設定(UserDefaults)と
  `NSOutlineView.syncSingleColumnWidthToBounds()`。
- `Sources/SlideshowController.swift` — 自動連続再生スライドショー。`FilenameDateParser`も同居。
- `Sources/RioMatcher.swift` — 璃央フィルター(下記)。

`build.sh` の`swiftc`呼び出しはファイルを明示的に列挙している(グロブではない)。
**新しい `.swift` ファイルを追加したら `build.sh` の `build()`/`needs_build()` 両方に
追記すること** — 追記を忘れるとコンパイル対象に入らない、または`./build.sh`が再ビルドを
スキップしてしまう。

`build.sh`は`swiftc`に`-target arm64-apple-macosx${MIN_MACOS}`(現在26.0)を明示している
(2026-10-15)** ― macOS 27(Darwin 27)に上げた後、無指定の`swiftc`の既定ターゲットが
`macosx28.0`になり(Darwin N→macOS N+1と換算するため)、ビルドしたアプリが`minos 28.0`に
なって「このバージョンのmacOSでは使えません」と起動を拒否された。SPMアプリは
`Package.swift`の`platforms`で明示しているので影響しないが、`swiftc`直叩きのアプリ
(このアプリと`mymarkdown/`)は同じ罠を踏む。この`-target`指定は外さないこと。

## OneDrive機能は削除済み(2026-11-09、v1.6)

ユーザーの明示的な依頼(「OneDrive 機能は削除していい」)で、2026-09-02に旧MySlideshowから
統合したOneDrive共有リンクのブラウズ機能をすべて削除した: `Sources/OneDriveMediaClient.swift`・
`Sources/OneDriveSidebarViewController.swift`(サイドバーの「ローカル/ビデオ/写真」3タブ切替・
年/月フォルダツリー・決め打ち2リンク)・`MainWindowController`のOneDrive読み込み/キャッシュ/
並び替え経路・`PhotoItem`の`source`/`remoteID`/`folderPath`/`thumbnailURL`。`PhotoItem`は
ローカルファイル専用に戻り、`cacheKey`は`url.path`、サイドバーは`SidebarViewController`
単体。`GallerySettings`(スライドショー設定のUserDefaults)と`NSOutlineView.
syncSingleColumnWidthToBounds()`だけは生かして`Sources/GallerySettings.swift`へ移した。
**スライドショーはローカルの写真・動画でそのまま動く**(OneDriveとは独立の機能)。
**再追加しないこと**(ユーザーに確認なく復活させない)。必要になった場合の実装は git 履歴
(`df59ca4`以前、`mygallery/Sources/OneDrive*.swift`)にある。iPad版`mygallery-ipad/`は
OneDrive専用アプリで、このコードベースとは別 ― 影響を受けず、今後は自動的に同期する
元も無くなった。

**NSOutlineView/垂直NSStackViewの教訓(OneDriveツリーで踏んだが、ローカルの
`SidebarViewController`にも当てはまる)**: 単一カラムの`NSOutlineView`は`viewDidLayout()`で
`syncSingleColumnWidthToBounds()`を呼んで列幅を実サイズへ同期すること。垂直`NSStackView`に
`NSScrollView`を入れるときは明示的な幅制約を張ること(既定の`alignment`は幅を埋めない)。

## スライドショー機能(2026-09-02、旧MySlideshowから機能統合)

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
- **範囲選択で登録(v1.7)**: 全体表示(ビューア)の静止画上でドラッグして璃央の顔を囲み、
  「この範囲を璃央として登録」(または Return)で登録できる(複数人写った写真から正確に
  1人を指定できる)。`ViewerOverlay`の`mouseDown/Dragged/Up`で選択枠を描き、表示座標→
  画像ピクセル座標(アスペクトフィット領域`displayedImageRect()`基準、Y反転)に変換して
  `RioFaceAnalyzer.regionPrint`へ渡す。範囲内で顔検出できれば最大の顔を通常登録と同じ
  切り出し(25%余白)で使い、できなければ範囲そのものを特徴量化。重複キーは
  `cacheKey#選択ピクセル矩形`。結果は`showToast`(infoLabel)で通知。ダブルクリックで閉じる
  挙動はそのまま(ドラッグ開始はシングルクリックのみ)。
- パイプライン: 人物 → 種類 → **璃央** → 画質ソートの順(`applyRioFilter`)。人物/種類と
  同じく静止画・ローカル専用(動画は除外、OneDriveではno-op)。

## 手動仕分けモード(2026-11-09、v1.8)

「璃央が写っている写真と写っていない写真を手動でも分けたい。Tinderのように1枚ずつ表示して、
右=璃央、左=璃央以外(削除候補)」という要望。`Sources/SortMode.swift`(`build.sh`の`SORT_SRC`):
`ManualLabel`/`ManualFilter`/`ManualLabelStore`/`SortOverlay`。自動判定(`RioMatcher.swift`)とは
**独立**(互いに影響しない)。

- 起動: 表示メニュー「璃央の仕分けを始める」。**現在グリッドに出ている未仕分けの静止画**が
  対象なので、先にフィルター(日付・人物あり等)で絞ってから始められる。
- 操作: → 璃央 / ← 璃央以外 / ↓・Space スキップ / ↑・⌫・⌘Z 元に戻す / Esc 終了。
  下のボタン、画像の左右ドラッグ(120pt以上)でも可。次の2枚を先読みする。
- 結果は`~/Library/Application Support/MyGallery/rio-labels.json`(パス→rio/other)。
  **キーはファイルパス**なので、写真を移動・改名すると仕分けは失われる。
- **左に仕分けてもその場では削除しない**。表示メニュー「「璃央以外」に仕分けた写真を
  ゴミ箱へ…」で、チェック中のフォルダ内の対象を件数確認の上ゴミ箱へ(復元可)。
- 後からの修正: グリッドの右クリック「選択した写真を『璃央』/『璃央以外』に仕分ける」「仕分けを解除」
  (`applyManualLabel`)。仕分けモード中の直前の取り消しは ↑/⌫/⌘Z。
- フィルターポップオーバーの「仕分け(手動)」(すべて/璃央/璃央以外/未仕分け)で絞り込み。
  `applyFilter`で日付の直後に同期で適用(静止画のみ、動画は除外)。

## その他の既存アーキテクチャ

回転・重複検出・人物/種類フィルター・画質順ソートの詳しい実装は
[README.md](README.md)の「How it works」を参照(このCLAUDE.mdでは重複させない)。
