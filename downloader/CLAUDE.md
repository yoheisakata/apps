# CLAUDE.md — downloader

YouTube ダウンローダー(`yt-dlp`/`ffmpeg` をラップ)と torrent ダウンローダー(`aria2c` を JSON-RPC 経由で
ラップ)を1つのアプリに統合したもの(SwiftUI + AppKit + SPM)。旧 `youtube-dl-mac` と
`torrent-dl-mac` を吸収した — **別アプリとして復活させない**。使い方は `README.md` を参照。

## ビルド / デプロイ

```bash
swift build         # コンパイル確認のみ(GUI 起動・目視確認は禁止 — ルート CLAUDE.md 参照)
./build_app.sh       # dist/Downloader.app を生成
./install.sh         # ビルド → /Applications へ上書きインストール
```

`dist/` `.build/` `AppIcon.icns` `AppIcon.iconset/` は .gitignore 済み・スクリプトから再生成される成果物。コミットしない。

## アーキテクチャ

- **どちらのエンジンも既存 CLI をラップするだけ**で、YouTube のダウンロードや BitTorrent プロトコル自体は
  実装しない。yt-dlp/ffmpeg/aria2c はいずれも Homebrew 前提・非同梱。
- **通常の Dock アイコン付きアプリ**(2026-08-05〜、以前は `LSUIElement=true` の
  メニューバー常駐アプリだった): `build_app.sh` の Info.plist から `LSUIElement` を外し、
  `AppDelegate.applicationDidFinishLaunching` で `NSApp.setActivationPolicy(.regular)` を
  明示している(Info.plist だけでなくコード側でも `.accessory` を指定していたため、両方
  直す必要があった)。ただし SwiftUI の `App`/`WindowGroup` は使わず、`App.swift` の
  `@main enum` から `NSApplication` を直接 `run()` する構成は維持している ―
  macOS の `WindowGroup` アプリのデフォルト挙動である「最後のウィンドウを閉じるとアプリも
  終了する」を避けるため(torrent のダウンロード継続に必須。YouTube 側もこの仕組みに
  相乗りしているだけで支障はない)。ウィンドウを閉じてもプロセスは終了せず、
  Dock アイコン右クリックまたはメニューバー拡張アイコンの「終了」(Cmd+Qと同義)でのみ終了する。
  Dock アイコンクリックでウィンドウを呼び戻せるよう `applicationShouldHandleReopen` も実装した。
  ウィンドウ管理・ステータスバーアイテムは `AppDelegate.swift` が一括して持ち、
  `aria2Engine`(`Aria2Engine`)と `ytDlpManager`(`YtDlpManager`)の両方を保持して
  `ContentView()` に `.environmentObject` で注入する。
- **UI はトップレベル `ContentView.swift` の `TabView`** で「YouTube」「Torrent」を切り替えるだけの薄い構造。
  各タブの実体は `YouTubeView.swift` / `TorrentView.swift`。
- **`YtDlpManager`**(`YtDlpManager.swift`, 旧 `DownloadManager`): yt-dlp を `Process` として起動し、
  `--newline` の進捗行をパースする。プレイリスト対応は下記参照。
- **`Aria2Engine`**(`Aria2Engine.swift`): aria2c を `Process` として起動し、
  `http://127.0.0.1:<random port>/jsonrpc` に `URLSession` で JSON-RPC を投げる。
  ポート番号・`--rpc-secret` はプロセス起動ごとにランダム生成。
  1秒間隔のポーリングで `tellActive`/`tellWaiting`/`tellStopped` を叩き `@Published var torrents` を更新する。
- **`ToolLocator`**(`ToolLocator.swift`): yt-dlp/ffmpeg/aria2c すべての探索をこの1本で共有する。
  Homebrew の既知パス(`/opt/homebrew/bin`, `/usr/local/bin`)とログインシェルの両方を見る
  (Finder 起動だと PATH が引き継がれないため)。

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

### Torrent 側の設定反映が2系統ある点に注意

- アップロード/ダウンロード速度上限 → `aria2.changeGlobalOption` で即時反映(`applySpeedLimits()`)
- 保存先フォルダ・seed-ratio・seed-time → aria2c の**起動時オプション**のため、変更には
  `Aria2Engine.restart()`(プロセスを terminate して再起動)が必要。SettingsView の
  「保存して再起動」ボタンから呼ぶ。aria2 の RPC は `seed-ratio`/`seed-time`/`dir` を
  changeGlobalOption のホワイトリストに含めていないため、ここを一本化しようとしても動かない。

### 完了後の即時 forceRemove(Torrent)

`seed-ratio=0`/`seed-time=0` はデフォルトで設定済みだが、これは aria2 内部の**周期チェック**で
効くため、100% 到達から実際にシード停止と判定されるまで一瞬のラグがありうる。ピアへの UL を
本当に即座に断つため、`Aria2Engine.refresh()` は `status == "complete"` を待たず
`TorrentItem.isFullyDownloaded`(バイト数だけで `completedBytes >= totalBytes` を判定)の時点で
`remove(gid)`(`aria2.forceRemove` + `removeDownloadResult`)を自分から呼び、一覧からも即座に外す。
`removalRequested: Set<String>` で同じ GID に対する重複呼び出しを防いでいる。
副作用として、**完了した torrent は一覧に「完了」の行としては一切表示されない**(見えた瞬間に消える)。
ダウンロードできたかどうかはダウンロード先フォルダの実ファイルで確認する。

### セッション永続化(Torrent)

`~/Library/Application Support/Downloader/session.aria2` に `--save-session`(30秒毎)。
次回起動時にファイルが存在すれば `--input-file` で読み込み、未完了のダウンロードキューを復元する
(分割ファイル自体の再開は aria2 の `.aria2` コントロールファイルによる)。

### magnet: URL スキームハンドラ

`build_app.sh` が Info.plist に `CFBundleURLTypes`(scheme = `magnet`)を書き込み、
`AppDelegate.applicationWillFinishLaunching` で `kAEGetURL` Apple Event のハンドラを登録する
(`applicationDidFinishLaunching` ではなく `willFinishLaunching` で登録するのが重要 — 未起動状態から
magnet リンククリックで起動された際の最初のイベントを取りこぼさないため)。受け取った URL は
`Aria2Engine.addMagnet` に渡す。アプリ起動直後は aria2c の RPC がまだ listen していないことがあるため、
`addMagnet`/`addTorrentFile` は内部で `addWithRetry`(300ms 間隔・最大10回)を使う。

### magnet 追加時の「メタデータ GID」の扱い

magnet を追加すると aria2 はまず .torrent メタデータ自体(数十KB)を DHT/トラッカー経由のピアから
取得する内部 GID を作り(ピアが見つかって ut_metadata 交換が終わるまで数秒〜十数秒かかることがあり、
これが「進捗バーが出るまでのラグ」の正体)、取得完了で `followedBy` により本体データ用の新しい GID に
引き継ぐ。引き継ぎ後のメタデータ GID(`followedBy` 非空、`TorrentItem.isMetadataHandoffDone`)を
そのまま一覧に出すと「進捗が一瞬で100%になる謎の項目」に見える(本体側は別 GID で別途進捗しているだけ)
ため `refresh()` で除外する。引き継ぎ前(`files[0].path` が `[METADATA]` で始まる、まだ取得中、
`TorrentItem.isFetchingMetadata`)のものは除外せず、`TorrentView.TorrentRow` 側で
「メタデータ取得中…」という不確定プログレスの専用表示に出し分けている
(ラグの間もユーザーに何も見えない状態を避けるため)。

### `~/Library/Application Support/Downloader/app.log`

イベント受信・追加の成否を記録するアプリ独自ログ(`Aria2Engine.appendLog`/`noteEvent`)。
aria2c 自体のログ(`aria2.log`)は `--log-level=warn` のため RPC 呼び出しの成否が出ず、
GUI を起動できない制約下では「magnet リンクのクリックがアプリに届いたか」「追加 RPC が成功したか」を
追う手段がなかった。ブラウザ起動まわりの不具合報告を受けたら、まずこのファイルを読む。
`refresh()` のポーリング成功時に `lastError` を無条件で nil に戻していたバグ(1秒ごとの一覧取得が
直前の追加失敗バナーを即座に消してしまい、失敗が完全にユーザーから見えなくなっていた)も
この調査で見つかったため修正済み — `lastError` は追加操作の開始時にのみクリアする。

## ソース構成 (`Sources/Downloader/`)

- `App.swift` — エントリ(`NSApplication.shared.run()`)
- `AppDelegate.swift` — ステータスバーアイテム、ウィンドウのライフサイクル管理、両エンジンの起動/終了、magnet ハンドラ
- `ContentView.swift` — トップレベルの `TabView`(YouTube / Torrent)
- `YouTubeView.swift` — YouTube タブの UI(URL入力・Audio/Video チェック・画質・保存先・ログ・中止)
- `YtDlpManager.swift` — yt-dlp プロセスの起動・進捗パース・フォーマット文字列の組み立て
- `TorrentView.swift` — Torrent タブの一覧 UI、ドラッグ&ドロップ受け口
- `AddTorrentView.swift` — マグネット貼り付け・ファイル選択シート
- `SettingsView.swift` — Torrent の帯域制限・保存先・シード設定
- `Aria2Engine.swift` — aria2c プロセス起動・JSON-RPC クライアント・ポーリング・設定反映。`Settings` enum(UserDefaults キー定義)もここに同居
- `Models.swift` — `TorrentItem`(tellStatus の JSON デコード)、バイト数フォーマッタ
- `ToolLocator.swift` — yt-dlp / ffmpeg / aria2c 共通の探索

## 変更時の注意

- yt-dlp/ffmpeg/aria2c は同梱しない。各タブは対応する `toolsReady == false` のときバナー表示 + 操作無効化を維持する。
- RPC のシークレットトークンは各パラメータの先頭に `"token:<secret>"` を付与する形式(aria2 の認証仕様)。
  この形式を崩すと全 RPC 呼び出しが `Unauthorized` になる。
- 「ウィンドウを閉じても終了しない」という要件は `LSUIElement`(2026-08-05に廃止)ではなく、
  `AppDelegate.applicationShouldTerminateAfterLastWindowClosed`が`false`を返すことと、
  `App.swift`が`NSApplication.shared.run()`を直接呼ぶ構成(SwiftUIの`WindowGroup`を使わない)
  の2つで成立している。この2つのどちらかを崩すと、ウィンドウを閉じただけでTorrentダウンロードが
  中断する事故につながるので変更時は注意する。
- yt-dlp の引数(フォーマット文字列・ファイル名テンプレート)を変える場合は README の表も更新する。
