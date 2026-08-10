#!/usr/bin/env python3
"""まなびアプリの読み上げ音声を一括生成する。

Open JTalk (pyopenjtalk-plus, Mei ボイス同梱・完全オフライン) で
固定フレーズを合成し、audio/ 以下に mp3 で書き出す。
くくの読み(よみ)は app.js の KUKU データから抽出する。

使い方:
    pip install pyopenjtalk-plus lameenc numpy
    python3 tools/generate_audio.py

生成後は sw.js の CACHE_NAME をインクリメントすること。
より高品質にしたい場合は、同じファイル構成のまま VOICEVOX 等で
作り直して差し替えればアプリ側の変更は不要。
"""

import os
import re

import lameenc
import numpy as np
import pyopenjtalk

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUDIO_DIR = os.path.join(APP_DIR, "audio")

# app.js と同じ 46 文字とローマ字ファイル名
KANA_ROMAJI = {
    "あ": "a", "い": "i", "う": "u", "え": "e", "お": "o",
    "か": "ka", "き": "ki", "く": "ku", "け": "ke", "こ": "ko",
    "さ": "sa", "し": "shi", "す": "su", "せ": "se", "そ": "so",
    "た": "ta", "ち": "chi", "つ": "tsu", "て": "te", "と": "to",
    "な": "na", "に": "ni", "ぬ": "nu", "ね": "ne", "の": "no",
    "は": "ha", "ひ": "hi", "ふ": "fu", "へ": "he", "ほ": "ho",
    "ま": "ma", "み": "mi", "む": "mu", "め": "me", "も": "mo",
    "や": "ya", "ゆ": "yu", "よ": "yo",
    "ら": "ra", "り": "ri", "る": "ru", "れ": "re", "ろ": "ro",
    "わ": "wa", "を": "wo", "ん": "nn",
}

COMMON = {
    "praise1": "せいかい!",
    "praise2": "すごい!",
    "praise3": "やったね!",
    "praise4": "その ちょうし!",
    "wrong": "おしい! もういちど!",
    "goodjob": "よく できました!",
}

SPEED = 0.95     # ややゆっくり (子ども向け)
HALF_TONE = 1.0  # 半音上げてやわらかく


def to_katakana(ch):
    # 単独のひらがなは助詞読み(は→わ 等)されうるのでカタカナで合成する
    return chr(ord(ch) + 0x60)


def extract_kuku_yomi():
    """app.js の KUKU 配列から (a, b, よみ) を抽出する。"""
    src = open(os.path.join(APP_DIR, "app.js"), encoding="utf-8").read()
    entries = re.findall(
        r'\{ a: (\d+), b: (\d+), ans: \d+, yomi: "([^"]+)" \}', src)
    assert len(entries) == 81, f"KUKU entries: {len(entries)}"
    return [(int(a), int(b), yomi) for a, b, yomi in entries]


def synth_mp3(text, path):
    x, sr = pyopenjtalk.tts(text, speed=SPEED, half_tone=HALF_TONE)
    x = x.astype(np.int16)
    enc = lameenc.Encoder()
    enc.set_bit_rate(64)
    enc.set_in_sample_rate(sr)
    enc.set_channels(1)
    enc.set_quality(2)
    data = enc.encode(x.tobytes()) + enc.flush()
    with open(path, "wb") as f:
        f.write(bytes(data))
    print(f"{os.path.relpath(path, APP_DIR)}  ({len(data) // 1024} KB)  {text}")


def main():
    files = []

    trace_dir = os.path.join(AUDIO_DIR, "trace")
    os.makedirs(trace_dir, exist_ok=True)
    for kana, romaji in KANA_ROMAJI.items():
        name = f"trace/{romaji}.mp3"
        synth_mp3(f"「{to_katakana(kana)}」を、なぞってね。",
                  os.path.join(AUDIO_DIR, name))
        files.append(name)

    common_dir = os.path.join(AUDIO_DIR, "common")
    os.makedirs(common_dir, exist_ok=True)
    for name, text in COMMON.items():
        rel = f"common/{name}.mp3"
        synth_mp3(text, os.path.join(AUDIO_DIR, rel))
        files.append(rel)

    kuku_dir = os.path.join(AUDIO_DIR, "kuku")
    os.makedirs(kuku_dir, exist_ok=True)
    for a, b, yomi in extract_kuku_yomi():
        rel = f"kuku/{a}x{b}.mp3"
        synth_mp3(f"{yomi}。", os.path.join(AUDIO_DIR, rel))
        files.append(rel)

    # Service Worker がキャッシュするファイル一覧 (sw.js が importScripts で読む)
    manifest = os.path.join(APP_DIR, "audio-manifest.js")
    with open(manifest, "w", encoding="utf-8") as f:
        f.write("// tools/generate_audio.py が生成 — 手で編集しないこと\n")
        f.write("var AUDIO_FILES = [\n")
        for rel in files:
            f.write(f'  "audio/{rel}",\n')
        f.write("];\n")
    print(f"audio-manifest.js: {len(files)} files")


if __name__ == "__main__":
    main()
