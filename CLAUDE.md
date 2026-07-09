# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This repo has two distinct kinds of projects:

1. **Web apps** ("アプリひろば") hosted on GitHub Pages — mobile-friendly, all-Japanese UI. The root `index.html` is the launcher/home screen, organizing apps into sections (ゲーム / ツール / まなぶ).
2. **Native macOS/iOS tools** (`cleanmac/`, `networth/`, `renamer/`, `youtube-dl-mac/`, `KidsVideoMaker/`, `kindle-transfer/`, `utilities/`) — personal-use local tools, built and run outside GitHub Pages, **not** referenced from the root `index.html`.

When editing, check which category a folder belongs to before assuming GitHub-Pages-style conventions (single HTML file, no build) apply.

## Architecture

### Web apps (deployed to GitHub Pages)

Most are **single self-contained HTML files** (inline CSS + JS) in their own directory — no build step, no dependencies, no frameworks. Open any `index.html` directly in a browser to develop. Exceptions:

- **world-cup-2026/** — Multi-file vanilla app: `index.html` + `main.js` + ES-module views in `views/` + `style.css`, with static datasets in `data/*.json`. No build step. A **Cloudflare Worker** (`worker/worker.js`, deployed via `worker/wrangler.toml`) proxies the Football-Data.org API: it allow-lists specific paths and uses the Cloudflare Cache API to stay under upstream rate limits.
- **receipt/** — Single HTML file integrating **Firebase Auth + Firestore** for cloud sync. Users supply their own Firebase config at runtime (stored in localStorage).
- **tcpip/** — Single-file interactive TCP/IP simulator (handshake + encapsulation/decapsulation visualization).

Static single-file apps: `tashizan` (たしざんクエスト), `kakeizan` (かけざんクエスト/九九), `earth`, `tarot`, `shinkansen`.

> `learn-postgresql/` (pglite/WASM SQL lab) was removed from the repo; do not re-add references to it unless the folder comes back.

### Native macOS/iOS tools (not deployed to GitHub Pages)

- **cleanmac/**, **networth/**, **renamer/**, **youtube-dl-mac/** — SwiftUI apps built with **Swift Package Manager** (`Package.swift`, `Sources/`). Same conventions across all four: `make-icon.swift` generates `AppIcon.icns`/`AppIcon.iconset/`, `build_app.sh` (or `build.sh`) produces a local `.app` bundle, `install.sh` builds + ad-hoc signs + copies to `/Applications`. No App Store distribution, no CI — rebuild locally via `install.sh` to update.
  - `networth/` also has a `--fetch` CLI mode for headless data collection and a `com.yoheisakata.networth-fetch.plist` LaunchAgent for scheduled runs (see [[networth-tracker]] memory for operational details).
- **KidsVideoMaker/** — SwiftUI app as a full **Xcode project** (`.xcodeproj`), not SPM. Build/run via Xcode.
- **kindle-transfer/** — Single Bash script (`kindle-transfer.sh`), no build. Uses `adb` to pull files from a Kindle Fire's SD card/internal storage over USB.
- **utilities/** — Standalone Python 3 / Bash scripts (not a packaged app) for a personal photo/video pipeline: backup organization (`backup-photos.sh`, `backup-videos.sh`, `sync-backups.sh`, `verify-photos.sh`), H.265 re-encoding (`encode_h265.py`), short-clip detection (`find_short_videos.py`), and kids'-video compilation (`create_memory_video.py`, `kids_video_maker.py`). Run individually from the CLI; no shared entry point.

## Build / Dev Commands

Web apps need no build — open the HTML file in a browser. There are no tests anywhere in this repo.

### world-cup-2026 Cloudflare Worker

```bash
cd world-cup-2026/worker
npx wrangler dev      # Run the proxy locally
npx wrangler deploy   # Deploy to Cloudflare
```

The Worker requires a `FOOTBALL_DATA_API_KEY` (configure as a Worker secret / in `wrangler.toml` env).

### SwiftUI/SPM native apps (cleanmac, networth, renamer, youtube-dl-mac)

```bash
cd <app>
swift run          # dev build, launches a window
./build_app.sh      # or ./build.sh for renamer — builds a local .app bundle
./install.sh        # build + ad-hoc sign + install to /Applications (use this to update)
```

### KidsVideoMaker

Open `KidsVideoMaker/KidsVideoMaker.xcodeproj` in Xcode and build/run from there.

## Conventions

### Web apps
- Apps use the Nunito font (Google Fonts), dark gradient themes, and CSS custom properties for colors.
- Mobile-first: `viewport` meta with `user-scalable=no`, touch-optimized interactions.
- State persistence via `localStorage` (tashizan, kakeizan save game progress).
- Icons are emoji or inline SVG data URIs — no external image assets.
- world-cup-2026 uses cache-buster version constants; bump them when changing cached behavior.

### Native macOS apps
- Deletions always go to the Trash (`FileManager.trashItem`), never a hard delete — see cleanmac.
- Secrets/credentials go in Keychain, never committed to the repo — see networth's SimpleFIN token handling.
- Each app ad-hoc signs on local build; there's no shared signing identity or notarization.

### Repo-wide
- Commit messages are in Japanese.

## Deployment

- **Web apps**: GitHub Pages from the `main` branch. No CI/CD — pushing to `main` deploys automatically. The world-cup-2026 Worker is the only piece deployed separately, via Wrangler.
- **Native macOS apps**: never deployed via GitHub Pages. Each is built and installed locally to `/Applications` via its own `install.sh` (or Xcode, for KidsVideoMaker). Re-run `install.sh` after pulling changes to update the installed copy.

## Updating the Launcher

Applies to **web apps only** — native macOS tools are never added to the launcher. When adding/removing a web app, update root `index.html`:
1. Add an `<a class="app {name}">` entry in the appropriate section (ゲーム, ツール, or まなぶ).
2. Add a `.app.{name} .icon-wrap` CSS rule with a gradient background and box-shadow.
3. Use a `.new-badge` span for recently added apps.
