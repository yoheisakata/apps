# MyMusic

YouTube や Suno / MusicCreator.ai / MusicGPT などの曲リンクをプレイリストとして貼り付け、
まとめて再生できる macOS 用のミニ・ミュージックプレーヤーです。downloader と同じくメニューバーに
常駐し(Dock アイコンなし)、ウィンドウを閉じても再生は止まりません。

## 使い方

1. `./install.sh` でビルドして `/Applications/MyApplications/` にインストール
2. 起動するとメニューバーに ♪ アイコンが常駐します。クリックでメニューから「ウィンドウを開く」
   (ウィンドウを閉じてもアプリは終了せず、再生も継続します。完全に終了するにはメニューの「終了」)
3. 上部の入力欄に曲のリンクを貼り付けて ➕ で追加
   - 複数リンクをまとめて追加したいときは、入力欄の隣の 📝 ボタンから「リンクをインポート」を開き、
     1行につき1リンクの形式でテキストを貼り付けて「インポート」を押す
   - インポートで失敗したリンクはスキップされ、シート内にエラー内容が一覧表示される。
     詳細は `~/Library/Application Support/MyMusic/import-errors.log` にも追記される
     (シート内の「エラーログを Finder で表示」からも開ける)
4. プレイリストの行をクリックすると再生開始。シャッフル/前へ/再生/次へ・シークバー・音量が使えます
   - シャッフルをオンにすると、次へ/自動送りはプレイリストからランダムに選び、前へは
     実際に再生した順序を遡ります(設定は次回起動時も保持されます)
5. 行はドラッグで並び替え、スワイプまたは編集操作で削除できます

## 対応リンク

| サイト | 方式 |
|---|---|
| YouTube (`youtube.com` / `youtu.be`) | `yt-dlp` + `ffmpeg` で音声を mp3 抽出し、ローカルにキャッシュしてから再生 |
| Suno (`suno.com`) | ページ内に埋め込まれた `audio_url` を直接ストリーミング再生 |
| MusicCreator.ai | ページの `og:audio` メタタグの mp3 URL を直接ストリーミング再生 |
| MusicGPT | ページ内に埋め込まれた `file_output_0` の mp3 URL を直接ストリーミング再生 |
| `.mp3` / `.m4a` / `.wav` などへの直リンク | そのままストリーミング再生 |
| その他のサイト | `og:audio` メタタグがあれば再生を試みる(なければ追加失敗) |

YouTube 以外は各サイトが公開しているページ内の音声 URL を読み取っているだけで、
サイト側の実装が変わると取得できなくなる可能性があります。

## 必要なツール(YouTube リンクのみ)

Homebrew で以下をインストールしてください。

```bash
brew install yt-dlp ffmpeg
```

未インストールの場合、YouTube 以外のリンクは通常どおり使えます。

## データの保存場所

- プレイリスト: `~/Library/Application Support/MyMusic/playlist.json`
- YouTube から抽出した mp3 のキャッシュ: `~/Library/Application Support/MyMusic/cache/`
- インポート失敗ログ: `~/Library/Application Support/MyMusic/import-errors.log`(インポート実行のたびに追記)
