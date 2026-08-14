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
  python3 check_video_codecs.py <フォルダ> --html ~/Desktop/codecs.html
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
         '-show_entries',
         'stream=codec_name,width,height:format=format_name,duration',
         '-of', 'json', str(path)],
        capture_output=True, text=True
    )
    codec_raw = ''
    format_name = ''
    duration = 0.0
    width = height = 0
    try:
        data = json.loads(result.stdout)
        streams = data.get('streams') or []
        if streams:
            codec_raw = streams[0].get('codec_name', '') or ''
            width = int(streams[0].get('width') or 0)
            height = int(streams[0].get('height') or 0)
        fmt = data.get('format') or {}
        format_name = fmt.get('format_name', '') or ''
        duration = float(fmt.get('duration') or 0)
    except Exception:
        pass

    try:
        size = path.stat().st_size
    except OSError:
        size = 0

    codec = CODEC_LABELS.get(codec_raw, codec_raw or '(不明)')
    is_mp4 = path.suffix.lower() == '.mp4'
    return {
        'path': path,
        'codec': codec,
        'codec_raw': codec_raw,
        'format_name': format_name,
        'is_mp4': is_mp4,
        'ok': bool(codec_raw),
        'size': size,
        'duration': duration,
        'width': width,
        'height': height,
    }


def human_size(n: int) -> str:
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if n < 1024 or unit == 'TB':
            return f'{n:.1f} {unit}' if unit != 'B' else f'{n} B'
        n /= 1024
    return f'{n:.1f} TB'


def human_duration(sec: float) -> str:
    if not sec:
        return '-'
    s = int(round(sec))
    h, rem = divmod(s, 3600)
    m, s = divmod(rem, 60)
    return f'{h}:{m:02d}:{s:02d}' if h else f'{m}:{s:02d}'


def group_of(r: dict) -> str:
    """フィルタ用のグループ名"""
    if not r['ok']:
        return 'error'
    if r['codec'] == 'h265':
        return 'h265-mp4' if r['is_mp4'] else 'h265-other'
    return 'other-mp4' if r['is_mp4'] else 'other-other'


GROUP_LABELS = {
    'h265-mp4': 'h265 + mp4',
    'h265-other': 'h265 だが mp4 でない',
    'other-mp4': 'h265 でない (mp4)',
    'other-other': 'h265 でない (mp4 でない)',
    'error': '読み取り失敗',
}


def write_html(out_path: Path, root: Path, results: list[dict],
               targets: list[dict], label: str) -> None:
    """1枚の自己完結 HTML(検索・絞り込み・ソート付き)に書き出す。

    上部のサマリーは全ファイル、表は targets(`--list` で選んだ対象)だけ。
    """
    from datetime import datetime
    from html import escape

    counts = {g: 0 for g in GROUP_LABELS}
    sizes = {g: 0 for g in GROUP_LABELS}
    for r in results:
        g = group_of(r)
        counts[g] += 1
        sizes[g] += r['size']

    shown = {g: 0 for g in GROUP_LABELS}
    for r in targets:
        shown[group_of(r)] += 1

    rows = []
    for r in sorted(targets, key=lambda x: str(x['path'])):
        g = group_of(r)
        rel = str(r['path'])
        if rel.startswith(str(root)):
            rel = rel[len(str(root)):].lstrip('/')
        res = f'{r["width"]}x{r["height"]}' if r['width'] else '-'
        rows.append(
            f'<tr data-g="{g}">'
            f'<td class="path" title="{escape(str(r["path"]))}">{escape(rel)}</td>'
            f'<td><span class="tag {"ok" if r["codec"] == "h265" else "warn"}">'
            f'{escape(r["codec"])}</span></td>'
            f'<td><span class="tag {"ok" if r["is_mp4"] else "warn"}">'
            f'{escape(r["path"].suffix.lower().lstrip(".") or "-")}</span></td>'
            f'<td class="num" data-v="{r["size"]}">{human_size(r["size"])}</td>'
            f'<td class="num" data-v="{r["duration"]:.3f}">'
            f'{human_duration(r["duration"])}</td>'
            f'<td class="num">{res}</td>'
            f'</tr>'
        )

    chips = ['<button class="chip active" data-f="all">'
             f'すべて <b>{len(targets)}</b></button>']
    for g, glabel in GROUP_LABELS.items():
        if shown[g]:
            chips.append(f'<button class="chip" data-f="{g}">{escape(glabel)} '
                         f'<b>{shown[g]}</b></button>')

    cards = []
    for g, glabel in GROUP_LABELS.items():
        if counts[g]:
            dim = '' if shown[g] else ' dim'
            cards.append(f'<div class="card{dim}"><div class="k">'
                         f'{escape(glabel)}</div>'
                         f'<div class="v">{counts[g]}</div>'
                         f'<div class="s">{human_size(sizes[g])}</div></div>')

    html = f'''<!DOCTYPE html>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>動画コーデック調査 — {escape(root.name)}</title>
<style>
  :root {{ color-scheme: light dark; --bg:#f6f7f9; --fg:#1c1f24; --sub:#6b7280;
    --panel:#fff; --line:#e3e6ea; --ok:#0f7b47; --okbg:#e4f5ec;
    --warn:#9a3412; --warnbg:#fdecdc; --accent:#2563eb; }}
  @media (prefers-color-scheme: dark) {{
    :root {{ --bg:#14171b; --fg:#e6e8ea; --sub:#9aa3ad; --panel:#1c2027;
      --line:#2c323a; --ok:#6ee7a8; --okbg:#123024; --warn:#fbbf7a;
      --warnbg:#3a2411; --accent:#7aa2ff; }}
  }}
  * {{ box-sizing: border-box; }}
  body {{ margin:0; padding:24px; background:var(--bg); color:var(--fg);
    font:14px/1.6 -apple-system, "Hiragino Sans", sans-serif; }}
  h1 {{ font-size:20px; margin:0 0 4px; }}
  h2 {{ font-size:15px; margin:0 0 8px; }}
  .meta {{ color:var(--sub); font-size:12px; margin-bottom:20px;
    word-break:break-all; }}
  .cards {{ display:flex; flex-wrap:wrap; gap:12px; margin-bottom:20px; }}
  .card {{ background:var(--panel); border:1px solid var(--line);
    border-radius:10px; padding:12px 16px; min-width:150px; }}
  .card .k {{ font-size:12px; color:var(--sub); }}
  .card .v {{ font-size:26px; font-weight:700; line-height:1.2; }}
  .card .s {{ font-size:12px; color:var(--sub); }}
  .card.dim {{ opacity:.45; }}
  .bar {{ display:flex; flex-wrap:wrap; gap:8px; align-items:center;
    margin-bottom:12px; position:sticky; top:0; background:var(--bg);
    padding:8px 0; z-index:2; }}
  .chip {{ border:1px solid var(--line); background:var(--panel);
    color:var(--fg); border-radius:999px; padding:6px 12px; font-size:13px;
    cursor:pointer; font-family:inherit; }}
  .chip.active {{ background:var(--accent); border-color:var(--accent);
    color:#fff; }}
  #q {{ flex:1; min-width:180px; padding:7px 12px; border-radius:8px;
    border:1px solid var(--line); background:var(--panel); color:var(--fg);
    font-family:inherit; font-size:13px; }}
  #count {{ color:var(--sub); font-size:12px; }}
  .wrap {{ overflow-x:auto; background:var(--panel);
    border:1px solid var(--line); border-radius:10px; }}
  table {{ border-collapse:collapse; width:100%; font-size:13px; }}
  th, td {{ padding:7px 12px; text-align:left; border-bottom:1px solid var(--line);
    white-space:nowrap; }}
  th {{ position:sticky; top:52px; background:var(--panel); cursor:pointer;
    font-size:12px; color:var(--sub); z-index:1; }}
  th:hover {{ color:var(--accent); }}
  td.path {{ white-space:normal; word-break:break-all; min-width:320px;
    font-family:ui-monospace, SFMono-Regular, Menlo, monospace; font-size:12px; }}
  td.num {{ text-align:right; font-variant-numeric:tabular-nums; }}
  .tag {{ display:inline-block; padding:1px 8px; border-radius:999px;
    font-size:12px; font-weight:600; }}
  .tag.ok {{ background:var(--okbg); color:var(--ok); }}
  .tag.warn {{ background:var(--warnbg); color:var(--warn); }}
  tr:hover td {{ background:color-mix(in srgb, var(--accent) 7%, transparent); }}
</style>
<h1>動画コーデック調査</h1>
<div class="meta">{escape(str(root))} — 全 {len(results)} ファイル /
  {datetime.now().strftime('%Y-%m-%d %H:%M')} 時点</div>
<div class="cards">{''.join(cards)}</div>
<h2>{escape(label)} — {len(targets)} 件</h2>
<div class="bar">{''.join(chips)}
  <input id="q" type="search" placeholder="パスで絞り込み…">
  <span id="count"></span>
</div>
<div class="wrap"><table>
<thead><tr><th>パス</th><th>コーデック</th><th>コンテナ</th><th>サイズ</th>
<th>長さ</th><th>解像度</th></tr></thead>
<tbody>{''.join(rows)}</tbody>
</table></div>
<script>
const rows = [...document.querySelectorAll('tbody tr')];
const q = document.getElementById('q');
const countEl = document.getElementById('count');
let filter = 'all';
function apply() {{
  const t = q.value.trim().toLowerCase();
  let n = 0;
  for (const tr of rows) {{
    const okG = filter === 'all' || tr.dataset.g === filter;
    const okQ = !t || tr.cells[0].textContent.toLowerCase().includes(t);
    const show = okG && okQ;
    tr.hidden = !show;
    if (show) n++;
  }}
  countEl.textContent = n + ' 件表示';
}}
document.querySelectorAll('.chip').forEach(b => b.onclick = () => {{
  document.querySelectorAll('.chip').forEach(x => x.classList.remove('active'));
  b.classList.add('active');
  filter = b.dataset.f;
  apply();
}});
q.oninput = apply;
document.querySelectorAll('th').forEach((th, i) => {{
  let asc = true;
  th.onclick = () => {{
    const tbody = document.querySelector('tbody');
    const sorted = rows.slice().sort((a, b) => {{
      const av = a.cells[i].dataset.v, bv = b.cells[i].dataset.v;
      if (av !== undefined && bv !== undefined)
        return (asc ? 1 : -1) * (parseFloat(av) - parseFloat(bv));
      return (asc ? 1 : -1) *
        a.cells[i].textContent.localeCompare(b.cells[i].textContent, 'ja');
    }});
    asc = !asc;
    tbody.append(...sorted);
  }};
}});
apply();
</script>
'''
    out_path.write_text(html, encoding='utf-8')


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
    parser.add_argument('--html',
                        help='一覧を HTML(検索・絞り込み・ソート付き)に書き出す。'
                             '表は --list の対象のみ、集計は全ファイル分')
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
    label = {
        'not-h265-mp4': '「h265 かつ mp4」になっていないファイル',
        'h265-not-mp4': 'h265 だが mp4 でないファイル',
        'not-h265': 'h265 でないファイル',
        'all': '全ファイル',
    }[args.which]

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
            w.writerow(['path', 'codec', 'codec_raw', 'container', 'format_name',
                        'size_bytes', 'duration_sec', 'width', 'height'])
            for r in results:
                w.writerow([str(r['path']), r['codec'], r['codec_raw'],
                            r['path'].suffix.lower().lstrip('.'), r['format_name'],
                            r['size'], f'{r["duration"]:.3f}',
                            r['width'], r['height']])
        print(f'CSV を書き出しました: {args.csv}', file=sys.stderr)

    if args.html:
        html_path = Path(args.html).expanduser()
        write_html(html_path, root, results, targets, label)
        print(f'HTML を書き出しました: {html_path}', file=sys.stderr)

    return 0


if __name__ == '__main__':
    sys.exit(main())
