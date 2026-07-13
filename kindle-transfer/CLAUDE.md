# CLAUDE.md — kindle-transfer

Kindle Fire の中身を `adb pull` で Mac にコピーする対話型 Bash スクリプト。
ビルドなし・単一ファイル (`kindle-transfer.sh`)。使い方は `README.md` を参照。

## 変更時の注意

- MTP や macFUSE に依存しない（それがこのツールの存在理由）。adb だけで完結させる。
- SD カードは `adb shell ls /storage` の `XXXX-XXXX` 形式ボリュームで自動判定。
- コピーは `adb pull -a`（タイムスタンプ等の属性保持）。`-a` を外さない。
- 対話フロー（adb 導入案内 → 接続検出 → コピー元選択 → コピー先指定 → 転送）を
  変えたら README の手順表と「よくあるトラブル」も更新する。
- Web アプリではないのでルート `index.html`（ランチャー）には載せない。
