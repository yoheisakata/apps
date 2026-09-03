# CLAUDE.md — myslideshow-ipad

myslideshow(Mac版)の「iPadでも使いたい」という要望(2026-08-30)から生まれた、
**OneDrive共有リンクの自動連続再生専用**のiPad版。mytube→mytube-ipadの移植と全く同じ
方針(「Mac版の対応する機能を絞って移植」)を踏襲した ― もともとmyslideshow自体が
OneDrive共有リンク専用アプリなので、mytube-ipadのように「YouTube/ローカルフォルダは
対象外にする」といった機能面のスコープ削減は不要だった。iPad版で削ったのは**macOSの
ウィンドウ管理に依存する部分だけ**(下記参照)。

**移植元のMac版(`myslideshow/`)は2026-09-02に廃止され、同等の機能は`mygallery/`に
統合された**(`mygallery/CLAUDE.md`参照)。このiPad版はその対象外で、そのまま独立した
アプリとして動作し続ける ― 以下の記述中「Mac版」への言及はすべて、廃止される前の
`myslideshow/`を指す歴史的な記録として読むこと(移植元のファイルはもう存在しない)。

## リポジトリ内で2つ目のXcodeプロジェクト製アプリ

他のSwiftUIネイティブアプリ(mynetworth/myorganizer/mytube/mygames/
mypass)はすべてSwift Package Manager(`Package.swift` + `swift build`/
`build_app.sh`)だが、mytube-ipadと同じ理由でこのアプリだけは**Xcodeプロジェクト**
(`.xcodeproj`)が必要 ― iOS/iPadOS向けの`.app`はSPMのコマンドラインビルドだけでは
生成できない。

- **`.xcodeproj`はコミットしない**(`.gitignore`済み)。[xcodegen](https://github.com/yonaskolb/XcodeGen)
  が`project.yml`から毎回生成する。`project.yml`を変更したら`xcodegen generate`を
  再実行すること。
- ビルド/実機インストールの手順は`README.md`参照。コンパイル確認は`swift build`が
  使えない(SPMではないため)ので、mytube-ipadと同じ以下のコマンドでSwiftの型チェックだけ
  行う:
  ```bash
  xcrun -sdk iphoneos swiftc -target arm64-apple-ios17.0 -typecheck \
    Sources/MySlideshowPad/*.swift Sources/MySlideshowPad/Core/*.swift Sources/MySlideshowPad/Views/*.swift
  ```

## なぜMac版とほぼ同じスコープで作れたか

myslideshow(Mac版)は最初からOneDrive共有リンク専用(ローカルフォルダのスキャンを持たない)
アプリだった。`Core/OneDriveMediaClient.swift`は`URLSession`(Foundationのみ)で完結して
おり、mytubeの`OneDriveShareClient`と同じ理由でiOS上でも無変更で動く(`Origin`/`Referer`
ヘッダーをネイティブアプリだから自由に設定できる、という同じ理屈)。そのため
mytube-ipadのような「YouTube/ローカルフォルダは大幅な設計変更が要るので対象外にする」
という機能面の判断は不要で、**このアプリで削ったのはmacOS固有のウィンドウ管理コードだけ**
だった。

## アーキテクチャ(Mac版との差分)

myslideshow(Mac版)の全ファイルをベースに、以下だけを変更して移植した。

- **`Models.swift`** — `MediaItem`/`HardcodedLink`は無変更。**`PlaybackMode`
  (ウィンドウ内/全画面/PIP)は移植していない** ― iPadはSwiftUIの`WindowGroup`が常に
  フルスクリーンで開き、Mac版のような「メインウィンドウをリサイズする」「別の浮動パネルを
  出す」という概念自体が存在しない。iPadのスライドショーは常にMac版の`.fullScreen`相当の
  唯一の見た目になる。
- **`Core/OneDriveMediaClient.swift`** — Mac版から**無変更**で移植(pure Foundationの
  ため)。認証フロー・非公開内部API依存・署名付きURLの1時間失効・全階層走査+リトライ+
  並列化(`ConcurrencyLimiter`)のいずれもMac版と完全に同じロジック。**片方を直したら
  もう片方も直すこと**(mytube/mytube-ipadと同じ、認証フローが変わった場合の注意)。
- **`Core/FilenameDateParser.swift`** / **`Core/Log.swift`** — Mac版から無変更で移植
  (前者は正規表現のみ、後者は`os.Logger`のみでプラットフォーム差異が無い)。`Log`の
  サブシステムは`com.yoheisakata.myslideshowpad`(Mac版の`com.yoheisakata.myslideshow`
  とは別)。
- **`Core/ImageLoader.swift`** — Mac版から`AppKit`(`NSImage`)を`UIKit`(`UIImage`)に
  差し替えただけ。ロジック(直近8枚のメモリキャッシュ、ディスクキャッシュ無し)は同じ。
- **`Core/PlayerEngine.swift`** — Mac版から**無変更**で移植(`AVFoundation`+`Combine`
  のみで、AppKit/UIKitのどちらにも依存していないため)。
- **`Views/NativeVideoPlayerView.swift`** — Mac版は`AVPlayerView`(AppKit)を
  `NSViewRepresentable`でラップしているが、iOSにAppKitの対応物は無いため
  `AVPlayerViewController`を`UIViewControllerRepresentable`でラップする(mytube-ipadの
  同名ファイルと同じ移植方針)。`showsPlaybackControls = false`でMac版の
  `controlsStyle = .none`と同じ「標準コントロールを出さない」効果を得ている。
- **`ContentView.swift`** — Mac版からホーム画面/スライドショー画面の切り替えロジック
  (`isShowingSlideshow`)・OneDriveアクセス(`start()`)・年別フォルダ選択の永続化を
  ほぼそのまま移植。**`playbackMode`関連の状態・分岐・`PIPWindowController`は丸ごと
  削除**(iPadに対応物が無いため)。ホーム画面/スライドショー画面それぞれに固定
  `.frame`を与えていたMac版と違い、iPad版はどちらの画面も明示的な`.frame`指定をせず
  画面いっぱいに表示する(Mac版はウィンドウサイズを自分で管理する必要があったが、
  iPadは端末の画面サイズがそのままウィンドウサイズなので不要)。`.statusBarHidden
  (isShowingSlideshow)`でスライドショー中だけステータスバーを隠す(Mac版に対応する
  概念は無い、iPad特有の追加)。
- **`Views/HomeView.swift`** — Mac版のレイアウト(`GroupBox`によるセクション分け、
  「全選択」/「全非選択」ボタン、写真の表示秒数/シャッフル/時間制限の設定)をほぼ
  そのまま移植。**変更点**:
  - **表示モードのセグメントピッカーを削除**(`PlaybackMode`が無いため)。
  - **`Toggle(.checkbox)`(iOSに存在しないスタイル)を自前の`FolderChip`(カプセル型
    チップボタン)に置き換えた** ― 選択中は塗りつぶし+チェックマーク、未選択は
    薄い背景色のみ。タップで`onToggleFolder`を呼ぶ点はMac版の`Toggle`と同じ。
  - **`ScrollView`で全体を包んだ**(Mac版は固定ウィンドウサイズ420×560だが、iPadは
    機種・向き(縦/横)によって画面サイズが変わるため、内容が収まらない場合でも
    必ずスクロールで到達できるようにするため)。
  - 本体コンテンツの最大幅を460→640に広げた(iPadの画面はMacの固定ウィンドウより
    大きいため、少し余裕を持たせた)。
- **`Views/SlideshowView.swift`** — Mac版の中心ロジック(写真は`Settings.
  photoDurationSeconds`秒でタイマー送り、動画は`PlayerEngine.onFinished`で送り、
  右下の撮影日ラベル、3秒で消えるコントロールオーバーレイ、時間制限タイマー、
  再生失敗時の自動スキップ)をほぼそのまま移植。**変更点**:
  - **`applyWindowModeIfNeeded()`/`restoreWindowModeIfNeeded()`(NSWindowを直接
    操作してウィンドウ内/全画面/PIPを出し分ける処理)を丸ごと削除** ― iPadは
    `WindowGroup`が常にフルスクリーンで開くため、Mac版のようなウィンドウサイズ
    調整・`NSApplication.shared.keyWindow`操作が一切不要になった。
  - **`NSEvent.addLocalMonitorForEvents`(macOS専用のキーボード監視)を、SwiftUI
    ネイティブの`.onKeyPress`(iOS 17+)に置き換えた** ― Magic Keyboard等の外部
    キーボードを接続したiPadでも、スペース/矢印/escでMac版と同じ操作ができる
    (`onKeyPress`はキーごとに個別のモディファイアとして書く、mytubeやmyslideshow
    Mac版のような単一のイベントハンドラ内でswitch分岐する形ではない)。
  - **`onContinuousHover`に加えて`onTapGesture`を追加** ― `onContinuousHover`は
    iPad単体(トラックパッド/Apple Pencilのポインタ非接続時)では発火しないため、
    指でのタップでもコントロールオーバーレイ(一時停止/前後送り/終了)を表示できる
    ようにした。これが子どもも含めた実際の主要な操作手段になる想定。
  - `NSImage` → `UIImage`(`Image(nsImage:)` → `Image(uiImage:)`)。

## アプリアイコン

`make-icon.swift`(`swift make-icon.swift`で実行)がmyslideshow(Mac版)と同じ
「山+太陽」の写真プレートモチーフを、mytube-ipadと同じ「白背景+青(`#1B5E9E`)の
シルエット」でiOS向け単一1024pxアイコンとして生成する(`Sources/MySlideshowPad/
Assets.xcassets/AppIcon.appiconset/icon-1024.png`)。色をMac版の赤から青に変えているのは
mytube-ipadで確立した「iPad版は青、Mac版は赤」という区別をそのまま踏襲したもの ―
モチーフ自体はMac版と揃えることで「同じアプリの兄弟」であることが分かるようにした。
アイコンを変更する場合は`make-icon.swift`を編集して再実行するだけでよい
(`AppIcon.appiconset`フォルダ自体はすでに存在するため、画像の差し替えだけなら
`xcodegen generate`の再実行は不要)。

## スライドショー設定の並び順

Mac版・iPad版とも「スライドショー設定」内は上から**ランダム再生**(`Toggle`)→
(Mac版のみ)表示モード→写真の表示時間→時間制限、という順(2026-08-31、
「ランダム設定を最初にもってきて」という要望への対応)。

## Mac版との同期漏れ

2026-08-31、「ipad版に適用してほしかった」という指摘で発覚 ― Mac版
(`myslideshow`)に加えた変更のうち、ウィンドウ管理に関わらない単純なUI変更
(ラベル文言・フォントサイズ)がiPad版へ反映されないまま残っていた。年別
チェックボックスの拡張(動画リンクを2020〜2021年→2020〜2026年)は別途
反映済みだったが、以下の2点が漏れていた:

- `Views/HomeView.swift`の`Toggle("順番をシャッフル", ...)` →
  `Toggle("ランダム再生", ...)`(Mac版v1.17.4の変更に追随)。
- `Views/SlideshowView.swift`の`dateLabel(for:)`のフォント
  `.callout.weight(.medium)`(padding 10/5) → `.system(size: 48, weight: .bold)`
  (padding 24/14)(Mac版v1.17.3〜v1.17.5の2段階の拡大要望に追随)。

**Mac版とiPad版はファイルが分かれているため自動的には同期しない** ―
`Views/HomeView.swift`/`Views/SlideshowView.swift`のようなウィンドウ管理に
依存しない画面はほぼ同じ内容なので、Mac版を変更したら都度この2ファイル
(および他の非依存ファイル)をiPad版にも反映すべきか確認すること。
この教訓を踏まえ、直後の「日付が少し大きくなりすぎたので、少しだけ小さく。
両方ともに」(2026-08-31、`dateLabel`のフォントを48pt→36ptへ)は最初から
Mac版・iPad版同時に反映した。

## 今後拡張する場合のメモ

- 「ウィンドウ内/全画面/PIP」に相当する何かがiPadで欲しくなった場合、iPadOSの
  Slide Over/Split Viewはユーザー操作(ホームバーからのドラッグ等)が起点でアプリ側から
  制御できないため、Mac版の`PIPWindowController`(自前のNSPanel)と同じ発想の移植先は
  無い。AVKitのシステムPicture-in-Picture(`AVPictureInPictureController`)は動画専用
  ― myslideshow(Mac版)が「写真も扱うため採用しなかった」と判断した理由がiPadでも
  同様に当てはまる。
- Mac版に将来機能が追加された場合、`Core/OneDriveMediaClient.swift`・
  `Core/FilenameDateParser.swift`・`Core/PlayerEngine.swift`は無変更のまま移植できる
  可能性が高い(プラットフォーム非依存のため)。`Models.swift`/`Settings.swift`/
  `ContentView.swift`/`Views/*.swift`はMac版の変更点を都度確認し、ウィンドウ管理に
  関わる部分以外を反映すること。
