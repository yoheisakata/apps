# CLAUDE.md — KidsVideoMaker

子ども動画のクリップまとめアプリ。**SPM ではなく Xcode プロジェクト**
（`KidsVideoMaker.xcodeproj`）。他のネイティブアプリの `build_app.sh` /
`install.sh` / `make-icon.swift` 規約は当てはまらない。Xcode でビルドする。

## 構成

- `KidsVideoMaker/VideoMakerViewModel.swift` にロジックが集約
  （動画列挙、ffmpeg でのクリップ抽出 0〜80% → 結合 80〜90% → BGM 合成 90〜100%）。
- クリップ長は `DurationMode`（.clip = 1本あたり秒数 / .total = 合計秒数から逆算）。
- 画質は CRF（`qualityPreset`、既定 18）。BGM 音量は `bgmVolume`（既定 0.3）。
- 既定の入力パス・BGM パスは UserDefaults に保存。

## 注意

- ffmpeg は外部コマンドとして呼ぶ（同梱しない）。
