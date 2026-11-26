#!/usr/bin/env python3
"""
お絵描き紹介動画専用スキャン（OCR + 画像マッチング）

使い方:
    python scan_oekaki.py

動作:
    1. 未処理のお絵描き紹介動画だけ対象
    2. 全体DL（1080p）
    3. 1秒間隔フレーム抽出
    4. OCR（manga-ocr「りお」検索）+ 画像マッチング（テンプレートマッチング）
    5. どちらかでヒットしたら保存
    6. バッチ完了後ギャラリー更新 + 動画削除

出力:
    oekaki_results/hit_frames/
    oekaki_results/results.json
    oekaki_results/gallery.html
"""

import json
import os
import ssl
import subprocess
import sys
import shutil
import tempfile
import time
from pathlib import Path

ssl._create_default_https_context = ssl._create_unverified_context
os.environ.setdefault("PYTHONHTTPSVERIFY", "0")

try:
    from PIL import Image
    import cv2
    import numpy as np
except ImportError:
    print("ERROR: pip install pillow opencv-python numpy")
    sys.exit(1)

try:
    from manga_ocr import MangaOcr
except ImportError:
    print("ERROR: pip install manga-ocr")
    sys.exit(1)

# ============================================================
# 設定
# ============================================================
KEYWORD = "りお"
FRAME_INTERVAL = 1
CROP_TOP_RATIO = 0.70
REFERENCE_IMAGE = Path("2025_0214_000000_12.jpeg")
MATCH_THRESHOLD = 0.55
SCALES = [0.2, 0.3, 0.4, 0.5, 0.6]
OEKAKI_TITLE_KEYWORDS = ["お絵描き", "お絵かき", "紹介"]
CHANNEL_LIST = Path("channel_video_list.json")
DATE_FROM = "20250301"
OUTPUT_DIR = Path("oekaki_results")
DL_DIR = Path("downloads_tmp")
YT_DLP_EXTRA = ["--no-check-certificates", "--cookies-from-browser", "chrome", "--remote-components", "ejs:github"]


def run_cmd(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


# ============================================================
# 画像マッチング
# ============================================================
def prepare_templates(ref_path, scales):
    ref_img = cv2.imread(str(ref_path))
    if ref_img is None:
        print(f"  ⚠️  参照画像読み込み失敗: {ref_path}")
        return []
    ref_gray = cv2.cvtColor(ref_img, cv2.COLOR_BGR2GRAY)
    h, w = ref_gray.shape
    templates = []
    for scale in scales:
        nw, nh = int(w * scale), int(h * scale)
        if nw < 20 or nh < 20:
            continue
        templates.append((scale, cv2.resize(ref_gray, (nw, nh))))
    return templates


def match_frame(frame_path, templates):
    frame = cv2.imread(str(frame_path), cv2.IMREAD_GRAYSCALE)
    if frame is None:
        return 0, 0
    best_score, best_scale = 0, 0
    for scale, tmpl in templates:
        th, tw = tmpl.shape
        if frame.shape[0] < th or frame.shape[1] < tw:
            continue
        result = cv2.matchTemplate(frame, tmpl, cv2.TM_CCOEFF_NORMED)
        _, max_val, _, _ = cv2.minMaxLoc(result)
        if max_val > best_score:
            best_score, best_scale = max_val, scale
    return best_score, best_scale


# ============================================================
# DL & スキャン
# ============================================================
def download_video(video, dl_dir):
    output_path = dl_dir / f"{video['id']}.mp4"
    if output_path.exists() and output_path.stat().st_size > 1000:
        return output_path
    cmd = ["yt-dlp", *YT_DLP_EXTRA,
           "-f", "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080]",
           "--merge-output-format", "mp4",
           "--no-warnings", "--quiet",
           "-o", str(output_path), video["url"]]
    run_cmd(cmd)
    if not output_path.exists():
        cmd2 = ["yt-dlp", *YT_DLP_EXTRA, "-f", "best[height<=1080]",
                "--no-warnings", "--quiet", "-o", str(output_path), video["url"]]
        run_cmd(cmd2)
    return output_path if output_path.exists() else None


def scan_video(video_path, video_meta, hit_dir, mocr, templates):
    """OCR + 画像マッチング"""
    vid_id = video_path.stem
    title = video_meta.get("title", vid_id)
    url = video_meta.get("url", f"https://www.youtube.com/watch?v={vid_id}")

    # フレーム抽出
    frames_dir = tempfile.mkdtemp(prefix=f"f_{vid_id}_")
    cmd = ["ffmpeg", "-y", "-i", str(video_path),
           "-vf", f"fps=1/{FRAME_INTERVAL}", "-q:v", "2",
           os.path.join(frames_dir, "frame_%04d.jpg")]
    run_cmd(cmd)
    frames = sorted(Path(frames_dir).glob("frame_*.jpg"))
    print(f"  {len(frames)}フレーム → ", end="", flush=True)

    hits = []
    for i, fp in enumerate(frames):
        if i % 60 == 0 and i > 0:
            print(f"{i}..", end="", flush=True)

        ocr_hit = False
        img_hit = False
        ocr_text = ""
        img_score = 0

        # OCR（下部クロップ）
        try:
            img = Image.open(fp)
            w, h = img.size
            cropped = img.crop((0, int(h * CROP_TOP_RATIO), w, h))
            ocr_text = mocr(cropped)
            if KEYWORD in ocr_text:
                ocr_hit = True
        except:
            pass

        # 画像マッチング
        if templates:
            score, scale = match_frame(fp, templates)
            if score >= MATCH_THRESHOLD:
                img_hit = True
                img_score = score

        if ocr_hit or img_hit:
            frame_sec = i * FRAME_INTERVAL
            time_str = f"{frame_sec // 60}:{frame_sec % 60:02d}"

            hit_type = "OCR+IMG" if (ocr_hit and img_hit) else ("OCR" if ocr_hit else "IMG")
            hit_filename = f"{vid_id}_{time_str.replace(':', 'm')}s.jpg"
            shutil.copy2(fp, os.path.join(hit_dir, hit_filename))

            hits.append({
                "video_id": vid_id,
                "title": title,
                "upload_date": video_meta.get("upload_date", "unknown"),
                "url": url,
                "timestamp": time_str,
                "timestamp_url": f"{url}&t={frame_sec}",
                "hit_type": hit_type,
                "keyword": KEYWORD if ocr_hit else "画像マッチ",
                "ocr_text": ocr_text,
                "img_score": round(img_score, 3),
                "frame_file": hit_filename
            })

    shutil.rmtree(frames_dir, ignore_errors=True)
    return hits


# ============================================================
# ギャラリー
# ============================================================
def generate_gallery(all_hits, output_dir):
    # 重複除外
    deduped = [all_hits[0]] if all_hits else []
    for h in all_hits[1:]:
        prev = deduped[-1]
        if h["video_id"] == prev["video_id"]:
            try:
                def to_sec(ts):
                    p = ts.split(":")
                    return int(p[0]) * 60 + int(p[1])
                if abs(to_sec(h["timestamp"]) - to_sec(prev["timestamp"])) <= 3:
                    continue
            except:
                pass
        deduped.append(h)

    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>お絵描き紹介 検索結果</title>
<style>
body{{font-family:-apple-system,sans-serif;background:#0f0f1a;color:#eee;padding:24px}}
h1{{color:#ffd700}}.summary{{color:#aaa;margin-bottom:20px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(450px,1fr));gap:20px}}
.card{{background:#1a1a2e;border-radius:12px;overflow:hidden;border:2px solid #2a2a4a}}
.card:hover{{border-color:#ffd700}}.card img{{width:100%;cursor:pointer;display:block}}
.info{{padding:12px}}.ocr{{color:#ffd700;font-size:15px;font-weight:bold}}
.type{{display:inline-block;padding:2px 6px;border-radius:4px;font-size:11px;margin-right:4px}}
.type.ocr-tag{{background:#2a4a2a;color:#8f8}}.type.img-tag{{background:#4a2a4a;color:#f8f}}
.type.both-tag{{background:#4a4a2a;color:#ff8}}
.title{{color:#ccc;font-size:13px;margin-top:4px}}
.meta{{color:#888;font-size:12px;margin-top:4px}}a{{color:#4fc3f7;text-decoration:none}}
</style></head><body>
<h1>🔍 お絵描き紹介 OCR+画像マッチング結果 ({len(deduped)}件)</h1>
<div class="summary">重複除外済み。画像クリック→YouTube。</div>
<div class="grid">"""
    for h in deduped:
        ht = h.get("hit_type", "OCR")
        tag_class = "both-tag" if "+" in ht else ("img-tag" if ht == "IMG" else "ocr-tag")
        html += f"""<div class="card"><a href="{h['timestamp_url']}" target="_blank"><img src="hit_frames/{h['frame_file']}" loading="lazy"></a><div class="info"><span class="type {tag_class}">{ht}</span><span class="ocr">{h.get('ocr_text','')[:25]}</span>{f" score={h['img_score']}" if h.get('img_score') else ""}<div class="title">{h.get('title','')[:50]}</div><div class="meta">[{h.get('upload_date','')}] ⏱️{h['timestamp']} | <a href="{h['timestamp_url']}" target="_blank">▶️YouTube</a></div></div></div>"""
    html += "</div></body></html>"
    with open(output_dir / "gallery.html", "w", encoding="utf-8") as f:
        f.write(html)
    return len(deduped)


# ============================================================
# メイン
# ============================================================
def main():
    OUTPUT_DIR.mkdir(exist_ok=True)
    DL_DIR.mkdir(exist_ok=True)
    hit_dir = str(OUTPUT_DIR / "hit_frames")
    os.makedirs(hit_dir, exist_ok=True)

    print("=" * 60)
    print("🔎 お絵描き紹介動画スキャン（OCR + 画像マッチング）")
    print("=" * 60)
    print(f"  OCRキーワード: {KEYWORD}")
    print(f"  画像マッチしきい値: {MATCH_THRESHOLD}")
    print(f"  フレーム間隔: {FRAME_INTERVAL}秒")
    print()

    # 動画リスト
    if not CHANNEL_LIST.exists():
        print(f"❌ {CHANNEL_LIST} がありません")
        sys.exit(1)
    with open(CHANNEL_LIST) as f:
        all_videos = json.load(f)

    # お絵描き紹介動画だけフィルタ
    oekaki = [v for v in all_videos if v.get("upload_date", "unknown") != "unknown"
              and v["upload_date"] >= DATE_FROM
              and any(kw in v.get("title", "") for kw in OEKAKI_TITLE_KEYWORDS)]

    # 処理済みスキップ
    done_file = OUTPUT_DIR / "processed_ids.txt"
    processed_ids = set()
    if done_file.exists():
        processed_ids = set(done_file.read_text().strip().split("\n"))
    remaining = [v for v in oekaki if v["id"] not in processed_ids]

    print(f"  お絵描き紹介動画: {len(oekaki)}本 → 未処理: {len(remaining)}本")

    if not remaining:
        print("\n✅ 全て処理済み！")
        sys.exit(0)

    # 既存結果
    results_file = OUTPUT_DIR / "results.json"
    all_hits = []
    if results_file.exists():
        with open(results_file) as f:
            all_hits = json.load(f)

    # モデルロード
    print("\n🧠 manga-ocr 読み込み中...")
    mocr = MangaOcr()
    print("  → OCR準備完了")

    # 画像テンプレート
    templates = []
    if REFERENCE_IMAGE.exists():
        templates = prepare_templates(REFERENCE_IMAGE, SCALES)
        print(f"  → 画像テンプレート: {len(templates)}スケール\n")
    else:
        print(f"  ⚠️  参照画像なし、OCRのみで実行\n")

    # 処理
    for idx, video in enumerate(remaining):
        print(f"\n[{idx+1}/{len(remaining)}] 🎬 [{video['upload_date']}] {video['title'][:45]}")
        t0 = time.time()

        # DL
        print(f"  ⬇️  DL中... ", end="", flush=True)
        dl_path = download_video(video, DL_DIR)
        if not dl_path or not dl_path.exists():
            print("❌ DL失敗")
            with open(done_file, "a") as f:
                f.write(video["id"] + "\n")
            continue
        size_mb = dl_path.stat().st_size / (1024 * 1024)
        print(f"{size_mb:.0f}MB")

        # スキャン
        print(f"  🔍 スキャン中... ", end="", flush=True)
        try:
            hits = scan_video(dl_path, video, hit_dir, mocr, templates)
            all_hits.extend(hits)
            elapsed = time.time() - t0
            if hits:
                print(f"\n  ✅ {len(hits)}件ヒット! ({elapsed:.0f}s)")
            else:
                print(f"なし ({elapsed:.0f}s)")
        except KeyboardInterrupt:
            raise
        except Exception as e:
            print(f"❌ {e}")

        # 処理済み記録 + 動画削除
        with open(done_file, "a") as f:
            f.write(video["id"] + "\n")
        dl_path.unlink(missing_ok=True)

        # 中間保存
        with open(results_file, "w", encoding="utf-8") as f:
            json.dump(all_hits, f, ensure_ascii=False, indent=2)

    # ギャラリー
    if all_hits:
        count = generate_gallery(all_hits, OUTPUT_DIR)
        print(f"\n🖼️  ギャラリー: {OUTPUT_DIR}/gallery.html ({count}件)")
    
    print(f"\n✅ 完了! ヒット合計: {len(all_hits)}件")
    print(f"   open {OUTPUT_DIR}/gallery.html")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n⚠️  中断。再実行で続きから。")
        for f in DL_DIR.glob("*.mp4"):
            f.unlink()
