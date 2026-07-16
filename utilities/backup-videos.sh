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
  --encode           整理後に H.265 エンコード＆mp4統一を実行
                     （H.265以外→再エンコード、H.265+mov→コンテナ変換）
  --encode-only      整理をスキップし、dest のエンコードのみ実行
  --remux-only       コンテナ変換のみ（再エンコードしない）
  --crf <N>          エンコード品質 (18=高品質〜28=標準、デフォルト: 20)
  --preset <PRESET>  エンコード速度 (デフォルト: slow)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  使用例
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # デフォルト設定で実行
  $(basename "$0") --run

  # ソースを指定して実行
  $(basename "$0") --src ~/Desktop/1 --run

  # 実際には移動せず確認だけ
  $(basename "$0") --src ~/Desktop/1 --dry-run

  # 整理 + H.265エンコード
  $(basename "$0") --run --encode

  # エンコードだけ実行（整理はスキップ）
  $(basename "$0") --encode-only

  # コンテナ変換のみ（再エンコードしない）
  $(basename "$0") --run --encode --remux-only

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
DO_ENCODE=false
ENCODE_ONLY=false
REMUX_ONLY=false
CRF=20
PRESET="slow"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)      usage; exit 0 ;;
    -r|--run)       shift ;;
    -s|--src)       SRC="$2"; shift 2 ;;
    -d|--dest)      DEST="$2"; shift 2 ;;
    --dry-run)      DRY_RUN=true; shift ;;
    --encode)       DO_ENCODE=true; shift ;;
    --encode-only)  ENCODE_ONLY=true; DO_ENCODE=true; shift ;;
    --remux-only)   REMUX_ONLY=true; shift ;;
    --crf)          CRF="$2"; shift 2 ;;
    --preset)       PRESET="$2"; shift 2 ;;
    *) echo "不明なオプション: $1"; echo ""; usage; exit 1 ;;
  esac
done

# --- 依存チェック ---
if ! command -v ffprobe &>/dev/null; then
  echo "エラー: ffprobe が見つかりません。brew install ffmpeg でインストールしてください"
  exit 1
fi
if ! $ENCODE_ONLY; then
  if [ ! -d "$SRC" ]; then
    echo "エラー: ソースフォルダが見つかりません: $SRC"
    exit 1
  fi
fi
if [ ! -d "$DEST" ]; then
  echo "エラー: 整理先が見つかりません: $DEST"
  exit 1
fi
if $DO_ENCODE && ! command -v ffmpeg &>/dev/null; then
  echo "エラー: ffmpeg が見つかりません。brew install ffmpeg でインストールしてください"
  exit 1
fi

$DRY_RUN && echo "  ※ DRY RUN モード（実際には移動しません）"

# === ステップ1: ファイル整理 ===
if $ENCODE_ONLY; then
  echo "整理をスキップし、エンコードのみ実行します"
  echo ""
else

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

fi  # ENCODE_ONLY

# === ステップ2: H.265 エンコード ===
if $DO_ENCODE; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  H.265 エンコード & mp4 統一"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  DEST="$DEST" DRY_RUN="$DRY_RUN" CRF="$CRF" PRESET="$PRESET" \
  REMUX_ONLY="$REMUX_ONLY" VIDEO_EXTS="$VIDEO_EXTS" python3 <<'ENCEOF'
import os, sys, json, subprocess
from pathlib import Path

DEST       = os.environ["DEST"]
DRY_RUN    = os.environ["DRY_RUN"] == "true"
CRF        = int(os.environ["CRF"])
PRESET     = os.environ["PRESET"]
REMUX_ONLY = os.environ["REMUX_ONLY"] == "true"
EXTS       = {"." + e for e in os.environ["VIDEO_EXTS"].split("|")}

def get_video_codec(filepath):
    result = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json",
         "-show_streams", "-select_streams", "v:0", str(filepath)],
        capture_output=True, text=True, timeout=60
    )
    try:
        data = json.loads(result.stdout)
        streams = data.get("streams", [])
        if streams:
            return streams[0].get("codec_name", "").lower()
    except Exception:
        pass
    return None

def is_h265(codec):
    return codec in ("hevc", "h265")

def get_duration_sec(filepath):
    result = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json",
         "-show_format", str(filepath)],
        capture_output=True, text=True, timeout=60
    )
    try:
        data = json.loads(result.stdout)
        return float(data["format"]["duration"])
    except Exception:
        return None

def run_ffmpeg_with_progress(cmd, label, total_sec):
    progress_cmd = cmd[:-1] + ["-progress", "pipe:1", "-nostats", cmd[-1]]
    proc = subprocess.Popen(progress_cmd, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True)
    last_pct = -1
    for line in proc.stdout:
        line = line.strip()
        if line.startswith("out_time_ms="):
            try:
                out_ms = int(line.split("=")[1])
                if total_sec and total_sec > 0:
                    pct = min(int(out_ms / (total_sec * 1_000_000) * 100), 99)
                    if pct != last_pct:
                        print(f"\r  {label}: {pct:3d}%", end="", flush=True)
                        last_pct = pct
            except ValueError:
                pass
        elif line.startswith("progress=end"):
            print(f"\r  {label}: 100%", flush=True)
    _, stderr_output = proc.communicate()
    if proc.returncode != 0:
        return False, stderr_output
    return True, ""

def remux_to_mp4(src, dst):
    cmd = [
        "ffmpeg", "-i", str(src),
        "-c", "copy",
        "-tag:v", "hvc1",
        "-map_metadata", "0",
        "-movflags", "+faststart",
        "-y",
        str(dst)
    ]
    if DRY_RUN:
        print(f"  [DRY-RUN] remux → {dst.name}")
        return True
    total_sec = get_duration_sec(src)
    success, err = run_ffmpeg_with_progress(cmd, "コンテナ変換中", total_sec)
    if not success:
        print(f"  [ERROR] ffmpeg 失敗:\n{err[-500:]}")
        if dst.exists():
            dst.unlink()
        return False
    return True

def encode_to_h265(src, dst):
    if DRY_RUN:
        print(f"  [DRY-RUN] encode H.265 → {dst.name}")
        return True
    cmd = [
        "ffmpeg", "-i", str(src),
        "-c:v", "libx265",
        "-crf", str(CRF),
        "-preset", PRESET,
        "-c:a", "aac",
        "-b:a", "128k",
        "-tag:v", "hvc1",
        "-map_metadata", "0",
        "-movflags", "+faststart",
        "-y",
        str(dst)
    ]
    print(f"  H.265エンコード開始 (libx265, CRF={CRF})")
    total_sec = get_duration_sec(src)
    success, err = run_ffmpeg_with_progress(cmd, "エンコード中", total_sec)
    if not success:
        print(f"  [ERROR] ffmpeg 失敗:\n{err[-500:]}")
        if dst.exists():
            dst.unlink()
        return False
    return True

def finalize(src, tmp_dst):
    if DRY_RUN:
        return True
    final = src.with_suffix(".mp4")
    src.unlink()
    if tmp_dst != final:
        if final.exists():
            size_mb = tmp_dst.stat().st_size / 1024 / 1024
            print(f"  完了 (名前衝突のため {tmp_dst.name} として保存, {size_mb:.1f} MB)")
            return True
        tmp_dst.rename(final)
    size_mb = final.stat().st_size / 1024 / 1024
    print(f"  完了 ({size_mb:.1f} MB)")
    return True

# --- 対象ファイル収集 ---
files = sorted(
    p for p in Path(DEST).rglob("*")
    if p.is_file() and p.suffix.lower() in EXTS
    and not p.name.startswith(".")
    and "_h265" not in p.stem
)

total = len(files)
skipped_h265 = 0
remuxed = 0
encoded = 0
failed = 0
skipped_err = 0

mode = "DRY-RUN" if DRY_RUN else "実行"
print(f"対象フォルダ: {DEST}")
print(f"モード: {mode}")
if REMUX_ONLY:
    print("コンテナ変換のみ（エンコードなし）")
else:
    print(f"品質(CRF): {CRF}, 速度: {PRESET}")
print(f"動画ファイル: {total}件\n")

for i, src in enumerate(files, 1):
    print(f"[{i}/{total}] {src.relative_to(DEST)}")

    try:
        codec = get_video_codec(src)
    except subprocess.TimeoutExpired:
        print("  [SKIP] ffprobe タイムアウト")
        skipped_err += 1
        continue

    if codec is None:
        print("  [SKIP] コーデック取得失敗")
        skipped_err += 1
        continue

    already_mp4 = src.suffix.lower() == ".mp4"
    already_h265_flag = is_h265(codec)

    print(f"  コーデック: {codec}, 拡張子: {src.suffix.lower()}", end="")

    if already_h265_flag and already_mp4:
        print(" → スキップ（H.265かつ.mp4）")
        skipped_h265 += 1
        continue

    tmp_dst = src.with_name(src.stem + "_h265.mp4")

    if already_h265_flag and not already_mp4:
        print(" → .mp4にコンテナ変換（再エンコードなし）")
        if remux_to_mp4(src, tmp_dst):
            finalize(src, tmp_dst)
            remuxed += 1
        else:
            failed += 1
    elif REMUX_ONLY:
        print(" → スキップ（H.265でないためエンコードが必要、--remux-only 指定）")
        skipped_h265 += 1
    else:
        print(f" → H.265に再エンコード")
        if encode_to_h265(src, tmp_dst):
            finalize(src, tmp_dst)
            encoded += 1
        else:
            failed += 1

print(f"\n=== エンコード結果 ===")
print(f"  スキップ (H.265+mp4済み): {skipped_h265}件")
print(f"  コンテナ変換のみ (.mov→.mp4): {remuxed}件")
print(f"  H.265エンコード:          {encoded}件")
print(f"  失敗:                     {failed}件")
print(f"  エラースキップ:           {skipped_err}件")
ENCEOF

fi  # DO_ENCODE
