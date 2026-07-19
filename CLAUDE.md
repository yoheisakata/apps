# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo has two distinct kinds of projects:

1. **Web apps** ("My Apps" — 旧アプリひろば) hosted on GitHub Pages — mobile-friendly, all-Japanese UI. The root `index.html` is the launcher/home screen, a single flat icon grid (no category sections).
2. **Native macOS/iOS tools** (`cleanmac/`, `networth/`, `renamer/`, `youtube-dl-mac/`, `KidsVideoMaker/`, `kindle-transfer/`, `utilities/`) — personal-use local tools, built and run outside GitHub Pages, **not** referenced from the root `index.html`.

When editing, check which category a folder belongs to before assuming GitHub-Pages-style conventions (single HTML file, no build) apply.

Each app directory has its own `README.md` (user-facing, Japanese) and `CLAUDE.md` (dev guidance) — read the app's own docs before making changes there, and update them when behavior changes.

## Architecture

### Web apps (deployed to GitHub Pages)

Most are **single self-contained HTML files** (inline CSS + JS) in their own directory — no build step, no dependencies, no frameworks. Open any `index.html` directly in a browser to develop. Exceptions:

- **world-cup-2026/** — Multi-file vanilla app: `index.html` + `main.js` + ES-module views in `views/` + `style.css`, with static datasets in `data/*.json`. No build step. The tournament ended 2026-07-19 (final: Spain 1-0 Argentina) — the app is now a fully static archive; all 104 match results are baked into `data/*.json`. The old live-fetch pipeline (Wikipedia + openfootball fallback, a Cloudflare Worker proxying FIFA rankings) was removed — do not reintroduce it.
- **tcpip/** — Single-file interactive TCP/IP simulator (handshake + encapsulation/decapsulation visualization).

Static single-file apps: `sansu` (さんすうれんしゅう — 旧 `tashizan`/`kakeizan` を統合した、ゲーム要素なしの たしざん + 九九 学習アプリ), `earth`, `tarot` (`index.html` 占い + `quiz.html` クイズ), `shinkansen`.

> `learn-postgresql/` (pglite/WASM SQL lab) and `receipt/` (Claude API + Firebase レシート web app; the user's Firebase account was deleted — receipt management now lives in networth's レシート tab) were removed from the repo; do not re-add references to them unless the folders come back.

### Native macOS/iOS tools (not deployed to GitHub Pages)

- **cleanmac/**, **networth/**, **omoide/**, **renamer/**, **youtube-dl-mac/** — SwiftUI apps built with **Swift Package Manager** (`Package.swift`, `Sources/`). Shared conventions: `make-icon.swift` generates `AppIcon.icns`/`AppIcon.iconset/`, a build script produces a local ad-hoc-signed `.app` bundle. No App Store distribution, no CI. Install/update scripts differ per app:
  - All apps: build script (bundle in place) + `./install.sh` (build + copy to `/Applications`).
  - cleanmac: `./build_app.sh` or `./install.sh`.
  - networth: `./build_app.sh` or `./install.sh`. `build_app.sh` reads `appVersion` from `Sources/NetWorth/Main.swift` (single source of truth) into Info.plist, and bundles `2026_Sakata_支出表.md` as the 固定収支 tab's fallback.
  - omoide: `./build_app.sh` or `./install.sh`.
  - renamer: `./build.sh` or `./install.sh`.
  - youtube-dl-mac: `./build-app.sh` (note the hyphen; outputs to `dist/`) or `./install.sh`.
- **networth/** specifics (v0.4.x, requires **macOS 26** via `Package.swift` — FoundationModels): tabs are メイン / 週 / 月 / 投資 / 固定収支 / レシート.
  - `--fetch` CLI mode for headless data collection; `com.yoheisakata.networth-fetch.plist` LaunchAgent runs it every morning (see [[networth-tracker]] memory for operational details).
  - 投資 tab overlays live quotes from Yahoo Finance's public chart API (`Quotes.swift`, no API key) on SimpleFIN's once-a-day holding values.
  - 固定収支 tab (`FixedBudget.swift`) renders `networth/2026_Sakata_支出表.md` with a minimal Markdown parser — it reads the repo file at `~/github/apps/networth/` directly (edit + 再読込 to update), falling back to the copy bundled at build time.
  - レシート tab (`Receipts.swift` + `ReceiptsTab.swift`) — Schedule C 向けレシート管理: Vision OCR + FoundationModels (on-device LLM) extraction; data lives in `~/Library/Application Support/Receipts/`. FoundationModels prompts must be in English (the model rejects prompts not matching the Apple Intelligence language setting). `ExpenseCategory` cases map to Schedule C Part II lines (8–27a) and their rawValues are persisted — never rename them.
- **kindle-transfer/** — Single Bash script (`kindle-transfer.sh`), no build. Uses `adb` to pull files from a Kindle Fire's SD card/internal storage over USB.
- **utilities/** — Standalone Python 3 / Bash scripts (not a packaged app) for a personal photo/video pipeline: backup organization (`backup-photos.sh`, `backup-videos.sh`, `sync-backups.sh`, `verify-photos.sh`), H.265 re-encoding (`encode_h265.py`), short-clip detection (`find_short_videos.py`), and kids'-video compilation (`create_memory_video.py`). Run individually from the CLI; no shared entry point.

## Build / Dev Commands

Web apps need no build — open the HTML file in a browser. There are no tests anywhere in this repo.

### world-cup-2026 Cloudflare Worker

```bash
cd world-cup-2026/worker
npx wrangler dev      # Run the proxy locally
npx wrangler deploy   # Deploy to Cloudflare
```

The Worker needs no API key or secrets (it only proxies the free FIFA rankings endpoint).

### SwiftUI/SPM native apps (cleanmac, networth, omoide, renamer, youtube-dl-mac)

```bash
cd <app>
swift build         # compile check (verification method — see below)
# Build the .app bundle (script name varies):
./build_app.sh      # cleanmac, networth, omoide
./build-app.sh      # renamer
./build-app.sh      # youtube-dl-mac (outputs to dist/)
# Install/update in /Applications:
./install.sh        # all apps (build + copy to /Applications)
```

**GUI アプリを起動しないこと**: `swift run`・`open <App>.app`・`.build/debug/<App>` の直接実行など、ウィンドウが開く形での目視確認は禁止(permissions の deny ルールでもブロック済み)。検証は `swift build` のコンパイル確認まで。アプリの起動・目視確認はユーザー自身が行う。例外: `NetWorth --fetch` のようなヘッドレス CLI モードは実行してよい。

## Conventions

### Web apps
- Dark gradient themes and CSS custom properties for colors; several apps (sansu, tcpip) use the Nunito font (Google Fonts).
- Mobile-first: `viewport` meta with `user-scalable=no`, touch-optimized interactions.
- State persistence via `localStorage` where it matters: world-cup-2026 caches live data + theme. sansu does **not** save progress (`localStorage` 不使用).
- Icons are emoji or inline SVG data URIs — no external image assets.
- world-cup-2026 has three version knobs to bump on release: `?v=N` cache-busters on JS/CSS imports, `APP_VERSION` in `main.js` (shown in the header), and `LIVE_CACHE_KEY` (bump only when the cached live-data shape changes; add the old key to the cleanup list).

### Native macOS apps
- Deletions always go to the Trash (`FileManager.trashItem`), never a hard delete — see cleanmac.
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
