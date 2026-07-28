# My Apps 🎮

スマホブラウザで遊べる、子ども向けの学習・ゲームアプリと実用ツールのコレクションです。
ルートの `index.html` がランチャー（ホーム画面）で、各アプリへのリンクを1つのアイコングリッドにまとめています（カテゴリ分けなし）。GitHub Pages で公開しています。

---

## 📱 Webアプリ

### 🌟 まなびアプリ — `kids-learning-app/`
たしざん・くく（かけ算）・ひらがな・タイピングを練習できる子ども向け学習アプリ（PWA）。正解すると⭐スターがたまる。
- たしざん：難易度別（レベル1〜5）の3択問題、絵文字による数の視覚化
- くく（かけざん）：段ごとの九九学習カード、音声読み上げ付き
- ひらがな：行ごとの4択クイズ／タイピング：ローマ字入力練習

### 🌏 ちきゅうをまなぼう — `earth/`
地球や自然について学べる子ども向け学習アプリ。

### 🚄 新幹線マップ — `shinkansen/`
日本の新幹線の路線をマップで見られるアプリ。

### 🔮 タロット占い — `tarot/`
タロットカードによる占いアプリ。カードの意味を学べる **タロットクイズ**（`tarot/quiz.html`）付き。

### 🐘 PostgreSQL まなびカード — `pgquiz/`
PostgreSQL 17以降を対象にした、クイズ／フラッシュカード形式の学習アプリ。全56問・8カテゴリ（基本概念・インデックス・クエリ最適化・JSON/JSONB・パーティション/レプリケーション・バキューム/運用・高度なSQL・17の新機能）。

### ⚽ ワールドカップ 2026 — `world-cup-2026/`
FIFA ワールドカップ 2026 のダッシュボード。日本代表ページ・決勝トーナメント表・全試合日程・順位表・チーム詳細・得点王・参加国/開催都市マップ（Leaflet）の8タブ構成。
試合データは **無料ソースのみ**（Wikipedia + openfootball）で取得し、FIFA公式ランキングだけ **Cloudflare Worker**（`world-cup-2026/worker/`）を CORS プロキシとして経由します。有料 API は使いません。

---

## 🖥️ macOS ネイティブアプリ（GitHub Pages 対象外）

SwiftUI / Swift Package Manager 製のローカル専用ツール群。ビルドして `/Applications` にインストールして使う、Webランチャーには載らないアプリです。

### 🗂️ Organizer — `organizer/`
写真・動画のバックアップ整理（日付フォルダへの振り分け、H.265再エンコード、rsync同期）、
ファイル一括リネーム、キャッシュ掃除・不要アプリ削除、重複写真・重複動画の検出、
子ども動画のまとめ動画作成などをまとめたメディア管理アプリ。旧`cleanmac`／`renamer`／
`omoide`アプリを統合済み。

### 💰 NetWorth — `networth/`
SimpleFIN 経由で複数の銀行・証券口座を集約する資産トラッカー（macOS 26+）。メイン／週／月／投資／固定収支／レシートの6タブ構成で、純資産の推移・支出アラート・保有銘柄（Yahoo Finance の現在株価で時価補正）・固定収支表（Markdown）・Schedule C 向けレシート管理（Vision OCR + オンデバイス LLM）まで1つのアプリにまとめている。`--fetch` オプションで launchd による毎朝の自動記録に対応。

### ⬇️ Downloader — `downloader/`
`yt-dlp` / `ffmpeg` を内部で呼び出す YouTube ダウンロードと、`aria2c` を使ったトレント
ダウンロードをメニューバー常駐アプリでまとめて扱う。旧`youtube-dl-mac`／`torrent-dl-mac`
アプリを統合済み。

### 📲 Kindle Fire → Mac 転送ツール — `kindle-transfer/`
`adb` を使って Kindle Fire の SD カード・内部ストレージの中身を Mac にまるごとコピーする対話型 Terminalスクリプト。

### 🗂️ utilities — `utilities/`
写真・動画のバックアップ整理、H.265再エンコード、短尺動画の検出などを行う、個人の写真/動画パイプライン用 Python / シェルスクリプト集（アプリではなくスクリプト置き場）。

---

## 技術スタック

| アプリ | 構成 |
|--------|------|
| ちきゅう／新幹線／タロット／PostgreSQLまなびカード | 単一HTMLファイル（HTML / CSS / JavaScript、ビルド不要） |
| まなびアプリ | バニラ JS（複数ファイル）+ Service Worker（PWA・オフライン対応） |
| ワールドカップ 2026 | バニラ JS（ES module）+ JSON データ + Cloudflare Worker（API プロキシ） |
| Organizer／NetWorth／Downloader | SwiftUI + Swift Package Manager（ローカルビルド、ad-hoc署名） |
| kindle-transfer | Bash + adb |
| utilities | Python 3 / Bash スクリプト |

ほとんどの**Webアプリ**はビルド不要で、HTML ファイルをブラウザで開くだけで動きます。**macOSネイティブアプリ**はローカルでビルドし、`/Applications` にインストールして使います（詳細は各フォルダの README）。

---

## デプロイ

`main` ブランチから GitHub Pages で自動公開されます（push すると反映）。対象はWebアプリのみです。
- ワールドカップ 2026 の Cloudflare Worker のみ、`world-cup-2026/worker/` から Wrangler で個別にデプロイします。
- macOSネイティブアプリ（organizer / networth / downloader / kindle-transfer）は GitHub Pages にはデプロイされません。各フォルダの `./install.sh` でローカルビルドし、`/Applications` にインストールして使います。

## アプリの追加・削除

Webアプリをランチャーに反映するには、ルート `index.html` を編集します（詳細は [CLAUDE.md](CLAUDE.md) を参照）。macOSネイティブアプリはランチャーには登録しません。
