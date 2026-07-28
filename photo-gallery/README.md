# photo-gallery

Photos.app 風のローカルフォルダ・フォトギャラリー(ネイティブ macOS)。
ライブラリへの取り込み(インポート)は一切せず、指定したルートフォルダ配下の
写真をその場で再帰スキャンして閲覧・整理する。

- Swift + AppKit の単一 `Sources/main.swift`(WKWebView なし・依存なし・実行時ネットワークなし)
- サイドバー: 画像を含むフォルダだけのツリー(枚数つき)+「すべての写真」
- サムネイルグリッド: 正方形サムネイル(EXIF 回転対応・並列生成・キャッシュ)、
  ツールバーのスライダー / ⌘+ / ⌘- でサイズ変更
- 複数選択: ⇧クリックで範囲選択、⌘クリックで個別トグル、⇧←/→/↑/↓ でキーボードから
  範囲選択、⌘A ですべて選択
- フルサイズビューア: ダブルクリック / Space / Return で開く、← → で移動、Esc で戻る
- 並び替え: 新しい順(既定)/ 古い順 / 名前順
- 整理: ⌘⌫ でゴミ箱へ(確認なし即実行・Finder のゴミ箱から復元可)、Finder で表示(⇧⌘R)、
  ⌘C でコピー、グリッドから Finder / 他アプリへドラッグも可
- 回転(⌘R): 選択(またはビューア表示中)の写真を90°時計回りに回転して元のファイルへ
  直接上書き保存(EXIF の向きを画素に焼き込んでからリセット)。ゴミ箱と違い元に戻せない点に
  注意。RAW など書き込みに対応していない形式は失敗として報告される
- 重複検出(⇧⌘D): ルートフォルダ全体をスキャンし、完全一致(SHA-256)〜あいまい一致
  (dHash、厳密/標準/ゆるいの3段階)まで4段階のマッチレベルを切り替え可能
  (Organizer.app の「重複写真」ペインと同等のロジック)。「残す基準」
  (解像度が最大/ファイルサイズが最大/最新/最古)で各グループの1枚を自動選択し、
  カードをクリックしてゴミ箱行き/残すを個別調整、まとめてゴミ箱へ(確認あり・復元可)。
  グループ見出しのチェックボックスを外すと誤検出グループを丸ごと削除対象から除外でき、
  「1グループ最大N枚」の上限(既定3枚)で緩いマッチレベルによる大量削除も防ぐ
- フィルター(ツールバーの絞り込みアイコン): 日付範囲(すべて/今日/今週/今月/カスタム)と
  人物あり/人物なし(Vision の顔検出、オンデバイス・ネットワーク不要)を組み合わせて
  現在のフォルダの表示を絞り込む。件数表示は「表示中 / 全体」の形式
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
| ⇧クリック | (グリッド内)クリックしたアイテムまでの範囲を選択 |
| ⌘クリック | (グリッド内)クリックしたアイテムだけを選択に追加/除外 |
| ⇧← ⇧→ ⇧↑ ⇧↓ | (グリッド内)キーボードで選択範囲を1件ずつ伸縮 |
| ⌘A | グリッド内のすべての写真を選択 |
| ⌘⌫ | 選択(またはビューア表示中)の写真をゴミ箱へ |
| ⌘R | 選択(またはビューア表示中)の写真を回転して上書き保存 |
| ⌘+ / ⌘- | サムネイルの拡大 / 縮小 |
| ⇧⌘D | 重複を検出… |
| ⇧⌘R | Finder で表示 |
| ⌥⌘S | サイドバーの表示/非表示 |

「再読み込み」(再スキャン)はショートカットなし(ファイルメニューから)。
⌘R を回転に割り当てたため。

## How it works

- スキャンは `FileManager.enumerator` によるバックグラウンド再帰列挙。隠しファイルと
  パッケージ内部(`.app` / `.photoslibrary` など)はスキップ。ファイルは一切動かさない。
- サムネイルは `CGImageSourceCreateThumbnailAtIndex`(EXIF 回転込み・最大 512px に
  ダウンサンプル)を並列 4 本の `OperationQueue` で生成し、`NSCache` に保持。
  RAW でも埋め込みサムネイルがあれば高速。
- グリッドは `NSCollectionView` + FlowLayout。セルは `CALayer.contentsGravity` の
  aspect-fill で正方形クロップ表示(ピクセル加工はしない)。
- ⇧クリック/⌘クリックは `NSCollectionView` 標準の複数選択(`allowsMultipleSelection`)
  にそのまま任せている。⇧←/→/↑/↓ によるキーボード範囲選択と ⌘A(`selectAll(_:)` の
  独自実装。`NSCollectionView` は自前実装しないと ⌘A が効かないため)は
  `GridCollectionView` 側で追加実装している。
- ビューアはグリッドに被せるオーバーレイビュー。まずキャッシュ済みサムネイルを即表示し、
  裏で最大 4096px を読み直して差し替える。
- ゴミ箱は `FileManager.trashItem`(システム標準のゴミ箱)なので Finder からいつでも戻せる。
- 回転は `CGImageSourceCreateThumbnailAtIndex`(`WithTransform: true`・実寸以上の
  `maxPixel`)で EXIF の向きを画素に反映したフル解像度画像を取得し、`CoreImage`
  (`CIImage.transformed(by:)`)で90°回転してから、元と同じ UTI で
  `CGImageDestination` により一時ファイルへ書き出し、`FileManager.replaceItemAt`
  で元ファイルとアトミックに差し替える。書き込み先の UTI が
  `CGImageDestinationCopyTypeIdentifiers()` に含まれない場合(RAW 等)は事前に
  失敗として弾き、元ファイルには一切触れない。回転後は `ThumbnailLoader` の
  メモリキャッシュを明示的に無効化し、`PhotoStore` 側の mtime を再取得することで
  ディスクキャッシュ(mtime をキーに含む)も自動的に再生成される。
- 重複検出はまず全写真を並列解析(`DispatchQueue.concurrentPerform`)し、ファイルサイズ・
  寸法・dHash(9×8 グレースケールに縮小した 64bit 知覚ハッシュ)を1回だけ計算してキャッシュする。
  マッチレベルの切り替えはこのキャッシュ済みデータの再グループ化だけで完結し、ファイルを
  読み直さない。「完全一致」はサイズ→SHA-256(`CryptoKit`、`FileHandle` ストリーミング読み)の
  二段階、「厳密/標準/ゆるい」は dHash のハミング距離を Union-Find でクラスタリングして
  類似画像(リサイズ/再エンコード後のコピー等)も検出する。
  Organizer.app の `DupPhotosViewModel` と同じアルゴリズム(重複ロジックは
  アプリごとに独立実装 — ルート `CLAUDE.md` の方針どおりコードは共有しない)。
  グループ・カードの表示は`NSCollectionView`を使わずプレーンな`NSStackView`で
  組んでいるため(セルの自動再利用が無い)、候補が数千件規模になるとカードを全部
  一度に作るだけならメモリは問題にならないが、各カードが読み込むサムネイル画像は
  スクロールの可視矩形(前後にバッファつき)と交差するグループだけ読み込み、外れたら
  解放する(`DuplicatesWindowController.updateVisibleThumbnails`、`NSClipView`の
  `boundsDidChangeNotification`で追従)。導入前は全候補分のサムネイルを即時読み込み・
  保持していたため、重複グループ数が多い大きなライブラリで数十GB規模のメモリを
  使うことがあった。
- フィルターの日付範囲は `PhotoItem.mtime`(ファイルの更新日時)に対する
  `DateInterval` 判定で、同期的かつ即座に効く。人物あり/なしは Vision の
  `VNDetectFaceRectanglesRequest` を縮小画像(最大 800px)にかけて判定し、
  結果を `(パス, mtime)` キーでメモリ内キャッシュする(`FaceCache`、ディスク永続化はしない)。
  人物フィルターを有効にしたときだけ、未解析の写真をバックグラウンドで並列解析して
  進捗をポップオーバーに表示し、完了後にグリッドへ反映する — フィルターを使わない限り
  顔検出は一切走らない。「イラスト判定」は Vision に専用の分類器がなく精度を保証できない
  ため見送り、「特定の人物」の識別も Vision に顔認識(同一人物判定)の公開 API がなく
  自前でのクラスタリング実装が必要になるため今回は対象外にした。

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
