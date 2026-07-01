# CleanMac 🧹

macOS 用のシンプルなお掃除アプリ（SwiftUI 製ネイティブ GUI）。
不要なキャッシュの削除と、アプリのアンインストール（関連ファイルごと）ができます。

> ⚠️ このリポジトリの他アプリは Web アプリですが、CleanMac だけは
> ネイティブ macOS アプリのため GitHub Pages では動きません。ローカルでビルドして使います。

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

## ビルド & 実行

必要環境: macOS 13+ / Swift 6 ツールチェーン（Xcode 同梱）。

```bash
cd apps/cleanmac

# 開発中（ウィンドウが立ち上がる）
swift run

# .app バンドルを作成して起動
./build_app.sh
open CleanMac.app
```

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
  Views/                   # SwiftUI 画面 + ViewModel
  Utils/                   # サイズ整形など
```
