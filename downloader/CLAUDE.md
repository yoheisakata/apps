# CLAUDE.md — downloader

YouTube ダウンローダー(`yt-dlp`/`ffmpeg` をラップ)と torrent ダウンローダー(`aria2c` を JSON-RPC 経由で
ラップ)を1つの常駐アプリに統合したもの(SwiftUI + AppKit + SPM)。旧 `youtube-dl-mac` と
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
- **常駐(メニューバー)アプリ**: `Info.plist` の `LSUIElement=true` で Dock アイコンなし。
  SwiftUI の `App`/`WindowGroup` は使わず、`App.swift` の `@main enum` から
  `NSApplication` を直接 `run()` している(最後のウィンドウを閉じると自動終了する挙動を避けるため —
  torrent のダウンロード継続に必須。YouTube 側もこの仕組みに相乗りしているだけで支障はない)。
  ウィンドウ管理・ステータスバーアイテムは `AppDelegate.swift` が一括して持ち、
  `aria2Engine`(`Aria2Engine`)と `ytDlpManager`(`YtDlpManager`)の両方を保持して
  `ContentView()` に `.environmentObject` で注入する。
- **UI はトップレベル `ContentView.swift` の `TabView`** で「YouTube」「Torrent」を切り替えるだけの薄い構造。
  各タブの実体は `YouTubeView.swift` / `TorrentView.swift`。
- **`YtDlpManager`**(`YtDlpManager.swift`, 旧 `DownloadManager`): yt-dlp を `Process` として起動し、
  `--newline` の進捗行をパースする。
- **`Aria2Engine`**(`Aria2Engine.swift`): aria2c を `Process` として起動し、
  `http://127.0.0.1:<random port>/jsonrpc` に `URLSession` で JSON-RPC を投げる。
  ポート番号・`--rpc-secret` はプロセス起動ごとにランダム生成。
  1秒間隔のポーリングで `tellActive`/`tellWaiting`/`tellStopped` を叩き `@Published var torrents` を更新する。
- **`ToolLocator`**(`ToolLocator.swift`): yt-dlp/ffmpeg/aria2c すべての探索をこの1本で共有する。
  Homebrew の既知パス(`/opt/homebrew/bin`, `/usr/local/bin`)とログインシェルの両方を見る
  (Finder 起動だと PATH が引き継がれないため)。

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
- `LSUIElement` を外すと Dock アイコンが出てしまい「ウィンドウを閉じても常駐」という要件が崩れるので、
  `build_app.sh` の Info.plist 生成部分は変更時に注意する。
- yt-dlp の引数(フォーマット文字列・ファイル名テンプレート)を変える場合は README の表も更新する。
