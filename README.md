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

### 🐘 PostgreSQL 強化書 — `pgquiz/`
PostgreSQL 17以降を対象にした、クイズ／フラッシュカード形式の学習アプリ。全104問・13カテゴリ（基本概念・データ型・インデックス・クエリ最適化・JSON/JSONB・パーティション/レプリケーション・バキューム/運用・セキュリティ/権限・内部構造・高度なSQL・運用チートシート・17の新機能・18の新機能）。

### ☁️ AWS SAP 対策 — `awsquiz/`
AWS Certified Solutions Architect – Professional (SAP-C02) の対策アプリ（PWA）。全202問・4ドメイン・15技術分野。
- 今日の練習（苦手・未着手を優先）／分野別クイズ／まちがい復習／模擬試験／フラッシュカードの5モード
- 模擬試験は本番形式 75問・180分（ハーフ40問・95分も可）。出題比率も本番どおりで、1000点換算のスコア目安とドメイン別正答率が出る
- **用語集**（183語）を搭載。カタカナ・略語・英語名のどれでも検索でき、クイズを解いている途中でも 📖 ボタンから引ける
- 試験日カウントダウン・1日の目標達成リング・連続学習日数・ドメイン別の到達度を表示（記録は端末の `localStorage` のみ）
- 出題範囲は公式試験ガイドのタスクステートメントと突き合わせ済み。ガイドに新設された Emerging Topics（生成AI の統制）にも対応

### ⚽ ワールドカップ 2026 — `world-cup-2026/`
FIFA ワールドカップ 2026 のダッシュボード。日本代表ページ・決勝トーナメント表・全試合日程・順位表・チーム詳細・得点王・参加国/開催都市マップ（Leaflet）の8タブ構成。
大会は 2026-07-19 に終了（決勝: スペイン 1-0 アルゼンチン）したため、現在は**完全な静的アーカイブ**です。全104試合の結果は `data/*.json` に取り込み済みで、外部からのライブ取得は行いません。

---

## 🖥️ macOS ネイティブアプリ（GitHub Pages 対象外）

SwiftUI / Swift Package Manager 製のローカル専用ツール群。ビルドして `/Applications/MyApplications/` にインストールして使う、Webランチャーには載らないアプリです。

### 🗂️ MyOrganizer — `myorganizer/`
写真・動画のバックアップ整理（日付フォルダへの振り分け、H.265再エンコード、rsync同期）、
ファイル一括リネーム、キャッシュ掃除・不要アプリ削除、重複動画の検出、
子ども動画のまとめ動画作成などをまとめたメディア管理アプリ。旧`cleanmac`／`renamer`／
`omoide`アプリを統合済み。

### 🖼️ MyGallery — `mygallery/`
Photos.app 風のローカルフォルダ・フォトギャラリー（Swift + AppKit の単一ソース、依存なし）。
ライブラリへの取り込みをせず、指定したフォルダ配下を再帰スキャンして閲覧・整理する。
サムネイルグリッド／フルサイズビューア／重複検出（SHA-256〜dHash の4段階）／
人物・種類・日付でのフィルター（Vision、オンデバイス）に対応。

### 🎵 MyMusic — `mymusic/`
iTunes/ミュージック.app 風の3ペイン構成（上部トランスポート＋ライブラリサイドバー＋曲リスト）の
音楽プレーヤー。YouTube・Suno・MusicCreator.ai・MusicGPT などの曲リンクを貼り付けるほか、
OneDrive の共有リンクを丸ごと取り込んでフォルダ単位で再生できる。ウィンドウを閉じても再生は続く。

### 📺 MyTube — `mytube/`
フォルダ内の動画を YouTube 風の見た目で見る動画プレイヤー。ローカルフォルダ・OneDrive共有リンク・
YouTubeプレイリストを同時に開いて1つのライブラリとして扱い、サムネイルグリッドから連続再生できる。

### 🎮 MyGames — `mygames/`
NES（ファミコン）／SNES（スーパーファミコン）のエミュレータ。libretro API 準拠のコア（.dylib）を
実行時に読み込んで動作する。ライブラリ／ROM／コントローラー／ボードゲームの4タブ構成で、
将棋・チェス・オセロ・囲碁・五目並べ・麻雀・ダイヤモンドゲーム（AI対戦あり）の旧`boardgames`アプリを
「ボードゲーム」タブとして統合済み。

### 🔑 MyPass — `mypass/`
マスターパスワード1つでログイン情報をまとめて暗号化・管理するパスワード管理アプリ。
保存されるのは暗号化された1つの Blob のみ（詳細は `mypass/README.md`）。

### 💰 MyNetWorth — `mynetworth/`
SimpleFIN 経由で複数の銀行・証券口座を集約する資産トラッカー（macOS 26+）。メイン／週／月／投資／固定収支／レシートの6タブ構成で、純資産の推移・支出アラート・保有銘柄（Yahoo Finance の現在株価で時価補正）・固定収支表（Markdown）・Schedule C 向けレシート管理（Vision OCR + オンデバイス LLM）まで1つのアプリにまとめている。`--fetch` オプションで launchd による毎朝の自動記録に対応。

### ⬇️ MyDownloader — `mydownloader/`
`yt-dlp` / `ffmpeg` を内部で呼び出して YouTube の動画・音声（単発／プレイリスト）を
ダウンロードするアプリ。旧`youtube-dl-mac`を統合したもの。
トレント機能（旧`torrent-dl-mac`由来の「Torrent」タブ）は 2026-08-12 に削除した。

### 📲 Kindle Fire → Mac 転送ツール — `kindle-transfer/`
`adb` を使って Kindle Fire の SD カード・内部ストレージの中身を Mac にまるごとコピーする対話型 Terminalスクリプト。

### 🗂️ utilities — `utilities/`
写真・動画のバックアップ整理、H.265再エンコード、短尺動画の検出などを行う、個人の写真/動画パイプライン用 Python / シェルスクリプト集（アプリではなくスクリプト置き場）。

---

## 技術スタック

| アプリ | 構成 |
|--------|------|
| ちきゅう／新幹線／タロット／PostgreSQL強化書 | 単一HTMLファイル（HTML / CSS / JavaScript、ビルド不要） |
| まなびアプリ | バニラ JS（複数ファイル）+ Service Worker（PWA・オフライン対応） |
| ワールドカップ 2026 | バニラ JS（ES module）+ 静的 JSON データ |
| MyOrganizer／MyMusic／MyTube／MyGames／MyPass／MyNetWorth／MyDownloader | SwiftUI + Swift Package Manager（ローカルビルド、ad-hoc署名） |
| MyGallery | Swift + AppKit（単一ソースファイル、ローカルビルド、ad-hoc署名） |
| kindle-transfer | Bash + adb |
| utilities | Python 3 / Bash スクリプト |

ほとんどの**Webアプリ**はビルド不要で、HTML ファイルをブラウザで開くだけで動きます。**macOSネイティブアプリ**はローカルでビルドし、`/Applications/MyApplications/` にインストールして使います（詳細は各フォルダの README）。

---

## デプロイ

`main` ブランチから GitHub Pages で自動公開されます（push すると反映）。対象はWebアプリのみです。
- macOSネイティブアプリ（myorganizer / mygallery / mymusic / mytube / mygames / mypass / mynetworth / mydownloader / kindle-transfer）は GitHub Pages にはデプロイされません。各フォルダの `./install.sh`（mygallery のみ `./build.sh`）でローカルビルドし、`/Applications/MyApplications/` にインストールして使います。

## アプリの追加・削除

Webアプリをランチャーに反映するには、ルート `index.html` を編集します（詳細は [CLAUDE.md](CLAUDE.md) を参照）。macOSネイティブアプリはランチャーには登録しません。
