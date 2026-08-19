#!/usr/bin/env python3
"""ひらがな46文字の筆順ストロークデータを生成する。

KanjiVG (https://kanjivg.tagaini.net/ / PyPI の kanjivg パッケージ,
CC BY-SA 3.0) の SVG から各画の中心線パスを取り出し、キャンバス座標
(320x320) のポリラインに変換して hiragana-strokes.js に書き出す。
なぞりがきのお手本描画と書き順判定の両方がこのデータを使う。

使い方:
    pip install kanjivg
    python3 tools/generate_strokes.py

生成後は sw.js の CACHE_NAME をインクリメントすること。
"""

import json
import math
import os
import re
import sys

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def find_kvg_dir():
    # kanjivg wheel は site-packages 直下に kanji/ (SVG 群) を配置する
    for base in sys.path:
        cand = os.path.join(base, "kanji")
        if os.path.isfile(os.path.join(cand, "03042.svg")):
            return cand
    raise SystemExit("KanjiVG が見つからない。pip install kanjivg を実行すること")


KVG_DIR = find_kvg_dir()

KANA = list("あいうえおかきくけこさしすせそたちつてとなにぬねの"
            "はひふへほまみむめもやゆよらりるれろわをん")

VIEWBOX = 109.0   # KanjiVG の座標系
CANVAS = 320.0    # アプリのキャンバス論理サイズ
STEP = 6.0        # 出力ポリラインの点間隔 (キャンバス座標)


def parse_path(d):
    """KanjiVG のパス (M/m, C/c, S/s のみ) を細かい折れ線に展開する。"""
    tokens = re.findall(r"([MmCcSsLl])([^MmCcSsLl]*)", d)
    pts = []
    cur = (0.0, 0.0)
    prev_c2 = None
    for cmd, args in tokens:
        nums = [float(v) for v in re.findall(r"-?\d*\.?\d+(?:e-?\d+)?", args)]
        if cmd in "Mm":
            x, y = nums[0], nums[1]
            if cmd == "m":
                x, y = cur[0] + x, cur[1] + y
            cur = (x, y)
            pts.append(cur)
            prev_c2 = None
            nums = nums[2:]
            # M の後に座標が続く場合は暗黙の lineto
            while nums:
                x, y = nums[0], nums[1]
                if cmd == "m":
                    x, y = cur[0] + x, cur[1] + y
                cur = (x, y)
                pts.append(cur)
                nums = nums[2:]
        elif cmd in "Ll":
            while nums:
                x, y = nums[0], nums[1]
                if cmd == "l":
                    x, y = cur[0] + x, cur[1] + y
                cur = (x, y)
                pts.append(cur)
                prev_c2 = None
                nums = nums[2:]
        elif cmd in "CcSs":
            while nums:
                if cmd in "Cc":
                    c1x, c1y, c2x, c2y, ex, ey = nums[:6]
                    nums = nums[6:]
                    if cmd == "c":
                        c1x += cur[0]; c1y += cur[1]
                        c2x += cur[0]; c2y += cur[1]
                        ex += cur[0]; ey += cur[1]
                else:  # smooth: 第1制御点は直前の第2制御点の鏡映
                    c2x, c2y, ex, ey = nums[:4]
                    nums = nums[4:]
                    if cmd == "s":
                        c2x += cur[0]; c2y += cur[1]
                        ex += cur[0]; ey += cur[1]
                    if prev_c2 is not None:
                        c1x = 2 * cur[0] - prev_c2[0]
                        c1y = 2 * cur[1] - prev_c2[1]
                    else:
                        c1x, c1y = cur
                # 3次ベジェを展開
                for i in range(1, 25):
                    t = i / 24.0
                    mt = 1 - t
                    x = (mt**3 * cur[0] + 3 * mt**2 * t * c1x
                         + 3 * mt * t**2 * c2x + t**3 * ex)
                    y = (mt**3 * cur[1] + 3 * mt**2 * t * c1y
                         + 3 * mt * t**2 * c2y + t**3 * ey)
                    pts.append((x, y))
                cur = (ex, ey)
                prev_c2 = (c2x, c2y)
        else:
            raise ValueError(f"unsupported path command: {cmd}")
    return pts


def resample(pts, step):
    """等間隔 (step) のポリラインに再サンプルする。"""
    out = [pts[0]]
    acc = 0.0
    for i in range(1, len(pts)):
        x0, y0 = pts[i - 1]
        x1, y1 = pts[i]
        seg = math.hypot(x1 - x0, y1 - y0)
        while acc + seg >= step:
            t = (step - acc) / seg
            nx, ny = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
            out.append((nx, ny))
            x0, y0 = nx, ny
            seg = math.hypot(x1 - x0, y1 - y0)
            acc = 0.0
        acc += seg
    if out[-1] != pts[-1]:
        out.append(pts[-1])
    return out


def main():
    scale = CANVAS / VIEWBOX
    data = {}
    for ch in KANA:
        svg = open(os.path.join(KVG_DIR, f"{ord(ch):05x}.svg"),
                   encoding="utf-8").read()
        paths = re.findall(r'<path[^>]*\bd="([^"]+)"', svg)
        strokes = []
        for d in paths:
            pts = [(x * scale, y * scale) for x, y in parse_path(d)]
            pts = resample(pts, STEP)
            strokes.append([[round(x), round(y)] for x, y in pts])
        assert strokes, ch
        data[ch] = strokes
        print(ch, len(strokes), "画,", sum(len(s) for s in strokes), "点")

    out = os.path.join(APP_DIR, "hiragana-strokes.js")
    with open(out, "w", encoding="utf-8") as f:
        f.write("// tools/generate_strokes.py が KanjiVG (CC BY-SA 3.0,\n")
        f.write("// https://kanjivg.tagaini.net/) から生成 — 手で編集しないこと\n")
        f.write("var HIRAGANA_STROKES = ")
        f.write(json.dumps(data, ensure_ascii=False, separators=(",", ":")))
        f.write(";\n")
    print(f"{out}: {os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
