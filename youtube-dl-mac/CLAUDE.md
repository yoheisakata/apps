# CLAUDE.md — youtube-dl-mac

`yt-dlp` / `ffmpeg` を呼び出す YouTube ダウンローダー (SwiftUI + SPM)。
使い方・フォーマット指定の詳細は `README.md` を参照。

## ビルド / デプロイ

```bash
swift run          # 開発ビルド
./build-app.sh     # ハイフン区切り。dist/YouTube-downloader.app を生成
./install.sh       # ビルド → /Applications へ上書きインストール
```

`dist/` `.build/` `AppIcon.icns` `AppIcon.iconset/` は .gitignore 済み・
スクリプトから再生成される成果物。コミットしない。

## ソース構成 (`Sources/YouTubeDownloader/`)

- `App.swift` — エントリ
- `ContentView.swift` — UI（URL入力・Audio/Video チェック・画質・保存先・ログ・中止）
- `DownloadManager.swift` — yt-dlp プロセスの起動・進捗パース・フォーマット文字列の組み立て
- `ToolLocator.swift` — yt-dlp / ffmpeg の探索。Homebrew の既知パス
  (`/opt/homebrew/bin`, `/usr/local/bin`) とログインシェルの PATH の両方を見る
  （Finder 起動だと PATH が引き継がれないため）

## 変更時の注意

- yt-dlp / ffmpeg は同梱しない。未インストール時は案内を出してダウンロードを
  無効化する挙動を維持する。
- ファイル名テンプレート `%(title)s [%(id)s].%(ext)s` + `--restrict-filenames`、
  プレイリスト URL には `--no-playlist`。変更するなら README の表も更新する。
