#!/bin/bash
# verify-photos.sh
# 写真フォルダの構造・ファイル名を確認＆修正する
#
# 想定する構造:
#   <root>/<YYYY>/<MM>/<MMDD>/YYYY_MMDD_HHMMSS.<ext>

set -euo pipefail

ROOT_DEFAULT="/Users/yohei/Library/CloudStorage/OneDrive-Personal/s-leo/0_Photo/2026"
PHOTO_EXTS="heic|jpg|jpeg|png|tif|tiff|dng|raw|cr2|nef|arw|gif"

# 数字以外で始まるフォルダはスキップ（璃央のカメラ、ピカケスクール写真* 等）
SKIP_PATTERN="^[^0-9]"

usage() {
  cat <<EOF
使い方: $(basename "$0") [オプション]

写真フォルダの構造・ファイル名を確認し、想定外のものを修正します。

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  想定する構造
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  <root>/<YYYY>/<MM>/<MMDD>/YYYY_MMDD_HHMMSS.<ext>

  スキップ対象フォルダ（数字以外で始まるもの）:
    璃央のカメラ / ピカケスクール写真* / 2023a 等

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  確認・修正内容
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  1. ファイル名が YYYY_MMDD_HHMMSS 形式でない
       → 日付を取得してリネーム
  2. ファイルが正しいフォルダにない
       → EXIF の撮影日時と現在フォルダが一致しない場合に正しい場所へ移動
  3. 正しい MMDD フォルダの下にない（YYYY/MM 直下など）
       → 正しい MMDD フォルダに移動
  4. 空フォルダ
       → 削除

  日付判断の優先順（backup-photos.sh と同じ）:
    1. EXIF メタデータ（sips）
    2. コンテンツ作成日（mdls）
    3. フォルダ名パターン（0514 / May 14, 2025 等）
    4. ファイル名パターン（IMG_20250514_ 等）
    5. ファイル更新日時（mtime）

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  オプション
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  -h, --help         このヘルプを表示して終了
  --root <dir>       対象ルートフォルダ
                     （デフォルト: s-leo/0_Photo）
  --report           問題のあるファイルを一覧表示のみ（デフォルト）
  --fix              実際に修正を実行
  --dry-run          修正内容を表示するが実行しない

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  使用例
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  # まず問題を確認
  $(basename "$0") --report

  # 修正内容をプレビュー
  $(basename "$0") --dry-run

  # 実際に修正
  $(basename "$0") --fix

EOF
}

# --- 引数パース ---
if [[ $# -eq 0 ]]; then usage; exit 0; fi

ROOT="$ROOT_DEFAULT"
MODE="report"  # report / dry-run / fix

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)   usage; exit 0 ;;
    --root)      ROOT="$2"; shift 2 ;;
    --report)    MODE="report"; shift ;;
    --dry-run)   MODE="dry-run"; shift ;;
    --fix)       MODE="fix"; shift ;;
    *) echo "不明なオプション: $1"; echo ""; usage; exit 1 ;;
  esac
done

if [ ! -d "$ROOT" ]; then
  echo "エラー: フォルダが見つかりません: $ROOT"
  exit 1
fi

ROOT="$ROOT" MODE="$MODE" PHOTO_EXTS="$PHOTO_EXTS" python3 <<'PYEOF'
import os, re, hashlib, shutil, subprocess
from datetime import datetime, timezone, timedelta
from pathlib import Path

ROOT     = os.environ["ROOT"]
MODE     = os.environ["MODE"]   # report / dry-run / fix
EXTS     = {e for e in os.environ["PHOTO_EXTS"].split("|")}
LOCAL_TZ = datetime.now().astimezone().utcoffset() or timedelta(hours=-7)

MONTH_MAP = {
    "january":1,"february":2,"march":3,"april":4,"may":5,"june":6,
    "july":7,"august":8,"september":9,"october":10,"november":11,"december":12,
    "jan":1,"feb":2,"mar":3,"apr":4,"jun":6,"jul":7,"aug":8,
    "sep":9,"oct":10,"nov":11,"dec":12
}

EXPECTED_NAME = re.compile(r"^\d{4}_\d{4}_\d{6}(_\d+)?\.")  # YYYY_MMDD_HHMMSS. または YYYY_MMDD_HHMMSS_1.

def md5(path):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def date_from_sips(path):
    try:
        out = subprocess.check_output(["sips", "-g", "creation", str(path)], stderr=subprocess.DEVNULL).decode()
        m = re.search(r"creation:\s*(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})", out)
        if m: return datetime(*map(int, m.groups())), "sips"
    except: pass
    return None, None

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

def date_from_folder(path):
    parts = Path(path).parts
    for part in reversed(parts):
        m = re.fullmatch(r"(\d{2})(\d{2})", part)
        if m:
            mm, dd = int(m.group(1)), int(m.group(2))
            if 1<=mm<=12 and 1<=dd<=31:
                for p in reversed(parts):
                    if re.fullmatch(r"20\d{2}", p):
                        return datetime(int(p), mm, dd), "フォルダ名(MMDD)"
        m = re.search(r"(\w+)\s+(\d{1,2}),?\s+(20\d{2})", part)
        if m:
            mon = MONTH_MAP.get(m.group(1).lower())
            if mon:
                return datetime(int(m.group(3)), mon, int(m.group(2))), "フォルダ名(英語)"
    return None, None

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

def date_from_mtime(path):
    return datetime.fromtimestamp(os.stat(path).st_mtime), "mtime"

def get_date(path):
    for fn in [date_from_sips, date_from_mdls,
               lambda p: date_from_folder(p),
               lambda p: date_from_filename(p.name)]:
        dt, src = fn(path)
        if dt: return dt, src
    return date_from_mtime(path)

def is_skip_dir(name):
    """数字以外で始まるフォルダはスキップ"""
    return not name[0].isdigit()

def safe_move(src, dst, dry):
    """重複を考慮して移動"""
    dst = Path(dst)
    if dst.exists():
        if md5(src) == md5(dst):
            if not dry: os.remove(src)
            return str(dst), "SKIP(同一)"
        else:
            stem = dst.stem
            ext  = dst.suffix
            n = 1
            while (dst.parent / f"{stem}_{n}{ext}").exists():
                n += 1
            dst = dst.parent / f"{stem}_{n}{ext}"
    if not dry:
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dst))
    return str(dst), "OK"

# --- スキャン ---
root = Path(ROOT)
issues = []   # (kind, path, expected_path, date_src)
ok_count = 0

print(f"スキャン中: {ROOT}")
print(f"モード: {MODE}\n")

# root は必ず年フォルダ（例: .../0_Photo/2026）
base = root.parent  # 移動先パスの基点（0_Photo 直下）

for month_dir in sorted(root.iterdir()):
    if not month_dir.is_dir() or month_dir.name.startswith("."): continue
    if not re.fullmatch(r"\d{2}", month_dir.name): continue

    for item in sorted(month_dir.iterdir()):
        if item.name.startswith("."): continue

        # MM/MMDD 配下でなく MM 直下にあるファイル
        if item.is_file() and item.suffix.lstrip(".").lower() in EXTS:
            dt, src = get_date(item)
            expected_dir = base / dt.strftime("%Y") / dt.strftime("%m") / dt.strftime("%m%d")
            newname = f"{dt.strftime('%Y_%m%d_%H%M%S')}{item.suffix.lower()}"
            expected = expected_dir / newname
            issues.append(("MM直下ファイル", item, expected, src))
            continue

        if not item.is_dir(): continue
        if is_skip_dir(item.name): continue

        mmdd_dir = item
        for f in sorted(mmdd_dir.rglob("*")):
            if not f.is_file() or f.name.startswith("."): continue
            if f.suffix.lstrip(".").lower() not in EXTS: continue

            dt, date_src = get_date(f)
            year  = dt.strftime("%Y")
            month = dt.strftime("%m")
            mmdd  = dt.strftime("%m%d")
            ts    = dt.strftime("%Y_%m%d_%H%M%S")
            ext   = f.suffix.lower()
            newname  = f"{ts}{ext}"
            expected_dir = base / year / month / mmdd

            name_ok   = EXPECTED_NAME.match(f.name)
            folder_ok = (f.parent == expected_dir)

            # suffix (_1, _2 ...) が付いているが base 名が存在しない → suffix を除去
            SUFFIXED = re.compile(r"^(\d{4}_\d{4}_\d{6})_\d+(\..+)$")
            m = SUFFIXED.match(f.name)
            if m and folder_ok:
                base_name = m.group(1) + m.group(2).lower()
                if not (f.parent / base_name).exists():
                    issues.append(("suffix除去", f, f.parent / base_name, date_src))
                    continue
                else:
                    # base 名が存在するので suffix は必要 → 正常扱い
                    ok_count += 1
                    continue

            if name_ok and folder_ok:
                ok_count += 1
                continue

            expected = expected_dir / newname
            kind = []
            if not name_ok:   kind.append("名前")
            if not folder_ok: kind.append("フォルダ")
            issues.append(("+".join(kind), f, expected, date_src))

# --- レポート ---
print(f"{'='*50}")
print(f"  問題あり: {len(issues)} 件 / 正常: {ok_count} 件")
print(f"{'='*50}\n")

if MODE == "report":
    for kind, f, expected, src in issues[:50]:
        rel = f.relative_to(base)
        exp_rel = expected.relative_to(base)
        print(f"  [{kind:12s}] {rel}")
        print(f"    → {exp_rel}  ({src})")
    if len(issues) > 50:
        print(f"\n  ...他 {len(issues)-50} 件（--fix または --dry-run で全件確認）")

elif MODE in ("dry-run", "fix"):
    fixed = skipped = 0
    for kind, f, expected, src in issues:
        rel = f.relative_to(base)
        if MODE == "dry-run":
            exp_rel = expected.relative_to(base)
            print(f"  [{kind:12s}] {rel}")
            print(f"    → {exp_rel}  ({src})")
            fixed += 1
        else:
            dst, result = safe_move(f, expected, dry=False)
            dst_rel = Path(dst).relative_to(base)
            if result == "SKIP(同一)":
                print(f"  SKIP(同一): {rel.name}")
                skipped += 1
            else:
                print(f"  FIX [{kind}]: {rel.name} -> {dst_rel}  ({src})")
                fixed += 1

    # 空フォルダ削除
    if MODE == "fix":
        for d in sorted(root.rglob("*"), reverse=True):
            if d.is_dir() and not any(d.iterdir()):
                try: d.rmdir()
                except: pass

    label = "処理予定" if MODE == "dry-run" else "修正"
    print(f"\n{'='*50}")
    print(f"  {label}: {fixed} 件  スキップ: {skipped} 件")
    print(f"{'='*50}")
PYEOF
