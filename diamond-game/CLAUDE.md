# CLAUDE.md (diamond-game)

Single self-contained `index.html` (inline CSS + JS), no build step — same convention as the other GitHub-Pages web apps in this repo. `mygames/`'s native ボードゲーム tab already includes a Swift ダイヤモンドゲーム implementation (one of its 7 absorbed `boardgames` titles: 将棋・チェス・オセロ・囲碁・五目並べ・麻雀・ダイヤモンドゲーム); this web app is an independent, from-scratch port with its own cube-coordinate rules engine and AI — same "separate implementation, not shared code" pattern as the standalone `shogi/` web app vs. mygames's native 将棋.

## Coordinate system

Board holes are represented in **cube coordinates** `(x,y,z)` with the invariant `x+y+z=0` — the standard way to address a triangular/hex lattice without the distortion a square r/c grid would introduce. Adjacency is exactly the 6 unit vectors:

```
DIRS = [[1,-1,0],[1,0,-1],[0,1,-1],[-1,1,0],[-1,0,1],[0,-1,1]]
```

A hole is keyed as the string `"x,y,z"` in a plain object map (`board[key] = 'p1' | 'p2'`), so occupancy lookups are O(1) without needing a dense 2D array — convenient since the star shape is sparse inside its bounding box.

### Board shape (star / hexagram)

The classic 121-hole board is generated as the **union of two overlapping big triangles** in cube space (this is a clean closed-form derivation, verified by test — see below):

```
TriangleUp   = { (x,y,z) : x+y+z=0, x>=-n, y>=-n, z>=-n }
TriangleDown = { (x,y,z) : x+y+z=0, x<=n,  y<=n,  z<=n  }
n = 4
```

Their **intersection** is the central hexagon (61 holes for n=4, formula `3n²+3n+1`). Each triangle's excess beyond the hexagon forms 3 of the 6 points (10 holes each, a depth-4 triangular number `1+2+3+4`), so the union is hexagon + 6 points = 61 + 60 = 121 holes total, matching the physical board.

`pointLabel(x,y,z,n)` classifies which of the 6 points (if any) a cell belongs to by checking which single axis exceeds `+n` or `-n`: `'+x','-x','+y','-y','+z','-z'`. `OPPOSITE_POINT` maps each to the point directly across the board (`'+x'<->'-x'`, etc.) — this is what "opposite point" win-condition logic and the AI's progress axis both key off of.

### Screen projection

`cubeToPixel`-equivalent inline code (in the `画面座標への変換` section) projects `(x,y,z)` to 2D via three unit vectors 120° apart (`DIR_X`, `DIR_Y`, `DIR_Z` at 0°/120°/240°), then rotates 90° (`rx=-py, ry=px`) so the `+x`/`-x` point pair lands at the bottom/top of the viewBox instead of left/right — verified numerically (avg screen-Y of `+x` cells vs `-x` cells have opposite sign) before shipping. The whole board is precomputed once into `SHAPE.cells[i].sx/sy` (padded, scaled) and rendered as an SVG (not a CSS grid — a square grid can't represent this triangular-lattice star shape or its diagonal jump lines cleanly).

## Player-count support shipped

**2 players only**, occupying the opposite `+x` / `-x` point pair. The engine's cube-coordinate model and `SHAPE.points` generalize cleanly to all 6 points (3-way, 4-way, or 6-way variants are a straightforward extension — assign more of `SHAPE.points['+y']` etc. to additional players, and generalize `OPPOSITE_POINT` targeting for players not on a strict opposite pair), but only the 2-player case was implemented, per the task priority (get 2-player fully correct first). If 4-/6-player support is added later, update this section and the README.

Two modes, matching `shogi/`'s structure exactly:
- **対AI対戦** — human vs AI, with 先攻/後攻 (who moves first) and 3 difficulty levels.
- **2人対戦** — local hot-seat, both sides human.

## Move generation

- `neighborsOf(x,y,z)` — the (up to 6) adjacent valid holes, for single-step moves.
- `jumpDestsFrom(board,x,y,z)` — single jumps: for each direction, the adjacent hole must be occupied (by *either* player — no distinction, since nothing is captured) and the hole immediately beyond it must be a valid, empty board cell.
- `reachableViaJumps(board,x,y,z)` — DFS over chained jumps. Critically, it tracks a `visited` set seeded with the **starting** hole and marks every landing hole visited as it's discovered, so **a chain can never land on a hole it already landed on in the same turn** (this is both the correct game rule and what prevents infinite jump-back-and-forth loops between two adjacent pieces). Verified by test with a symmetric two-piece setup that would loop forever under a naive DFS.
- `movesForPiece` unions single-step moves with every jump-chain landing hole (each exposed as one flat `{type:'jump', from, to}` move directly to the final landing spot — the UI doesn't need to animate intermediate hops, matching how physical play treats a multi-jump as one turn).
- Per the rules, a turn is *either* one step *or* one-or-more chained jumps — never mixed. This falls out naturally because `movesForPiece` offers steps and jump-landings as separate, mutually exclusive move options; nothing chains a step onto a jump.

## AI

`pickAiMove` + `negamax`, structured like `shogi/`'s AI (plain minimax + alpha-beta, capture-move-ordering analog, difficulty via depth + random slack over near-best moves):

- **Evaluation** (`evaluateForOwner`): since this is a pure race with no captures, the heuristic is progress along the player's start→goal axis — literally the relevant cube coordinate (e.g. a `+x`-side player's progress score is `-x` summed over their pieces, since smaller/more-negative `x` is closer to the `-x` goal). This is O(1) per piece and naturally rewards chained multi-jumps, which can swing a piece's axis coordinate much further in one move than a step can.
- **Move ordering** (`moveProgressDelta`) sorts candidate moves by their own immediate progress delta before recursing, for better alpha-beta cutoffs — analogous to shogi's capture-first ordering.
- **Depth**: capped at 1–2 plies (`app.aiDepth`), same reasoning as shogi — full-width move generation (every piece × every reachable step/jump landing) is not free, and depth-2 negamax was empirically timed at up to ~200ms in a populated midgame position (measured via a Node harness before shipping — see below), which is an acceptable one-time delay behind the "AIが考え中" message and doesn't hang the UI thread beyond a single `setTimeout` tick. Depth 3 was not attempted; back-of-envelope branching (~50-150 moves/position) put it far too slow.
- Difficulty presets (やさしい/ふつう/つよい): depth 1/1/2, slack 200/60/12 (slack = how far below the best-scored move a candidate can be and still be picked at random — mirrors shogi's `aiSlack` mechanism so "easy" isn't just shallower but also less consistent).

## Known simplifications (intentional, not bugs)

- No forced-capture-style rule exists in this game (there is no capturing at all), so none was implemented — matches the real rules.
- If a player has zero legal moves for every piece (a boxed-in deadlock — rare, and near-impossible to reach in normal play), their turn is silently skipped with a message rather than ending the game; there's no formal stalemate/draw rule in real ダイヤモンドゲーム.
- 3-way / 4-way / 6-way play is not implemented (see "Player-count support shipped" above).
- No move history, no undo, no save/resume.

## Testing performed

Before embedding into `index.html`, the engine was extracted to a standalone Node-requireable module and exercised with an automated test suite (37 assertions, all passing) covering:

1. A simple single-step move (origin empties, destination fills correctly).
2. A single jump over one piece (landing correct, jumped-over piece **not** removed — no captures).
3. A chained multi-jump (2 jumps in one turn) is found by `reachableViaJumps` and reachable as one `movesForPiece` result, and applying it updates the board correctly end-to-end.
4. Board shape correctness: exactly 121 holes (61 hexagon + 6×10 points), no duplicate coordinates, all cells satisfy `x+y+z=0`, and the `+x`/`-x` point pair is point-symmetric through the center.
5. Win detection: fires when a player's pieces exactly fill their target point, and correctly does **not** fire if one target hole is occupied by the opponent or left empty.

Additional coverage: a symmetric-jump setup that would loop forever under a naive "no revisit" implementation was verified to terminate in well under 500ms and not revisit the start hole; AI search timing was measured from both the initial position and randomized 30-/60-ply midgame positions at depth 1 and 2 (worst case ~200ms at depth 2 in a busy midgame — acceptable, see AI section above). After embedding the engine into `index.html`, the exact inline script was re-extracted and the full 37-assertion suite was re-run against it (not just the pre-embedding standalone copy) to confirm nothing broke in the copy/paste.

## Versioning

Per the repo-wide convention (see root `CLAUDE.md`), bump `.app-version` in `index.html` on every change to this app (patch for fixes, minor for features).
