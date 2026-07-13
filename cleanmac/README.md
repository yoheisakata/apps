# CleanMac 🧹

macOS 用のシンプルなお掃除アプリ（SwiftUI 製ネイティブ GUI）。
不要なキャッシュの削除、アプリのアンインストール（関連ファイルごと）、
重複写真の検索・整理ができます。

> ⚠️ ネイティブ macOS アプリのため GitHub Pages では動きません
> （networth / renamer などと同じローカルビルドのツール群です）。

## 特長 / 安全設計

- **削除は必ず「ゴミ箱へ移動」**（`FileManager.trashItem`）。完全削除はしないため、
  ゴミ箱を空にするまで復元できます。
- 実行前に必ず **スキャン → サイズ表示 → 選択 → 確認ダイアログ** を挟みます。
- システム領域（`/System`, `/private/var` など）は対象外。ユーザー領域のみを扱います。

## 機能

### 1. キャッシュ掃除
以下を個別に選んでゴミ箱へ移動できます。
- `~/Library/Caches`（ユーザーキャッシュ）
- `~/Library/Logs`（アプリのログ）
- `~/.Trash`（ゴミ箱の中身）
- `~/Library/Developer/Xcode/DerivedData` ほか Xcode 関連（開発者向け）

### 2. アプリ削除（アンインストール）
- `/Applications` と `~/Applications` のアプリを一覧・サイズ表示
- 選択したアプリ本体に加え、`Application Support` / `Preferences` /
  `Caches` / `Containers` などに残る関連ファイルもまとめてゴミ箱へ移動

### 3. 重複写真（Duplicate Photos Fixer Pro の代替）
- 写真の入ったフォルダをドラッグ＆ドロップ（複数可）してスキャン
- **マッチレベル 4 段階**
  - **完全一致** — バイト単位で同一のファイルのみ（サイズ → SHA-256 の二段階判定）
  - **厳密 / 標準 / ゆるい** — 知覚ハッシュ（dHash）のハミング距離で類似画像を検出。
    リサイズ・再圧縮・軽微な編集をされたコピーも見つかる
- グループごとにサムネイル一覧表示（完全一致 / 類似のバッジ、節約可能サイズ付き）
- **残す 1 枚の自動選択** — 解像度最大 / ファイルサイズ最大 / 最新 / 最古 から選べる。
  手動でチェックの付け外しも可能
- 対応形式: JPEG, PNG, HEIC/HEIF, TIFF, GIF, BMP, WebP, 主要 RAW（ARW, CR2/CR3, NEF, RAF, ORF, DNG ほか）
- マルチコア並列スキャン + 進捗バー + キャンセル
- 「写真」アプリのライブラリ（`.photoslibrary`）内部は対象外。ライブラリ内の重複は
  macOS 標準の「写真 → アルバム → 重複項目」を使うこと

## ビルド & 実行

必要環境: macOS 13+ / Swift 6 ツールチェーン（Xcode 同梱）。

```bash
cd apps/cleanmac

# 開発中（ウィンドウが立ち上がる）
swift run

# .app バンドルをその場に作成して起動
./build_app.sh
open CleanMac.app

# /Applications にインストール（ダブルクリックで起動できるようになる）
./install.sh
```

`./install.sh` はビルド → アドホック署名 → `/Applications/CleanMac.app` へコピー →
起動まで一括で行います。以降は **Launchpad / アプリケーションフォルダから
ダブルクリックで起動**できます。更新したいときは再度 `./install.sh` を実行するだけです。

> ローカルビルドなので Gatekeeper には基本ブロックされませんが、もし
> 「開発元を確認できません」と出た場合は、アプリを **右クリック → 開く** を一度だけ実行してください。

## 補足

- `~/Library/Caches` の一部やアプリ本体（App Store 由来など）は
  権限の都合で移動に失敗する場合があります。その旨は実行後に表示されます。
- 一部フォルダのスキャンには **フルディスクアクセス** が必要なことがあります。
  必要に応じて「システム設定 › プライバシーとセキュリティ › フルディスクアクセス」で許可してください。

## 構成

```
Sources/CleanMac/
  CleanMacApp.swift        # @main / アプリのエントリ
  Models/                  # CleanupItem, InstalledApp
  Cleaner/                 # スキャン & ゴミ箱移動ロジック
  DupPhotos/               # 重複写真の検出エンジン（dHash / SHA-256）
  Views/                   # SwiftUI 画面 + ViewModel
  Utils/                   # サイズ整形など
```
