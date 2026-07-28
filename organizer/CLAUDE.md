# CLAUDE.md — Organizer

`utilities/` の写真・動画パイプライン用スクリプト6本のロジックをSwiftネイティブで
再実装し、旧`renamer/`アプリの一括リネーム機能、旧`cleanmac/`アプリのキャッシュ掃除・
アプリのアンインストール・重複写真検出機能も統合して、1つのGUIにまとめたmacOSアプリ。
**SwiftUI + SPM** 構成。リポジトリ全体の規約はルートの `CLAUDE.md` を参照。

## ビルド / デプロイ

```bash
swift run                        # 開発ビルド(ウィンドウ起動)
./build_app.sh                   # release ビルド → Organizer.app
./install.sh                     # ビルド → /Applications へインストール
```

- **バージョンは `Sources/Organizer/Main.swift` の `appVersion` が唯一の定義**。
  `build_app.sh` が Info.plist の `CFBundleShortVersionString` に反映する。

## 設計上の方針

- `utilities/` のスクリプトは**呼び出さない**。日付推定(EXIF/QuickTime→mdls→フォルダ名
  →ファイル名→mtimeの5段階フォールバック)・MD5重複判定・rsync差分パース等のロジックは
  すべてSwiftで独立に再実装している。`utilities/` 側を変更してもこのアプリには
  自動反映されないので、挙動を揃えたい場合は両方を手動で直す。
- 旧`renamer/`アプリ(単一ファイル`main.swift`・swiftc直接ビルド)はロジック・UIとも
  無変更でこのアプリに移植し、`renamer/`ディレクトリ自体は削除済み。データ保存先も
  `~/Library/Application Support/Renamer/` から `~/Library/Application Support/
  Organizer/Renamer/` に変更した(presets.json・history.log)。
- 旧`cleanmac/`アプリ(キャッシュ掃除・アプリのアンインストール・重複写真検出)も
  ロジック・UIとも無変更でこのアプリに移植し、`cleanmac/`ディレクトリ自体は削除済み。
  cleanmacは状態を持たない(プリセットや履歴の永続化なし)ため、データ移行は不要だった。
  唯一のクラス名変更は`DupPhotosEngine`→`DupPhotosViewModel`(他の`ViewModels/`との
  命名一貫性のため。`RenamerViewModel`が旧`AppState`から改名された前例と同じ扱い)。
- `ffmpeg` / `ffprobe` / `rsync` / `sips` / `mdls` は外部コマンドとしてそのまま呼ぶ
  （同梱しない）。`sips` / `mdls` はmacOS標準、`ffmpeg` / `ffprobe` / `rsync` は
  Homebrew前提（`Core/ToolLocator.swift` が `/opt/homebrew/bin` → `/usr/local/bin` →
  `/usr/bin` → `PATH` の順で解決）。

## 構成 (`Sources/Organizer/`)

- `Main.swift` — エントリポイント + `appVersion`。`WindowGroup`1本のみ(メイン画面)。
  実行状況・実行ログは別ウィンドウではなく各ペイン内に埋め込む方式(下記)。
- `ContentView.swift` — `NavigationSplitView` のサイドバー(10ペイン + 依存チェック)。
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
    QuickTime=ffprobe)だけ呼び出し側が渡す。
  - `H265Encoder.swift` — エンコード判定(skip/remux/encode)とffmpeg実行
    (`-progress pipe:1`で進捗%抽出)。1ファイル分の判定・実行は`processFile(_:label:...)`
    に切り出してあり、フォルダ一括の`run(config:...)`(「エンコード」ペイン用)と、
    動画整理の`afterMove`フック(移動直後の1ファイルだけ)の両方から呼ばれる
    (`encode_h265.py`と`backup-videos.sh`内の重複を統合した上の共通実装)。
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
  - `PerceptualHash.swift` — 知覚ハッシュ(dHash、9x8グレースケール縮小+隣接ピクセル比較で
    64bit化)としきい値`enum MatchLevel`(exact/strict/normal/loose)。`DupPhotosViewModel`
    (重複写真)と`SimilarityIndex`(誤配置修正の類似写真フォールバック)の両方から使う共通実装
    (元は`DupPhotosViewModel`内に private であったものをCoreへ移動)。`MatchLevel.exact`は
    重複写真パインではSHA-256バイト一致に特殊扱いされる(`threshold`は使われない)が、
    `SimilarityIndex`側は常にdHashのハミング距離で比較するため「完全一致」の意味が
    微妙に異なる(dHash距離0=見た目が完全一致、であってバイト一致ではない)点に注意。
  - `SimilarityIndex.swift` — 誤配置修正の「類似写真からEXIF日付を借用する」機能の中核。
    `SimilarityIndex.build(roots:extensions:threshold:...)`が候補フォルダ(例: 2020年・
    2021年)を再帰列挙し、`MediaDateResolver.fromSips(url)`が非nilを返す(=本物のTIFF/EXIF
    撮影日を持つ)ファイルだけを候補にする(推定日付は信用しない)。`DupPhotosViewModel.scan()`
    と同じ「`[T?](repeating:nil)` + `concurrentPerform` + 各iterationが自分のindexだけに
    書く」パターンで並列化(共有配列へのappendは並行安全ではないため)。`closestMatch(for:)`は
    しきい値以内でハミング距離最小の候補を返す(同距離は列挙順=先勝ちで決定的)。
    `LazySimilarityIndex`はビルドを実際に必要になるまで遅延するラッパー(候補年を設定して
    いてもmtimeフォールバックが発生しなければビルドコストがかからない。`MisplacedFixViewModel`
    が対象(年・月)をまたいで同じインスタンスを使い回すことでビルドは最大1回だけになる)。
  - `RsyncSync.swift` — rsyncのdry-run差分パース・実同期・レポート生成。実削除を伴う
    ため呼び出し側(SyncViewModel)は必ず差分確認→ユーザー確認→実行の順を守ること。
  - `ShortClipFinder.swift` — 長さ解析・レポート/M3U生成。
  - `ProcessRunner.swift` — 外部コマンドを非同期実行し標準出力/エラーを1行ずつ通知する
    共通ラッパー。`cancel()`でプロセス終了できる。
  - `JobRunner.swift` — アプリ全体で同時に1ジョブだけ実行するシングルトン。実行中は
    `ProcessInfo.beginActivity`でスリープを防止(caffeinate相当)。`title`/`detail`/
    `progress`は全ペイン共通(下部ステータスバー用)だが、ログ本文は`JobKind`
    (`.photos`/`.videos`/`.encode`/`.verify`/`.sync`/`.shortClips`)ごとに
    `logsByKind: [JobKind: [String]]`で分けて保持し、`run(kind:title:_:)`呼び出し時に
    その`kind`のログだけをリセットする。各ペインの`JobLogSectionView(kind:)`は
    自分の`kind`のログしか表示しないため、他タブの実行結果は混ざらない
    (「同期」ペインは差分確認・同期実行の2アクションを両方`.sync`に紐付け、
    同じログセクションを共有する)。ログは次に同じ`kind`のジョブが始まるまで
    保持される(完了後もログが残る)。
  - `ToolLocator.swift` — 外部コマンドの実体パス解決 + キャッシュ。
  - `ByteFmt.swift` — バイト数の文字列整形(旧cleanmac由来)。
  - `FileScanner.swift` — サイズ計算・ディレクトリ直下の列挙(旧cleanmac由来。
    `CacheScanner`/`AppScanner`の両方が使う)。
  - `FileRemover.swift` — ゴミ箱への移動 + 権限エラー時のFinder経由(AppleScript)再試行
    (旧cleanmac由来。`CacheViewModel`/`AppViewModel`の両方が使う)。
  - `CacheScanner.swift` — `CleanupItem`/`CacheCategory`モデル + `~/Library/Caches`等
    ユーザー領域のキャッシュ・ログ・ゴミ箱・Xcode関連のスキャン(旧cleanmac由来)。
  - `AppScanner.swift` — `AppInfo`/`InstalledApp`モデル + `/Applications`のアプリ列挙・
    残存ファイル探索(旧cleanmac由来)。
- `ViewModels/RenamerViewModel.swift` — 旧renamerの`AppState`をそのまま移植した
  `ObservableObject`。ファイル一覧・ルール・プリセットCRUD・Undoスタック・
  メタデータキャッシュ・プレビュー生成(衝突/重複検出込み)・実際のリネーム実行を持つ。
  `JobRunner`は使わない(リネームは同期的で一瞬なため)。
- `Views/RenamerView.swift` — 「リネーム」ペイン。ルール一覧(`RulesPane`)+
  ドラッグ&ドロップ対応のファイルリスト(`FilesPane`、ライブプレビュー付き)の
  2ペイン構成。他ペインと違い`JobLogSectionView`を使わず、旧renamerアプリと同じ
  即時プレビュー+実行ボタンのみのUI。「リネーム実行」ボタンは`vm.performRename()`を
  呼ぶ前に`JobRunner.shared.isRunning`を確認し、他のジョブ実行中なら
  (`JobRunner`は使わないこのペイン自身は待たされないが、写真整理等の裏の処理と
  ファイル操作が競合しうるため)実行せず既存の`errorMessage`アラートで警告する。
- `ViewModels/CacheViewModel.swift` + `Views/CacheCleanerView.swift` — 「キャッシュ掃除」
  ペイン(旧cleanmac由来)。`CacheScanner`でスキャン→カテゴリ別に選択→`FileRemover`で
  ゴミ箱へ移動。`JobRunner`は使わないが、「ゴミ箱へ移動」ボタンは確認ダイアログを出す前に
  `JobRunner.shared.isRunning`を確認し、他のジョブ実行中なら`errorMessage`アラートで警告する
  (下記3ペインも同じパターン)。
- `ViewModels/AppViewModel.swift` + `Views/AppUninstallerView.swift` — 「アプリ削除」
  ペイン(旧cleanmac由来)。`AppScanner`でインストール済みアプリを列挙→選択したアプリ+
  残存ファイルを`FileRemover`でゴミ箱へ移動。`JobRunner`は使わない(実行前の
  busy確認は上記と同じ)。
- `ViewModels/DupPhotosViewModel.swift` + `Views/DupPhotosView.swift` — 「重複写真」
  ペイン(旧cleanmac由来。クラス名は旧`DupPhotosEngine`から改名)。重複写真検出
  エンジン(サイズ→SHA-256の完全一致 + dHashの類似判定、マルチコア並列スキャン、
  Union-Findによるグループ化)・モデル(`Photo`/`DupGroup`/`KeepRule`)・
  サムネイルローダー(`ThumbLoader`)を単一ファイルに内包する(dHash自体と`MatchLevel`は
  `Core/PerceptualHash.swift`に共通化済み、`RenamerViewModel`と同様、
  単一ペイン専用の複雑なロジックはCoreに分離せずViewModel内に置く方針)。各グループの
  見出しにチェックボックス(`enabledGroups`)があり、外すとそのグループはkeepRuleによる
  自動選択の対象外になり個々の写真も手動選択できなくなる(誤検出したグループを丸ごと
  削除対象から除外するため)。「全グループ選択」/「全グループ解除」
  (`enableAllGroups()`/`disableAllGroups()`)で一括切り替えもできる。`maxDeletePerGroup`
  (既定3、`dupPhotos.maxDeletePerGroup`に永続化)は1グループあたり削除対象にできる枚数の
  上限で、`autoSelectIDs`はこの上限までしか自動選択せず、`toggle`も手動選択でこの上限を
  超えようとすると拒否する(「ゆるい」等の緩いマッチレベルで誤って大きくクラスタリング
  されたグループを一気に削除しないための安全策)。上限を超えるグループはUIに
  警告アイコンを出す。`JobRunner`は使わない(実行前のbusy確認は上記と同じ)。
  「写真」アプリの`.photoslibrary`内部は対象外(意図的)。
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
- `ViewModels/` / `Views/`(上記を除く) — ペインごとに1組。共通コンポーネントは
  `Views/JobLogSectionView.swift`(実行ボタンの下に置く実行ログセクション。`kind: JobKind`
  を受け取り、そのタブ自身のタイトル/詳細/進捗/中止ボタン + `LogConsoleView`のみを表示。
  実行ボタンを持つ6ペイン全て ― 写真整理/動画整理/エンコード/写真検証/同期/
  短い動画検索 ― の末尾に、それぞれ自分の`JobKind`を渡して埋め込む)、
  `Views/LogConsoleView.swift`(ログ表示、`JobLogSectionView`内でのみ使用)、
  `Views/FolderPickerRow.swift`(パス入力+選択)、`Views/StatusBarView.swift`
  (下部ステータスバー、タイトル/詳細/%/中止ボタンのみ。こちらはタブ横断でジョブが
  走っていることが分かるよう`kind`に関係なく表示する)。

## 変更時の注意

- 「同期」機能はターゲット側のファイルを削除する。UIから確認ダイアログを外したり、
  差分確認なしに実行できるようにしたりしない。
- `JobRunner`を使わない4ペイン(リネーム/キャッシュ掃除/アプリ削除/重複写真)の実際に
  ファイルを変更するボタンは、実行前に`JobRunner.shared.isRunning`を確認し、他のジョブ
  (写真整理/動画整理/エンコード/写真検証/同期/短い動画検索/誤配置修正のいずれか)が
  実行中なら、既存の`errorMessage`アラートで警告して処理を中断する(ボタン自体は
  disabledにしない — 「実行しようとしたら警告する」体験にするため。裏で走っている
  ジョブと同時にファイルを動かして競合しないようにするための保護)。新しく実行系の
  ボタンを追加する際はこのパターンを踏襲する。
- 各機能は独立したView/ViewModelに保つ(utilities/のスクリプトが単体完結する方針を
  アプリ内でも踏襲)。ただし`MediaOrganizer`/`H265Encoder`のように、複数ペインで
  完全に同一のロジックを使う場合はCoreに1本化してよい(実際にそうしている)。
- GUIアプリを起動しての目視確認は禁止。検証は `swift build` / `./build_app.sh` の
  コンパイル確認まで(ルートCLAUDE.md参照)。
- 「リネーム」ペイン固有の不変条件(旧renamerから継承):
  - リネームは必ずプレビュー → 衝突チェック(赤色警告 + 実行ブロック) → 実行の順。
    衝突検出を迂回するパスを作らない。
  - 実行したリネームはUndoスタック(バッチ単位・複数回)と
    `~/Library/Application Support/Organizer/Renamer/history.log` の両方に記録する。
  - ルールは拡張子を除いた名前部分に適用する(拡張子を触るのは「拡張子を変更」ルールのみ)。
- 「キャッシュ掃除」/「アプリ削除」/「重複写真」ペイン固有の不変条件(旧cleanmacから継承):
  - 削除は必ず`FileManager.trashItem`(ゴミ箱へ移動)。完全削除のコードを書かない。
  - 対象はユーザー領域のみ。`/System`や`/private/var`などシステム領域をスキャン・
    削除対象に加えない。
  - 実行フローは スキャン → サイズ表示 → 選択 → 確認ダイアログ の順を崩さない。
  - 一部フォルダはフルディスクアクセスが無いとスキャンできず、権限エラーでの
    ゴミ箱移動失敗はFinder経由(AppleScript、`NSAppleEventsUsageDescription`が必要)で
    再試行する。失敗は握りつぶさず結果に表示する。
