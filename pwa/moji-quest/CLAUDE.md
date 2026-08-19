# CLAUDE.md — moji-quest（もじくえすと）

多ファイル構成のバニラ JS PWA（`index.html` + `app.js` + `style.css` +
`manifest.json` + `sw.js`）。ビルドなし・依存なし。共通規約はルートの
`CLAUDE.md` を参照。

**この app.js/style.css/hiragana-strokes.js/audio/ は `suji-quest/` と
まったく同じコピーです。** 2026-08-18 まで両方は「まなびアプリ」という
1つのアプリ（たしざん・くく・ひらがな・タイピングの4モード）だったが、
ユーザーの依頼でランチャー上は「すうじくえすと」（たしざん・くく）と
「もじくえすと」（ひらがな・タイピング）の2アプリに分割された。**コードは
共有せず完全に複製**しており、`index.html` のホーム画面ボタンを削って
見せるモードを絞っただけ — `app.js` 自体は今もたしざん/ククのロジックを
まるごと含んでいる（ホーム画面にボタンが無いので到達不能なだけ）。
共有ロジック（スター報酬・音声再生・画面遷移の click delegation 等）を
直すときは、同じ修正が `suji-quest/app.js` にも要ることが多い（自動同期は
されない）。

- 2モード: ひらがな（行選択の canvas なぞりがき練習）・タイピング
  （ローマ字入力練習）。
- なぞりがきは**書き順判定**: `hiragana-strokes.js`（`tools/generate_strokes.py`
  が KanjiVG の SVG から生成した、画ごとの中心線ポリライン・点間隔約6px）を
  お手本描画と判定の両方に使う。1画ずつ、始点から `TRACE_START_TOL` 以内で
  書きはじめ、`TRACE_CORRIDOR` 以内で線に沿って先読み `TRACE_LOOKAHEAD` 点の
  範囲を進み、画の `TRACE_END_RATIO` まで到達したら1画完成。脱線・途中放し・
  順番ちがい（始点が合わない）はその画のやりなおし。塗りつぶしでは正解に
  ならない。KanjiVG は CC BY-SA 3.0 — README のクレジットを消さないこと。
  以前あった「きこえた文字を4択で選ぶクイズ」は `speechSynthesis` の音質が
  端末依存で聞き取れないため削除済み — 再追加しないこと。
- ゲーム要素（⭐スター・効果音・`localStorage` 保存）。星は
  `moji-quest-stars` キーで永続化（分割前の共通キー `manabi-stars` とは
  別物 — 分割時に進捗はリセットされた）。
- 画面切り替えは `document.body` への1つの click delegation（`data-action`
  属性）で行う。新しい画面・ボタンを足すときもこのパターンに合わせること。
- 読み上げは2系統: 固定フレーズ（なぞりがきの説明・ほめことば）は `audio/`
  の同梱 mp3（`tools/generate_audio.py` が Open JTalk/pyopenjtalk-plus で
  生成、完全オフライン・無料）を `playAudio()` で再生し、失敗時と動的な文
  （タイピングのことば）だけ `speak()` = `speechSynthesis` にフォールバック
  する。`speak()` は端末の日本語音声から高品質なもの（Kyoko / Google 日本語
  等）を明示選択する。フレーズを増やしたら `tools/generate_audio.py` を
  再実行し（`audio-manifest.js` も再生成される）、`CACHE_NAME` をバンプする
  こと。より高音質にしたければ同じファイル構成で VOICEVOX 等で作り直して
  差し替えればよい（アプリ側の変更不要）。
- `sw.js` はオフラインキャッシュ用（`CACHE_NAME = "moji-quest-v1"`、
  `suji-quest/` とは別名にしてキャッシュが衝突しないようにしてある）。
  `index.html`/`app.js`/`style.css` のいずれかを変更したら `CACHE_NAME` を
  インクリメントすること（しないと PWA としてインストール済みの端末に
  反映されない）。
- **このアプリを変更したら `.app-version`（ホーム画面のタイトルの下＝上部）の
  バージョンを必ず上げること**。あわせて `CACHE_NAME` も上げる（cache-first
  なので上げないと iPhone に新しいバージョンが届かない）。
- 変更後は `index.html` をブラウザで直接開いて動作確認する。

## 未使用だが残っているコード

たしざん・くく（かけざん）のロジック一式が `app.js` に残っている。ホーム
画面から到達できないので実害はないが、`app.js` を大きく書き換える際は
これらの関数もまだ存在する前提でスコープを確認すること。もし将来
`moji-quest` から完全に削ぎ落としたくなったら、`suji-quest/CLAUDE.md` の
対応セクションと合わせて両方のファイルを見直すこと。
