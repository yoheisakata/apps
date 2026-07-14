# utilities — 写真・動画パイプライン用スクリプト集

個人の写真/動画バックアップ運用のための Python 3 / Bash スクリプト置き場。
パッケージ化されたアプリではなく、それぞれ CLI から個別に実行する
（共通のエントリポイントは無い）。

## スクリプト一覧

### バックアップ整理 (Bash)

| スクリプト | 役割 |
|---|---|
| `backup-photos.sh` | Photos から手動エクスポートした**写真**を日付フォルダに整理 |
| `backup-videos.sh` | Photos から手動エクスポートした**動画**を日付フォルダに整理 |
| `verify-photos.sh` | 写真フォルダの構造・ファイル名 (`<root>/<YYYY>/<MM>/<MMDD>/YYYY_MMDD_HHMMSS.<ext>`) を確認・修正 |
| `sync-backups.sh` | ExFAT HDD 間の同期。ソースを正としてターゲットを合わせる（ターゲット側の余分は削除） |

いずれも「Photos で選択 → ファイル > 未編集のオリジナルを書き出す」で
エクスポートしたファイルを入力にする想定。

### 動画処理 (Python 3)

| スクリプト | 役割 |
|---|---|
| `encode_h265.py` | H.265 (HEVC) への再エンコード + mp4 統一。`caffeinate -i` 併用でスリープ防止しながら長時間実行する想定 |
| `find_short_videos.py` | フォルダ内の短い動画を洗い出してレポート / M3U プレイリストを出力（`--max-seconds` で閾値指定） |
| `create_memory_video.py` | 月フォルダ内の動画から「いちばん動きのある部分」を抜き出し、BGM を重ねて1本のサマリー動画を生成（CLI） |

## 使い方

各スクリプトの冒頭コメント / docstring に使い方とオプションが書いてある。
例:

```bash
python3 find_short_videos.py <フォルダ> --max-seconds 5
caffeinate -i python3 encode_h265.py <対象フォルダ>
```

動画処理系は `ffmpeg` / `ffprobe` が必要（Homebrew: `brew install ffmpeg`）。

> クリップまとめの macOS ネイティブ GUI 版は別ディレクトリの
> `KidsVideoMaker/`（Xcode プロジェクト）にある。
