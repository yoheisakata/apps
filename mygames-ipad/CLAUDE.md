# CLAUDE.md — MyGames Pad(mygames-ipad/)

## Overview

MyGames(Mac版)の「ボードゲーム」タブだけを取り出したiPad版。エミュレータ機能
(ライブラリ/ROM/コントローラーの3タブ、libretroコアの`dlopen`前提)は
iOSのアプリサンドボックス上そのままでは成立しない(ROM取り込みUI・外部コア
読み込みが必要)ため、意図的に含めない — ユーザー指示「ROM機能以外を含めて」
どおり、ボードゲーム集のみを移植した。2026-09-07、ユーザー指示で
`pwa/cardgames/`(トランプゲーム)も追加した。

トランプの画面構成は何度か作り直している:
1. 当初はトップタブで「ボードゲーム」/「トランプ」を切り替える2画面構成。
2. 2026-09-08、ユーザー指示「同じページに、水平線で分けて」で、メニュー画面
   (`MenuView`)の上半分にボードゲームのアイコングリッド、区切り線、下半分に
   `CardGamesWebView`を常時表示する1画面構成に変更。
3. 2026-09-09、この常時表示方式を廃止。「My Mac (Designed for iPad)」実行時に
   `WKWebView`が`WebContentProcess`を起動できずエラーになる不具合(ユーザー報告
   「トランプゲームがいまだにランチャーページに出てこない」)が出た際、
   メニュー画面を開くたびに(=ボードゲームを選ぶだけのときも)`CardGamesWebView`
   が常にマウントされてWKWebViewの起動を試みていたことが無駄な失敗を増やして
   いたと判断し、根本的に構成を変更した: トランプを**ボードゲーム8種と全く
   同じ`LazyVGrid`内の9個目のアイコンタイル**にして(ユーザー指示「トランプも
   同じグループとして出して」)、タップしたときだけ`Router.screen`に新設した
   `.cardGames`ケースに切り替えて`CardGamesWebView`をフルスクリーンで
   マウントする、対局画面と同じ「選んでから読み込む」遅延ロード方式にした。
4. **2026-09-09、さらにユーザー指示「トランプの各ゲームをトップページに
   おいて」で、トランプの1個のアイコンをやめ、トランプの8ゲーム個別の
   アイコン(神経衰弱・ババ抜き・スピード・大富豪・７並べ・21・ポーカー・
   ブラックジャック)をそれぞれトップページに直接並べる形に変更した** —
   ボードゲーム8種+トランプ8種、合計16個が同じ`LazyVGrid`に並ぶ。各アイコンの
   絵柄・タイトルは`Shared.swift`の`CardGameEntry.all`(id/title/emblem、
   `index.html`側の`goSetup(id)`が受け取るidと1対1)にカタログ化してある。
   トランプの各アイコンをタップすると`Router.screen`が`.cardGames(id)`
   (idを伴う形に変更済み)になり、`CardGamesWebView(gameID: id)`が
   `index.html`をロードしたあとに`goSetup('<id>')`を注入JSで呼び出して、
   ホーム画面を経由せずそのゲームのセットアップ画面へ直行する。
   `WKWebView`はユーザーが実際にトランプのどれかのゲームを開いたときにしか
   起動を試みなくなる(根本原因である「Designed for iPad」実行時のWebContent
   プロセス起動失敗そのものは直っていないので、その環境で開けばやはり
   失敗する — 実iPad/シミュレータで使うことを推奨、詳細は下記の`README.md`と
   の対応関係を参照)。`.cardGames`画面には`GameTopBar`相当の「その他のゲーム」
   ボタン(2026-09-09、ユーザー指示で「トップメニュー」から改名)を`ZStack`の
   オーバーレイとして手動で用意してある(WKWebView内の
   「← My Apps」リンクはJSで隠しているので、これが無いと後戻りできなくなる)。

**ランチャーの見た目(2026-09-08〜09、ユーザー指示)** — `BoardGamesRootView.swift`
の`LauncherTheme` enumがランチャー(トップメニュー)の配色を集約している。
アイコンタイルのグラデーション+発光シャドウは、`pwa/cardgames/index.html`の
8ゲーム分の配色定義(`.game.shinkei`〜`.game.bj`の`icon-wrap`)をそのまま
`LauncherTheme.iconGradients`に転記したもの(2026-09-08、ユーザー指示
「見た目を一貫させて、トランプ側に寄せる」)。ボードゲーム側は
`GameKind.allCases`の並び順(将棋→チェス→…→コネクトフォー、ちょうど8種)に
1対1で対応させて流用しているだけなので中身のゲームは違うが色の言語を揃えている
一方、トランプの各アイコンは`CardGameEntry.all`の並び順が最初から
`iconGradients`と同じ8ゲーム・同じ順序(神経衰弱→ババ抜き→…→ブラックジャック)
なので、こちらは**トランプ本家の実際の色そのもの**が使われる。背景は当初
トランプ側に合わせた深緑グラデーションだったが、2026-09-09にユーザー指示で
**黒**(`LauncherTheme.background = Color.black`)に変更した。共通のアイコン
タイル描画は`LauncherIconTile<Emblem: View>`(ジェネリックな絵柄ビューを受け取る)に
切り出してあり、`GameIconButton`(ボードゲーム用)とトランプのタイルの両方が
これを使う。ゲーム内(セットアップ画面・対局画面のサイドバー等)の配色は
この対象外(`Color(uiColor: .systemBackground)`など従来どおりシステム追従の
まま) — 統一したのはトップメニューのランチャー部分のみ。背景は黒→
2026-09-09にユーザー指示でセピア(暖色の焦げ茶、`LauncherTheme.background`)に
再変更した。`.cardGames`画面(トランプの各ゲームをフルスクリーン表示する
`ZStack`の背景)も同じ`LauncherTheme.background`を参照するようにして揃えてある。

## Architecture

`Sources/MyGamesPad/BoardGames/` はもともと `mygames/Sources/MyGames/BoardGames/`
のほぼそのままのコピーだった(7種の独立した`*Engine.swift`/`*Game.swift`/
`*Views.swift` + 共有の`Shared.swift`)。**2026-09-08、Mac版(`mygames/`)から
ボードゲームタブそのものが削除された**(ユーザー指示、`mygames/CLAUDE.md`参照) —
以降このiPad版が唯一の実装であり、「Mac版と同期を取る」という運用は終了した。
下記の「Mac版をコピー→sed置換」という追随手順の記述は、削除前に行われた過去の
移植作業の記録として残してある。

**麻雀は2026-09-08、ユーザー指示でこのアプリからも削除した**(4人前提でセットアップ
画面に馴染まず、`GameKind`から独立した特別扱いのコードが多かったため)。
`BoardGames/Mahjong{Engine,Game,Views}.swift`を削除し、`Shared.swift`の
`GameKind.mahjong`ケース、`MyGamesPadApp.swift`/`BoardGamesRootView.swift`の
`MahjongGameState`まわりを取り除いた。同時に、メニュー画面(`MenuView`)の
タイトル下の説明文(「アイコンをクリックすると…」)もユーザー指示で削除した —
タイトルのみのシンプルな見た目になっている。2026-09-08、続けてユーザー指示で
各ゲームアイコン下のサブタイトル文言(`GameKind.subtitle`をアイコングリッドに
表示していた`Text(kind.subtitle)`)も`BoardGamesRootView.swift`の
`GameIconButton`から削除した(`GameKind.subtitle`自体は各`*SetupView`が
参照するわけではなく単に未使用になっただけなので、値は残してある — 消しても
実害はないが将来また使うかもしれないため保持)。

**チェッカー・コネクトフォー追加(2026-09-08、ユーザー提案→承諾)** — 「iPadに
適した他のボードゲーム」の提案としてこちらから挙げた2種を、ユーザーの「いれてみて」
の一言で実装。**Mac版に対応する実装は存在しない**(Mac版のボードゲームタブ自体が
2026-09-08に削除済みなので、この2種は最初からiPad版オンリー)。他の6種と同じ
`Shared.swift`の`OpponentMode`/`RadioRow`/`GameSetupView`/`SaveSlotsBox`基盤に
乗せてあり、パターンは完全に共通:
- `CheckersGame.swift`(エンジン+AI+`CheckersGameState`) / `CheckersViews.swift` —
  8x8盤の暗いマス32個だけを使うアメリカンチェッカー。通常のコマは前方斜め1マス、
  キングは4方向1マス(国際ドラフツのような遠距離移動はしない簡易ルール)。
  **捕獲優先ルール**(飛び越えて取れる手があるときは必ずそれを選ばなければならない
  — `CheckersPosition.legalMoves(for:)`が捕獲手を最優先で返す)と、**連続捕獲**
  (1回取ったあと同じコマでさらに取れるならその場で続けて取る)を実装。
  `CheckersGameState.forcedContinuation`が連続捕獲中のコマのマスを保持し、
  `tapCell`はそのコマ以外の選択を拒否する。AIの連続捕獲は`finishAIMove`が
  自分自身を再帰的にスケジュールして自動で最後まで打ち切る。
- `ConnectFourGame.swift`(エンジン+AI+`ConnectFourGameState`) / `ConnectFourViews.swift` —
  7列×6段、列をタップすると重力で一番下の空きマスに落ちる(五目並べの
  `lineLength`/`cellScore`パターンを4目版に流用)。`ConnectFourColumnOverlay`が
  列全体を覆う透明なタップ領域で、どの段をタップしても同じ列に落ちる。内部の
  駒は共有`Disc`(黒/白)をそのまま使っているが、2026-09-09にユーザー指示
  「色がわかりづらいので、青と黄色にして」で盤上の見た目・表示名だけ青/黄に
  変更した(`Theme.connectFourBlue`/`connectFourYellow`、`Disc.connectFourName`
  というこのゲーム専用の表示名拡張 — 共有`Disc.name`(黒/白、オセロ等が使う)
  はそのまま)。
- 両方とも麻雀と違い2人対戦にも自然に馴染むゲームなので、他の6種と同じ
  「vs CPU/2人対戦」のセットアップ画面 + 画面回転ロックがそのまま適用される。

移植時の変更点(iOS向けの最小限の書き換えのみ):
- `import AppKit` を削除(`BoardGamesRootView.swift`/`ShogiViews.swift`。実際の
  AppKit APIは使っていない、importだけ残っていた)
- `Color(nsColor: .windowBackgroundColor)` → `Color(uiColor: .systemBackground)`
  (全ゲームの背景色、他は変更不要)
- `BoardGamesRootView.swift`の`.frame(minWidth: 880, minHeight: 660)`は
  `.frame(maxWidth: .infinity, maxHeight: .infinity)`に置き換える(2026-09-08、
  「縦にしても将棋盤が画面いっぱいにならない」で発覚・修正)。Mac版のこの行は
  リサイズ可能なウィンドウの最小サイズ指定として妥当だが、iPadのポートレート幅
  (多くの機種で880pt未満、iPad Pro 13"のみ超える)ではこれがそのまま画面より
  広い最小幅の強制になってしまい、将棋の2人対戦フルスクリーンレイアウトの
  `GeometryReader`が正しい画面サイズを取得できず盤が縮んで表示される。
  **Mac版をコピーするたびに必ず再適用すること**(忘れると2人対戦フルスクリーン
  表示が壊れて気づきにくい)。合わせて`ContentView.swift`のルート`VStack`にも
  `.frame(maxWidth: .infinity, maxHeight: .infinity)`を付けてあるので、
  こちらは新規ファイルなのでMac側との同期対象外(消さないこと)。

2人対戦モード追加(2026-09-07)は Mac版と全く同じロジック(`OpponentMode`・
`isHumanTurn`の一般化・`scheduleAIMove`のガード等、詳細は`mygames/CLAUDE.md`
参照)を丸ごとコピーしたもの — Mac版の`Sources/MyGames/BoardGames/`から
7ファイルすべてを上書きコピーしたあと、上記3つのiOS向け変換(`import AppKit`
削除・`nsColor`→`uiColor`・`BoardGamesRootView.swift`のframe修正)と、iOS 17の
`onChange(of:perform:)`非推奨対応(2パラメータ/0パラメータ形式への書き換え、
オセロの石めくりアニメーションのみ`{ _, newValue in }`、他は`{ }`)を機械的に
再適用する運用にしている。今後Mac版のボードゲームロジックを変更する際も、
この「Mac版をコピー→3つのsed置換→onChange書き換えを再適用」の手順を踏めば
大きな手作業なしに追随できる。
将棋の2人対戦フルスクリーンレイアウト(2026-09-08、`ShogiBoardView`/
`ShogiHandView`のサイズを可変化し`ShogiGameView`をAI対戦/2人対戦で別レイアウト
に分岐 — 詳細は`mygames/CLAUDE.md`参照)もこの手順でそのまま移植済み。
iPadは特に縦長画面での2人対戦(タブレットを挟んで向かい合う使い方)を想定
しているため、この変更の効果が最も出るのはこちらの版。

**全ゲームの2人対戦フルスクリーンレイアウト(2026-09-09、ユーザー指示
「すべてのゲームにおいて2人対戦の場合は盤だけの表示にしてほしい。参考は
将棋にして」)** — 将棋以外の7種(チェス・オセロ・囲碁・五目並べ・
ダイヤモンドゲーム・チェッカー・コネクトフォー)にも、将棋と全く同じ
`aiLayout`/`twoPlayerLayout`分岐パターンを適用した。各`<Game>GameView.body`は
`!hasStarted → SetupView`、`opponentMode == .human → twoPlayerLayout`、
それ以外 → `aiLayout`の3分岐(将棋と同じ形)。`twoPlayerLayout`は
`GeometryReader`で使える幅・高さから逆算してセル寸法を求め、盤をできるだけ
大きく表示する。各ゲームのBoardViewは元々セルサイズが固定`let`定数(または
Goのように盤面サイズだけに依存する内部計算)だったので、外から上書きできる
`var`パラメータに変えてある(チェス`cell`・オセロ`cell`・チェッカー`cell`は
そのまま`var`化、五目並べ`spacing`・コネクトフォー`spacing`も`var`化、
囲碁は盤サイズ9/13依存の計算に`spacingOverride: CGFloat?`を追加、ダイヤモンド
ゲームは六芒星型で単純な正方格子ではないため`unitX`/`unitY`/`margin`/コマの
`cellSize`をすべて比例させる`scale: CGFloat = 1.0`倍率パラメータを新設して
対応)。逆算式は盤の形ごとに異なる(例: 五目並べ・コネクトフォーは
`margin = spacing * 定数`の関係を使って一辺の長さから`spacing`を解く、
ダイヤモンドゲームは`scale=1`のときの盤の幅564pt・高さ548ptから比率で
`scale`を求める)。

**2026-09-09、さらにユーザー指示「二人モードの変更です。縦モードでも横モードでも
ゲーム終了ボタンだけを表示。盤にかぶらない場所に表示」で`twoPlayerLayout`を
簡素化** — それまでは盤の下に`ScrollView`でサイドバーの内容(対局/操作/コーチ/
駒ガイドなど)と`MoveRecordView`(棋譜/記録)をまるごと表示していたが、これを
やめて**盤(+将棋のみ持ち駒)と「ゲーム終了」ボタンだけ**にした。`ScrollView`も
撤去 — `GeometryReader`が計算するセル寸法にボタン用の固定バー
(`topBarHeight = 44`)ぶんを`reserved`に追加で差し引いてあるので、
どんな向き・画面サイズでもボタンが盤に重ならない。「ゲーム終了」ボタンは
盤の上に幅いっぱいの帯(`HStack`+`Spacer()`で右寄せ)として常時表示され、
`Shared.swift`の`EndGameOverlayButton`(角丸カプセル+`.ultraThinMaterial`、
タップで`game.goToSetup()`)がその中身。囲碁だけ例外で、この帯の左側に
「パス」ボタンも残してある — パスは設定ではなく2回連続で終局する正式な
着手の一つなので、2人対戦でも押せないと終局できなくなってしまうため
(囲碁の`GoSidebarView`の「操作」ボックスにも同じパスボタンがあるが、
そちらはAI対戦時のみ表示され、2人対戦では代わりにこの帯の方を使う)。
学習モード(将棋のみ)の悪手警告表示も2人対戦では出さないようにしてある
(`ShogiGame.swift`の`commitHumanMove`が`opponentMode == .ai`のときだけ
`Coach.warning`を呼ぶ、2026-09-09)。

**セットアップ画面 + スタートボタン(2026-09-08)** も現存する6種すべてに同じ手順で
移植済み(`RadioRow`/`GameSetupView`は`Shared.swift`、各`*SetupView`は各
`*Views.swift`内 — 詳細は`mygames/CLAUDE.md`参照)。最初の画面(セットアップ)
では盤面をレンダリングせず、「スタート」を押して`hasStarted`が`true`になって
初めて盤+持ち駒が現れる(`if !game.hasStarted { <Game>SetupView() } else { ... }`
という分岐なので、セットアップ画面の裏に盤が透けて見えることはない)。

## 画面回転ロック(vs CPU=横向き固定 / 2人対戦=縦向き固定)

2026-09-08、ユーザー指示「vs CPU の時は、横置きのみ」「2人対戦は縦向きのみに
固定」で追加。iPad版だけの機能(Mac版に画面の向きという概念はない)。

- **`Sources/MyGamesPad/Core/OrientationLock.swift`**(新規、Mac版との同期対象外) —
  `OrientationLock.mask`(現在許可する向き)と、それを返す
  `OrientationAppDelegate.application(_:supportedInterfaceOrientationsFor:)`。
  SwiftUIには画面回転を直接制御するAPIが無いため、`UIApplicationDelegate`を
  経由する必要がある。`MyGamesPadApp.swift`に
  `@UIApplicationDelegateAdaptor(OrientationAppDelegate.self)`で接続してある。
  `OrientationLock.apply(_:)`は`mask`を更新したうえで
  `UIWindowScene.requestGeometryUpdate(_:)`(iOS 16+)を呼び、即座に画面を
  回転させる。
- **呼び出し箇所はMac版と共有のソース側に`#if os(iOS)`で埋め込んである**
  (この型自体はiPad版にしか無いが、呼び出しコードはMac/iPad共通ファイル内):
  - `Shared.swift`の`Router.backToMenu()` — メニューに戻るたびロック解除
    (`.all`)。他タブへ移動しても向きが固定されたままにならないための保険。
  - 各`*GameState`の`goToSetup()` — セットアップ画面に戻るときもロック解除。
  - 各`*SetupView`の`onStart`クロージャ — `OrientationLock.apply(mode == .human
    ? .portrait : .landscape)`。スタートを押した瞬間、選んだモードに応じて
    ロックがかかる(セットアップ画面自体は`.all`のまま自由な向きで操作できる)。
- **Mac版をコピーするたびにこの`#if os(iOS)`ブロックは自動的についてくる**
  (Mac側のソースに直接書いてあるので、上記3つのsed置換とは別に手作業で
  足す必要はない)。ただし`Core/OrientationLock.swift`自体は新規ファイルなので
  Mac側に存在せず、初回作成時にコピーではなく手で書いた — 万一
  誤って削除した場合は再作成が必要。
- `project.yml`の`UISupportedInterfaceOrientations`がロックの上限になる —
  `OrientationLock.mask`はこの範囲の部分集合でなければならない(現状
  `.portrait`/`.landscape`ともに範囲内)。2026-09-09、Xcodeのビルド警告
  「Support for all orientations will soon be required」「UIRequiresFullScreen
  will soon be ignored」を受けて、4方向すべて(Portrait/PortraitUpsideDown/
  LandscapeLeft/LandscapeRight)を宣言し、`UIRequiresFullScreen: true`は削除した
  (Appleが今後iPadアプリに全方向対応とマルチタスク許可を必須化する方針のため)。
  ランタイムの`OrientationLock`自体は従来どおり機能する(この宣言はあくまで
  「アプリが対応しうる向きの上限」で、それを実行時にさらに絞り込むのが
  `supportedInterfaceOrientationsFor:`の役割)。ただし`UIRequiresFullScreen`を
  外したことで実iPad上ではSplit View/Slide Over/Stage Managerでの起動も
  理論上可能になった — 各ゲームの`GeometryReader`ベースのサイズ計算
  (将棋の`twoPlayerLayout`など)がフルスクリーン前提になっている箇所は、
  マルチタスクの小さいウィンドウでは未検証。
- **「My Mac (Designed for iPad)」実行時は無効化する(2026-09-08、ユーザー報告で
  発覚)** — Xcodeの実行先を実iPad/シミュレータではなくMacにすると、アプリは
  リサイズ可能なmacOSウィンドウとして動く。この状態で`requestGeometryUpdate`を
  呼ぶ(あるいは`supportedInterfaceOrientationsFor`が`.all`以外を返すだけでも)と、
  実機の回転という概念がないため、ウィンドウが中途半端な大きさへ縮んで
  左上にmacOSの信号機ボタン(赤黄緑)が出た「半分のウィンドウ」になる不具合が
  出た。`OrientationLock.apply(_:)`の先頭で`ProcessInfo.processInfo.isiOSAppOnMac`
  (と念のため`isMacCatalystApp`)を見て、真なら`mask`の更新も
  `requestGeometryUpdate`の呼び出しも両方スキップするようにして回避した — 実iPad/
  シミュレータでは常にfalseなので、この分岐はそちらの動作に影響しない。

`Sources/MyGamesPad/MyGamesPadApp.swift` が`@main`。ルートビューは
`Sources/MyGamesPad/ContentView.swift`(新規、Mac版の`ContentView`とは別物) —
`Router` + 8つの`GameState`(将棋・チェス・オセロ・囲碁・ダイヤモンドゲーム・
五目並べ・チェッカー・コネクトフォー)を`environmentObject`で注入した
`BoardGamesRootView`をそのまま表示するだけの薄いラッパー(タブバーは
2026-09-08に廃止済み、上記「同じページに水平線で分けて」の変更を参照)。

セーブは`~/Library/Application Support/BoardGames/<game>/slotN.json`
(iOS版のサンドボックス内、Mac版とは別ストレージ)。

## トランプ(CardGames)

`Sources/MyGamesPad/CardGames/index.html` はもともと `pwa/cardgames/index.html`
(外部fetchなしの完全自己完結HTML、8種のトランプゲーム)の**手動コピー**として
持ち込んだもの。ネイティブ移植はせず、`CardGamesWebView.swift`
(`WKWebView`をラップした`UIViewRepresentable`)でアプリバンドル内のコピーを
そのままオフラインで表示するだけ。理由: Web版はすでに完成度が高く自己完結して
いるため、大きなゲームロジックを再実装するより流用する方が圧倒的に低リスク。
**`pwa/cardgames/`自体は2026-09-07にユーザー指示で削除済みなので、この
`index.html`が唯一現存するコピーであり、以降「Web版と同期を取る」という運用は
終了している**(Mac版ボードゲームタブが削除されたあとの`mygames/CLAUDE.md`と
同じ状況)。

- 2026-09-09、ユーザー指示でこのコピーに直接3つの変更を加えた:
  1. **ババ抜きを削除**(「トランプでババ抜きはいらない」)—
     ホーム画面のタイル、`.game.baba`のCSS、セットアップ/ゲーム/結果の3画面、
     関連JS関数一式(`babaCfg`/`startBaba`/`babaRender`/`babaTurn`/`babaDraw`/
     `babaEnd`/`quitBaba`等)を削除した。`.baba-result-list`/`.baba-result-row`
     というCSSクラス名はババ抜き用に作ったものだが大富豪/7並べ/21/
     ブラックジャックの結果画面が流用しているため、名前はそのまま残してある
     (リネームは影響範囲が広く実益もないため見送った)。
  2. **神経衰弱の絵柄を🧠から🎴に変更**(「神経衰弱アイコンのシルエットが
     気持ち悪い」)— ホーム画面タイル・セットアップ画面タイトルの両方を修正。
  3. **神経衰弱・7並べ・スピードを2人対戦専用化(のちにスピードは往復)**
     (「次のゲーム二人モード専用にして: 神経衰弱、7並べ、スピード」)—
     各ゲームのセットアップ画面から「対戦相手(対AI対戦/2人対戦)」の選択
     自体を削除し、常に人間2人で開始するようにした。付随するAI専用コード
     (神経衰弱の`cpuMemory`/`cpuShinkeiTurn`、スピードの`speedTick`内の
     CPU反応ロジック、7並べの`sevensCpuMove`と`CPUの人数`セットアップ)も
     すべて削除した。**スピードはこの直後にユーザー指示「vs CPU モードも
     復活」で対AI対戦をロールバックし**(セットアップ画面を「対AI対戦
     (CPUの速さ選択つき)/2人対戦」の2択に戻し、`speedTick`のCPU反応
     ロジック等も復元)、**さらにそのあと今度は逆にユーザー指示「スピードで
     vs CPU はいらない」で再度2人対戦専用に戻した**(対AI対戦の選択・
     `speedCfg`・CPU反応ロジックを改めて削除)— 結果としてスピードも
     現在は2人対戦専用。7並べはこの一連の変更のさらに後で**まるごと削除**
     した(下記4)。神経衰弱は最初の2人対戦専用化のまま変わっていない。
     大富豪は当初からAI対戦のみ(のちに明示的にvs CPU専用化、下記5)。
     21は当初からAI対戦/2人対戦の両対応だったが、最終的にゲームごと削除
     した(下記10)。ブラックジャックは変更していない。
  4. **7並べを削除**(「7並べもいらない」)— ホーム画面のタイル・CSS
     (`.game.sevens`/`.sevens-*`)・セットアップ/ゲーム/結果の3画面・
     関連JS関数一式(`sevens`まわりの`start`/`Turn`/`Advance`/`Render`/`End`等)
     を削除した。`CardGameEntry.all`(`Shared.swift`)からも項目を削除。
  5. **大富豪をvs CPU専用化**(「大富豪も vs CPU モードのみでいい」)—
     セットアップ画面から「対戦相手」の選択を削除し、常に人間1人+CPU数人
     (2人/3人選択は維持)で開始するようにした。
  6. **大富豪の場札を少し重ねて表示**(「トランプを置いたら、ずらして、
     前のトランプが少し見えるようにしてほしい」)— それまでは場に出された
     組が新しい組に置き換わるたびに前の組が完全に消えていた。ルール判定用の
     `daifugo.pile`(直前に出された組だけを保持、8切り等のクリア含め従来通り)
     とは別に、場に出た札を全部積み上げる表示専用の`daifugo.pileStack`を
     新設し、`#daifugo-pile`のCSSに`flex-wrap:nowrap`+横スクロール+
     `margin-left:-38px`の重ね表示を追加した。
  7. **神経衰弱・スピードのカードを大きくしてタップしやすく**(「スピードの
     カードを大きくしてタップしやすく」「神経衰弱のカードを大きくして」)—
     神経衰弱は`.mem-card`を42×58→58×80(狭い画面用メディアクエリも
     36×50→48×66)に、スピードは手札のカードサイズを`sz-md`→`sz-lg`に
     変更(場札は元から`sz-lg`)。
  8. **vs CPU対戦の勝利でコインを付与**(「トランプゲームで、vs CPU の
     ときは、勝ったらコインが10枚増えるようにしてほしい」)— ホーム画面上部に
     `#coin-badge`(🪙)を常設し、`localStorage`(キー`cardgames_coins`)に
     端末側で保存するだけの簡易実装(何かに使う仕組みはまだ無い)。導入時点
     では`addCoins(10)`をスピード(`speedCheckWin`)・大富豪(`daifugoEnd`)・
     21(`twEnd`)・ブラックジャック(`bjEnd`)・ポーカー(`pokerShowdown`)の
     各勝利判定に差し込んだが、**その後21がゲームごと削除され(下記10)、
     スピードも2人対戦専用に戻った(上記3)ため、現時点でコインが実際に
     入るのは大富豪・ブラックジャック(`bj.mode==='ai'`のときだけ)・
     ポーカーの3ゲームのみ**(`speedCheckWin`/`twEnd`の`addCoins`呼び出しは
     コードごと削除済み)。人間同士の対戦では増減しない。神経衰弱は
     2人対戦専用のため元から対象外。
  9. **ポーカーをテキサスホールデムに全面書き換え、vs CPU専用・CPU3人固定**
     (「ポーカーはテキサスポーカーにしてほしい。vs CPU モードオンリーで、
     CPU は3人」)— 旧実装(1対1のドロー・ポーカー、手札交換1回)を破棄し、
     あなた+CPU3人の4人テーブルでプリフロップ→フロップ→ターン→リバー→
     ショーダウンの4ストリートを実装した。`pokerEvaluate`/`pokerCompare`
     (役の強さ比較、5枚固定)は流用し、7枚(手札2+場札5)から最強5枚を選ぶ
     `pokerCombinations`/`pokerBestHand`を新設。ベットは定額制の簡易ルール
     (プリフロップ/フロップはベット・レイズ幅20、ターン/リバーは40、
     1ストリートあたりのレイズ回数上限`POKER_RAISE_CAP=3`)、アンティは
     開始時に全員一律10。サイドポットは実装していない(オールインで足りない
     分もそのままポット全体を争える簡易ルール)。CPUの意思決定
     (`pokerCpuAct`)はプリフロップは手札の額面・ペア・スーテッド、フロップ
     以降は`pokerBestHand`の役ランクを0〜1の強さに正規化し、閾値+乱数で
     フォールド/コール/レイズを選ぶ簡易ヒューリスティック。ラウンド進行は
     `poker.toAct`(まだ行動していないプレイヤーIDのキュー、ベット/レイズが
     入るたびに他の全員を積み直す標準的な「ベッティングラウンド完了」判定)
     で管理。Node上にDOM/localStorageのスタブを用意し、常にコール/常にレイズ/
     常に即フォールドの3戦略で計200〜300ハンドを自動対戦させるハーネスで
     無限ループ・例外が出ないことを確認済み(ハーネス自体はコミットしていない
     使い捨てスクリプト)。ホーム画面のアイコン表示は短い「ポーカー」のまま
     残し、種目の違いはセットアップ画面のタイトル「♠️ テキサスホールデム」
     側で示す。
  10. **21を削除**(「21 はいらない」)— ホーム画面のタイル・`.game.tw`の
      CSS・セットアップ/ゲーム/結果の3画面・関連JS関数一式(`twCfg`/
      `startTw`/`twGetPlayer`/`twTurn`/`twCpuStep`/`twHit`/`twStand`/
      `twAdvance`/`twRender`/`twEnd`/`quitTw`)を削除した。ただし
      `calcHandValue`(トランプの合計点計算)と`.tw-status`というCSSクラス名
      はブラックジャックも共有して使っているため残してある(`.tw-hand-block`/
      `.tw-total`/`.tw-players`は21専用だったので削除し、ブラックジャック
      専用の`.bj-hand-block`/`.bj-total`/`.bj-area`はそのまま)。
  11. **スピードのvs CPUを再度削除**(「スピードで vs CPU はいらない」、
      上記3参照)— 一度復活させた対AI対戦の選択・`speedCfg`・
      `speedTick`のCPU反応ロジックを再び削除し、常に2人対戦のみで開始する
      形に戻した。
  - `CardGameEntry.all`(`Shared.swift`)からもババ抜き・7並べ・21の項目を
    削除し、残る5項目(神経衰弱/スピード/大富豪/ポーカー/ブラックジャック)の
    `emblem`を(神経衰弱は🎴に)更新した。トランプの各アイコン色は
    `LauncherTheme.iconGradients`への位置(元々8種のトランプと同じ並び順に
    依存していた)を直接の配列indexではなく`CardGameEntry.colorIndex`という
    固定フィールドで持たせるように変更した — 単純にindexのままだと削除した
    ゲームの分だけ後続のゲームの色がずれてしまうため(値は元の並び順のまま、
    ババ抜きの1・7並べの4・21の5が欠番)。
- **Web版とは自動で同期しない**(そもそもWeb版はもう存在しない)。今後
  このコピーに変更を加える際は直接編集する。
- Web版の「← My Apps」(`.home-link`、ルートランチャーへ戻るリンク)は
  ネイティブアプリ内では行き先が存在しない(ルートランチャーはWebのみ)ため、
  `CardGamesWebView`が読み込み時に`WKUserScript`で`display:none`にして隠す
  (コピー先のHTML自体は書き換えない — 過去のWeb版とのdiffを取りやすくする
  ため)。
- xcodegenは`Sources/MyGamesPad/`配下の非Swiftファイル(`index.html`)を
  自動的に「Copy Bundle Resources」に含める(`project.yml`側の追加設定は不要、
  `xcodegen generate`後に`project.pbxproj`で確認済み)。

## Icon

**ユーザー指示によりMac版と同じ意匠**(白背景+ファミコン実機配色のコントローラー、
`mygames/make-icon.swift`と同じ配色・レイアウト)。mytube-ipad/mygallery-ipad
が確立した「iPad版はMac版と別色にする」慣例には**従わない**([[app-icon-style]]
の例外、MyGames Mac版自体がすでに単色シルエット統一から外れた多色アイコンの
例外だったのを踏襲)。`make-icon.swift`はMac版と同じ描画コードを流用しつつ、
iOS向けに角丸を手動で描かず(システム側がマスクする)、`.icns`/`.iconset`では
なく単一の1024x1024 PNGを`Assets.xcassets/AppIcon.appiconset/`に出力する形に
変更してある(mygallery-ipadのmake-icon.swiftと同じ出力形式)。

## Build

`mytube-ipad`/`mygallery-ipad`と同じ、xcodegenベースのXcodeプロジェクト
(`.xcodeproj`は`.gitignore`済み、`project.yml`から再生成する)。

```bash
xcodegen generate
open MyGamesPad.xcodeproj
```

コンパイル確認だけなら(Xcodeを開かずに):
```bash
xcrun -sdk iphoneos swiftc -target arm64-apple-ios17.0 -typecheck \
  Sources/MyGamesPad/*.swift Sources/MyGamesPad/Core/*.swift \
  Sources/MyGamesPad/BoardGames/*.swift Sources/MyGamesPad/CardGames/*.swift
```

実機へのビルド・インストールはユーザー自身がXcodeから行う(無料Apple IDでの
7日間再署名運用、`README.md`参照)。
