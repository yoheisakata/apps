# CLAUDE.md — world-cup-2026

FIFA W杯 2026 ダッシュボード。バニラ JS (ES Modules)・ビルド不要。
リポジトリ全体の規約はルートの `CLAUDE.md`、構成の詳細は `README.md` と
`architecture.md` を参照。

**大会は 2026-07-19 の決勝(スペイン 1-0 アルゼンチン、延長)で終了済み。
このアプリは完全に静的なアーカイブ — ライブデータ取得・Cloudflare Worker・
localStorage キャッシュは全部削除済み。データは `data/*.json` が正で、以後は
編集しない限り変わらない。**

## 構成の要点

- `main.js` がタブ状態・ハッシュルーティングを持ち、起動時に `data/*.json` を
  一度読み込んで `views/` の各ビューを遅延生成する。タブは `VALID_TABS`
  (japan / knockout / schedule / standings / teams / rankings / world / cities)。
  日本タブは専用ビューではなく `country.js` のチーム詳細ページを共用している
  (`japan.js` は存在しない)。
- `views/livedata.js` には Wikipedia スカッド読み込み + スコアラー名マッチングの
  ヘルパーだけが残っている(`fetchLiveData` などの試合結果ライブ取得ロジックは
  削除済み)。openfootball.js・footballapi.js・worker/ も削除済み — 復活させない
  こと(git 履歴には残っているので、参照だけなら見られる)。

## 決勝トーナメントの落とし穴 (過去に実際に壊れた・data/matches.json 手動編集時にも該当)

- **2026 のブラケットはクロス対戦**(例: Match 89 = W74 × W77)。日付順・記事順の
  「隣接畳み込み」では対戦が狂う。公式の結線は knockout.js の `KO_FEED`
  (公式試合番号 73〜104 ベース)にハードコードされている。
  **位置(インデックス)ベースでチームや結果を別ソースからコピーしない**こと。
- PK 決着の判定は `penalties` フィールド(`[home, away]`)。引き分けタイの勝者を
  ブラケットに畳み込むのに必須。

## リリース時に上げるバージョン (2種類・用途が違う)

1. `?v=N` — `index.html` / `main.js` の import のキャッシュバスター。変更したファイルだけ上げる
2. `APP_VERSION` (`main.js`) — ヘッダー表示。リリースごとに +1

## その他

- 「今日の試合」は America/New_York 基準で判定する(過去の試合表示にのみ影響)。
- チーム名は `data/teams.json` が正。
