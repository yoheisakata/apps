# CLAUDE.md — cleanmac

SwiftUI + SPM の macOS お掃除アプリ。リポジトリ全体の規約はルートの
`CLAUDE.md`、機能の詳細は `README.md` を参照。

## ビルド / デプロイ

```bash
swift run          # 開発ビルド
./build_app.sh     # CleanMac.app をその場に生成 (ad-hoc 署名込み)
./install.sh       # ビルド → /Applications へコピー → 起動
```

アイコンは `swift make-icon.swift` で再生成（紫グラデ背景 + 白いほうき🧹の
シルエット。「CM」文字ではない）。

## 変更時の絶対条件

- **削除は必ず `FileManager.trashItem`（ゴミ箱へ移動）**。完全削除のコードを
  書かない。これがこのアプリの安全設計の核。
- 対象はユーザー領域のみ。`/System` や `/private/var` などシステム領域を
  スキャン・削除対象に加えない。
- 実行フローは スキャン → サイズ表示 → 選択 → 確認ダイアログ の順を崩さない。

## ソース構成 (`Sources/CleanMac/`)

- `CleanMacApp.swift` — @main エントリ
- `Models/` — CleanupItem, InstalledApp
- `Cleaner/` — キャッシュ/アプリのスキャンとゴミ箱移動ロジック
- `DupPhotos/` — 重複写真エンジン（サイズ→SHA-256 の完全一致 + dHash の類似判定、
  マルチコア並列スキャン）
- `Views/` — SwiftUI 画面 + ViewModel
- `Utils/` — サイズ整形など

## 注意

- 「写真」アプリの `.photoslibrary` 内部は重複写真の対象外（意図的）。
- 一部フォルダはフルディスクアクセスが無いとスキャンできない。失敗は握りつぶさず
  結果に表示する方針。
