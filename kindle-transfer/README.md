# Kindle Fire → Mac ファイル転送ツール 📱➡️💻

Amazon Kindle Fire（Fire OS / Android）の **SD カード**や内部ストレージの中身を、
USB 経由で macOS にまるごとコピーする対話型 Terminal ツールです。

macOS が苦手とする MTP ではなく **adb（Android Debug Bridge）の `adb pull`** を使うので、
Android File Transfer が不安定な Kindle Fire でも安定して転送できます。
カーネル拡張（macFUSE 等）は不要で、Apple Silicon でもそのまま動きます。

## 必要なもの

- macOS（Apple Silicon / Intel どちらも可）
- データ通信対応の USB ケーブル（充電専用ケーブルは不可）
- `adb`（未インストールならスクリプトが Homebrew で導入を案内します）

## 事前準備：Kindle 側で USB デバッグを有効化（初回のみ）

1. **設定 → デバイスオプション** を開き、**シリアル番号を7回タップ** → 「開発者オプション」が出現
2. **設定 → デバイスオプション → 開発者オプション** で **「ADB を有効にする」/「USB デバッグ」** をオン
3. データ通信対応の USB ケーブルで Mac に接続
4. Kindle に表示される **「USB デバッグを許可しますか？」で「許可」** をタップ
   - 毎回聞かれないように「このパソコンを常に許可」にチェックを入れると便利です

## 使い方

```bash
cd kindle-transfer
chmod +x kindle-transfer.sh   # 初回のみ
./kindle-transfer.sh
```

あとは画面の案内に従うだけです：

1. `adb` が無ければインストール（Homebrew）
2. Kindle の接続を自動検出（未承認なら許可を促します）
3. **SD カード**を自動検出し、コピー元を選択
   - SD カード / 内部ストレージ全体 / 写真・動画のみ / パス手入力 から選べます
4. Mac 側のコピー先を指定（既定は `~/Downloads/Kindle-日時`）
5. 転送開始 → 完了後に Finder で開けます

## よくあるトラブル

| 症状 | 対処 |
| --- | --- |
| デバイスが検出されない | データ通信対応ケーブルか確認 / 別の USB ポート / 一度抜き差し |
| `unauthorized` と出る | Kindle 画面の「USB デバッグを許可」をタップ |
| SD カードが見つからない | カードが挿入・マウントされているか確認。内部ストレージは選択肢に常に出ます |
| `adb` が見つからない | `brew install --cask android-platform-tools` |

## 仕組み

- `adb devices` で接続・承認状態を確認
- `adb shell ls /storage` を見て `XXXX-XXXX` 形式のボリューム（SD カード）を自動判定
- `adb pull -a "<元>/." "<先>"` で属性（タイムスタンプ）を保持したままコピー

> ⚠️ これは Web アプリではなく macOS 向けの Terminal ツールのため、GitHub Pages のランチャー（ルート `index.html`）には登録していません。
