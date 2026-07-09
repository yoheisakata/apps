#!/usr/bin/env python3
"""
子どもビデオまとめメーカー
各動画から短いクリップを抜き出し、BGMと合わせてまとめ動画を生成します。
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import os
import subprocess
import threading
import json
import random

VIDEO_EXTS = {".mp4", ".mov", ".avi", ".m4v", ".mkv", ".mts", ".m2ts", ".3gp"}


def get_duration(path):
    result = subprocess.run(
        ["ffprobe", "-v", "quiet", "-print_format", "json", "-show_format", path],
        capture_output=True, text=True
    )
    try:
        return float(json.loads(result.stdout)["format"]["duration"])
    except Exception:
        return None


def find_videos(folder):
    files = []
    for root, _, filenames in os.walk(folder):
        for f in filenames:
            if os.path.splitext(f)[1].lower() in VIDEO_EXTS:
                files.append(os.path.join(root, f))
    files.sort()
    return files


class App(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("子どもビデオまとめメーカー")
        self.resizable(False, False)

        self.folder_var = tk.StringVar()
        self.music_var = tk.StringVar()
        self.mode_var = tk.StringVar(value="clip")   # "clip" or "total"
        self.clip_sec_var = tk.IntVar(value=8)
        self.total_sec_var = tk.IntVar(value=120)
        self.start_offset_var = tk.IntVar(value=3)
        self.bgm_vol_var = tk.DoubleVar(value=0.3)
        self.orig_vol_var = tk.DoubleVar(value=0.7)
        self.output_var = tk.StringVar()
        self.videos = []

        self._build_ui()
        self.clip_sec_var.trace_add("write", lambda *_: self._on_value_change())
        self.total_sec_var.trace_add("write", lambda *_: self._on_value_change())

    def _build_ui(self):
        pad = {"padx": 10, "pady": 5}
        f = ttk.Frame(self, padding=16)
        f.pack(fill="both", expand=True)

        # ── フォルダ選択 ──────────────────────────
        ttk.Label(f, text="動画フォルダ", font=("", 12, "bold")).grid(
            row=0, column=0, sticky="w", **pad)
        ttk.Entry(f, textvariable=self.folder_var, width=44).grid(
            row=0, column=1, sticky="ew", **pad)
        ttk.Button(f, text="選択…", command=self._pick_folder).grid(
            row=0, column=2, **pad)

        # 動画一覧
        list_frame = ttk.Frame(f)
        list_frame.grid(row=1, column=0, columnspan=3, padx=10, pady=4, sticky="ew")
        self.video_list = tk.Listbox(list_frame, height=8, width=62,
                                     selectmode="extended", activestyle="dotbox")
        sb = ttk.Scrollbar(list_frame, orient="vertical", command=self.video_list.yview)
        self.video_list.configure(yscrollcommand=sb.set)
        self.video_list.pack(side="left", fill="both", expand=True)
        sb.pack(side="right", fill="y")

        self.count_var = tk.StringVar(value="")
        count_row = ttk.Frame(f)
        count_row.grid(row=2, column=0, columnspan=3, padx=10, pady=(0, 2), sticky="ew")
        ttk.Label(count_row, textvariable=self.count_var, font=("", 11, "bold")).pack(side="left")
        ttk.Button(count_row, text="選択した動画を除外",
                   command=self._remove_selected).pack(side="right")
        ttk.Label(count_row, text="動画をクリックで選択して除外できます",
                  foreground="gray").pack(side="right", padx=8)

        # ── 音楽ファイル ──────────────────────────
        ttk.Label(f, text="BGM ファイル", font=("", 12, "bold")).grid(
            row=3, column=0, sticky="w", **pad)
        ttk.Entry(f, textvariable=self.music_var, width=44).grid(
            row=3, column=1, sticky="ew", **pad)
        ttk.Button(f, text="選択…", command=self._pick_music).grid(
            row=3, column=2, **pad)

        # ── 詳細設定 ──────────────────────────────
        detail = ttk.LabelFrame(f, text="詳細設定", padding=(10, 6))
        detail.grid(row=4, column=0, columnspan=3, sticky="ew", padx=10, pady=8)

        # row0: モード切替
        ttk.Radiobutton(detail, text="1動画の抜粋秒数を指定", variable=self.mode_var,
                        value="clip", command=self._on_mode_change).grid(
            row=0, column=0, sticky="w", pady=2)
        ttk.Radiobutton(detail, text="全体の尺を指定", variable=self.mode_var,
                        value="total", command=self._on_mode_change).grid(
            row=0, column=1, sticky="w", pady=2)

        # row1: 1動画あたり秒数
        ttk.Label(detail, text="1動画あたり").grid(row=1, column=0, sticky="w", pady=3)
        self.clip_spin = ttk.Spinbox(detail, from_=3, to=600, textvariable=self.clip_sec_var, width=6)
        self.clip_spin.grid(row=1, column=1, sticky="w", padx=6)
        ttk.Label(detail, text="秒").grid(row=1, column=2, sticky="w")

        # row2: 全体の尺
        ttk.Label(detail, text="全体の尺").grid(row=2, column=0, sticky="w", pady=3)
        self.total_spin = ttk.Spinbox(detail, from_=10, to=7200, textvariable=self.total_sec_var, width=6)
        self.total_spin.grid(row=2, column=1, sticky="w", padx=6)
        ttk.Label(detail, text="秒").grid(row=2, column=2, sticky="w")

        # row3: 計算結果
        self.calc_label_var = tk.StringVar(value="")
        ttk.Label(detail, textvariable=self.calc_label_var, foreground="gray").grid(
            row=3, column=0, columnspan=3, sticky="w", pady=2)

        # row4: 冒頭スキップ
        ttk.Label(detail, text="冒頭スキップ秒数").grid(row=4, column=0, sticky="w", pady=3)
        ttk.Spinbox(detail, from_=0, to=120, textvariable=self.start_offset_var,
                    width=6).grid(row=4, column=1, sticky="w", padx=6)
        ttk.Label(detail, text="秒").grid(row=4, column=2, sticky="w")

        # row5: BGM音量
        ttk.Label(detail, text="BGM 音量").grid(row=5, column=0, sticky="w", pady=3)
        ttk.Scale(detail, from_=0, to=1, variable=self.bgm_vol_var,
                  orient="horizontal", length=180).grid(row=5, column=1, columnspan=2, sticky="w")

        # row6: 元音声音量
        ttk.Label(detail, text="元音声 音量").grid(row=6, column=0, sticky="w", pady=3)
        ttk.Scale(detail, from_=0, to=1, variable=self.orig_vol_var,
                  orient="horizontal", length=180).grid(row=6, column=1, columnspan=2, sticky="w")

        # ── 出力先 ────────────────────────────────
        ttk.Label(f, text="出力ファイル", font=("", 12, "bold")).grid(
            row=5, column=0, sticky="w", **pad)
        ttk.Entry(f, textvariable=self.output_var, width=44).grid(
            row=5, column=1, sticky="ew", **pad)
        ttk.Button(f, text="選択…", command=self._pick_output).grid(
            row=5, column=2, **pad)

        # ── 進捗 & ステータス ─────────────────────
        self.progress = ttk.Progressbar(f, mode="indeterminate", length=440)
        self.progress.grid(row=6, column=0, columnspan=3, padx=10, pady=(10, 4))

        self.status_var = tk.StringVar(value="フォルダを選んでください")
        ttk.Label(f, textvariable=self.status_var, foreground="#555555").grid(
            row=7, column=0, columnspan=3, pady=2)

        # ── 実行ボタン ────────────────────────────
        self.run_btn = ttk.Button(
            f, text="▶  まとめ動画を作成", command=self._start_generate
        )
        self.run_btn.grid(row=8, column=0, columnspan=3, pady=(8, 4), ipadx=20, ipady=6)

        self._on_mode_change()  # 初期状態を適用

    # ── イベント ──────────────────────────────────

    def _pick_folder(self):
        d = filedialog.askdirectory(title="動画フォルダを選択")
        if not d:
            return
        self.folder_var.set(d)
        self.videos = find_videos(d)
        self.video_list.delete(0, "end")
        for v in self.videos:
            self.video_list.insert("end", os.path.relpath(v, d))
        self._update_count()
        if not self.output_var.get():
            self.output_var.set(os.path.join(d, "まとめ動画.mp4"))
        self._on_mode_change()

    def _pick_music(self):
        f = filedialog.askopenfilename(
            title="BGMファイルを選択",
            filetypes=[("音楽ファイル", "*.mp3 *.aac *.m4a *.wav *.flac"), ("すべて", "*")]
        )
        if f:
            self.music_var.set(f)

    def _pick_output(self):
        f = filedialog.asksaveasfilename(
            title="出力ファイルを保存",
            defaultextension=".mp4",
            filetypes=[("MP4", "*.mp4")]
        )
        if f:
            self.output_var.set(f)

    def _update_count(self):
        n = len(self.videos)
        self.count_var.set(f"{n} 本の動画が見つかりました" if n > 0 else "")
        self.status_var.set(f"{n} 本の動画が見つかりました" if n > 0 else "フォルダを選んでください")

    def _on_mode_change(self):
        if self.mode_var.get() == "clip":
            self.clip_spin.configure(state="normal")
            self.total_spin.configure(state="disabled")
        else:
            self.clip_spin.configure(state="disabled")
            self.total_spin.configure(state="normal")
        self._on_value_change()

    def _on_value_change(self):
        n = len(self.videos)
        if n == 0:
            self.calc_label_var.set("")
            return
        try:
            if self.mode_var.get() == "clip":
                total = self.clip_sec_var.get() * n
                m, s = divmod(total, 60)
                self.calc_label_var.set(f"→ 全体の尺：約 {m}分{s:02d}秒（{n}本）")
            else:
                clip = self.total_sec_var.get() / n
                self.calc_label_var.set(f"→ 1動画あたり：約 {clip:.1f}秒（{n}本）")
        except (tk.TclError, ZeroDivisionError):
            self.calc_label_var.set("")

    def _remove_selected(self):
        selected = list(self.video_list.curselection())
        for i in reversed(selected):
            self.video_list.delete(i)
            del self.videos[i]
        self._update_count()
        self._on_value_change()

    def _start_generate(self):
        if not self.videos:
            messagebox.showerror("エラー", "動画フォルダを選択してください")
            return
        if not self.output_var.get():
            messagebox.showerror("エラー", "出力ファイルを指定してください")
            return
        self.run_btn.configure(state="disabled")
        self.progress.start(10)
        threading.Thread(target=self._generate, daemon=True).start()

    def _generate(self):
        try:
            self._do_generate()
        except Exception as e:
            msg = str(e)
            self.after(0, lambda m=msg: messagebox.showerror("エラー", m))
        finally:
            self.after(0, self._done)

    def _do_generate(self):
        tmp_dir = os.path.join(os.path.dirname(self.output_var.get()), ".video_tmp")
        os.makedirs(tmp_dir, exist_ok=True)

        clip_files = []
        if self.mode_var.get() == "total":
            clip_sec = max(1, self.total_sec_var.get() // len(self.videos))
        else:
            clip_sec = self.clip_sec_var.get()
        offset = self.start_offset_var.get()
        orig_vol = self.orig_vol_var.get()
        total = len(self.videos)

        for idx, vpath in enumerate(self.videos):
            self.after(0, lambda i=idx: self.status_var.set(
                f"処理中… {i+1}/{total}: {os.path.basename(self.videos[i])}"))

            dur = get_duration(vpath)
            if dur is None or dur < offset + 1:
                start = 0
            else:
                latest = dur - clip_sec
                earliest = min(offset, latest)
                start = random.uniform(earliest, max(earliest, latest))

            out_clip = os.path.join(tmp_dir, f"clip_{idx:04d}.mp4")
            subprocess.run([
                "ffmpeg", "-y", "-ss", str(start), "-i", vpath,
                "-t", str(clip_sec), "-af", f"volume={orig_vol}",
                "-c:v", "libx264", "-preset", "fast", "-crf", "23",
                "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart",
                out_clip
            ], capture_output=True, check=True)
            clip_files.append(out_clip)

        list_file = os.path.join(tmp_dir, "clips.txt")
        with open(list_file, "w") as lf:
            for c in clip_files:
                lf.write(f"file '{c}'\n")

        concat_out = os.path.join(tmp_dir, "concat.mp4")
        self.after(0, lambda: self.status_var.set("クリップを結合中…"))
        subprocess.run([
            "ffmpeg", "-y", "-f", "concat", "-safe", "0",
            "-i", list_file, "-c", "copy", concat_out
        ], capture_output=True, check=True)

        output = self.output_var.get()
        music = self.music_var.get()
        bgm_vol = self.bgm_vol_var.get()

        if music and os.path.exists(music):
            self.after(0, lambda: self.status_var.set("BGMを合成中…"))
            # 動画の総尺を取得してフェード計算
            total_dur = get_duration(concat_out) or 0
            fade_dur = min(2.0, total_dur / 4)
            fade_out_start = max(0, total_dur - fade_dur)
            bgm_filter = (
                f"[1:a]volume={bgm_vol},"
                f"afade=t=in:st=0:d={fade_dur},"
                f"afade=t=out:st={fade_out_start:.3f}:d={fade_dur}[bgm];"
                f"[0:a]volume=1[va];"
                f"[va][bgm]amix=inputs=2:duration=first[aout]"
            )
            subprocess.run([
                "ffmpeg", "-y", "-i", concat_out,
                "-stream_loop", "-1", "-i", music,
                "-filter_complex", bgm_filter,
                "-map", "0:v", "-map", "[aout]",
                "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", output
            ], capture_output=True, check=True)
        else:
            import shutil
            shutil.copy(concat_out, output)

        import shutil
        shutil.rmtree(tmp_dir, ignore_errors=True)
        self.after(0, lambda: messagebox.showinfo("完成！", f"まとめ動画を保存しました:\n{output}"))

    def _done(self):
        self.progress.stop()
        self.run_btn.configure(state="normal")
        self.status_var.set("完成！ 動画が保存されました")


if __name__ == "__main__":
    app = App()
    app.mainloop()
