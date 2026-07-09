#!/usr/bin/env python3
"""
create_memory_video.py

月フォルダ内の動画を自動でまとめて、1本のサマリー動画を作る。
各動画から「いちばん動きのある部分」を抜き出し、BGM を重ねて出力する。

使い方:
  python3 create_memory_video.py <月フォルダ> <出力ファイル.mp4> [オプション]

例:
  python3 create_memory_video.py /Volumes/backup1/leo_video/2024/01 ~/Desktop/2024_01_summary.mp4
  python3 create_memory_video.py /Volumes/backup1/leo_video/2024/01 ~/Desktop/2024_01_summary.mp4 --bgm ~/Music/song.mp3
  python3 create_memory_video.py /Volumes/backup1/leo_video/2024/01 ~/Desktop/2024_01_summary.mp4 --duration 7

オプション:
  --duration  TARGET  目標の長さ（分）。デフォルト: 7
  --bgm       FILE    BGM ファイル（mp3, m4a, aac など）
  --bgm-vol   0-1     BGM の音量（デフォルト: 0.3）
  --orig-vol  0-1     元音声の音量（デフォルト: 0.8）
"""

import argparse
import json
import math
import os
import subprocess
import sys
import tempfile
from pathlib import Path

VIDEO_EXTS = {".mov", ".mp4", ".m4v", ".avi", ".mkv", ".mts", ".m2ts"}


# ---------------------------------------------------------------------------
# ffprobe / ffmpeg helpers
# ---------------------------------------------------------------------------

def get_duration(path: Path) -> float:
    """動画の長さを秒で返す。取得できなければ 0。"""
    result = subprocess.run(
        ["ffprobe", "-v", "quiet",
         "-show_entries", "format=duration",
         "-of", "json", str(path)],
        capture_output=True, text=True
    )
    try:
        return float(json.loads(result.stdout)["format"]["duration"])
    except Exception:
        return 0.0


def get_video_info(path: Path) -> dict:
    """幅・高さ・fps を返す。"""
    result = subprocess.run(
        ["ffprobe", "-v", "quiet",
         "-select_streams", "v:0",
         "-show_entries", "stream=width,height,r_frame_rate",
         "-of", "json", str(path)],
        capture_output=True, text=True
    )
    try:
        s = json.loads(result.stdout)["streams"][0]
        num, den = map(int, s["r_frame_rate"].split("/"))
        fps = num / den if den else 30
        return {"width": s["width"], "height": s["height"], "fps": fps}
    except Exception:
        return {"width": 1920, "height": 1080, "fps": 30}


def find_best_clip_start(path: Path, duration: float, clip_len: float) -> float:
    """
    動きのスコアを使って、いちばん「賑やか」な開始位置を見つける。
    動画を 5 分割してそれぞれのモーション量を計測し、最大のセグメントを返す。
    """
    if duration <= clip_len:
        return 0.0

    # 最初と最後の 5% はカメラ操作が多いのでスキップ
    margin = duration * 0.05
    search_range = duration - 2 * margin - clip_len
    if search_range <= 0:
        return margin

    n_samples = min(5, max(2, int(search_range / clip_len)))
    best_score = -1.0
    best_start = margin

    for i in range(n_samples):
        start = margin + (search_range / max(n_samples - 1, 1)) * i
        # 3 秒分のフレームでモーション量（PSNR の逆数的な値）を計測
        probe_dur = min(3.0, clip_len)
        result = subprocess.run(
            ["ffmpeg", "-ss", str(start), "-t", str(probe_dur),
             "-i", str(path),
             "-vf", "select='eq(pict_type,I)',mestimate,metadata=print:file=-",
             "-an", "-f", "null", "-"],
            capture_output=True, text=True
        )
        # motion_est の平均を疑似スコアとして使う（出力行数 = 動き検出数）
        score = result.stderr.count("frame=")
        if score > best_score:
            best_score = score
            best_start = start

    return best_start


def extract_clip(src: Path, start: float, duration: float, dst: Path,
                 target_w: int, target_h: int) -> bool:
    """指定区間を切り出し、解像度を統一して dst に保存。"""
    cmd = [
        "ffmpeg", "-y",
        "-ss", str(start),
        "-t", str(duration),
        "-i", str(src),
        "-vf", f"scale={target_w}:{target_h}:force_original_aspect_ratio=decrease,"
               f"pad={target_w}:{target_h}:(ow-iw)/2:(oh-ih)/2",
        "-c:v", "libx264", "-preset", "fast", "-crf", "23",
        "-c:a", "aac", "-b:a", "128k",
        "-movflags", "+faststart",
        str(dst)
    ]
    result = subprocess.run(cmd, capture_output=True)
    return result.returncode == 0


def concat_clips(clip_files: list[Path], output: Path) -> bool:
    """クリップリストを結合する。"""
    with tempfile.NamedTemporaryFile("w", suffix=".txt", delete=False) as f:
        for p in clip_files:
            f.write(f"file '{p}'\n")
        list_file = f.name

    cmd = [
        "ffmpeg", "-y",
        "-f", "concat", "-safe", "0", "-i", list_file,
        "-c", "copy",
        str(output)
    ]
    result = subprocess.run(cmd, capture_output=True)
    os.unlink(list_file)
    return result.returncode == 0


def add_bgm(video: Path, bgm: Path, output: Path,
            bgm_vol: float, orig_vol: float) -> bool:
    """BGM を重ねる。元音声は orig_vol、BGM は bgm_vol。BGM はループ再生。"""
    total_dur = get_duration(video)
    cmd = [
        "ffmpeg", "-y",
        "-i", str(video),
        "-stream_loop", "-1", "-i", str(bgm),
        "-filter_complex",
        f"[0:a]volume={orig_vol}[a_orig];"
        f"[1:a]volume={bgm_vol},afade=t=out:st={total_dur - 3}:d=3[a_bgm];"
        f"[a_orig][a_bgm]amix=inputs=2:duration=first[a_out]",
        "-map", "0:v", "-map", "[a_out]",
        "-c:v", "copy", "-c:a", "aac", "-b:a", "192k",
        "-t", str(total_dur),
        str(output)
    ]
    result = subprocess.run(cmd, capture_output=True)
    return result.returncode == 0


# ---------------------------------------------------------------------------
# メイン
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="月ごとの子供動画サマリーを作成")
    parser.add_argument("folder", help="月フォルダのパス")
    parser.add_argument("output", help="出力ファイルのパス（.mp4）")
    parser.add_argument("--duration", type=float, default=7.0,
                        help="目標の長さ（分）。デフォルト: 7")
    parser.add_argument("--bgm", help="BGM ファイルのパス")
    parser.add_argument("--bgm-vol", type=float, default=0.3,
                        help="BGM の音量 0〜1。デフォルト: 0.3")
    parser.add_argument("--orig-vol", type=float, default=0.8,
                        help="元音声の音量 0〜1。デフォルト: 0.8")
    args = parser.parse_args()

    folder = Path(args.folder)
    output = Path(args.output).expanduser()
    target_sec = args.duration * 60

    # 動画ファイルを日付順に収集
    videos = sorted(
        [p for p in folder.rglob("*") if p.suffix.lower() in VIDEO_EXTS],
        key=lambda p: p.name
    )
    if not videos:
        print(f"動画が見つかりませんでした: {folder}")
        sys.exit(1)

    print(f"\n📂 {len(videos)} 本の動画が見つかりました")

    # 各動画の長さを取得
    durations = []
    for v in videos:
        d = get_duration(v)
        durations.append(d)
        print(f"  {v.name}: {d:.1f}秒")

    total_sec = sum(durations)
    print(f"\n⏱  合計: {total_sec:.0f}秒 ({total_sec/60:.1f}分)")
    print(f"🎯 目標: {target_sec:.0f}秒 ({args.duration}分)")

    # 各動画から切り出す長さを計算（比率で配分）
    ratio = min(1.0, target_sec / total_sec)
    clip_lengths = [max(3.0, d * ratio) for d in durations]
    actual_total = sum(clip_lengths)
    print(f"✂️  各動画から平均 {actual_total/len(videos):.1f}秒を抽出します")

    # 出力解像度（最も多い解像度に統一）
    print("\n🔍 動画情報を解析中...")
    infos = [get_video_info(v) for v in videos]
    target_w = max(set(i["width"] for i in infos), key=lambda w: [i["width"] for i in infos].count(w))
    target_h = max(set(i["height"] for i in infos), key=lambda h: [i["height"] for i in infos].count(h))
    print(f"📐 出力解像度: {target_w}x{target_h}")

    # クリップを抽出
    with tempfile.TemporaryDirectory() as tmpdir:
        tmp = Path(tmpdir)
        clip_paths = []

        print("\n🎬 クリップを抽出中...")
        for i, (v, dur, clip_len) in enumerate(zip(videos, durations, clip_lengths), 1):
            print(f"  [{i}/{len(videos)}] {v.name} → {clip_len:.1f}秒")
            start = find_best_clip_start(v, dur, clip_len)
            clip_out = tmp / f"clip_{i:03d}.mp4"
            ok = extract_clip(v, start, clip_len, clip_out, target_w, target_h)
            if ok and clip_out.exists():
                clip_paths.append(clip_out)
            else:
                print(f"    ⚠️ スキップ（変換失敗）")

        if not clip_paths:
            print("クリップの抽出に失敗しました。")
            sys.exit(1)

        # クリップを結合
        print(f"\n🔗 {len(clip_paths)} クリップを結合中...")
        if args.bgm:
            concat_out = tmp / "concat.mp4"
        else:
            concat_out = output
        output.parent.mkdir(parents=True, exist_ok=True)
        ok = concat_clips(clip_paths, concat_out)
        if not ok:
            print("結合に失敗しました。")
            sys.exit(1)

        # BGM を追加
        if args.bgm:
            bgm = Path(args.bgm).expanduser()
            if not bgm.exists():
                print(f"BGM ファイルが見つかりません: {bgm}")
                sys.exit(1)
            print(f"🎵 BGM を追加中: {bgm.name}")
            ok = add_bgm(concat_out, bgm, output, args.bgm_vol, args.orig_vol)
            if not ok:
                print("BGM の追加に失敗しました。")
                sys.exit(1)

    final_dur = get_duration(output)
    print(f"\n✅ 完成: {output}")
    print(f"   長さ: {final_dur:.0f}秒 ({final_dur/60:.1f}分)")


if __name__ == "__main__":
    main()
