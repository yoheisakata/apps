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

## MyGallery PadはmyslideshowPadの上位互換ではない ― 新しく足したもの

**ユーザー要望はOneDriveブラウズ+スライドショーの両方**だったが、
myslideshow-ipadは「選んだ年フォルダの写真・動画を問答無用でスライドショー
再生する」だけのアプリで、**ブラウズ可能なグリッド・1件ずつ見る手動ビューアを
持たない**。MyGallery Padの実装で最も工数を割いたのはこの欠けている部分 ―
「グリッドで一覧して、タップした1枚から見始められる」というMyGallery
(Mac版)らしい体験を、SwiftUIで新規に組み上げることだった。

- **`Views/GridView.swift`(新規)** ― `LazyVGrid`のサムネイルグリッド。
  mygallery(Mac版)の`GridViewController`+`NSCollectionView`に相当する画面だが、
  完全に新規のSwiftUI実装(移植元は無い)。動画アイテムには左下に▶バッジを
  重ねる(Mac版のグリッドが動画サムネイルに付けているのと同じ意図)。
- **`Views/ViewerView.swift`(新規)** ― グリッドでタップした位置から始まる
  全画面の単体ビューア。mygallery(Mac版)の`ViewerOverlay`に相当する画面だが、
  これも完全に新規のSwiftUI実装。**ページング方式は`TabView(.page)`ではなく
  独自の`DragGesture`+ボタン送り**にした ― `Views/SlideshowView.swift`
  (myslideshow-ipadから移植、下記)がすでに「現在のインデックスを持ち前後だけ
  レンダリングする」設計で実績があり、`TabView(.page)`は`AVPlayer`を持つ
  ページが隣接ページとして先読み保持される際の再生状態・メモリ管理が読みづらい
  ため、実績のある方式に揃えた。写真はタップでコントロール表示/非表示、動画は
  `AVPlayerViewController`の標準コントロール(`showsPlaybackControls: true`)を
  そのまま出す ― スライドショーと違い手動視聴なのでシークバー等を直接操作
  できた方が良いと判断した(`Views/NativeVideoPlayerView.swift`に
  `showsControls`引数を追加したのはこのため、下記参照)。
- **`Core/LinkBrowseState.swift`(新規)** ― 1本のOneDriveリンクぶんの
  「年/月フォルダ構造+選択状態」を保持する観測可能な状態オブジェクト。
  mygallery(Mac版)の`OneDriveFolderTreeViewController`(`NSOutlineView`ベースの
  年/月チェックボックスツリー)が持っていたのと同じ責務(フォルダ階層の
  インクリメンタル表示・チェック状態・選択の永続化)を、SwiftUIのチップUI向けに
  書き直したもの。**年/月の2階層(祖先優先ルール、年チェック→配下の月も
  一括選択)を実装しているのがmyslideshow-ipadとの最大の違い** ― 下記
  「年/月フォルダの粒度について」参照。
- **`Views/HomeView.swift`(myslideshow-ipadから大幅に改変)** ― 年チップだけ
  だったmyslideshow-ipad版に、年の下へ展開できる月チップを追加した。「開始」
  ボタンの遷移先もスライドショーではなく「グリッドを開く」(グリッド画面)に
  変更している。
- **`ContentView.swift`(myslideshow-ipadから大幅に改変)** ― 状態遷移が
  `home ⇄ slideshow`の2状態(myslideshow-ipad)から`home ⇄ grid`の2状態
  (このアプリ、スライドショー/ビューアはグリッドから`fullScreenCover`で
  さらに一段重ねる)に変わっている。「開始」時の実データ取得(フェーズ2)は
  `OneDriveMediaClient.scanLeafFolders`を使う点はmyslideshow-ipadと同じ。

## 年/月フォルダの粒度について(myslideshow-ipadとの最大の違い)

myslideshow-ipadのホーム画面(`Views/HomeView.swift`)は**年フォルダのチップだけ**
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
`toggleMonth`/`isMonthSelected`、`Views/HomeView.swift`の年チップ+展開可能な
月チップ)。実データ(Day階層)の回収はMac版と同じくフェーズ2
(`scanLeafFolderItems`)がMonthフォルダ配下を再帰的に辿って行う ―
フォルダツリーの選択粒度と実ファイルの取得ロジックの役割分担はMac版を
そのまま踏襲している。

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

## mygallery(Mac版)とは別コードベース、自動同期しない

mytube-ipad/myslideshow-ipadと同じ注意点: **Mac版とiPad版はファイルが分かれて
いるため自動的には同期しない**。mygallery(Mac版)に将来機能追加や不具合修正が
入っても、このiPad版へは反映されない。特に`Core/OneDriveMediaClient.swift`は
上記の通りMac版から移植したロジックそのものなので、Mac版側の認証フロー変更・
API仕様変更対応(署名付きURL失効・スキャン性能まわりの修正等)は、気づいたら
このアプリの同名ファイルにも同じ修正を反映するか検討すること。逆にこのアプリ
側で見つけたOneDrive関連の不具合修正も、Mac版に同じ問題が無いか確認した方が
よい(ロジックの大元は共通のため)。
