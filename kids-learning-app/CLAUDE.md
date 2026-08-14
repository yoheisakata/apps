# CLAUDE.md — kids-learning-app

「まなびアプリ」。多ファイル構成のバニラ JS PWA（`index.html` + `app.js` +
`style.css` + `manifest.json` + `sw.js`）。ビルドなし・依存なし。共通規約は
ルートの `CLAUDE.md` を参照。

- 4モード: たしざん（レベル1〜5）・くく/かけざん（だん選択+`speechSynthesis`
  読み上げ）・ひらがな（行選択の canvas なぞりがき練習）・タイピング
  （ローマ字入力練習）。くく・たしざんのレベル/だんデータは旧 `sansu/`
  アプリから移植したもの。
- なぞりがきは**書き順判定**: `hiragana-strokes.js`（`tools/generate_strokes.py`
  が KanjiVG の SVG から生成した、画ごとの中心線ポリライン・点間隔約6px）を
  お手本描画と判定の両方に使う。1画ずつ、始点から `TRACE_START_TOL` 以内で
  書きはじめ、`TRACE_CORRIDOR` 以内で線に沿って先読み `TRACE_LOOKAHEAD` 点の
  範囲を進み、画の `TRACE_END_RATIO` まで到達したら1画完成。脱線・途中放し・
  順番ちがい（始点が合わない）はその画のやりなおし。塗りつぶしでは正解に
  ならない。KanjiVG は CC BY-SA 3.0 — README のクレジットを消さないこと。
  以前あった「きこえた文字を4択で選ぶクイズ」は `speechSynthesis` の音質が
  端末依存で聞き取れないため削除済み — 再追加しないこと。
- ゲーム要素（⭐スター・効果音・`localStorage` 保存）がある点が `sansu/` との
  違い。星は `manabi-stars` キーで永続化。すべてのモードで共通の報酬系。
- 画面切り替えは `document.body` への1つの click delegation（`data-action`
  属性）で行う。新しい画面・ボタンを足すときもこのパターンに合わせること。
- 読み上げは2系統: 固定フレーズ（なぞりがきの説明・ほめことば・くくの読み）は
  `audio/` の同梱 mp3（`tools/generate_audio.py` が Open JTalk/pyopenjtalk-plus
  で生成、完全オフライン・無料）を `playAudio()` で再生し、失敗時と動的な文
  （たしざんの問題文・タイピングのことば）だけ `speak()` = `speechSynthesis`
  にフォールバックする。`speak()` は端末の日本語音声から高品質なもの
  （Kyoko / Google 日本語 等）を明示選択する。フレーズを増やしたら
  `tools/generate_audio.py` を再実行し（`audio-manifest.js` も再生成される）、
  `CACHE_NAME` をバンプすること。より高音質にしたければ同じファイル構成で
  VOICEVOX 等で作り直して差し替えればよい（アプリ側の変更不要）。
- `sw.js` はオフラインキャッシュ用。`index.html`/`app.js`/`style.css` の
  いずれかを変更したら `CACHE_NAME` をインクリメントすること（しないと
  PWA としてインストール済みの端末に反映されない）。
- **このアプリを変更したら `.app-version`（ホーム画面のタイトルの下＝上部）の
  バージョンを必ず上げること**。あわせて `CACHE_NAME` も上げる（cache-first
  なので上げないと iPhone に新しいバージョンが届かない）。ホーム画面に登録した
  状態で更新が届いたか確認する唯一の手段。
- 変更後は `index.html` をブラウザで直接開いて動作確認する。
