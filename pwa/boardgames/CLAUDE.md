# CLAUDE.md (boardgames)

`index.html` here is only a **picker/launcher screen** — a home-screen grid of links to the 7 board-game apps, which live as subfolders of this directory: `shogi/`, `chess/`, `go/`, `othello/`, `gomoku/`, `mahjong/`, `diamond-game/`. Unlike `cardgames/`, this is not a merged single-file app: each board game keeps its own subdirectory, its own `index.html`, its own CSS theme, AI, and rules engine, completely unchanged — only the folder location moved (from `pwa/<name>/` to `pwa/boardgames/<name>/`) and the relative links were updated accordingly. This picker exists purely so the root launcher (`index.html`) only needs one tile ("ボードゲーム") instead of seven, mirroring how `cardgames/` groups multiple card games behind one home-screen tile — but here the grouping is navigational (plain links to sibling folders), not a code merge, because these games are large, independent, from-scratch rule engines (see each game's own `CLAUDE.md`/`README.md`, which stayed with their folder in the move) where merging into one file would be high-risk for no real benefit.

Each game's own `index.html` has a `← ボードゲーム一覧へ` link back to `../` (this picker, its immediate parent) — not to the root `My Apps` launcher directly. This picker's own `← My Apps` link goes to `../../` (root).

## Adding a new board game

1. Build it as its own self-contained `pwa/boardgames/<name>/index.html`, same conventions as the existing 7 (dark theme, `.home-link` back to `../`, `.app-version`).
2. Add a `.game-link` entry to this file's `#home` grid (relative href `<name>/`, no `../` — the game folders are direct children of this directory).
3. Do **not** add it to the root `index.html` grid — only this picker links to individual board games now.

## Versioning

Bump `.app-version` here when the picker screen itself changes (adding/removing/reordering games, restyling). Each individual game keeps its own separate version, bumped independently when that game's own file changes.
