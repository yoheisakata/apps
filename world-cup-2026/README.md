# World Cup 2026 Dashboard

FIFA ワールドカップ 2026 (アメリカ・カナダ・メキシコ共催) のダッシュボードアプリ。
GitHub Pages で静的ホスティングし、試合結果を無料のデータソース
(Wikipedia / openfootball / FIFA公式ランキング) だけで自動取得します。
※ 有料 API (Football-Data.org) を使う機能は削除済み。

## 機能

| タブ | 内容 |
|------|------|
| 🇯🇵 日本 | 日本代表ページ (チーム詳細ページの共通フォーマットを利用)。戦績・突破確率・次戦カウントダウン・スカッド |
| 決勝T | 決勝トーナメント表。未確定の枠は Elo ベースのモンテカルロシミュレーション (`predict.js`) で予想 |
| 試合 | 全104試合の日程・結果。今日の試合 (NY東部時間基準)・グループ/ステージ別フィルター |
| 順位表 | グループ A〜L の勝点・得失点差を試合結果から自動集計 |
| チーム | 48チーム一覧 (連盟別・FIFAランキング順)。クリックでチーム詳細ページへ |
| 得点王 | トップスコアラーランキング。選手クリックで Wikipedia プロフィール |
| 参加国 | 世界地図上に48カ国を表示 (Leaflet)。FIFAランキングはライブ取得 |
| 開催都市 | 16開催都市を地図上に国旗マーカーで表示。クリックで都市・スタジアム情報 |

### チーム詳細ページ

各チームをクリックすると、日本代表ページと同じフォーマットで詳細が表示されます:

- ヘッダー: 国旗・チーム名・FIFAランキング・連盟・W/D/L 戦績
- 次の試合までのカウントダウン (試合日には「試合日！」表示)
- グループリーグ突破確率 (モンテカルロシミュレーション)
- グループ順位表
- 全試合日程・結果 (自チームは常に左側に表示)
- 大会得点者・登録メンバー一覧
- 選手名クリックで Wikipedia プロフィール表示

### その他の機能

- **URL ハッシュルーティング**: タブ状態・チームページが URL に反映 (`#teams`, `#country/ESP/teams` 等)。リロードしても同じページに復帰
- **ダークモード**: ヘッダーの 🌙/☀️ ボタンで切替。localStorage に保存
- **試合モーダル**: 試合カードクリックで得点者 (分・PK・OG)・会場情報・ハイライト動画リンクを表示
- **オフライン対応**: 静的 JSON → localStorage キャッシュ → ライブ更新の3段階

## アーキテクチャ

```
ブラウザ (GitHub Pages から配信)
│
├── ① 静的 JSON 読み込み (即表示・オフライン対応)
│     data/teams.json, groups.json, matches.json, venues.json
│
├── ② localStorage キャッシュ復元 (前回のライブデータ)
│     キー: wc2026-livedata-v13
│
└── ③ ライブ更新 (すべて無料・キー不要)
      │
      ├─→ Wikipedia API (メイン)
      │    ・CORS 対応済み。試合結果・決勝Tの勝ち上がりを記事から解析
      │
      ├─→ openfootball worldcup.json (フォールバック + 補完)
      │    ・jsDelivr / GitHub raw から直接取得
      │    ・得点者詳細 (分・PK・OG) や会場を「空のフィールドだけ」補完
      │
      └─→ Cloudflare Worker (/fifa-rankings のみ)
           wc2026-api.yoheisakata.workers.dev
           ・FIFA公式ランキング API の CORS プロキシ (1時間キャッシュ)
```

ライブ更新は Wikipedia を優先し、失敗時に openfootball にフォールバック。
成功時も、もう一方のソースから得点者詳細・会場情報を補完する
(空のフィールドだけを埋め、メインソースのデータは上書きしない)。

### なぜ Cloudflare Worker が必要か

FIFA 公式ランキング API (api.fifa.com) はブラウザからの直接リクエストを
CORS で拒否するため、Worker が CORS ヘッダーを付けて中継します。
API キーは不要で、Cloudflare の無料枠 (10万リクエスト/日) で運用しています。

### Worker のエンドポイント

| パス | 用途 |
|------|------|
| `/fifa-rankings` | FIFA 公式ランキング (api.fifa.com をプロキシ、1時間キャッシュ) |

上記以外のパスは 404 になります。

> かつては有料の Football-Data.org API (`/competitions/WC/*`, `/matches/{id}`)
> もこの Worker でプロキシしていましたが、無料ソースで十分になったため
> 連携ごと削除しました (試合スタッツ表示など Football-Data 専用の機能も廃止)。

### localStorage の役割

ライブデータは毎回 API から取得しますが、取得完了まで数秒かかります。
localStorage にキャッシュしておくことで:

- **初回表示が速い**: 静的 JSON → キャッシュ復元で即座に最新に近いデータを表示
- **API 障害時**: 前回取得したデータで閲覧を継続できる
- **バージョン管理**: キーに `v13` などのバージョンを含め、データ形式を変えたときに
  キーを上げる (`main.js` の `LIVE_CACHE_KEY`)。旧キーは起動時に削除される

## ファイル構成

```
world-cup-2026/
├── index.html              エントリーポイント
├── main.js                 アプリ起動・タブ管理・データ統合・ハッシュルーティング
├── style.css               全スタイル (ダークモード対応)
├── data/
│   ├── teams.json          48チーム情報 (国旗・FIFAランク・連盟等)
│   ├── groups.json         グループ A〜L の組み分け
│   ├── matches.json        全試合データ (初期スナップショット)
│   └── venues.json         16会場の情報 (座標・収容人数等)
├── views/
│   ├── country.js          各チーム詳細ページ (🇯🇵 日本タブもこれを共用)
│   ├── schedule.js         試合日程・結果 + 今日の試合
│   ├── standingstab.js     順位表タブ
│   ├── standings.js        順位計算ロジック (共有)
│   ├── knockout.js         決勝トーナメント表 (決勝T タブ)
│   ├── predict.js          Elo ベース予測エンジン (突破確率・決勝T 予想)
│   ├── rankings.js         得点王ランキング
│   ├── teamlist.js         チーム一覧
│   ├── cities.js           開催都市マップ (Leaflet)
│   ├── world.js            参加国マップ (Leaflet)
│   ├── matchmodal.js       試合詳細モーダル
│   ├── footballapi.js      FIFA ランキング連携 (Worker 経由)
│   ├── openfootball.js     openfootball worldcup.json データソース
│   ├── livedata.js         Wikipedia パーサー + スカッド読み込み
│   ├── wiki.js             Wikipedia 記事・画像取得
│   └── util.js             共有ユーティリティ
├── worker/
│   ├── worker.js           Cloudflare Worker (API プロキシ)
│   └── wrangler.toml       Worker 設定
├── architecture.md         アーキテクチャ図
└── README.md               このファイル
```

## セットアップ

### GitHub Pages (フロントエンド)

特別なビルドは不要です。リポジトリの main ブランチが GitHub Pages で自動配信されます。

### Cloudflare Worker (FIFA ランキングの CORS プロキシ)

API キーやシークレットの設定は不要です。

```bash
cd world-cup-2026/worker
npx wrangler deploy
```

Worker の変更後は `npx wrangler deploy` の再実行が必要です。

## 技術スタック

- **フロントエンド**: Vanilla JS (ES Modules), CSS Custom Properties
- **地図**: Leaflet + CARTO Voyager タイルセット
- **API プロキシ**: Cloudflare Workers
- **データソース**: Wikipedia API / openfootball worldcup.json / FIFA ランキング API (すべて無料・キー不要)
- **ホスティング**: GitHub Pages
- **キャッシュ**: localStorage (クライアント側), Cloudflare Edge (FIFAランキングのみ・1時間)

## 日付・タイムゾーン

「今日の試合」の判定には **ニューヨーク東部時間 (ET)** を基準にしています。
大会が北米で開催されるため、現地時間に合わせた日付判定が適切です。

```javascript
const todayStr = new Intl.DateTimeFormat("en-CA", {
  timeZone: "America/New_York",
}).format(new Date());
```

## バージョンとキャッシュバスター

リリース時に上げるバージョンが3種類あります:

1. **`?v=N` キャッシュバスター** — `index.html` と `main.js` の import に付与。
   変更したファイルの `?v=` を上げる (ファイルごとに番号が異なってよい)
2. **`APP_VERSION`** (`main.js`) — ヘッダーに `vNN` として表示。リリースごとに +1
3. **`LIVE_CACHE_KEY`** (`main.js`) — localStorage のライブデータキー。
   キャッシュするデータの形式を変えたときだけ上げ、旧キーを起動時の削除リストに追加
