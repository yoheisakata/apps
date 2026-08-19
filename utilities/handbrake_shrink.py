#!/usr/bin/env python3
"""
HandBrakeCLI 経由での H.265 再圧縮スクリプト

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  試し変換（本番前に必ず1本チェック）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  python3 handbrake_shrink.py "<フォルダ>" --preview
  → フォルダ内の先頭ファイルの一部（既定: 60秒地点から30秒間）だけを
    「<元ファイル名>_hbpreview.mp4」として書き出す。元ファイルは触らない。
    QuickTime等で画質を確認してから本番実行するのを強く推奨。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  本番実行方法（バックグラウンド・スリープ防止付き）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  caffeinate -i python3 handbrake_shrink.py "<フォルダ>" \
    > handbrake_shrink.log 2>&1 &

  進捗確認:  tail -f handbrake_shrink.log
  中断:      kill <PID>
  再開:      同じコマンドを再実行（済みファイルは自動スキップ）

  依存: brew install handbrake  (HandBrakeCLI)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  処理内容
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

使い方: python3 handbrake_shrink.py <フォルダパス> [オプション]

  既にH.265(HEVC)+mp4になっている動画（放送録画など）を、さらに小さい
  H.265 10bitに再エンコードする。encode_h265.py はH.265以外→H.265の
  変換が対象で、既にH.265+mp4のファイルはスキップする。本スクリプトは
  その後段として、既にH.265のファイルをさらに縮める用途。

  既定のエンコーダは Apple VideoToolbox のハードウェアエンコーダ
  (vt_h265_10bit)。ソフトウェアエンコーダ(x265)は圧縮効率は良いが実測で
  1080p60ソースの10秒処理に約97秒かかった（58分の1話で約9時間相当）ため、
  数十話規模のバッチには非現実的で既定では使わない。時間をかけてでも
  圧縮効率を優先したい場合は --encoder x265_10bit --preset slow を指定する。

  変換後のサイズが元より --min-savings (既定5%) 以上縮まなければ、
  そのファイルは変換せず元のまま残す（H.265の再エンコードは必ず縮むとは
  限らないため）。

  画質(--quality)の意味はエンコーダにより逆になる点に注意:
    vt_h265_10bit (VideoToolbox) : 0-100、大きいほど高画質・大きいファイル
    x265 / x265_10bit            : 0-51 (CRF)、小さいほど高画質・大きいファイル

オプション:
  --dry-run           実際には処理せず対象ファイルを確認するだけ
  --preview [FILE]    指定ファイル（省略時はフォルダ内先頭の1本）の一部だけ
                       試し変換する。本編ファイルは変更しない
  --preview-offset SEC  試し変換の開始位置（秒、既定60）
  --preview-seconds SEC 試し変換の長さ（秒、既定30）
  --quality Q         画質。既定はエンコーダに応じて vt系50 / x265系22
  --encoder ENC        vt_h265_10bit(既定) / vt_h265 / x265_10bit / x265
  --preset PRESET      x265系のみ有効（ultrafast〜placebo、既定slow）
  --min-savings PCT   この割合(%)以上縮まなければ元ファイルを残す（既定5）
  --min-size MB        指定サイズ(MB)以上のファイルのみ対象（既定: 制限なし）
  --refresh-cache      キャッシュを無視して全ファイルを再処理する
"""

import re
import sys
import json
import subprocess
import argparse
from pathlib import Path

VIDEO_EXTENSIONS = {'.mp4', '.mov', '.m4v', '.mkv'}
PROGRESS_RE = re.compile(r'Encoding: task \d+ of \d+, (\d+\.\d+) %')


def load_cache(cache_path: Path) -> dict:
    if cache_path.exists():
        try:
            return json.loads(cache_path.read_text(encoding='utf-8'))
        except Exception:
            pass
    return {}


def save_cache(cache_path: Path, cache: dict) -> None:
    try:
        cache_path.write_text(json.dumps(cache, indent=2, ensure_ascii=False),
                               encoding='utf-8')
    except Exception:
        pass


def get_duration_sec(filepath):
    result = subprocess.run(
        ['ffprobe', '-v', 'quiet', '-print_format', 'json', '-show_format', str(filepath)],
        capture_output=True, text=True, timeout=60
    )
    try:
        data = json.loads(result.stdout)
        return float(data['format']['duration'])
    except Exception:
        return None


def default_quality(encoder: str) -> float:
    return 50.0 if encoder.startswith('vt_') else 22.0


def build_cmd(src: Path, dst: Path, encoder: str, quality: float, preset: str,
              start_at=None, stop_at=None):
    cmd = ['HandBrakeCLI', '-i', str(src), '-o', str(dst),
           '-e', encoder, '-q', str(quality),
           '-E', 'copy:aac', '-B', '128',
           '-f', 'av_mp4', '-O']
    if not encoder.startswith('vt_'):
        cmd += ['--encoder-preset', preset]
    if start_at is not None:
        cmd += ['--start-at', f'seconds:{start_at}']
    if stop_at is not None:
        cmd += ['--stop-at', f'seconds:{stop_at}']
    return cmd


def run_handbrake_with_progress(cmd, label, total_sec):
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    last_pct = -1
    tail = []
    for line in proc.stdout:
        tail.append(line)
        if len(tail) > 40:
            tail.pop(0)
        m = PROGRESS_RE.search(line)
        if m:
            pct = int(float(m.group(1)))
            if pct != last_pct:
                print(f'\r  {label}: {pct:3d}%', end='', flush=True)
                last_pct = pct
    proc.wait()
    if proc.returncode != 0:
        return False, ''.join(tail)
    print(f'\r  {label}: 100%', flush=True)
    return True, ''


def get_file_size_mb(path):
    try:
        return path.stat().st_size / 1024 / 1024
    except Exception:
        return 0.0


def collect_files(folder: Path):
    return sorted([
        p for p in folder.rglob('*')
        if p.is_file() and p.suffix.lower() in VIDEO_EXTENSIONS
        and not p.name.startswith('.')
        and '_hbshrink' not in p.stem
        and '_hbpreview' not in p.stem
    ])


def preview(folder: Path, target: str, offset: int, seconds: int,
            encoder: str, quality: float, preset: str):
    folder = Path(folder)
    if target:
        src = Path(target)
        if not src.is_absolute():
            src = folder / target
    else:
        files = collect_files(folder)
        if not files:
            print('対象動画が見つかりません')
            sys.exit(1)
        src = files[0]

    if not src.exists():
        print(f'エラー: ファイルが見つかりません: {src}')
        sys.exit(1)

    dst = src.with_name(src.stem + '_hbpreview.mp4')
    print(f'試し変換: {src.name}')
    print(f'  区間: {offset}秒〜{offset + seconds}秒, encoder={encoder}, quality={quality}')
    cmd = build_cmd(src, dst, encoder, quality, preset, start_at=offset, stop_at=seconds)
    success, err = run_handbrake_with_progress(cmd, '試し変換中', seconds)
    if not success:
        print(f'  [ERROR] HandBrakeCLI 失敗:\n{err[-800:]}')
        sys.exit(1)
    print(f'  完了 → {dst}')
    print('  QuickTimeなどで画質を確認してから本番実行してください。')


def process_folder(folder, encoder='vt_h265_10bit', quality=None, preset='slow',
                    dry_run=False, min_size_mb=0, min_savings_pct=5.0,
                    refresh_cache=False):
    folder = Path(folder)
    if not folder.exists() or not folder.is_dir():
        print(f'エラー: フォルダが見つかりません: {folder}')
        sys.exit(1)

    if quality is None:
        quality = default_quality(encoder)

    cache_path = folder / '.handbrake_shrink_cache.json'
    cache = {} if refresh_cache else load_cache(cache_path)

    print(f'対象フォルダ: {folder}')
    print(f'モード: {"DRY-RUN" if dry_run else "実行"}')
    print(f'エンコーダ: {encoder}, 画質: {quality}' +
          (f', preset: {preset}' if not encoder.startswith('vt_') else ''))
    print(f'最低削減率: {min_savings_pct}% 未満なら元ファイルを維持')
    if min_size_mb > 0:
        print(f'サイズフィルター: {min_size_mb} MB 以上のみ変換')
    print()

    files = collect_files(folder)
    total = len(files)
    shrunk = 0
    kept_original = 0
    failed = 0
    skipped_size = 0

    print(f'動画ファイル: {total}件\n')

    for i, src in enumerate(files, 1):
        print(f'[{i}/{total}] {src.relative_to(folder)}')

        src_key = str(src)
        if src_key in cache:
            cached_action = cache[src_key].get('action')
            if cached_action in ('shrunk', 'kept_original'):
                print(f'  [CACHED] {cached_action} (前回実行済み)')
                if cached_action == 'shrunk':
                    shrunk += 1
                else:
                    kept_original += 1
                continue

        orig_mb = get_file_size_mb(src)
        if min_size_mb > 0 and orig_mb < min_size_mb:
            print(f'  → スキップ（{orig_mb:.1f} MB < 最小 {min_size_mb} MB）')
            skipped_size += 1
            continue

        tmp_dst = src.with_name(src.stem + '_hbshrink.mp4')

        if dry_run:
            print(f'  [DRY-RUN] {encoder} q={quality} → {tmp_dst.name}')
            continue

        total_sec = get_duration_sec(src)
        cmd = build_cmd(src, tmp_dst, encoder, quality, preset)
        success, err = run_handbrake_with_progress(cmd, 'エンコード中', total_sec)
        if not success:
            print(f'  [ERROR] HandBrakeCLI 失敗:\n{err[-800:]}')
            if tmp_dst.exists():
                tmp_dst.unlink()
            failed += 1
            continue

        new_mb = get_file_size_mb(tmp_dst)
        savings_pct = (1 - new_mb / orig_mb) * 100 if orig_mb > 0 else 0

        if savings_pct < min_savings_pct:
            print(f'  削減率 {savings_pct:+.1f}% ({orig_mb:.1f} MB → {new_mb:.1f} MB) '
                  f'< 最低{min_savings_pct}% → 元ファイルを維持')
            tmp_dst.unlink()
            cache[src_key] = {'action': 'kept_original', 'savings_pct': savings_pct}
            kept_original += 1
            continue

        final = src
        src.unlink()
        tmp_dst.rename(final)
        print(f'  完了 ({orig_mb:.1f} MB → {new_mb:.1f} MB, {-savings_pct:+.0f}%)')
        cache[src_key] = {'action': 'shrunk', 'savings_pct': savings_pct}
        shrunk += 1

    print(f'\n=== 結果 ===')
    print(f'  縮小:                   {shrunk}件')
    print(f'  削減率不足で元のまま:   {kept_original}件')
    print(f'  サイズ不足でスキップ:   {skipped_size}件')
    print(f'  失敗:                   {failed}件')

    if cache:
        save_cache(cache_path, cache)


def main():
    parser = argparse.ArgumentParser(
        description='HandBrakeCLI で H.265 動画をさらに再圧縮する',
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument('folder', help='対象フォルダのパス')
    parser.add_argument('--dry-run', action='store_true',
                         help='実際には処理せず、対象ファイルを確認するだけ')
    parser.add_argument('--preview', nargs='?', const='', metavar='FILE',
                         help='指定ファイル（省略時は先頭の1本）の一部だけ試し変換する')
    parser.add_argument('--preview-offset', type=int, default=60, metavar='SEC')
    parser.add_argument('--preview-seconds', type=int, default=30, metavar='SEC')
    parser.add_argument('--encoder', default='vt_h265_10bit',
                         choices=['vt_h265_10bit', 'vt_h265', 'x265_10bit', 'x265'])
    parser.add_argument('--quality', type=float, default=None,
                         help='画質。既定はエンコーダに応じて自動選択')
    parser.add_argument('--preset', default='slow',
                         choices=['ultrafast', 'superfast', 'veryfast', 'faster', 'fast',
                                  'medium', 'slow', 'slower', 'veryslow', 'placebo'],
                         help='x265系のみ有効（既定: slow）')
    parser.add_argument('--min-savings', type=float, default=5.0, metavar='PCT',
                         help='この割合(%%)以上縮まなければ元ファイルを残す（既定: 5）')
    parser.add_argument('--min-size', type=float, default=0, metavar='MB',
                         help='指定サイズ(MB)以上のファイルのみ変換（既定: 制限なし）')
    parser.add_argument('--refresh-cache', action='store_true',
                         help='キャッシュを無視して全ファイルを再処理する')
    args = parser.parse_args()

    quality = args.quality if args.quality is not None else default_quality(args.encoder)

    if args.preview is not None:
        preview(args.folder, args.preview or None, args.preview_offset, args.preview_seconds,
                args.encoder, quality, args.preset)
    else:
        process_folder(args.folder, encoder=args.encoder, quality=quality, preset=args.preset,
                        dry_run=args.dry_run, min_size_mb=args.min_size,
                        min_savings_pct=args.min_savings, refresh_cache=args.refresh_cache)


if __name__ == '__main__':
    main()
