# NetWorth — 資産トラッカー(macOS ネイティブ)

Bank of America・Fidelity など全口座の残高を SimpleFIN 経由で取得し、
純資産の推移・口座ごとの増減・カード支出をまとめて表示する macOS アプリ。

- 総資産と推移グラフ(今週 / 今月の増減)
- 口座ごとの残高・増減
- 支出の週次比較、今週の使い先 Top 5、日別の明細
- `--fetch` フラグで UI なしの取得モード(launchd で毎朝自動記録)

## データの置き場所

- SimpleFIN のアクセスURL(読み取り専用) → **Keychain**
- 残高・取引の履歴 → `~/Library/Application Support/NetWorth/history.json`

リポジトリには秘密情報も金融データも入らない。

## ビルドと初回セットアップ

```bash
cd networth
./build_app.sh
cp -R NetWorth.app /Applications/
open /Applications/NetWorth.app
```

1. https://bridge.simplefin.org でアカウント作成(年 $15)、Bank of America / Fidelity を接続
2. 「New App Connection」でセットアップトークンを発行
3. アプリの設定画面(⚙)に貼り付けて「接続」

SimpleFIN 契約前でも「デモデータで試す」で UI を確認できる。

## 毎朝の自動記録(任意)

アプリを開いた時に毎回最新を取得するが、開かない日も記録したい場合:

```bash
cp com.yoheisakata.networth-fetch.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.yoheisakata.networth-fetch.plist
```

毎朝 7:00 に `NetWorth --fetch` を実行する(ログ: `/tmp/networth-fetch.log`)。

## 注意

- 残高スナップショットは1日1回。推移グラフは記録を始めた日から貯まっていく
- 「支出」はカード引き落とし・送金・給与を正規表現で除外する簡易方式
  (`Dashboard.transferPattern`)。誤分類があればパターンを調整する
- ビルドのたびにアドホック署名が変わるため、再ビルド後の初回起動時に
  Keychain へのアクセス許可を求められることがある
