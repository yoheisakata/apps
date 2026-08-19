# World Cup 2026 Dashboard

FIFA ワールドカップ 2026 (アメリカ・カナダ・メキシコ共催) のダッシュボードアプリ。
GitHub Pages で静的ホスティング。**大会は 2026-07-19 の決勝 (スペイン 1-0
アルゼンチン、延長) で終了済み** — 全104試合の最終結果を `data/*.json` に
static に格納しており、ライブデータ取得は行いません。

## 機能

| タブ | 内容 |
|------|------|
| 🇯🇵 日本 | 日本代表ページ (チーム詳細ページの共通フォーマットを利用)。最終成績・スカッド |
| 決勝T | 決勝トーナメント表 (全試合結果確定) |
| 試合 | 全104試合の日程・最終結果。グループ/ステージ別フィルター |
| 順位表 | グループ A〜L の最終勝点・得失点差 |
| チーム | 48チーム一覧 (連盟別・FIFAランキング順、大会終了時点)。クリックでチーム詳細ページへ |
| 得点王 | 最終得点者ランキング (優勝: Mbappé 10得点)。選手クリックで Wikipedia プロフィール |
| 参加国 | 世界地図上に48カ国を表示 (Leaflet) |
| 開催都市 | 16開催都市を地図上に国旗マーカーで表示。クリックで都市・スタジアム情報 |

### チーム詳細ページ

各チームをクリックすると、日本代表ページと同じフォーマットで詳細が表示されます:

- ヘッダー: 国旗・チーム名・FIFAランキング・連盟・W/D/L 最終成績
- グループ順位表
- 全試合日程・結果 (自チームは常に左側に表示)
- 大会得点者・登録メンバー一覧
- 選手名クリックで Wikipedia プロフィール表示

### その他の機能

- **URL ハッシュルーティング**: タブ状態・チームページが URL に反映 (`#teams`, `#country/ESP/teams` 等)。リロードしても同じページに復帰
- **ダークモード**: ヘッダーの 🌙/☀️ ボタンで切替。localStorage に保存
- **試合モーダル**: 試合カードクリックで得点者 (分・PK・OG)・会場情報を表示

## アーキテクチャ

```
ブラウザ (GitHub Pages から配信)
│
└── 静的 JSON 読み込みのみ (即表示・完全オフライン対応)
      data/teams.json, groups.json, matches.json, venues.json
```

ライブ取得の仕組み (Wikipedia / openfootball / FIFA ランキング Worker) は
大会終了に伴い削除しました。最終結果は起動時に一度だけ Node スクリプトで
取得・マージし、`data/*.json` に焼き込んであります (決勝のみ、フリーソースの
反映待ちだったため手動で確定)。当時のライブ取得ロジックは git 履歴
(`views/livedata.js` の `fetchLiveData`、`views/openfootball.js`、
`views/footballapi.js`、`worker/`) に残っています。

## ファイル構成

```
world-cup-2026/
├── index.html              エントリーポイント
├── main.js                 アプリ起動・タブ管理・静的データ読み込み・ハッシュルーティング
├── style.css                全スタイル (ダークモード対応)
├── data/
│   ├── teams.json          48チーム情報 (国旗・最終FIFAランク・連盟等)
│   ├── groups.json         グループ A〜L の最終組み分け
│   ├── matches.json        全104試合の最終結果
│   └── venues.json         16会場の情報 (座標・収容人数等)
├── views/
│   ├── country.js          各チーム詳細ページ (🇯🇵 日本タブもこれを共用)
│   ├── schedule.js         試合日程・結果
│   ├── standingstab.js     順位表タブ
│   ├── standings.js        順位計算ロジック (共有)
│   ├── knockout.js         決勝トーナメント表 (決勝T タブ)
│   ├── predict.js          Elo ベース予測エンジン (当時の突破確率シミュレーション用、参照実装として残存)
│   ├── rankings.js         得点王ランキング
│   ├── teamlist.js         チーム一覧
│   ├── cities.js           開催都市マップ (Leaflet)
│   ├── world.js             参加国マップ (Leaflet)
│   ├── matchmodal.js       試合詳細モーダル
│   ├── livedata.js         Wikipedia スカッド読み込み + スコアラー名マッチング (試合結果ライブ取得部分は削除済み)
│   ├── wiki.js              Wikipedia 記事・画像取得
│   └── util.js               共有ユーティリティ
├── architecture.md         アーキテクチャ図
└── README.md               このファイル
```

## セットアップ

特別なビルドは不要です。リポジトリの main ブランチが GitHub Pages で自動配信されます。

## 技術スタック

- **フロントエンド**: Vanilla JS (ES Modules), CSS Custom Properties
- **地図**: Leaflet + CARTO Voyager タイルセット
- **データ**: `data/*.json` に焼き込んだ最終結果 (ネットワーク取得なし)
- **ホスティング**: GitHub Pages

## バージョンとキャッシュバスター

リリース時に上げるバージョンが2種類あります:

1. **`?v=N` キャッシュバスター** — `index.html` と `main.js` の import に付与。
   変更したファイルの `?v=` を上げる (ファイルごとに番号が異なってよい)
2. **`APP_VERSION`** (`main.js`) — ヘッダーに `vNN` として表示。リリースごとに +1
