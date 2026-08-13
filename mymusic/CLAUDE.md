# CLAUDE.md — mymusic

曲の共有リンク(YouTube / Suno / MusicCreator.ai / MusicGPT / 直リンク mp3 等)をプレイリストとして
貼り付け、まとめて再生する SwiftUI + SPM 製のミニプレーヤー。ダウンロードして保存する用途ではなく
**再生に特化**している(YouTube だけは音声抽出のため内部的にローカルへ mp3 キャッシュするが、
ユーザーに見せる保存先 UI は持たない)。downloader と同じくメニューバー常駐(Dock アイコンなし)で、
ウィンドウを閉じても再生は止まらない。使い方は `README.md` を参照。

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

- **メニューバー常駐**(`Main.swift` + `AppDelegate.swift`): downloader と同一構成。SwiftUI の
  `App`/`WindowGroup` は使わず `Main.swift` の `@main enum` から `NSApplication.shared.run()` を
  直接呼ぶ。`AppDelegate` が `PlaylistStore`/`PlayerEngine` を(ウィンドウの生死とは無関係に)
  唯一のインスタンスとして保持し、`ContentView()` に `.environmentObject` で注入する。
  `applicationShouldTerminateAfterLastWindowClosed` を `false` にして、ウィンドウを閉じても
  プロセス(=再生)が終了しないようにしている。`NSApp.setActivationPolicy(.accessory)` +
  `build_app.sh` が書き込む Info.plist の `LSUIElement=true` で Dock アイコンを消し、
  代わりにメニューバーのステータスアイテム(♪ アイコン、クリックでメニュー「ウィンドウを開く」
  「終了」)を常駐させる。`NSApplication.shared.run()` を直接呼ぶ構成では `mainMenu` が
  自動生成されないため、`setupMainMenu()` で Edit メニュー(Cut/Copy/Paste/Select All)だけ
  最低限組み立てている(無いとテキストフィールドで Cmd+V が効かない)。
  **`NSMenuItem` は `target` を明示的に `self` に設定すること** — `addItem(withTitle:action:
  keyEquivalent:)` は既定で `target == nil` になり、レスポンダーチェーン(キーウィンドウの
  first responder → キーウィンドウ → `NSApp` → `NSApp.delegate`)を辿って解決される。
  アクセサリアプリでキーウィンドウが無い/フォーカスが特殊な状態だとこの解決に失敗し、
  「メニューの『終了』を選んでも何も起きない」という再現しづらい不具合になりうる(ユーザー報告)。
  Edit メニュー(Cut/Copy/Paste/Select All)は逆に **`target` を設定してはいけない** —
  フォーカス中のテキストフィールドの first responder に届く必要があるため、nil のままにする。
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
- **`Track`**(`Models.swift`): プレイリストの1曲。`audioURL` は再生に使う最終 URL で、
  YouTube はダウンロード済みローカルファイルの `file://` パス、それ以外は解決先サイトが返す
  リモート mp3 の直リンク文字列。`SiteKind` で UI 上のサイトバッジ表示を切り替える。
- **`PlaylistStore`**(`PlaylistStore.swift`): `tracks: [Track]` を保持し、
  `~/Library/Application Support/MyMusic/playlist.json` に JSON で永続化する。
  `addLink` は `LinkResolver.resolve` を `Task` 内で非同期に呼び、失敗時は `lastError` に
  日本語メッセージをセットする(呼び出し元でバナー表示)。
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
  - **既存プレイリストの重複除去**: `load()` は読み込んだ `tracks` を `audioURL` 基準で
    先勝ちフィルタしてから保持し、1件でも削れたら即 `save()` して `playlist.json` 自体も
    クリーンにする。過去バージョンで紛れ込んだ重複は次回起動時に自動的に消える
    (アプリ起動中に手動でクリーンアップする UI は持たない)。
- **`PlayerEngine`**(`PlayerEngine.swift`): `AVPlayer` を薄くラップし、再生位置/長さを
  `Published` で公開する。**プレイリストの中身は一切知らない** — `load(track:index:)` で
  渡された1曲を再生するだけで、曲末尾到達時は `onTrackFinished` クロージャを呼ぶだけに留めている。
  次に何を再生するか(次曲へ進む/末尾なら停止)は `ContentView` 側の責務。
- **シャッフル**(`ContentView.swift`): `isShuffled`(`@AppStorage` で永続化)と
  `shuffleHistory: [Int]`(再生した曲の index を積む配列)は `PlayerEngine` ではなく
  `ContentView` が持つ。シャッフル ON 時の `playNext` は現在の曲を除いた index からランダムに
  1つ選び、`playPrevious` は `shuffleHistory` を pop して直前に再生していた曲へ戻る
  (シャッフル OFF なら通常どおり index ±1)。`playTrack(at:recordHistory:)` の
  `recordHistory` はシャッフル中の「戻る」で pop した曲を再生する際に履歴を二重に積まないための
  フラグ。**プレイリストの並び替え/削除で `shuffleHistory` 内の index が古いプレイリストの
  内容を指したままになりうる**(未対応の既知の限界。個人利用スコープでは許容している)。
- **`ToolLocator`**(`ToolLocator.swift`): downloader の同名ファイルと同一内容(yt-dlp/ffmpeg の
  探索)。共有パッケージ化するほどの規模ではないため意図的に複製している — 変更する場合は
  両方に反映するか、両者の乖離を許容する。
- **UI**: `ContentView.swift`(URL 入力欄・エラーバナー・全体レイアウト・シャッフル状態管理)、
  `PlayerControlsView.swift`(アートワーク・シークバー・シャッフル/再生ボタン・音量)、
  `PlaylistView.swift`(プレイリスト一覧・並び替え・削除・選択再生)、
  `ImportLinksView.swift`(複数リンクの一括インポート用シート。テキストエディタ・進捗・
  失敗一覧・Finder でのログ表示)に分割。

## 変更時の注意

- yt-dlp/ffmpeg は同梱しない。両方揃っていない場合は YouTube リンクの追加のみ失敗し、
  それ以外のリンクは通常どおり使える(`PlaylistStore.ytdlpPath`/`ffmpegPath` が nil のときの
  バナー表示を維持する)。
- 新しい曲共有サイトに対応する場合は `LinkResolver.resolve` にホスト名の分岐を1つ追加し、
  そのサイトの生 HTML を curl で確認してから抽出用正規表現を書くこと。`og:audio` メタタグを
  持つサイトなら `extractOGAudioURL` の汎用フォールバックだけで動く場合もある。
