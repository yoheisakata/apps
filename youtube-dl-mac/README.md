# YouTube-downloader (macOS / SwiftUI)

YouTube のリンクから動画・音声をダウンロードする macOS デスクトップアプリ。
内部で [`yt-dlp`](https://github.com/yt-dlp/yt-dlp)(ダウンロード)と
[`ffmpeg`](https://ffmpeg.org/)(結合・変換)を呼び出します。

## 機能

- YouTube リンクを貼り付けてダウンロード
- チェックボックスで形式を選択(両方同時も可)
  - **Audio** … mp3 で最高音質
  - **Video** … 画質をプルダウンで選択(720p / 1080p / 1440p / 4K / 最高画質)し mp4 で取得
- 保存先フォルダの選択(既定は `~/Downloads`)
- 進捗バーと yt-dlp の生ログ表示、中止ボタン
- 紫グラデーションの「YD」アプリアイコン

## 必要なもの

[Homebrew](https://brew.sh/) で各自インストールしてください:

```bash
brew install yt-dlp ffmpeg
```

未インストールの場合はアプリ上部に案内が表示され、ダウンロードボタンは無効になります。
yt-dlp は YouTube の仕様変更に追従するため、定期的に更新してください:

```bash
brew upgrade yt-dlp
```

## インストール(/Applications に登録)

`install.sh` を実行すると、ビルドして `/Applications` に上書きインストールします。
新しいバージョンに更新するときも、このスクリプトを実行するだけです。

```bash
cd youtube-dl-mac
./install.sh
```

インストール後は **Launchpad / Spotlight(⌘+Space)で「YouTube-downloader」** から起動できます。

- 初回起動で Gatekeeper の警告が出たら、`.app` を**右クリック →「開く」**で一度許可すれば
  次回から普通に開けます(ad-hoc 署名のため)。

## その他の起動方法

### Finder からダブルクリック(インストールせずに試す)

`build-app.sh` は `dist/` に `.app` を生成するだけです(`/Applications` には登録しません)。

```bash
cd youtube-dl-mac
./build-app.sh
open dist/        # Finder で開く → YouTube-downloader.app をダブルクリック
```

### ターミナルから直接(開発時)

Xcode 不要。Swift Package として `swift run` で起動できます:

```bash
cd youtube-dl-mac
swift run            # デバッグビルド
swift run -c release # リリースビルド
```

## スクリプト一覧

| スクリプト        | 役割 |
| ----------------- | ---- |
| `./install.sh`    | ビルド → `/Applications/YouTube-downloader.app` に上書きインストール(更新もこれ) |
| `./build-app.sh`  | アイコン生成 → リリースビルド → `dist/YouTube-downloader.app` を生成 |
| `swift make-icon.swift` | 紫グラデーションの「YD」アイコン(`AppIcon.icns`)を生成 |

`dist/` `.build/` `AppIcon.icns` `AppIcon.iconset/` は `.gitignore` 済みで、
すべて上記スクリプトから再生成されます。

## 仕組み(形式の指定)

yt-dlp に渡すフォーマット指定:

| 形式  | フォーマット文字列                                                        | 後処理 |
| ----- | ------------------------------------------------------------------------ | ------ |
| Audio | `bestaudio/best`                                                          | `--extract-audio --audio-format mp3 --audio-quality 0` |
| Video | `bestvideo[height<=H]+bestaudio/best[height<=H]/bestvideo+bestaudio/best`（`H` は選択画質。最高画質時は `bestvideo+bestaudio/best`） | `--merge-output-format mp4` |

ファイル名は `%(title)s [%(id)s].%(ext)s`(`--restrict-filenames` で安全化)、
プレイリスト URL でも `--no-playlist` で単一動画のみを取得します。
GUI を Finder から起動しても yt-dlp / ffmpeg を見つけられるよう、Homebrew の既知パス
(`/opt/homebrew/bin`, `/usr/local/bin`)とログインシェルの両方を探索します。

## 注意

ダウンロードは YouTube の利用規約および各国の著作権法の範囲内
(自分のコンテンツ・権利者の許諾があるもの・パブリックドメイン等)で
利用してください。
