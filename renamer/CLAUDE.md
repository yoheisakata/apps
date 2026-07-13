# CLAUDE.md — renamer

Better Rename 代替の一括リネームアプリ。SwiftUI + SPM。機能一覧と制限事項は
`README.md` を参照。

## ビルド / デプロイ

```bash
swift run       # 開発ビルド
./build.sh      # Renamer.app をその場に生成 (build_app.sh ではない)
./install.sh    # ビルド → /Applications へ登録
```

## 構造

- **アプリ本体は `Sources/main.swift` の単一ファイル**（約 46KB）。分割しない方針。
- ルールは列挙型で定義され、上から順に適用。ルールごとに拡張子フィルタを持てる
  （連番はフィルタ内だけでカウント）。
- EXIF は ImageIO、音楽タグは AVFoundation。取得できないファイルはそのルールをスキップ。

## 変更時の注意

- リネームは必ずプレビュー → 衝突チェック（赤色警告 + 実行ブロック）→ 実行の順。
  衝突検出を迂回するパスを作らない。
- 実行したリネームは Undo スタック（バッチ単位・複数回）と
  `~/Library/Application Support/Renamer/history.log` の両方に記録する。
- プリセットは JSON で保存・書き出し・読み込みできる形式を維持する。
- ルールは拡張子を除いた名前部分に適用（拡張子を触るのは「拡張子を変更」ルールだけ）。
