# CLAUDE.md — world-cup-2026

FIFA W杯 2026 ダッシュボード。バニラ JS (ES Modules)・ビルド不要。
リポジトリ全体の規約はルートの `CLAUDE.md`、構成の詳細は `README.md` と
`architecture.md` を参照。

## 構成の要点

- `main.js` がタブ状態・データ統合・ハッシュルーティングを持ち、`views/` の
  各ビューを遅延生成する。タブは `VALID_TABS`(japan / knockout / schedule /
  standings / teams / rankings / world / cities)。日本タブは専用ビューではなく
  `country.js` のチーム詳細ページを共用している(`japan.js` は存在しない)。
- ライブデータ: **無料ソースのみ**。Wikipedia を優先、失敗時は openfootball に
  フォールバック。成功時ももう一方のソースで得点者・PK・会場などを
  「空フィールドのみ」補完する(`refreshLive`)。**有料の Football-Data.org
  連携は削除済み** — 再導入しない(試合スタッツ表示なども一緒に廃止した)。
- FIFA ランキングは Worker の `/fifa-rankings`(FIFA API プロキシ・1時間キャッシュ)。

## 決勝トーナメントの落とし穴 (過去に実際に壊れた)

- Wikipedia の **R32 は独立記事** (`2026 FIFA World Cup round of 32`) にあり、
  knockout stage 記事は `{{#lst:}}` で参照するだけ(生 wikitext には展開されない)。
  livedata.js は両方の記事を取得して連結パースする。
- football box テンプレートは記事によって `Football box`(大文字)と
  `football box` が混在する — パーサーの正規表現は `[Ff]` で両対応。
- **2026 のブラケットはクロス対戦**(例: Match 89 = W74 × W77)。日付順・記事順の
  「隣接畳み込み」では対戦が狂う。公式の結線は knockout.js の `KO_FEED`
  (公式試合番号 73〜104 ベース)にハードコードされており、試合の `matchNo` は
  openfootball の `num` からチームペア照合でコピーされる。
  **位置(インデックス)ベースでチームや結果を別ソースからコピーしない**こと。
- PK 決着の判定: Wikipedia は `|penaltyscore=`、openfootball は `score.p` を持つ。
  どちらかが無いと引き分けタイの勝者をブラケットに畳み込めない。

## リリース時に上げるバージョン (3種類・用途が違う)

1. `?v=N` — `index.html` / `main.js` の import のキャッシュバスター。変更したファイルだけ上げる
2. `APP_VERSION` (`main.js`) — ヘッダー表示。リリースごとに +1
3. `LIVE_CACHE_KEY` (`main.js`) — ライブデータの localStorage キー。
   **データ形式を変えたときだけ**上げ、旧キーを起動時の removeItem リストに追加する

## Cloudflare Worker (`worker/`)

- `/fifa-rankings`(FIFA 公式ランキングの CORS プロキシ・Cache API 3600s)だけを
  提供する。それ以外のパスは 404。API キー・シークレットは不要。
- 変更したら `npx wrangler deploy` を再実行する。

## その他

- 「今日の試合」は America/New_York 基準で判定する。
- チーム名は `data/teams.json` が正。openfootball / Wikipedia 側の表記ゆれは
  各ビューのエイリアス表で吸収している。
