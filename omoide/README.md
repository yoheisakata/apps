# Omoide 🎬 — `omoide/`

子どもの動画フォルダから短いクリップをまとめて1本のまとめ動画を生成する macOS アプリ。

## 機能

- フォルダ内の動画を自動検出、個別に除外可能
- 1動画あたりの秒数 or 全体の尺を指定してクリップ抽出
- 暗い/止まったシーンを自動回避（最大5回リトライ）
- 冒頭タイトルカード + 映像中テキストオーバーレイ
- BGM 合成（フェードイン/アウト付き）
- 画質・冒頭スキップ・音量の詳細設定

## 動かし方

```bash
swift run                        # 開発ビルド
./build_app.sh                   # Omoide.app を生成
cp -R Omoide.app /Applications/  # インストール
```

ffmpeg / ffprobe が必要（`brew install ffmpeg`）。
