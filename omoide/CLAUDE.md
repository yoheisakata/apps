# CLAUDE.md — Omoide

子ども動画のクリップまとめアプリ。**SwiftUI + SPM** 構成。
リポジトリ全体の規約はルートの `CLAUDE.md` を参照。

## ビルド / デプロイ

```bash
swift run                        # 開発ビルド(ウィンドウ起動)
./build_app.sh                   # release ビルド → Omoide.app
cp -R Omoide.app /Applications/  # install.sh は無い。cp でデプロイ
```

- **バージョンは `Sources/Omoide/Main.swift` の `appVersion` が唯一の定義**。
  `build_app.sh` が Info.plist の `CFBundleShortVersionString` に反映する。

## 構成

- `Sources/Omoide/Main.swift` — エントリポイント + バージョン定義。
- `Sources/Omoide/VideoMakerViewModel.swift` にロジックが集約
  （動画列挙、ffmpeg でのクリップ抽出 0〜80% → 結合 80〜90% → BGM 合成 90〜100%）。
- `Sources/Omoide/ContentView.swift` — SwiftUI のメイン UI。
- クリップ長は `DurationMode`（.clip = 1本あたり秒数 / .total = 合計秒数から逆算）。
- 画質は CRF（`qualityPreset`、既定 18）。BGM 音量は `bgmVolume`（既定 0.3）。
- 既定の入力パス・BGM パスは UserDefaults に保存。

## 注意

- ffmpeg は外部コマンドとして呼ぶ（同梱しない）。
