#!/usr/bin/env python3
"""
画像マッチング検索 — 息子の絵をテンプレートとして動画フレーム内で部分一致検索

使い方:
    python image_match.py

動作:
    0. 動画リストを増分更新（新着のみ・channel_list.py）
    1. 対象期間（2026年9月1日〜実行日まで。実行のたびに自動で伸びる）の未処理動画を取得
    2. 20本バッチで: DL → 2秒間隔フレーム抽出 → テンプレートマッチング → 動画削除
    3. マッチしたフレームを保存 + ギャラリー生成

テンプレートマッチング:
    - 参照画像を複数スケールで縮小
    - cv2.matchTemplate で各フレーム内をスキャン
    - しきい値以上の類似度の箇所があればヒット

前提:
    brew install yt-dlp ffmpeg deno
    pip install opencv-python pillow

出力:
    img_results/hit_frames/   — ヒットフレームJPG
    img_results/results.json  — ヒット一覧
    img_results/gallery.html  — ギャラリー
"""

import json
import os
import subprocess
import sys
import shutil
import tempfile
import time
from pathlib import Path

try:
    import cv2
    import numpy as np
except ImportError:
    print("ERROR: pip install opencv-python numpy")
    sys.exit(1)

# channel_list.py: 動画リストの増分更新・検索期間（2026年9月〜実行日まで）・対象の選定
from channel_list import (YT_DLP_EXTRA, read_processed_ids, search_window,
                          select_targets, update_channel_list)

# ============================================================
# 設定
# ============================================================
REFERENCE_IMAGE = Path("2025_0214_000000_12.jpeg")
FRAME_INTERVAL = 1         # 1秒間隔
MATCH_THRESHOLD = 0.55     # テンプレートマッチングのしきい値（0〜1, 高いほど厳しい）
SCALES = [0.3, 0.4, 0.5, 0.6, 0.8]  # 参照画像のスケール候補
BATCH_SIZE = 20
OUTPUT_DIR = Path("img_results")
DL_DIR = Path("downloads_tmp")


def run_cmd(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def prepare_templates(ref_path, scales):
    """参照画像を複数スケールに縮小してテンプレート群を作成"""
    ref_img = cv2.imread(str(ref_path))
    if ref_img is None:
        print(f"❌ 参照画像を読み込めません: {ref_path}")
        sys.exit(1)

    # グレースケール
    ref_gray = cv2.cvtColor(ref_img, cv2.COLOR_BGR2GRAY)
    h, w = ref_gray.shape

    templates = []
    for scale in scales:
        new_w = int(w * scale)
        new_h = int(h * scale)
        if new_w < 20 or new_h < 20:
            continue
        resized = cv2.resize(ref_gray, (new_w, new_h))
        templates.append((scale, resized))

    print(f"  テンプレート: {len(templates)} スケール ({scales})")
    return templates


def match_frame(frame_path, templates, threshold):
    """1フレームに対してテンプレートマッチング（複数スケール）"""
    frame = cv2.imread(str(frame_path), cv2.IMREAD_GRAYSCALE)
    if frame is None:
        return None

    best_score = 0
    best_scale = 0
    best_loc = (0, 0)

    for scale, template in templates:
        th, tw = template.shape
        # フレームがテンプレートより小さい場合スキップ
        if frame.shape[0] < th or frame.shape[1] < tw:
            continue

        result = cv2.matchTemplate(frame, template, cv2.TM_CCOEFF_NORMED)
        _, max_val, _, max_loc = cv2.minMaxLoc(result)

        if max_val > best_score:
            best_score = max_val
            best_scale = scale
            best_loc = max_loc

    if best_score >= threshold:
        return {"score": best_score, "scale": best_scale, "location": best_loc}
    return None


def download_video(video, dl_dir):
    """最高画質でDL"""
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


def extract_frames(video_path, frames_dir):
    """フレーム抽出"""
    os.makedirs(frames_dir, exist_ok=True)
    cmd = ["ffmpeg", "-y", "-i", str(video_path),
           "-vf", f"fps=1/{FRAME_INTERVAL}", "-q:v", "2",
           os.path.join(frames_dir, "frame_%04d.jpg")]
    run_cmd(cmd)
    return sorted(Path(frames_dir).glob("frame_*.jpg"))


def process_video(video, dl_dir, hit_dir, templates):
    """1本処理: DL → フレーム抽出 → マッチング"""
    vid_id = video["id"]
    title = video.get("title", vid_id)
    url = video.get("url", f"https://www.youtube.com/watch?v={vid_id}")

    # DL
    dl_path = download_video(video, dl_dir)
    if not dl_path or not dl_path.exists():
        return None, []

    size_mb = dl_path.stat().st_size / (1024 * 1024)
    print(f"DL {size_mb:.0f}MB → ", end="", flush=True)

    # フレーム抽出
    frames_dir = tempfile.mkdtemp(prefix=f"f_{vid_id}_")
    frames = extract_frames(dl_path, frames_dir)
    print(f"{len(frames)}f → ", end="", flush=True)

    # マッチング
    hits = []
    for i, fp in enumerate(frames):
        result = match_frame(fp, templates, MATCH_THRESHOLD)
        if result:
            frame_sec = i * FRAME_INTERVAL
            time_str = f"{frame_sec // 60}:{frame_sec % 60:02d}"

            hit_filename = f"{vid_id}_{time_str.replace(':', 'm')}s.jpg"
            shutil.copy2(fp, os.path.join(hit_dir, hit_filename))

            hits.append({
                "video_id": vid_id,
                "title": title,
                "upload_date": video.get("upload_date", "unknown"),
                "url": url,
                "timestamp": time_str,
                "timestamp_url": f"{url}&t={frame_sec}",
                "match_score": round(result["score"], 3),
                "match_scale": result["scale"],
                "frame_file": hit_filename
            })

    # フレーム削除
    shutil.rmtree(frames_dir, ignore_errors=True)

    return dl_path, hits


def generate_gallery(all_hits, output_dir):
    """ギャラリー生成"""
    # 重複除外（同動画4秒以内）
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

    # スコア順にソート
    deduped.sort(key=lambda x: x.get("match_score", 0), reverse=True)

    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>画像マッチング結果</title>
<style>
body{{font-family:-apple-system,sans-serif;background:#0f0f1a;color:#eee;padding:24px}}
h1{{color:#ffd700}}.summary{{color:#aaa;margin-bottom:20px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(450px,1fr));gap:20px}}
.card{{background:#1a1a2e;border-radius:12px;overflow:hidden;border:2px solid #2a2a4a}}
.card:hover{{border-color:#ffd700}}.card img{{width:100%;cursor:pointer;display:block}}
.info{{padding:12px}}.score{{color:#4caf50;font-size:16px;font-weight:bold}}
.title{{color:#ccc;font-size:13px;margin-top:4px}}
.meta{{color:#888;font-size:12px;margin-top:4px}}a{{color:#4fc3f7;text-decoration:none}}
</style></head><body>
<h1>🖼️ 画像マッチング結果 ({len(deduped)}件)</h1>
<div class="summary">スコア順。画像クリック→YouTube。</div>
<div class="grid">"""
    for h in deduped:
        html += f"""<div class="card"><a href="{h['timestamp_url']}" target="_blank"><img src="hit_frames/{h['frame_file']}" loading="lazy"></a><div class="info"><div class="score">スコア: {h['match_score']} (scale {h['match_scale']})</div><div class="title">{h.get('title','')[:50]}</div><div class="meta">[{h.get('upload_date','')}] ⏱️{h['timestamp']} | <a href="{h['timestamp_url']}" target="_blank">▶️YouTube</a></div></div></div>"""
    html += "</div></body></html>"

    with open(output_dir / "gallery.html", "w", encoding="utf-8") as f:
        f.write(html)
    return len(deduped)


def main():
    OUTPUT_DIR.mkdir(exist_ok=True)
    DL_DIR.mkdir(exist_ok=True)
    hit_dir = str(OUTPUT_DIR / "hit_frames")
    os.makedirs(hit_dir, exist_ok=True)

    print("=" * 60)
    print("🖼️  画像マッチング検索")
    print("=" * 60)
    print(f"  参照画像: {REFERENCE_IMAGE}")
    print(f"  しきい値: {MATCH_THRESHOLD}")
    print(f"  フレーム間隔: {FRAME_INTERVAL}秒")
    print(f"  バッチサイズ: {BATCH_SIZE}本")
    print()

    # 参照画像のテンプレート準備
    if not REFERENCE_IMAGE.exists():
        print(f"❌ 参照画像が見つかりません: {REFERENCE_IMAGE}")
        sys.exit(1)
    templates = prepare_templates(REFERENCE_IMAGE, SCALES)

    # 動画リスト（新着のみ増分更新）+ 対象期間の未処理動画
    date_from, date_to = search_window()
    print(f"  対象期間: {date_from}〜{date_to}（実行日まで自動）")
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

    # 既存結果
    results_file = OUTPUT_DIR / "results.json"
    all_hits = []
    if results_file.exists():
        with open(results_file) as f:
            all_hits = json.load(f)

    # バッチ処理
    total_batches = (len(remaining) + BATCH_SIZE - 1) // BATCH_SIZE
    video_times = []

    for batch_idx in range(total_batches):
        batch_start = batch_idx * BATCH_SIZE
        batch = remaining[batch_start:batch_start + BATCH_SIZE]

        if video_times:
            avg = sum(video_times) / len(video_times)
            eta_min = int(avg * (len(remaining) - batch_start) / 60)
            eta_str = f"{eta_min//60}h{eta_min%60:02d}m" if eta_min >= 60 else f"{eta_min}分"
            print(f"\n{'='*60}")
            print(f"📦 バッチ {batch_idx+1}/{total_batches} | ⏳{eta_str} | {len(all_hits)}件ヒット")
        else:
            print(f"\n{'='*60}")
            print(f"📦 バッチ {batch_idx+1}/{total_batches} ({len(batch)}本)")
        print(f"{'='*60}")

        # DL → マッチング
        dl_paths = []
        for i, video in enumerate(batch):
            t0 = time.time()
            print(f"  [{batch_start+i+1}/{len(remaining)}] ", end="", flush=True)

            try:
                dl_path, hits = process_video(video, DL_DIR, hit_dir, templates)
                all_hits.extend(hits)
                if hits:
                    print(f"✅ {len(hits)}件! {video['title'][:25]}")
                else:
                    print(f"- {video['title'][:30]}")
                if dl_path:
                    dl_paths.append(dl_path)
            except KeyboardInterrupt:
                raise
            except Exception as e:
                print(f"❌ {e}")

            with open(done_file, "a") as f:
                f.write(video["id"] + "\n")
            video_times.append(time.time() - t0)

        # バッチ完了: 保存 + ギャラリー + 動画削除
        with open(results_file, "w", encoding="utf-8") as f:
            json.dump(all_hits, f, ensure_ascii=False, indent=2)

        if all_hits:
            gallery_count = generate_gallery(all_hits, OUTPUT_DIR)
            print(f"\n  💾 ギャラリー更新 ({gallery_count}件)")

        for p in dl_paths:
            p.unlink(missing_ok=True)
        print(f"  🗑️  動画削除完了")

    # 最終
    print(f"\n\n{'='*60}")
    print(f"🏁 完了！ ヒット: {len(all_hits)}件")
    print(f"{'='*60}")
    if all_hits:
        for h in all_hits[:10]:
            print(f"  [{h['upload_date']}] {h['timestamp']} score={h['match_score']} | {h['title'][:30]}")
    print(f"\n🖼️  open img_results/gallery.html")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print(f"\n\n⚠️  中断。再実行で続きから再開されます。")
        for f in DL_DIR.glob("*.mp4"):
            f.unlink()
        sys.exit(0)
