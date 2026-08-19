#!/usr/bin/env python3
"""
H.265 (HEVC) 再エンコード & mp4統一スクリプト

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  実行方法（バックグラウンド・スリープ防止付き）
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  caffeinate -i python3 /Volumes/backup1/leo_video/encode_h265.py /Volumes/backup1/leo_video \
    > /Volumes/backup1/leo_video/encode_h265.log 2>&1 &

  進捗確認:  tail -f /Volumes/backup1/leo_video/encode_h265.log
  中断:      kill <PID>
  再開:      同じコマンドを再実行（済みファイルは自動スキップ）

  依存: brew install ffmpeg

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  処理内容
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

使い方: python3 encode_h265.py <フォルダパス> [オプション]

  - H.265以外 → H.265に再エンコードして .mp4 に変換
  - H.265だが .mov → コンテナのみ .mp4 に変換（再エンコードなし・劣化なし・高速）
  - H.265かつ .mp4 → スキップ
変換成功後、オリジナルを削除する。

オプション:
  --dry-run          実際には処理せず対象ファイルを確認するだけ
  --report [FILE]    変換が必要なファイルのサマリーをレポート出力（変換はしない）
  --skip-if-larger   H.265エンコード後のサイズが元より大きい場合、そのH.265は破棄し、
                      元のコーデックのまま .mp4 コンテナ変換のみ行う（既に.mp4なら何もしない）
"""

import sys
import json
import subprocess
import argparse
from datetime import datetime
from pathlib import Path

VIDEO_EXTENSIONS = {'.mp4', '.mov', '.m4v', '.mkv', '.avi', '.mts', '.m2ts', '.mpg', '.mpeg'}

def load_cache(cache_path: Path) -> dict:
    """キャッシュを読み込む (無かったら空)。"""
    if cache_path.exists():
        try:
            return json.loads(cache_path.read_text(encoding='utf-8'))
        except Exception:
            pass
    return {}


def save_cache(cache_path: Path, cache: dict) -> None:
    """キャッシュを保存する。"""
    try:
        cache_path.write_text(json.dumps(cache, indent=2, ensure_ascii=False),
                             encoding='utf-8')
    except Exception:
        pass

def get_video_codec(filepath):
    """動画のビデオコーデックを取得する"""
    result = subprocess.run(
        ['ffprobe', '-v', 'quiet', '-print_format', 'json',
         '-show_streams', '-select_streams', 'v:0', str(filepath)],
        capture_output=True, text=True, timeout=60
    )
    try:
        data = json.loads(result.stdout)
        streams = data.get('streams', [])
        if streams:
            return streams[0].get('codec_name', '').lower()
    except Exception:
        pass
    return None

def is_h265(codec):
    return codec in ('hevc', 'h265')

def get_duration_sec(filepath):
    """動画の総時間（秒）を取得する"""
    result = subprocess.run(
        ['ffprobe', '-v', 'quiet', '-print_format', 'json',
         '-show_format', str(filepath)],
        capture_output=True, text=True, timeout=60
    )
    try:
        data = json.loads(result.stdout)
        return float(data['format']['duration'])
    except Exception:
        return None

def run_ffmpeg_with_progress(cmd, label, total_sec):
    """ffmpeg をリアルタイム進捗付きで実行する。total_sec=None の場合は % 表示なし。"""
    # -progress で進捗を stdout に出力させる
    progress_cmd = cmd[:-1] + ['-progress', 'pipe:1', '-nostats', cmd[-1]]
    proc = subprocess.Popen(progress_cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    last_pct = -1
    stderr_lines = []

    for line in proc.stdout:
        line = line.strip()
        if line.startswith('out_time_ms='):
            try:
                out_ms = int(line.split('=')[1])
                if total_sec and total_sec > 0:
                    pct = min(int(out_ms / (total_sec * 1_000_000) * 100), 99)
                    if pct != last_pct:
                        print(f'\r  {label}: {pct:3d}%', end='', flush=True)
                        last_pct = pct
            except ValueError:
                pass
        elif line.startswith('progress=end'):
            print(f'\r  {label}: 100%', flush=True)

    _, stderr_output = proc.communicate()
    # stderr はエラー確認用に保持
    if proc.returncode != 0:
        return False, stderr_output
    return True, ''

def remux_to_mp4(src, dst, dry_run=False):
    """コンテナのみ .mp4 に変換（ストリームコピー、再エンコードなし）"""
    cmd = [
        'ffmpeg', '-i', str(src),
        '-c', 'copy',          # 映像・音声ともコピー（再エンコードなし）
        '-tag:v', 'hvc1',      # Apple互換タグ
        '-map_metadata', '0',  # メタデータ保持
        '-movflags', '+faststart',
        '-y',
        str(dst)
    ]
    if dry_run:
        print(f'  [DRY-RUN] remux → {dst.name}')
        return True

    total_sec = get_duration_sec(src)
    success, err = run_ffmpeg_with_progress(cmd, 'コンテナ変換中', total_sec)
    if not success:
        print(f'  [ERROR] ffmpeg 失敗:\n{err[-500:]}')
        if dst.exists():
            dst.unlink()
        return False
    return True

def encode_to_h265(src, dst, crf=20, preset='slow', dry_run=False):
    """H.265に再エンコードして .mp4 に変換（libx265 ソフトウェアエンコーダー）"""
    if dry_run:
        print(f'  [DRY-RUN] encode H.265 → {dst.name}')
        return True

    cmd = [
        'ffmpeg', '-i', str(src),
        '-c:v', 'libx265',
        '-crf', str(crf),
        '-preset', preset,
        '-c:a', 'aac',
        '-b:a', '128k',
        '-tag:v', 'hvc1',
        '-map_metadata', '0',
        '-movflags', '+faststart',
        '-y',
        str(dst)
    ]
    print(f'  H.265エンコード開始 (libx265, CRF={crf})')
    total_sec = get_duration_sec(src)
    success, err = run_ffmpeg_with_progress(cmd, 'エンコード中', total_sec)
    if not success:
        print(f'  [ERROR] ffmpeg 失敗:\n{err[-500:]}')
        if dst.exists():
            dst.unlink()
        return False
    return True

def finalize(src, tmp_dst, dry_run=False):
    """変換成功後: オリジナル削除 → 最終ファイル名にリネーム"""
    if dry_run:
        return True
    orig_mb = src.stat().st_size / 1024 / 1024
    final = src.with_suffix('.mp4')
    src.unlink()
    if tmp_dst != final:
        if final.exists():
            # 衝突時は _h265 のままにする
            size_mb = tmp_dst.stat().st_size / 1024 / 1024
            print(f'  完了 (名前衝突のため {tmp_dst.name} として保存, {orig_mb:.1f} MB → {size_mb:.1f} MB)')
            return True
        tmp_dst.rename(final)
    size_mb = final.stat().st_size / 1024 / 1024
    diff_pct = (size_mb / orig_mb - 1) * 100 if orig_mb > 0 else 0
    print(f'  完了 ({orig_mb:.1f} MB → {size_mb:.1f} MB, {diff_pct:+.0f}%)')
    return True

def get_file_size_mb(path):
    try:
        return path.stat().st_size / 1024 / 1024
    except Exception:
        return 0.0


def collect_files(folder):
    """フォルダ内の対象動画ファイルを収集してコーデック情報と共に返す"""
    files = sorted([
        p for p in folder.rglob('*')
        if p.is_file() and p.suffix.lower() in VIDEO_EXTENSIONS
        and not p.name.startswith('.')
        and '_h265' not in p.stem
    ])

    results = []
    total = len(files)
    for i, src in enumerate(files, 1):
        print(f'\r  解析中... [{i}/{total}] {src.name[:50]}', end='', flush=True)
        try:
            codec = get_video_codec(src)
        except subprocess.TimeoutExpired:
            codec = None

        already_mp4 = src.suffix.lower() == '.mp4'
        already_h265 = is_h265(codec) if codec else False

        if already_h265 and already_mp4:
            action = 'skip'
        elif already_h265 and not already_mp4:
            action = 'remux'
        elif codec is None:
            action = 'error'
        else:
            action = 'encode'

        results.append({
            'path': src,
            'codec': codec or '不明',
            'action': action,
            'size_mb': get_file_size_mb(src),
        })

    print()  # 改行
    return results


def report_only(folder, report_file=None, min_size_mb=0):
    """変換が必要なファイルを解析してレポートを出力する（変換はしない）"""
    folder = Path(folder)
    if not folder.exists() or not folder.is_dir():
        print(f'エラー: フォルダが見つかりません: {folder}')
        sys.exit(1)

    print(f'対象フォルダ: {folder}')
    if min_size_mb > 0:
        print(f'サイズフィルター: {min_size_mb} MB 以上のみ')
    print(f'ファイルを解析中...')

    results = collect_files(folder)

    # サイズフィルター適用（remux/encode のみ対象）
    def filtered(action):
        return [r for r in results if r['action'] == action
                and (min_size_mb == 0 or action == 'skip' or r['size_mb'] >= min_size_mb)]

    skip   = [r for r in results if r['action'] == 'skip']
    remux  = filtered('remux')
    encode = filtered('encode')
    error  = [r for r in results if r['action'] == 'error']
    skipped_size = [r for r in results
                    if r['action'] in ('remux', 'encode') and r['size_mb'] < min_size_mb]

    total_encode_mb = sum(r['size_mb'] for r in encode)
    total_remux_mb  = sum(r['size_mb'] for r in remux)

    lines = []
    lines.append('encode_h265 変換レポート')
    lines.append(f'生成日時  : {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}')
    lines.append(f'対象フォルダ: {folder}')
    lines.append('')
    lines.append('=== サマリー ===')
    lines.append(f'  スキップ (H.265+mp4済み)    : {len(skip):4d} 件')
    lines.append(f'  コンテナ変換のみ (.mov→.mp4): {len(remux):4d} 件  ({total_remux_mb:.1f} MB)')
    lines.append(f'  H.265エンコード必要          : {len(encode):4d} 件  ({total_encode_mb:.1f} MB)')
    if min_size_mb > 0:
        lines.append(f'  サイズ不足でスキップ         : {len(skipped_size):4d} 件  (< {min_size_mb} MB)')
    lines.append(f'  解析エラー                   : {len(error):4d} 件')
    lines.append(f'  合計                         : {len(results):4d} 件')
    lines.append('')

    if encode:
        lines.append('=== H.265エンコードが必要なファイル ===')
        for r in encode:
            rel = r['path'].relative_to(folder)
            lines.append(f'  [{r["codec"]:>8}]  {r["size_mb"]:6.1f} MB  {rel}')
        lines.append('')

    if remux:
        lines.append('=== コンテナ変換のみ（再エンコードなし）===')
        for r in remux:
            rel = r['path'].relative_to(folder)
            lines.append(f'  [{r["codec"]:>8}]  {r["size_mb"]:6.1f} MB  {rel}')
        lines.append('')

    if error:
        lines.append('=== 解析エラー ===')
        for r in error:
            rel = r['path'].relative_to(folder)
            lines.append(f'  {rel}')
        lines.append('')

    output = '\n'.join(lines)
    print('\n' + output)

    if report_file:
        Path(report_file).expanduser().write_text(output, encoding='utf-8')
        print(f'レポートを保存しました: {report_file}')


def process_folder(folder, crf=20, preset='slow', dry_run=False, min_size_mb=0,
                    remux_only=False, skip_if_larger=False, refresh_cache=False):
    folder = Path(folder)
    if not folder.exists() or not folder.is_dir():
        print(f'エラー: フォルダが見つかりません: {folder}')
        sys.exit(1)

    cache_path = folder / '.encode_h265_cache.json'
    cache = {} if refresh_cache else load_cache(cache_path)

    print(f'対象フォルダ: {folder}')
    print(f'モード: {"DRY-RUN" if dry_run else "実行"}')
    if remux_only:
        print(f'コンテナ変換のみ（エンコードなし）')
    else:
        print(f'品質(CRF): {crf}, 速度: {preset}')
    if skip_if_larger:
        print(f'サイズが大きくなる場合はH.265を破棄しコンテナ変換のみ行う')
    if min_size_mb > 0:
        print(f'サイズフィルター: {min_size_mb} MB 以上のみ変換')
    print()

    files = sorted([
        p for p in folder.rglob('*')
        if p.is_file() and p.suffix.lower() in VIDEO_EXTENSIONS
        and not p.name.startswith('.')
        and '_h265' not in p.stem
    ])

    total = len(files)
    skipped_h265 = 0   # 既にH.265かつ.mp4
    remuxed = 0        # H.265だが.mov → .mp4コンテナ変換
    encoded = 0        # H.265以外 → H.265エンコード
    kept_original = 0  # H.265の方が大きかったためコンテナ変換のみ/変更なし
    failed = 0
    skipped_err = 0

    print(f'動画ファイル: {total}件\n')

    for i, src in enumerate(files, 1):
        print(f'[{i}/{total}] {src.relative_to(folder)}')

        src_key = str(src)
        if src_key in cache:
            cached_action = cache[src_key].get('action')
            if cached_action in ('remuxed', 'encoded', 'kept_original'):
                print(f'  [CACHED] {cached_action} (前回実行済み)')
                if cached_action == 'remuxed':
                    remuxed += 1
                elif cached_action == 'encoded':
                    encoded += 1
                elif cached_action == 'kept_original':
                    kept_original += 1
                continue

        try:
            codec = get_video_codec(src)
        except subprocess.TimeoutExpired:
            print(f'  [SKIP] ffprobe タイムアウト')
            skipped_err += 1
            continue

        if codec is None:
            print(f'  [SKIP] コーデック取得失敗')
            skipped_err += 1
            continue

        already_mp4 = src.suffix.lower() == '.mp4'
        already_h265_flag = is_h265(codec)

        print(f'  コーデック: {codec}, 拡張子: {src.suffix.lower()}', end='')

        if already_h265_flag and already_mp4:
            print(' → スキップ（H.265かつ.mp4）')
            cache[src_key] = {'action': 'skip', 'codec': codec}
            skipped_h265 += 1
            continue

        # サイズフィルター
        if min_size_mb > 0:
            size_mb = get_file_size_mb(src)
            if size_mb < min_size_mb:
                print(f' → スキップ（{size_mb:.1f} MB < 最小 {min_size_mb} MB）')
                skipped_h265 += 1
                continue

        tmp_dst = src.with_name(src.stem + '_h265.mp4')

        if already_h265_flag and not already_mp4:
            # コンテナのみ変換（ストリームコピー）
            print(' → .mp4にコンテナ変換（再エンコードなし）')
            success = remux_to_mp4(src, tmp_dst, dry_run=dry_run)
            if success:
                finalize(src, tmp_dst, dry_run=dry_run)
                cache[src_key] = {'action': 'remuxed', 'codec': codec}
                remuxed += 1
            else:
                failed += 1
        elif remux_only:
            # --remux-only のときはエンコードが必要なファイルをスキップ
            print(' → スキップ（H.265でないためエンコードが必要、--remux-only 指定）')
            cache[src_key] = {'action': 'skip', 'codec': codec, 'reason': 'remux_only'}
            skipped_h265 += 1
        else:
            # H.265に再エンコード
            print(f' → H.265に再エンコード')
            success = encode_to_h265(src, tmp_dst, crf=crf, preset=preset, dry_run=dry_run)
            if not success:
                failed += 1
                continue

            if skip_if_larger and not dry_run:
                orig_mb = get_file_size_mb(src)
                new_mb = get_file_size_mb(tmp_dst)
                if new_mb >= orig_mb:
                    print(f'  H.265の方が大きい ({new_mb:.1f} MB >= {orig_mb:.1f} MB) → H.265を破棄')
                    tmp_dst.unlink()
                    if already_mp4:
                        print('  既に.mp4のため変更なし')
                        cache[src_key] = {'action': 'kept_original', 'codec': codec, 'reason': 'larger_mp4'}
                    else:
                        print('  コンテナのみ.mp4に変換（元コーデックのまま）')
                        remux_dst = src.with_name(src.stem + '_mp4.mp4')
                        if remux_to_mp4(src, remux_dst, dry_run=dry_run):
                            finalize(src, remux_dst, dry_run=dry_run)
                            cache[src_key] = {'action': 'kept_original', 'codec': codec, 'reason': 'larger_remux'}
                        else:
                            failed += 1
                            continue
                    kept_original += 1
                    continue

            finalize(src, tmp_dst, dry_run=dry_run)
            cache[src_key] = {'action': 'encoded', 'codec': codec}
            encoded += 1

    print(f'\n=== 結果 ===')
    print(f'  スキップ (H.265+mp4済み): {skipped_h265}件')
    print(f'  コンテナ変換のみ (.mov→.mp4): {remuxed}件')
    print(f'  H.265エンコード:          {encoded}件')
    if skip_if_larger:
        print(f'  H.265の方が大きく元コーデック維持: {kept_original}件')
    print(f'  失敗:                     {failed}件')
    print(f'  エラースキップ:           {skipped_err}件')

    if cache:
        save_cache(cache_path, cache)

def main():
    parser = argparse.ArgumentParser(
        description='H.265再エンコード & mp4統一スクリプト',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
処理内容:
  H.265以外       → H.265に再エンコード + .mp4に変換
  H.265だが.mov   → コンテナのみ.mp4に変換（再エンコードなし・高速・劣化なし）
  H.265かつ.mp4   → スキップ

--skip-if-larger 指定時、H.265エンコード後のサイズが元より大きければ
そのH.265は破棄し、元のコーデックのまま.mp4コンテナ変換のみ行う
（既に.mp4なら変更なし）。
        """
    )
    parser.add_argument('folder', help='対象フォルダのパス')
    parser.add_argument('--dry-run', action='store_true',
                        help='実際には処理せず、対象ファイルを確認するだけ')
    parser.add_argument('--report', nargs='?', const='', metavar='FILE',
                        help='変換が必要なファイルのサマリーを表示（変換はしない）。'
                             'FILEを指定するとファイルにも保存')
    parser.add_argument('--min-size', type=float, default=0, metavar='MB',
                        help='指定サイズ(MB)以上のファイルのみ変換（デフォルト: 制限なし）')
    parser.add_argument('--remux-only', action='store_true',
                        help='H.265だが.mp4でないファイルのコンテナ変換のみ行う（エンコードはしない）')
    parser.add_argument('--skip-if-larger', action='store_true',
                        help='H.265エンコード後のサイズが元より大きい場合、H.265を破棄し'
                             '元コーデックのまま.mp4コンテナ変換のみ行う（既に.mp4なら変更なし）')
    parser.add_argument('--crf', type=int, default=20,
                        help='品質設定 (18=高品質〜28=標準、デフォルト: 20)')
    parser.add_argument('--preset', default='slow',
                        choices=['ultrafast','superfast','veryfast','faster',
                                 'fast','medium','slow','slower','veryslow'],
                        help='エンコード速度 (デフォルト: medium)')
    parser.add_argument('--refresh-cache', action='store_true',
                        help='キャッシュを無視して全ファイルを再処理する')
    args = parser.parse_args()

    if args.report is not None:
        report_file = args.report if args.report else None
        report_only(args.folder, report_file=report_file, min_size_mb=args.min_size)
    else:
        process_folder(args.folder, crf=args.crf, preset=args.preset,
                       dry_run=args.dry_run, min_size_mb=args.min_size,
                       remux_only=args.remux_only, skip_if_larger=args.skip_if_larger,
                       refresh_cache=args.refresh_cache)

if __name__ == '__main__':
    main()
