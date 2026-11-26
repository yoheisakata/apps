# Leo（りお）の絵を YouTube から探すツール

SunSun Kids TV (`@sunsunkidstv`) に投稿した Leo の絵が紹介されている動画を探すためのツール群。

## 背景

- 2025年2月14日前後にお絵かきをチャンネルに投稿
- どの動画で紹介されたか不明
- テロップに「りお」「りおくん」「りおちゃん」等で名前が表示されるはず
- 名前の読みは「りお」（Leo）、ローマ字は `leo`

## ツール一覧

### 1. `find_leo_full.py` — OCR テキスト検索

動画を DL し、1秒間隔でフレーム抽出、manga-ocr で下部テロップを読み取り「りお」を検索する。お絵描き紹介動画は全体、それ以外は末尾10分だけを対象にする。

```bash
python find_leo_full.py
```

- **方式**: manga-ocr（下部30%クロップ）
- **検索語**: 「りお」（部分一致 → りおくん/りおちゃん/りおさん全部拾う）
- **解像度**: 480p（`OCR_MAX_HEIGHT = 480`。1080p だと 1 本 100〜270MB で遅いため。テロップが読めなくなったら 720 などに上げる）
- **フレーム間隔**: 1秒
- **DL範囲**: お絵描き紹介動画（タイトルに「お絵描き」「お絵かき」「紹介」を含む）は全体、それ以外は末尾10分だけ（`TAIL_MINUTES = 10`）。長さが取れない動画は全体。
- **画像マッチ（`image_match.py`）は全動画を対象**にする点が OCR と異なる。
- **バッチ**: 20本DL → OCR → ギャラリー更新 → 動画削除（ストレージ節約）
- **出力**: `leo_results/hit_frames/`, `leo_results/gallery.html`

### 2. `image_match.py` — 画像マッチング検索

Leo の絵（`2025_0214_000000_12.jpeg`）をテンプレートとして、動画フレーム内で部分一致検索する。テロップが読めなくても、絵そのものが映っていれば検出可能。

```bash
python image_match.py
```

- **方式**: OpenCV テンプレートマッチング（複数スケール）
- **参照画像**: `2025_0214_000000_12.jpeg`
- **しきい値**: 0.55（形の一致度、グレースケール比較）
- **フレーム間隔**: 1秒
- **バッチ**: 20本DL → マッチング → ギャラリー更新 → 動画削除
- **出力**: `img_results/hit_frames/`, `img_results/gallery.html`

### 3. `get_channel_video_list.py` — チャンネル動画リスト取得

チャンネルの全動画のID・タイトル・アップロード日・長さを取得して `channel_video_list.json` に保存する。他のスクリプトの前提データ。

```bash
python get_channel_video_list.py --channel "https://www.youtube.com/@sunsunkidstv"
```

## 前提ツール

```bash
brew install yt-dlp ffmpeg deno python@3.12

# Python 3.12 の仮想環境（システムの pip は PEP 668 で拒否されるため venv を使う）
/opt/homebrew/opt/python@3.12/bin/python3.12 -m venv ~/.venvs/leo
~/.venvs/leo/bin/python -m pip install manga-ocr pillow opencv-python numpy certifi
```

- **Python 3.12 が必要**: 3.15 では `fugashi`（manga-ocr の依存）のビルドが通らない。
- **実行は venv の Python で**: `~/.venvs/leo/bin/python find_leo_full.py` など。
- **初回のみ**: manga-ocr のモデル（約450MB）をダウンロードする。
- **ブラウザの Cookie は使わない（既定）**: Chrome のプロファイルは macOS の権限で読めないため。必要なときだけ `LEO_COOKIES_BROWSER=chrome` を付けて実行する。

## ファイル構成

```
leo/
├── README.md                   ← ドキュメント
├── channel_list.py             ← 増分の動画リスト更新・対象期間・未処理の選定（共通）
├── find_leo_full.py            ← OCR テキスト検索
├── image_match.py              ← 画像マッチング検索
├── get_channel_video_list.py   ← 動画リスト取得（全件取り直し用）
├── channel_video_list.json     ← 動画リスト（日付付き）
├── 2025_0214_000000_12.jpeg    ← Leo の絵（参照画像）
├── leo_results/                ← OCR検索の結果
└── img_results/                ← 画像マッチングの結果
```

## 使い方

```bash
cd leo/   # このフォルダ（リポジトリ内でも、OneDrive 上の作業コピーでもよい）

# どちらか or 両方を実行（別ターミナルで並行可能）
python find_leo_full.py      # OCR検索
python image_match.py        # 画像マッチング

# 結果確認
open leo_results/gallery.html   # OCR結果
open img_results/gallery.html   # 画像マッチング結果
```

## 実行時の動き（増分チェック）

実行するたびに次の順で処理する（どのスクリプトも同じ）。

1. **動画リストを増分更新**: `channel_list.py` が新着だけを取得して `channel_video_list.json` の先頭に追加する。既知の動画に当たったら停止。日付が取れていない動画は、ここで日付を取り直す。
2. **対象期間を決める**: 開始は `SEARCH_FROM`（既定 `20260901` = 2026年9月1日 GMT、絵が入っていなかった時期の次）、終了は**実行日まで自動**。明日実行すれば、明日までの新着も対象になる。
3. **未処理だけ調べる**: `processed_ids.txt` にあるIDは飛ばす。OCR/マッチまで終わった動画だけ記録するので、途中で止めても次回は未完了分からやり直す。
4. **結果を出す**: ヒットを `results.json` / `gallery.html` に追加し、今回の新規ヒットを末尾に表示する。

```bash
cd ~/github/apps/leo
python find_leo_full.py     # OCR（「りお」テロップ）
python image_match.py       # 絵そのもののマッチング
```

## 中断・再開

どのスクリプトも `Ctrl+C` で安全に中断可能。再実行で処理済み動画を自動スキップして続きから再開する。

## 設定変更

- `channel_list.py` の `SEARCH_FROM` — 検索の開始日（YYYYMMDD）
- `channel_list.py` の `SEARCH_TO` — 終了日を固定したい場合だけ指定（既定 `None` = 実行日まで）
- `BATCH_SIZE` — 1バッチの本数（デフォルト: 20）
- `MATCH_THRESHOLD` — 画像マッチングのしきい値（0.55）
- `KEYWORD` — OCR検索語（デフォルト: `"りお"`）
