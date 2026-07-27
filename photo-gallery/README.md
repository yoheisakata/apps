# photo-gallery

Photos.app 風のローカルフォルダ・フォトギャラリー(ネイティブ macOS)。
ライブラリへの取り込み(インポート)は一切せず、指定したルートフォルダ配下の
写真をその場で再帰スキャンして閲覧・整理する。

- Swift + AppKit の単一 `Sources/main.swift`(WKWebView なし・依存なし・実行時ネットワークなし)
- サイドバー: 画像を含むフォルダだけのツリー(枚数つき)+「すべての写真」
- サムネイルグリッド: 正方形サムネイル(EXIF 回転対応・並列生成・キャッシュ)、
  ツールバーのスライダー / ⌘+ / ⌘- でサイズ変更
- フルサイズビューア: ダブルクリック / Space / Return で開く、← → で移動、Esc で戻る
- 並び替え: 新しい順(既定)/ 古い順 / 名前順
- 整理: ⌫ でゴミ箱へ(確認あり・Finder のゴミ箱から復元可)、Finder で表示(⇧⌘R)、
  ⌘C でコピー、グリッドから Finder / 他アプリへドラッグも可
- 対応形式: JPEG / PNG / GIF / HEIC / WebP / TIFF / BMP / AVIF ほか、
  主要 RAW(CR2/CR3/NEF/ARW/DNG など。ImageIO がデコードできるもの)
- 前回のルートフォルダ・並び順・サムネイルサイズは次回起動時に復元

## Install

```bash
cd photo-gallery
./build.sh           # = ./build.sh install — build + /Applications へコピー
```

以降は Spotlight(⌘Space → "Photo Gallery")や Launchpad から起動。
ソースを変更したときだけ再実行する(ad-hoc codesign のローカル用アプリ)。

その他のコマンド:

```bash
./build.sh app       # build/ にダブルクリック可能な .app を作って開く
./build.sh build     # バイナリのみコンパイル
./build.sh clean     # build/ を削除
```

## Usage

ルートフォルダの指定方法(いずれか):

- ⌘O(ファイル → フォルダを開く…)
- ウインドウへフォルダをドラッグ&ドロップ
- Finder でフォルダを右クリック → このアプリケーションで開く → Photo Gallery

キーボード:

| キー | 動作 |
|---|---|
| Space / Return / ダブルクリック | フルサイズビューアを開く |
| ← → (ビューア内) | 前後の写真へ |
| Esc / Space (ビューア内) | グリッドに戻る |
| ⌫ | 選択(またはビューア表示中)の写真をゴミ箱へ |
| ⌘+ / ⌘- | サムネイルの拡大 / 縮小 |
| ⌘R | 再読み込み(再スキャン) |
| ⇧⌘R | Finder で表示 |
| ⌥⌘S | サイドバーの表示/非表示 |

## How it works

- スキャンは `FileManager.enumerator` によるバックグラウンド再帰列挙。隠しファイルと
  パッケージ内部(`.app` / `.photoslibrary` など)はスキップ。ファイルは一切動かさない。
- サムネイルは `CGImageSourceCreateThumbnailAtIndex`(EXIF 回転込み・最大 512px に
  ダウンサンプル)を並列 4 本の `OperationQueue` で生成し、`NSCache` に保持。
  RAW でも埋め込みサムネイルがあれば高速。
- グリッドは `NSCollectionView` + FlowLayout。セルは `CALayer.contentsGravity` の
  aspect-fill で正方形クロップ表示(ピクセル加工はしない)。
- ビューアはグリッドに被せるオーバーレイビュー。まずキャッシュ済みサムネイルを即表示し、
  裏で最大 4096px を読み直して差し替える。
- ゴミ箱は `FileManager.trashItem`(システム標準のゴミ箱)なので Finder からいつでも戻せる。

## Layout

```
photo-gallery/
├── build.sh                 # build / install(mini-editor と同じ自己完結パターン)
├── VERSION
├── Sources/main.swift       # アプリ全体(store / サムネイルローダ / グリッド / サイドバー / ビューア)
└── Resources/AppIcon.png    # アイコンのマスター(build.sh が .icns を生成)
```

## Requirements

macOS 11+ と Swift toolchain(`swiftc`)— Xcode Command Line Tools で十分。
