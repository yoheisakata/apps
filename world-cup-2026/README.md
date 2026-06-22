# World Cup 2026 Dashboard

FIFA ワールドカップ 2026 (アメリカ・カナダ・メキシコ共催) のダッシュボードアプリ。
GitHub Pages で静的ホスティングし、試合結果・スタッツをリアルタイムで自動取得します。

## 機能

| タブ | 内容 |
|------|------|
| 🇯🇵 日本 | 日本代表専用ページ。戦績・突破確率・次戦カウントダウン・スカッド |
| 試合 | 全104試合の日程・結果。今日の試合 (NY東部時間基準)・グループ/ステージ別フィルター |
| 順位表 | グループ A〜L の勝点・得失点差を試合結果から自動集計 |
| 優勝予想 | Elo ベースのモンテカルロシミュレーションによるトーナメント表 |
| チーム | 48チーム一覧 (連盟別・FIFAランキング順)。クリックでチーム詳細ページへ |
| 得点王 | トップスコアラーランキング TOP10。選手クリックで Wikipedia プロフィール |
| 参加国 | 世界地図上に48カ国を表示 (Leaflet) |
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
- **試合モーダル**: 試合カードクリックで得点者・分・アシスト・スタッツ・審判情報を表示
- **オフライン対応**: 静的 JSON → localStorage キャッシュ → ライブ更新の3段階

## アーキテクチャ

```
ブラウザ (GitHub Pages から配信)
│
├── ① 静的 JSON 読み込み (即表示・オフライン対応)
│     data/teams.json, groups.json, matches.json, venues.json
│
├── ② localStorage キャッシュ復元 (前回のライブデータ)
│     キー: wc2026-livedata-v6
│
└── ③ ライブ更新
      │
      ├─→ Cloudflare Worker (プロキシ)  ─→  Football-Data.org API (v4)
      │    wc2026-api.yoheisakata.workers.dev
      │    ・CORS ヘッダー付与
      │    ・API キーをサーバー側で管理
      │    ・60秒キャッシュ
      │
      └─→ Wikipedia API (フォールバック)
           ・CORS 対応済み
           ・試合結果を記事から解析
```

### なぜ Cloudflare Worker が必要か

Football-Data.org API には2つの制約があります:

1. **CORS**: ブラウザからの直接リクエストを拒否
2. **API キー**: 認証トークンが必要 (ブラウザの JS に埋め込むと公開されてしまう)

Cloudflare Worker がプロキシとして中継し、サーバー側で API キーを付与して転送します。
Worker は Cloudflare の無料枠 (10万リクエスト/日) で運用しています。

### Football-Data.org API エンドポイント

| パス | 用途 |
|------|------|
| `/competitions/WC/matches` | 全試合の日程・結果・スコア |
| `/competitions/WC/standings` | グループ順位表 |
| `/competitions/WC/scorers` | 得点ランキング (得点王ページ用) |
| `/matches/{id}` | 個別試合の詳細 (ゴール詳細・スタッツ・審判) |

### localStorage の役割

ライブデータは毎回 API から取得しますが、取得完了まで数秒かかります。
localStorage にキャッシュしておくことで:

- **初回表示が速い**: 静的 JSON → キャッシュ復元で即座に最新に近いデータを表示
- **API 障害時**: 前回取得したデータで閲覧を継続できる
- **バージョン管理**: キーに `v6` を含め、バージョンアップ時に古いキャッシュを自動削除

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
│   ├── japan.js            日本代表ページ
│   ├── country.js          各チーム詳細ページ (japan.js と同形式)
│   ├── schedule.js         試合日程・結果 + 今日の試合
│   ├── standingstab.js     順位表タブ
│   ├── standings.js        順位計算ロジック (共有)
│   ├── bracket.js          優勝予想トーナメント表
│   ├── predict.js          Elo ベース予測エンジン
│   ├── rankings.js         得点王ランキング
│   ├── teamlist.js         チーム一覧
│   ├── cities.js           開催都市マップ (Leaflet)
│   ├── world.js            参加国マップ (Leaflet)
│   ├── matchmodal.js       試合詳細モーダル
│   ├── footballapi.js      Football-Data.org API 連携
│   ├── livedata.js         Wikipedia パーサー + スカッド読み込み
│   └── wiki.js             Wikipedia 記事・画像取得
├── worker/
│   ├── worker.js           Cloudflare Worker (API プロキシ)
│   └── wrangler.toml       Worker 設定
├── architecture.md         アーキテクチャ図
└── README.md               このファイル
```

## セットアップ

### GitHub Pages (フロントエンド)

特別なビルドは不要です。リポジトリの main ブランチが GitHub Pages で自動配信されます。

### Cloudflare Worker (API プロキシ)

```bash
cd world-cup-2026/worker

# Football-Data.org の API キーを設定
npx wrangler secret put FOOTBALL_API_TOKEN

# デプロイ
npx wrangler deploy
```

Worker の変更 (新しい API パスの追加等) 後は `npx wrangler deploy` の再実行が必要です。

## 技術スタック

- **フロントエンド**: Vanilla JS (ES Modules), CSS Custom Properties
- **地図**: Leaflet + CARTO Voyager タイルセット
- **API プロキシ**: Cloudflare Workers
- **データソース**: Football-Data.org API v4 / Wikipedia API
- **ホスティング**: GitHub Pages
- **キャッシュ**: localStorage (クライアント側), Cloudflare Edge (サーバー側 60秒)

## 日付・タイムゾーン

「今日の試合」の判定には **ニューヨーク東部時間 (ET)** を基準にしています。
大会が北米で開催されるため、現地時間に合わせた日付判定が適切です。

```javascript
const todayStr = new Intl.DateTimeFormat("en-CA", {
  timeZone: "America/New_York",
}).format(new Date());
```

## キャッシュバスター

ブラウザキャッシュが古い JS を配信し続ける問題を防ぐため、
全 JS/CSS ファイルの import に `?v=6` のバージョンパラメータを付与しています。
コードを更新した際はバージョン番号を上げてください。
