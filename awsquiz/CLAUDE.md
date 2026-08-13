# CLAUDE.md — awsquiz

AWS SAP-C02 対策の学習アプリ。ビルドなし・依存なし。共通規約はルートの `CLAUDE.md`
を参照（Nunito フォント・ダークグラデ・モバイルファースト・絵文字アイコン）。

## ファイル構成

pgquiz と違い**単一 HTML ではない**（問題データが大きいため分離している）:

- `index.html` — UI とロジック全部（インライン CSS + JS）
- `questions.js` — 出題データ。`window.SAP_QUESTIONS` / `SAP_DOMAINS` /
  `SAP_CATEGORY_EMOJI` / `SAP_FIGURES` をグローバルに置くだけの素の JS
- `manifest.json` / `sw.js` — PWA（iPhone のホーム画面に追加してオフライン学習するため）
- `SAP-C02-quiz.md` — ユーザーが自分で書いた練習問題集（30問、`<details>` 形式）。
  **`questions.js` の `md-NN` はこのファイルから取り込んだもの**。どちらかを直したら
  もう片方も直す（自動同期はしていない）。

`fetch` を使っていないので `file://` で直接開いても動く。

## データ

各問題は `{ id, dom, cat, q, choices, answer, note, fig? }`。

- **`id` は進捗の保存キー**（`localStorage` の `awsquiz-v1` → `q[id]`）。
  いちど入れた問題の id は変えないこと。変えると学習履歴が切れる。
  接頭辞で出自が分かるようにしてある: `d1-`〜`d4-` は書き下ろし、`md-` は
  `SAP-C02-quiz.md` からの取り込み。新しい取り込み元が増えたら別の接頭辞を使う。
- `dom` は `SAP_DOMAINS` の id（1〜4）。`cat` は `SAP_CATEGORY_EMOJI` のキー。
  **新しい技術分野を足すときは `SAP_CATEGORY_EMOJI` にも絵文字を追加する**
  （カテゴリ選択画面と進捗画面の生成に使われる）。
- `answer` は単一選択なら数値、複数選択なら数値の配列。配列の長さがそのまま
  「N つ選択」バッジと解答ボタンの必要選択数になる。
- `note` の `\n` は `<br>` に変換される。問題文・選択肢・解説はすべて
  `textContent` か `esc()` 経由で入るので HTML は書けない（`fig` の SVG のみ例外）。
- `fig` は `SAP_FIGURES` のキー。図は **回答後の解説とフラッシュカードの裏面にだけ**表示する
  （問題と一緒に出すと答えのネタバレになるため。pgquiz と同じ方針）。
  色はダークテーマ直書き（#ff9900 / #4dabf7 / #2ed573 / #ff4757 / #eef4fa / #93a7bd）。

問題を追加・変更したら、整合性チェックを走らせること:

```bash
cd awsquiz && node -e "global.window={};require('./questions.js');const Q=window.SAP_QUESTIONS,D=window.SAP_DOMAINS,C=window.SAP_CATEGORY_EMOJI,F=window.SAP_FIGURES;const ids=new Set();let bad=[];for(const q of Q){if(ids.has(q.id))bad.push('dup id '+q.id);ids.add(q.id);if(!C[q.cat])bad.push('unknown cat '+q.id);if(!D.some(d=>d.id===q.dom))bad.push('unknown dom '+q.id);const a=Array.isArray(q.answer)?q.answer:[q.answer];for(const i of a)if(i<0||i>=q.choices.length)bad.push('answer range '+q.id);if(new Set(q.choices).size!==q.choices.length)bad.push('dup choice '+q.id);if(q.fig&&!F[q.fig])bad.push('unknown fig '+q.id)}console.log(Q.length+'問',bad.length?bad:'OK');for(const d of D)console.log(d.short,Q.filter(q=>q.dom===d.id).length,'('+d.pct+'%目標)')"
```

**ドメインごとの問題数は、本番の出題比率（26/29/25/20%）に合わせて維持する。**
模擬試験モードがこの比率で問題を抽出するため、比率が崩れると模試の妥当性が落ちる。

## 内容の正確さ

- **対象は SAP-C02**。試験ガイドは 4ドメイン・75問・180分・合格 750/1000。
- AWS のサービス仕様は変わるので、数値（上限値・SLA・料金体系）を書くときは
  推測で書かない。確信が持てないものは「〜が多い」「〜のことがある」と幅を持たせるか、
  そもそも書かない。すでにある問題も、古くなったら直す。
- 廃止・改称されたサービス名を新規に足さないこと（例: Server Migration Service は
  Application Migration Service に置き換わっている）。

## 実装メモ

- 画面切り替えは `document.body` への click delegation（`data-action` 属性）。
- セッション（クイズ/復習/模試）は `session.entries[]` に
  `{ item, order, chosen, answered, ok, flagged, hinted }` を持つ。
  選択肢の並びはセッション生成時に1回だけシャッフルして `order` に固定する
  （模試で前の問題に戻ったときに並びが変わらないようにするため）。
- モードによる分岐は `session.mode`（`"quiz" | "review" | "exam"`）。
  exam は即時フィードバックなし・タイマーあり・前後移動とドットジャンプあり。
- 進捗は Leitner ボックス（0〜5、`MASTER_BOX = 3` 以上で習得ずみ）。
  `pickSmart()` が「未着手 > 直近不正解 > ボックスが低い」順に優先して出題する。
- **`sw.js` は network-first**。cache-first にすると問題を追加しても古い
  `questions.js` が返り続けるため。キャッシュ対象を変えたら `CACHE_NAME` を上げる。
- `.next-btn` は `.action-row`（flex）の中で `flex:1` にしているので、
  その外に単独で置くと縦に伸びる。模擬試験の設定画面では CSS で打ち消している。
- 変更後は `index.html` をブラウザで開いて確認する。特にクイズ画面は狭い画面幅で、
  長文シナリオと複数選択（必要数を選ぶまで解答ボタンが無効）の挙動を見ること。
