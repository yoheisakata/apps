# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A collection of mobile-friendly web apps ("アプリひろば") hosted on GitHub Pages. The root `index.html` is the launcher/home screen, organizing apps into sections (ゲーム / ツール / まなぶ). All UI is in Japanese.

## Architecture

Most apps are **single self-contained HTML files** (inline CSS + JS) in their own directory — no build step, no dependencies, no frameworks. Open any `index.html` directly in a browser to develop. Exceptions:

- **world-cup-2026/** — Multi-file vanilla app: `index.html` + `main.js` + ES-module views in `views/` + `style.css`, with static datasets in `data/*.json`. No build step. A **Cloudflare Worker** (`worker/worker.js`, deployed via `worker/wrangler.toml`) proxies the Football-Data.org API: it allow-lists specific paths and uses the Cloudflare Cache API to stay under upstream rate limits.
- **learn-postgresql/** — A **prebuilt Vite bundle** (hashed files in `assets/`, including pglite WASM). The repo holds the build output only; runs Postgres in-browser via WASM.
- **receipt/** — Single HTML file integrating **Firebase Auth + Firestore** for cloud sync. Users supply their own Firebase config at runtime (stored in localStorage).
- **tcpip/** — Single-file interactive TCP/IP simulator (handshake + encapsulation/decapsulation visualization).

Static single-file apps: `tashizan` (たしざんクエスト), `kakeizan` (かけざんクエスト/九九), `earth`, `tetris`, `tarot`, `shinkansen`.

## Build / Dev Commands

Most apps need no build — open the HTML file in a browser. There are no tests.

### world-cup-2026 Cloudflare Worker

```bash
cd world-cup-2026/worker
npx wrangler dev      # Run the proxy locally
npx wrangler deploy   # Deploy to Cloudflare
```

The Worker requires a `FOOTBALL_DATA_API_KEY` (configure as a Worker secret / in `wrangler.toml` env).

### learn-postgresql

The committed `assets/` are build output. Rebuild only from the upstream Vite source (not in this repo).

## Conventions

- Commit messages are in Japanese.
- Apps use the Nunito font (Google Fonts), dark gradient themes, and CSS custom properties for colors.
- Mobile-first: `viewport` meta with `user-scalable=no`, touch-optimized interactions.
- State persistence via `localStorage` (tashizan, kakeizan save game progress).
- Icons are emoji or inline SVG data URIs — no external image assets.
- world-cup-2026 uses cache-buster version constants; bump them when changing cached behavior.

## Deployment

GitHub Pages from the `main` branch. No CI/CD — pushing to `main` deploys automatically. (The world-cup-2026 Worker is the only piece deployed separately, via Wrangler.)

## Updating the Launcher

When adding/removing an app, update root `index.html`:
1. Add an `<a class="app {name}">` entry in the appropriate section (ゲーム, ツール, or まなぶ).
2. Add a `.app.{name} .icon-wrap` CSS rule with a gradient background and box-shadow.
3. Use a `.new-badge` span for recently added apps.
