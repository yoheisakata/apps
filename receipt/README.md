# レシートスキャン（確定申告） 🧾 — `receipt/`

レシートを撮影・アップロードすると **Claude API** が店名・金額・カテゴリを
自動抽出し、確定申告向けに整理できるWebアプリ。スマホのカメラ撮影
（`capture` 属性）に対応。

## セットアップ（利用者側で用意するもの）

1. **Claude API キー** — console.anthropic.com で取得し、設定画面に貼り付ける。
   キーはこのデバイスの `localStorage` にのみ保存される
2. **Firebase 設定（任意・クラウド同期用）** — console.firebase.google.com で
   プロジェクトを作成し、設定 JSON を貼り付けると Firebase Auth + Firestore で
   デバイス間同期ができる

どちらもリポジトリには含まれず、実行時に利用者が自分のものを設定する方式。

## 仕組み

- レシート画像をブラウザから直接 Claude API（`claude-haiku-4-5`、
  `anthropic-dangerous-direct-browser-access` ヘッダ使用）に送って内容を抽出
- データは `localStorage`（`receipts_v2`）に保存。設定は `receipt_settings`
- Firebase 設定済みなら Firestore に同期（firebase-js SDK 10.x compat 版を CDN 読み込み）

## 動かし方

ビルド不要の単一 HTML ファイル。`index.html` をブラウザで開くだけ。

> ⚠️ macOS ネイティブの NetWorth アプリにも「レシート」タブ（Schedule C 向け・
> オンデバイス LLM）があるが、あちらは別物。こちらは日本の確定申告向けの
> Web アプリ。
