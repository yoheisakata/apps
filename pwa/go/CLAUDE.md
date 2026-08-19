# CLAUDE.md (go)

Single self-contained `index.html` (inline CSS + JS), no build step — same convention as the other GitHub-Pages web apps in this repo (see `shogi/` for the sibling app this was modeled on). Board/piece logic is entirely different from shogi (Go rules), but the code organization mirrors it: one IIFE, a clearly delimited engine section, an AI section, and a UI section.

## Structure

Everything lives in one `<script>` block in `index.html`:

- **Board model**: `board` is a flat `Array(size*size)` of `null` / `'b'` / `'w'`, indexed via `idx(size,r,c) = r*size+c`. `size` is 9 or 13 (chosen on the home screen, 9 is the default).
- **Engine section** (marked with `ENGINE START` / `ENGINE END` comments in `index.html` so it can be mechanically extracted for testing — see Testing below): pure functions with no DOM dependency —
  - `getGroup(board,size,r,c)` — flood-fills the connected same-color group from a point and returns its stones + liberty count.
  - `attemptMove(board,size,r,c,color,koBoardStr)` — the single entry point for legality + effects. Non-destructive: returns `{legal:false,reason}` or `{legal:true,board,captured}` without mutating the input board. Order of operations: (1) reject occupied/out-of-bounds, (2) place the stone on a cloned board, (3) remove any adjacent opponent groups now at 0 liberties (capture), (4) check the mover's own group's liberties on the post-capture board — 0 liberties here is `suicide` and rejected, (5) compare the resulting board string against `koBoardStr` — an exact match is a `ko` violation and rejected.
  - `computeArea(board,size)` — Chinese-rules area scoring: flood-fills each empty region, and credits it to a color only if every bordering stone color is uniform (otherwise it's neutral `dame`).
- **AI section**: `chooseAiMove(state,color,difficulty)` calls `collectAiCandidates` (every legal empty point scored by `scoreCandidateMove`) and picks from the top-scoring pool with a random slack window whose size depends on difficulty (1=やさしい widest slack, 3=つよい narrowest). `scoreCandidateMove` weighs: captures (dominant weight, so the bot never "forgets" a free capture), post-move liberties, self-atari avoidance (unless it's a capturing move), not filling one's own fully-enclosed eye, putting opponent groups in atari/near-atari, proximity to existing stones, a small edge-of-board penalty, and a small star-point bonus.
- **UI section**: `app` holds mutable UI state (`state` = the game state object `{board,size,history,captures,lastActionWasPass}`, `turn`, `mode`, `humanSide`, `aiDifficulty`, `lastMove`, `koPoint` for the ko-marker display, `passCount`, `gameOver`). `render()` re-draws the board/status/turn-indicator from `app` on every state change (no diffing, same as shogi's approach — boards are small enough that full re-render is cheap).

## Known simplifications (intentional, not bugs)

- **Simple ko only, not positional superko.** `state.history` is an array of board-string snapshots; on each move the candidate resulting board is compared only against `history[history.length-2]` (the position immediately before the opponent's last move). This correctly blocks the classic single-stone immediate-recapture ko shape, but does **not** detect longer cyclic repetitions (e.g. multi-stone repeating cycles, or "returning" to a position from several moves further back via a different move order). Real Go superko rules (positional or situational) would require comparing against the *entire* history, not just one snapshot back.
- **Chinese-rules area scoring, not Japanese territory scoring.** Score = stones-on-board + surrounded-empty-territory (`computeArea`). This was chosen over Japanese rules specifically because it's robust without dead-stone negotiation: a purely mechanical flood-fill at double-pass gives a well-defined score, whereas Japanese territory scoring (territory only, stones not counted, but *dead* stones must first be identified and removed by agreement) needs a scoring-phase UI this app does not have.
- **No dead-stone marking/removal.** At double-pass, whatever is physically on the board is scored as alive. If a player passes while a clearly-dead group is still sitting on the board, it counts as living stones/eye space for its owner — same simplification real area-scoring implementations without a negotiation phase make. Players are expected to actually capture dead groups before passing (the board is small enough — 9x9/13x13 — that this is normally practical).
- **Heuristic AI, not a real Go engine.** `chooseAiMove`/`scoreCandidateMove` is a hand-tuned local-scoring heuristic with no search/lookahead, no pattern database, and no MCTS/neural net (a real Go engine strong enough to matter is far out of scope for a casual single-file web app). It reliably takes free captures and avoids obvious self-atari, but has no concept of life-and-death, influence, or multi-move tactics/ladders — it can and will misread larger fights and semeai. Verified via simulated AI-vs-AI games (see Testing) that it plays a full game to completion without crashing and produces a mechanically sane score, not that its moves are strong.
- No move history/kifu export, no undo (use 「やりなおす」 to restart instead), no handicap stones.

If any of these get implemented later (e.g. positional superko, a dead-stone negotiation phase, a stronger AI), update this file and the README's ルール実装メモ section.

## Testing

The engine has no automated test file in the repo (this repo has no test infrastructure — see root `CLAUDE.md`: "There are no tests anywhere in this repo"), but it was verified during development by extracting the code between the `ENGINE START`/`ENGINE END` markers (plus the AI section) out of `index.html` into a temporary Node module and running scripted checks:

1. Placing stones to surround and capture a single stone — verified the stone is removed and the resulting board is correct.
2. Placing stones to surround and capture a 3-stone L-shaped group — verified the whole group (not just part of it) is removed.
3. Attempting a suicide move (playing into a fully-enclosed point that leaves the mover's own group at 0 liberties) — verified it's rejected with `reason:'suicide'`, distinguishing it from the case where the same point captures an opponent group first (which is legal).
4. A classic single-stone ko shape — verified the immediate recapture that would recreate the position from two plies back is rejected with `reason:'ko'`, and that the same recapture is accepted when no ko constraint applies.
5. A full random-move game simulated to double-pass (with an escalating pass probability so it terminates) — verified no exceptions, `computeArea`'s three buckets (black score + white score + dame) always sum to exactly `size*size`, and scores are non-negative. Separately, several full **AI-vs-AI** games (`chooseAiMove` on both sides, sizes 9 and 13, all difficulty combinations) were run to double-pass — all completed without throwing and produced mechanically consistent scores. Note: because the heuristic bot has no lookahead, AI-vs-AI games at low/medium difficulty frequently end in one side capturing effectively the whole board rather than a close split — this is expected weak-bot behavior (see the AI simplification note above), not a scoring or capture-logic bug; the same capture/suicide/ko unit checks (1–4) pass identically against the code extracted from the shipped `index.html`.

If you touch the engine section, re-extract and re-run an equivalent check before shipping — the failure modes that matter most are (a) a group that should have 0 liberties not being detected/captured, and (b) a multi-stone group being only partially removed.

## Versioning

Per the repo-wide convention (see root `CLAUDE.md`), bump `.app-version` in `index.html` on every change to this app (patch for fixes, minor for features).
