# CLAUDE.md — mymusic

曲の共有リンク(YouTube / Suno / MusicCreator.ai / MusicGPT / 直リンク mp3 等)や OneDrive の
共有フォルダをプレイリストとして貼り付け、まとめて再生する SwiftUI + SPM 製のミニプレーヤー。
ダウンロードして保存する用途ではなく **再生に特化**している(YouTube だけは音声抽出のため内部的にローカルへ mp3 キャッシュするが、
ユーザーに見せる保存先 UI は持たない)。**Dock アイコンを持つ通常のアプリ**で、ウィンドウを閉じても再生は止まらない。
使い方は `README.md` を参照。

2026-08-12 に `musicplayer`/MusicPlayer から **MyMusic** へ改名した(ディレクトリ・ターゲット名・
バンドル ID `com.yohei.mymusic`・データディレクトリ `~/Library/Application Support/MyMusic/` を
すべて変更)。改名時に既存の `MusicPlayer` データディレクトリはリネームし、`playlist.json` 内の
YouTube キャッシュを指す `file://` URL(パーセントエンコードされているので `Application%20Support`
のように空白が `%20` になっている点に注意)も新パスへ書き換え済み。コード側に旧パスからの
移行処理は持たせていないので、他マシンに古いデータがある場合は同じ手当てが必要。

## ビルド / デプロイ

```bash
swift build         # コンパイル確認のみ(GUI 起動・目視確認は禁止 — ルート CLAUDE.md 参照)
./build_app.sh       # dist/MyMusic.app を生成
./install.sh         # ビルド → /Applications/MyApplications へ上書きインストール
```

`dist/` `.build/` `AppIcon.icns` `AppIcon.iconset/` は .gitignore 済み・スクリプトから再生成される成果物。コミットしない。

## アーキテクチャ

- **通常の Dock アプリ**(`Main.swift` + `AppDelegate.swift`): SwiftUI の `App`/`WindowGroup` は
  使わず `Main.swift` の `@main enum` から `NSApplication.shared.run()` を直接呼ぶ構成
  (downloader と同じ)。`AppDelegate` が `PlaylistStore`/`PlayerEngine` を(ウィンドウの
  生死とは無関係に)唯一のインスタンスとして保持し、`ContentView()` に `.environmentObject`
  で注入する。
  **2026-08-12 にメニューバー常駐をやめた**(「mytube のようにメニューバーに置かなくていい」
  という要望への対応): `NSApp.setActivationPolicy(.accessory)` → `.regular`、
  `build_app.sh` が書く Info.plist の `LSUIElement` を削除、♪ のステータスアイテム
  (`setupStatusItem()`)も丸ごと削除した。**ただし mytube と違い
  `applicationShouldTerminateAfterLastWindowClosed` は `false` のまま** ― 音楽プレーヤーは
  ウィンドウを閉じても再生が続くべきで、mytube(動画を裏で流し続ける必要がない)とは
  前提が違う。ウィンドウを閉じた後の復帰口はステータスアイテムのメニューではなく
  `applicationShouldHandleReopen`(Dock アイコンのクリック)とアプリメニューの
  「ウィンドウを開く」の2つ。
  `NSApplication.shared.run()` を直接呼ぶ構成では `mainMenu` が自動生成されないため、
  `setupMainMenu()` でアプリメニュー(ウィンドウを開く/終了)と Edit メニュー
  (Cut/Copy/Paste/Select All)だけ最低限組み立てている(無いとテキストフィールドで
  Cmd+V が効かない)。
  **`NSMenuItem` は `target` を明示的に `self` に設定すること** — `addItem(withTitle:action:
  keyEquivalent:)` は既定で `target == nil` になり、レスポンダーチェーン(キーウィンドウの
  first responder → キーウィンドウ → `NSApp` → `NSApp.delegate`)を辿って解決される。
  キーウィンドウが無い/フォーカスが特殊な状態だとこの解決に失敗し、「メニューの『終了』を
  選んでも何も起きない」という再現しづらい不具合になりうる(メニューバー常駐時代の
  ユーザー報告)。Edit メニュー(Cut/Copy/Paste/Select All)は逆に **`target` を設定しては
  いけない** — フォーカス中のテキストフィールドの first responder に届く必要があるため、
  nil のままにする。
  `ContentView` 側は `@StateObject` ではなく `@EnvironmentObject` で `store`/`player` を受け取る
  ことが必須 — `@StateObject` にすると、ウィンドウを閉じて再度開いたときに
  `NSHostingController` ごと再生成され再生状態が失われる(実際にはウィンドウを閉じても
  `NSWindow`/`NSHostingController` インスタンス自体は `AppDelegate.window` に保持され続けて
  再利用されるので今のところ問題は起きないが、`AppDelegate` 側が唯一の所有者という前提を崩さないこと)。
- **`LinkResolver`**(`LinkResolver.swift`): 曲リンクを再生可能な `Track` に解決する唯一の入口。
  ホスト名で分岐し、
  - YouTube → `yt-dlp -x --audio-format mp3 --print "after_move:%(id)s\t%(title)s\t%(thumbnail)s"`
    を `Process` で実行し、キャッシュ(`~/Library/Application Support/MyMusic/cache/%(id)s.mp3`)
    にダウンロードしつつ、stdout のタブ区切り1行から `id`/`title`/`thumbnail` を取得する。
    同じ動画を再追加しても yt-dlp が既存ファイルを検出してスキップするため、独自のキャッシュ判定は
    持たない。ここは3つの不具合を踏んで今の形になっている(いずれもユーザー報告で発覚):
    1. **最終 mp3 のパスは yt-dlp の出力を信用せず、`id` から `cacheDir/<id>.mp3` を自分で
       組み立てている。** `--print-json`/`--print` が返す `filepath`/`_filename`/
       `requested_downloads` は `-x`(音声抽出)による post-process **前**の一時ファイル
       (`<id>.webm` 等)の情報のままで、変換後の最終 mp3 パスには一切追随しない(常に
       `filepath: null`)。実機の `yt-dlp` 実行結果を `python3 -c "import json; ..."` で
       直接パースして確認するまで気づかなかった。yt-dlp の出力キーを信じて実装するときは、
       **自分が渡した `-o` テンプレートとポストプロセッサの有無から最終ファイル名を自分で
       導出できないか常に検討すること** — 導出できるならその方が JSON のフィールド構成
       (yt-dlp のバージョンや post-process の有無で変わりうる)に依存せず堅牢。
    2. **`--print-json` から軽量な `--print` (id/title/thumbnail の3フィールドのみ)に変更し、
       パイプの読み取りも `terminationHandler` 内の `readDataToEndOfFile` から
       `readabilityHandler` によるストリーミング読み取りに変更した。** `--print-json` は
       YouTube 動画の全フォーマット一覧(ストーリーボード込みで数十〜100KB超)を1行で吐くため、
       「プロセス終了を待ってからまとめてパイプを読む」実装だと OS のパイプバッファ(macOS は
       既定 64KB 程度)を超えた時点で子プロセスが `write()` でブロックし、`waitUntilExit`/
       `terminationHandler` も永久に呼ばれない**相互デッドロック**に陥っていた(症状:
       読み込み中アイコンが回り続けたまま止まらない)。`music.youtube.com` の動画はフォーマット
       数が多くまさにこの閾値を超えていた。`PipeBuffer`(内部で `NSLock` を持つ薄いラッパー)で
       stdout/stderr 双方を実行中から継続的に吸い出す(downloader/YtDlpManager.swift と同じ
       方式)ことで根本的に回避している。**`Process` の標準出力/標準エラーを扱うときは、
       出力量が小さいと分かっていない限り `readDataToEndOfFile` をプロセス終了後にしか
       呼ばないコードを書かないこと** — 出力が伸びた瞬間にこの種のデッドロックを踏む。
    3. **`--print` には必ず `after_move:` ステージ接頭辞を付けること。** ステージ接頭辞なしの
       `--print TEMPLATE`(既定は `video` ステージ)は、この yt-dlp バージョン
       (`2026.07.04`)では `[info] Downloading N format(s): ...` の行だけ出して**実際の
       ダウンロード/音声抽出を一切行わずに終了コード 0 で終わってしまい**、mp3 ファイルが
       全く作られない不具合を実機で確認した(`--print-json` だとこの問題は起きない —
       違いは未調査。yt-dlp のバージョンアップで直る可能性はあるが、`after_move:` を
       付けておけば「最終ファイルへの move が完了した後」というこちらの意図が明示され、
       挙動に依存しなくなる)。`swift build` が通ることと `curl`/手元の Python でレスポンス
       構造を確認することは、実際に `yt-dlp` プロセスを最後まで走らせて成果物(mp3)が
       本当にディスクに出力されるかとは別の話 — **yt-dlp の引数を変えたら、必ず実際に
       ターミナルでそのままのコマンドを実行し、生成物のファイルが存在するところまで
       確認すること。** stdout の内容が「それっぽい」だけでは不十分。
  - Suno / MusicCreator.ai / MusicGPT / その他 → `URLSession` でページの HTML を取得し、
    正規表現で音声 URL を抜き出してそのままストリーミング再生する(ダウンロードしない)。
    3サイトとも **サーバレンダリングされた HTML の中に直接再生可能な mp3 URL が埋め込まれている**
    ことを事前に curl で確認済み(WKWebView や JS 実行は不要):
    - Suno: 埋め込み JSON の `"audio_url":"https://cdn1.suno.ai/....mp3"`
    - MusicCreator.ai: `<meta property="og:audio" content="....mp3">`(標準 OGP タグ)
    - MusicGPT: Next.js の RSC 埋め込み JSON の `"file_output_0":"https://cdn1.musicgpt.com/....mp3"`
    - その他の未対応サイトも `og:audio` があれば汎用フォールバックとして再生を試みる。
  - **ハマりどころ**: Suno と MusicGPT の音声 URL は `<meta>` タグではなく
    `self.__next_f.push([1,"...文字列..."])` という Next.js の RSC ペイロード(JS の文字列リテラル)
    の中に JSON として丸ごと入っている。そのため実際のバイト列では各 `"` の前に `\` が付く
    (例: `\"audio_url\":\"https://...\"`)。最初の実装ではこれを見落として単純な
    `"audio_url":"..."` パターンで書いてしまい、`swift build` は通るのに実サイトでは一切マッチしない
    という不具合を作り込んだ(ユーザー報告で発覚)。`extractSunoAudioURL`/`extractMusicGPTAudioURL`
    は `\\?"` (バックスラッシュ任意+必須クォート) でこの揺れを吸収している。**この手の抽出正規表現を
    書いたり直したりするときは、必ず `curl -sL -A "<Safari UA>" <url>` で生バイト列を取得し、
    実際の regex(NSRegularExpression 相当。Python の `re` で近似検証すれば十分)でマッチするか
    機械的に確認すること** — 目視でスニペットを読んだだけで「埋め込まれているから動くはず」と
    判断しない(og:title/og:image は同じページ内でも `<meta>` タグとして生の(エスケープなしの)
    HTML でも重複出力されているため紛らわしい)。og:title/og:audio 等の `<meta>` タグ由来の抽出は
    このエスケープ問題の影響を受けない。
  - いずれの経路で解決した mp3 URL も CORS/Range 対応済み(HEAD で `accept-ranges: bytes` 確認済み)
    で `AVPlayer` から直接再生できる。
  - **サイト側の実装変更に弱い**: 上記の正規表現(`extractSunoAudioURL` 等)が壊れたら、まず
    実サイトの生 HTML を `curl -sL -A "<Safari UA>" <url>` で取り直して構造を確認すること
    (`WebFetch` 相当のツールは HTML→Markdown 変換で `<meta>`/埋め込み JSON を消してしまうため
    調査には使えない)。
- **`OneDriveShareClient`**(`OneDriveShareClient.swift`、2026-08-12追加): OneDrive の
  「リンクを知っている全員が閲覧可能」共有フォルダ/ファイルを、サインインせずにスキャンして
  音声ファイル一覧を得る。mytube の `Core/OneDriveShareClient.swift` からの移植
  (あちらは動画、こちらは `audioExtensions` の音声だけを拾う) ― **2つのアプリで意図的に
  複製している**(`ToolLocator` と同じ方針。共有パッケージ化はしていないので、内部 API の
  仕様変更で直すときは両方に反映するか、乖離を許容すること)。仕組みは3ステップ:
  ①`api-badgerp.svc.ms/v1.0/token` に固定の appId(公開値、OneDrive Web クライアント自身の
  JS にハードコードされている)を渡して匿名トークン("Badger" スキーム)を発行 ②共有 URL を
  `u!<base64url>` 形式にエンコードして `my.microsoftpersonalcontent.com/_api/v2.0/shares/
  {encoded}/driveitem` へ `Prefer: autoredeem` 付きで POST し `driveId`/`itemId` を得る
  (この呼び出し自体が redeem の副作用を持つため、以降は同じトークンを使い回すこと ―
  別トークンだと accessDenied)③`/drives/{driveId}/items/{itemId}/children` を GET すると
  `@content.downloadUrl`(tempauth 署名付き、追加認証なしで直接ストリーミングできる)付きで
  中身が返る。いずれも公式の Graph API ではなく OneDrive Web クライアントの**内部 API**
  (`Origin`/`Referer` が `onedrive.live.com` であることをサーバー側で検証している)のため、
  予告なく遮断されうる。
  - **`@content.downloadUrl` は1時間程度で失効する** ― mytube と違い MyMusic は
    `playlist.json` に URL を永続化するので、保存した URL は次回起動時にはたいてい死んでいる。
    そのため `Track.oneDrive`(`OneDriveRef` = 共有 URL + driveId + itemId)を持たせ、
    **再生直前に `freshDownloadURL` で取り直す**(`PlaylistStore.refreshedTrack` →
    `ContentView.playTrack`)。取り直しに失敗したら1度だけトークン発行・redeem からやり直す。
  - **トークンと解決済みルートは `Session`(actor)に共有 URL ごと20分キャッシュする** ―
    そうしないと1曲再生するたびに3リクエスト投げることになる(キャッシュが生きていれば
    `fetchItem` の1回だけで済む)。
  - **サブフォルダは `withThrowingTaskGroup` で並行に辿る**(実測: 1300曲超の共有フォルダで
    逐次 86秒 → 並行 24秒)。同時 HTTP 本数は `Limiter`(actor 実装の async セマフォ、4本)で
    抑えるが、**スロットを取るのはページ取得(HTTP)だけで再帰呼び出し自体は取らない** ―
    親が子の完了を待つ間もスロットを握る作りにすると、階層が深いフォルダでスロットを
    使い切った瞬間に自己デッドロックする。完了順が不定になるので、最後に
    「フォルダパス/ファイル名」の `localizedStandardCompare` で並べ直してから返す
    (プレイリストに入る順序が実行のたびに変わらないようにするため)。
  - スキャン中の進捗は `onProgress`(見つかった曲数、スキャン用スレッドから呼ばれる)で
    通知し、`PlaylistStore` が MainActor に戻して `lastNotice` バナーに出す。
  - **ジャケットは `/thumbnails` エンドポイントから取る**(`thumbnailURL(shareURL:driveId:
    itemId:size:)`、2026-08-12追加。「OneDrive からの場合、Work Art は取得&表示できる?」
    という質問への回答)。曲ファイルに埋め込まれたアートワーク(mp3 の ID3 `APIC` / m4a の
    `covr`)を OneDrive 側(SharePoint のメディア変換サービス)が画像に起こして配信して
    くれるため、**こちらで音声本体を数百 KB 落としてタグを解析する必要はない**
    (`AVAsset.commonMetadata` を使う手もあるが、そちらは曲ごとに実ファイルの
    ダウンロードが要る)。実測: small=96 / medium=176 / large=800 px 四方、
    返る URL は `Authorization` 無しでそのまま取得できる、1件あたり 350〜500ms。
    **アートワークが埋め込まれていない曲でも `/thumbnails` は URL を返すが、その URL の
    取得が 404 になる**(実測。この共有フォルダでは m4a は概ねアートあり、mp3 は無しだった)
    ので、画像取得の失敗をもって「ジャケット無し」と判断する。
- **`Track`**(`Models.swift`): プレイリストの1曲。`audioURL` は再生に使う最終 URL で、
  YouTube はダウンロード済みローカルファイルの `file://` パス、それ以外は解決先サイトが返す
  リモート mp3 の直リンク文字列。`SiteKind` で UI 上のサイトバッジ表示を切り替える。
  OneDrive 由来の曲だけ `oneDrive: OneDriveRef?` が非 nil になる(既存の `playlist.json` に
  このキーは無いが Optional なのでそのままデコードできる)。`folderPath: [String]` は共有
  フォルダのルートから見た所在で、サイドバーのツリーはこの値だけから組む。**`Track` は
  `init(from:)` を自前で書いている** ― 合成される実装はプロパティに既定値があってもキーが
  無いとデコードに失敗するため。ここで `folderPath` を `decodeIfPresent` で読みつつ、
  フォルダ表示以前のデータ(「フォルダ名/曲名」をタイトルに詰めていた形式)を
  タイトルと階層に分解して移行している。プレイリスト内の同一曲判定には
  `audioURL` ではなく `dedupeKey` を使うこと ― OneDrive は URL が再取得のたびに変わるため、
  代わりに `onedrive:<driveId>/<itemId>` という安定したキーを返すようにしてある。
- **`PlaylistStore`**(`PlaylistStore.swift`): `tracks: [Track]` を保持し、
  `~/Library/Application Support/MyMusic/playlist.json` に JSON で永続化する。
  `addLink` は `LinkResolver.resolve` を `Task` 内で非同期に呼び、失敗時は `lastError` に
  日本語メッセージをセットする(呼び出し元でバナー表示)。成功時の案内(OneDrive から
  何曲追加したか、スキャンの進捗)は別の `lastNotice`(グレーのバナー)に出す。
  **`tracks` の `didSet` でサイドバー用の `oneDriveSources` を組み直す**(計算プロパティに
  すると `ContentView.body` の再評価ごと=0.5秒ごとに全曲を舐めることになるため)。
  その代わり `tracks` への書き込み1回ごとに O(n) の再計算が走るので、**スキャン結果の反映は
  ローカル配列に溜めてから最後に1回だけ代入する**(曲ごとに `tracks` を触ると、
  1300曲のスキャンで @Published の通知と再計算が1300回走る)。
  - **OneDrive の共有リンクだけは `LinkResolver` を通さない**: 1リンク=1曲を前提にした
    `LinkResolver.resolve` では表現できない(1リンク=複数曲)ため、`addLink`/`importLinks`
    とも `OneDriveShareClient.isShareLink` で判定して `scanOneDriveShare` へ振り分ける。
    同じ共有リンクを貼り直したときは `dedupeKey` で既存分をスキップし、共有フォルダに
    増えた曲だけを取り込む(同期のように使える) ― そのため `addLink` 冒頭の
    「同じ `sourceURL` は弾く」チェックより手前で分岐させている。
  `importLinks(_:)`(1行1リンクのテキストをまとめて解決)はリンクを1件ずつ**逐次**
  (並行実行ではない)解決し、成功のたびに `tracks.append` + `save()` するので、途中で
  アプリが終了しても解決済み分は残る。失敗した行はスキップして次へ進み、`ImportResult` として
  `importResult` に格納(`ImportLinksView.swift` のシートで一覧表示)しつつ、
  `~/Library/Application Support/MyMusic/import-errors.log` に
  `appendImportErrorLog` でタイムスタンプ付きで追記する(実行のたびに追記、上書きしない)。
  - **重複防止**: 判定キーは貼り付けた `sourceURL`(解決前の軽い一致チェック)と、解決後の
    `audioURL`(YouTube はローカルキャッシュパス、他サイトは実 mp3 URL)の二段構え。
    `audioURL` 基準にしているのは、同じ曲でも `youtu.be` と `youtube.com`、あるいは
    Suno/MusicGPT の共有コード違いのリンクなど **見た目の違う URL が同じ曲を指す**ケースを
    正しく重複扱いするため(解決してみないと同一かどうか分からないので、`addLink`/`importLinks`
    とも一旦 `LinkResolver.resolve` してから `audioURL` で照合している)。重複はエラーと同じ
    `lastError`/`ImportResult.failed` の経路に「重複のためスキップ」というメッセージで乗せている
    (専用の状態を増やさず、既存のエラー表示・ログ基盤をそのまま流用)。
    `importLinks` はバッチ内(同じテキスト貼り付け内)の重複も `seenSourceURLs`/`seenAudioURLs`
    に随時追加しながら検出する。
  - **既存プレイリストの重複除去**: `load()` は読み込んだ `tracks` を `dedupeKey` 基準で
    先勝ちフィルタしてから保持し、1件でも削れたら即 `save()` して `playlist.json` 自体も
    クリーンにする。過去バージョンで紛れ込んだ重複は次回起動時に自動的に消える
    (アプリ起動中に手動でクリーンアップする UI は持たない)。
- **再生前の URL 取り直し**(`ContentView.playTrack`): `track.oneDrive` が非 nil の曲は
  `player.load` を直接呼ばず、`store.refreshedTrack(_:)` で署名付き URL を取り直してから
  読み込む(1曲あたり数百ミリ秒。その間は前の曲がそのまま鳴り続ける)。取得中に別の曲が
  選ばれた場合に古い結果で上書きしないよう `playRequestID`(`@State` の UUID)で
  世代を照合し、待っている間にプレイリストが並び替わっている可能性があるので
  index ではなく `Track.id` で現在の位置を引き直してから `player.load` に渡す。
- **`PlayerEngine`**(`PlayerEngine.swift`): `AVPlayer` を薄くラップし、再生位置/長さを
  `Published` で公開する。**プレイリストの中身は一切知らない** — `load(track:)` で
  渡された1曲を再生するだけで、曲末尾到達時は `onTrackFinished` クロージャを呼ぶだけに留めている。
  次に何を再生するか(次曲へ進む/末尾なら停止)は `ContentView` 側の責務。
  再生中の曲は index ではなく `currentTrack: Track?` で持つ ― サイドバーの選択で
  キューの中身も並びも変わるため、index では「今どれを鳴らしているか」を表せない。
- **再生キューはサイドバーの選択そのもの**(`ContentView.visibleTracks` = 選択中のフォルダ +
  検索欄で絞った配列)。`playNext`/`playPrevious` はこの配列の中で現在の曲を `Track.id` で
  探して前後に動く(再生中の曲がキューの外にある場合 ― 再生中にフォルダを切り替えた等 ―
  は先頭から再生する)。
  - **`player.onTrackFinished` は `setupAutoplay()` で作り直し続けること**: このクロージャは
    `visibleTracks`(= `selection`/`searchText` という View の `@State`)に依存するため、
    `onAppear` で1度渡すだけだと View 構造体の古いコピーを捕まえたまま、最初に選んでいた
    フォルダのキューで自動送りし続ける。`onAppear` に加えて `selection`/`searchText`/
    `isShuffled`/`tracks.count` の `onChange` からも呼び直している(mytube の
    `PlayerPaneView.setupAutoplayNext()` と同じ罠・同じ対処)。
  - **シャッフル**: `isShuffled`(`@AppStorage` で永続化)と `shuffleHistory: [UUID]` は
    `PlayerEngine` ではなく `ContentView` が持つ。履歴は index ではなく `Track.id` を積む
    ― 並び替え・削除・キューの切り替えで index がずれる問題(以前の既知の限界)を
    構造的に回避するため。`play(_:recordHistory:)` の `recordHistory` は、シャッフル中の
    「前へ」で pop した曲を再生する際に履歴を二重に積まないためのフラグ。
- **`ToolLocator`**(`ToolLocator.swift`): downloader の同名ファイルと同一内容(yt-dlp/ffmpeg の
  探索)。共有パッケージ化するほどの規模ではないため意図的に複製している — 変更する場合は
  両方に反映するか、両者の乖離を許容する。
- **UI は iTunes/Music.app 風の3分割**(2026-08-12、「OneDrive のリンクは構造化で表示してほしい。
  イメージは MyTube の音楽版」という要望への対応。それ以前は幅380ptの縦1列 ―
  アートワーク+シークバーの下に全曲のフラットなリスト、という作りだった。1つの共有フォルダで
  1300曲入るようになり、フラットな一覧では実用にならなくなったため):
  上に再生バー(`PlayerControlsView.swift`、横一列に組み替え済み)、下は
  左に `LibrarySidebarView.swift`(幅220pt)+ 右に `PlaylistView.swift`(曲リスト)。
  ウィンドウの既定サイズも 380×640 → 940×620(最小 720×420)に広げてある(`AppDelegate.swift`)。
  - **`Library.swift`** ― サイドバーのデータ構造。`LibrarySelection`(`.all` / `.links` /
    `.oneDriveFolder(shareURL:folderPath:)`)の `matches(_:)` がそのまま曲リストの絞り込み条件で、
    フォルダは **`folderPath.starts(with:)` で配下も全部含む**(祖先フォルダを選べばその下の
    アルバムも全部聴ける ― mytube と同じ規約)。`LibraryTree.build` は `Track.folderPath` だけから
    木を組むので、曲の入っていない空フォルダは出ない。共有リンクの一覧
    (`PlaylistStore.oneDriveSources`)も曲から導出する ― ソース一覧を別ファイルに持つと
    `playlist.json` との二重管理になるため。
  - **`LibrarySidebarView.swift`** ― `List`/`OutlineGroup` を使わない自前の再帰ビュー
    (mytube の `SidebarView` と同じ理由: `OutlineGroup` は子の有無でインデント量がずれる)。
    **フォルダツリーは計算プロパティではなく `@State` にキャッシュし、曲数
    (`allCount`)と `sources` が変わったときだけ組み直す** ― `ContentView.body` は再生位置の
    更新で0.5秒ごとに再評価されるため、計算プロパティのままだと毎回全曲を辿ることになる。
    共有リンクのルート行の右クリックで「再スキャン」「この共有リンクの曲を削除」。
  - **曲リスト(`PlaylistView.swift`)は絞り込み後の配列を受け取る**ので、削除は行番号ではなく
    `Track` そのものを渡す(`PlaylistStore.remove(tracks:)`)。**削除は「MyMusic の
    ライブラリ(`playlist.json`)から外す」だけで、OneDrive 上のファイルにも共有元にも
    一切触れない**(リポジトリ規約どおり、リモートの実体を消す機能は持たない)。
    標準の `.onDelete` はスワイプ時のラベルが「削除」固定で、OneDrive の曲では
    「クラウド上のファイルが消える」と誤解されうる(ユーザーからの問い合わせで判明)ため、
    `.swipeActions` に置き換えて OneDrive の曲は「外す」、右クリックメニューは
    「ライブラリから外す(OneDrive のファイルは消えません)」と出し分けている。
    なお OneDrive の曲を1曲外しても、その共有リンクを再スキャンすれば戻ってくる
    (共有フォルダの中身が正)。ドラッグ並び替えは
    「すべての曲」+ 検索欄が空のときだけ有効 ― 絞り込み中の行を動かしても、元の配列の
    どこへ挿すのかを決められないため(`allowsReorder`)。
  - **`ArtworkStore.swift`** ― OneDrive の曲のジャケットを取得・キャッシュする
    (mytube の `Core/ThumbnailStore.swift` と同じ設計)。曲リストは1000曲を超えるため
    **表示されている行のぶんだけ** `.task(id:)` から遅延取得し、メモリ(`NSCache`)+
    ディスク(`~/Library/Caches/MyMusic/artwork/`)にキャッシュする。同時実行は `Limiter`
    (actor、4本)で絞り、同じ曲への重複リクエストは `inFlight` で1本にまとめ、
    ジャケット無し(404)は `missing` に憶えて再取得しない(セッション限り ― 共有元で
    アートを入れ直した場合に再起動で拾い直せるようにするため。通信エラーは `failedUntil` で
    10分抑止)。**`NSImage` は macOS 14 未満で `Sendable` でない**ため、`Task`/`Task.detached`
    を跨ぐ値は `ImageBox`(`@unchecked Sendable`)に包む ― `async` 関数の戻り値を
    `NSImage?` にすると警告になるので、`loadImage(for:size:)` は `ImageBox` を返す。
    行は `small`、再生バー(40pt = Retina で 80px)は `medium` を使う。
  - `ImportLinksView.swift`(複数リンクの一括インポート用シート。テキストエディタ・進捗・
    失敗一覧・Finder でのログ表示)は従来どおり。

## 変更時の注意

- yt-dlp/ffmpeg は同梱しない。両方揃っていない場合は YouTube リンクの追加のみ失敗し、
  それ以外のリンクは通常どおり使える(`PlaylistStore.ytdlpPath`/`ffmpegPath` が nil のときの
  バナー表示を維持する)。
- OneDrive まわりが動かなくなったら、まず内部 API 側の変更を疑うこと。`OneDriveShareClient` は
  Foundation にしか依存していないので、`swiftc main.swift OneDriveShareClient.swift` で
  ヘッドレスの CLI に組んで実リンクを叩けば GUI を起動せず切り分けられる(実際この形で
  スキャン・URL 取り直し・Range リクエストでの再生可否まで検証した)。mytube 側の同名
  ファイルも同じ API を使っているため、直すときは両方を見ること。
- 新しい曲共有サイトに対応する場合は `LinkResolver.resolve` にホスト名の分岐を1つ追加し、
  そのサイトの生 HTML を curl で確認してから抽出用正規表現を書くこと。`og:audio` メタタグを
  持つサイトなら `extractOGAudioURL` の汎用フォールバックだけで動く場合もある。
