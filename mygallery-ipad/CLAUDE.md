# CLAUDE.md — mygallery-ipad

mygallery(Mac版)の「iPadでも近いものを使いたい」という要望から生まれた、
**OneDrive共有リンクのブラウズ専用**の縮小版アプリ。mytube→mytube-ipad、
myslideshow→myslideshow-ipadの移植と同じ方針(「Mac版の対応する機能を絞って
移植」)を踏襲している。ローカルフォルダのブラウズ・Visionベースの画質順ソート・
重複検出・回転・ゴミ箱への削除は対象外 ― 下記「なぜOneDriveだけなのか」参照。

## リポジトリ内で3つ目のXcodeプロジェクト製アプリ

他のSwiftUIネイティブアプリ(mynetworth/myorganizer/mytube/mygames/mypass)は
すべてSwift Package Manager(`Package.swift` + `swift build`/`build_app.sh`)、
mygallery/mymarkdown(Mac版)は`build.sh`が直接`swiftc`を呼ぶ単一バイナリ構成だが、
mytube-ipad/myslideshow-ipadと同じ理由でこのアプリだけは**Xcodeプロジェクト**
(`.xcodeproj`)が必要 ― iOS/iPadOS向けの`.app`(実機にインストール可能な形)は
SPMのコマンドラインビルドだけでは生成できず、Xcodeの署名・プロビジョニングの
仕組みが要るため。

- **`.xcodeproj`はコミットしない**(`.gitignore`済み)。[xcodegen](https://github.com/yonaskolb/XcodeGen)
  (Homebrewで`brew install xcodegen`)が`project.yml`から毎回生成する。
  `project.yml`を変更したら`xcodegen generate`を再実行すること。
- ビルド/実機インストールの手順は`README.md`参照。コンパイル確認は`swift build`が
  使えない(SPMではないため)ので、mytube-ipad/myslideshow-ipadと同じ以下の
  コマンドでSwiftの型チェックだけ行う:
  ```bash
  xcrun -sdk iphoneos swiftc -target arm64-apple-ios17.0 -typecheck \
    Sources/MyGalleryPad/*.swift Sources/MyGalleryPad/Core/*.swift Sources/MyGalleryPad/Views/*.swift
  ```

## なぜOneDriveだけなのか

mygallery(Mac版)は「ローカルフォルダ」/「動画(OD)」/「画像(OD)」の3タブ構成で、
ローカルブラウズには回転・重複検出(⇧⌘D)・人物/種類フィルター(Vision)・
画質順ソート(Vision)・ゴミ箱への削除など、iPadでは成立しない・成立させる価値が
薄い機能が多数ぶら下がっている:

- **ローカルフォルダ**: iOSは自由なファイルシステムアクセスができず、
  `UIDocumentPicker`+security-scoped bookmarkでの都度選択が必要になり、
  Mac版のような「フォルダを開いたままにしておく」体験からは離れる
  (mytube-ipad/myslideshow-ipadが同じ理由で見送ったのと同じ判断)。
- **回転・削除**: OneDriveアイテムはそもそもMac版でも対象外(ローカル専用機能)。
  iPadでもOneDriveだけを扱う以上、この制約はそのまま引き継がれる。
- **重複検出・画質順ソート(いずれもVisionベース)**: Mac版のCLAUDE.mdにある
  通りOneDriveアイテムには元々適用されない(ローカルファイルのみ対象)。iPad版が
  ローカルフォルダを持たない以上、丸ごと不要になる。
- **OneDrive**: `Core/OneDriveMediaClient.swift`は`URLSession`(Foundation+os
  のみ)で完結しており、iOS上でも無変更で動く。これが「OneDriveだけなら作れる」
  と判断した最大の理由(mytube-ipad/myslideshow-ipadと共通)。

つまりスコープの絞り方自体はmytube-ipadと同じ発想(「Mac版の中でプラットフォーム
非依存に動く部分だけを取り出す」)だが、対象がYouTube/ローカルフォルダではなく
ローカルフォルダ+Vision機能群という点が異なる。

## ナビゲーション構造(2026-09-07、mytube-ipad風のサイドバー常設方式へ全面改訂)

当初(myslideshow-ipad由来)は`ContentView`が`screen: .home / .grid`の2状態を
`ZStack`で切り替える構成だった ― `HomeView`が起動直後に出るブロッキングの
全画面(両リンクぶんの年/月フォルダチップ+スライドショー設定+「グリッドを
開く」ボタン)で、押すまでグリッドへ進めず、開いた後は両リンクの写真・動画が
1つの`mediaItems`配列にまとめて表示されていた(リンク単体でのブラウズができ
なかった)。

**この構成を撤去し、mytube-ipad(`ContentView.swift`)と同じ`NavigationSplitView`
サイドバー+detail方式に作り直した**:

- **`ContentView.swift`** ― サイドバーは`List(selection: $selectedLinkID)`で
  `links`(ビデオ/写真の2件、ハードコード)を単純に列挙するだけ(mytube-ipadと
  違い「+」での追加・削除UIは無い ― リンクが固定な方針は変わっていない)。
  `.navigationSplitViewColumnWidth(130)`・`.font(.caption)`の行ラベルも
  mytube-ipadと同じ値・スタイルに揃えてある。detailは選択中リンクがあれば
  `Views/LinkDetailView.swift`(下記)、無ければ`ContentUnavailableView`
  (「リンクを選んでください」)。`videoState`/`photoState`(`LinkBrowseState`、
  リンクごとのフォルダ構造+選択状態)は従来通り`ContentView`が保持するが、
  加えて`galleryStates: [String: LinkGalleryState]`(リンクIDをキーにした
  フェーズ2スキャン結果のキャッシュ、`items`/`isLoading`/`errorMessage`/
  `hasScannedOnce`)を新設した ― mytube-ipadの`sources: [String: RemoteSource]`
  と同じ設計で、いったんスキャンしたリンクへサイドバーで戻ってきても
  再スキャンせずキャッシュをそのまま表示する。`scan(link:)`が実際の
  `OneDriveMediaClient.scanLeafFolders`呼び出し(旧`openGrid()`のロジックを
  リンク単体向けに書き直したもの、ソートロジックは無変更)を担う。
- **`Views/LinkDetailView.swift`(新規)** ― 選択中リンク1本ぶんのグリッド画面。
  mytube-ipadの`Views/SourceGridView.swift`と同じ役割分担 ― 中身の描画は
  `Views/GridView.swift`(下記)に委譲し、このビューはフェーズ2スキャンの
  トリガー(初回自動・`.refreshable`のプルダウン・フォルダピッカーを閉じた
  とき)とナビゲーションタイトル・ツールバーの「年/月を選ぶ」ボタンだけを持つ。
  **フォルダ選択の変更のたびに即スキャンはしない**(下記「フォルダ選択とスキャン
  タイミングについて」参照)。
- **`Views/FolderPickerSheet.swift`(新規、旧`Views/HomeView.swift`から分離)** ―
  年/月フォルダチップ(`FolderChip`含む)+スライドショー設定(ランダム再生・
  写真の表示時間)を、単一リンク向けのシートとして持つ。中身のUI自体は旧
  `HomeView`の`linkSection`/`GroupBox`とほぼ同じ(複数リンクぶんの`ForEach`を
  単一の`state`直参照に変えただけ)。`LinkDetailView`のツールバーから開き、
  「閉じる」で`Environment(\.dismiss)`する。
- **`Views/GridView.swift`(改変)** ― 以前は自前で`NavigationStack`を持ち、
  「戻る」(ホーム画面へのブロッキング遷移)・「再読み込み」ボタンを自分の
  ツールバーに持っていたが、**`NavigationSplitView`のdetailに直接収まる前提の
  ビューへ変えた**(`NavigationStack`は撤去、`.navigationTitle`もこのビュー自体は
  付けない ― `LinkDetailView`が付ける)。mytube-ipadの`VideoLibraryView`と
  同じく、複数の`.toolbar`修飾子(このビューの「スライドショー」ボタンと
  `LinkDetailView`の「年/月を選ぶ」ボタン)は同一ビュー系列上でSwiftUIが
  自動的に1つのナビゲーションバーへマージする。「戻る」はサイドバー選択が
  そのままナビゲーションになったため不要に、「再読み込み」は
  `LinkDetailView`の`.refreshable`のプルダウンに統合したため撤去した。
  `items`に加えて`isLoading`/`errorMessage`も受け取るようになり、一覧が空の
  ときはローディング中/エラー/「写真・動画がありません」を出し分ける。

## 年/月フォルダの粒度について(myslideshow-ipadとの最大の違い)

myslideshow-ipadのホーム画面は**年フォルダのチップだけ**
(`HardcodedLink.availableFolders`が年の一覧、選択の最小単位が年)。一方
mygallery(Mac版)の`OneDriveFolderTreeViewController`は**Year/Monthの2階層の
チェックボックスツリー**を持っている(`Sources/OneDriveSidebarViewController.swift`)
― 実際のOneDriveライブラリがYear/Month/Dayの3階層まで存在するのに対し、
「フォルダツリーでの表示・選択はYear/Monthの2階層までで十分」というMac版での
ユーザー判断がすでに反映されたものだった。

このタスクの指示に「mygalleryがmonth粒度を露出しているか確認し、していれば
iPad版にも追加すること」とあったため確認し、上記の通りMac版はYear/Monthの
2階層を持つことを`Sources/OneDriveSidebarViewController.swift`
(`OneDriveFolderNode`/`OneDriveFolderTreeViewController`)で確認した ―
**このiPad版でも月レベルのチップを追加した**(`Core/LinkBrowseState.swift`の
`toggleMonth`/`isMonthSelected`、`Views/FolderPickerSheet.swift`の年チップ+
展開可能な月チップ)。実データ(Day階層)の回収はMac版と同じくフェーズ2
(`scanLeafFolderItems`)がMonthフォルダ配下を再帰的に辿って行う ―
フォルダツリーの選択粒度と実ファイルの取得ロジックの役割分担はMac版を
そのまま踏襲している。

## フォルダ選択とスキャンタイミングについて(mytube-ipadとの意図的な違い)

mytube-ipadはリンクを選んだ瞬間に即スキャンが始まり、以降は手動のプルダウン
更新のみでフォルダ選択という概念自体を持たない。MyGallery Padはこれに
「年/月フォルダの選択」という追加の軸があり、しかも`Core/
OneDriveMediaClient.swift`冒頭のコメントに詳しい通り**このアプリのフェーズ2
スキャンはmytube-ipadの単純な1リンクスキャンより重い**(選択された葉フォルダ
(月)ごとに個別のOneDrive APIリクエストが飛ぶ)。そのため、素朴に「フォルダ
選択が変わるたびに即スキャン」を実装すると、月チップを何個も連続でタップする
操作のたびに毎回重いスキャンが走ってしまう。

そこで`Views/LinkDetailView.swift`は次の3タイミングだけでスキャンする設計に
した:

1. **リンクを初めて開いたとき** ― フォルダ構造(フェーズ1)が揃って既定選択が
   決まった直後に1回だけ自動実行(`browseState.structureLoaded`の変化を
   `onChange`で検知、`LinkGalleryState.hasScannedOnce`で以降は自動発火しない
   ようにガード)。
2. **フォルダピッカー(`FolderPickerSheet`)を閉じたとき** ― チップの
   トグル操作自体ではスキャンせず、シートの`onDismiss`でまとめて1回。
3. **プルダウン更新(`.refreshable`)** ― 現在の選択のまま再スキャン
   (署名付きURLの失効対策、他アプリと同じ用途)。

**既定の選択も「初回は直近の年だけ」に変更した**(`Core/
LinkBrowseState.swift`の`loadStructureIfNeeded()`)― 以前(ホーム画面が
ブロッキングで「グリッドを開く」ボタンを押すまでスキャンが始まらなかった
構成)は初回の既定選択が「全年月」でも、実際にスキャンが走るのはユーザーが
明示的にボタンを押した後だったため問題にならなかった。今回はリンクを選んだ
瞬間に自動でフェーズ2が走るため、初回の既定を全年月のままにすると
「リンクを選んだだけで数年分の重いスキャンが自動的に始まる」ことになって
しまう。そのため初回(保存済みの選択が一切ない場合)だけ、フォルダ構造の
ストリームが完了した後に最新の年(`discoveredYears.max`)だけを選択済みに
する既定へ変えた。2回目以降の起動やユーザーが選び直した後は、通常通り
`Settings.folderSelections`に保存された選択がそのまま復元される。

## `Core/OneDriveMediaClient.swift`はmyslideshow-ipad自身のコピーではなく
## mygallery(Mac版)から移植した

myslideshow-ipad/mytube-ipadはどちらも自分自身の`Core/OneDriveMediaClient.swift`
(または`OneDriveShareClient.swift`)を持っているが、このアプリでは**あえて
myslideshow-ipad自身のコピーを流用せず、mygallery(Mac版)の
`Sources/OneDriveMediaClient.swift`を移植元に選んだ**。理由:

- mygalleryリポジトリで`git log --follow -- Sources/OneDriveMediaClient.swift`
  を確認したところ、直近のコミットはすべて2026-09-06/07付けで、
  myslideshow(Mac版、2026-09-02廃止)時点のロジックのままのmyslideshow-ipad版
  より明らかに新しい。
- mygallery版は`MediaItem`に`size`(ファイルサイズ)と`thumbnailURL`
  (OneDriveサーバー側生成済みの軽量サムネイル、2026-09-07追加)を持つ ―
  `Views/GridView.swift`のサムネイル読み込みを高速化するのに必須。
  myslideshow-ipad版の`MediaItem`にはどちらも無い。
- mygallery版はフォルダ階層の取得が「フェーズ1(Year/Monthの構造だけを
  ストリーミング取得)/フェーズ2(チェック済みMonthフォルダだけを個別取得)」の
  2段階に分かれている ― これが上記の年/月フォルダピッカーの土台になっている。
  myslideshow-ipad版は「選んだ年フォルダの中身(実ファイルまで)を1回のスキャンで
  全部集めてから返す」設計のままで、月粒度の選択に対応できない。

移植は`MediaKind`/`MediaItem`/`HardcodedLink`をこのファイルから切り出して
`Models.swift`へ移した点(myslideshow-ipadの置き場所の方針に揃えた)と、
ファイル内蔵だった`GalleryLog`を`Core/Log.swift`の`Log.scan`
(サブシステムは`com.yoheisakata.mygalleryipad`固定)に差し替えた点を除き、
ロジックは無変更。移植時に落としてはいけない設計(フェーズ1でのトップ
フォルダ絞り込み・並列`TaskGroup`+`ConcurrencyLimiter`・フェーズ2の
`resolveShare`によるトークンredeem等)は`Core/OneDriveMediaClient.swift`冒頭の
コメントに詳しく残してある ― 退化させると「年/月/日と深くネストした実際の
OneDriveライブラリで著しく遅くなる」というmygallery/myslideshow(いずれも
Mac版)で実証済みの不具合が再発する。

## myslideshow-ipadからほぼ無変更で移植したファイル

- **`Core/FilenameDateParser.swift`** ― 完全に無変更(pure Foundation)。
- **`Core/PlayerEngine.swift`** ― 完全に無変更(pure AVFoundation+Combine)。
- **`Views/SlideshowView.swift`** ― ほぼ無変更。追加したのは`startIndex`
  パラメータ(グリッド/ビューアからタップした位置を引き継いでスライドショーを
  開始できるようにした、myslideshow-ipadには無い ― myslideshow-ipadは常に
  ホーム画面から先頭件で開始するため不要だった)だけ。
- **`Core/ImageLoader.swift`** ― `NSImage`→`UIImage`の型自体は
  myslideshow-ipadと同じUIKitベースだが、**このアプリ独自に`thumbnail(for:)`
  (グリッド用、`thumbnailURL`優先)と`image(for:)`(ビューア/スライドショー用、
  常に`downloadURL`)を分離した** ― `MediaItem.thumbnailURL`という
  myslideshow-ipadには無いフィールドを活かすための変更。キャッシュ上限も
  スライドショー専用の8枚からグリッド全体を素早くスクロールできるよう
  60枚に増やした。
- **`Views/NativeVideoPlayerView.swift`** ― `showsControls: Bool`引数を
  追加した(既定`false`でmyslideshow-ipadと同じ挙動)。スライドショーは
  従来通り`false`(自前オーバーレイのみ)、`Views/ViewerView.swift`(手動視聴)は
  `true`(標準の再生バーを出す)で使う。

## リンク・年フォルダの選択肢

mygallery(Mac版)の`OneDriveLinks.video`/`.photo`と全く同じ2件・同じ年範囲
(2020〜2026)を`ContentView.links`にハードコードしてある。リンクの追加・削除
UIは持たない(Mac版が2026-09-06に「決め打ち2リンク」へ回帰したのと同じ方針、
`mygallery/CLAUDE.md`参照)。

## アプリアイコン

`make-icon.swift`(`swift make-icon.swift`で実行)が、mygallery(Mac版)の
`make-icon.swift`と同じ**SF Symbol "photo"(山と太陽の入った額縁)のシルエット**
モチーフを使う。ただし配色は変えてある:

- **背景**: Mac版は紫グラデーション(`0.55, 0.36, 0.96` → `0.36, 0.20, 0.70`、
  MyPassと同じ配色)だが、iPad版はmytube-ipad/myslideshow-ipadが確立した
  「白背景+単色シルエット」の型に合わせ、白のベタ塗りにした
  (`[[app-icon-style]]`参照)。
- **シルエット色**: Mac版の紫をそのまま使わず、ティール(`#12766B`)にした。
  mytube-ipad/myslideshow-ipadはどちらもすでに同じ青(`#1B5E9E`)を使っている
  ため、3本目のiPadアプリに同じ青を選ぶとホーム画面での見分けがつきにくくなる
  ― 「iPad版はMac版と別の色にする」というmytube-ipad由来の慣例は守りつつ、
  既存の2本の青とも別の色相にして、3本を並べたときに見分けやすくすることを
  優先した。

`Assets.xcassets/AppIcon.appiconset`フォルダ自体はすでに存在するため、
色やモチーフを再調整する場合は`make-icon.swift`を編集して再実行するだけでよい
(`xcodegen generate`の再実行は不要)。

## 不具合修正: プルダウン更新でグリッドが空になる(2026-09-07)

**症状**: すでに写真・動画が表示されているグリッドを下に引っぱって更新すると、
サムネイルが全部消えてしまう(その後何度か更新すると復活することもあれば
しないこともある)。

**根本原因**: `ContentView.scan(link:)`は「選択中の葉フォルダ(月)が1つも無い」
場合(`state.selectedLeafFolders()`が空)に`current.items = []`で無条件に
上書きしていた。この分岐自体は単体では「選択が空なら結果も空」という一見自然な
ロジックだが、`scan()`は**3つの独立したトリガー**(初回自動実行・
`.refreshable`のプルダウン・`FolderPickerSheet`の`onDismiss`)から同じ関数として
呼ばれる。`isLoading`だけを見た再入防止(`guard galleryStates[key]?.isLoading
!= true`)は「今まさに実行中の呼び出しが1つだけ」であることは保証するが、
**「短い時間差で立て続けに呼ばれた複数のscan()呼び出しのうち、後から開始した
呼び出しの結果を、先に開始したが後から完了した呼び出しが上書きしてしまう」**
という順序の逆転までは防げない。例えば「フォルダピッカーを閉じた直後
(`onDismiss`のscan開始)にもう一度素早く引っぱって更新する
(`.refreshable`のscan開始)」という操作をすると、後発の`.refreshable`呼び出し
(新しい選択状態を見ている)が先に完了して正しい結果を`galleryStates`へ書き込んだ
直後に、先発の`onDismiss`呼び出し(まだ古い選択状態のスナップショットを掴んで
いた場合や、たまたま`selectedLeafFolders()`が一瞬0件を返した場合)が完了して
`current.items = []`で上書きしてしまう、という経路が起こり得る。

`selectedLeafFolders()`自体が依存する`months`/`yearRefs`/`selectedPaths`
(`Core/LinkBrowseState.swift`)は、フェーズ1(`loadStructureIfNeeded()`)が
一度完了した後は明示的なユーザー操作(`selectAll`/`selectNone`/`toggleYear`/
`toggleMonth`)以外で書き換わることは無いと確認済み ― つまりこの不具合は
「選択状態そのものが壊れている」のではなく、**「複数の非同期`scan()`呼び出しの
結果が正しい順序で`galleryStates`へ反映されない」という古典的な非同期の
out-of-order書き込み**だった。

**修正**:

1. `LinkGalleryState`に`generation: Int`という単調カウンタを追加した。
   `scan(link:)`は開始時に`generation`をインクリメントして自分の世代番号を
   控え、結果を書き込む直前(`applyResult`ヘルパー)に「自分がまだ最新の世代か」
   を確認する ― 既により新しい`scan()`呼び出しが結果を書き込んでいた場合は
   何もしない。これにより「後から開始した呼び出しの結果を、先に開始した
   呼び出しが後から上書きする」逆転を構造的に防ぐ。
2. **指示された通りの防御的な修正も追加した**: 「選択中の葉フォルダが0件」
   「取得結果が0件」「取得が失敗した」のいずれの場合も、**すでにグリッドに
   表示中のアイテム(`current.items`)があるときはそれを消さない**ように変更
   した。空/エラーメッセージは「元々何も表示されていなかった」ときだけ出す。
   これは根本原因(世代の逆転)を修正した後でも、「本当にユーザーが全フォルダの
   選択を外した」場合にグリッドが空になる体験自体は変わらない ― 今回の指示は
   「リフレッシュの副作用として消してはいけない」という一段強い要件だったため、
   `guard`の分岐そのものを「消す」から「(既存アイテムがあれば)保つ」へ変更した。

新しく`scan()`まわりを触るときは、`galleryStates[key] = ...`の直接代入では
なく必ず`applyResult(key:generation:)`経由にすること ― 直接代入すると世代
チェックが素通りし、この不具合が再発する。

## サイドバーの年フィルター + グリッドの年月区切り線(2026-09-07、mygallery Mac版のOneDriveブラウズUXに寄せる)

「Mac版のOneDriveブラウズ体験(サイドバーでの年/月フィルター、グリッドの
年月区切り線)をiPad版にも」という要望への対応。Mac版の該当箇所
(`mygallery/Sources/main.swift`の`SortOrder`/`groupingEnabled`まわり、
`mygallery/Sources/OneDriveSidebarViewController.swift`の
`OneDriveFolderNode`/`OneDriveFolderTreeViewController`)を読み、**移植したのは
概念(年/月ツリーによる絞り込み、日付順のときだけ出る区切り線)だけ**で、
実装はSwiftUI向けに新規に書き起こした(Mac版は`NSOutlineView`/
`NSCollectionViewFlowLayout`セクションというAppKit APIに強く依存しており、
コードとしての移植先が無いため)。

### サイドバー年フィルター: シートと併存させた(月レベルは従来通りシートで)

`ContentView.swift`のサイドバー`List`に、各リンク名を`DisclosureGroup`の
ラベルにして、開くとその年一覧がチェック行(`yearFilterRows(for:)`)として
並ぶようにした。タップすると`LinkBrowseState.toggleYear(_:)`(既存のAPI、
`Views/FolderPickerSheet.swift`の年チップと全く同じもの)を呼び、続けて
`scan(link:)`を叩いて即座に絞り込みを反映する。

**設計判断: `Views/FolderPickerSheet.swift`は廃止せず、月レベルの絞り込み用に
残した。** 検討した選択肢は次の3つ:

1. シートを完全に廃止し、月チップもサイドバーへネストする。
2. サイドバーには年だけ、月はシートに残す(**採用**)。
3. サイドバーは触らず、シートだけで完結させる(=何もしない)。

(1)を選ばなかった理由: `NavigationSplitView`のサイドバー幅は
`.navigationSplitViewColumnWidth(170)`程度の狭い列で、年の下にさらに月チップ
(最大12個、`LazyVGrid`で複数列必要)までネストすると、サイドバー1行の高さが
リンクによって大きく変わり、リスト全体が窮屈かつ見苦しくなる(実機の
横幅を想定した判断、シミュレータでは検証していない)。またシートには
スライドショー設定(ランダム再生・写真表示秒数)も同居しており、月チップだけ
サイドバーへ引っ越すとシートに残るのはスライドショー設定だけになり、
「年/月を選ぶ」というボタン名と中身が食い違ってしまう。
(3)を選ばなかった理由: 「サイドバーでの年フィルター」というタスクの要求を
満たさない。

(2)の設計では、サイドバーの年チェックとシートの年チップは**両方とも同じ
`LinkBrowseState.selectedPaths`を直接操作する**ため、どちらで変更しても
もう片方に即座に反映され、状態が食い違うことは無い(`ObservableObject`の
`@Published`を両方が購読しているため)。年レベルの操作(絞り込みの大半は
「今年だけ見たい」等、年単位で十分なことが多い)はサイドバーからワンタップで
即座に効き、月単位の細かい絞り込みが必要なときだけシートを開く、という
役割分担にした。両方に同じ年チップ相当の操作が存在する重複は許容している
(実装・保守コストより、削って機能を弱める方が問題と判断)。

サイドバーの年フィルターは、対応するリンクの`LinkDetailView`をまだ一度も
開いていなくても使えるようにするため、`ContentView.body`の`List`に
`.task { videoState.loadStructureIfNeeded(); photoState.loadStructureIfNeeded() }`
を追加し、両リンクのフェーズ1(フォルダ構造)を起動時に先読みしている
(`loadStructureIfNeeded()`は多重実行防止のガード付きなので、後で
`LinkDetailView.task(id:)`が同じ呼び出しをしても安全)。

### グリッドの年月区切り線: `LazyVGrid`内の`Section`で実装

`Views/GridView.swift`に`groups: [ItemGroup]`という計算プロパティを追加した
― 呼び出し元(`ContentView.scan`/`.onChange(of: sortOrder)`)側で既に
`SortOrder`通りに並べ替え済みの`items`を、`folderPath`(年/月)が変わるたびに
新しい区切りにする「連続run」へ分割する。Mac版の`recomputeGroups()`
(`items`を`sortDate`の年月境界で連続run分割)と同じ考え方だが、SwiftUIには
`NSCollectionViewFlowLayout`のセクション機構が無いため、代わりに**`Section`を
`LazyVGrid`の直下に置く**方式にした(SwiftUIの`Section`はグリッド内でも
使え、ヘッダーはグリッドの列割り(`columns`)を無視して1行まるごとを占める ―
Mac版のセクションヘッダーと同じ見た目になる)。`GroupHeader`(タイトル+
水平線)が`DateSectionHeaderView`に相当する。

- `SortOrder.isDateOrder`のときだけ、かつグループが2つ以上あるときだけ見出しを
  出す(Mac版の`sortOrder.isDateOrder`ゲート・`groups.count > 1`条件と同じ)。
  名前順/サイズ順のときは`groups`自体が常に単一グループ(区切らない)を返す。
- 表示順そのもの(`items`のフラットな配列順)は変えていない ― `ItemGroup.items`
  は`(offset: Int, element: MediaItem)`のペアで、`offset`が`items`配列上の
  絶対インデックス(ビューア/スライドショーの開始位置に必要)を保持している。
  Mac版の`flatIndex(for:)`/`indexPath(forFlatIndex:)`ヘルパーに相当する考え方を、
  SwiftUIでは単にタプルに絶対インデックスを持たせるだけで済ませた
  (`NSCollectionView`の`IndexPath`API制約が無いため、Mac版ほど複雑な変換層は
  不要だった)。

## 並び替え順 + サイズ/日付バッジ(2026-09-07、mygallery Mac版の`SortOrder`/バッジ機構を移植)

`Core/SortOrder.swift`(新規)にMac版の`SortOrder`(`main.swift`)を移植した ―
**画質順(`.qualityDesc`/`.qualityAsc`)は対象外**(Visionベースの画質スコアリングは
ローカルファイル専用機能で、このアプリには元々存在しない、`CLAUDE.md`冒頭
「なぜOneDriveだけなのか」参照)。日付(新しい順/古い順)・名前順・サイズ順
(大きい順/小さい順)の5種類のみ。`isDateOrder`(グリッドの区切り線を出すかの
ゲート)・`showsFileSize`(サイズ順のときサイズバッジを強制表示するかのゲート)は
Mac版と同じ名前・同じ意味で移植してある。

- **日付順の並べ替えキーは`MediaItem.capturedDate`(ファイル名優先)→
  `modifiedDate`(OneDriveの更新日時)のフォールバック**。Mac版の`PhotoItem
  .sortDate`と同じ考え方(OneDriveの更新日時はアップロード/同期日時であって
  撮影日ではないことが多いため)。ただしMac版は`FilenameDateParser
  .dateTime(from:)`で時刻(`HHMMSS`)まで見るのに対し、このアプリの
  `FilenameDateParser`は日付までしか拾わない(既存の`MediaItem.capturedDate`が
  元々その粒度)。同日内の順序は`modifiedDate`をタイブレークに使うことで
  対応した ― 時刻粒度のパーサーを新設するほどの必要性は無いと判断した
  **意図的な簡略化**。同じ日に何件も撮った場合の順序がMac版と完全には
  一致しない可能性がある。
- **並び替え順の変更はOneDriveへの再取得を伴わない**。`ContentView`の
  `.onChange(of: sortOrder)`は`galleryStates`内の既取得アイテムをその場で
  並べ替えるだけ(Mac版のツールバー並び替えと同じ体感 ― 選ぶたびに毎回
  重いフェーズ2スキャンが走ると使いづらいため、`CLAUDE.md`前半の「フォルダ
  選択とスキャンタイミングについて」と同じ配慮)。並び替え順自体は
  `Settings.sortOrder`(UserDefaults)に永続化され、次回起動時も引き継ぐ。
  一方、新規にOneDriveへ取得するとき(`ContentView.scan`)は取得直後に
  `SortOrder.current.sorted(collected)`を通す ― 保存済みの順序を無視して
  常に`.dateDesc`で返す、といった食い違いが起きないようにするため。
- **サイズ/日付バッジ**は`Views/GridView.swift`の`ThumbnailCell`に実装。
  Mac版の`PhotoCell`と同じ2スロットdesign(左上=月日バッジ`showDateBadge`、
  右下=サイズバッジ`showSizeBadge`)だが、Mac版の右下スロットは画質バッジと
  排他(`ThumbnailBadge.none/.fileSize/.quality`)だったのに対し、このアプリは
  画質バッジが無いため右下はサイズ専用の単純な`Bool`で済ませた。**サイズ順
  ソート中はトグルの状態に関わらずサイズバッジを強制表示する**
  (`Views/LinkDetailView.swift`が`GridView`へ渡す際に
  `showSizeBadge || sortOrder.showsFileSize`を計算する形で実装、Mac版の
  `updateThumbnailBadge()`の強制分岐と同じ挙動)。月日バッジの書式は
  Mac版と同じ`"MMM d"`(例: `Jan 1`、`en_US_POSIX`ロケール固定 ― アプリ全体は
  日本語UIだが日付表記だけ意図的に英語)。
- ツールバーのUI: `Views/LinkDetailView.swift`のツールバーに、既存の
  「年/月を選ぶ」ボタンの並びとして並び替え`Menu`(⇅アイコン、`SortOrder
  .allCases`を`Picker`で列挙)と、月日/サイズバッジの押し込みトグルボタン
  (`.toggleStyle(.button)`)を追加した。両方とも状態は`ContentView`が
  `@State`として保持し、`Binding`でバケツリレーしている(`photoDuration`/
  `shuffleEnabled`と同じ配線パターン)。

## mygallery(Mac版)とは別コードベース、自動同期しない

mytube-ipad/myslideshow-ipadと同じ注意点: **Mac版とiPad版はファイルが分かれて
いるため自動的には同期しない**。mygallery(Mac版)に将来機能追加や不具合修正が
入っても、このiPad版へは反映されない。特に`Core/OneDriveMediaClient.swift`は
上記の通りMac版から移植したロジックそのものなので、Mac版側の認証フロー変更・
API仕様変更対応(署名付きURL失効・スキャン性能まわりの修正等)は、気づいたら
このアプリの同名ファイルにも同じ修正を反映するか検討すること。逆にこのアプリ
側で見つけたOneDrive関連の不具合修正も、Mac版に同じ問題が無いか確認した方が
よい(ロジックの大元は共通のため)。
