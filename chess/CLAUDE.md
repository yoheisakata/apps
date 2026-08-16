# CLAUDE.md (chess)

Single self-contained `index.html` (inline CSS + JS), no build step — same convention as the other GitHub-Pages web apps in this repo. Not related to `mygames/`'s native ボードゲーム tab (which has its own separate Swift implementations of other board games, not chess); this is a from-scratch web port with its own rules engine and AI, kept intentionally independent. Structurally modeled on `shogi/index.html` (same pseudoMovesFrom → generateLegalMoves → isSquareAttacked/isInCheck → cloneState-based negamax pipeline) but the piece-movement rules were rewritten from scratch for chess (castling, en passant, mandatory promotion with piece choice, no drops).

## Structure

Everything lives in one `<script>` block in `index.html`:

- **Board/piece model**: `board[r][c]` is `null` or `{type, owner}`. `owner` is `'w'` (White) or `'b'` (Black). `type` is one of `P,N,B,R,Q,K`. `row 0` is the 8th rank (Black's home side, top of the rendered board), `row 7` is the 1st rank (White's home side, bottom) — the board is never flipped in the data model; only rendering flips (see below). `state` also carries `castling` (`{wK,wQ,bK,bQ}` booleans), `enPassant` (`[r,c]` of the passable square, or `null`), and `halfmoveClock`/`fullmoveNumber` (tracked but not currently used for any draw rule — see Known simplifications).
- **Attacks vs moves**: `attacksFrom(board,r,c)` computes the squares a piece *attacks* (used only for check/castling-safety detection) as distinct from `pseudoMovesFrom(state,r,c)` which computes squares a piece can actually *move to* (used for move generation/UI). These differ specifically for pawns: a pawn attacks its two diagonal squares regardless of whether they're occupied, but can only *move* there by capturing (or via en passant); it never attacks its forward square. Conflating the two would break check detection near pawns.
- **Move generation**: `pseudoMovesFrom` emits unfiltered candidate moves per piece (including flags: `isDouble` for a pawn's 2-square opening move, which sets `enPassant`; `isEnPassant`; `isPromotion`; `isCastle: 'K'|'Q'`). Castling candidates are generated directly inside `pseudoMovesFrom` (via `addCastlingMoves`) with the full legality check already applied there — rights flag set, king not currently in check, squares between king and rook empty, and neither the transit square nor landing square attacked — because that "king must not pass through/land on an attacked square" condition is castling-specific and isn't caught by the generic "does this move leave my own king in check" filter that every other move goes through. `generateLegalMoves` then filters *all* pseudo moves (castling included) by cloning state, applying the move, and rejecting it if the mover's own king ends up in check — this is what catches pins and "moving into check" for every other piece type.
- **Promotion**: unlike shogi's optional 成る/成らない, chess promotion is *mandatory* when a pawn reaches the last rank — the choice is *which* piece (Q/R/B/N), not whether to promote. `generateLegalMoves` expands each `isPromotion` pseudo-move into 4 legal-move candidates (one per `PROMO_CHOICES`), each independently checked for king safety (in practice the four never differ in legality, since the promoted piece's own type can't affect whether the *mover's* king is left in check, but they're checked individually anyway for simplicity/symmetry with the rest of the pipeline). The UI's `selectSquare` groups same-destination moves together; `performMove` opens the promotion modal only when a destination has more than one grouped move.
- **AI**: `pickAiMove` + `negamax`, plain material evaluation (`PIECE_VALUE`) plus a small center-control bonus (`CENTER_BONUS` grid), alpha-beta pruning, capture-first move ordering (`orderMoves`/`moveCaptureValue`, which also accounts for promotion gain and en passant). Difficulty (`app.aiDepth`/`app.aiSlack`) is やさしい=depth 1/slack 400, ふつう=depth 2/slack 150, つよい=depth 3/slack 0 — one ply deeper at every tier than shogi's scheme, since chess has no drops (so move generation is cheaper per node) and empirical Node timing (`node test-timing.js` during development) showed depth-3 search from the opening position taking at most ~250ms and depth-4 spiking to ~1.5s on some positions — depth 3 was chosen as the "つよい" cap to stay safely inside a browser's per-move budget; depth 4 was measured but not shipped due to that spike.
- **Board orientation**: `app.flipped` is set when playing vs AI as Black, and `visToActual(vr,vc)` remaps the rendered row/column to actual board coordinates (the data model itself never flips — only `renderBoard`'s iteration order and the DOM `dataset.r/c` it writes, which round-trip through `onCellClick` unchanged).

## Testing

The engine was extracted into a temporary standalone Node module (not committed — pure engine functions only, no DOM) and exercised with `require()`-based test scripts during development:

- A full random-move game to completion (200-move cap) — no crash, `moves available when not over` held at every step.
- An AI-vs-AI game at depth 2 — completed in ~100 moves via checkmate, no crash.
- En passant: black double-steps a pawn next to a white pawn, white captures en passant; asserted the captured pawn is removed from its actual square (not the destination square) and the capturing pawn lands correctly.
- Castling: asserted both kingside and queenside castling are generated and correctly move both king and rook; asserted castling is correctly **disallowed** when (a) a transit square is attacked, (b) the king is currently in check, and (c) the castling-rights flag is already false.
- Promotion: asserted a pawn one step from the last rank generates exactly 4 legal moves (Q/R/B/N) and that applying the knight- and queen-promotion moves produces a knight/queen (not a pawn) on the board.
- Checkmate detection: replayed Fool's Mate (1.f3 e5 2.g4 Qh4#) and Scholar's Mate (1.e4 e5 2.Bc4 Nc6 3.Qh5 Nf6 4.Qxf7#) move-by-move through `generateLegalMoves`/`applyMove` and asserted `gameStatus` reports `checkmate` with the correct winner.
- Stalemate sanity: a hand-built King+Queen vs King stalemate position, asserted the side to move has no legal moves and is *not* in check, and `gameStatus` reports `stalemate` (draw, no winner).
- A byte-for-byte extraction of the engine code actually embedded in `index.html`'s `<script>` block was re-run against the entire test suite above before shipping, to catch any copy/paste drift between a scratch working copy and the final file.

If you touch the engine again, re-derive a throwaway copy of the `<script>` block's engine portion (everything above the `UI 状態管理` comment) into a Node-requirable module and rerun equivalent checks — there is no engine.js or test file checked into this directory (keeping with the "single self-contained index.html" convention), so nothing here runs automatically.

## Known simplifications (intentional, not bugs)

- **Threefold repetition** (draw by repeating the same position 3 times) is **not** detected.
- **The 50-move rule** is **not** enforced — `state.halfmoveClock` is tracked (reset on pawn moves/captures) but nothing currently reads it to offer or force a draw.
- **Insufficient material** draws (e.g. K vs K, K+B vs K) are **not** detected — such an endgame will just continue until stalemate or an actual mate, which in practice may never come.
- No move history / algebraic notation log, no PGN export, no undo (only "やりなおす" = full restart).
- No game save/resume across page reloads.

If any of these get implemented later, update this file and the README's ルール実装メモ section.

## Versioning

Per the repo-wide convention (see root `CLAUDE.md`), bump `.app-version` in `index.html` on every change to this app (patch for fixes, minor for features).
