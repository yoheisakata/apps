#!/usr/bin/env python3
"""
名探偵コナン TVアニメのエピソードファイルに、Wikipediaのエピソード一覧から
取得したサブタイトルを付けてリネームする。

対象ファイル名パターン: 名探偵コナン_<話数4桁>.<拡張子>
  例: 名探偵コナン_1210.mp4 -> 名探偵コナン_1210_○○○○○.mp4
既にサブタイトルが付いている（話数の後に "_" が続く）ファイルはスキップする。

使い方:
  python3 conan_rename_episodes.py <対象フォルダ>              # 実行（リネームする）
  python3 conan_rename_episodes.py <対象フォルダ> --dry-run     # プレビューのみ
  python3 conan_rename_episodes.py <対象フォルダ> --since-year 2024
                                                                # 取得するシーズンの下限を
                                                                # 明示指定したい場合に使う。
                                                                # 省略時は新しいシーズンから
                                                                # 遡って自動で必要な範囲だけ
                                                                # 取得する

依存: 標準ライブラリのみ（urllib, json, re）。ネットワークアクセスが必要
（ja.wikipedia.org の MediaWiki API を叩く）。
"""

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

WIKI_PAGE = "名探偵コナンのアニメエピソード一覧"
API_URL = "https://ja.wikipedia.org/w/api.php"
USER_AGENT = "conan-rename-episodes-script/1.0 (personal use)"
REQUEST_INTERVAL_SEC = 0.5  # WikipediaのAPIレート制限(429)を避けるための最小間隔

FILENAME_RE = re.compile(r"^名探偵コナン_(\d{3,4})\.(mp4|mkv|mov|avi)$")
SEASON_LINE_RE = re.compile(r"^シーズン\d+（(\d+)年）$")

_last_request_time = 0.0


def api_get(params, max_retries=5):
    global _last_request_time
    params = dict(params, format="json")
    url = API_URL + "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    for attempt in range(max_retries):
        wait = REQUEST_INTERVAL_SEC - (time.monotonic() - _last_request_time)
        if wait > 0:
            time.sleep(wait)
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                _last_request_time = time.monotonic()
                return json.load(resp)
        except urllib.error.HTTPError as e:
            _last_request_time = time.monotonic()
            if e.code == 429 and attempt < max_retries - 1:
                backoff = 2 ** attempt
                print(f"  429 Too Many Requests、{backoff}秒待って再試行...", file=sys.stderr)
                time.sleep(backoff)
                continue
            raise


def get_season_sections(since_year=None):
    data = api_get({"action": "parse", "page": WIKI_PAGE, "prop": "sections"})
    sections = []
    for s in data["parse"]["sections"]:
        m = SEASON_LINE_RE.match(s["line"])
        if not m:
            continue
        year = int(m.group(1))
        if since_year is not None and year < since_year:
            continue
        sections.append((int(s["index"]), s["line"]))
    return sections


def get_section_wikitext(index):
    data = api_get({
        "action": "parse", "page": WIKI_PAGE,
        "prop": "wikitext", "section": index,
    })
    return data["parse"]["wikitext"]["*"]


def clean(text):
    text = re.sub(r"<ref[^>]*/>", "", text)
    text = re.sub(r"<ref[^>]*>.*?</ref>", "", text, flags=re.S)
    text = re.sub(r"\{\{ruby\|([^|}]*)\|[^}]*\}\}", r"\1", text)  # ふりがな -> 基本表記
    text = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", text)      # [[リンク|表示]] -> 表示
    text = re.sub(r"\[\[([^\]]*)\]\]", r"\1", text)                # [[リンク]] -> リンク
    text = re.sub(r"<br\s*/?>", " ", text)                         # 改行 -> スペース（連結防止）
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\{\{[^{}]*\}\}", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def looks_like_dvd_cell(field):
    f = field.strip()
    if f == "-":
        return True
    if "rowspan=" in f or "colspan=" in f:
        return True
    if re.search(r'style="text-align:center;?"', f):
        return True
    if re.match(r"(?i)^(part\d|vol\.)", f):  # 大文字小文字表記ゆれ（PART/Part）あり
        return True
    return False


def parse_episode_titles(wikitext):
    """1シーズン分のwikitextから {話数(int): サブタイトル} を抽出する。"""
    titles = {}
    for table in re.findall(r"\{\|.*?\n\|\}", wikitext, flags=re.S):
        for row in table.split("\n|-"):
            row = row.lstrip("\n")
            if not row.startswith("|"):
                continue
            fields = row[1:].split("||")
            if len(fields) < 3:
                continue
            ep_field = fields[1].strip()
            if not re.match(r"^\d{3,4}$", ep_field):
                continue  # 特別編など非数値の話数はスキップ
            idx = 2
            if idx < len(fields) and looks_like_dvd_cell(fields[idx]):
                idx += 1
            if idx >= len(fields):
                continue
            subtitle = clean(fields[idx])
            if subtitle:
                titles[int(ep_field)] = subtitle
    return titles


def build_title_map(needed_episodes, since_year=None):
    """新しい(放送年が新しい)シーズンから遡って取得し、必要な話数が
    揃うか、対象範囲より古いシーズンに達したら打ち切る。"""
    sections = get_season_sections(since_year)
    if not sections:
        print("警告: シーズンのセクションが見つかりませんでした", file=sys.stderr)
        return {}
    min_needed = min(needed_episodes) if needed_episodes else None
    titles = {}
    for index, line in sorted(sections, reverse=True):  # 新しい年から
        wikitext = get_section_wikitext(index)
        season_titles = parse_episode_titles(wikitext)
        titles.update(season_titles)
        print(f"  取得: {line} (累計{len(titles)}話)", file=sys.stderr)
        if needed_episodes and needed_episodes.issubset(titles.keys()):
            break
        if since_year is None and season_titles and min(season_titles) <= min_needed:
            # これ以上古いシーズンはさらに小さい話数しか含まないため打ち切ってよい
            break
    return titles


def find_targets(root_dir):
    """タイトル未設定のファイルを再帰的に探す。"""
    targets = []
    for dirpath, _dirs, filenames in os.walk(root_dir):
        for fn in filenames:
            m = FILENAME_RE.match(fn)
            if m:
                targets.append((dirpath, fn, m.group(1), m.group(2)))
    return targets


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target_dir", help="対象フォルダ（再帰的に走査）")
    parser.add_argument("--dry-run", action="store_true", help="リネームせずプレビューのみ表示")
    parser.add_argument("--since-year", type=int, default=None, help="この年以降のシーズンだけ取得する（高速化用）")
    args = parser.parse_args()

    targets = find_targets(args.target_dir)
    if not targets:
        print("タイトル未設定のファイルは見つかりませんでした。")
        return

    print(f"{len(targets)}件のタイトル未設定ファイルを検出。Wikipediaから話数一覧を取得します...", file=sys.stderr)
    needed_episodes = {int(epnum_str) for _d, _f, epnum_str, _e in targets}
    titles = build_title_map(needed_episodes, args.since_year)

    renamed, missing = 0, []
    for dirpath, fn, epnum_str, ext in targets:
        epnum = int(epnum_str)
        title = titles.get(epnum)
        if title is None:
            missing.append(fn)
            continue
        new_name = f"名探偵コナン_{epnum_str}_{title}.{ext}"
        old_path = os.path.join(dirpath, fn)
        new_path = os.path.join(dirpath, new_name)
        if args.dry_run:
            print(f"[dry-run] {fn} -> {new_name}")
        else:
            os.rename(old_path, new_path)
            print(f"{fn} -> {new_name}")
        renamed += 1

    print(f"\n完了: {renamed}件{'（プレビュー）' if args.dry_run else ''}", file=sys.stderr)
    if missing:
        print(f"タイトルが見つからなかった話数（Wikipediaに未掲載の可能性）: {', '.join(sorted(missing))}", file=sys.stderr)


if __name__ == "__main__":
    main()
