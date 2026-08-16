# CLAUDE.md (othello)

Single self-contained `index.html` (inline CSS + JS), no build step — same convention as the other GitHub-Pages web apps in this repo. Not related to `mygames/`'s native ボードゲーム tab (which does not currently include Othello); this is a from-scratch web port with its own rules engine and AI, kept intentionally independent (same pattern as `shogi/`).

## Structure

Everything lives in one `<script>` block in `index.html`:

- **Board model**: `board[r][c]` is `null`, `'b'` (黒), or `'w'` (白). 8x8, 0-indexed. Initial setup: `board[3][3]='w'`, `board[3][4]='b'`, `board[4][3]='b'`, `board[4][4]='w'` (standard Othello starting position), black moves first.
- **Move generation**: `flipsForMove(board, r, c, player)` scans all 8 directions from an empty cell; for each direction it walks over a contiguous run of opponent discs and, only if that run is terminated by one of the player's own discs (not the edge or another empty cell), appends that run to the flip list. `legalMoves` collects every empty cell where `flipsForMove` returns a non-empty list.
- **Applying a move**: `applyMove` sets the target cell and flips every cell in `move.flips` to the mover's color. Total disc count therefore always increases by exactly 1 per move (flips only change ownership, never count) — verified by test.
- **Turn advancement / passing**: `advanceTurn` checks the *next* player's legal moves first; if empty, it checks whether the player who just moved still has a move (auto-pass with a message) rather than ending immediately. The game only ends when neither side has any legal move (checked in sequence, not simultaneously computed) — this correctly handles the standard "pass propagates until someone can move, or both are stuck" rule.
- **AI**: `pickAiMove` + `minimax` — alpha-beta pruning, node evaluation via `evaluate()`. Unlike shogi (material-based), Othello's evaluation is positional-weight-based (`WEIGHTS` table: corners +120, cells adjacent-to-empty-corners -20/-40, edges +20, interior small positive) plus a mobility term (legal-move-count difference) plus a disc-count difference whose weight increases sharply once the board has fewer than 12 empty cells (endgame favors raw disc count; midgame favors position/mobility, since disc count is not purely additive/predictive early on). `minimax` handles passes by recursing to the opponent at the same depth (not decrementing search depth) so a forced pass doesn't waste a ply of lookahead. Difficulty varies both search depth (1/3/5 plies) and `aiSlack` (how far below the best score a move can be and still be picked randomly among near-best candidates).

## Known simplifications (intentional, not bugs)

- No move history, no undo, no game save/resume.
- No opening book or endgame solver — search is a plain fixed-depth alpha-beta minimax the whole game, so late-game play at "つよい" is strong but not perfect/exhaustive.
- No hint system beyond highlighting legal-move cells (no "best move" suggestion for the human).

If any of these get implemented later, update this file and the README's ルール実装メモ section.

## Testing notes

The move-generation (`flipsForMove`/`legalMoves`) and flip-application (`applyMove`) logic was verified by extracting the pure engine functions into a standalone Node.js module and running it against: the four known-correct standard opening moves and their single flips, a known correct white response set to one specific opening move, a synthetic 4-direction simultaneous-flip position, occupied-cell rejection, a fully-blocked-position pass scenario, several full AI-vs-AI simulated games (both fixed-move and randomized-AI-depth) that all terminated cleanly with sane final disc totals, and a full-game disc-count-conservation invariant (total discs increases by exactly 1 every move). All checks passed.

## Versioning

Per the repo-wide convention (see root `CLAUDE.md`), bump `.app-version` in `index.html` on every change to this app (patch for fixes, minor for features).
