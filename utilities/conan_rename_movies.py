#!/usr/bin/env python3
"""
名探偵コナンの劇場版(映画)ファイルに、Wikipediaの作品一覧から取得した
邦題を付けてリネームする。

対象ファイル名パターン: Detective[ _]Conan_Movie_<話数2桁>_<年>.<拡張子>
  例: Detective Conan_Movie_01_1997.mp4
      Detective_Conan_Movie_20_2016.mp4
  -> 名探偵コナン_映画_01_時計じかけの摩天楼_1997.mp4

使い方:
  python3 conan_rename_movies.py <対象フォルダ>              # 実行（リネームする）
  python3 conan_rename_movies.py <対象フォルダ> --dry-run     # プレビューのみ

データ元: ja.wikipedia.org の Template:名探偵コナン映画作品
（「シリーズ」表の通番・題名・公開年を使用。総集編/コラボ作品は対象外）。

依存: 標準ライブラリのみ（urllib, json, re）。ネットワークアクセスが必要。
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

TEMPLATE_PAGE = "Template:名探偵コナン映画作品"
API_URL = "https://ja.wikipedia.org/w/api.php"
USER_AGENT = "conan-rename-movies-script/1.0 (personal use)"
REQUEST_INTERVAL_SEC = 0.5

FILENAME_RE = re.compile(r"^Detective[ _]Conan_Movie_(\d{2})_(\d{4})\.(mp4|mkv|mov|avi)$")

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


def clean(text):
    text = re.sub(r"\{\{ruby\|([^|}]*)\|[^}]*\}\}", r"\1", text)  # ふりがな -> 基本表記
    text = re.sub(r"\[\[[^\]|]*\|([^\]]*)\]\]", r"\1", text)      # [[リンク|表示]] -> 表示
    text = re.sub(r"\[\[([^\]]*)\]\]", r"\1", text)                # [[リンク]] -> リンク
    text = re.sub(r"<br\s*/?>", " ", text)
    text = re.sub(r"\{\{[^{}]*\}\}", "", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = re.sub(r"\s+", " ", text)
    return text.strip()


def build_title_map():
    data = api_get({"action": "parse", "page": TEMPLATE_PAGE, "prop": "wikitext"})
    wikitext = data["parse"]["wikitext"]["*"]
    m = re.search(r"\|\+シリーズ\n(.*?)\n\|\}", wikitext, flags=re.S)
    if not m:
        print("警告: シリーズ表が見つかりませんでした", file=sys.stderr)
        return {}
    table = m.group(1)

    titles = {}
    for row in table.split("\n|-"):
        lines = [l.strip() for l in row.split("\n") if l.strip()]
        num, cells = None, []
        for l in lines:
            mnum = re.search(r"第(\d+)作", l)
            if l.startswith("!") and mnum:
                num = int(mnum.group(1))
                continue
            if l.startswith("!") or l.startswith("|"):
                cells.append(l[1:])
        if num is None or len(cells) < 2:
            continue
        title = clean(cells[0])
        year_match = re.search(r"(\d{4})年", cells[1])
        if title and year_match:
            titles[num] = (title, year_match.group(1))
    return titles


def find_targets(root_dir):
    targets = []
    for dirpath, _dirs, filenames in os.walk(root_dir):
        for fn in filenames:
            m = FILENAME_RE.match(fn)
            if m:
                targets.append((dirpath, fn, m.group(1), m.group(2), m.group(3)))
    return targets


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("target_dir", help="対象フォルダ（再帰的に走査）")
    parser.add_argument("--dry-run", action="store_true", help="リネームせずプレビューのみ表示")
    args = parser.parse_args()

    targets = find_targets(args.target_dir)
    if not targets:
        print("タイトル未設定の劇場版ファイルは見つかりませんでした。")
        return

    print(f"{len(targets)}件検出。Wikipediaから作品一覧を取得します...", file=sys.stderr)
    titles = build_title_map()

    renamed, missing = 0, []
    for dirpath, fn, num_str, year_str, ext in targets:
        num = int(num_str)
        entry = titles.get(num)
        if entry is None:
            missing.append(fn)
            continue
        title, wiki_year = entry
        if wiki_year != year_str:
            print(f"警告: {fn} の年({year_str})とWikipediaの公開年({wiki_year})が不一致。ファイル名の年をそのまま使用します。", file=sys.stderr)
        new_name = f"名探偵コナン_映画_{num_str}_{title}_{year_str}.{ext}"
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
        print(f"タイトルが見つからなかった作品: {', '.join(sorted(missing))}", file=sys.stderr)


if __name__ == "__main__":
    main()
