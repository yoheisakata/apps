# CLAUDE.md — mygallery

Photos.app 風のローカルフォルダ・フォトギャラリー。**SPM パッケージではない** —
`Sources/main.swift`(+ 2026-09-02 追加の3ファイル、下記)を `build.sh` が直接
`swiftc` でコンパイルする、単一バイナリの Swift + AppKit アプリ。`swift build` は使えない。

機能・キーボード操作の一覧は [README.md](README.md) を参照。ここでは実装上の設計判断と、
今後変更するときに踏みやすい落とし穴を記録する。

## ファイル構成(2026-09-02、OneDrive+スライドショー機能の統合で複数ファイルへ分割)

それまで `Sources/main.swift` 一本(3583行)だった構成に、MySlideshow(廃止済み、下記)の
機能を統合するにあたって3ファイルを追加した:

- `Sources/main.swift` — 元からのローカルブラウズ本体。`PhotoItem`/`PhotoStore`/
  `ThumbnailLoader`/`GridViewController`/`SidebarViewController`/`ViewerOverlay`/
  `MainWindowController`/`AppDelegate` 等。
- `Sources/OneDriveMediaClient.swift` — OneDrive共有リンクのスキャン(認証・ページング・
  並列walk)。`myslideshow/Sources/MySlideshow/Core/OneDriveMediaClient.swift` から
  ほぼそのまま移植。
- `Sources/OneDriveSidebarViewController.swift` — OneDriveリンクの追加・削除UI、
  サイドバーのローカル/OneDriveモード切替コンテナ、`GallerySettings`(UserDefaults)。
- `Sources/SlideshowController.swift` — 自動連続再生スライドショーの状態機械+
  コントロールバー・日付ラベルのオーバーレイビュー。`FilenameDateParser`もここに同居。

`build.sh` の `swiftc` 呼び出しはこの4ファイルを明示的に列挙している(グロブではない)。
**新しい `.swift` ファイルを追加したら `build.sh` の `build()`/`needs_build()` 両方に
追記すること** — 追記を忘れるとファイルが存在するのにコンパイル対象に入らず、
`swiftc` が未定義シンボルで失敗するか、最悪コンパイルは通るが変更が反映されない
(`needs_build`のタイムスタンプ比較が新ファイルを見ていないと`./build.sh`が
再ビルドをスキップしてしまう)。

## OneDrive + スライドショー機能(2026-09-02、旧MySlideshowから機能統合)

「MySlideshowの機能をMyGalleryに追加してほしい」というユーザー要望への対応。
MySlideshow(Mac版、`myslideshow/`)はこの統合の完了後に**削除済み**
(ルート`CLAUDE.md`参照)。`myslideshow-ipad/`は対象外でそのまま残っている。

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
- **MyGalleryだけの新機能(MySlideshowには無かった)**: OneDriveリンクの
  追加・削除UI。MySlideshowは「リンクはめったに変わらないのでハードコードで
  いい」という理由で追加・削除UIを持たなかったが、MyGalleryは汎用ギャラリー
  アプリなので、リンクをUIから追加・削除できる方が自然と判断した(ユーザー承認済み)。
  初回起動時はMySlideshowが使っていた2リンク(動画専用「動画」・写真専用「写真」、
  ともに2020〜2026年フォルダ)を`GallerySettings.oneDriveLinks`のデフォルト値として
  引き継ぐ(`OneDriveSidebarViewController.swift`の`GallerySettings.defaultLinks`)。

### データモデル: `PhotoItem`とローカル/OneDriveの二刀流

`PhotoItem`(main.swift）は元々ローカルファイル専用だったが、OneDriveアイテムも
表せるよう拡張した:

- `source: PhotoSource`(`.local` / `.oneDrive(linkID:)`)、`remoteID: String?`、
  `folderPath: [String]`を追加。
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

### ローカル/OneDriveの排他モード切り替え

`SidebarModeContainerViewController`(`OneDriveSidebarViewController.swift`)が
サイドバー上部の「ローカル」/「OneDrive」セグメントコントロールと、選択に応じて
中身(既存の`SidebarViewController` vs. 新規`OneDriveSidebarViewController`)を
差し替えるコンテナ。既存の`SidebarViewController`自体は一切変更していない。

`MainWindowController.isOneDriveMode`がこのモードを反映し、ローカル専用機能
(回転・ゴミ箱・Finder表示・コピー・重複検出・Visionベースの人物/種類フィルター・
画質順ソート)を`validateMenuItem`で無効化する。**`reloadGrid()`自体も
`isOneDriveMode`の間はno-opにしている** ― OneDriveブラウズ中に⌘Oでローカル
フォルダを開こうとした場合は`setRoot(_:)`の冒頭で`sidebarContainerVC.
switchToLocal()`を呼んでローカルモードへ強制的に戻してから処理する(戻さないと
`reloadGrid()`がno-opのまま「読み込み中…」から進まなくなる)。

**既知の粗さ**: ツールバーのフィルター/並び替えポップオーバーの表示・操作自体は
OneDriveモード中も無効化していない(押せてしまう)。ただし`reloadGrid()`が
no-opなので実際にグリッドが書き換わることはない ― データ破損やクラッシュには
ならないが、UI上「押しても何も起きない」という粗さが残っている。ボタン自体を
グレーアウトするには`NSToolbarItemValidation`の実装が必要で、今回はスコープ外にした。

### OneDriveスキャンの必須パフォーマンス設計(移植時に落とすとリグレッションになる)

`myslideshow/`(削除済み)の`CLAUDE.md`に記録されていた、実際に踏んだ失敗の経緯を
踏まえて`OneDriveMediaClient.swift`に移植済み。**以下を退化させると
「年/月/日と深くネストした実際のOneDriveライブラリで著しく遅くなる」という
過去に実証済みの不具合が再発する**:

- `scan(shareURL:onlyTopLevelFolders:)`を使うこと ― 選択したフォルダだけを
  ルート直下で絞り込んでから`walk`で深く辿る。「まず全階層スキャンしてから
  事後的に絞り込む」設計に戻さないこと。
- サブフォルダの並列`walk`(`TaskGroup` + `ConcurrencyLimiter`で同時8リクエストに
  制限)を維持すること ― 逐次`walk`に戻さないこと。
- `scanWithRetry`の一時的ネットワークエラー(`.networkConnectionLost`/
  `.timedOut`)自動リトライを維持すること。

`listTopLevelFolders(shareURL:)`はMyGalleryだけの新規追加(MySlideshowには無い) ―
リンク追加時に年フォルダ等の候補チェックボックスを自動取得するため、ルート直下
1ページだけを浅く列挙する。

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

## その他の既存アーキテクチャ

回転・重複検出・人物/種類フィルター・画質順ソートの詳しい実装は
[README.md](README.md)の「How it works」を参照(このCLAUDE.mdでは重複させない)。
