#!/usr/bin/env python3
"""
Leo（りお）検索 — DL→OCR→ギャラリー→削除 を20本バッチで繰り返す

使い方:
    python find_leo_full.py
    python find_leo_full.py --reset   # 処理済みデータをリセット

動作:
    0. 動画リストを増分更新（新着のみ・channel_list.py）
    1. 対象期間（2026年9月1日〜実行日まで。実行のたびに自動で伸びる）の未処理動画を抽出
    2. 20本ずつバッチ処理:
       a. お絵描き紹介動画 → 全体DL / その他 → 最後10分だけDL（1080p）
       b. 1秒間隔フレーム抽出 → manga-ocr で「りお」検索
       c. ヒットフレームを保存 + ギャラリー更新
       d. DL済み動画を削除（ストレージ節約）
    3. 全バッチ完了まで繰り返す

前提:
    brew install yt-dlp ffmpeg deno
    pip install manga-ocr pillow
    channel_video_list.json が存在すること

出力:
    leo_results/hit_frames/   — ヒットフレームJPG
    leo_results/results.json  — ヒット一覧
    leo_results/gallery.html  — ギャラリー（バッチごとに更新）
"""

import argparse
import json
import os
import ssl
import subprocess
import sys
import shutil
import tempfile
import time
from pathlib import Path

# SSL回避
ssl._create_default_https_context = ssl._create_unverified_context
os.environ.setdefault("PYTHONHTTPSVERIFY", "0")

try:
    from PIL import Image
except ImportError:
    print("ERROR: pip install pillow")
    sys.exit(1)

try:
    from manga_ocr import MangaOcr
except ImportError:
    print("ERROR: pip install manga-ocr")
    sys.exit(1)

# channel_list.py: 動画リストの増分更新・検索期間（2026年9月〜実行日まで）・対象の選定
from channel_list import (YT_DLP_EXTRA, read_processed_ids, search_window,
                          select_targets, update_channel_list)

# ============================================================
# 設定
# ============================================================
KEYWORD = "りお"
FRAME_INTERVAL = 1
CROP_TOP_RATIO = 0.70
TAIL_MINUTES = 10
OEKAKI_TITLE_KEYWORDS = ["お絵描き", "お絵かき", "紹介"]
BATCH_SIZE = 20
OUTPUT_DIR = Path("leo_results")
DL_DIR = Path("downloads_tmp")


def run_cmd(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def is_oekaki_video(video):
    """お絵描き紹介動画かどうか"""
    title = video.get("title", "")
    return any(kw in title for kw in OEKAKI_TITLE_KEYWORDS)


# ============================================================
# DL
# ============================================================
def download_video(video, dl_dir):
    """DL: お絵描き紹介動画は全体、それ以外は最後10分"""
    output_path = dl_dir / f"{video['id']}.mp4"
    if output_path.exists() and output_path.stat().st_size > 1000:
        return output_path

    if is_oekaki_video(video):
        cmd = ["yt-dlp", *YT_DLP_EXTRA,
               "-f", "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080]",
               "--merge-output-format", "mp4",
               "--no-warnings", "--quiet",
               "-o", str(output_path), video["url"]]
    else:
        duration = video.get("duration", 0)
        start_time = max(0, duration - TAIL_MINUTES * 60) if duration > 0 else 0
        cmd = ["yt-dlp", *YT_DLP_EXTRA,
               "-f", "bestvideo[height<=1080][ext=mp4]+bestaudio[ext=m4a]/best[height<=1080]",
               "--merge-output-format", "mp4",
               "--download-sections", f"*{start_time}-inf",
               "--no-warnings", "--quiet",
               "-o", str(output_path), video["url"]]

    result = run_cmd(cmd)

    if result.returncode != 0 or not output_path.exists():
        cmd2 = ["yt-dlp", *YT_DLP_EXTRA, "-f", "best[height<=1080]",
                "--no-warnings", "--quiet", "-o", str(output_path), video["url"]]
        run_cmd(cmd2)

    return output_path if output_path.exists() else None


# ============================================================
# OCRスキャン
# ============================================================
def scan_video(video_path, video_meta, hit_dir, mocr):
    """1本をフレーム抽出→OCRスキャン"""
    vid_id = video_path.stem
    title = video_meta.get("title", vid_id)
    url = video_meta.get("url", f"https://www.youtube.com/watch?v={vid_id}")

    # タイムスタンプのオフセット計算（最後10分DLの場合）
    duration = video_meta.get("duration", 0)
    time_offset = max(0, duration - TAIL_MINUTES * 60) if (not is_oekaki_video(video_meta) and duration > 0) else 0

    # フレーム抽出（テンポラリ）
    frames_dir = tempfile.mkdtemp(prefix=f"f_{vid_id}_")
    cmd = ["ffmpeg", "-y", "-i", str(video_path),
           "-vf", f"fps=1/{FRAME_INTERVAL}", "-q:v", "2",
           os.path.join(frames_dir, "frame_%04d.jpg")]
    run_cmd(cmd)
    frames = sorted(Path(frames_dir).glob("frame_*.jpg"))

    # OCR
    hits = []
    for i, fp in enumerate(frames):
        try:
            img = Image.open(fp)
            w, h = img.size
            cropped = img.crop((0, int(h * CROP_TOP_RATIO), w, h))
            text = mocr(cropped)
        except Exception:
            text = ""

        if KEYWORD in text:
            frame_sec = time_offset + i * FRAME_INTERVAL
            time_str = f"{frame_sec // 60}:{frame_sec % 60:02d}"

            hit_filename = f"{vid_id}_{time_str.replace(':', 'm')}s.jpg"
            shutil.copy2(fp, os.path.join(hit_dir, hit_filename))

            hits.append({
                "video_id": vid_id,
                "title": title,
                "upload_date": video_meta.get("upload_date", "unknown"),
                "url": url,
                "timestamp": time_str,
                "timestamp_url": f"{url}&t={frame_sec}",
                "keyword": KEYWORD,
                "frame_file": hit_filename,
                "ocr_text": text
            })

    shutil.rmtree(frames_dir, ignore_errors=True)
    return hits


# ============================================================
# ギャラリー
# ============================================================
def generate_gallery(all_hits, output_dir):
    deduped = [all_hits[0]] if all_hits else []
    for h in all_hits[1:]:
        prev = deduped[-1]
        if h["video_id"] == prev["video_id"]:
            try:
                def to_sec(ts):
                    p = ts.split(":")
                    return int(p[0]) * 60 + int(p[1])
                if abs(to_sec(h["timestamp"]) - to_sec(prev["timestamp"])) <= 4:
                    continue
            except:
                pass
        deduped.append(h)

    # 「り」+「お」が単語の切れ目をまたいで偶然並んだ誤検出を除外する
    false_pos = ["やっぱりおいしい", "シンガリオン", "によりお", "よりお", "やっぱりお"]
    filtered = [h for h in deduped if not any(fp in h.get("ocr_text", "") for fp in false_pos)]

    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>りお検索結果</title>
<style>
body{{font-family:-apple-system,sans-serif;background:#0f0f1a;color:#eee;padding:24px}}
h1{{color:#ffd700}}.summary{{color:#aaa;margin-bottom:20px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(450px,1fr));gap:20px}}
.card{{background:#1a1a2e;border-radius:12px;overflow:hidden;border:2px solid #2a2a4a}}
.card:hover{{border-color:#ffd700}}.card img{{width:100%;cursor:pointer;display:block}}
.info{{padding:12px}}.ocr{{color:#ffd700;font-size:16px;font-weight:bold}}
.title{{color:#ccc;font-size:13px;margin-top:4px}}
.meta{{color:#888;font-size:12px;margin-top:4px}}a{{color:#4fc3f7;text-decoration:none}}
</style></head><body>
<h1>🔍「りお」検索結果 ({len(filtered)}件)</h1>
<div class="summary">重複・偽陽性除外済み。画像クリック→YouTube。</div>
<div class="grid">"""
    for h in filtered:
        html += f"""<div class="card"><a href="{h['timestamp_url']}" target="_blank"><img src="hit_frames/{h['frame_file']}" loading="lazy"></a><div class="info"><div class="ocr">OCR: {h['ocr_text']}</div><div class="title">{h.get('title','')[:50]}</div><div class="meta">[{h.get('upload_date','')}] ⏱️{h['timestamp']} | <a href="{h['timestamp_url']}" target="_blank">▶️YouTube</a></div></div></div>"""
    html += "</div></body></html>"

    with open(output_dir / "gallery.html", "w", encoding="utf-8") as f:
        f.write(html)
    return len(filtered)


# ============================================================
# メイン
# ============================================================
def main():
    OUTPUT_DIR.mkdir(exist_ok=True)
    DL_DIR.mkdir(exist_ok=True)
    hit_dir = str(OUTPUT_DIR / "hit_frames")
    os.makedirs(hit_dir, exist_ok=True)

    # --reset オプション
    parser = argparse.ArgumentParser(description="Leo（りお）検索")
    parser.add_argument("--reset", action="store_true",
                        help="処理済みデータをリセットして最初からやり直す")
    args = parser.parse_args()

    if args.reset:
        done_file = OUTPUT_DIR / "processed_ids.txt"
        results_file = OUTPUT_DIR / "results.json"
        for f in [done_file, results_file]:
            if f.exists():
                f.unlink()
        hit_frames_dir = OUTPUT_DIR / "hit_frames"
        if hit_frames_dir.exists():
            shutil.rmtree(hit_frames_dir)
            hit_frames_dir.mkdir()
        print("🔄 リセット完了。最初から処理します。\n")

    print("=" * 60)
    print("🔎 Leo（りお）検索（バッチ処理: DL→OCR→ギャラリー→削除）")
    print("=" * 60)
    print(f"  キーワード: {KEYWORD}")
    print(f"  バッチサイズ: {BATCH_SIZE}本")
    print(f"  フレーム間隔: {FRAME_INTERVAL}秒")
    date_from, date_to = search_window()
    print(f"  対象期間: {date_from}〜{date_to}（実行日まで自動）")
    print()

    # 動画リスト更新（新着のみ）+ 対象の選定
    all_videos = update_channel_list()
    print()

    done_file = OUTPUT_DIR / "processed_ids.txt"
    processed_ids = read_processed_ids(done_file)
    videos = select_targets(all_videos, set(), date_from, date_to)
    remaining = select_targets(all_videos, processed_ids, date_from, date_to)

    print(f"  期間内: {len(videos)}本 → 処理済み: {len(videos) - len(remaining)} → 残り: {len(remaining)}本")

    if not remaining:
        print("\n✅ 全て処理済み！")
        sys.exit(0)

    # 既存結果読み込み
    results_file = OUTPUT_DIR / "results.json"
    all_hits = []
    if results_file.exists():
        with open(results_file) as f:
            all_hits = json.load(f)

    hits_before = len(all_hits)

    # manga-ocr ロード
    print("\n🧠 manga-ocr 読み込み中...")
    mocr = MangaOcr()
    print("  → 準備完了\n")

    # バッチ処理
    total_batches = (len(remaining) + BATCH_SIZE - 1) // BATCH_SIZE
    video_times = []

    for batch_idx in range(total_batches):
        batch_start = batch_idx * BATCH_SIZE
        batch = remaining[batch_start:batch_start + BATCH_SIZE]

        # ETA
        if video_times:
            avg = sum(video_times) / len(video_times)
            videos_left = len(remaining) - batch_start
            eta_min = int(avg * videos_left / 60)
            eta_str = f"{eta_min//60}h{eta_min%60:02d}m" if eta_min >= 60 else f"{eta_min}分"
            print(f"\n{'='*60}")
            print(f"📦 バッチ {batch_idx+1}/{total_batches} ({len(batch)}本) | ⏳残り{eta_str} | {len(all_hits)}件ヒット")
        else:
            print(f"\n{'='*60}")
            print(f"📦 バッチ {batch_idx+1}/{total_batches} ({len(batch)}本)")
        print(f"{'='*60}")

        # ---- Phase 1: DL ----
        print(f"\n  ⬇️  DLフェーズ ({len(batch)}本)")
        dl_results = []
        for i, video in enumerate(batch):
            t0 = time.time()
            print(f"    [{i+1}/{len(batch)}] DL中... ", end="", flush=True)

            dl_path = download_video(video, DL_DIR)
            if not dl_path or not dl_path.exists():
                print(f"❌ 失敗: {video['title'][:35]}")
                with open(done_file, "a") as f:
                    f.write(video["id"] + "\n")
                continue

            size_mb = dl_path.stat().st_size / (1024*1024)
            print(f"✅ {size_mb:.0f}MB ({time.time()-t0:.0f}s) {video['title'][:30]}")
            dl_results.append((video, dl_path))

        # ---- Phase 2: OCR ----
        print(f"\n  🔍 OCRフェーズ ({len(dl_results)}本)")
        for i, (video, dl_path) in enumerate(dl_results):
            t0 = time.time()
            print(f"    [{i+1}/{len(dl_results)}] OCR中... ", end="", flush=True)

            try:
                hits = scan_video(dl_path, video, hit_dir, mocr)
                all_hits.extend(hits)
                elapsed = time.time() - t0
                if hits:
                    print(f"✅ {len(hits)}件! ({elapsed:.0f}s) {video['title'][:30]}")
                else:
                    print(f"- ({elapsed:.0f}s) {video['title'][:30]}")
            except KeyboardInterrupt:
                raise
            except Exception as e:
                print(f"❌ {e}")

            # OCR まで完了した時点で処理済みにする（途中中断時は次回やり直す）
            with open(done_file, "a") as f:
                f.write(video["id"] + "\n")
            video_times.append(time.time() - t0)

        # ---- Phase 3: ギャラリー更新 + 動画削除 ----
        with open(results_file, "w", encoding="utf-8") as f:
            json.dump(all_hits, f, ensure_ascii=False, indent=2)

        if all_hits:
            gallery_count = generate_gallery(all_hits, OUTPUT_DIR)
            print(f"\n  💾 ギャラリー更新 ({gallery_count}件)")

        # 動画削除
        for _, dl_path in dl_results:
            dl_path.unlink(missing_ok=True)
        print(f"  🗑️  動画削除完了")

    # 最終サマリー
    print(f"\n\n{'='*60}")
    print(f"🏁 全バッチ完了！ 累計ヒット: {len(all_hits)}件 / 今回の新規: {len(all_hits) - hits_before}件")
    print(f"{'='*60}")
    new_hits = all_hits[hits_before:]
    for h in new_hits[:20]:
        print(f"  [{h['upload_date']}] {h['timestamp']} | {h['ocr_text'][:20]} | {h['title'][:30]}")
    if len(new_hits) > 20:
        print(f"  ... 他 {len(new_hits)-20}件")
    print(f"\n🖼️  open leo_results/gallery.html")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n⚠️  中断。再実行で続きから再開されます。")
        if DL_DIR.exists():
            for f in DL_DIR.glob("*.mp4"):
                f.unlink()
        sys.exit(0)
