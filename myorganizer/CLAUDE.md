# CLAUDE.md — MyOrganizer (myorganizer/)

`utilities/` の写真・動画パイプライン用スクリプト6本のロジックをSwiftネイティブで
再実装し、旧`renamer/`アプリの一括リネーム機能、旧`cleanmac/`アプリのキャッシュ掃除・
アプリのアンインストール機能、旧`omoide/`アプリのまとめ動画作成機能、旧`mydownloader/`
アプリのYouTubeダウンロード機能も統合して、1つのGUIにまとめたmacOSアプリ。
**SwiftUI + SPM** 構成。リポジトリ全体の規約はルートの `CLAUDE.md` を参照。

## ビルド / デプロイ

```bash
swift build                      # コンパイル確認のみ(GUI 起動・目視確認は禁止 — ルート CLAUDE.md 参照)
./build_app.sh                   # release ビルド → MyOrganizer.app
./install.sh                     # ビルド → /Applications/MyApplications へインストール
```

- **バージョンは `Sources/MyOrganizer/Main.swift` の `appVersion` が唯一の定義**。
  `build_app.sh` が Info.plist の `CFBundleShortVersionString` に反映する。

## 設計上の方針

- `utilities/` のスクリプトは**呼び出さない**。日付推定(EXIF/QuickTime→mdls→フォルダ名
  →ファイル名→mtimeの5段階フォールバック)・MD5重複判定・rsync差分パース等のロジックは
  すべてSwiftで独立に再実装している。`utilities/` 側を変更してもこのアプリには
  自動反映されないので、挙動を揃えたい場合は両方を手動で直す。
- 旧`renamer/`アプリ(単一ファイル`main.swift`・swiftc直接ビルド)はロジック・UIとも
  無変更でこのアプリに移植し、`renamer/`ディレクトリ自体は削除済み。データ保存先も
  `~/Library/Application Support/Renamer/` から `~/Library/Application Support/
  MyOrganizer/Renamer/` に変更した(presets.json・history.log)。
- 旧`cleanmac/`アプリ(キャッシュ掃除・アプリのアンインストール・重複写真検出)も
  ロジック・UIとも無変更でこのアプリに移植し、`cleanmac/`ディレクトリ自体は削除済み。
  cleanmacは状態を持たない(プリセットや履歴の永続化なし)ため、データ移行は不要だった。
  唯一のクラス名変更は`DupPhotosEngine`→`DupPhotosViewModel`(他の`ViewModels/`との
  命名一貫性のため。`RenamerViewModel`が旧`AppState`から改名された前例と同じ扱い)。
  その後、重複写真検出(「重複写真」ペイン・`DupPhotosViewModel`/`DupPhotosView`)は
  不要になったため削除した。写真サムネイル読み込み(`ThumbLoader`)だけは「日付推定」
  ペインも使っていたため、削除前に`Core/ThumbLoader.swift`へ切り出して残した。
  dHash自体(`PerceptualHash`)・しきい値(`MatchLevel`)・`UnionFind`はもともと
  `SimilarityIndex`/`VideoDupFinder`が使うため元からCoreに独立していたので、
  重複写真の削除による影響はない。
- 旧`mydownloader/`アプリ(YouTube動画・音声のダウンロード、`yt-dlp`/`ffmpeg`ラッパー)を
  「ダウンロード」ペインとして移植し、`mydownloader/`ディレクトリ自体は削除済み
  (2026-09-02)。ロジック(`YtDlpManager`)はほぼ無変更で
  `ViewModels/DownloaderViewModel.swift`へ移植したが、次の2点は変更している。
  ①シングルトン化(`.shared`) — `JobRunner.shared`と同じ理由で、サイドバーの選択を
  切り替えるとdetailの`switch`が新しいView構造体を作り直すため、ペイン自身が
  `@StateObject`で状態を持つ設計だとダウンロード中に他ペインへ切り替えただけで
  進行中のダウンロード状態(進捗・ログ・`Process`参照)が失われてしまう
  (mydownloaderは単一ウィンドウでこの問題自体が存在しなかった)。
  ②独自実装だった`ToolLocator`(Homebrew既知パス3つ+ログインシェルの`command -v`)を
  廃止し、既存の`Core/ToolLocator.swift`の`resolve`(キャッシュ+`NSLock`付き)に統一した。
  `yt-dlp`/`ffmpeg`を同梱しない前提は引き継ぎ、「依存チェック」ペインにも`yt-dlp`の
  項目を追加した。mydownloaderは「ウィンドウを閉じてもダウンロード継続」のために
  `AppDelegate`+`NSApplication.shared.run()`直接呼び出し(SwiftUIの`WindowGroup`を
  使わない構成)でDockアプリのライフサイクルを自前管理していたが、MyOrganizerは
  元々`WindowGroup`1枚構成でこの問題設定自体が存在しない(アプリを終了しない限り
  ウィンドウは開いたまま、サイドバーで別ペインへ切り替えるだけ)ため、この部分は
  移植していない — 上記①のシングルトン化だけで「ペインを離れてもダウンロードは
  裏で継続する」という実質的な要件は満たされる。
- `ffmpeg` / `ffprobe` / `rsync` / `sips` / `mdls` は外部コマンドとしてそのまま呼ぶ
  （同梱しない）。`sips` / `mdls` はmacOS標準、`ffmpeg` / `ffprobe` / `rsync` は
  Homebrew前提（`Core/ToolLocator.swift` が `/opt/homebrew/bin` → `/usr/local/bin` →
  `/usr/bin` → `PATH` の順で解決）。
- 「写真検証」ペイン(`VerifyView`/`VerifyViewModel`)は削除済み。単一年フォルダに対して
  `PhotoVerifier.run`をreport/dryRun/fixモードで呼ぶだけで、複数年・月単位選択や
  類似写真フォールバックを持つ「誤配置修正」ペインの完全な部分集合だったため
  (誤配置修正で年を1つだけ選べば同じ操作ができる)。`PhotoVerifier`/`VerifyMode`自体は
  誤配置修正が使うため引き続き`Core/`に残る。

## 構成 (`Sources/MyOrganizer/`)

- `Main.swift` — エントリポイント + `appVersion`。`WindowGroup`1本のみ(メイン画面)。
  実行状況・実行ログは別ウィンドウではなく各ペイン内に埋め込む方式(下記)。
- `ContentView.swift` — `NavigationSplitView` のサイドバー。15ペインを「画像系」(写真整理/
  誤配置修正/日付推定)・「動画系」(動画整理/エンコード/短い動画検索/動画重複/まとめ動画)・
  「その他」(リネーム/同期/OneDrive同期/クリーン/ストレージ分析/アプリ削除/ダウンロード/
  依存チェック — 画像・動画どちらか専用ではない汎用機能)の3セクション(`sidebarGroups`)に
  グルーピングして`List`の`Section`で表示する。
  選択(`selection: SidebarItem?`)はセクションをまたいで共通の1つの`Binding`。
- `Core/`
  - `RenameEngine.swift` — 旧renamerのルールエンジン(状態を持たない純粋ロジック)。
    `RuleKind`等のenum群、`RenameRule.apply(base:ext:seqIndex:item:meta:)`、
    `FileItem`/`PreviewEntry`/`Preset`。EXIF(ImageIO)・音楽タグ(AVFoundation)読み取りは
    ここではなく`RenamerViewModel`側(メタデータキャッシュを持つため)。
  - `MediaOrganizer.swift` — 写真整理・動画整理の共通エンジン(走査→日付解決→MD5重複判定
    →リネーム移動)。拡張子集合・日付リゾルバ・HEIC変換有無だけを設定で切り替える
    (`backup-photos.sh`/`backup-videos.sh`が重複実装していたロジックを統合)。
    `afterMove`フックで「移動直後のファイル」を受け取れる(動画整理がここにH.265エンコードを
    差し込み、移動とエンコードを1ファイルずつ交互に行う)。`async throws`。
  - `MediaDateResolver.swift` — 日付推定の5段階フォールバック。一次ソース(EXIF=sips /
    QuickTime=ffprobe)だけ呼び出し側が渡す。ファイル名フォールバック(`fromFileName`)のうち
    iOSが生成する`YYYYMMDD_HHmmssSSS_iOS`形式(例: `20210120_205244217_iOS.heic`)は、
    埋め込まれた時刻がローカル時刻ではなくUTCであるため(実機で確認: EXIF上のローカル撮影時刻と
    ファイル名の時刻がタイムゾーン差ぶんずれていた)、他のファイル名パターン(ローカル時刻として
    解釈)とは別に`utcCalendar`で解釈してからDateに変換する。数字部分だけなら他の
    `YYYYMMDD_HHmmss`パターンにもマッチしてしまうため、`_iOS`判定を先に行う。
  - `H265Encoder.swift` — エンコード判定(skip/remux/encode)とffmpeg実行
    (`-progress pipe:1`で進捗%抽出)。1ファイル分の判定・実行は`processFile(_:label:...)`
    に切り出してあり、フォルダ一括の`run(config:...)`(「エンコード」ペイン用)と、
    動画整理の`afterMove`フック(移動直後の1ファイルだけ)の両方から呼ばれる
    (`encode_h265.py`と`backup-videos.sh`内の重複を統合した上の共通実装)。
    `processFile`は`(outcome: FileOutcome, sizeMB: Double)`を返し(元ファイルのサイズを
    呼び出し側で計算し直さなくて済むよう一緒に返す)、`EncodeResult.add(_:sizeMB:)`が
    `.encoded`(実際にH.265へ再エンコードする、または dry-run では「する予定」)のケースだけ
    `encodedSizeMB`に積算する(remux/skipは対象外 — コンテナ変換のみは一瞬で終わるため、
    「エンコードにどれだけの元サイズが必要か」の集計には含めない)。dry-runでは実際には
    ffmpegを呼ばないため`.failed`にはならず、`encodedSizeMB`はそのまま「エンコードが
    必要なトータルサイズ」を表す。`run(config:...)`終盤の`=== エンコード結果 ===`ログと、
    `VideosViewModel`の動画整理後のエンコードサマリーの両方に、`encoded`件数が1件以上
    あれば`ByteFmt.string`で整形した合計サイズの行を追加する。`analyze(files:minSizeMB:
    remuxOnly:onProgress:)`は`processFile`と同じ判定順序(H.265+mp4→skip、サイズ未満→skip、
    H.265のみ→remux、remuxOnly→skip、それ以外→encode)をffmpegを呼ばずffprobeだけで
    再現する「エンコード」ペインの「スキャン」ボタン用(`EncodeViewModel.scan()`が
    `VideoDupViewModel`と同じバックグラウンドキュー+進捗コールバックの
    パターンで呼ぶ)。以前はこの関数自体が定義されているだけで呼び出し元がなく、しかも
    `minSizeMB`/`remuxOnly`を引数に取らず判定に反映していなかった(実際の`run`とは
    ずれた甘い判定のまま放置されていた)ため、スキャン機能を配線する際に判定ロジックを
    `processFile`に追従させる形で書き直した。`EncodeViewModel`は`@MainActor`のため、
    バックグラウンドキューからキャンセルフラグを読み書きする箇所は`private final class
    CancelFlag`(ロック付き、`VideoDupViewModel`の`Counter`と同じ考え方だが`@MainActor`
    隔離の警告を避けるため`@unchecked Sendable`にしている)を介す。

    **ジョブ全体の進捗表示**: `run(config:...)`の`setProgress`は「今処理中の1件」の
    ffmpeg進捗(`-progress pipe:1`由来、ファイルが変わるたびに`nil`にリセット)専用で、
    もともと「フォルダ内に何件エンコード待ちが残っているか」を示す全体進捗の概念が
    無かった。これを追加するため`JobRunner.Handle`に`setOverallProgress`/
    `setOverallDetail`(`JobRunner`側は`overallProgress: Double?`/`overallDetail: String`、
    `progress`/`detail`と同様ジョブ開始・終了時にリセット)を新設した。`H265Encoder.run`は
    ループ開始前に`analyze(files:minSizeMB:remuxOnly:)`を1回通し(「スキャン」ボタンと
    同じ処理を自動実行、ログに`エンコード対象を確認中…`/`エンコード対象: N件`を出す)、
    実際に`.encode`判定されたファイルの集合を`encodeTargets`として保持する。メインループは
    従来通り全ファイル(skip/remux込み)を回すが、処理したURLが`encodeTargets`に含まれる
    ときだけ`encodeDone`をインクリメントして`setOverallProgress(encodeDone/encodeTotal)`
    を呼ぶ — 分母を全ファイル数ではなく実際にエンコードが必要な件数にしているのは、
    一瞬で終わるskip/remuxを混ぜると「実際の作業量」とかけ離れた%になるため。
    `analyze`をここでも呼ぶため`processFile`内の`getVideoCodec`と合わせてffprobeが
    ファイルごとに2回走る(スキャンボタンと同じ既知のコスト)が、ffprobe自体は軽量で
    実際のlibx265エンコード時間に比べて無視できるため許容している。UIは
    `JobLogSectionView`(ペイン内、タイトル行の上に「全体の進捗」バーを追加)と
    `StatusBarView`(ウィンドウ下部、詳細テキストの下に`全体: N / M件（エンコード対象）`を
    追加)の両方に出す。`overallProgress`が`nil`のジョブ種別(エンコード以外)は
    このUIごと非表示になるだけで、他ペインへの影響はない。`overallDetail`には残り時間の
    目安も含める(`formatETA(_:)`)。ループ開始前に`encodeStartTime = Date()`を記録し、
    `エンコード対象1件終わるたびに「経過時間 ÷ 完了件数」を1件あたりの平均所要時間とみなして
    残り件数に掛ける単純な線形外挿(ダウンロードの残り時間表示等でよく使う方式)で見積もる。
    ファイルごとに長さ・解像度が違うためあくまで目安で、1件も終わっていない段階では
    見積もりようがないため出さない(`remaining > 0`かつ`encodeDone >= 1`のときだけ)。

    **コーデック取得失敗の原因表示**: 旧`getVideoCodec`は`ffprobe`が見つからない・
    実行できない・出力が空・映像ストリームが無い、をすべて一律`nil`にまとめていたため、
    実際にFull Disk Access権限が原因でフォルダ内の全ファイルが一斉に
    「コーデック取得失敗」になった際、ログを見ても原因が全く分からなかった。
    `probeVideoCodec(_:) -> CodecProbeResult`(`.success(String)`/`.failure(String)`)を
    新設して理由つきで返すようにし、`getVideoCodec`はこれの`.codec`を返すだけの薄い
    ラッパーとして残した(`VideoDupFinder`等の既存呼び出し元は無変更で動く)。
    `EncodeCandidate.errorReason`(action == .errorのときだけ非nil)に理由を積み、
    「スキャン」結果(`EncodeScanSummary.errorSamples`、先頭3件を`ファイル名: 理由`で
    `EncodeView`に表示)と、`run(config:...)`実行時の`processFile`のログ行
    (`[SKIP] コーデック取得失敗: <理由>`)の両方で理由が見えるようにした。
  - `PhotoVerifier.swift` — 構造検証・修正(report/dry-run/fixの3モード)。EXIF/mdls/フォルダ名/
    ファイル名のどこからも撮影日が分からずmtimeフォールバックになったファイルは、誤った年月日
    フォルダを作らずルート(年フォルダ)の親直下のUnknown/へ元のファイル名のまま退避する
    (`MisplacedFixViewModel`が年単位・月単位でこれを呼び出す用途で使う。`monthFilter`を
    渡すとroot直下の一致する月フォルダだけを処理する。`maxFixCount`を渡すとfixモードでは
    問題が上限件数見つかった時点でスキャン自体を打ち切る(EXIF/mdls呼び出しが主なコスト
    なので全件スキャンを待たずに済む。report/dryRunは全件見せたいので上限を適用しない)。
    `estimateFileCount`は日付解決なしで対象ファイル数だけ軽く数える、全体進捗バー用の
    ヘルパー。`safeMove`(実際のファイル移動)は`fm.moveItem`/`createDirectory`の失敗を
    `try?`で握りつぶさずthrowする — 以前はOneDrive等のプレースホルダー(未ダウンロード)
    ファイルで移動が実際には失敗していてもログ上「FIX」と表示され`fixed`にカウントされる
    バグがあったため、失敗は`VerifyResult.failed`に計上し`[ERROR]`としてログに出す。
    `similarityIndex: LazySimilarityIndex?`を渡すと、mtimeフォールバックになったファイルに
    ついて`SimilarityIndex`(下記)でEXIF付きの類似写真を探し、見つかれば`類似写真(EXIF)`
    という`dateSource`でその日付を借用する。借用元は`VerifyIssue.matchedFrom`に記録し、
    report/dryRun/fixのログに「類似元: ...」として出す。類似写真経由で解決した件は
    `[kind]`表示が`[kind・類似写真]`になり(`kindLabel`)、`VerifyResult.similarityMatched`
    に件数を集計してサマリー行にも「うち類似写真から日付を推定: N件」として出す — 通常の
    EXIF/mdls等での解決と混ざって見えないよう、あいまいな根拠に基づく変更だと一目でわかる
    ようにするため)。
  - `VideoMaker.swift` — 旧`omoide/`アプリの移植。「まとめ動画」ペインの中核。
    `findVideos(in:)`(拡張子フィルタ+再帰列挙)・`detectTitle(from:)`(フォルダ名から
    「YYYY年MM月」構造を検出しタイトル初期値にする)は純粋関数として残し、UI状態を
    持つ列挙・タイトル検出は`VideoMakerViewModel`から呼ぶ。本体の`generate(config:...)`
    はomoideの`doGenerate`をベースにしたアルゴリズム(各動画から`effectiveClipSec`秒を抽出
    (`blackdetect`/`freezedetect`で暗い/止まったシーンを最大5回リトライして回避、
    詳細は後述) →
    ディゾルブトランジション付きで結合 → フェードイン+タイトルオーバーレイ → 先頭に
    黒画面タイトルカード(3秒)を追加 → BGMをループ+フェードインして合成 → 終端の演出)
    だが、実行方式はomoideの独自`isRunning`/`progress`/`statusMessage`から他ペインと
    同じ`JobRunner`ベースに置き換えた。ffmpeg呼び出しもomoideの同期`Process`
    (`waitUntilExit`)直呼びから、他Coreファイルと同じ`ProcessRunner`(非同期・
    `onCancel`でプロセス終了可)/`SyncExec`(ffprobeでのdurationやクリップ品質チェックの
    ような短時間コマンド)に置き換え、パス解決も`ToolLocator.resolve`に統一した
    (omoideはffmpeg/ffprobeのパスを`/opt/homebrew/bin`→`/usr/local/bin`に自前で
    ハードコードしていた)。クリップ抽出フェーズ(0〜70%)はクリップ本数のインデックスで
    進捗を出す(omoideと同じ簡易的な方式)が、結合・BGM合成フェーズ(70〜78%/85〜92%)は
    `-progress pipe:1`の`out_time_ms`を`runFFmpegWithProgress`でパースする
    `H265Encoder.runFFmpegWithProgress`と同じパターン。タイトル画像生成
    (`renderTitleOverlay`、CoreGraphics/CoreTextで黒帯+テキストのPNGを描画し
    ffmpegの`overlay`/`-loop 1`で合成、drawtextフィルタの代替)はomoideから無変更で移植。
    クリップ抽出時に`hasAudioStream(ffprobe:path:)`(ffprobeで`-select_streams a`の結果が
    空かどうか判定、判定不能時は安全側で「あり」扱い)で音声トラックの有無を確認し、
    無音のソース動画(スクリーン録画等)には`-f lavfi -i anullsrc=r=44100:cl=stereo`で
    ダミーの無音トラックを合成してから抽出する。これはomoideには無かった処理で、
    2クリップ以上をディゾルブ結合する分岐が全クリップの音声ストリーム(`[i:a]`)を
    前提に`filter_complex`を組み立てるため、音声トラックの無いソースが1本でも
    混ざっていると`Stream specifier ':a' ... matches no streams`でffmpegごと失敗する
    バグがあった(実際に無音のスクリーン録画動画が混在するフォルダで発生した)。
    `normalizeFilter`(クリップ抽出時の`scale`/`pad`)には`setsar=1`を入れている
    (omoideには無かった) — ソース動画が非正方形ピクセル(SAR≠1)を持つ場合、
    `scale`/`pad`で1920x1080の固定解像度にしてもSARのメタデータはそのまま引き継がれ、
    再生側がそのSARに基づいてさらに引き伸ばして表示してしまう(動画によって画像が
    伸びて見えるバグの原因だった)。`setsar=1`で正方形ピクセルに矯正することで解消する。
    暗い/止まったシーンを避けるリトライも、単純な乱数5回だと同じ(静止した)区間に
    5回とも偏って当たり得る(特にソース動画の一部だけが静止している場合に、その静止区間を
    引き続けて`isGoodClip`が全滅し、「最終はあきらめて使う」のフォールバックで実際に
    静止したクリップを採用してしまう — 「最後の動画が止まって見える」不具合の原因だった)ため、
    範囲を`attempts`(5)等分したバケツごとに1回ずつ試す方式に変更した(バケツ内では
    乱数でずらすため、再生成のたびに多少違う位置を試す挙動は維持)。それでも動画全体が
    完全に静止している場合はどのバケツを試しても全滅するため、最終走査地点をそのまま
    使うフォールバック自体は残っている(ソース映像そのものが静止しているケースはアルゴリズムでは解決できない)。
    `VideoMakerConfig.perClipSeconds: [Int]?`(既定nil)は「自動作成」用の拡張で、
    `videos`と同じ順序・個数で各クリップの秒数を個別指定できる(nilなら従来通り
    `clipSec`を全クリップに一律適用する手動モード)。これに伴い`generate(config:)`内の
    クリップ秒数は単一の`effectiveClipSec`変数からクリップごとの`durations[idx]`配列
    (private `clipDurations(config:)`が`perClipSeconds`と`clipSec`のどちらから
    導出するかを吸収する)に置き換えた。ディゾルブ結合(`xfade`/`acrossfade`の
    `filter_complex`)のoffset計算も、以前は全クリップ同じ長さ前提の等差数列
    (`(i+1)*effectiveClipSec - (i+1)*transDur`)だったが、クリップごとに長さが違うと
    成立しないため、`runningLength`(それまでの結合済み実長)を都度更新しながら
    「隣接ペアごとに`min(transitionSec, min(durations[i], durations[i+1])/2)`だけ
    重ねる」方式に一般化した。`estimateTotalSec(config:)`も同じロジックを
    private `mainDuration(durations:transitionSec:)`として共有し、UIプレビューと
    実際の生成が食い違わないようにしている。

    **自動作成でしばしば動画が数秒間フリーズする不具合**(2026-07-29): クリップ抽出時、
    ソース動画の実際の長さが要求した秒数(`durations[idx]`、自動作成では2〜3秒がランダムに
    割り当たるため特に起きやすいが、手動モードの`clipSec`でも短い素材があれば同様に起こり得る)
    に満たない場合、ffmpegの`-t`は単に素材が尽きた時点で止まるだけで、指定した秒数分の
    映像が生成されるわけではない。ところが後段のディゾルブ結合(xfadeの`offset`計算)は
    「要求した秒数」をそのまま使って全クリップの結合後タイムラインを組み立てるため、
    実際には存在しない区間をxfadeに要求することになり、その区間はソース側の最終フレームが
    そのまま引き延ばされて数秒間静止して見える(検証用に`swiftc`で`VideoMaker.swift`単体を
    ビルドし、1秒しかない素材に2秒を要求するケースを再現したところ、フレームサンプリングで
    13フレーム分・3秒以上にわたって同一サイズのフレームが連続することを確認した)。
    修正: 抽出ループ内で`getDuration(ffprobe:path:)`と`earliest`(シーク開始位置)から
    実際に抽出可能な長さ`effectiveClipSec = min(requestedClipSec, max(0.1, dur - earliest))`を
    計算し、`-t`に渡すと同時に`durations[idx]`(`var`に変更)へ書き戻す。クリップ抽出は
    全クリップぶん先に完了してから結合フェーズに入るシーケンシャルな設計のため、結合時に
    参照する`durations`配列はこの時点で全クリップぶん実測値に更新済みになっており、
    xfadeのoffset計算や`estimatedDur`(=`mainDuration(durations:transitionSec:)`)も
    実測ベースで一貫する。

    `mediaDurationSec(_:)`は`getDuration(ffprobe:path:)`(生成処理内部で使うprivate版)の
    公開ラッパーで、`VideoMakerViewModel`がBGMファイルの長さ表示(「選択…」で選んだ直後・
    アプリ起動時にUserDefaultsから復元したパスの両方で`refreshMusicDuration()`から呼ぶ)
    のように、生成処理の外からffprobeでメディアの長さだけ知りたい場合に使う。
    終端の演出はomoideから変更した点: omoideは映像と音声(元音声・BGMそれぞれ別に)を
    同時に同じ長さでフェードアウトしていたが、「音がフェードアウトし終わってから映像が
    黒みにフェードアウトし、黒みを2秒保持して終わる」という順序だったユーザー要望に
    合わせて再設計した。BGM合成(`amix`)はフェードインだけをかけた状態で先に元音声と
    1本のトラックへ混ぜ、その後の`outro_faded.mp4`生成ステップで映像・音声(混合済み)
    それぞれに`fade`/`afade`の`t=out`を1回だけかける(元音声とBGMを別々にフェードアウト
    させると二重にフェードがかかってしまうため、必ず`amix`後の1トラックに対して行うこと)。
    `audioFadeStart`(音声フェード開始)は`videoFadeStart`(映像フェード開始)から
    `audioFadeSec`だけ遡った時刻にすることで、音声フェードが終わったちょうどそのタイミングで
    映像フェードが始まるようにしている(重ならない・隙間も空かない)。フェード長
    (`videoFadeSec`/`audioFadeSec`、既定は各`min(1.0, coreDur/8)`秒、短い動画では
    `coreDur/4`秒まで縮める)はハードコードで、UIからは調整できない。最後に
    `color=c=black`+`anullsrc`で生成した無音の黒み2秒分(`blackHoldSec`)を
    `outro_faded.mp4`の後ろに`-c copy`で結合する(タイトルカードの結合と同じ
    concatデマクサ方式)。
  - `PerceptualHash.swift` — 知覚ハッシュ(dHash、9x8グレースケール縮小+隣接ピクセル比較で
    64bit化)としきい値`enum MatchLevel`(exact/strict/normal/loose)。`SimilarityIndex`
    (誤配置修正の類似写真フォールバック)と`VideoDupViewModel`(動画重複)の両方から使う
    共通実装(元は削除済みの旧`DupPhotosViewModel`内に private であったものをCoreへ
    移動したもの)。`SimilarityIndex`/`VideoDupViewModel`ともdHashのハミング距離で
    比較するため、`MatchLevel.exact`(距離0)は「見た目が完全一致」を意味し、バイト単位の
    一致ではない点に注意。
  - `FaceFocusedFeaturePrint.swift` / `FeaturePrintIndex.swift` — 「日付推定」ペインの中核。
    dHash(`PerceptualHash`)は8x8グレースケールの知覚ハッシュでほぼ同一カット/バーストショット
    向け(見た目がわずかでも違うと距離が大きく離れる)なので、「別の日に撮った、同じ子どもが
    写っている写真」を探すには向かない。`FaceFocusedFeaturePrint.compute(for:)`はVisionの
    `VNGenerateImageFeaturePrintRequest`(オンデバイスの意味的画像特徴量、ネットワーク不要)を
    使い、さらに`VNDetectFaceRectanglesRequest`で最大の顔を検出できれば余白60%を付けて
    クロップしてから特徴量を計算する(背景や服装より「写っている人物の見た目」に寄せ、
    子どもの年齢の手がかりを拾いやすくするため)。顔が検出できない場合(後ろ姿・風景等)は
    画像全体で計算する。`FeaturePrintIndex`は`SimilarityIndex`と同じ「候補フォルダ配下の、
    `MediaDateResolver.fromSips`が非nilを返す(=EXIF撮影日を持つ)写真だけを集める」構築方法・
    並列化パターン(`[T?](repeating:nil)` + `concurrentPerform`)を踏襲するが、
    `closestMatch`(1件に決め打ち・自動確定用)ではなく`nearestMatches(for:k:)`で距離昇順の
    上位k件を返す点が違う(自動確定はせず、日付推定ペインで人が候補から選ぶ前提のため)。

    **初期実装でメモリ枯渇が発生した不具合**: 当初`FaceFocusedFeaturePrint.compute`は
    `CGImageSourceCreateImageAtIndex`でフル解像度のままデコードしていた(RAW/HEICは
    1枚あたり数十MB)。候補写真が数千枚規模になるとFeaturePrintIndex.build/
    DateEstimateViewModel.scanの`concurrentPerform`がワーカースレッド数ぶん同時に
    フル解像度画像をデコード+Vision推論するため、実機でメモリを使い果たした
    (「メモリがすぐ枯渇する」という報告で発覚)。対策は2つ: ①`PerceptualHash.dHash`と
    同じ`CGImageSourceCreateThumbnailAtIndex`(`kCGImageSourceThumbnailMaxPixelSize: 640`)
    へ切り替え、`autoreleasepool`で1枚ごとに解放する(顔検出・特徴量計算はこの解像度で
    十分機能する)。②`VideoDupViewModel`のffmpeg/ffprobe並列実行と同じ理由・同じ形
    (`DispatchSemaphore(value: min(4, activeProcessorCount))`)で、FeaturePrintIndex.build・
    DateEstimateViewModel.scanの両方の`concurrentPerform`にスロットリングを追加した
    (concurrentPerform自体のワーカースレッド数に任せず、Vision推論の同時実行数を絞る)。
  - `SimilarityIndex.swift` — 誤配置修正の「類似写真からEXIF日付を借用する」機能の中核。
    `SimilarityIndex.build(roots:extensions:threshold:...)`が候補フォルダ(例: 2020年・
    2021年)を再帰列挙し、`MediaDateResolver.fromSips(url)`が非nilを返す(=本物のTIFF/EXIF
    撮影日を持つ)ファイルだけを候補にする(推定日付は信用しない)。「`[T?](repeating:nil)` +
    `concurrentPerform` + 各iterationが自分のindexだけに
    書く」パターンで並列化(共有配列へのappendは並行安全ではないため)。`closestMatch(for:)`は
    しきい値以内でハミング距離最小の候補を返す(同距離は列挙順=先勝ちで決定的)。
    `LazySimilarityIndex`はビルドを実際に必要になるまで遅延するラッパー(候補年を設定して
    いてもmtimeフォールバックが発生しなければビルドコストがかからない。`MisplacedFixViewModel`
    が対象(年・月)をまたいで同じインスタンスを使い回すことでビルドは最大1回だけになる)。
  - `UnionFind.swift` — パスの半分圧縮つきUnion-Find(`VideoDupFinder`のフレームハッシュ
    クラスタリングで使う。元は削除済みの旧`DupPhotosViewModel`内にprivateであったものを
    Coreへ移動)。
  - `VideoDupFinder.swift` — 「動画重複」ペインの中核。`allVideoFiles(in:)`で対象フォルダ配下の
    動画を再帰列挙し、`collectStemGroups`は拡張子を除いたファイル名が同じもの同士でグループ化
    (軽量な下準備、ファイル名のみ)。ファイル名が違っても同じ動画を検知できるよう、
    `mergeCandidateGroups(files:durations:)`が同名グループと「長さ(秒)が`durationBucketSeconds`
    (既定1秒)単位で丸めて一致するグループ」を`UnionFind`で統合し、最終的な解析候補グループを
    作る(長さは呼び出し側=`VideoDupViewModel`が`H265Encoder.getDurationSec`で並列・進捗表示
    付きに事前取得し、`mergeCandidateGroups`自体は統合ロジックのみを担う純粋関数)。
    `analyze(_:)`で各候補のサイズ・コーデック(`H265Encoder.getVideoCodec`を再利用)・
    開始5秒以内のサンプル地点(既定1秒・4秒、`sampleSeconds`)のdHash(ffmpegで1フレームだけ
    一時ファイルに書き出し`PerceptualHash.dHash`にかける。`-ss`を`-i`より前に置く高速シークで、
    動画全体のデコードを避ける)を取得する。`isSameVideo`は両者に共通して抽出できたサンプル
    地点だけを比較し、1地点も比較できなければ「同じではない」とする(安全側に倒す —
    長さが偶然一致しただけの別動画をここで弾く)。`cluster(_:threshold:)`は候補グループ内を
    `UnionFind`でクラスタリングし、2本以上のクラスタだけを`VideoDupGroup`にする(3本以上が
    候補の場合にも対応)。`VideoDupGroup.keeper`はH.265を優先し(複数あればサイズ最大)、
    H.265が無ければ全体でサイズ最大を残す固定ルール(ユーザー選択式ではない)。
  - `RsyncSync.swift` — rsyncのdry-run差分パース・実同期・レポート生成。実削除を伴う
    ため呼び出し側(SyncViewModel)は必ず差分確認→ユーザー確認→実行の順を守ること。
  - `ShortClipFinder.swift` — 長さ解析・レポート/M3U生成。`play(_:)`はプレイリスト(.m3u)・
    単体動画ファイルどちらのURLも受け取れる共通の再生関数(iina/mpv/vlcのいずれかがあれば
    それで開き、無ければ`NSWorkspace.shared.open`でデフォルトアプリに委ねる)。
  - `ProcessRunner.swift` — 外部コマンドを非同期実行し標準出力/エラーを1行ずつ通知する
    共通ラッパー。`cancel()`でプロセス終了できる。

    **ファイルディスクリプタ枯渇バグ(2026-08-01)**: `SyncExec.run`/`ProcessRunner.run`は
    `process.run()`後、`Pipe()`の書き込み端(親側の複製、子プロセスにdupされた後は不要)を
    明示的に閉じておらず、ARCのdealloc任せにしていた。数千ファイル規模のフォルダを
    一括処理する処理(「エンコード」ペインでの`H265Encoder.analyze`/`processFile`の
    ffprobe呼び出し等)ではこれが1呼び出しあたり確実に蓄積し、OSのファイルディスクリプタ
    上限に達した時点で以降**すべて**のPipe/Process生成が壊れ、`ffprobeの出力が読めません`
    のようなエラーが最後まで延々と続く(実際に2545ファイル中1496件目あたりから発生を
    確認、`lsof -p <pid>`で経過時間に比例してfd数が線形に増え続けることをスクリプトで
    再現・確認した)。修正は`process.run()`直後に`pipe.fileHandleForWriting.close()`
    (親側はもう使わない)、読み取り完了後に`pipe.fileHandleForReading.close()`を
    明示的に呼ぶこと。`HEICConverter.swift`(写真整理でのHEIC→JPG変換、`sips`呼び出し)にも
    同種の問題があり(しかも誰も読み取らない`Pipe()`をstdout/stderrに渡していたため、
    OSパイプバッファが満杯になった場合にデッドロックし得る潜在バグも併発していた)、
    出力自体を使わないため`Pipe()`ではなく`FileHandle.nullDevice`に直接捨てる形に変えた。
    `ToolLocator.swift`の`which`呼び出しは`resolve`のキャッシュにより実行回数がツール名の
    種類数(数個)に限られるため対象外(同じ書き込み端閉じ忘れはあるが実害が出るほどの
    呼び出し回数にならない)。
  - `JobRunner.swift` — アプリ全体で同時に1ジョブだけ実行するシングルトン。実行中は
    `ProcessInfo.beginActivity`でスリープを防止(caffeinate相当)。`title`/`detail`/
    `progress`は全ペイン共通(下部ステータスバー用)だが、ログ本文は`JobKind`
    (`.photos`/`.videos`/`.encode`/`.sync`/`.shortClips`/`.misplacedFix`)ごとに
    `logsByKind: [JobKind: [String]]`で分けて保持し、`run(kind:title:_:)`呼び出し時に
    その`kind`のログだけをリセットする。各ペインの`JobLogSectionView(kind:)`は
    自分の`kind`のログしか表示しないため、他タブの実行結果は混ざらない
    (「同期」ペインは差分確認・同期実行の2アクションを両方`.sync`に紐付け、
    同じログセクションを共有する)。ログは次に同じ`kind`のジョブが始まるまで
    保持される(完了後もログが残る)。ログ本文は`logsByKind[kind]`が3000行を超えると
    古い方から1000行`removeFirst`する(無制限に溜め続けるとメモリを圧迫するため)。
    数千ファイル規模の一括処理(「エンコード」ペインで9000件超のフォルダ等)では
    1ファイルあたり2〜3行ログが出るため序盤のログはジョブ完了時には既に破棄されており、
    「コピー」ボタンで取れる内容は末尾の数千行だけになる(実際にこれが原因で、序盤に
    起きたエラーがユーザーからは見えなくなる不具合として報告された)。この上限自体は
    変えず(表示パフォーマンスとメモリのため)、代わりに`H265Encoder.EncodeResult`に
    `errorDetails: [String]`(「ファイル名: 理由」の一覧、`.failed`/`.errorSkipped`の
    たびに`add(_:sizeMB:detail:)`が積む)を持たせ、`run(config:...)`と
    `VideosViewModel`の動画整理後エンコードサマリーの両方で、末尾の`=== エンコード結果 ===`
    ブロックに「失敗/エラーの詳細:」として全件書き出す(件数だけでなくファイル名・理由も)。
    サマリーは常にログの一番最後に追記されるため、ジョブがどれだけ大きくてもこの部分だけは
    切り捨てられない — 「何件失敗したか」だけでなく「どのファイルがなぜ失敗したか」を
    確実に確認できる場所を保証する狙い。実際にこの仕組みで原因を辿ったところ、
    9332件中2件だけ「コーデック取得失敗」になった事例があり、該当ファイルを個別に
    ffprobeで確認すると正常なhevcだった(=ファイル自体は無問題、数千件連続でffprobeを
    呼ぶ間にディスクI/Oが一瞬詰まった等の一過性の失敗と判断)。そのため
    `probeVideoCodec`は初回失敗時に0.3秒待って1回だけ再試行する
    (`probeVideoCodecOnce`に本体を切り出し、`probeVideoCodec`がリトライの皮を被せる形)。
    2回とも失敗する場合(ffprobe自体が無い等の恒常的な問題)はこれまで通り`.failure`を返す。
  - `ToolLocator.swift` — 外部コマンドの実体パス解決 + キャッシュ。キャッシュ辞書への
    アクセスは`NSLock`で保護する(複数スレッドから同時に`resolve`を呼ぶと初回は
    同じキーへの同時書き込みが起きうるため。`VideoDupFinder`が`concurrentPerform`で
    `resolve("ffmpeg")`/`resolve("ffprobe")`を並列に呼んで初めてこの競合が顕在化し、
    Dictionary破損によるクラッシュを起こしたことがある — 外部コマンドを並列に呼ぶ
    機能を追加するときは、ここが排他制御されていることに注意)。
  - `ByteFmt.swift` — バイト数の文字列整形(旧cleanmac由来)。
  - `FileScanner.swift` — サイズ計算・ディレクトリ直下の列挙(旧cleanmac由来。
    `CacheScanner`/`AppScanner`の両方が使う)。
  - `FileRemover.swift` — ゴミ箱への移動 + 権限エラー時のFinder経由(AppleScript)再試行
    (旧cleanmac由来。`CacheViewModel`/`AppViewModel`の両方が使う)。
  - `CacheScanner.swift` — `CleanupItem`/`CacheCategory`モデル + `~/Library/Caches`等
    ユーザー領域のキャッシュ・ログ・ゴミ箱・Xcode関連のスキャン(旧cleanmac由来)。
  - `AppScanner.swift` — `AppInfo`/`InstalledApp`モデル + `/Applications`のアプリ列挙・
    残存ファイル探索(旧cleanmac由来)。
  - `StorageAnalyzer.swift` — 「ストレージ分析」ペイン(新規、2026-08-11)の中核。
    `CacheScanner`(固定パス・浅い列挙)と違い、任意フォルダを`FileManager.enumerator`で
    1回だけ深く再帰し、①直下フォルダ別の合計サイズ(内訳表示用)と②100MB
    (`largeFileThresholdBytes`)以上のファイル一覧(削除候補用)を同時に集計する
    (2回に分けて走査すると大きいフォルダでコストが倍になるため)。走査対象の直下が
    `.`始まり(`.Trash`含む)の場合は`enumerator.skipDescendants()`で配下ごとスキャン対象外
    にする(クリーンペインと役割が重ならないようにする狙いもある)。

    **OneDriveファイルの二重カウント(2026-08-11)**: ホームディレクトリ全体をスキャンすると、
    同じOneDriveファイルが`~/Library/CloudStorage/OneDrive-Personal/...`(ユーザーに見える
    FileProvider経由の表示パス)と`~/Library/Group Containers/UBF8T346G9.OneDriveStandaloneSuite/
    OneDrive.noindex/OneDrive/...`(OneDrive拡張の内部管理領域、`Group Containers`はアプリの
    サンドボックス共有領域)の2箇所に別inodeで現れ、「大きいファイル」一覧に同一ファイルが
    2件出る・合計サイズが二重計上される不具合が実機で発覚した(`stat`で確認: inodeは異なるが
    論理サイズは同一、実使用ブロック数はディスク逼迫時どちらも同時に0になる=同じ実体を
    参照していると考えられる)。`excludedAbsolutePaths`(`~/Library/Group Containers`)を
    新設し、走査中にこのパス配下に入ったら`skipDescendants()`で丸ごとスキップするように
    修正した。他のクラウドストレージ(iCloud Drive/Google Drive等)でも同様の内部管理領域が
    `Group Containers`配下に作られることがあるため、OneDrive専用の対処にはせず
    パス自体を汎用に除外している。`~/Library/CloudStorage/...`(ユーザーに見える側)は
    除外しない — バックアップ済みのOneDrive同期ファイルを整理したい、という正当な
    ユースケースがあるため。ただしこちら経由でファイルをゴミ箱に移動すると実際に
    クラウド側からも削除される(ローカルキャッシュの解放とは違う)ため、`StorageAnalysisView`
    のヘッダーに常時警告文を出している。
- `ViewModels/RenamerViewModel.swift` — 旧renamerの`AppState`をそのまま移植した
  `ObservableObject`。ファイル一覧・ルール・プリセットCRUD・Undoスタック・
  メタデータキャッシュ・プレビュー生成(衝突/重複検出込み)・実際のリネーム実行を持つ。
  `JobRunner`は使わない(リネームは同期的で一瞬なため)。`includeSubfolderFiles`
  (既定OFF、旧renamerには無かった追加設定)をONにすると、`addURLs`はフォルダを
  追加した際にそのフォルダ自体を1件のアイテムとして加える代わりに、
  `filesRecursively(under:)`で配下のファイルをサブフォルダも含めて再帰列挙し
  フラットに追加する(ディレクトリ自体はリスト化しない)。ファイル選択パネル・
  ドラッグ&ドロップの両方の入り口(`addURLs`)で共通に効く。
- `Views/RenamerView.swift` — 「リネーム」ペイン。ルール一覧(`RulesPane`)+
  ドラッグ&ドロップ対応のファイルリスト(`FilesPane`、ライブプレビュー付き)の
  2ペイン構成。他ペインと違い`JobLogSectionView`を使わず、旧renamerアプリと同じ
  即時プレビュー+実行ボタンのみのUI。「リネーム実行」ボタンは`vm.performRename()`を
  呼ぶ前に`JobRunner.shared.isRunning`を確認し、他のジョブ実行中なら
  (`JobRunner`は使わないこのペイン自身は待たされないが、写真整理等の裏の処理と
  ファイル操作が競合しうるため)実行せず既存の`errorMessage`アラートで警告する。
- `ViewModels/OneDriveSyncViewModel.swift` + `Views/OneDriveSyncView.swift` — 「OneDrive同期」
  ペイン(2026-08-10、`JobKind.oneDriveSync`)。汎用の「同期」ペイン(`SyncViewModel`/
  `SyncView`、2つのHDD間の丸ごとミラーリング)とは別物 — OneDrive直下には同期不要な
  巨大フォルダ(動画アーカイブ等)も混在するため丸ごと同期には向かず、ソース
  (既定`~/Library/CloudStorage/OneDrive-Personal`)直下のサブフォルダをチェックボックスで
  選び、選んだサブフォルダだけを`RsyncSync.checkDiff`/`sync`に1つずつかける
  (`MisplacedFixViewModel`のTarget配列+ループと同じパターン)。既定の選択は
  全サブフォルダ(選択を一度も保存していない場合のみ`scanSubfolders()`が適用、
  `UserDefaults`の`oneDriveSync.selected`に保存後は空集合になっていてもそちらを
  優先する)。保存済みの選択がある場合、ルート変更時は`scanSubfolders()`が実在しない
  フォルダの選択を落とす。
  ターゲットの既定は`/Volumes/backup1/0_onedrive_backup`。差分確認→ユーザー確認→実行の
  順を守る点、ターゲット側の余分なファイルを削除する点は汎用「同期」ペインと同じ不変条件
  (下記「変更時の注意」)を共有する。`status(for:)`が`results`(直近の差分確認/同期結果)から
  フォルダ名で1件引く小さなヘルパーで、`Views/OneDriveSyncView.swift`のprivate
  `FolderRow`(チェックボックス+フォルダ名の行、差分確認前は素のリスト)がこれを使い、
  差分確認後は行の右側に追加/更新/削除の件数バッジ(`+N`/`↻N`/`-N`、色分け)を出す。
  差分ゼロのフォルダだけは3つの数字の代わりに緑チェック「同期済み」1つにまとめる方が
  見やすいため、`FolderRow`内で`hasChanges`により出し分けている。以前は結果一覧を
  チェックリストとは別に(差分ありのみ/全件と変遷しつつ)重複表示していたが、行ごとの
  バッジに一本化して削除した(合計件数の表示と実行ボタンだけが下の結果ボックスに残る)。
  「同期を実行」(`confirmSync()`)は各フォルダの`RsyncSync.sync`が**exitCode 0で**成功する
  たびに、その場で`results`内の対象行を空の`SyncDiff()`(差分ゼロ)に書き換える — 同期が
  成功した時点でソース/ターゲットは一致しているはずなので、実際にdry-runを取り直さなくても
  「同期済み」マークをその場で(1フォルダ終わるごとに)反映できる。

  **一部ファイルだけ転送失敗するケース(2026-08-10)**: OneDriveのクラウド専用(未ダウンロード)
  ファイルは、rsyncがそのファイルを読もうとした瞬間にOneDrive側がダウンロードを始める。
  ダウンロードが間に合わないと`read errors mapping ... Operation timed out (60)`で
  そのファイルだけ転送失敗し(rsyncは1回リトライしてそれでも失敗すれば諦めて次のファイルへ
  進む)、rsync自体はexitCode 23(部分転送エラー)で終了する — フォルダ内の他のファイルは
  正常に転送済みだが、失敗したファイルだけソース/ターゲットが不一致のまま残る。当初
  `confirmSync()`は`RsyncSync.sync`の戻り値(終了コード)を`_ = try await ...`で捨てて
  無条件に「同期済み」表示にしていたため、この部分失敗があっても緑チェックが出てしまう
  不具合があった(実際に`photo/2025/07/0723/...jpeg`1枚だけタイムアウトした事例で発覚)。
  修正: 戻り値のexitCodeを見て、0のときだけ「同期済み」に書き換え、非0のときは`results`の
  該当行を変更せず(差分あり表示のまま残す)、`⚠️ <folder>: 一部ファイルを転送できませんでした`
  という警告をログに出す。ループ自体は中断せず次のフォルダに進み、失敗したフォルダ名は
  ループ終了後に`=== 転送できなかったフォルダ: ... ===`としてまとめて出す。汎用の「同期」
  ペイン(`SyncViewModel.confirmSync`)にも同じ「戻り値を捨てている」箇所が残っているが、
  そちらはこの「同期済み」自動マーキング機能自体を持たないため実害は薄く、
  未修正のままになっている。

  **差分の詳細ログ(2026-08-10)**: `RsyncSync.checkDiff`は元々、追加/更新/削除の各行を
  `SyncDiff.addedLines`/`deletedLines`(更新行は件数のみでリストは持たなかった)に集めて
  いたが、呼び出し側(`checkDiff()`)はその中身をログに出さず件数だけを出していたため、
  「どのファイルが」「なぜ」差分扱いになったのか確認するには「レポートを保存」で
  ファイルに書き出すしかなかった。`SyncDiff`に`modifiedLines: [String]`を追加して更新行も
  保持するようにし、`checkDiff()`が差分確認のたびに各フォルダの追加(`+ path`)/更新
  (`~ path  (理由)`)/削除(`- path`)を1行ずつジョブログへ出すよう変更した。「理由」は
  `RsyncSync.changeReason(from:)`(新設、`extractPath(from:)`と合わせて`private`から
  昇格)がitemize-changesの11文字のフラグ部分(`>f..t......`等)をパースし、'.'/' '以外の
  属性文字を日本語ラベル(サイズ/更新日時/内容 等)に変換する。このアプリの同期は`-c`
  (チェックサム比較)を使わないため、実運用で見るのはほぼ's'(サイズ)と't'(更新日時)のみ。
  OneDriveは中身が同じでもmtimeだけズレることがあり、その場合`理由`が「更新日時変更」だけに
  なるため、実質無害な差分かどうかがログから判別できる。

  **`--size-only`オプション(2026-08-10)**: 上記のmtimeドリフトが実際に頻発したため、
  「更新日時は考慮しない(サイズのみで比較)」トグル(`sizeOnly`、既定OFF、
  `UserDefaults`の`oneDriveSync.sizeOnly`に永続化)を追加した。ONの間は`checkDiff()`/
  `confirmSync()`の両方が`RsyncSync.checkDiff`/`sync`に`sizeOnly: true`を渡し、
  `baseArgs`が`--size-only`をrsyncへ渡す(サイズが同じなら更新日時に関わらず「変更なし」
  扱いになる — 中身は同じでサイズも同じだが1バイト単位で内容だけ変わっている、という
  極端なケースは理論上見逃すが、既定のサイズ+mtime比較でも中身までは見ていない点は同じで、
  このアプリは元々`-c`チェックサム比較を採用していないため実質的なトレードオフの上乗せは
  小さいと判断した)。`RsyncSync.checkDiff`/`sync`とも`sizeOnly`はデフォルト`false`の
  追加引数のため、汎用の「同期」ペイン(`SyncViewModel`)の既存呼び出しはこの引数を渡さず
  今まで通り動く(影響なし)。トグルを変更すると`results`をクリアする(既存の差分表示は
  古い比較条件のものなので、比較方法が変わったら差分を確認し直させるため)。

  **Unicode正規化(NFC/NFD)違いによる誤検出と実削除の危険(2026-08-10)**: 「名探偵コナン」
  フォルダの同期で、ソース(OneDrive)とターゲット(外付けexFAT HDD)の合計サイズが同じなのに
  111〜112件が「削除」として検出される不具合が発覚した。原因はファイル名のUnicode正規化
  形式の違い: OneDriveは常にNFC(結合済み、例: `ゼ`が1コードポイント)でファイル名を返すが、
  このexFATボリュームはmacOSが書き込み時に自動でNFD(分解形、濁点/半濁点付きの仮名が
  基底文字+結合文字に分かれる)へ正規化して格納する。見た目もFinder上の表示も同一文字列
  だが、rsyncはバイト単位でファイル名を比較するため別ファイル扱いになっていた
  (`unicodedata.normalize("NFC", ...)`で正規化して両ディレクトリを突き合わせたところ
  差分0件、実際には1件も欠落していないことをPythonスクリプトで確認した)。
  対象ファイルをNFCへ明示的にリネームしても、この自動正規化により**リネーム直後に
  OS側がNFDへ戻してしまう**ため恒久的には直らない(実機で確認済み)。rsyncの`--iconv`
  オプション(本来はHFS+/exFAT系のNFD問題向けに用意されている)も試したが、送受信とも
  同一ホスト上のローカルパス同士(リモート接続なし)の転送ではワイヤプロトコル上の
  iconv変換が働かず効果がなかった(実機で確認済み)。

  これは表示上の誤検出であるだけでなく、**「同期を実行」を押すと実際にこれらのファイルが
  `--delete`で削除される実害のあるバグ**だった(rsyncの通常の名前ベース比較では、
  ターゲット側のNFD名エントリは「ソースに存在しない」と判定されるため)。そのため
  `RsyncSync.normalizationMismatchExcludes(source:target:)`を新設し、ソース/ターゲット
  双方を`FileManager.enumerator`で直接列挙(`relativePaths(under:)`、正規化せず生のまま)、
  `String.precomposedStringWithCanonicalMapping`(Foundation標準のNFC正規化)で比較して
  「相手側にNFC正規化後は存在するが、生のバイト表現では一致しない」相対パスを検出する。
  戻り値には検出パスのNFC形・生のバイト表現の両方を含める(rsyncの`--exclude`にどちらの
  形でマッチさせる必要があるか事前には分からないため)。`checkDiff()`/`sync()`の両方が
  これを`baseArgs`の`extraExcludes`(`--exclude=/<path>`、転送ルートからの相対パスとして
  アンカー)として渡すため、**差分確認と実同期の両方**でこれらのファイルが一貫して
  比較・転送・削除の対象から除外される(表示だけを誤魔化して実処理は素通しになる、
  という不整合を避けるため、判定ロジックを両関数で共有する設計にした)。除外件数が
  あれば`progress`経由でログに「※ファイル名のUnicode正規化違い(NFC/NFD)によりN件を
  比較対象/同期対象から除外しました」と出す。汎用の「同期」ペイン(`SyncViewModel`)は
  通常exFAT同士(双方とも同じくNFDに正規化される)の組み合わせのため、この関数は
  「相手にもNFC正規化後は存在する」という条件を満たすペアが実質発生せず無害な
  no-opになる — ソース側がクラウドストレージ(OneDrive)等、ターゲットと異なる
  正規化形を返す組み合わせで初めて効果を持つ。トレードオフとして、正規化違いとして
  除外されたファイルは今後**内容が実際に変わっても検知されない**(パスの正規化一致だけを
  見ており中身は比較しないため)が、`checkDiff()`/`sync()`のたびに`normalizationMismatchExcludes`
  を再計算するため、次回そのファイルの正規化違いが解消されていれば(例えばターゲット側を
  別の方法で完全に上書きし直した場合)自動的に除外対象から外れる。

  **上記の初回実装が効いていなかった不具合(2026-08-11)**: ビルド・インストール後も
  `conan`フォルダの誤検出(111件の削除)が消えなかった。原因はSwiftの`String`の`==`/`!=`が
  Unicode**正規化を考慮した等価性比較**(canonical equivalence)を行うことで、NFCとNFDの
  文字列はバイト列が異なっていても`==`で真(等しい)と判定される。そのため
  `normalizationMismatchExcludes`内の`raw != nfc`(「このファイル名は正規化すると
  変わるか?」を調べるための自己比較のつもりだった)が常に`false`になり、除外候補が
  1件も見つからず、実質何もしないno-opになっていた(`swift`コマンドでGUIを起動せず
  単体のSwiftスクリプトとして同じロジックを実行し、`excludes count: 0`として再現・特定した)。
  対して`FileManager.enumerator`が返す生のパス自体(`relativePaths`)は正しく実際の
  オンディスクのバイト列を保持していた(同じスクリプトで検証: ソース側は64バイト=NFC、
  ターゲット側は67バイト=NFDと、Pythonでの検証結果と一致)ため、`FileManager`側の挙動は
  無罪だった。修正は`bytesEqual(_:_:)`(`Array(a.utf8) == Array(b.utf8)`)を新設し、
  `raw != nfc`を`!bytesEqual(raw, nfc)`に置き換えるだけ(`sourceNFCSet`/`targetNFCSet`への
  `.contains`チェック側はSwiftのCanonical equivalenceベースの比較のままで問題ない —
  そちらは「正規化後の形が相手に存在するか」を調べたいだけなので、むしろ好都合)。
  同じ検証用Swiftスクリプトで修正後は`excludes count: 112`となることを確認してから
  ビルド・インストールした。

  **フォルダ合計サイズ・ファイル数・全体の状況テーブル(2026-08-11)**: rsyncの差分検出結果
  (追加/更新/削除の件数)だけでなく、ソース/ターゲット双方のフォルダ合計サイズ・ファイル数も
  並べて表示し、目視でも「だいたい同じ量になっているか」を確認できるようにした。
  `FileScanner.sizeAndCount(of:)`(新設、既存の`size(of:)`はこれの`.size`だけを返す薄い
  ラッパーに変更)がディレクトリを1回走査してサイズと件数をまとめて返す(個別に2回
  走査するより大きいフォルダでコストを半減できる)。`FolderDiffResult`に
  `sourceSizeBytes`/`targetSizeBytes`/`sourceFileCount`/`targetFileCount`(既定0)を追加し、
  `checkDiff()`のループ内で各フォルダの差分検出後に`Self.folderStats(_:)`
  (`FileScanner.sizeAndCount(of:)`を`nonisolated` + `Task.detached`でMainActorから
  明示的に外して呼ぶラッパー、`async let`でソース/ターゲットを並列に実測)を呼んで実測し、
  ジョブログにも「サイズ: ソース=X(N件) / ターゲット=Y(M件)」を出す。数千ファイル規模の
  フォルダでは`sizeAndCount`自体が同期的に数秒かかりうるため、`nonisolated`にせず素朴に
  呼ぶと(このViewModelは`@MainActor`なので)JobRunnerのジョブクロージャ内でUIが
  ブロックされてしまう — `MisplacedFixViewModel`が`Task.detached`でCPU重い処理を
  MainActorから逃がしているのと同じ理由・同じパターン。`confirmSync()`側で同期成功後に
  「同期済み」へ書き換える際は、サイズ・件数を実測し直さず(大きいフォルダでまた数秒
  かかるため)直前にcheckDiff()で実測済みのソース側の値をそのまま両方に引き継ぐ
  (転送成功=内容が一致したはずという前提)。

  UIは「差分を確認」のたびに出す「全体の状況」テーブル(`Views/OneDriveSyncView.swift`の
  private `ResultsTable`、`Grid`)に一本化した。列は「フォルダ / ファイル数(ソース・
  ターゲット) / サイズ(ソース・ターゲット) / 状態」の6列で、ヘッダーを2段にして1段目で
  「ファイル数」「サイズ」をそれぞれ`gridCellColumns(2)`で2列分ずつ束ね、2段目で
  「ソース」「ターゲット」を並べる(2026-08-11、指標(サイズ/ファイル数)優先の見出しと
  ソース/ターゲット優先の見出しを試した末、最終的に「指標が親、ソース/ターゲットが子」
  かつ「ファイル数が先・サイズが後」の並びに落ち着いた — 具体的なレイアウト案を
  ユーザーが直接提示したものをそのまま反映した)。サイズ・ファイル数はソース側の
  セルとターゲット側の対応するセルが完全一致すれば「状態」列の「同期済み」ラベルと
  揃えて緑文字、1件でも違えばペア両方をオレンジ文字で目立たせる(前バージョンにあった
  一致/不一致アイコンは、列がソース/
  ターゲットで隣り合わなくなったため誤解を招きやすく、廃止して文字色だけに単純化した。
  NFC/NFD正規化違いで除外されたファイル分の数KB程度の差はexFATの割り当て単位差などで
  出ることがあるため、この不一致は「絶対に何かおかしい」ではなく「念のため目視で
  確認してほしい」というシグナルとして使う想定)。状態列は差分バッジ or
  「同期済み (HH:mm)」のまま。以前は対象サブフォルダのチェックリスト
  自体に差分バッジ・サイズを2行構成で埋め込んでいたが、「全体の状況を知りたい」という
  要望で情報を集約したテーブルに移した方が見やすいと判断し、チェックリスト側は
  チェックボックスのみのシンプルな`LazyVGrid`に戻した(旧`FolderRow`とその
  `status(for:)`ヘルパーは削除)。

  **`totalFileAllocatedSize`が0になる不具合(2026-08-11)**: 「全体の状況」テーブルで
  OneDrive側のサイズが実際よりはるかに小さく(ほぼ0)表示される不具合が発覚した。原因は
  `FileScanner.sizeAndCount`が`totalFileAllocatedSize`(ローカルディスク上の実使用量)を
  `fileSize`(論理サイズ)より優先していたこと — OneDriveのクラウド専用(未ダウンロード)
  ファイルは`totalFileAllocatedSize`がほぼ0になる(実機で確認: conanフォルダ329ファイル
  合計で`totalFileAllocatedSize`はわずか40KBだが`fileSize`は約101GB)。`sizeAndCount`/
  `fileSize`ヘルパーに`preferLogicalSize: Bool = false`を追加し(既定false、
  `CacheScanner`等の既存呼び出し元は「実際にディスクを解放できる量」を知りたいので
  現状維持)、OneDriveSyncViewModelの`folderStats`だけ`preferLogicalSize: true`で呼ぶ
  ように修正した。

  **変更ファイル一覧テーブル(2026-08-11)**: それまで追加/更新/削除の対象ファイルは
  ジョブログに`+`/`~`/`-`のプレフィックス付きプレーンテキストとしてしか出しておらず、
  色分けもフォルダごとの整理もされていなかった。`OneDriveSyncViewModel`に`FileChange`
  (folder/kind/path/reason)を追加し、`checkDiff()`が`diff.addedLines`/`modifiedLines`/
  `deletedLines`をログ出力するのと同時に構造化データとしても`fileChanges`に集める
  (`confirmSync()`が成功したフォルダの`results`エントリを更新する際、対応する
  `fileChanges`もフォルダ名で除去する)。`Views/OneDriveSyncView.swift`の新設private
  `FileChangesList`が「変更ファイル」セクションとして表示する — `List`+`Section`
  (フォルダごとにグループ化、`Section`ヘッダーに件数)を使い、緑(追加)/青(更新)/赤(削除)の
  色分けアイコンを行ごとに出す。数百〜数千件規模の差分(docsやphotoは実際にそれくらいの
  規模になりうる)でも軽く保つため、非遅延の`Grid`ではなく標準の`List`(行を遅延描画)を
  採用した。
- `ViewModels/CacheViewModel.swift` + `Views/CacheCleanerView.swift` — 「クリーン」
  ペイン(旧cleanmac由来、旧称「キャッシュ掃除」)。`CacheScanner`でスキャン→カテゴリ別に
  選択→`FileRemover`でゴミ箱へ移動。`JobRunner`は使わないが、「ゴミ箱へ移動」ボタンは
  確認ダイアログを出す前に`JobRunner.shared.isRunning`を確認し、他のジョブ実行中なら
  `errorMessage`アラートで警告する(下記5ペインも同じパターン)。`CacheScanner.scanAll()`
  は`~/Library/Caches`等の固定パス直下の列挙(`FileScanner.childItems`、非再帰)のみを行う。
  以前は「不要な隠しファイル」カテゴリ(ホームディレクトリ配下を再帰スキャンし`.DS_Store`と
  `._*`(AppleDouble)を検出、`FileScanner.hiddenJunkItems`)もあったが、不要になったため
  削除した(2026-08-10)。
- `ViewModels/StorageAnalysisViewModel.swift` + `Views/StorageAnalysisView.swift` —
  「ストレージ分析」ペイン(新規、2026-08-11)。「クリーン」が既知の固定パス(キャッシュ・
  ログ等)だけを対象にするのに対し、こちらは任意フォルダ(既定はホームディレクトリ全体、
  `FolderPickerRow`で変更可・`UserDefaults`の`storageAnalysis.root`に永続化)を対象に
  「今どこが容量を食っているか」を目視で判断しながら大きいファイルを個別に削除する用途。
  `StorageAnalyzer.scan(root:)`の結果を①内訳セクション(直下フォルダ別サイズ上位15件を
  横棒グラフ、`GeometryReader`で最大値に対する比率の幅を描画)②大きいファイル一覧
  セクション(100MB以上、`CleanupItem`と同様チェックボックス付き行+「すべて選択」
  トグル)の2つの`List`の`Section`として表示する。内訳・一覧行とも右クリックで
  「Finderで表示」(`NSWorkspace.shared.activateFileViewerSelecting`、`VideoDupView`と
  同じパターン)を出す。削除は`FileRemover.moveToTrash`→失敗分は
  `FileRemover.retryWithFinder`と、他ペインと同じ「スキャン→サイズ表示→選択→確認
  ダイアログ→ゴミ箱」の流れ。`JobRunner`は使わない(ホームディレクトリ全体の再帰
  スキャンは数十秒〜数分かかりうるが、既存の`VideoDupView`等と同様スピナー表示のみで
  段階的な進捗は出していない)。
- `ViewModels/AppViewModel.swift` + `Views/AppUninstallerView.swift` — 「アプリ削除」
  ペイン(旧cleanmac由来)。`AppScanner`でインストール済みアプリを列挙→選択したアプリ+
  残存ファイルを`FileRemover`でゴミ箱へ移動。`JobRunner`は使わない(実行前の
  busy確認は上記と同じ)。
- `ViewModels/VideoDupViewModel.swift` + `Views/VideoDupView.swift` — 「動画重複」ペイン。
  `isWorking`/`progress`/`enabledGroups`/`selection`等の状態を持ち、`JobRunner`は使わず
  busy確認は上記と同じパターン。判定ロジックは`Core/VideoDupFinder.swift`が担う。`scan()`は
  「①`allVideoFiles`で対象動画を全列挙し、concurrentPerformで並列`H265Encoder.getDurationSec`
  (ファイル名が違っても同じ動画を検知するための長さ確認、ここは全ファイルが対象) →
  ②`mergeCandidateGroups`が同名グループ+長さ一致グループを統合した候補を作る →
  ③候補だけをconcurrentPerformで並列`analyze`(サイズ・コーデック・フレームハッシュを算出、
  ここが最も重い) → ④`regroup()`が現在の`matchLevel`で`cluster`」という4段階。①・③は共通の
  `DispatchSemaphore`で同時実行数を`min(4, activeProcessorCount)`に絞っている(絞らないと
  候補が多いとき大量のffmpeg/ffprobeが同時に立ち上がりメモリ逼迫でクラッシュし得た)。
  進捗バーは①を0〜50%、③を50〜100%に割り当てる。`candidateGroups`(解析済み・
  ハッシュ算出済みの生データ)を保持しているので、`matchLevel`(既定`.strict`)を
  変えたときの`regroup()`はffmpeg/ffprobeを呼び直さず再クラスタリングのみで済む。
  グループごとのキープ判定はユーザー選択式ではなく`VideoDupGroup.keeper`の固定ルール
  (H.265優先、同条件ならサイズ最大)。`VideoDupCell`は開始1秒地点のフレームをサムネイル
  表示する(`VideoThumbLoader`、`AVAssetImageGenerator`でNSCacheに300MB分キャッシュ。
  ImageIOでは動画を読めないためAVFoundationを使う実装。ffmpegの別プロセス起動より軽量)。
  ファイル名・コーデック・サイズも表示し、キープ対象には「残す」バッジを出す。
- `ViewModels/MisplacedFixViewModel.swift` + `Views/MisplacedFixView.swift` — 「誤配置修正」
  ペイン。写真ライブラリのルート(年フォルダの親)を指定すると直下の年フォルダをチェック
  ボックス一覧で出す。「単位」セグメントで年単位/月単位を切り替えられ、月単位では選んだ
  年の中の月フォルダ(MM)を"YYYY-MM"キーでさらに選べる(`scanMonths()`)。選んだ年、または
  選んだ月(年フォルダ+`monthFilter`)ごとに`PhotoVerifier.run`を順番に呼ぶ
  (共通の`Target(label:yearRoot:monthFilter:)`にまとめてから1つのループで実行)。
  過去のMediaDateResolverフォールバック不具合(フォルダ名フォールバックが無関係な年+MMDD
  フォルダを組み合わせて誤った日付を捏造し、大量のファイルが同一フォルダに誤配置された)の
  復旧用に追加した、年単位・月単位で少しずつ実行するための一時的な修復ツール。
  fixモードでは「一度に修正する最大数」(既定50、`misplacedFix.maxFixCount`に永続化)を
  選んだ対象**全体**を通しての上限として適用し、上限に達した時点で残りの対象を未処理のまま
  打ち切る(`remainingBudget`を対象間で引き継ぐ)。実行前に`PhotoVerifier.estimateFileCount`
  で対象全体のファイル数を数え、`onFileProcessed`フックのたびに`JobRunner.Handle.setProgress`
  を呼んで全体進捗(%)を出す。「EXIFが無い写真を類似写真から推定」トグル
  (`similarityFallbackEnabled`、既定OFF)をONにすると、「候補年(参照元)」チェックボックス
  (`candidateYears`、fix対象の`selectedYears`/`selectedMonths`とは独立)と`MatchLevel`
  ピッカー(`similarityMatchLevel`、既定`.exact`= dHash距離0)が出る。`run()`内で
  `LazySimilarityIndex`を対象ループの前に1つだけ作り(ビルド自体は実際にmtime
  フォールバックが発生するまで遅延)、全対象の`PhotoVerifier.run`呼び出しに使い回す。
  候補年と実行対象の年が重なっている場合はログに警告を出す(ブロックはしない)。
  `JobRunner`は`.misplacedFix`を使う。
- `ViewModels/DateEstimateViewModel.swift` + `Views/DateEstimateView.swift` — 「日付推定」
  ペイン(新規)。誤配置修正の類似写真フォールバック(`SimilarityIndex`、dHashベース・
  mtimeフォールバック時に自動で日付を確定させる無言の救済策)とは別物で、こちらは
  `FeaturePrintIndex`(Vision特徴量ベース)で上位5件の候補を出し、人が見比べて選ぶ・確認する
  対話式のペイン。「対象フォルダ」(通常は誤配置修正が作る`Unknown/`)と「ライブラリルート」
  (年フォルダの親)を`FolderPickerRow`2つで指定し、`MisplacedFixViewModel.scanYears`と同じ
  パターンで拾った年フォルダを「候補年(参照元)」としてチェックボックスで選ぶ。`scan()`は
  `JobRunner.shared.run(kind: .dateEstimate, ...)`で①候補年から`FeaturePrintIndex.build`
  (EXIF付き写真だけを対象に特徴量を計算)→②対象フォルダの各写真の特徴量を計算し
  `nearestMatches(for:k:5)`で上位候補を求める、の2段階をバックグラウンド実行し、
  完了後`items: [DateEstimateItem]`(写真1枚+上位5候補)をセットする。結果一覧は候補年数・
  対象枚数が多いと時間がかかる点も含め`SimilarityIndex`と同じトレードオフ(Vision推論を
  1枚ずつ同期呼び出しするため)で、キャッシュは持たずスキャンのたびに毎回再構築する。
  各itemの候補チップ(サムネイル+日付+距離)をクリックすると`apply(_:date:)`が
  `PhotoVerifier.standardDest`+`PhotoVerifier.safeMove`(誤配置修正と共有、可視性を
  `internal`に変更済み)で即座にファイルを移動する — ゴミ箱行きの削除と違いライブラリ内の
  移動で後から戻せるため、確認ダイアログは挟まない(候補を目視で選ぶ操作自体が確認になっている
  という判断)。候補が合わなければ`DatePicker`で手動の日付を指定して同じ`apply`を呼ぶか、
  `skip(_:)`で何もせず一覧から外す。移動結果は`JobRunner`とは別の`applyLog: [LogLine]`
  (即時アクションのログのため)に積み、`LogConsoleView`で表示する。
- `ViewModels/VideoMakerViewModel.swift` + `Views/VideoMakerView.swift` — 「まとめ動画」
  ペイン(旧`omoide/`アプリ由来)。ロジックは`Core/VideoMaker.swift`が持つため、
  ViewModelはUI状態(対象フォルダ・除外選択・タイトル・BGMパス・尺/画質/トランジション等の
  詳細設定・UserDefaultsへのフォルダ/BGMパス永続化)と`VideoMakerConfig`の組み立てだけを
  持つ薄いラッパー(`RenamerViewModel`と違い、このペインは長時間の
  ffmpeg処理のため`JobRunner`を使う側 — Encode/ShortClips等と同じ構成)。フォルダを
  ピッカーで選ぶか`FolderPickerRow`のテキストフィールドを直接編集すると
  `refreshVideos()`(`onChange(of: folderPath)`経由)が動画一覧とタイトル初期値を
  再スキャンする。`JobRunner`は`.videoMaker`を使う。動画一覧は`allVideos`(フォルダ
  スキャン結果そのもの、除外・上限本数を反映しない)と`excludedVideos`(「選択した動画を
  除外」で除外された動画)を別々に保持し、`videos`(実際に使う一覧、Viewが表示・
  `VideoMakerConfig`に渡すのはこちら)は`applyFileLimits()`がその都度
  `allVideos.filter { !excludedVideos.contains($0) }`からランダム化・上限本数を
  適用して再計算する。以前は`videos`自身を直接`prefix`で削って上限をかけていたため、
  上限本数を後から増やしても一度削られた動画が戻らないバグがあった
  (`allVideos`という「上限を反映しない元データ」を持たなかったのが原因)。上限本数の
  `TextField`は値が変わるたびに`onChange`で`applyFileLimits()`を呼ぶ(以前は`onSubmit`
  のみでEnterを押すまで反映されなかった)。`estimatedTotalDisplay`(ViewModel)は
  `VideoMaker.estimateTotalSec(config:)`(本数・1本あたり秒数・トランジションの重なり・
  タイトルカード3秒・末尾の黒み2秒を`generate(config:)`と同じ計算式で見積もる、
  `titleCardDurationSec`/`blackHoldSec`という共有定数を使う)をUI表示用に文字列化した
  もので、フォームの下部に常時表示する。数値系の詳細設定のうち、音量以外
  (1動画あたり秒数/冒頭スキップ/上限ファイル数/画質(CRF)/トランジション)は
  `VideoMakerView.swift`末尾の`LabeledIntField`/`LabeledDoubleField`(private、
  Int版/Double版、テキストフィールドのみ)を使う。BGM音量/元音声音量の2つだけ
  `LabeledDoubleSlider`(スライダー+テキストフィールド)を使う — 当初は全項目を
  スライダー+フィールドにしていたが、スライダーが多すぎて見づらいという理由で
  音量系(0〜1の連続値で、スライダーでの直感的な調整に向く)以外は削除し
  フィールドのみに戻した経緯がある。`LabeledDoubleSlider`は`Slider`に`step:`を
  渡さない(`Slider(value:in:step:)`にすると、このmacOSバージョンのSwiftUIでは
  スライダー下に目盛り(tick marks)が自動描画されてしまうため、見た目を嫌って
  `step:`無しの`Slider(value:in:)`にした経緯がある)。「上限ファイル数」の
  `LabeledIntField`は範囲を持たない単純なテキストフィールドなので、
  `refreshVideos()`で`allVideos`を更新するたびに`maxFileCount`を
  `1...allVideos.count`へクランプする(未設定=0のときは全件を初期値にする)処理は
  「無効な値のまま保持しない」ための保険として残っている(以前はここが
  `Slider`の`range`の妥当性(`lowerBound < upperBound`)にも関わっていたが、
  フィールドのみになった今は表示上の制約ではなくデータの一貫性のためだけに存在する)。
  有効/無効を切り替えるチェックボックス(`useMaxFileCount`)は廃止済み — フィールドを
  最初から常時表示し、`totalScannedCount`(=読み込んだ全本数)と同じ値にすれば実質
  「上限なし」になるようにした。`applyFileLimits()`側も`maxFileCount > 0`のときは
  常に上限を適用する(トグルの分岐がない)。

  クリップ長の指定方法はかつて「1動画あたり秒数」/「全体の尺」の2モード
  (`DurationMode`、セグメントピッカーで切り替え)があったが、「全体の尺」モードは廃止した
  (`VideoMakerConfig`/`VideoMaker.generate`/`estimateTotalSec`から`durationMode`/
  `totalSec`ごと削除、現在は`clipSec`のみ)。「全体の尺」は`totalSec / videos.count`で
  1本あたり秒数を逆算する仕様だったが、ディゾルブトランジション(`transDur = min(
  transitionSec, effectiveClipSec / 2)`)の重なり分は考慮せずに逆算するため、本数が多いと
  `transDur`が`effectiveClipSec / 2`のキャップに張り付き、重なりの合計が指定した「全体の尺」
  の半分近くにまで達することがあった(例: 30秒指定でも実際の予想合計時間が20秒になる、
  という問い合わせがあった)。「1本あたり秒数を指定する」方式だけならこの逆算が要らず
  誤解の余地がないため、モードごと削除する形で解消した。

  設定項目が増えて縦に長くなり見通しが悪くなったため、意味のまとまりごとに
  `VideoMakerView.swift`末尾の`TitleAndMusicSection`(タイトル文字列+BGMファイル選択)・
  `ClipSettingsSection`(1動画あたり秒数/上限ファイル数/ファイル再生の順序/冒頭スキップ/
  トランジション/画質(CRF))・`VolumeSettingsSection`(BGM音量/元音声音量)という3つの
  `private struct`(各`Text(...).font(.headline)`の見出し付き)に分割し、`Divider()`で
  区切って縦に並べている。いずれも`@ObservedObject var model: VideoMakerViewModel`を
  親の`@StateObject`から受け取るだけの薄いラッパー(状態は`VideoMakerViewModel`に
  一元化されたまま)。一度`TabView`でタブ切り替え式にした(当時の downloader の YouTube/Torrent タブ、
  mynetworthのメイン/週/月/…タブと同じパターンを踏襲)ことがあったが、「設定が常に見える
  ようにしたい」という要望でこの常時表示の縦並びに戻した — 新しく設定を追加するときは
  タブに隠さず、意味の近いセクションに`Divider()`区切りで追加する方針。

  **相反するパラメータのグレイアウト**: 意味を持たない・無視される組み合わせは、
  該当行を非表示にするのではなく`.disabled()`でグレイアウトする方針(値と操作自体は
  そのまま残し、「今は効かない」ことだけを示す)。
  - 「ファイル再生の順序」(旧「ランダムモード」トグル。`ファイル順`/`ランダム`の
    `enum PlayOrder`をセグメントピッカーで選ぶ方式に変更済み)と「トランジション」は
    `model.videos.count <= 1`(実際に使う動画が1本以下)のとき無効(並び替え・クリップ間の
    遷移が意味を持たないため)。
  - 「BGM 音量」は`model.musicPath.isEmpty`(BGMファイル未設定)のとき無効。
  - 「上限ファイル数」は`model.totalScannedCount <= 1`のとき無効。

  **自動作成**: 「まとめ動画を作成」ボタンの左に置いた「自動作成」ボタン(`wand.and.stars`
  アイコン、`.help()`でツールチップ説明)は、手動の詳細設定(上限ファイル数・再生順・
  1動画あたり秒数)を一切使わず、BGMの長さに合わせてクリップ秒数と使用する動画を
  自動で組み立てて生成する一発ボタン。有効条件は`canAutoGenerate`(除外・選択中を
  除いた対象動画が1本以上・BGMパスが設定済みかつ長さが取得できている・出力先が設定済み)。
  `generate()`/`autoGenerate()`はどちらも先に`private var isAutoMode`をセットしてから
  上書き確認(`showOverwriteConfirm`)の要否を見て`startGenerate()`を呼ぶ構成
  ―上書き確認ダイアログを挟んでも「自動」か「手動」かの情報を保持する必要があるため、
  このフラグに載せている(ダイアログのボタン自体は共通で`model.startGenerate()`を
  呼ぶだけ)。`startGenerate()`は`isAutoMode`に応じて`currentConfig`(手動、`videos`
  ―除外・上限・再生順を反映済みの一覧―を使う)と`buildAutoConfig()`(自動)の
  どちらを`VideoMaker.generate(config:)`に渡すか切り替える。
  `buildAutoConfig()`は`videos`(上限本数や再生順が反映済み)ではなく
  `allVideos.filter { !excludedVideos.contains($0) && !selectedVideos.contains($0) }`
  (除外設定と、リストで現在選択中の動画の両方を引き継いだプール)を母集団にする点に注意
  ― 上限本数・再生順は自動モードの選定ロジックそのものが代わりに担うため、手動設定を
  混ぜると本数の意図が二重になってしまう。`selectedVideos`(「選択した動画を除外」
  ボタンをまだ押していない、リスト上でハイライトしているだけの動画)も対象から
  外すのは「自動作成では選択したファイルを含めないでほしい」という要望に対応するため
  ― 明示的な除外操作を経ずとも、リストで選ぶだけで自動作成の対象から外せるようにした。
  この結果、全動画を選択/除外すると対象が0本になり得るため、`canAutoGenerate`は
  `allVideos.isEmpty`ではなく`allVideos.contains { !excludedVideos.contains($0) &&
  !selectedVideos.contains($0) }`で判定する(そうしないと対象0本のままボタンが有効に
  見え、押しても`buildAutoConfig()`が黙って`nil`を返すだけの分かりにくい状態になる)。
  クリップ秒数は`buildAutoClipDurations(targetMainDur:transitionSec:maxClips:)`が
  「2秒/3秒をランダムに選んでは、ディゾルブの重なりを差し引いた実効長を積算し、
  目標尺(`targetMainDur`)を超える手前で打ち切る」処理で決める。`targetMainDur`は
  BGMファイル自体の長さ(`musicDurationSec`、ループ後の尺ではない)からタイトルカード分
  (タイトル文字列が設定されていれば`titleCardDurationSec`)を引いたもの ― BGMは
  `generate(config:)`内でタイトルカードを含む`withTitle`区間全体に敷かれる
  (`preOutroDur`)ため、メインクリップ区間だけを対象にするにはタイトルカード分を
  差し引く必要がある。使える動画本数(`maxClips`)を超えて積み上げることはない
  (フォルダの動画が少ないとBGMの長さに届かないまま打ち切られる)。
  どの動画を使うかは`balancedSelection(from:count:)`が決める ―
  「ファイルの順番で選ぶが、最初のファイルばかりが選ばれないように」という要望に
  対応するため、ファイル順にソート済みのプールの先頭から単純に`count`本取るのではなく、
  `0...(pool.count-1)`の範囲を`count`等分した位置(`round(i * (pool.count-1) / (count-1))`)
  ごとに1本ずつ選ぶ ― 結果はファイル順(昇順)を保ったまま、フォルダ全体
  (先頭〜末尾)から均等にサンプリングされる。
- `ViewModels/DownloaderViewModel.swift` + `Views/DownloaderView.swift` — 「ダウンロード」
  ペイン(旧`mydownloader/`アプリの移植、上記「設計上の方針」参照)。他ペインの
  `XxxViewModel`と違い`DownloaderViewModel`は`.shared`シングルトン(`JobRunner.shared`と
  同じ理由)で、`DownloaderView`は`@StateObject`で受け取るのではなく
  `@StateObject private var manager = DownloaderViewModel.shared`という形でこの
  シングルトンを参照する(新規にインスタンス化しない)。`JobRunner`は使わず、
  busy確認(他ジョブ実行中の警告)の対象にもしていない — ダウンロードは既存の
  写真・動画ファイルを変更するジョブ群とは独立した処理のため。
- `ViewModels/` / `Views/`(上記を除く) — ペインごとに1組。共通コンポーネントは
  `Views/JobLogSectionView.swift`(実行ボタンの下に置く実行ログセクション。`kind: JobKind`
  を受け取り、そのタブ自身のタイトル/詳細/進捗/中止ボタン + `LogConsoleView`のみを表示。
  実行ボタンを持つ7ペイン全て ― 写真整理/動画整理/エンコード/同期/
  短い動画検索/誤配置修正/まとめ動画 ― の末尾に、それぞれ自分の`JobKind`を渡して埋め込む)、
  `Views/LogConsoleView.swift`(ログ表示、`JobLogSectionView`内でのみ使用)、
  `Views/FolderPickerRow.swift`(パス入力+選択)、`Views/StatusBarView.swift`
  (下部ステータスバー、タイトル/詳細/%/中止ボタンのみ。こちらはタブ横断でジョブが
  走っていることが分かるよう`kind`に関係なく表示する)。

## 変更時の注意

- 「同期」/「OneDrive同期」機能はターゲット側のファイルを削除する。UIから確認ダイアログを
  外したり、差分確認なしに実行できるようにしたりしない。
- `JobRunner`を使わない5ペイン(リネーム/クリーン/ストレージ分析/アプリ削除/動画重複)の実際に
  ファイルを変更するボタンは、実行前に`JobRunner.shared.isRunning`を確認し、他のジョブ
  (写真整理/動画整理/エンコード/同期/短い動画検索/誤配置修正のいずれか)が
  実行中なら、既存の`errorMessage`アラートで警告して処理を中断する(ボタン自体は
  disabledにしない — 「実行しようとしたら警告する」体験にするため。裏で走っている
  ジョブと同時にファイルを動かして競合しないようにするための保護)。新しく実行系の
  ボタンを追加する際はこのパターンを踏襲する。「短い動画検索」ペインの検索自体は
  `.shortClips`の`JobRunner`ジョブだが、検出結果へのゴミ箱移動(チェックボックスで選択→
  確認ダイアログ)は同期的な即時アクションなので同じ busy 確認パターンを踏襲している
  (`FileRemover.moveToTrash`→`retryWithFinder`、動画重複と同じ流れ)。
- 各機能は独立したView/ViewModelに保つ(utilities/のスクリプトが単体完結する方針を
  アプリ内でも踏襲)。ただし`MediaOrganizer`/`H265Encoder`のように、複数ペインで
  完全に同一のロジックを使う場合はCoreに1本化してよい(実際にそうしている)。
- GUIアプリを起動しての目視確認は禁止。検証は `swift build` / `./build_app.sh` の
  コンパイル確認まで(ルートCLAUDE.md参照)。
- 「リネーム」ペイン固有の不変条件(旧renamerから継承):
  - リネームは必ずプレビュー → 衝突チェック(赤色警告 + 実行ブロック) → 実行の順。
    衝突検出を迂回するパスを作らない。
  - 実行したリネームはUndoスタック(バッチ単位・複数回)と
    `~/Library/Application Support/MyOrganizer/Renamer/history.log` の両方に記録する。
  - ルールは拡張子を除いた名前部分に適用する(拡張子を触るのは「拡張子を変更」ルールのみ)。
- 「クリーン」/「アプリ削除」ペイン固有の不変条件(旧cleanmacから継承):
  - 削除は必ず`FileManager.trashItem`(ゴミ箱へ移動)。完全削除のコードを書かない。
  - 対象はユーザー領域のみ。`/System`や`/private/var`などシステム領域をスキャン・
    削除対象に加えない。
  - 実行フローは スキャン → サイズ表示 → 選択 → 確認ダイアログ の順を崩さない。
  - 一部フォルダはフルディスクアクセスが無いとスキャンできず、権限エラーでの
    ゴミ箱移動失敗はFinder経由(AppleScript、`NSAppleEventsUsageDescription`が必要)で
    再試行する。失敗は握りつぶさず結果に表示する。
