#!/usr/bin/env python3
"""
動画リストの増分更新と検索対象の決定（find_leo_full.py / image_match.py 共通）

- 検索期間: SEARCH_FROM 〜 実行日（ローカル日付）まで。実行のたびに「今日まで」が自動で伸びる
- 増分: channel_video_list.json に無い新着だけ取得（先頭から既知IDに当たったら停止）
- 処理済み: 各スクリプトの processed_ids.txt にあるIDは再処理しない
- 日付不明（yt-dlp が upload_date を返せなかった動画）は次回以降の実行で日付を補完する
"""

import json
import os
import subprocess
from datetime import date
from pathlib import Path

CHANNEL_LIST = Path("channel_video_list.json")
CHANNEL_URL = "https://www.youtube.com/@sunsunkidstv/videos"
# yt-dlp の共通オプション。ブラウザの Cookie は既定では使わない
# （この Mac では Chrome のプロファイルを macOS の権限で読めず失敗するため）。
# 必要なときだけ環境変数 LEO_COOKIES_BROWSER=chrome（など）を指定する。
_COOKIES_BROWSER = os.environ.get("LEO_COOKIES_BROWSER", "").strip()
YT_DLP_EXTRA = ["--no-check-certificates", "--remote-components", "ejs:github"]
if _COOKIES_BROWSER:
    YT_DLP_EXTRA += ["--cookies-from-browser", _COOKIES_BROWSER]

# 検索の開始日（YYYYMMDD）。璃央の絵が入っていなかった 2026年9月 以降を見る
SEARCH_FROM = "20260901"
# 検索の終了日。None なら実行日（今日）まで
SEARCH_TO = None


def search_window():
    """(開始日, 終了日) を返す。終了日は実行時点の日付"""
    date_to = SEARCH_TO or date.today().strftime("%Y%m%d")
    return SEARCH_FROM, date_to


def read_processed_ids(path):
    if not path.exists():
        return set()
    return set(line.strip() for line in path.read_text().splitlines() if line.strip())


def fill_unknown_dates(videos):
    """upload_date が unknown の動画について、yt-dlp で日付と長さを取り直す。補完できた件数を返す"""
    unknown = [v for v in videos if v.get("upload_date", "unknown") in ("unknown", "", None)]
    if not unknown:
        return 0
    print(f"  日付不明 {len(unknown)}本の日付を取得中...")
    filled = 0
    for v in unknown:
        r = subprocess.run(
            ["yt-dlp", *YT_DLP_EXTRA, "--skip-download",
             "--print", "%(upload_date)s|%(duration)s", "--no-warnings", v["url"]],
            capture_output=True, text=True)
        out = r.stdout.strip().splitlines()
        if out and "|" in out[-1]:
            d, du = out[-1].split("|", 1)
            if d.isdigit() and len(d) == 8:
                v["upload_date"] = d
                filled += 1
            try:
                v["duration"] = int(float(du))
            except (ValueError, TypeError):
                pass
    return filled


def update_channel_list():
    """新着動画だけをリストの先頭に追記する。既存リストは書き換えない部分を保つ"""
    print("📋 動画リストを更新中...")

    existing_videos = []
    if CHANNEL_LIST.exists():
        with open(CHANNEL_LIST, encoding="utf-8") as f:
            existing_videos = json.load(f)
    existing_ids = set(v["id"] for v in existing_videos)
    print(f"  既存: {len(existing_videos)}本")

    cmd = [
        "yt-dlp", *YT_DLP_EXTRA,
        "--skip-download",
        "--print", "%(id)s|%(title)s|%(upload_date)s|%(duration)s",
        "--no-warnings",
        "--lazy-playlist",
        CHANNEL_URL,
    ]
    process = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

    new_videos = []
    for line in iter(process.stdout.readline, ""):
        line = line.strip()
        if not line or "|" not in line:
            continue
        parts = line.split("|")
        if len(parts) < 4:
            continue
        vid_id, title, upload_date, duration = parts[0], parts[1], parts[2], parts[3]

        # 既知IDに当たったら、それ以降は全て既知 → 停止
        if vid_id in existing_ids:
            process.kill()
            break

        try:
            dur = int(float(duration)) if duration and duration not in ("NA", "None") else 0
        except (ValueError, TypeError):
            dur = 0
        clean_date = upload_date.strip() if upload_date else "unknown"
        if clean_date in ("NA", "None", ""):
            clean_date = "unknown"

        new_videos.append({
            "id": vid_id,
            "title": title,
            "upload_date": clean_date,
            "duration": dur,
            "url": f"https://www.youtube.com/watch?v={vid_id}",
        })
    process.wait()

    updated = new_videos + existing_videos
    filled = fill_unknown_dates(updated)

    if new_videos or filled:
        with open(CHANNEL_LIST, "w", encoding="utf-8") as f:
            json.dump(updated, f, ensure_ascii=False, indent=2)
    if new_videos:
        print(f"  ✅ 新着 {len(new_videos)}本を追加 → 合計{len(updated)}本")
    else:
        print("  ✅ 新着なし（最新です）")
    return updated


def select_targets(videos, processed_ids, date_from, date_to):
    """対象期間内・日付既知・未処理の動画だけを返す（リストの新着順を維持）"""
    return [v for v in videos
            if v.get("upload_date", "unknown") not in ("unknown", "", None)
            and date_from <= v["upload_date"] <= date_to
            and v["id"] not in processed_ids]
