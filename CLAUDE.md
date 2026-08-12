# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo has two distinct kinds of projects:

1. **Web apps** ("My Apps" — 旧アプリひろば) hosted on GitHub Pages — mobile-friendly, all-Japanese UI. The root `index.html` is the launcher/home screen, a single flat icon grid (no category sections).
2. **Native macOS/iOS tools** (`networth/`, `organizer/`, `downloader/`, `musicplayer/`, `mytube/`, `kindle-transfer/`, `utilities/`) — personal-use local tools, built and run outside GitHub Pages, **not** referenced from the root `index.html`.

When editing, check which category a folder belongs to before assuming GitHub-Pages-style conventions (single HTML file, no build) apply.

Each app directory has its own `README.md` (user-facing, Japanese) and `CLAUDE.md` (dev guidance) — read the app's own docs before making changes there, and update them when behavior changes.

## Architecture

### Web apps (deployed to GitHub Pages)

Most are **single self-contained HTML files** (inline CSS + JS) in their own directory — no build step, no dependencies, no frameworks. Open any `index.html` directly in a browser to develop. Exceptions:

- **world-cup-2026/** — Multi-file vanilla app: `index.html` + `main.js` + ES-module views in `views/` + `style.css`, with static datasets in `data/*.json`. No build step. The tournament ended 2026-07-19 (final: Spain 1-0 Argentina) — the app is now a fully static archive; all 104 match results are baked into `data/*.json`. The old live-fetch pipeline (Wikipedia + openfootball fallback, a Cloudflare Worker proxying FIFA rankings) was removed — do not reintroduce it.
- **kids-learning-app/** — Multi-file vanilla app (「まなびアプリ」): `index.html` + `app.js` + `style.css` + `manifest.json` + `sw.js` (installable PWA with offline cache — bump `CACHE_NAME` in `sw.js` whenever cached assets change). Covers たしざん (leveled, 5 levels), くく/かけざん (speech-read multiplication tables via `speechSynthesis`), ひらがな, and ローマ字タイピング, with a shared star (`localStorage`) + sound-effect reward system across all modes. Absorbed the former standalone `sansu/` app (たしざん levels + 九九) — do not re-add `sansu/` as a separate app.

Static single-file apps: `earth`, `tarot` (`index.html` 占い + `quiz.html` クイズ), `shinkansen`, `pgquiz` (PostgreSQL 17以降向けのクイズ/フラッシュカード学習アプリ、104問・13カテゴリ).

> `learn-postgresql/` (pglite/WASM SQL lab) and `receipt/` (Claude API + Firebase レシート web app; the user's Firebase account was deleted — receipt management now lives in networth's レシート tab) were removed from the repo; do not re-add references to them unless the folders come back.

### Native macOS/iOS tools (not deployed to GitHub Pages)

- **networth/**, **organizer/**, **downloader/**, **musicplayer/**, **mytube/** — SwiftUI apps built with **Swift Package Manager** (`Package.swift`, `Sources/`). Shared conventions: `make-icon.swift` generates `AppIcon.icns`/`AppIcon.iconset/`, a build script produces a local ad-hoc-signed `.app` bundle. No App Store distribution, no CI. Install/update scripts differ per app:
  - All apps: build script (bundle in place) + `./install.sh` (build + copy to `/Applications`).
  - networth: `./build_app.sh` or `./install.sh`. `build_app.sh` reads `appVersion` from `Sources/NetWorth/Main.swift` (single source of truth) into Info.plist, and bundles `2026_Sakata_支出表.md` as the 固定収支 tab's fallback.
  - organizer: `./build_app.sh` or `./install.sh`.
  - downloader: `./build_app.sh` or `./install.sh`.
  - musicplayer: `./build_app.sh` or `./install.sh`.
  - mytube: `./build_app.sh` or `./install.sh`.
- **networth/** specifics (v0.4.x, requires **macOS 26** via `Package.swift` — FoundationModels): tabs are メイン / 週 / 月 / 投資 / 固定収支 / レシート.
  - `--fetch` CLI mode for headless data collection; `com.yoheisakata.networth-fetch.plist` LaunchAgent runs it every morning (see [[networth-tracker]] memory for operational details).
  - 投資 tab overlays live quotes from Yahoo Finance's public chart API (`Quotes.swift`, no API key) on SimpleFIN's once-a-day holding values.
  - 固定収支 tab (`FixedBudget.swift`) renders `networth/2026_Sakata_支出表.md` with a minimal Markdown parser — it reads the repo file at `~/github/apps/networth/` directly (edit + 再読込 to update), falling back to the copy bundled at build time.
  - レシート tab (`Receipts.swift` + `ReceiptsTab.swift`) — Schedule C 向けレシート管理: Vision OCR + FoundationModels (on-device LLM) extraction; data lives in `~/Library/Application Support/Receipts/`. FoundationModels prompts must be in English (the model rejects prompts not matching the Apple Intelligence language setting). `ExpenseCategory` cases map to Schedule C Part II lines (8–27a) and their rawValues are persisted — never rename them.
- **kindle-transfer/** — Single Bash script (`kindle-transfer.sh`), no build. Uses `adb` to pull files from a Kindle Fire's SD card/internal storage over USB.
- **utilities/** — Standalone Python 3 / Bash scripts (not a packaged app) for a personal photo/video pipeline: backup organization (`backup-photos.sh`, `backup-videos.sh`, `sync-backups.sh`, `verify-photos.sh`), H.265 re-encoding (`encode_h265.py`), short-clip detection (`find_short_videos.py`). Run individually from the CLI; no shared entry point.
- **organizer/** — GUI front-end covering all of `utilities/`'s functionality (写真整理/動画整理/エンコード/誤配置修正/同期/短い動画検索 in a sidebar) plus a dependency-check pane. Deliberately **reimplements** the scripts' logic natively in Swift rather than shelling out to `utilities/` — the two do not stay in sync automatically; see `organizer/CLAUDE.md`. External tools (`ffmpeg`/`ffprobe`/`rsync`/`sips`/`mdls`) are still invoked as subprocesses, not bundled. Also absorbed the former standalone `renamer/` app as its「リネーム」pane (rule-based batch renaming), the former standalone `cleanmac/` app as its「キャッシュ掃除」/「アプリ削除」panes (trash-only cache/app cleanup — the same `cleanmac/`-derived「重複写真」pane was later removed, see `organizer/CLAUDE.md`), and the former standalone `omoide/` app as its「まとめ動画」pane (clips a kids'-video folder into one movie with title cards + BGM via ffmpeg — see `organizer/CLAUDE.md`) — do not re-add `renamer/`, `cleanmac/`, or `omoide/` as separate apps.
- **downloader/** — Regular Dock-icon app (also keeps a menu-bar status item; closing the window doesn't quit the app — `NSApp.setActivationPolicy(.regular)` + `applicationShouldTerminateAfterLastWindowClosed == false`, no `LSUIElement`, no SwiftUI `WindowGroup`, since 2026-08-05) merging the former standalone `youtube-dl-mac` and `torrent-dl-mac` into one `TabView` ("YouTube" / "Torrent") — do not re-add either as a separate app. YouTube tab wraps `yt-dlp`/`ffmpeg` (single videos and — since 2026-08-05 — full playlists, downloaded into a per-playlist subfolder; a "ダウンロード名" field auto-fetches the title on paste and lets the user override it); Torrent tab wraps `aria2c` via its JSON-RPC interface rather than implementing BitTorrent itself (all three Homebrew, not bundled) — same "thin GUI over an existing CLI" approach throughout. Torrent defaults favor downloading over uploading (low upload-speed cap, seed-ratio/seed-time of 0 = stop seeding right after completion); speed limits apply live via `aria2.changeGlobalOption`, while seed-ratio/seed-time/download-dir are startup-only options requiring an engine restart. Registers the `magnet:` URL scheme so clicking a magnet link in a browser launches the app and starts the download (see `downloader/CLAUDE.md` for the Apple Event handling and metadata-GID pitfalls this uncovered).
- **musicplayer/** — Menu-bar-resident (`LSUIElement=true`, no Dock icon; closing the window doesn't quit or stop playback) mini music player: paste song links (YouTube, Suno, MusicCreator.ai, MusicGPT, or direct `.mp3` links) into a playlist — singly or bulk-imported one-per-line via a sheet that logs failures to `import-errors.log` — and play them back-to-back, with an optional shuffle mode. Same `AppDelegate`-owns-the-engines / `NSApplication.shared.run()` structure as downloader. YouTube links are extracted to a local mp3 cache via `yt-dlp`/`ffmpeg` (same "thin GUI over CLI" approach as downloader); the AI-song-sharing sites (Suno/MusicCreator.ai/MusicGPT) each embed a direct, publicly-fetchable mp3 URL in their server-rendered HTML (JSON blob or `og:audio` meta tag) — no headless browser or JS execution needed, just an `URLSession` HTML fetch + regex per site (see `musicplayer/CLAUDE.md` for the exact extraction patterns, a backslash-escaping gotcha in the Suno/MusicGPT JSON, and how to re-derive them if a site's markup changes).
- **mytube/** — Regular windowed app (standard SwiftUI `App`/`WindowGroup`, not menu-bar-resident like downloader/musicplayer — playback doesn't need to continue after the window closes). A local, read-only video player with a YouTube-like look: pick a folder, it's recursively scanned for video files, top-level subfolders become sidebar "channels," and a thumbnail grid (auto-generated + disk-cached frame per video, `~/Library/Caches/MyTube/thumbnails/`) serves as the home feed. Clicking a video opens a watch page (`AVKit.VideoPlayer`) with an "up next" list that autoplays sequentially. Remembers the last-picked folder (plain `UserDefaults` path string — no security-scoped bookmark needed since the app isn't sandboxed). See `mytube/CLAUDE.md` for the async thumbnail-cache design and a `WatchView` autoplay-closure-staleness pitfall.

## Build / Dev Commands

Web apps need no build — open the HTML file in a browser. There are no tests anywhere in this repo.

### world-cup-2026 Cloudflare Worker

```bash
cd world-cup-2026/worker
npx wrangler dev      # Run the proxy locally
npx wrangler deploy   # Deploy to Cloudflare
```

The Worker needs no API key or secrets (it only proxies the free FIFA rankings endpoint).

### SwiftUI/SPM native apps (networth, organizer, downloader)

```bash
cd <app>
swift build         # compile check (verification method — see below)
# Build the .app bundle:
./build_app.sh      # networth, organizer, downloader
# Install/update in /Applications:
./install.sh        # all apps (build + copy to /Applications)
```

**GUI アプリを起動しないこと**: `swift run`・`open <App>.app`・`.build/debug/<App>` の直接実行など、ウィンドウが開く形での目視確認は禁止(permissions の deny ルールでもブロック済み)。検証は `swift build` のコンパイル確認まで。アプリの起動・目視確認はユーザー自身が行う。例外: `NetWorth --fetch` のようなヘッドレス CLI モードは実行してよい。

## Conventions

### Web apps
- Dark gradient themes and CSS custom properties for colors; several apps (pgquiz) use the Nunito font (Google Fonts).
- Mobile-first: `viewport` meta with `user-scalable=no`, touch-optimized interactions.
- State persistence via `localStorage` where it matters: world-cup-2026 caches live data + theme; kids-learning-app persists a star count (`manabi-stars`).
- Icons are emoji or inline SVG data URIs — no external image assets.
- world-cup-2026 has three version knobs to bump on release: `?v=N` cache-busters on JS/CSS imports, `APP_VERSION` in `main.js` (shown in the header), and `LIVE_CACHE_KEY` (bump only when the cached live-data shape changes; add the old key to the cleanup list).

### Native macOS apps
- Deletions always go to the Trash (`FileManager.trashItem`), never a hard delete — see organizer's キャッシュ掃除/アプリ削除 panes.
- Secrets/credentials go in Keychain, never committed to the repo — see networth's SimpleFIN token handling.
- Each app ad-hoc signs on local build; there's no shared signing identity or notarization.

### Repo-wide
- Commit messages are in Japanese.

## Deployment

- **Web apps**: GitHub Pages from the `main` branch. No CI/CD — pushing to `main` deploys automatically. The world-cup-2026 Worker is the only piece deployed separately, via Wrangler.
- **Native macOS apps**: never deployed via GitHub Pages. Each is built and installed locally to `/Applications` via `./install.sh`. Re-run the install step after pulling changes to update the installed copy.

## Updating the Launcher

Applies to **web apps only** — native macOS tools are never added to the launcher. When adding/removing a web app, update root `index.html`:
1. Add an `<a class="app {name}">` entry to the single icon grid (category sections were removed — do not re-add them without asking).
2. Add a `.app.{name} .icon-wrap` CSS rule with a gradient background and box-shadow.
3. Use a `.new-badge` span for recently added apps.
