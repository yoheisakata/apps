# CLAUDE.md — suji-quest（すうじくえすと）

多ファイル構成のバニラ JS PWA（`index.html` + `app.js` + `style.css` +
`manifest.json` + `sw.js`）。ビルドなし・依存なし。共通規約はルートの
`CLAUDE.md` を参照。

**この app.js/style.css/hiragana-strokes.js/audio/ は `moji-quest/` と
まったく同じコピーです。** 2026-08-18 まで両方は「まなびアプリ」という
1つのアプリ（たしざん・くく・ひらがな・タイピングの4モード）だったが、
ユーザーの依頼でランチャー上は「すうじくえすと」（たしざん・くく）と
「もじくえすと」（ひらがな・タイピング）の2アプリに分割された。**コードは
共有せず完全に複製**しており、`index.html` のホーム画面ボタンを削って
見せるモードを絞っただけ — `app.js` 自体は今もひらがな/タイピングの
ロジックをまるごと含んでいる（ホーム画面にボタンが無いので到達不能なだけ）。
共有ロジック（スター報酬・音声再生・画面遷移の click delegation 等）を
直すときは、同じ修正が `moji-quest/app.js` にも要ることが多い（自動同期は
されない）。

- 2モード: たしざん（レベル1〜5）・くく/かけざん（だん選択+`speechSynthesis`
  読み上げ）。レベル/だんデータは旧 `sansu/` アプリから移植したもの。
- ゲーム要素（⭐スター・効果音・`localStorage` 保存）。星は
  `suji-quest-stars` キーで永続化（分割前の共通キー `manabi-stars` とは
  別物 — 分割時に進捗はリセットされた）。
- 画面切り替えは `document.body` への1つの click delegation（`data-action`
  属性）で行う。新しい画面・ボタンを足すときもこのパターンに合わせること。
- 読み上げは2系統: 固定フレーズは `audio/` の同梱 mp3
  （`tools/generate_audio.py` が Open JTalk/pyopenjtalk-plus で生成、完全
  オフライン・無料）を `playAudio()` で再生し、失敗時と動的な文（たしざんの
  問題文）だけ `speak()` = `speechSynthesis` にフォールバックする。
  フレーズを増やしたら `tools/generate_audio.py` を再実行し
  （`audio-manifest.js` も再生成される）、`CACHE_NAME` をバンプすること。
- `sw.js` はオフラインキャッシュ用（`CACHE_NAME = "suji-quest-v1"`、
  `moji-quest/` とは別名にしてキャッシュが衝突しないようにしてある）。
  `index.html`/`app.js`/`style.css` のいずれかを変更したら `CACHE_NAME` を
  インクリメントすること（しないと PWA としてインストール済みの端末に
  反映されない）。
- **このアプリを変更したら `.app-version`（ホーム画面のタイトルの下＝上部）の
  バージョンを必ず上げること**。あわせて `CACHE_NAME` も上げる（cache-first
  なので上げないと iPhone に新しいバージョンが届かない）。
- 変更後は `index.html` をブラウザで直接開いて動作確認する。

## 未使用だが残っているコード

ひらがな（なぞりがき・書き順判定）とローマ字タイピングのロジック一式が
`app.js`/`hiragana-strokes.js`/関連 CSS に残っている。ホーム画面から到達
できないので実害はないが、`app.js` を大きく書き換える際はこれらの関数も
まだ存在する前提でスコープを確認すること。もし将来 `suji-quest` から
完全に削ぎ落としたくなったら、`moji-quest/CLAUDE.md` の対応セクションと
合わせて両方のファイルを見直すこと。
