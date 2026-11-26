# 別PCでのセットアップ手順

1. zip を展開して leo フォルダに移動
       cd leo
2. ツールのインストール
       brew install yt-dlp ffmpeg deno        (macOS)
       pip install manga-ocr pillow opencv-python numpy certifi
3. Chrome で YouTube にログインしておく（スクリプトが Chrome の Cookie を使うため）
   初回は manga-ocr のモデル（約450MB）が自動でダウンロードされます
4. 実行（必ず leo フォルダの中で）
       python get_channel_video_list.py --channel "https://www.youtube.com/@sunsunkidstv"
       python find_leo_full.py
       open leo_results/gallery.html          (Windows は start leo_results\gallery.html)
5. お絵描き紹介動画を画像でも探す場合
       python scan_oekaki.py

処理済みID（*_results/processed_ids.txt）を入れてあるので、処理済みの動画は飛ばされます。
ヒット画像（hit_frames）は容量削減のため入れていません。新しいヒットは別PCで新たに保存されます。
YouTube を自動で4倍速にしたい場合は youtube_4x_speed.user.js を Tampermonkey に登録してください。
