# mychat (MyChat)

SwiftUI + SPM の Mac アプリ（macOS 14+、bundle ID `com.yoheisakata.mychat`）。Claude の Messages API を `URLSession` で直接呼ぶチャットクライアント。Swift には公式 Anthropic SDK が無いので raw HTTP + SSE。外部依存なし。

- ビルド確認は `swift build`、インストールは `./install.sh`（`build_app.sh` → `/Applications/MyApplications/`）。アイコンは `make-icon.swift`。バージョンは `Sources/MyChat/Main.swift` の `appVersion` と `Info.plist` の `CFBundleShortVersionString`（両方上げる）。
- ファイル:
  - `ClaudeClient.swift` — `POST /v1/messages`、`anthropic-version: 2026-10-21`、`stream: true`、`max_tokens` 64000、`output_config.effort`。Opus/Sonnet ではサーバー側フォールバック（`fallbacks: "default"` + beta `server-side-fallback-2026-07-01`）を付ける（Haiku は非対応なので付けない）。2026-10-21 では `temperature`/`top_p`/`top_k` は 400 になるので送らないこと。
  - `ChatStore.swift` — 会話一覧・送受信・保存（`~/Library/Application Support/MyChat/conversations.json`）。
  - `Models.swift` — `ChatModel`（rawValue = モデル ID、保存されるので変えない）、`Effort`、`ChatMessage`、`Conversation`。
  - `Keychain.swift` — API キー（service `com.yoheisakata.mychat`）。キーをファイルや UserDefaults に置かないこと。
  - `Views.swift` — 画面（一覧・チャット・簡易 Markdown 表示・設定）。
- **履歴は追記のみ（重要）**: 新しいモデルは thinking ブロックの署名が「それまでの system / messages」に結びついていて、過去の発言を書き換えると 400 や thinking の破棄になる。そのため:
  - アシスタントの応答は SSE から組み立てた content ブロック列（thinking + signature を含む）を `rawContent` に保存し、次回は**そのまま**送り返す。
  - システムプロンプトは会話作成時に `Conversation.systemPrompt` へコピーして固定（設定の変更は新しい会話から）。
  - 削除してよいのは「末尾の、まだ答えのない発言」だけ（エラー時に入力欄へ戻す処理）。途中の発言の編集・削除機能は作らないこと。
  - 拒否（`stop_reason: "refusal"`）されたやりとりは `excluded = true` にして以後送らない。一度 true にしたら戻さない。
  - 停止ボタンで止めた応答は `rawContent` なし（テキストのみ）で保存。
  - 途中でフォールバックが起きた応答は、最後の `fallback` ブロックより前は `text` だけ送り返す（`ClaudeClient.echoBlocks`）。
- `ChatMessage`/`Conversation` に保存項目を足すときは Optional にする（合成 Decodable は既定値があってもキー必須なので、古い保存ファイルが読めなくなる）。
- モデル ID を変えるとき（新モデル登場時など）は、`ChatModel` に case を**追加**する（既存 rawValue は保存データにあるので消さない）。
