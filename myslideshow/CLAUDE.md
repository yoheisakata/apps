# CLAUDE.md — myslideshow

OneDrive共有リンク(フォルダ)内の写真・動画を、自動連続再生でテレビのように流しっぱなしに
するスライドショーアプリ。SwiftUI + SPM製の**新規・独立アプリ**(2026-08-29追加) ―
mytubeを拡張する形にはせず、あえて別アプリにした(「動画をスライドショーで見たい、
まずはネイティブ版から」というユーザー要望に対するAskUserQuestionで「新規の別アプリ」
「自動連続再生」「写真も混在」の3点を選んで確定した設計方針)。将来的にWeb版(pwa/配下)が
追加される可能性はあるが、ネイティブ版が先。

## ビルド / デプロイ

```bash
swift build         # コンパイル確認のみ(GUI 起動・目視確認は禁止 — ルート CLAUDE.md 参照)
./build_app.sh       # MySlideshow.app を生成
./install.sh         # ビルド → /Applications/MyApplications へインストール
```

`MySlideshow.app` `.build/` `AppIcon.icns` `AppIcon.iconset/` は .gitignore 済み・
スクリプトから再生成される成果物。コミットしない。

- **バージョンは `Sources/MySlideshow/Main.swift` の `appVersion` が唯一の定義**
  (mytube/myorganizer と同じ方式)。`build_app.sh` が Info.plist に反映する。
- **`Package.swift` の `linkerSettings: [.linkedFramework("AVKit")]` を外さないこと。**
  mytubeで実機確認済みの理由(AVKitが明示リンクされていないとXcodeデバッガ無しの起動で
  demangleクラッシュする、FB8928032)がそのまま当てはまる ― `AVPlayerView`を直接使う
  `Views/NativeVideoPlayerView.swift`側の話であり、SwiftUIの`VideoPlayer`は使っていない。
- **通常の SwiftUI `App`/`WindowGroup` 構成**。動画再生を裏で継続する必要がないため、
  ウィンドウを閉じればアプリごと終了してよい(mytube/myorganizerと同じ)。
- **ウィンドウは420×560固定・リサイズ不可**(2026-08-30、「起動時のウィンドウを
  できるだけ小さくできる?」→「自由に大きくできなくていい」という2段階の要望への
  対応)。まず`Main.swift`の`.defaultSize(width: 420, height: 560)`を`ContentView`の
  `.frame(minWidth: 420, minHeight: 560)`(ホーム画面の内容がクリップされずに収まる
  最小サイズ)にぴったり一致させ(以前は`defaultSize(width: 640, height: 520)`で、
  幅はホーム画面の中身が`.frame(maxWidth: 460)`で頭打ちになるぶん無駄に横長、
  高さは`minHeight: 560`未満のため結局起動直後に560へ引き上げられていた)、続けて
  「自由に大きくできなくていい」という要望を受けて`ContentView`側を
  `.frame(minWidth:minHeight:)`(下限だけで上限は無制限、自由にドラッグで拡大できる)
  から`.frame(width: 420, height: 560)`(固定・上限=下限)に変えた。SwiftUIは
  ルートビューが単一の固定サイズしか受け付けない(サイズの幅・範囲を持たない)場合、
  それだけでウィンドウのリサイズハンドルを自動的に無効化するため、`windowResizability`
  修飾子は使っていない。**一度`.windowResizability(.contentSize)`を`WindowGroup`に
  追加して試したが、「スライドショーが全画面で始まってない」という報告で発覚した
  とおり、これを付けるとネイティブフルスクリーン(下記`enterFullScreenIfNeeded`の
  `toggleFullScreen`)が動かなくなったため撤去した**(推測: `.contentSize`指定は
  `NSWindow`の`.resizable`スタイルマスクごと外してしまい、macOSの標準フルスクリーンは
  リサイズ可能なウィンドウを前提にしているため)。`.frame(width:height:)`による固定
  だけならスタイルマスク上は`.resizable`を保持したままリサイズ範囲だけを1点に
  絞るらしく、フルスクリーンは正常に動く。**今後ウィンドウサイズ関連を触るときは
  `windowResizability`を安易に追加しない**(フルスクリーンを壊す既知の組み合わせ)。
  スライドショー画面(`SlideshowView`)自体はこのウィンドウサイズ固定とは無関係に
  全画面表示できる(フルスクリーンはOS側がウィンドウサイズ制約を無視して画面全体へ
  広げる)。ホーム画面の内容(リンクごとの年別チェックボックス等)を増やす場合は、
  `ContentView`の固定サイズと`defaultSize`の両方を合わせて見直すこと(ずれると
  再びクリップや無駄な余白が生まれる)。
- **非サンドボックス**。OneDrive共有リンク専用でローカルファイルへのアクセスは無い
  (ダウンロードもしない ― 下記参照)ため、entitlements・security-scoped bookmarkは不要。
- **ローカルフォルダのスキャンは無い**。mytubeと違い`VideoScanner`に相当するものを持たない ―
  このアプリはOneDrive共有リンクだけを対象にした、意図的にスコープを絞ったアプリ。

## アーキテクチャ

- **`Models.swift`** — `MediaItem`(写真/動画どちらも表す。`kind: MediaKind`で分岐)+
  `HardcodedLink`(名前+URL+`kindFilter: MediaKind?`+`availableFolders: [String]`)。
  mytubeの`VideoItem`と違い`remoteID`は必須(常にOneDriveのアイテムID) ― ローカル
  スキャンが無く、リモート専用のため。**`HardcodedLink.availableFolders`(年別チェック
  ボックスの選択肢)もハードコード**(2026-08-29、「写真は2020から2026までチェック
  ボックスを決め打ちにして。動画は2020から2021に。リンクからはとらない」という要望への
  対応 ― 直前まではOneDriveを起動時にスキャンして実際に存在するフォルダ名を動的に
  検出していたが、選択肢を得るためだけに実データの取得(重い全階層スキャン)まで
  発生してしまうミスマッチがあったため、選択肢自体を静的な配列にした。詳細は下記
  `ContentView.swift`の項)。**`HardcodedLink`は旧`SharedLinkBookmark`(2026-08-29に
  撤去)の後継** ― 追加・削除UIを持たないぶん、`Codable`/`Identifiable`(UUID)である
  必要が無く、URL文字列自体を`id`に
  使う単純な構造体になっている(下記`ContentView.swift`の項参照)。
- **`Core/OneDriveMediaClient.swift`** — mytubeの`Core/OneDriveShareClient.swift`から
  認証フロー(匿名Badgerトークン→共有解決[+redeem]→children一覧の再帰取得、3ステップ)を
  そのまま移植したもの。**内部API(`api-badgerp.svc.ms`/`my.microsoftpersonalcontent.com`)
  を使っている点、署名付きダウンロードURL(`@content.downloadUrl`)が1時間程度で失効する点は
  mytube側のコメントを参照** ― 詳しい経緯・注意点をここには重複して書かない。違いは
  `videoExtensions`に加えて`photoExtensions`(jpg/jpeg/png/heic/heif/gif/bmp/tiff/tif/webp)も
  対象にし、`VideoItem`ではなく`MediaItem`(kind: .photo/.video)を返す点だけ。
  ファイルサイズ(`size`)フィールドは取得していない(UI上どこにも表示箇所が無いため、
  mytubeが一度削除して`knownFileSize`用に復活させた経緯とは違いこちらは最初から持たない)。
  **深さ制限(`maxDepth`)を一時的に試したが撤回し、mytubeと同じ「深さ制限なしの全階層走査
  + 一時的ネットワークエラーの自動リトライ」に統一した**(2026-08-29、この日のうちに
  以下の経緯をたどった):
  1. 「動画、写真、配下の一つ下のサブディレクトリのみでいいので、読み込みを早くしてほしい」
     という要望を受け、`scan(shareURL:maxDepth:)`に`maxDepth`引数を追加し、
     `ContentView.scan(_:)`から`maxDepth: 1`で呼ぶようにした(`walk`内で
     `pathComponents.count < maxDepth`を満たす間だけ子フォルダへ再帰し、それより深い
     フォルダは中に入らず丸ごとスキップする)。
  2. ところがこのユーザーの実際のOneDriveライブラリ(動画リンク)は年/月/日と3階層以上
     ネストしており、`Core/Log.swift`のログ(下記)で調査したところ、年フォルダ
     直下にはさらに月フォルダしか無く(`media=0`)、実際のファイルは
     「年/月/日」の3階層目にあることが判明した(例:
     `walk[2022/12/1203]: children=6 folders=0 media=6`)。`maxDepth: 1`だと年フォルダの
     「存在」は分かってもその配下のファイルにまるで到達できず、「動画も写真も年フォルダが
     出てこない/再ロードしてもでてこない」という新たな不具合を生んだ。
  3. 「リンクからディレクトリの取得の仕方はMyTubeを参考にしてみて」という指摘を受け、
     `maxDepth`引数を撤去して`walk`を無条件に全階層再帰する形に戻し(mytubeの
     `OneDriveShareClient.walk`と同じ)、代わりに`scanWithRetry(shareURL:)`
     (`ContentView`はこちらを呼ぶ、`scan(shareURL:)`を直接呼ばない)を新設した。
     mytubeの`ContentView.scanOneDriveWithRetry(shareURL:)`をそのまま移植したもので、
     `URLError.networkConnectionLost`/`.timedOut`だけ自動で1回リトライする ―
     mytube側で「フォルダ数が多いライブラリほど、逐次HTTPリクエストのどこかで一時的な
     接続断を踏む確率が上がり、`walk`が例外を投げるとそこまでの結果ごと丸ごと捨てられて
     スキャン全体が失敗する(＝サブフォルダが1つも出てこないように見える)」という
     既知の不具合として2026-08-28に対応済みだったのと、症状(「サブフォルダが出てこない」)
     が完全に一致したため。
  結果として、深さ制限による高速化は行わない(年/月/日のように深いライブラリでは
  読み込みに時間がかかりうる、`README.md`の制限事項に明記)。
  4. その後「年別チェックボックスをハードコードにし、実データの取得は「スライドショー
     開始」を押した瞬間まで遅延させる」設計(下記`ContentView.swift`の項)に変わったが、
     「スライドショーがなかなか始まらない」という報告で調査したところ、`start()`が
     `scanWithRetry(shareURL:)`(リンク全体を無条件に全階層走査)を呼んでから
     `items.filter`で選んだ年だけに事後的に絞り込んでいたため、選んでいない年の
     ツリー(さらに写真リンクの場合は`availableFolders`に無い「璃央のカメラ」等の
     フォルダも)に無駄にアクセスしていたことが判明した。`scan(shareURL:
     onlyTopLevelFolders:)`/`scanWithRetry(shareURL:onlyTopLevelFolders:)`
     (2026-08-29追加)を新設し、ルート直下だけ1ページずつ列挙して名前が
     `topLevelFolders`に一致するフォルダだけ`walk`で深く辿るようにした(一致しない
     フォルダは中に入らず丸ごとスキップ)。`ContentView.start()`はこちらを
     `onlyTopLevelFolders: folders`(選んだ年の集合)で呼ぶため、選んでいない年には
     一切アクセスしなくなった ― 選ぶ年を絞るほど実際に速くなる。ルート直下に直接
     置かれたファイル(フォルダ構造を持たないリンク向け)は`rootFolderLabel`
     (`"(ルート)"`、この定数はOneDriveMediaClient側に一本化し、ContentViewは
     独自に持たない)が`topLevelFolders`に含まれているときだけ対象にする ―
     `availableFolders`は年しか列挙しないため、実質的には今のところ常に対象外になる。
  5. それでも「まだ、遅いです」という報告を受けた(2026-08-30)。選んだ年フォルダの
     絞り込みは効いていたが、その年フォルダ自身が年/月/日と深くネストしている場合
     (上記2.の通りこのユーザーの実際のライブラリがまさにそう)、`walk`が
     兄弟フォルダ(同じ年の中の月フォルダ、同じ月の中の日フォルダ)を1つずつ
     **逐次**HTTPリクエストしていたため、フォルダ数が多いとその回数分だけ待ち時間が
     積み上がっていた。`walk`を`inout [MediaItem]`へ直接追記する完全に逐次的な実装
     (`inout`は並行タスク間で安全に共有できないため並列化と相性が悪い)から、
     戻り値`[MediaItem]`を返す形に書き換え、フォルダ1つぶんの`children`ページを
     すべて読み終えたあとにサブフォルダを`withThrowingTaskGroup`で並列に`walk`する
     形にした。ただし際限なく並列化するとOneDrive側のレート制限に引っかかる懸念が
     あるため、`ConcurrencyLimiter`(`actor`ベースの簡易セマフォ、`CheckedContinuation`
     で待機列を持つ)で同時HTTPリクエスト数を最大8に絞っている
     (`concurrencyLimiter.acquire()`/`.release()`をHTTPリクエストの前後で呼ぶ)。
     `scan(shareURL:)`(絞り込み無し版)・`scan(shareURL:onlyTopLevelFolders:)`
     (絞り込み版)のどちらも内部で新しい`walk(driveId:itemId:pathComponents:token:)`
     を呼ぶだけで、呼び出し側(`ContentView.start()`)からは並列化していることは
     見えない(透過的)。ログ行(`walk[...]: children=... folders=... media=...
     skipped=... hasNextLink=...`)はページ単位のまま変えていない(サブフォルダの
     再帰は別タスクで行われるため、1行が表す範囲は「そのフォルダ自身の直下」で
     以前と同じ)。
  **スキャンの詳細は`Log.scan`(`Core/Log.swift`)へ記録する**(2026-08-29追加 ― GUIを
  起動して目視確認できない制約があるため、`log show --predicate 'subsystem ==
  "com.yoheisakata.myslideshow"'`で後から直接読める形にした。上記の原因調査で実際に
  役立った。mytubeの`Core/Log.swift`と同じ発想だが、こちらは最小限の`Logger`インスタンス
  1つ(`category: "scan"`)だけ)。`resolveShare`(共有先がフォルダかどうか・
  driveId/itemId)と`walk`(フォルダごとの`children`件数・フォルダ数・メディア数・
  スキップ数・次ページの有無)の両方にログを仕込んである。
- **`Core/PlayerEngine.swift`** — mytubeの同名ファイルを大幅に簡略化したもの。再生速度制御
  (`playbackRate`)・複数経路のエラー検知(④の15秒タイムアウト等)は持たず、
  `onFinished`/`onError`の2つのコールバックだけ。**動画の再生失敗は`SlideshowView`側で
  ポップアップにせず自動的に次へスキップする**(下記参照) ― mytubeと違い、この画面は
  子どもが操作する前提で「エラーダイアログを出して止まる」より「何も言わず流し続ける」方を
  優先した設計判断。**一時期`playSegment(startSeconds:durationSeconds:)`(動画を区間だけ
  シーク再生する、ハイライト再生機能用)を持っていたが、2026-08-29に「ハイライト機能は
  削除」の要望でハイライト再生機能ごと撤去し、`load`/`stop`/`togglePlayPause`+
  `onFinished`/`onError`だけの元の単純な形に戻した。** 区間再生のフレーム精度シーク
  (`toleranceBefore/After: .zero`)や`CheckedContinuation`の後始末など、当時の実装で
  踏んだ落とし穴は今後同種の機能(動画の一部だけ再生する等)を足す際に再度踏みうるため、
  この段落だけ簡単に書き残しておく: トレランス省略版の`seek(to:)`は近い方のキーフレームへ
  スナップする寛容なシークで対象時刻より前に着地することがあり、区間の切れ目で前の区間の
  末尾と重なって「同じ場面が繰り返される」ように見える不具合があった(`toleranceBefore/
  After: .zero`のフレーム精度シークで解消)。また`Task.cancel()`はSwiftの
  `CheckedContinuation`を自動的には再開しないため、`await withCheckedContinuation`を
  使うコードは`stop()`/`load(url:)`の冒頭とdeinitの両方で明示的にcontinuationを
  再開する後始末が必須だった。
- **`Core/FilenameDateParser.swift`**(2026-08-29追加、「ファイル名からいつからわかるはずなので、
  右下に表示して」という要望への対応) — `IMG_20230515_120033.jpg`のようなカメラ・スマホの
  標準的な命名規則から、正規表現(`YYYYMMDD`、区切り文字`-_.`有り無しどちらも許容)で
  撮影日らしき日付を拾う純粋関数。**OneDriveの`lastModifiedDateTime`
  (`MediaItem.modifiedDate`)へはフォールバックしない** ― それはアップロード/同期日時であって
  撮影日ではないことが多く、分からないときに紛らわしい日付を出すよりは何も出さない方が
  誤解を招かないと判断した。`MediaItem.capturedDate`(計算プロパティ)がこの関数を呼ぶ。
- **`Core/ImageLoader.swift`** — 写真を`downloadURL`から取得し、直近8枚だけメモリ
  (`NSImage`、単純な配列ベースのLRU)にキャッシュするシングルトン。**ディスクキャッシュは
  持たない** ― mytubeの`ThumbnailStore`と違い、このアプリは「1セッションで流し切る」用途で
  再訪の価値が薄いことと、署名付きURLがどのみち1時間程度で失効するため永続化してもすぐ
  無効になることから、あえてディスクへの保存を省いた(スコープを絞るシンプルさ優先)。
  `prefetch(_:)`は次に来る写真を先読みするだけで、動画は先読みしない(ストリーミング再生
  なので不要)。
- **`Core/PIPWindowController.swift`**(2026-08-30追加) — `PlaybackMode.pip`専用の、
  `NSPanel`ベースの小さな常時最前面浮動パネル。「スライドショーには3つのモードが
  ほしい: ウィンドウ内/全画面/PIP」という要望を受け、「PIP」の実体をAskUserQuestionで
  確認した結果「自前の小さい常時最前面ウィンドウ」を選んだ(macOSネイティブの
  Picture-in-Picture、AVKitの`AVPictureInPictureController`は動画専用でシステム管理の
  浮動パネルになるため、写真も扱うこのアプリの要件には合わない ― 選択肢として提示し
  却下された)。`.windowed`/`.fullScreen`のようにメインウィンドウの中身を差し替えるのでは
  なく、`ContentView.start()`が`PIPWindowController.show(items:timeLimitMinutes:onExit:)`を
  呼んで**別ウィンドウ**として`SlideshowView`をホストする ― メインウィンドウはホーム画面を
  表示したまま裏に残る(ホーム画面を隠さず、他の作業をしながら隅で流せるようにするため)。
  パネルの`styleMask`は`[.titled, .closable, .resizable, .fullSizeContentView]`+
  `titleVisibility = .hidden`+`titlebarAppearsTransparent = true`でタイトルバーの
  文字だけ隠しつつ閉じるボタン(トラフィックライト)は残す、という見た目上クロームレス・
  機能はほぼ通常ウィンドウという組み合わせ(`.borderless`にしなかったのは、`NSPanel`の
  `.borderless`はデフォルトでキーウィンドウになれず、`SlideshowView`のキーボード
  ショートカット[スペース/矢印/esc]用の`NSEvent.addLocalMonitorForEvents`がkeyDownを
  受け取れなくなる懸念があったため)。`level = .floating`+`collectionBehavior:
  [.canJoinAllSpaces, .fullScreenAuxiliary]`+`hidesOnDeactivate = false`が「常時最前面・
  他アプリの上にも・Spaces切り替えやフルスクリーンアプリの上にも追随」という
  「常時最前面ウィンドウ」の要件を満たす部分。`isMovableByWindowBackground = true`で
  背景ドラッグによる移動に対応(「ドラッグで移動可能」)。パネルを閉じる経路は3つ
  (自前の✕ボタン/escキー→`SlideshowView.onExit`、ネイティブの閉じるボタン→
  `NSWindowDelegate.windowWillClose`)あるが、`SlideshowView`自体の後始末
  (`engine.stop()`・タスクのキャンセル等)はどの経路でも`onDisappear`(ビューが
  破棄されるときに自動的に呼ばれる)に任せているため、`PIPWindowController`側は
  `panel`参照を手放すだけでよい。
- **`Views/NativeVideoPlayerView.swift`** — `AVPlayerView`を直接ラップ。mytubeと違い
  `controlsStyle = .none`(標準コントロールバーを一切出さない) ― 一時停止/前後送りは
  `SlideshowView`自前のオーバーレイ+キーボード操作(スペース/矢印キー)で行うため、
  AVKit標準のコントロールと二重に持たせない。
- **`Views/SlideshowView.swift`** — このアプリの中心。写真は`Settings.photoDurationSeconds`
  (既定6秒、ホーム画面のスライダーで3〜15秒に変更可)だけ`Task.sleep`で待ってから次へ進み、
  動画は`PlayerEngine.onFinished`を受けて次へ進む。**「自動連続再生・操作不要」という要件を
  満たすため、`onAppear`で自動的にウィンドウをフルスクリーン化する**(`NSApplication.shared.
  keyWindow?.toggleFullScreen(nil)`、`window.styleMask.contains(.fullScreen)`で二重トグルを
  防止)。終了(`onExit`、✕ボタン/escキー)時は逆に`exitFullScreenIfNeeded()`でフルスクリーンを
  解除してからホーム画面へ戻る。
  - **コントロールオーバーレイは既定で隠れており、マウスを動かすと3秒だけ現れる**
    (`.onContinuousHover`+`Task.sleep`で3秒後に自動的に`showsControls = false`)。子どもが
    誤って操作できないよう、常時は前後送り/一時停止/終了ボタンを一切出さない設計。
  - **キーボード操作は`NSEvent.addLocalMonitorForEvents(matching: .keyDown)`のローカル
    モニター**(mytubeの`PlayerPaneView.installSpacebarMonitor()`と同じ手法)で
    スペース(一時停止/再開)・←→(前後の写真・動画へ)・esc(終了)を横断的に拾う。
    `onAppear`/`onDisappear`でモニターの設置/解除を行う ― `SlideshowView`自体が破棄される
    (ホーム画面へ戻る)ときに確実に解除しないとリークする(mytubeの同パターンと同じ注意)。
  - **動画の再生失敗(`engine.onError`)は自動的に次へスキップする**(上記
    `Core/PlayerEngine.swift`の項参照)。コーデック非対応・OneDriveの署名付きURL期限切れ等で
    起きうるが、子どもが操作する前提の画面のためエラーダイアログは出さない。
  - **写真は`ImageLoader.shared.prefetch(upcoming())`で次の3件を先読みする** ―
    表示が切り替わった瞬間に真っ黒/ローディングスピナーが挟まる頻度を減らすため。
  - **右下の日付ラベル**(`dateLabel(for:)`、2026-08-29追加) — `current.capturedDate`が
    取れているときだけ、画面右下に常時(`showsControls`と連動しない ― 操作オーバーレイは
    3秒で消えるが、こちらはマウスを動かさなくても出続ける)表示する。`.allowsHitTesting(false)`
    でマウスイベントを素通しする(`.onContinuousHover`によるオーバーレイ表示のトリガーを
    妨げないため)。
  - **表示モード**(`playbackMode: PlaybackMode`、2026-08-30追加、「スライドショーには
    3つのモードがほしい: ウィンドウ内/全画面/PIP」という要望への対応) —
    `applyWindowModeIfNeeded()`(`onAppear`で1回)/`restoreWindowModeIfNeeded()`
    (`exit()`で1回)がメインウィンドウを直接操作する形で分岐する(旧
    `enterFullScreenIfNeeded`/`exitFullScreenIfNeeded`を汎用化したもの):
    - `.fullScreen`(既定、従来の唯一の挙動) — `window.toggleFullScreen(nil)`。
    - `.windowed` — `window.styleMask.insert(.resizable)`してから
      `window.setContentSize(NSSize(width: 960, height: 640))`で一度だけ大きめサイズへ
      広げる。ホーム画面へ戻るときの縮小・リサイズ不可化は明示的なAppKit操作をせず、
      `ContentView`側のホーム画面ブランチが持つ`.frame(width: 420, height: 560)`
      (固定)がSwiftUIの層で自動的に効くのに任せている(下記`ContentView.swift`の項の
      「ウィンドウサイズ」注記も参照)。
    - `.pip` — 何もしない(`guard playbackMode != .pip`で早期return)。メインウィンドウ
      ではなく`Core/PIPWindowController.swift`が用意した別パネルにホストされるため。
    **`.pip`のときに一度`window.toggleFullScreen`等でメインウィンドウを誤って操作
    しないよう、両関数とも`.pip`を最初にガードしている**(`NSApplication.shared.
    keyWindow`はPIPパネル表示中でもタイミング次第でメインウィンドウを指しうるため、
    ここを誤ると「PIP再生中にホーム画面が意図せずフルスクリーン化する」といった
    事故になりうる)。
  - **時間制限**(`timeLimitMinutes`、2026-08-29追加、「スライドショーの時間制限を
    作りたい。スライダーで5分毎のメモリで最大は無制限」という要望への対応、旧ハイライト
    再生機能の撤去と同じタイミング) — `scheduleTimeLimitIfNeeded()`が`onAppear`で1回
    呼ばれ、`timeLimitMinutes`が非nilなら`timeLimitMinutes * 60`秒後に`exit()`を呼ぶ
    単純な`Task.sleep`タイマー(`timeLimitTask`、`onDisappear`でキャンセル)。写真の
    表示秒数と違い一時停止との連動は無い(一時停止中でも制限時間のカウントは進む ―
    「スライドショー全体の上限時間」という意味なので、これで意図通り)。
    **`Settings.timeLimitMinutes: Int?`は5分刻みの整数、`nil`が無制限**
    (`Core/Settings.swift`)。`Views/HomeView.swift`のスライダーは
    `[5,10,...,60,nil]`という固定配列へのインデックスとして実装されている
    (`Slider`自体は連続値`Double`しか扱えないため、配列インデックスの整数値との
    往復変換をカスタム`Binding`で行っている) ― スライダーの右端(最後の要素)が
    「無制限」に対応する、という「最大は無制限」という要望をそのままUIの右端に
    マッピングした設計。
- **`ContentView.swift`** — ホーム画面(`Views/HomeView.swift`)とスライドショー画面
  (`Views/SlideshowView.swift`)の2つを`isShowingSlideshow`で切り替えるだけの薄い
  コンテナ。OneDriveアクセス・設定値の永続化(`onChange`で`Settings`へ書き戻す)をすべて
  ここに集約し、`HomeView`は「受け取ったデータを表示し、操作をコールバックで返すだけ」の
  純粋なビューに徹する。
  - **OneDriveリンクは`ContentView.links`にハードコードした固定配列**(2026-08-29、
    複数回のやり取りを経て現在の形に落ち着いた ― 当初はブックマーク配列を`UserDefaults`
    (`Settings.bookmarks`)へCRUDする仕組み+リンクの追加・削除だけを担う`SettingsView`
    画面(⚙️ボタンで開く)を作ったが、「リンクはめったにかわらないので、ハードコードの
    ままでいい。設定にも追加や削除できなくていいので、設定がいらない」という要望を受けて
    `SettingsView`/`Views/OpenLinkSheet.swift`/`Models.SharedLinkBookmark`/
    `Settings.bookmarks`ごと丸ごと削除し、`ContentView`に直書きの`[HardcodedLink]`に
    置き換えた)。現在2件: 動画専用「動画」・写真専用「写真」(`kindFilter`で絞る)。
    リンクを増減・変更する場合はこの配列を直接編集する(ビルド・インストールし直せば
    反映される、UIからの操作は無い)。**動画リンクの`availableFolders`は当初2020〜2021年
    だけだったが、2026-08-30に「動画の年を増やしました。2025までチェックボックスを
    増やして」の要望で2020〜2025年へ拡張した**(OneDrive側に年フォルダが増えたことに
    追随しただけで、UI・ロジックの変更は無い)。
  - **年別チェックボックスの選択肢もハードコード(`HardcodedLink.availableFolders`)で、
    OneDriveへのアクセスは一切しない**。**実際にOneDriveへ写真・動画を取得しに行くのは
    「スライドショー開始」を押した瞬間だけ**(`start()`)(2026-08-29、「写真は2020から
    2026までチェックボックスを決め打ちにして。動画は2020から2021に。リンクからはとらない。
    スライドショー開始ではじめて、リンクへ動画、写真を取得しに行く」という要望への対応)。
    この設計に至るまで2段階の変遷があった:
    1. 当初は「スライドショー開始」を押してから初めてスキャンし、成功したら別画面
       (`Views/FolderPickerView.swift`、削除済み)でフォルダを選ばせる2段階の設計。
    2. 「起動時にすでに、動画も写真も年のサブフォルダを表示してほしい」という要望で、
       起動時に両リンクを丸ごとスキャンして`linkScans: [String: LinkScanState]`
       (`Models.swift`、削除済み)にキャッシュし、`HomeView`にフォルダのチェックリストを
       最初から埋め込む1画面構成にした。
    3. ところがこのユーザーのOneDriveライブラリは年/月/日と深くネストしており、起動時の
       全階層スキャン自体が数分かかることがあり、しかも「年の一覧が知りたいだけなのに
       実データまで全部取りに行ってしまう」というミスマッチがあった。最終的に
       「年の範囲はハードコードでよい、実データの取得は開始ボタンを押した瞬間まで
       遅延させたい」という要望を受けて現在の形(この項)に落ち着いた。
    `selectedFolders: [String: Set<String>]`(キーは`HardcodedLink.id`)は選択状態
    **だけ**を持つ軽量な状態で、`ensureSelectionDefaults()`が`.onAppear`で
    `Settings.folderSelections[link.id]`(前回選んだフォルダ名の集合と`availableFolders`
    との積集合、無ければ`availableFolders`全部)から即座に(OneDriveへ触れずに)組み立てる。
    `toggleFolder(_ link: HardcodedLink, _ folder: String)`がどのリンクのトグルかを
    引数で受け取り、そのリンクの選択だけを更新して`Settings.folderSelections[link.id]`へ
    保存する。
  - **ウィンドウサイズはホーム画面/スライドショー画面(`.windowed`)で別々の`.frame`を
    持つ**(2026-08-30、表示モード追加時に`ZStack`共通の1つの`.frame`から分割した) ―
    ホーム画面ブランチは`.frame(width: 420, height: 560)`(固定・リサイズ不可、
    「自由に大きくできなくていい」という要望への対応、上記`Main.swift`の項参照)、
    スライドショー画面ブランチは`.frame(minWidth: 420, minHeight: 320)`(下限のみ・
    リサイズ可能)。SwiftUIはウィンドウのリサイズ可否・サイズ範囲を、現在描画されている
    ルートビューの`.frame`制約から自動的に再計算する(前者の固定サイズだけで
    `windowResizability`修飾子なしにリサイズハンドルが自動的に消えることは
    `Main.swift`の項で確認済みの挙動)ため、ブランチが切り替わるたびに
    ウィンドウ側もそれに追随する。`.windowed`モードで実際に大きいサイズへ広げる
    一度きりの操作は`SlideshowView.applyWindowModeIfNeeded()`(上記参照)が行う ―
    ここの`minWidth: 420, minHeight: 320`はあくまで下限の宣言で、実際の初期サイズは
    `SlideshowView`側のAppKit操作(`.windowed`なら960×640、`.fullScreen`なら
    そのままフルスクリーン化するので一瞬の中間サイズは見えない)に任せている。
  - **`start()`が実際のOneDriveアクセスを一括で行う** ― `Self.links`を順に
    `OneDriveMediaClient.scanWithRetry(shareURL:onlyTopLevelFolders:)`
    (`selectedFolders[link.id]`を渡す ― 選んだ年フォルダだけを辿り、選んでいない
    年やその他のフォルダには一切アクセスしない、上記`Core/OneDriveMediaClient.swift`
    の項参照)でスキャンし、`kindFilter`で絞り、「フォルダパス→ファイル名
    (localizedStandardCompare)」のアルファベット順にソートしてから合算する。
    **フォルダによる絞り込みは`OneDriveMediaClient`側(スキャン時点)で完結しており、
    `ContentView`側で改めて`items.filter`し直す必要は無い**(以前は逆で、リンク全体を
    スキャンしてから事後的に絞り込んでいたため「選んだ年が少なくても遅い」不具合が
    あった)。**1つのリンクが失敗しても他方の結果があれば続行する**
    (`failureMessages`に集めておき、最終的に`final`が空だったときだけ
    `errorMessage`として表示する ― 部分的な失敗で全体を止めない設計)。シャッフルは
    全リンク合算後、実際にスライドショーへ渡す直前に`Settings.shuffleEnabled`が
    `true`なら適用する。`isLoading`が`true`の間`HomeView`はチェックボックス・
    「スライドショー開始」ボタンを無効化する。**取得後の分岐は`playbackMode`
    (2026-08-30追加)次第**: `.windowed`/`.fullScreen`は従来通り`isShowingSlideshow
    = true`でメインウィンドウの中身を`SlideshowView`へ差し替える。`.pip`は
    `isShowingSlideshow`をいじらず(メインウィンドウはホーム画面のまま)、
    `pipController.show(items:timeLimitMinutes:onExit:)`を呼んで別パネルを開く
    (`Core/PIPWindowController.swift`の項参照)。
- **`Views/HomeView.swift`** — `links`を`ForEach`し、それぞれ`linkSection(_:)`が
  `HardcodedLink.availableFolders`(ハードコード、常に即座に表示できる)のチェック
  リストを出す + 読み込み中/エラー表示(`start()`実行中だけ意味を持つ)+ スライドショー
  設定(表示モード/写真の表示秒数/シャッフル/時間制限、`GroupBox`でまとめる)+
  画面最下部中央の
  「スライドショー開始」ボタン(件数は事前に分からないため表示しない ― 実データは
  「開始」を押すまで取得しないため)、という1画面構成。各リンクのフォルダのチェック
  リストは`GroupBox(link.name)`(「動画」「写真」がそのまま見出しになる)+
  `Toggle(...).toggleStyle(.checkbox)`(複数選択なので、設定項目の`Toggle`(既定の
  スイッチ style)とは見た目を変えている)。🔄再スキャンボタンは撤去した ―
  「開始」のたびに毎回スキャンし直す設計になったため、専用の再スキャン操作自体が
  不要になった。
  - **表示モードは`Picker(...).pickerStyle(.segmented)`(3択: `PlaybackMode.allCases`)**
    (2026-08-30追加)。「スライドショー設定」`GroupBox`内の先頭に置く ―
    写真の表示秒数等より上、常に見える位置。
  - **チェックボックスは`LazyVGrid(columns: [GridItem(.adaptive(minimum: 76))])`で
    横に並べて折り返す**(2026-08-29、「チェックボックスをバランスよく並べて。横並びで
    OK」という要望への対応 ― 以前は`VStack`の1列縦並びで、「写真」の7個(2020〜2026)が
    「動画」の2個に対して縦に間延びして見えていた)。各グループの先頭に「全選択」/
    「全非選択」ボタン(同じ要望の「全選択、全非選択を追加して」の部分、
    `ContentView.setAllFolders(_:selected:)`を呼ぶだけ ― 対象リンクの
    `selectedFolders`をまるごと全部/空に置き換えて`Settings.folderSelections`へ
    保存する)も付けた。
  - **レイアウトは「全体的にボタンや設定をバランスよく配置してほしい」という要望を受けて
    統一した** ― 本体コンテンツを`.frame(maxWidth: 460).frame(maxWidth: .infinity)`という
    2段の`.frame`で「460pt幅の1カラムに揃えてから、それを画面幅いっぱいの中で水平中央
    寄せする」パターンで包む。スライドショー設定・各リンクのフォルダのチェックリストは
    どれも`GroupBox`で視覚的にひとまとめにしてある。

## 変更時の注意

- OneDriveのフォルダ一覧は非公開の内部API依存(mytube側のコメント参照)。予告なく仕様変更・
  遮断される可能性があり、その場合は`Core/OneDriveMediaClient.swift`をmytubeの
  `Core/OneDriveShareClient.swift`の対応する変更と合わせて直すこと(認証フロー自体は
  完全に同一のロジックを維持している ― 片方だけ直すと差分が生まれるので注意)。
- 対応拡張子を増やす場合は`OneDriveMediaClient.videoExtensions`/`.photoExtensions`の
  1箇所を直すだけでよい。
- ローカルフォルダのスキャン・お気に入り・ダウンロードキャッシュ・複数ソース同時オープンなど、
  mytubeにある機能の多くは意図的に持たせていない(「まずはネイティブ版から」「自動連続再生」
  というスコープに絞った結果) ― 追加する場合はユーザーに確認してから。
- **「まとめ動画を作る」機能は一度実装したが、2026-08-29に「一切削除」の要望で撤去済み**
  (myorganizerの「まとめ動画」ペインをOneDriveソース向けに移植したもの ―
  `Core/VideoMaker.swift`/`ToolLocator.swift`/`ProcessRunner.swift`/`SyncExec.swift`/
  `VideoDownloadCache.swift`、`ViewModels/VideoMakerViewModel.swift`、
  `Views/VideoMakerView.swift`、ホーム画面の「まとめ動画を作る」ボタンをすべて削除した)。
  経緯は「スライドショーとまとめ動画の仕組みを統合できないか」という提案の後、
  「スライドショー側をまとめ動画のように設定豊富にしたい」という方向へ話が変わり、
  結果としてまとめ動画機能自体は不要と判断された。実装(ffmpegでのクリップ抽出→
  ディゾルブ結合→タイトルカード→BGM合成のパイプライン)自体はmyorganizer側に残っている
  ため、再度必要になれば同じ移植方針(ローカルフォルダ由来かOneDrive由来かをffmpeg
  パイプライン層は区別しない)で作り直せる ― ただし再度追加する場合はユーザーに確認すること。
- **リンクの追加・削除UI(`SettingsView`/`OpenLinkSheet`/`SharedLinkBookmark`/
  `Settings.bookmarks`)も同じく一度実装したが、2026-08-29に「リンクはめったにかわらないので、
  ハードコードのままでいい。設定にも追加や削除できなくていいので、設定がいらない」という
  要望で撤去済み** ― OneDriveリンクは`ContentView.links`への直書きに戻した(上記
  `ContentView.swift`の項参照)。再度ユーザー自身がリンクを追加・削除できるUIが必要になった
  場合は、この経緯をふまえて(一度作って使われなかった機能だと分かるように)ユーザーに
  確認してから追加すること。
