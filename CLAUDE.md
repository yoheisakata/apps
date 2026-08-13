# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo has two distinct kinds of projects:

1. **Web apps** ("My Apps" — 旧アプリひろば) hosted on GitHub Pages — mobile-friendly, all-Japanese UI. The root `index.html` is the launcher/home screen, a single flat icon grid (no category sections).
2. **Native macOS/iOS tools** (`mynetworth/`, `myorganizer/`, `mygallery/`, `mydownloader/`, `mymusic/`, `mytube/`, `mygames/`, `mypass/`, `kindle-transfer/`, `utilities/`) — personal-use local tools, built and run outside GitHub Pages, **not** referenced from the root `index.html`.

When editing, check which category a folder belongs to before assuming GitHub-Pages-style conventions (single HTML file, no build) apply.

Each app directory has its own `README.md` (user-facing, Japanese) and `CLAUDE.md` (dev guidance) — read the app's own docs before making changes there, and update them when behavior changes.

## Architecture

### Web apps (deployed to GitHub Pages)

Most are **single self-contained HTML files** (inline CSS + JS) in their own directory — no build step, no dependencies, no frameworks. Open any `index.html` directly in a browser to develop. Exceptions:

- **world-cup-2026/** — Multi-file vanilla app: `index.html` + `main.js` + ES-module views in `views/` + `style.css`, with static datasets in `data/*.json`. No build step. The tournament ended 2026-07-19 (final: Spain 1-0 Argentina) — the app is now a fully static archive; all 104 match results are baked into `data/*.json`. The old live-fetch pipeline (Wikipedia + openfootball fallback, a Cloudflare Worker proxying FIFA rankings) was removed — do not reintroduce it.
- **kids-learning-app/** — Multi-file vanilla app (「まなびアプリ」): `index.html` + `app.js` + `style.css` + `manifest.json` + `sw.js` (installable PWA with offline cache — bump `CACHE_NAME` in `sw.js` whenever cached assets change). Covers たしざん (leveled, 5 levels), くく/かけざん (speech-read multiplication tables via `speechSynthesis`), ひらがな, and ローマ字タイピング, with a shared star (`localStorage`) + sound-effect reward system across all modes. Absorbed the former standalone `sansu/` app (たしざん levels + 九九) — do not re-add `sansu/` as a separate app.
- **awsquiz/** — AWS Certified Solutions Architect – Professional (**SAP-C02**) 対策アプリ「AWS SAP 対策」: `index.html` (UI + logic) + `questions.js` (question bank, kept separate because it is large) + `manifest.json` + `sw.js` (installable PWA so it works offline on the iPhone). No build step, no `fetch` — it still opens over `file://`. 202 questions across the exam's 4 domains, weighted to the real 26/29/25/20% split; a second axis of 14 技術分野 categories. `SAP-C02-quiz.md` in the same folder is the user's own hand-written practice set; the 30 questions whose `id` starts with `md-` were imported from it, so edits to one should be mirrored in the other. Five modes: 今日の練習 / 分野別クイズ / まちがい復習 / 模擬試験 (75問180分 or 40問95分, no per-question feedback, 1000点換算スコア) / フラッシュカード, plus a 進捗 screen. Progress lives in `localStorage` (`awsquiz-v1`) as a per-question Leitner box (連続3回正解で習得ずみ) plus a daily log driving the exam countdown, daily goal ring and streak. **`sw.js` here is network-first on purpose** (cache-first would keep serving a stale `questions.js` after questions are added). See `awsquiz/CLAUDE.md` — it has the data schema, the `id`-is-a-save-key rule, and a validation one-liner to run after editing questions.

Static single-file apps: `earth`, `tarot` (`index.html` 占い + `quiz.html` クイズ), `shinkansen`, `pgquiz` (PostgreSQL 17以降向けのクイズ/フラッシュカード学習アプリ、104問・13カテゴリ).

> `learn-postgresql/` (pglite/WASM SQL lab) and `receipt/` (Claude API + Firebase レシート web app; the user's Firebase account was deleted — receipt management now lives in mynetworth's レシート tab) were removed from the repo; do not re-add references to them unless the folders come back.

### Native macOS/iOS tools (not deployed to GitHub Pages)

- **mynetworth/**, **myorganizer/**, **mydownloader/**, **mymusic/**, **mytube/**, **mygames/**, **mypass/** — SwiftUI apps built with **Swift Package Manager** (`Package.swift`, `Sources/`); **mygallery/** is the odd one out (plain Swift + AppKit, a single `Sources/main.swift` compiled with `swiftc` — no `Package.swift`). Shared conventions: `make-icon.swift` generates `AppIcon.icns`/`AppIcon.iconset/`, a build script produces a local ad-hoc-signed `.app` bundle. No App Store distribution, no CI. Install/update scripts differ per app:
  - All SPM apps: build script (bundle in place) + `./install.sh` (build + copy to `/Applications/MyApplications/`).
  - mynetworth: `./build_app.sh` or `./install.sh`. `build_app.sh` reads `appVersion` from `Sources/MyNetWorth/Main.swift` (single source of truth) into Info.plist, and bundles `2026_Sakata_支出表.md` as the 固定収支 tab's fallback.
  - myorganizer: `./build_app.sh` or `./install.sh`.
  - mydownloader: `./build_app.sh` or `./install.sh`.
  - mymusic: `./build_app.sh` or `./install.sh`.
  - mytube: `./build_app.sh` or `./install.sh`.
  - mygames: `./build_app.sh` or `./install.sh`. See `mygames/CLAUDE.md`.
  - mypass: `./build_app.sh` or `./install.sh`.
  - mygallery: **no `install.sh`** — `./build.sh` (= `./build.sh install`) builds and copies to `/Applications/MyApplications/`; `./build.sh app` only builds the bundle in `build/`.
- **mynetworth/** (MyNetWorth — renamed from `networth`/NetWorth on 2026-08-12, together with its bundle ID `com.yoheisakata.mynetworth` and its data dir `~/Library/Application Support/MyNetWorth/`; the LaunchAgent became `com.yoheisakata.mynetworth-fetch`) specifics (v0.4.x, requires **macOS 26** via `Package.swift` — FoundationModels): tabs are メイン / 週 / 月 / 投資 / 固定収支 / レシート.
  - **The Keychain service string stays `com.yoheisakata.networth`** (`Keychain.swift`) — it is the lookup key of the already-stored SimpleFIN access URL, so renaming it would lose the token (same reasoning as MyPass's `PMBACKUP` magic).
  - `--fetch` CLI mode for headless data collection; `com.yoheisakata.mynetworth-fetch.plist` LaunchAgent runs it every morning (see [[networth-tracker]] memory for operational details).
  - 投資 tab overlays live quotes from Yahoo Finance's public chart API (`Quotes.swift`, no API key) on SimpleFIN's once-a-day holding values.
  - 固定収支 tab (`FixedBudget.swift`) renders `mynetworth/2026_Sakata_支出表.md` with a minimal Markdown parser — it reads the repo file at `~/github/apps/mynetworth/` directly (edit + 再読込 to update), falling back to the copy bundled at build time.
  - レシート tab (`Receipts.swift` + `ReceiptsTab.swift`) — Schedule C 向けレシート管理: Vision OCR + FoundationModels (on-device LLM) extraction; data lives in `~/Library/Application Support/Receipts/`. FoundationModels prompts must be in English (the model rejects prompts not matching the Apple Intelligence language setting). `ExpenseCategory` cases map to Schedule C Part II lines (8–27a) and their rawValues are persisted — never rename them.
- **kindle-transfer/** — Single Bash script (`kindle-transfer.sh`), no build. Uses `adb` to pull files from a Kindle Fire's SD card/internal storage over USB.
- **utilities/** — Standalone Python 3 / Bash scripts (not a packaged app) for a personal photo/video pipeline: backup organization (`backup-photos.sh`, `backup-videos.sh`, `sync-backups.sh`, `verify-photos.sh`), H.265 re-encoding (`encode_h265.py`), short-clip detection (`find_short_videos.py`). Run individually from the CLI; no shared entry point.
- **myorganizer/** — GUI front-end covering all of `utilities/`'s functionality (写真整理/動画整理/エンコード/誤配置修正/同期/短い動画検索 in a sidebar) plus a dependency-check pane. Deliberately **reimplements** the scripts' logic natively in Swift rather than shelling out to `utilities/` — the two do not stay in sync automatically; see `myorganizer/CLAUDE.md`. External tools (`ffmpeg`/`ffprobe`/`rsync`/`sips`/`mdls`) are still invoked as subprocesses, not bundled. Also absorbed the former standalone `renamer/` app as its「リネーム」pane (rule-based batch renaming), the former standalone `cleanmac/` app as its「キャッシュ掃除」/「アプリ削除」panes (trash-only cache/app cleanup — the same `cleanmac/`-derived「重複写真」pane was later removed, see `myorganizer/CLAUDE.md`), and the former standalone `omoide/` app as its「まとめ動画」pane (clips a kids'-video folder into one movie with title cards + BGM via ffmpeg — see `myorganizer/CLAUDE.md`) — do not re-add `renamer/`, `cleanmac/`, or `omoide/` as separate apps.
- **mydownloader/** (MyDownloader — renamed from `downloader`/Downloader on 2026-08-12, together with its bundle ID `com.yohei.mydownloader`) — Regular Dock-icon app (also keeps a menu-bar status item; closing the window doesn't quit the app — `NSApp.setActivationPolicy(.regular)` + `applicationShouldTerminateAfterLastWindowClosed == false`, no `LSUIElement`, no SwiftUI `WindowGroup`, since 2026-08-05). A thin GUI over `yt-dlp`/`ffmpeg` (Homebrew, not bundled): single videos and — since 2026-08-05 — full playlists, downloaded into a per-playlist subfolder; a "ダウンロード名" field auto-fetches the title on paste and lets the user override it. Absorbed the former standalone `youtube-dl-mac` — do not re-add it as a separate app. **The torrent half was removed on 2026-08-12**: the app used to have a second "Torrent" tab wrapping `aria2c` over JSON-RPC (absorbed from `torrent-dl-mac`), plus a `magnet:` URL-scheme handler. All of it — `Aria2Engine`/`TorrentView`/`AddTorrentView`/`SettingsView`/`Models` and the `CFBundleURLTypes` entry — is gone; **do not reintroduce torrent support or `torrent-dl-mac`** without asking. The old implementation is in git history.
- **mymusic/** (MyMusic — renamed from `musicplayer`/MusicPlayer on 2026-08-12, together with its bundle ID `com.yohei.mymusic` and its data dir `~/Library/Application Support/MyMusic/`; do not re-add `musicplayer/`) — Regular Dock-icon app (as of 2026-08-12 it is **no longer menu-bar-resident** — `LSUIElement` and the ♪ status item were removed; unlike mytube, though, closing the window doesn't quit or stop playback: `applicationShouldTerminateAfterLastWindowClosed == false` + `applicationShouldHandleReopen` reopens from the Dock). A music player with an iTunes/Music.app-style three-pane layout: a top transport bar, a library sidebar (`LibrarySidebarView`/`Library.swift`), and the song list. Sources: song links (YouTube, Suno, MusicCreator.ai, MusicGPT, or direct `.mp3` links) added singly or bulk-imported one-per-line via a sheet that logs failures to `import-errors.log`, **plus OneDrive 共有リンク** — a shared folder is scanned recursively (`OneDriveShareClient.swift`, ported from mytube's client) and shows up in the sidebar as its own folder tree; picking a folder makes it the play queue. OneDrive's signed URLs expire in ~1 hour, so each track stores driveId/itemId and the URL is re-fetched right before playback. Same `AppDelegate`-owns-the-engines / `NSApplication.shared.run()` structure as mydownloader. YouTube links are extracted to a local mp3 cache via `yt-dlp`/`ffmpeg` (same "thin GUI over CLI" approach as mydownloader); the AI-song-sharing sites (Suno/MusicCreator.ai/MusicGPT) each embed a direct, publicly-fetchable mp3 URL in their server-rendered HTML (JSON blob or `og:audio` meta tag) — no headless browser or JS execution needed, just an `URLSession` HTML fetch + regex per site (see `mymusic/CLAUDE.md` for the exact extraction patterns, a backslash-escaping gotcha in the Suno/MusicGPT JSON, and how to re-derive them if a site's markup changes).
- **mytube/** — Regular windowed app (standard SwiftUI `App`/`WindowGroup`, not menu-bar-resident like mydownloader/mymusic — playback doesn't need to continue after the window closes). A video player with a YouTube-like look: **multiple** local folders can be open at once (each recursively scanned, its folder tree shown in the sidebar), and since 2026-08-04/05 two remote sources join the same library — OneDrive 共有リンク and YouTube playlists — both cached locally by `Core/DownloadStore.swift` (different download paths and post-cache handling for each; see `mytube/CLAUDE.md`). The sidebar groups them as ローカル / OneDrive / YouTube. A thumbnail grid (auto-generated + disk-cached frame per video, `~/Library/Caches/MyTube/thumbnails/`) is the home feed; `ContentView` swaps `HomeVideosView` for `PlayerPaneView` (`AVKit.VideoPlayer`) on `selectedVideo`, with an "up next" list that autoplays sequentially. Open folders persist as plain `UserDefaults` path strings (`Settings.openLocalFolders` — no security-scoped bookmark needed since the app isn't sandboxed). `Package.swift` must keep `linkerSettings: [.linkedFramework("AVKit")]` — without it the installed `.app` aborts at launch. See `mytube/CLAUDE.md` for the async thumbnail-cache design and the autoplay-closure-staleness pitfall.
- **mygames/** (MyGames — renamed from `emulator`/RetroGames on 2026-08-12, together with its bundle ID `com.yoheisakata.mygames` and its data dir `~/Library/Application Support/MyGames/`) — NES/SNES emulator frontend using the libretro API (loads `.dylib` cores at runtime via `dlopen`). Tabs: ライブラリ / ROM / コントローラー / ボードゲーム. Also absorbed the former standalone `boardgames` app (将棋・チェス・オセロ・囲碁・五目並べ・麻雀・ダイヤモンドゲームの7種、AI対戦あり) as its「ボードゲーム」タブ — do not re-add `boardgames` as a separate app. See `mygames/CLAUDE.md`.
- **mygallery/** (MyGallery — renamed from `photo-gallery`; bundle ID `com.yosakata.mygallery`) — Photos.app-like browser for a local folder tree, **not** an SPM package: a single `Sources/main.swift` (Swift + AppKit, no WKWebView, no dependencies, no runtime networking) compiled directly by `build.sh`, which also writes the Info.plist inline and reads the version from the `VERSION` file. Nothing is imported into a library — the chosen root folder is scanned in place. Features: thumbnail grid + full-size viewer, sort orders including a Vision-based blur/quality score, filters (date range / 人物あり・なし / イラスト・写真, all on-device Vision), 重複検出 (⇧⌘D) with four match levels from exact SHA-256 to dHash fuzzy matching, and rotation that re-writes the original file. Deletions go to the Trash (⌘⌫, no confirmation, restorable). The dup-detection logic was ported from myorganizer's old「重複写真」pane, which has since been removed from myorganizer — mygallery is now the only place it lives.
- **mypass/** (MyPass — renamed from `passman`/PassMan on 2026-08-12, together with its bundle ID `com.yoheisakata.mypass` and its data dir `~/Library/Application Support/MyPass/`) — SwiftUI password manager. Everything is stored as one encrypted blob (`vault.dat`); the master password derives a KEK via PBKDF2-HMAC-SHA256 (600k iterations, CommonCrypto — `CryptoStore.swift` explains why Argon2id was not used despite `DESIGN.md`), which unwraps a DEK used for AES-256-GCM. Touch ID unlock stores the DEK in the Keychain (`BiometricStore.swift`). **The `.passmanbackup` extension and its `PMBACKUP` magic keep the old name on purpose** — they are file contents, so renaming them would break every previously exported backup (`VaultFile.swift`); `*.passmanbackup` is gitignored since backups are personal data.

## Build / Dev Commands

Web apps need no build — open the HTML file in a browser. There are no tests anywhere in this repo.

### SwiftUI/SPM native apps (mynetworth, myorganizer, mydownloader, mymusic, mytube, mygames, mypass)

```bash
cd <app>
swift build         # compile check (verification method — see below)
# Build the .app bundle:
./build_app.sh      # every SPM app
# Install/update in /Applications/MyApplications:
./install.sh        # every SPM app (build + copy to /Applications/MyApplications)
```

mygallery is not an SPM package — use `./build.sh` there (see the mygallery entry above); `swift build` does not apply to it.

**GUI アプリを起動しないこと**: `swift run`・`open <App>.app`・`.build/debug/<App>` の直接実行など、ウィンドウが開く形での目視確認は禁止(permissions の deny ルールでもブロック済み)。検証は `swift build` のコンパイル確認まで。アプリの起動・目視確認はユーザー自身が行う。例外: `MyNetWorth --fetch` のようなヘッドレス CLI モードは実行してよい。

## Conventions

### Web apps
- Dark gradient themes and CSS custom properties for colors; several apps (pgquiz) use the Nunito font (Google Fonts).
- Mobile-first: `viewport` meta with `user-scalable=no`, touch-optimized interactions.
- State persistence via `localStorage` where it matters: world-cup-2026 stores the theme (`wc2026-theme`); kids-learning-app persists a star count (`manabi-stars`).
- Icons are emoji or inline SVG data URIs — no external image assets.
- world-cup-2026 has two version knobs to bump on release: `?v=N` cache-busters on JS/CSS imports and `APP_VERSION` in `main.js` (shown in the header). The old `LIVE_CACHE_KEY` knob is gone with the live-fetch pipeline; `main.js` only keeps a one-time cleanup that purges the leftover live-era `localStorage` keys.

### Native macOS apps
- **App names use the `My〜` prefix** (all eight: MyDownloader / MyGallery / MyGames / MyMusic / MyNetWorth / MyOrganizer / MyPass / MyTube — as of 2026-08-12 no app is left without the prefix). When renaming one, change all of: directory name, SPM target + `Sources/<Target>/`, product/executable name, `.app` display name, bundle ID, `~/Library/Application Support/<name>/` data dir (mv the existing one to carry data over), build/install scripts, README + CLAUDE.md, and the old `/Applications` copy (trash it). See the [[app-rename-my-prefix]] memory for the full checklist.
- Installs go to **`/Applications/MyApplications/`**, not `/Applications` directly (自作アプリをまとめるため).
- Deletions always go to the Trash (`FileManager.trashItem`), never a hard delete — see myorganizer's キャッシュ掃除/アプリ削除 panes.
- Secrets/credentials go in Keychain, never committed to the repo — see mynetworth's SimpleFIN token handling.
- Each app ad-hoc signs on local build; there's no shared signing identity or notarization.

### Repo-wide
- Commit messages are in Japanese.

## Deployment

- **Web apps**: GitHub Pages from the `main` branch. No CI/CD — pushing to `main` deploys automatically. Nothing is deployed anywhere else (the world-cup-2026 Cloudflare Worker was removed along with the live-fetch pipeline).
- **Native macOS apps**: never deployed via GitHub Pages. Each is built and installed locally to `/Applications/MyApplications/` via `./install.sh`(mygallery のみ `./build.sh`。自作アプリはこのサブフォルダにまとめている). Re-run the install step after pulling changes to update the installed copy.

## Updating the Launcher

Applies to **web apps only** — native macOS tools are never added to the launcher. When adding/removing a web app, update root `index.html`:
1. Add an `<a class="app {name}">` entry to the single icon grid (category sections were removed — do not re-add them without asking).
2. Add a `.app.{name} .icon-wrap` CSS rule with a gradient background and box-shadow.
3. Use a `.new-badge` span for recently added apps.
