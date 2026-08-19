# CLAUDE.md (shogi)

Single self-contained `index.html` (inline CSS + JS), no build step — same convention as the other GitHub-Pages web apps in this repo. Not related to `mygames/`'s native ボードゲーム tab (which has its own separate Swift implementation of 将棋 and other games); this is a from-scratch web port with its own rules engine and AI, kept intentionally independent.

## Structure

Everything lives in one `<script>` block in `index.html`:

- **Board/piece model**: `board[r][c]` is `null` or `{type, owner}`. `owner` is `'b'` (先手) or `'w'` (後手). `type` is a 2-letter code (`FU`,`KY`,`KE`,`GI`,`KI`,`KA`,`HI`,`OU` and their promoted forms `TO`,`NY`,`NK`,`NG`,`UM`,`RY`). `hands[owner][baseType]` holds captured-piece counts.
- **Move generation**: `pseudoMovesFrom` computes unfiltered moves per piece type/direction; `generateLegalMoves` filters out moves that leave the mover's own king in check (by cloning state and calling `isInCheck`), and adds drop moves (with 二歩/行き所のない駒 restrictions).
- **Promotion**: `mustPromote` (forced — pawn/lance on the far rank, knight on the far two ranks) vs `canPromoteMove` (optional — piece moves into/out of the promotion zone). The UI shows a 成る/成らない modal only for the optional case.
- **AI**: `pickAiMove` + `negamax` — plain material-based evaluation (`PIECE_VALUE` + a small center-control bonus), alpha-beta pruning, capture-first move ordering. Search depth is capped at 1–2 plies (`app.aiDepth`, set by difficulty) — legal move generation clones the whole board+hands per candidate to check king safety, so it's too expensive to search deeper without a real perft/undo-move optimization. Difficulty also varies `app.aiSlack` (how far below the best score a move can be and still be picked randomly) rather than depth alone, so "easy" isn't just a shallower search but also a less consistent one.

## Known simplifications (intentional, not bugs)

- 打ち歩詰め (illegal to deliver checkmate by dropping a pawn) is **not** enforced — dropping a pawn for mate is allowed here even though it's illegal in real shogi.
- 千日手 (repetition draw) is **not** detected.
- No handicap (駒落ち) modes, no game save/resume, no move history/kifu export.

If any of these get implemented later, update this file and the README's ルール実装メモ section.

## Versioning

Per the repo-wide convention (see root `CLAUDE.md`), bump `.app-version` in `index.html` on every change to this app (patch for fixes, minor for features).
