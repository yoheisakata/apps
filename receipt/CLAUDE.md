# CLAUDE.md — receipt

単一 HTML ファイルのレシート整理アプリ（日本の確定申告向け）。ビルドなし。
共通規約はルートの `CLAUDE.md` を参照。

- 抽出は Claude API を**ブラウザから直接**呼ぶ（`api.anthropic.com/v1/messages`、
  モデル `claude-haiku-4-5`、`anthropic-dangerous-direct-browser-access: true`）。
  API キーは利用者入力で `localStorage` 保存 — **リポジトリにキーを書かない**。
- データ: `localStorage` の `receipts_v2`（レシート）と `receipt_settings`（設定）。
  `receipts_v2` の形式を変えるときは旧データの移行を書く（v2 という名前が既に
  その歴史）。
- クラウド同期は Firebase compat SDK（CDN・v10.x）+ 利用者持ち込みの
  firebaseConfig。アプリ名 `'receipt'` で initializeApp している。
- **networth のレシートタブ（Schedule C・FoundationModels）とは無関係**。
  混同して片方の変更をもう片方に持ち込まない。
