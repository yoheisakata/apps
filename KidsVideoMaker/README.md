# KidsVideoMaker 🎬

子どもの動画フォルダから短いクリップを抜き出し、BGM を重ねて1本のまとめ動画を
作る macOS アプリ（SwiftUI / Xcode プロジェクト）。
`utilities/kids_video_maker.py`（tkinter GUI 版）のネイティブ版。

## 機能

- 動画フォルダを指定して一覧から対象を選択
- クリップの長さ指定は2モード:
  - **クリップ秒数指定** — 各動画から N 秒ずつ
  - **合計秒数指定** — 出来上がりの長さから1本あたりを逆算
- 各クリップは先頭からのオフセット秒数を指定して抽出
- BGM ファイルを指定して音量調整（既定 30%）して合成
- 画質は CRF 値で指定（低いほど高画質、既定 18）
- 進捗表示（クリップ抽出 → 結合 → BGM 合成）

処理は内部で `ffmpeg` を呼び出して行う。

## ビルド / 実行

SPM ではなく **Xcode プロジェクト**。

```
open KidsVideoMaker.xcodeproj
```

Xcode からビルド & 実行する（他のネイティブアプリのような
`build_app.sh` / `install.sh` は無い）。

## 構成

- `KidsVideoMaker/KidsVideoMakerApp.swift` — エントリ
- `KidsVideoMaker/ContentView.swift` — UI
- `KidsVideoMaker/VideoMakerViewModel.swift` — 動画列挙・ffmpeg 実行・進捗管理
