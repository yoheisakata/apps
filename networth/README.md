# NetWorth — 資産トラッカー(macOS ネイティブ)

Bank of America・Fidelity など全口座の残高を SimpleFIN 経由で取得し、
純資産の推移・支出・保有銘柄・固定収支・レシート(Schedule C)まで
1つにまとめた macOS アプリ。**macOS 26 以降が必要**(レシートタブの
FoundationModels がオンデバイス LLM を使うため)。

## タブ構成

| タブ | 内容 |
|------|------|
| メイン | 総資産と推移グラフ、口座ごとの残高・増減、支出アラート、カテゴリ別の月次推移 |
| 週 | 週単位の収支・内訳・日毎の支出明細 |
| 月 | 月単位の収支・内訳・日毎の支出明細 |
| 投資 | 株・投資の推移と保有銘柄一覧(口座ごとにグループ化・小計付き)。Yahoo Finance の現在株価で時価・損益を 株数×現在値 に補正 |
| 固定収支 | `networth/2026_Sakata_支出表.md` を軽量 Markdown パーサーで表示。md を編集して「再読込」すれば反映 |
| レシート | Schedule C(個人事業主)向けレシート管理。下記参照 |

### レシートタブ (Schedule C 経費整理)

- レシートの写真/PDF をドロップ(またはファイル・フォルダ選択)で取り込み
- **Vision OCR + FoundationModels(オンデバイス LLM)** で店名・日付・金額・
  カテゴリー・購入商品を自動抽出。外部 API には一切送らない
- カテゴリーは Form 1040 **Schedule C Part II の行(Line 8〜27a)に対応**。
  集計画面では行単位のロールアップ + 控除見込額(飲食費は50%)を表示
- 年別の CSV エクスポート(Excel 対応の BOM 付き UTF-8)
- 重複取り込みはハッシュで自動スキップ。削除時の元画像はゴミ箱へ
- データは `~/Library/Application Support/Receipts/` に保存
  (元は単体アプリ receipts-mac のデータをそのまま引き継ぐ)

## データの置き場所

- SimpleFIN のアクセスURL(読み取り専用) → **Keychain**
- 残高・取引の履歴 → `~/Library/Application Support/NetWorth/history.json`
- レシート → `~/Library/Application Support/Receipts/`

リポジトリには秘密情報も金融データも入らない。

## ビルドと初回セットアップ

```bash
cd networth
./build_app.sh                       # release ビルド + ad-hoc 署名
cp -R NetWorth.app /Applications/    # install.sh は無いので cp でデプロイ
open /Applications/NetWorth.app
```

バージョンは `Sources/NetWorth/Main.swift` の `appVersion` が唯一の定義で、
`build_app.sh` が Info.plist に反映する。リリース時はここだけ上げる。

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
- 「支出」はカード引き落とし・送金・給与・配当再投資などを正規表現で除外する
  簡易方式(`Dashboard.transferPattern`)。誤分類があればパターンを調整する
- 現在株価は Yahoo Finance の公開 chart API(API キー不要)。取得できない銘柄は
  SimpleFIN の同期値のまま表示する
- レシートの自動抽出は Apple Intelligence が有効な環境でのみ動く。
  FoundationModels へのプロンプトは**英語必須**(言語設定と一致しないと拒否される)
- ビルドのたびにアドホック署名が変わるため、再ビルド後の初回起動時に
  Keychain へのアクセス許可を求められることがある
