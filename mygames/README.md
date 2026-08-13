# MyGames（マイゲームズ）

NES（ファミコン）と SNES（スーパーファミコン）のエミュレータ。libretro API 準拠のコアを読み込んで動作します。

## インストール

```bash
./install.sh
```

## コアの準備

libretro コア（.dylib）を以下のディレクトリに配置してください:

```
~/Library/Application Support/MyGames/Cores/
```

### 対応コア

| システム | 推奨コア | ファイル名例 |
|---------|---------|-------------|
| NES（ファミコン） | Nestopia, FCEUmm | `nestopia_libretro.dylib` |
| SNES（スーファミ） | Snes9x, bsnes | `snes9x_libretro.dylib` |

コアは [libretro buildbot](https://buildbot.libretro.com/nightly/apple/osx/) からダウンロードできます。

> ダウンロード後、macOS の検疫属性を解除する必要があります:
> ```bash
> xattr -d com.apple.quarantine ~/Library/Application\ Support/MyGames/Cores/*.dylib
> ```

## 使い方

1. アプリを起動
2. 「ROMを開く…」で ROM ファイルを選択（またはウィンドウにドラッグ＆ドロップ）
3. 拡張子に応じて自動的に対応コアがロードされます

## キーボード操作

| キー | ボタン |
|------|--------|
| ↑↓←→ | 十字キー |
| Z | A |
| X | B |
| A | X（SNES） |
| S | Y（SNES） |
| Return | Start |
| Right Shift | Select |
| Q | L（SNES） |
| W | R（SNES） |

## メニュー操作

| ショートカット | 機能 |
|---------------|------|
| ⌘O | ROM を開く |
| ⌘P | 一時停止 / 再開 |
| ⌘R | リセット |
| ⇧⌘S | ステートセーブ |
| ⇧⌘L | ステートロード |
| ⌘W | 停止 |

## ゲームコントローラー

MFi / Xbox / PlayStation コントローラーに対応しています（macOS の GameController フレームワーク経由）。

## データ保存先

| 種類 | パス |
|------|------|
| コア | `~/Library/Application Support/MyGames/Cores/` |
| セーブデータ | `~/Library/Application Support/MyGames/Saves/` |
| ステートセーブ | `~/Library/Application Support/MyGames/States/` |
| システム | `~/Library/Application Support/MyGames/System/` |
