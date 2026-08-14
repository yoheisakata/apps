#!/usr/bin/env python3
"""
check_video_codecs.py

指定フォルダ配下の動画を ffprobe で調べ、コーデック(h265/h264/その他)と
コンテナ(mp4 かどうか)を集計する。デフォルトでは「h265 かつ mp4」に
なっていないファイルのフルパス一覧を出力する。

使い方:
  python3 check_video_codecs.py                       # 既定: /Volumes/backup1/ys_video
  python3 check_video_codecs.py <フォルダ>
  python3 check_video_codecs.py <フォルダ> --list h265-not-mp4   # h265 だが mp4 でない
  python3 check_video_codecs.py <フォルダ> --list not-h265       # h265 でない
  python3 check_video_codecs.py <フォルダ> --list all            # 全ファイル
  python3 check_video_codecs.py <フォルダ> --report ~/Desktop/codecs.txt
  python3 check_video_codecs.py <フォルダ> --csv ~/Desktop/codecs.csv
  python3 check_video_codecs.py <フォルダ> --paths-only          # パスだけ(パイプ用)

コンテナ判定は拡張子で行う(.mp4 = mp4)。ffmpeg の mov/mp4 は同じ demuxer
(`mov,mp4,m4a,3gp,3g2,mj2`)で報告されるため、format_name では .mov と .mp4 を
区別できないため。format_name は CSV 出力にのみ含める。
"""

import argparse
import csv
import json
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

VIDEO_EXTS = {'.mp4', '.mov', '.m4v', '.mkv', '.avi', '.mts', '.m2ts',
              '.mpg', '.mpeg', '.wmv', '.flv', '.webm', '.3gp', '.ts'}

# ffprobe の codec_name → 表示名
CODEC_LABELS = {
    'hevc': 'h265',
    'h265': 'h265',
    'h264': 'h264',
    'avc1': 'h264',
}


def probe(path: Path) -> dict:
    """1ファイル分の情報を返す。失敗しても例外は投げない。"""
    result = subprocess.run(
        ['ffprobe', '-v', 'quiet',
         '-select_streams', 'v:0',
         '-show_entries', 'stream=codec_name:format=format_name',
         '-of', 'json', str(path)],
        capture_output=True, text=True
    )
    codec_raw = ''
    format_name = ''
    try:
        data = json.loads(result.stdout)
        streams = data.get('streams') or []
        if streams:
            codec_raw = streams[0].get('codec_name', '') or ''
        format_name = (data.get('format') or {}).get('format_name', '') or ''
    except Exception:
        pass

    codec = CODEC_LABELS.get(codec_raw, codec_raw or '(不明)')
    is_mp4 = path.suffix.lower() == '.mp4'
    return {
        'path': path,
        'codec': codec,
        'codec_raw': codec_raw,
        'format_name': format_name,
        'is_mp4': is_mp4,
        'ok': bool(codec_raw),
    }


def collect_files(root: Path) -> list[Path]:
    files = [p for p in root.rglob('*')
             if p.is_file()
             and not p.name.startswith('.')
             and p.suffix.lower() in VIDEO_EXTS]
    return sorted(files)


def main() -> int:
    parser = argparse.ArgumentParser(
        description='動画のコーデック(h265/h264)とコンテナ(mp4)を調べる')
    parser.add_argument('root', nargs='?', default='/Volumes/backup1/ys_video',
                        help='調べるフォルダ (既定: /Volumes/backup1/ys_video)')
    parser.add_argument('--list', dest='which', default='not-h265-mp4',
                        choices=['not-h265-mp4', 'h265-not-mp4', 'not-h265', 'all'],
                        help='一覧に出す対象 (既定: not-h265-mp4 = h265+mp4 になっていないもの)')
    parser.add_argument('--workers', type=int, default=8,
                        help='ffprobe の並列数 (既定: 8)')
    parser.add_argument('--report', help='一覧をテキストファイルにも書き出す')
    parser.add_argument('--csv', help='全ファイルの調査結果を CSV に書き出す')
    parser.add_argument('--paths-only', action='store_true',
                        help='集計を出さずフルパスだけを出力する')
    args = parser.parse_args()

    root = Path(args.root).expanduser()
    if not root.is_dir():
        print(f'フォルダが見つかりません: {root}', file=sys.stderr)
        return 1

    files = collect_files(root)
    if not files:
        print(f'動画ファイルが見つかりません: {root}', file=sys.stderr)
        return 1

    if not args.paths_only:
        print(f'調査対象: {len(files)} ファイル ({root})', file=sys.stderr)

    with ThreadPoolExecutor(max_workers=args.workers) as pool:
        results = list(pool.map(probe, files))

    # --- 集計 ---
    counts: dict[tuple[str, str], int] = {}
    for r in results:
        key = (r['codec'], 'mp4' if r['is_mp4'] else r['path'].suffix.lower())
        counts[key] = counts.get(key, 0) + 1

    def selected(r: dict) -> bool:
        if args.which == 'all':
            return True
        if args.which == 'h265-not-mp4':
            return r['codec'] == 'h265' and not r['is_mp4']
        if args.which == 'not-h265':
            return r['codec'] != 'h265'
        return not (r['codec'] == 'h265' and r['is_mp4'])  # not-h265-mp4

    targets = [r for r in results if selected(r)]
    lines = [str(r['path']) for r in targets]

    if args.paths_only:
        for line in lines:
            print(line)
    else:
        print()
        print('=== コーデック × コンテナ 集計 ===')
        width = max(len(f'{c} / {ext}') for c, ext in counts) if counts else 10
        for (codec, ext), n in sorted(counts.items(), key=lambda x: -x[1]):
            print(f'  {codec} / {ext:<{max(4, width)}} : {n:5d}')
        print()

        h265_mp4 = sum(1 for r in results if r['codec'] == 'h265' and r['is_mp4'])
        h265_not_mp4 = sum(1 for r in results if r['codec'] == 'h265' and not r['is_mp4'])
        not_h265 = sum(1 for r in results if r['codec'] != 'h265')
        failed = sum(1 for r in results if not r['ok'])
        print(f'  h265 かつ mp4        : {h265_mp4}')
        print(f'  h265 だが mp4 でない : {h265_not_mp4}')
        print(f'  h265 でない          : {not_h265}')
        if failed:
            print(f'  ffprobe 失敗         : {failed}')
        print()

        label = {
            'not-h265-mp4': '「h265 かつ mp4」になっていないファイル',
            'h265-not-mp4': 'h265 だが mp4 でないファイル',
            'not-h265': 'h265 でないファイル',
            'all': '全ファイル',
        }[args.which]
        print(f'=== {label} ({len(targets)} 件) ===')
        for r in targets:
            print(f'{r["path"]}\t[{r["codec"]}]')

    if args.report:
        Path(args.report).expanduser().write_text('\n'.join(lines) + '\n',
                                                  encoding='utf-8')
        print(f'\n一覧を書き出しました: {args.report}', file=sys.stderr)

    if args.csv:
        with open(Path(args.csv).expanduser(), 'w', newline='',
                  encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(['path', 'codec', 'codec_raw', 'container', 'format_name'])
            for r in results:
                w.writerow([str(r['path']), r['codec'], r['codec_raw'],
                            r['path'].suffix.lower().lstrip('.'), r['format_name']])
        print(f'CSV を書き出しました: {args.csv}', file=sys.stderr)

    return 0


if __name__ == '__main__':
    sys.exit(main())
