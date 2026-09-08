# CLAUDE.md — MyGames Pad(mygames-ipad/)

## Overview

MyGames(Mac版)の「ボードゲーム」タブだけを取り出したiPad版。エミュレータ機能
(ライブラリ/ROM/コントローラーの3タブ、libretroコアの`dlopen`前提)は
iOSのアプリサンドボックス上そのままでは成立しない(ROM取り込みUI・外部コア
読み込みが必要)ため、意図的に含めない — ユーザー指示「ROM機能以外を含めて」
どおり、ボードゲーム集のみを移植した。2026-09-07、ユーザー指示で
`pwa/cardgames/`(トランプゲーム)も追加し、アプリ内はトップタブで
「ボードゲーム」/「トランプ」を切り替える2画面構成になった。

## Architecture

`Sources/MyGamesPad/BoardGames/` は `mygames/Sources/MyGames/BoardGames/` の
ほぼそのままのコピー(7種の独立した`*Engine.swift`/`*Game.swift`/`*Views.swift`
+ 共有の`Shared.swift`)。**Mac版と同期は自動で取れない** — Mac版のボードゲーム
ロジックを変更したら、この移植版にも同じ修正を反映するか検討すること。

移植時の変更点(iOS向けの最小限の書き換えのみ):
- `import AppKit` を削除(`BoardGamesRootView.swift`/`ShogiViews.swift`。実際の
  AppKit APIは使っていない、importだけ残っていた)
- `Color(nsColor: .windowBackgroundColor)` → `Color(uiColor: .systemBackground)`
  (全ゲームの背景色、他は変更不要)

2人対戦モード追加(2026-09-07)は Mac版と全く同じロジック(`OpponentMode`・
`isHumanTurn`の一般化・`scheduleAIMove`のガード等、詳細は`mygames/CLAUDE.md`
参照)を丸ごとコピーしたもの — Mac版の`Sources/MyGames/BoardGames/`から
7ファイルすべてを上書きコピーしたあと、上記2つのiOS向け変換(`import AppKit`
削除・`nsColor`→`uiColor`)と、iOS 17の`onChange(of:perform:)`非推奨対応
(2パラメータ/0パラメータ形式への書き換え、オセロの石めくりアニメーションのみ
`{ _, newValue in }`、他は`{ }`)を機械的に再適用する運用にしている。今後
Mac版のボードゲームロジックを変更する際も、この「Mac版をコピー→2つの
sed置換→onChange書き換えを再適用」の手順を踏めば大きな手作業なしに追随できる。

`Sources/MyGamesPad/MyGamesPadApp.swift` が`@main`。ルートビューは
`Sources/MyGamesPad/ContentView.swift`(新規、Mac版の`ContentView`とは別物) —
「ボードゲーム」/「トランプ」を切り替えるシンプルなトップタブバーで、
`Router` + 7つの`GameState`を`environmentObject`で注入した`BoardGamesRootView`と
`CardGamesWebView`を切り替える。

セーブは`~/Library/Application Support/BoardGames/<game>/slotN.json`
(iOS版のサンドボックス内、Mac版とは別ストレージ)。

## トランプ(CardGames)

`Sources/MyGamesPad/CardGames/index.html` は `pwa/cardgames/index.html`
(外部fetchなしの完全自己完結HTML、1900行超・8種のトランプゲーム)の
**手動コピー**。ネイティブ移植はせず、`CardGamesWebView.swift`
(`WKWebView`をラップした`UIViewRepresentable`)でアプリバンドル内の
コピーをそのままオフラインで表示するだけ。理由: Web版はすでに完成度が高く
自己完結しているため、1900行のゲームロジックを再実装するより流用する方が
圧倒的に低リスク。

- **Web版とは自動で同期しない** — `pwa/cardgames/index.html`を変更したら、
  このコピーにも `cp pwa/cardgames/index.html mygames-ipad/Sources/MyGamesPad/CardGames/index.html`
  で反映するか検討すること。
- Web版の「← My Apps」(`.home-link`、ルートランチャーへ戻るリンク)は
  ネイティブアプリ内では行き先が存在しない(ルートランチャーはWebのみ)ため、
  `CardGamesWebView`が読み込み時に`WKUserScript`で`display:none`にして隠す
  (コピー先のHTML自体は書き換えない — Web版とのdiffを取りやすくするため)。
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
  Sources/MyGamesPad/*.swift Sources/MyGamesPad/BoardGames/*.swift Sources/MyGamesPad/CardGames/*.swift
```

実機へのビルド・インストールはユーザー自身がXcodeから行う(無料Apple IDでの
7日間再署名運用、`README.md`参照)。
