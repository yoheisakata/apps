# アプリひろば 🎮

スマホブラウザで遊べる、子ども向けの学習・ゲームアプリと実用ツールのコレクションです。
ルートの `index.html` がランチャー（ホーム画面）で、各アプリへのリンクをまとめています。GitHub Pages で公開しています。

---

## 🕹️ ゲーム

### ⚔️ たしざんクエスト — `tashizan/`
足し算を解いて勇者を育てる学習RPG。問題に正解すると経験値とコインがもらえ、モンスターとバトルできます。
- レベルアップ・装備ショップ・セーブ機能
- 効果音と実績（じつりょく）システム
- 段階的に上がる難易度

### ✖️ かけざんクエスト — `kakeizan/`
5歳〜向けの九九（かけ算）学習アプリ。「くくをおぼえよう」をコンセプトに、楽しく九九を覚えられます。

### 🌏 ちきゅうをまなぼう — `earth/`
地球や自然について学べる子ども向け学習アプリ。

### 🚄 新幹線マップ — `shinkansen/`
日本の新幹線の路線をマップで見られるアプリ。

---

## 📚 まなぶ

### 🔮 タロット占い — `tarot/`
タロットカードによる占いアプリ。カードの意味を学べる **タロットクイズ**（`tarot/quiz.html`）付き。

### 🌐 TCP/IP シミュレーター — `tcpip/`
TCP/IP 通信を可視化する学習アプリ。3ウェイハンドシェイクや、データのカプセル化／非カプセル化の流れをインタラクティブに確認できます。

### ⚽ ワールドカップ 2026 — `world-cup-2026/`
FIFA ワールドカップ 2026 のダッシュボード。日本代表ページ・決勝トーナメント表・全試合日程・順位表・チーム詳細・得点王・参加国/開催都市マップ（Leaflet）の8タブ構成。
試合データは **無料ソースのみ**（Wikipedia + openfootball）で取得し、FIFA公式ランキングだけ **Cloudflare Worker**（`world-cup-2026/worker/`）を CORS プロキシとして経由します。有料 API は使いません。

---

## 🛠️ ツール

### 🧾 レシート確定申告 — `receipt/`
レシートを撮影して Claude API（利用者が自分の API キーを設定）で内容を抽出し、確定申告向けに整理するツール。
Firebase（Auth + Firestore）でデバイス間のクラウド同期に対応（Firebase 設定は利用者が用意）。
※ macOS ネイティブの NetWorth「レシート」タブ（Schedule C 向け）とは別物。

---

## 🖥️ macOS ネイティブアプリ（GitHub Pages 対象外）

SwiftUI / Swift Package Manager 製のローカル専用ツール群。ビルドして `/Applications` にインストールして使う、Webランチャーには載らないアプリです。

### 🧹 CleanMac — `cleanmac/`
キャッシュ・不要アプリの削除（ゴミ箱経由）と、重複写真の検出・整理を行う掃除アプリ。

### 💰 NetWorth — `networth/`
SimpleFIN 経由で複数の銀行・証券口座を集約する資産トラッカー（macOS 26+）。メイン／週／月／投資／固定収支／レシートの6タブ構成で、純資産の推移・支出アラート・保有銘柄（Yahoo Finance の現在株価で時価補正）・固定収支表（Markdown）・Schedule C 向けレシート管理（Vision OCR + オンデバイス LLM）まで1つのアプリにまとめている。`--fetch` オプションで launchd による毎朝の自動記録に対応。

### ✏️ Renamer — `renamer/`
検索置換・連番・EXIF日付・音楽メタデータなど多彩なルールを組み合わせて使えるファイル一括リネームアプリ（Better Rename の代替）。

### ⬇️ YouTube-downloader — `youtube-dl-mac/`
`yt-dlp` / `ffmpeg` を内部で呼び出し、YouTube の動画・音声をダウンロードするデスクトップアプリ。

### 📲 Kindle Fire → Mac 転送ツール — `kindle-transfer/`
`adb` を使って Kindle Fire の SD カード・内部ストレージの中身を Mac にまるごとコピーする対話型 Terminalスクリプト。

### 🎬 KidsVideoMaker — `KidsVideoMaker/`
子どもの動画フォルダから短いクリップをまとめて1本にする Xcode（SwiftUI）製アプリ。

### 🗂️ utilities — `utilities/`
写真・動画のバックアップ整理、H.265再エンコード、短尺動画の検出などを行う、個人の写真/動画パイプライン用 Python / シェルスクリプト集（アプリではなくスクリプト置き場）。

---

## 技術スタック

| アプリ | 構成 |
|--------|------|
| たしざん／かけざん／ちきゅう／新幹線／タロット／TCP-IP | 単一HTMLファイル（HTML / CSS / JavaScript、ビルド不要） |
| ワールドカップ 2026 | バニラ JS（ES module）+ JSON データ + Cloudflare Worker（API プロキシ） |
| レシート確定申告 | 単一HTMLファイル + Firebase（Auth / Firestore） |
| CleanMac／NetWorth／Renamer／YouTube-downloader | SwiftUI + Swift Package Manager（ローカルビルド、ad-hoc署名） |
| KidsVideoMaker | SwiftUI + Xcode プロジェクト |
| kindle-transfer | Bash + adb |
| utilities | Python 3 / Bash スクリプト |

ほとんどの**Webアプリ**はビルド不要で、HTML ファイルをブラウザで開くだけで動きます。**macOSネイティブアプリ**はローカルでビルドし、`/Applications` にインストールして使います（詳細は各フォルダの README）。

---

## デプロイ

`main` ブランチから GitHub Pages で自動公開されます（push すると反映）。対象はWebアプリのみです。
- ワールドカップ 2026 の Cloudflare Worker のみ、`world-cup-2026/worker/` から Wrangler で個別にデプロイします。
- macOSネイティブアプリ（cleanmac / networth / renamer / youtube-dl-mac / KidsVideoMaker）は GitHub Pages にはデプロイされません。各フォルダの `install.sh`（networth は `build_app.sh` + `cp -R NetWorth.app /Applications/`、KidsVideoMaker は Xcode）でローカルビルドし、`/Applications` にインストールして使います。

## アプリの追加・削除

Webアプリをランチャーに反映するには、ルート `index.html` を編集します（詳細は [CLAUDE.md](CLAUDE.md) を参照）。macOSネイティブアプリはランチャーには登録しません。
