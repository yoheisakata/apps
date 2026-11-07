# MyChat

Claude（Anthropic）とチャットする Mac アプリ。

## 使い方

1. インストール: `./install.sh`（ビルドして `/Applications/MyApplications/MyChat.app` に入れる）
2. 起動したらメニュー「MyChat」→「設定…」（⌘,）で **Anthropic API キー**を入力して「保存」。キーは macOS のキーチェーンにだけ保存される（console.anthropic.com で発行、利用料はそのキーのアカウントに請求される）。
3. 入力欄に書いて Return で送信（⌥Return で改行）。返事は少しずつ表示される。■ で途中で止められる。

- ⌘N で新しいチャット。左の一覧で切り替え、右クリックで削除。
- 右上でモデルを切り替え: Opus 5.5（既定・賢い）／ Sonnet 5.5（速くて十分賢い）／ Haiku 5.5（いちばん速くて安い）
- 設定で、新しいチャットの初期モデル・考える深さ（低／中／高）・システムプロンプトを変えられる。システムプロンプトは会話ごとに作成時点のもので固定。
- 返事のコードブロックと本文はそれぞれコピーできる。
- 会話は `~/Library/Application Support/MyChat/conversations.json` に保存される。
- 通信エラーのときは、送った文章が入力欄に戻るので、そのまま送り直せる。
