#!/usr/bin/env python3
"""
find_short_videos.py

指定フォルダ内の短い動画ファイルを洗い出し、レポートや M3U プレイリストを出力する。

使い方:
  python3 find_short_videos.py <フォルダ>
  python3 find_short_videos.py <フォルダ> --max-seconds 5
  python3 find_short_videos.py <フォルダ> --report ~/Desktop/short.txt
  python3 find_short_videos.py <フォルダ> --playlist ~/Desktop/short.m3u
  python3 find_short_videos.py <フォルダ> --playlist ~/Desktop/short.m3u --play
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

VIDEO_EXTS = {'.mp4', '.mov', '.m4v', '.mkv', '.avi', '.mts', '.m2ts'}

PLAYERS = ['iina', 'mpv', 'vlc']  # 優先順位順


def get_duration(path: Path) -> float | None:
    result = subprocess.run(
        ['ffprobe', '-v', 'quiet',
         '-show_entries', 'format=duration',
         '-of', 'json', str(path)],
        capture_output=True, text=True
    )
    try:
        return float(json.loads(result.stdout)['format']['duration'])
    except Exception:
        return None


def find_player() -> str | None:
    """インストール済みのプレイヤーを優先順に探す"""
    for player in PLAYERS:
        result = subprocess.run(['which', player], capture_output=True, text=True)
        if result.returncode == 0:
            return player
    return None


def write_m3u(path: Path, files: list[tuple[Path, float]]) -> None:
    """M3U プレイリストを絶対パスで書き出す"""
    lines = ['#EXTM3U']
    for f, dur in files:
        lines.append(f'#EXTINF:{int(dur)},{f.name}')
        lines.append(str(f.resolve()))
    path.expanduser().write_text('\n'.join(lines) + '\n', encoding='utf-8')


def main():
    parser = argparse.ArgumentParser(description='短い動画ファイルを洗い出す')
    parser.add_argument('folder', help='対象フォルダ')
    parser.add_argument('--max-seconds', type=float, default=3.0,
                        help='この秒数以下を対象にする（デフォルト: 3）')
    parser.add_argument('--report', metavar='FILE',
                        help='テキストレポートをファイルに保存')
    parser.add_argument('--playlist', metavar='FILE',
                        help='M3U プレイリストを保存（VLC / IINA / mpv で開ける）')
    parser.add_argument('--play', action='store_true',
                        help='--playlist と併用: 保存後にプレイヤーで即再生')
    args = parser.parse_args()

    folder = Path(args.folder)
    if not folder.is_dir():
        print(f'エラー: フォルダが見つかりません: {folder}')
        sys.exit(1)

    files = sorted(
        p for p in folder.rglob('*')
        if p.is_file() and p.suffix.lower() in VIDEO_EXTS and not p.name.startswith('.')
    )

    print(f'対象フォルダ: {folder}')
    print(f'閾値: {args.max_seconds} 秒以下')
    print(f'動画ファイル数: {len(files)}\n')

    short = []
    for i, f in enumerate(files, 1):
        print(f'\r  解析中... [{i}/{len(files)}] {f.name[:50]}', end='', flush=True)
        dur = get_duration(f)
        if dur is not None and dur <= args.max_seconds:
            short.append((f, dur))

    print()

    if not short:
        print(f'\n{args.max_seconds} 秒以下の動画は見つかりませんでした。')
        return

    # --- テキストレポート ---
    lines = []
    lines.append(f'{args.max_seconds} 秒以下の動画: {len(short)} 件\n')
    for f, dur in short:
        size_mb = f.stat().st_size / 1024 / 1024
        lines.append(f'  {dur:5.2f}秒  {size_mb:6.1f} MB  {f.resolve()}')

    output = '\n'.join(lines)
    print('\n' + output)

    if args.report:
        Path(args.report).expanduser().write_text(output, encoding='utf-8')
        print(f'\nレポートを保存しました: {args.report}')

    # --- M3U プレイリスト ---
    if args.playlist:
        playlist_path = Path(args.playlist).expanduser()
        write_m3u(playlist_path, short)
        print(f'プレイリストを保存しました: {playlist_path}')

        if args.play:
            player = find_player()
            if player:
                print(f'再生中... ({player})')
                subprocess.Popen([player, str(playlist_path)])
            else:
                # プレイヤーが見つからなければ open で関連アプリを起動
                print('再生中... (open)')
                subprocess.Popen(['open', str(playlist_path)])


if __name__ == '__main__':
    main()
