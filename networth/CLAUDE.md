# CLAUDE.md — networth

SwiftUI + SPM の macOS 資産トラッカー。リポジトリ全体の規約はルートの
`CLAUDE.md` を参照。ここはこのアプリ固有の注意点だけ。

## ビルド / デプロイ

```bash
swift run                            # 開発ビルド(ウィンドウ起動)
./build_app.sh                       # release ビルド → NetWorth.app
./install.sh                         # ビルド → /Applications へインストール
```

- **バージョンは `Sources/NetWorth/Main.swift` の `appVersion` が唯一の定義**。
  `build_app.sh` が Info.plist の `CFBundleShortVersionString` に反映する。
  機能を変えたらここを上げ、コミットメッセージにも `(vX.Y.Z)` を入れる(履歴の慣例)。
- `Package.swift` で **macOS 26 必須**(FoundationModels のため)。下げない。
- `build_app.sh` は `2026_Sakata_支出表.md` を Resources に同梱する(固定収支タブの
  フォールバック)。

## ソース構成 (`Sources/NetWorth/`)

| ファイル | 役割 |
|---|---|
| `Main.swift` | エントリポイント。`--fetch` で UI なしの取得モード(launchd 用) |
| `FinanceStore.swift` | ObservableObject。履歴・株価・接続状態。Dashboard はキャッシュして使い回す |
| `SimpleFIN.swift` | SimpleFIN Bridge API(claim / fetchAccounts) |
| `Keychain.swift` | アクセスURL の保存先(リポジトリに秘密を置かない) |
| `History.swift` | `~/Library/Application Support/NetWorth/history.json` の読み書き・デモデータ |
| `Dashboard.swift` | 集計ロジック。`transferPattern` で振込・給与等を支出から除外 |
| `Quotes.swift` | Yahoo Finance chart API から現在株価(API キー不要、UA 偽装、失敗銘柄はフォールバック) |
| `Views.swift` | タブ UI(メイン/週/月/投資/固定収支/レシート)と各カード |
| `FixedBudget.swift` | 固定収支タブ。`~/github/apps/networth/2026_Sakata_支出表.md` を直接読む軽量 md パーサー(見出し/表/引用/区切り/太字のみ対応) |
| `Receipts.swift` | レシートのデータ層: ReceiptStore、Vision OCR、FoundationModels 抽出、CSV 出力 |
| `ReceiptsTab.swift` | レシート UI: 一覧(取り込み・編集)と集計(Schedule C 行別ロールアップ) |

## 変更時の注意

- **`ExpenseCategory` の rawValue は保存データに使われている — 変更禁止**。
  case の定義順 = Schedule C の行順 = Picker と集計の表示順なので、追加時は行順を保つ。
- **FoundationModels のプロンプトは英語で書く**。Apple Intelligence の言語設定と
  一致しない言語のプロンプトは拒否される。
- レシートの編集はキーストロークごとに `scheduleSave()`(500ms デバウンス)。
  即時保存が要る操作(削除・解析結果の書き戻し等)は `save()` を直接呼ぶ。
- レシート取り込みは順次実行して通知(notice)を集約する設計。並列化すると
  notice が上書き合戦になるので戻さない。
- CSV 出力は Excel 対応のため BOM 付き UTF-8。
- 金融データ・トークンをリポジトリやログに残さない(Keychain / Application Support のみ)。
- 動作確認は `swift build` + `swift run`。テストは無い。
