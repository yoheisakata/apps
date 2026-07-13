# CLAUDE.md — utilities

写真/動画パイプライン用の独立スクリプト集。アプリではない。一覧と用途は
`README.md` を参照。

## 変更時の注意

- 各スクリプトは単体で完結させる（共有モジュール・共通エントリポイントを作らない）。
- 使い方は各ファイル冒頭のコメント / docstring が正。挙動を変えたらそこも更新する。
- バックアップ系はユーザーの実データ（外付け HDD）を対象にする。特に
  `sync-backups.sh` はターゲット側の削除を伴うので、dry-run・確認まわりの
  挙動を安易に変えない。
- 想定ディレクトリ構造は `<root>/<YYYY>/<MM>/<MMDD>/YYYY_MMDD_HHMMSS.<ext>`
  （`verify-photos.sh` がこの規約の番人）。
- 動画処理は ffmpeg / ffprobe 前提。長時間処理は `caffeinate -i` 併用が慣例。
