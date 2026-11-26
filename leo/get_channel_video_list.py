#!/usr/bin/env python3
"""
チャンネル動画リストの増分更新（新着分だけ取得して自動停止）

仕組み:
  Phase 1: --flat-playlist で ID/タイトルだけ高速に新着順で取得
           → 既知IDに連続で当たったら即停止
  Phase 2: 新着IDだけ個別にアップロード日・長さを取得
  → 既存 channel_video_list.json の先頭にマージ

使い方:
    python get_channel_video_list.py --channel "https://www.youtube.com/@sunsunkidstv"
    python get_channel_video_list.py --channel "..." --full   # 全件取り直し（遅い）
"""

import argparse
import json
import subprocess
import sys
from pathlib import Path

YT_DLP_EXTRA = ["--no-check-certificates", "--cookies-from-browser", "chrome",
                "--remote-components", "ejs:github"]
STOP_AFTER_CONSECUTIVE_KNOWN = 5
MAX_SCAN = 300  # 安全装置: これ以上は走査しない（増分モード時）


def fetch_flat_ids(channel_url, known_ids, full):
    """Phase 1: ID/タイトルを高速取得。既知に連続で当たったら停止"""
    cmd = ["yt-dlp", *YT_DLP_EXTRA, "--flat-playlist",
           "--print", "%(id)s|%(title)s", "--no-warnings", channel_url]
    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    new_items, consecutive, scanned = [], 0, 0
    try:
        for line in iter(proc.stdout.readline, ""):
            line = line.strip()
            if "|" not in line:
                continue
            vid_id, title = line.split("|", 1)
            scanned += 1

            if not full and vid_id in known_ids:
                consecutive += 1
                if consecutive >= STOP_AFTER_CONSECUTIVE_KNOWN:
                    print(f"  ⏹  既知の動画に{consecutive}本連続で到達 → 停止（{scanned}本走査）")
                    break
                continue

            consecutive = 0
            new_items.append((vid_id, title))
            print(f"  + {title[:50]}")

            if not full and scanned >= MAX_SCAN:
                print(f"  ⚠️  {MAX_SCAN}本走査しても既知に到達せず停止（既存リストを確認してください）")
                break
    finally:
        proc.kill()
        proc.wait()
    return new_items


def fetch_meta(vid_id):
    """Phase 2: 1本分の upload_date / duration を取得"""
    url = f"https://www.youtube.com/watch?v={vid_id}"
    r = subprocess.run(["yt-dlp", *YT_DLP_EXTRA, "--skip-download",
                        "--print", "%(upload_date)s|%(duration)s", "--no-warnings", url],
                       capture_output=True, text=True)
    date, dur = "unknown", 0
    out = r.stdout.strip().splitlines()
    if out and "|" in out[-1]:
        d, du = out[-1].split("|", 1)
        if d.isdigit() and len(d) == 8:
            date = d
        try:
            dur = int(float(du))
        except (ValueError, TypeError):
            pass
    return date, dur


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--channel", "-c", required=True)
    p.add_argument("--output", "-o", default="channel_video_list")
    p.add_argument("--full", action="store_true")
    args = p.parse_args()

    channel_url = args.channel.rstrip("/")
    if not channel_url.endswith("/videos"):
        channel_url += "/videos"
    json_path = Path(f"{args.output}.json")

    existing = []
    if json_path.exists() and not args.full:
        try:
            existing = json.loads(json_path.read_text(encoding="utf-8"))
        except Exception as e:
            print(f"❌ 既存リストの読み込みに失敗: {e}")
            print("   全件取得したい場合は --full を付けて実行してください")
            sys.exit(1)
    known_ids = {v["id"] for v in existing if "id" in v}

    print("=" * 60)
    print(f"📋 動画リスト更新（{'全件' if args.full else '増分'}）")
    print(f"  既存: {len(known_ids)}本  ({json_path.resolve()})")
    print("=" * 60)

    print("\n[Phase 1] 新着IDを取得中...")
    new_items = fetch_flat_ids(channel_url, known_ids, args.full)

    if not new_items:
        print("\n✅ 新着なし。リストは最新です。")
        return

    print(f"\n[Phase 2] 新着 {len(new_items)}本の日付を取得中...")
    new_videos = []
    for i, (vid_id, title) in enumerate(new_items, 1):
        date, dur = fetch_meta(vid_id)
        print(f"  [{i}/{len(new_items)}] [{date}] {title[:45]}")
        new_videos.append({"id": vid_id, "title": title, "upload_date": date,
                           "duration": dur, "url": f"https://www.youtube.com/watch?v={vid_id}"})

    seen, merged = set(), []
    for v in new_videos + ([] if args.full else existing):
        if v["id"] not in seen:
            seen.add(v["id"])
            merged.append(v)

    json_path.write_text(json.dumps(merged, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"\n✅ 新着 {len(new_videos)}本を追加 → 合計 {len(merged)}本")
    print("   次: python find_leo_full.py")


if __name__ == "__main__":
    main()
