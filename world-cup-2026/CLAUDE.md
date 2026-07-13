# CLAUDE.md — world-cup-2026

FIFA W杯 2026 ダッシュボード。バニラ JS (ES Modules)・ビルド不要。
リポジトリ全体の規約はルートの `CLAUDE.md`、構成の詳細は `README.md` と
`architecture.md` を参照。

## 構成の要点

- `main.js` がタブ状態・データ統合・ハッシュルーティングを持ち、`views/` の
  各ビューを遅延生成する。タブは `VALID_TABS`(japan / knockout / schedule /
  standings / teams / rankings / world / cities)。日本タブは専用ビューではなく
  `country.js` のチーム詳細ページを共用している(`japan.js` は存在しない)。
- ライブデータ: Football-Data.org(Worker プロキシ経由)を優先、失敗時は
  Wikipedia → openfootball の順でフォールバック。成功時も openfootball →
  Wikipedia の順で得点者・会場を「空フィールドのみ」補完する(`refreshLive`)。
- FIFA ランキングは Worker の `/fifa-rankings`(FIFA API プロキシ・1時間キャッシュ)。

## リリース時に上げるバージョン (3種類・用途が違う)

1. `?v=N` — `index.html` / `main.js` の import のキャッシュバスター。変更したファイルだけ上げる
2. `APP_VERSION` (`main.js`) — ヘッダー表示。リリースごとに +1
3. `LIVE_CACHE_KEY` (`main.js`) — ライブデータの localStorage キー。
   **データ形式を変えたときだけ**上げ、旧キーを起動時の removeItem リストに追加する

## Cloudflare Worker (`worker/`)

- 許可リスト方式: `/competitions/WC/(matches|standings|scorers)`, `/matches/{id}`,
  `/fifa-rankings` のみ。新しいパスを使うときは `ALLOWED_PATHS` に追加して
  `npx wrangler deploy` を再実行する。
- Cache API の TTL: 試合/順位 60s、得点者 120s、試合詳細 300s、FIFAランキング 3600s。
- API キーは `FOOTBALL_API_TOKEN`。`npx wrangler secret put FOOTBALL_API_TOKEN` で設定
  (現状 `wrangler.toml` の `[vars]` にも直書きされている点に注意)。

## その他

- 「今日の試合」は America/New_York 基準で判定する。
- チーム名は `data/teams.json` が正。openfootball / Wikipedia 側の表記ゆれは
  各ビューのエイリアス表で吸収している。
