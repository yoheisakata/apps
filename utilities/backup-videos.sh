#!/bin/bash
# backup-videos.sh
# Photos から手動エクスポートした動画を日付フォルダに整理する
#
# 事前準備:
#   Photos で動画を選択 → ファイル > 未編集のオリジナルを書き出す → <src> に保存

set -euo pipefail

SRC_DEFAULT="$HOME/Desktop/photos_video_export"
DEST_DEFAULT="/Volumes/backup1/leo_video"

VIDEO_EXTS="mov|mp4|m4v|mkv|avi|mts|m2ts"

usage() {
  cat <<EOF
使い方: $(basename "$0") [オプション]

Photos から手動エクスポートした動画を日付フォルダに整理します。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  事前準備
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Photos で動画を選択し、以下の手順でエクスポートしてください:
    メニュー: ファイル > 未編集のオリジナルを書き出す
    保存先:   ~/Desktop/photos_video_export（または --src で指定）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  仕組み
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  各ファイルの撮影日時を以下の優先順で判断します:
    1. QuickTime メタデータ（ffprobe）  ← 最優先・最も正確
    2. ファイルのコンテンツ作成日（mdls）
    3. フォルダ名のパターンマッチ
         0517  /  Bellevue, May 31, 2026  など
    4. ファイル名のパターンマッチ
         IMG_20260517_...  /  2026_0517_...  など
    5. ファイルの更新日時（mtime）       ← 最終フォールバック

  撮影日時をもとにリネーム＆移動:
    <dest>/<YYYY>/<MM>/<MMDD>/YYYY_MMDD_HHMMSS.<ext>

  重複ファイルの扱い:
    - MD5 が一致（同じファイル）→ スキップ
    - MD5 が不一致（別内容）   → suffix をつけて移動
        例: 2026_0531_115137_1.mov

  何度実行しても安全:
    - 既に整理済みのファイルは MD5 チェックでスキップされます

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  オプション
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  -h, --help         このヘルプを表示して終了
  -r, --run          デフォルト設定で実行
  -s, --src <dir>    エクスポート済み動画のフォルダ
                     （デフォルト: ~/Desktop/photos_video_export）
  -d, --dest <dir>   整理先ルートディレクトリ
                     （デフォルト: /Volumes/backup1/leo_video）
  --dry-run          実際には移動せず、処理内容だけ表示

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  使用例
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # デフォルト設定で実行
  $(basename "$0") --run

  # ソースを指定して実行
  $(basename "$0") --src ~/Desktop/1 --run

  # 実際には移動せず確認だけ
  $(basename "$0") --src ~/Desktop/1 --dry-run

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  依存ツール
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  - ffprobe（ffmpeg に含まれる）: brew install ffmpeg
  - python3（macOS 標準）

EOF
}

# --- 引数パース ---
if [[ $# -eq 0 ]]; then usage; exit 0; fi

SRC="$SRC_DEFAULT"
DEST="$DEST_DEFAULT"
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)  usage; exit 0 ;;
    -r|--run)   shift ;;
    -s|--src)   SRC="$2"; shift 2 ;;
    -d|--dest)  DEST="$2"; shift 2 ;;
    --dry-run)  DRY_RUN=true; shift ;;
    *) echo "不明なオプション: $1"; echo ""; usage; exit 1 ;;
  esac
done

# --- 依存チェック ---
if ! command -v ffprobe &>/dev/null; then
  echo "エラー: ffprobe が見つかりません。brew install ffmpeg でインストールしてください"
  exit 1
fi
if [ ! -d "$SRC" ]; then
  echo "エラー: ソースフォルダが見つかりません: $SRC"
  exit 1
fi
if [ ! -d "$DEST" ]; then
  echo "エラー: 整理先が見つかりません: $DEST"
  exit 1
fi

$DRY_RUN && echo "  ※ DRY RUN モード（実際には移動しません）"

SRC="$SRC" DEST="$DEST" DRY_RUN="$DRY_RUN" VIDEO_EXTS="$VIDEO_EXTS" python3 <<'PYEOF'
import os, re, hashlib, shutil, subprocess, json
from datetime import datetime, timezone, timedelta
from pathlib import Path

SRC      = os.environ["SRC"]
DEST     = os.environ["DEST"]
DRY_RUN  = os.environ["DRY_RUN"] == "true"
EXTS     = {e for e in os.environ["VIDEO_EXTS"].split("|")}
LOCAL_TZ = datetime.now().astimezone().utcoffset() or timedelta(hours=-7)

MONTH_MAP = {
    "january":1,"february":2,"march":3,"april":4,"may":5,"june":6,
    "july":7,"august":8,"september":9,"october":10,"november":11,"december":12,
    "jan":1,"feb":2,"mar":3,"apr":4,"jun":6,"jul":7,"aug":8,
    "sep":9,"oct":10,"nov":11,"dec":12
}

def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

# 1. ffprobe で QuickTime 撮影日時を取得
def date_from_ffprobe(path):
    try:
        out = subprocess.check_output(
            ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", str(path)],
            stderr=subprocess.DEVNULL).decode()
        tags = json.loads(out).get("format", {}).get("tags", {})
        s = tags.get("com.apple.quicktime.creationdate", "")
        if s:
            dt = datetime.fromisoformat(s)
            return dt.replace(tzinfo=None) if dt.tzinfo else dt, "ffprobe(QT)"
        # creation_time (UTC) フォールバック
        s = tags.get("creation_time", "")
        if s:
            dt = datetime.fromisoformat(s.replace("Z", "+00:00")).replace(tzinfo=timezone.utc)
            return (dt + LOCAL_TZ).replace(tzinfo=None), "ffprobe(UTC)"
    except: pass
    return None, None

# 2. mdls でコンテンツ作成日を取得
def date_from_mdls(path):
    try:
        out = subprocess.check_output(
            ["mdls", "-name", "kMDItemContentCreationDate", "-raw", str(path)],
            stderr=subprocess.DEVNULL).decode().strip()
        if out and out != "(null)":
            dt = datetime.strptime(out, "%Y-%m-%d %H:%M:%S +0000").replace(tzinfo=timezone.utc)
            return (dt + LOCAL_TZ).replace(tzinfo=None), "mdls"
    except: pass
    return None, None

# 3. フォルダ名からパターンマッチ
def date_from_folder(path):
    parts = Path(path).parts
    for i, part in enumerate(reversed(parts)):
        # MMDD 形式: 0517
        m = re.fullmatch(r"(\d{2})(\d{2})", part)
        if m:
            mm, dd = int(m.group(1)), int(m.group(2))
            if 1<=mm<=12 and 1<=dd<=31:
                for p in reversed(parts):
                    if re.fullmatch(r"20\d{2}", p):
                        return datetime(int(p), mm, dd), "フォルダ名(MMDD)"
                return datetime(datetime.now().year, mm, dd), "フォルダ名(MMDD)"
        # "Bellevue, May 31, 2026" / "May 31, 2026" 形式
        m = re.search(r"(\w+)\s+(\d{1,2}),?\s+(20\d{2})", part)
        if m:
            mon = MONTH_MAP.get(m.group(1).lower())
            if mon:
                return datetime(int(m.group(3)), mon, int(m.group(2))), "フォルダ名(英語)"
    return None, None

# 4. ファイル名からパターンマッチ
def date_from_filename(name):
    stem = Path(name).stem
    for pat in [
        r"(20\d{2})_(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})",
        r"(20\d{2})(\d{2})(\d{2})_(\d{2})(\d{2})(\d{2})",
        r"(20\d{2})(\d{2})(\d{2})",
    ]:
        m = re.search(pat, stem)
        if m:
            g = m.groups()
            try:
                if len(g) == 6:
                    return datetime(int(g[0]),int(g[1]),int(g[2]),int(g[3]),int(g[4]),int(g[5])), "ファイル名"
                else:
                    return datetime(int(g[0]),int(g[1]),int(g[2])), "ファイル名"
            except: pass
    return None, None

# 5. mtime フォールバック
def date_from_mtime(path):
    return datetime.fromtimestamp(os.stat(path).st_mtime), "mtime"

def get_date(path):
    for fn in [
        lambda p: date_from_ffprobe(p),
        lambda p: date_from_mdls(p),
        lambda p: date_from_folder(p),
        lambda p: date_from_filename(p.name),
    ]:
        dt, src = fn(path)
        if dt:
            return dt, src
    return date_from_mtime(path)

# --- ファイル収集 ---
files = sorted(
    p for p in Path(SRC).rglob("*")
    if p.is_file()
    and p.suffix.lstrip(".").lower() in EXTS
    and not p.name.startswith(".")
)

print(f"対象フォルダ: {SRC}")
print(f"動画ファイル数: {len(files)}\n")

ok = skipped = renamed = 0

for f in files:
    dt, src = get_date(f)
    year  = dt.strftime("%Y")
    month = dt.strftime("%m")
    mmdd  = dt.strftime("%m%d")
    ts    = dt.strftime("%Y_%m%d_%H%M%S")
    ext   = f.suffix.lower()
    newname  = f"{ts}{ext}"
    destdir  = Path(DEST) / year / month / mmdd
    destfile = destdir / newname

    if DRY_RUN:
        print(f"  [{src:15s}] {f.name} -> {year}/{month}/{mmdd}/{newname}")
        ok += 1
        continue

    destdir.mkdir(parents=True, exist_ok=True)

    if destfile.exists():
        if md5(f) == md5(destfile):
            os.remove(f)
            skipped += 1
            print(f"  SKIP (同一): {f.name}")
        else:
            n = 1
            while (destdir / f"{ts}_{n}{ext}").exists():
                n += 1
            shutil.move(str(f), str(destdir / f"{ts}_{n}{ext}"), copy_function=shutil.copy)
            renamed += 1
            print(f"  RENAMED: {f.name} -> {ts}_{n}{ext}  [{src}]")
    else:
        shutil.move(str(f), str(destfile), copy_function=shutil.copy)
        ok += 1
        print(f"  OK: {f.name} -> {year}/{month}/{mmdd}/{newname}  [{src}]")

# src 配下の空サブフォルダを削除（ルートフォルダ自体は残す）
for d in sorted(Path(SRC).rglob("*"), reverse=True):
    if d.is_dir() and d != Path(SRC):
        try: d.rmdir()
        except OSError: pass

if DRY_RUN:
    print(f"\n=============================== DRY RUN")
    print(f"  処理予定: {ok} 件")
else:
    print(f"\n===============================")
    print(f"  移動: {ok}件  スキップ: {skipped}件  リネーム: {renamed}件")
    print(f"  整理先: {DEST}")
    print(f"===============================")
PYEOF
