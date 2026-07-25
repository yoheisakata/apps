# CLAUDE.md — kids-learning-app

「まなびアプリ」。多ファイル構成のバニラ JS PWA（`index.html` + `app.js` +
`style.css` + `manifest.json` + `sw.js`）。ビルドなし・依存なし。共通規約は
ルートの `CLAUDE.md` を参照。

- 4モード: たしざん（レベル1〜5）・くく/かけざん（だん選択+`speechSynthesis`
  読み上げ）・ひらがな（行選択の4択クイズ）・タイピング（ローマ字入力練習）。
  くく・たしざんのレベル/だんデータは旧 `sansu/` アプリから移植したもの。
- ゲーム要素（⭐スター・効果音・`localStorage` 保存）がある点が `sansu/` との
  違い。星は `manabi-stars` キーで永続化。すべてのモードで共通の報酬系。
- 画面切り替えは `document.body` への1つの click delegation（`data-action`
  属性）で行う。新しい画面・ボタンを足すときもこのパターンに合わせること。
- `sw.js` はオフラインキャッシュ用。`index.html`/`app.js`/`style.css` の
  いずれかを変更したら `CACHE_NAME` をインクリメントすること（しないと
  PWA としてインストール済みの端末に反映されない）。
- 変更後は `index.html` をブラウザで直接開いて動作確認する。
