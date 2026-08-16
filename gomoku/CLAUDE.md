# CLAUDE.md (gomoku)

Single self-contained `index.html` (inline CSS + JS), no build step — same convention as the other GitHub-Pages web apps in this repo. Not related to `mygames/`'s native ボードゲーム tab (which has its own separate Swift implementations of 五目並べ-adjacent games); this is a from-scratch web port with its own rules engine and AI, kept intentionally independent. Structured after `shogi/index.html` (home screen → game screen, dark theme, result modal) but the board/game logic is completely different — Gomoku has no pieces, no captures, no promotion, just stones on a 15×15 intersection grid.

## Structure

Everything lives in one `<script>` block in `index.html`:

- **Board model**: `board[r][c]` is `null`, `'b'` (黒/先手), or `'w'` (白/後手). `SIZE = 15`. Stones sit on line **intersections**, not inside cells — the CSS draws each `.point` as a 15×15 grid cell with pseudo-element line segments through its center (`::before` horizontal, `::after` vertical), shortened to a half-segment on the four board edges (`.edge-l/-r/-t/-b`) so lines don't run past the board boundary. This is the standard way to fake a Go/Gomoku-style line board with plain CSS grid instead of an actual `<table>` of intersections.
- **Win detection**: `checkWin(board, r, c, player)` — called immediately after placing a stone at `(r,c)`. For each of the 4 line directions (`DIRS = [[0,1],[1,0],[1,1],[1,-1]]`, i.e. horizontal/vertical/both diagonals), it walks outward from `(r,c)` in both the positive and negative direction counting consecutive same-player stones, and wins if the total (including the placed stone itself) is `>= 5`. **Overlines (6+) count as a win** — this app uses freestyle rules, not 連珠(renju) rules, so there's no 長連 restriction and no forbidden-move (三三/四四) logic for black. If renju-style restrictions are ever wanted, they'd need to be added as extra move-legality checks before `placeStone` commits, and this file + the README's ルール実装メモ should be updated.
- **Draw**: `isBoardFull` — game ends in a draw if no winner and every intersection is filled.
- **AI** (`pickAiMove`): a 3-stage heuristic, not a from-scratch deep search (a full-depth minimax over a 15×15 board is impractical in-browser):
  1. `findImmediateWin` — if the AI has any move that completes 5-in-a-row right now, take it unconditionally.
  2. Otherwise check if the human has an immediate winning move next turn; block it (weighted by difficulty via `blockBias` — lower difficulty sometimes "misses" the block on purpose so it isn't unbeatable-by-omission).
  3. Otherwise score candidate moves with `evaluateBoard`/`negamax`. `evaluateBoard` sums, per stone on the board, a per-direction "shape score" (`shapeValue(len, openEnds)`) based on the length of the unbroken run that stone starts and how many ends are open — an open three or a four with an open end score much higher than a blocked equivalent. `negamax` adds shallow alpha-beta lookahead (0/1/2 plies depending on difficulty) on top of that static evaluation.
  - Candidate moves are never the full empty board — `generateCandidates` only considers empty intersections within a radius-2 box of an existing stone (or board center on an empty board), and `negamax`/`pickAiMove` further cap the branching factor to the top ~12–24 candidates by a cheap line-length pre-score (`quickScore`) before running the (relatively) expensive `evaluateBoard`/recursive search on them. This keeps every AI move well under a second in-browser even at the "つよい" (depth-2) setting.
  - Difficulty (`app.difficulty`, 1/2/3) tunes three things at once: search depth (0/1/2 plies), `slack` (how far below the best-scored move a candidate can be and still be randomly picked — higher slack = weaker/more erratic), and `blockBias` (probability of actually taking an available block). This mirrors shogi's `aiSlack` approach to difficulty (randomized near-optimal choice rather than a single deterministic "best" move).

## Win-detection testing

`checkWin` was extracted verbatim and exercised with a standalone Node script (not checked into this repo — it lived in the session scratchpad) covering: horizontal/vertical/both diagonal 5-in-a-rows, wins detected regardless of which stone in the line is queried, edge-of-board cases where a run sits flush against row 0/row 14/column 14/a corner (must not falsely win and must not throw from an out-of-bounds read), a gap breaking a run, an opponent stone blocking a run, overline (6-in-a-row) counting as a win, and a simulated move sequence confirming the win is flagged the instant the 5th stone is placed, not one move later. All cases passed. If `checkWin` or `DIRS` is ever edited, re-derive a similar throwaway test rather than trusting a manual read — off-by-one errors in the forward/backward walk or in the edge `.edge-*` CSS are the most likely place for bugs in this app.

## Known simplifications (intentional, not bugs)

- No 連珠(renju) forbidden-move rules for black (三三・四四・長連 restrictions) — pure freestyle Gomoku, symmetric rules for both colors.
- No swap2/pie-rule opening balancing (first-move advantage is not compensated).
- No game save/resume, no move history/kifu export, no undo.
- AI does not use a transposition table or iterative deepening — the shallow fixed-depth negamax plus a hard candidate-count cap is sufficient at this board size/branching factor without them.

If any of these get implemented later, update this file and the README's ルール実装メモ section.

## Versioning

Per the repo-wide convention (see root `CLAUDE.md`), bump `.app-version` in `index.html` on every change to this app (patch for fixes, minor for features).
