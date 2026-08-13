# CLAUDE.md — downloader

YouTube ダウンローダー(`yt-dlp`/`ffmpeg` をラップ)の macOS アプリ(SwiftUI + AppKit + SPM)。
旧 `youtube-dl-mac` を吸収したもの — **別アプリとして復活させない**。使い方は `README.md` を参照。

**2026-08-12 に torrent 機能(`aria2c` を JSON-RPC でラップした「Torrent」タブ、旧 `torrent-dl-mac`)を
削除した**。`Aria2Engine.swift` / `TorrentView.swift` / `AddTorrentView.swift` / `SettingsView.swift` /
`Models.swift`(`TorrentItem` とバイト数フォーマッタ)を丸ごと削除し、`magnet:` URL スキームの
ハンドラ登録(Info.plist の `CFBundleURLTypes` + `kAEGetURL` Apple Event)も外してある。
**torrent 機能を戻さないこと** — 消した経緯があるので、必要になったら改めてユーザーに確認する。
削除前の実装(aria2 の JSON-RPC クライアント、メタデータ GID の扱い、完了時の即時 forceRemove など)は
git 履歴に残っている。

## ビルド / デプロイ

```bash
swift build         # コンパイル確認のみ(GUI 起動・目視確認は禁止 — ルート CLAUDE.md 参照)
./build_app.sh       # dist/Downloader.app を生成
./install.sh         # ビルド → /Applications/MyApplications へ上書きインストール
```

`dist/` `.build/` `AppIcon.icns` `AppIcon.iconset/` は .gitignore 済み・スクリプトから再生成される成果物。コミットしない。

## アーキテクチャ

- **既存 CLI をラップするだけ**で、YouTube のダウンロード自体は実装しない。yt-dlp/ffmpeg は
  Homebrew 前提・非同梱。
- **通常の Dock アイコン付きアプリ**(2026-08-05〜、以前は `LSUIElement=true` の
  メニューバー常駐アプリだった): `build_app.sh` の Info.plist に `LSUIElement` は書かず、
  `AppDelegate.applicationDidFinishLaunching` で `NSApp.setActivationPolicy(.regular)` を
  明示している(Info.plist だけでなくコード側でも `.accessory` を指定していたため、両方
  直す必要があった)。ただし SwiftUI の `App`/`WindowGroup` は使わず、`App.swift` の
  `@main enum` から `NSApplication` を直接 `run()` する構成は維持している ―
  macOS の `WindowGroup` アプリのデフォルト挙動である「最後のウィンドウを閉じるとアプリも
  終了する」を避けるため(ダウンロード中にウィンドウを閉じても継続させる)。
  Dock アイコンクリックでウィンドウを呼び戻せるよう `applicationShouldHandleReopen` も実装した。
  ウィンドウ管理・ステータスバーアイテムは `AppDelegate.swift` が一括して持ち、
  `ytDlpManager`(`YtDlpManager`)を `ContentView()` に `.environmentObject` で注入する。
- **`ContentView.swift` は `YouTubeView` を出すだけの薄い入れ物**。torrent 削除前は
  「YouTube」「Torrent」の `TabView` だった名残りで、タブは1つも無い。
- **`YtDlpManager`**(`YtDlpManager.swift`, 旧 `DownloadManager`): yt-dlp を `Process` として起動し、
  `--newline` の進捗行をパースする。プレイリスト対応は下記参照。
- **`ToolLocator`**(`ToolLocator.swift`): yt-dlp/ffmpeg の探索をこの1本で共有する。
  Homebrew の既知パス(`/opt/homebrew/bin`, `/usr/local/bin`)とログインシェルの両方を見る
  (Finder 起動だと PATH が引き継がれないため)。mymusic にも同一内容のコピーがあり、
  意図的に複製している(`mymusic/CLAUDE.md` 参照)。

### YouTube プレイリストのダウンロード

`YouTubeView` のトグル(`isPlaylist`、URLに`list=`を含むと自動でON)が`YtDlpManager.start`まで
素通しされ、`buildArguments`が`--no-playlist`/`--yes-playlist`と`-o`の出力テンプレートを切り替える。
プレイリストモードでは`-o`が`%(playlist_title)s/%(title)s [%(id)s].%(ext)s`になり、
`保存先/プレイリスト名/`のサブフォルダにまとまる ― mytube の「フォルダを選択」にそのまま渡せる形に
するため意図的にこうしている(mytube 自体はダウンロード機能を持たない設計方針
— `mytube/CLAUDE.md`参照 — なので、YouTube プレイリストの取り込みはここで完結させる)。
`handleOutput`は yt-dlp が出す`Downloading item 3 of 23`行を`parsePlaylistItem`で拾い、
`statusLine`の先頭に`(3/23) `を付与してプレイリスト全体の進み具合を見せる(ファイル単位の
パーセント表示`parsePercent`とは別物、両方を組み合わせて表示している)。
Audio・Video両方チェックした状態でプレイリストを落とすと、プレイリスト全体を2回
(audio抽出用・video結合用)処理する ― 単発動画のときの既存挙動と同じ。

### ダウンロード名の自動取得 / 上書き

`YouTubeView`はURL入力を500msデバウンス(`scheduleTitleFetch`、前回分は`Task.cancel()`)した後
`YtDlpManager.fetchTitle(url:isPlaylist:)`を呼び、ダウンロード自体は行わずタイトルだけ軽量取得して
「ダウンロード名」欄に反映する。プレイリストのときは`--flat-playlist --playlist-end 1 --print
"%(playlist_title)s"`で1件目の列挙だけに留めてプレイリストタイトルを取得(実測1秒前後、
全件列挙する`--dump-single-json`より高速)、単発動画は`--skip-download --print "%(title)s"`。
取得失敗(無効なURL・削除済み動画等)はnilを返すだけで、名前欄は手入力のまま使い続けられる
(呼び出し側でエラー表示はしない)。

「ダウンロード名」欄が空でなければ、`buildArguments`が`-o`テンプレートの`%(title)s`
(プレイリストなら`%(playlist_title)s`)の代わりにその文字列をそのまま埋め込む。この埋め込みは
`--restrict-filenames`の対象外(あれはyt-dlp側の`%()s`展開にしか効かない)なので、
`sanitizePathComponent`で`/`を置換し`.`/`..`だけの入力は空扱いにしてから使う
― ユーザー入力をパスの1階層としてそのまま使うため、意図しない階層作成/移動を防ぐガード。
`YouTubeView`側にも`customNameWarning`(同じ「/」「.」「..」の判定基準)があり、置き換えが
発生することをダウンロード前に注意文で知らせる ― 自動取得したタイトルに「/」が含まれることは
実際にある(曲名の「A/B」等)ため、黙って変わるより気付けるようにした。

## ソース構成 (`Sources/Downloader/`)

- `App.swift` — エントリ(`NSApplication.shared.run()`)
- `AppDelegate.swift` — ステータスバーアイテム、ウィンドウのライフサイクル管理
- `ContentView.swift` — トップレベル(`YouTubeView` を出すだけ)
- `YouTubeView.swift` — UI(URL入力・Audio/Video チェック・画質・保存先・ログ・中止)
- `YtDlpManager.swift` — yt-dlp プロセスの起動・進捗パース・フォーマット文字列の組み立て
- `ToolLocator.swift` — yt-dlp / ffmpeg の探索

## 変更時の注意

- yt-dlp/ffmpeg は同梱しない。`toolsReady == false` のときのバナー表示 + 操作無効化を維持する。
- 「ウィンドウを閉じても終了しない」という要件は `LSUIElement`(2026-08-05に廃止)ではなく、
  `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`が`false`を返すことと、
  `App.swift`が`NSApplication.shared.run()`を直接呼ぶ構成(SwiftUIの`WindowGroup`を使わない)
  の2つで成立している。この2つのどちらかを崩すと、ウィンドウを閉じただけでダウンロードが
  中断する事故につながるので変更時は注意する。
- yt-dlp の引数(フォーマット文字列・ファイル名テンプレート)を変える場合は README も更新する。
