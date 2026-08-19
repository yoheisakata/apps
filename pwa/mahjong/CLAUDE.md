# CLAUDE.md (mahjong)

Single self-contained `index.html` (inline CSS + JS), no build step — same convention as the other GitHub-Pages web apps in this repo.

## Why this app doesn't follow the shogi/othello/gomoku "対AI対戦 / 2人対戦" mode pattern

Mahjong is inherently a 4-player game — there is no meaningful 2-player variant, and a "対AI対戦" vs "2人対戦" picker doesn't map onto it. So this app skips the mode-picker screen entirely and is always **1人プレイ(あなた)+ AI 3人**: you occupy seat 0, the other three seats are always computer-controlled. The only pre-game choice is match length (東1局 / 東風戦4局 / 半荘風8局). This is a deliberate deviation from the other board-game apps in this repo, not an oversight.

## Structure

Everything lives in one `<script>` block in `index.html`, split into two clearly delimited sections:

1. **Engine section** (pure logic, no DOM access) — tile definitions, hand decomposition, yaku/fu/han evaluation, scoring tables, and the heuristic AI decision functions. At the end of this section the functions are collected into a `MahjongEngine` object; if `module.exports` exists (i.e. running under Node, not a browser) the script exports `MahjongEngine` and `return`s immediately, skipping all DOM code. This is what makes the engine independently unit-testable — see "Testing" below.
2. **UI section** (everything after that early-return) — DOM element lookups, the game state object `G`, the turn/draw/discard/call state machine, and all `render*` functions.

### Tile representation

Tiles are strings: `m1`..`m9` (萬子/manzu), `p1`..`p9` (筒子/pinzu), `s1`..`s9` (索子/souzu), `z1`..`z7` (字牌: 東南西北白發中, i.e. z1=East, z2=South, z3=West, z4=North, z5=White/白, z6=Green/發, z7=Red/中). `TILE_KINDS` is the canonical ordering (index 0–33); `TILE_INDEX` maps code → index. Most internal hand-shape logic works on a 34-length `counts` array (one slot per tile kind) rather than on the raw tile-code arrays, since suit/sequence adjacency is just index arithmetic that way (`idx % 9` for position within a suit, `idx >= 27` for honors).

Tiles render as native Unicode Mahjong Tile glyphs (U+1F000–U+1F02B) with a small kanji label (`TILE_LABEL`, e.g. "5萬") always shown underneath each tile — this was chosen specifically so the app stays legible even in environments with incomplete Mahjong-glyph font coverage (the label is not a conditional fallback, it's always rendered).

### Hand-shape / win detection

- `parseMelds(counts)` recursively decomposes a 34-slot count array into every possible list of triplets/sequences (tries triplet-then-sequence at the lowest nonzero index each step, backtracking). `decomposeHand(counts, neededSets)` wraps it: for every tile kind with count ≥ 2, treats it as the pair and asks `parseMelds` for decompositions of the rest, keeping only ones with exactly `neededSets` sets. `neededSets = 4 - melds.length` — an open meld (pon) or a closed kan (ankan) each count as "one of the 4 sets" structurally, even though ankan physically holds 4 tiles.
- `isChiitoitsuCounts` checks the seven-distinct-pairs shape directly (rejects any kind with count 4, since four-of-a-kind doesn't count as two pairs for chiitoitsu).
- `isWinningShape(counts, meldsCount)` = chiitoitsu shape (only when `meldsCount===0`, chiitoitsu requires a fully closed hand) OR `decomposeHand(...).length > 0`.
- `isTenpai` / `tenpaiWaits` try adding each of the 34 tile kinds and check `isWinningShape` — this is also how riichi eligibility, AI riichi decisions, and ryuukyoku tenpai payments are determined.
- **国士無双 (kokushi musou / thirteen orphans) is not implemented.** `isWinningShape` never recognizes it. A genuine kokushi-shaped hand simply won't register as a win in this app.

### Yaku / fu / han

`analyzeWin(concealedTilesIncWin, winTile, isTsumo, melds, seatWind, roundWind, isRiichi, isRinshan)` is the single entry point used for every win check (human tsumo/ron buttons, AI tsumo, and both human and AI ron-call checks). It:

1. Checks the chiitoitsu branch (if closed) and every standard 4-sets+pair decomposition from `decomposeHand`, computing a yaku list + han total for each.
2. For each candidate decomposition, computes fu via `computeFu`, which determines the wait type (`getWaitInfo`: tanki/shanpon/kanchan/penchan/ryanmen) by finding which set (or the pair) contains the winning tile, and adds ankou/minko/ankan/minkan fu per set plus yakuhai-pair fu plus wait-shape fu, rounding up to the nearest 10 (except pinfu, which is a fixed 20/30, and chiitoitsu, fixed 25).
3. Discards any candidate with han = 0 (no yaku — an invalid win), then picks the highest-scoring surviving candidate (`estimateScoreRank`) as the "best interpretation," matching the real-rules convention of scoring a hand by its most favorable valid reading.
4. Returns `null` if no candidate has any yaku at all — the caller then treats the tile/hand as **not a win**. This is the deliberate conservative default requested for this app: an unrecognized-yaku hand fails closed (can't be claimed as a win) rather than risking an incorrect score.

Implemented yaku: 立直 (riichi, flagged externally on the seat), 門前清自摸和 (menzen tsumo), 平和 (pinfu), 断么九 (tanyao — checks concealed tiles *and* meld tiles), 役牌 (yakuhai — dragons always, seat wind and round wind separately, so a dealer's own East trip during the fixed East round scores twice), 一盃口 (iipeikou, closed hand only), 対々和 (toitoi), 七対子 (chiitoitsu), 混一色/清一色 (honitsu/chinitsu, open value differs from closed), 嶺上開花 (rinshan kaihou, flagged when the win comes from an ankan replacement draw).

**Not implemented** (a hand that would only score via one of these does not register as a win): 三色同順, 一気通貫, チャンタ/純チャン, 二盃口, 三暗刻, 三色同刻, 小三元, all yakuman (国士無双, 四暗刻, 大三元, 字一色, 九蓮宝燈, etc). As a deliberate safety-conservative simplification, an all-honor tile hand (which in real rules would be the yakuman 字一色) is instead scored as 混一色 (3 han) by `honitsuOrChinitsu` rather than rejected outright or (wrongly) paid out as a yakuman — this under-scores a would-be yakuman hand, never over-scores a lesser hand, and was chosen because it's a two-line special case in `honitsuOrChinitsu` rather than a new yakuman-detection subsystem.

Dora, aka-dora (red fives), uradora, and ippatsu are **not implemented at all** — no dora indicator is ever revealed, and no extra han is ever added for them.

### Scoring

`computePayments(han, fu, isDealer, isTsumo)` uses the standard base-point formula (`fu * 2^(2+han)`) for han 1–4, clamped up to the mangan table if the computed base exceeds 2000 (the usual "kiriage mangan" rounding), and fixed payment tables (`SCORE_TIERS`) for mangan/haneman/baiman/sanbaiman/yakuman at han ≥ 5 (the yakuman tier is reachable only by han stacking through riichi + multiple stacked yaku, since no yaku is itself flagged yakuman-strength). Honba adds 300 points to a ron payment or 100 points per payer to a tsumo payment; riichi-stick bank (1000 each) goes entirely to the winner and is not itself subject to honba.

### Turn / call state machine (UI section)

`beginTurn(seatIdx)` draws a tile and calls `processDrawnTile`, which checks tsumo, then ankan, then (for AI) picks a discard via `aiChooseDiscard` and possibly declares riichi. Every discard funnels through `doDiscardCommon`, which then calls `resolveCalls(discarderSeat, tile)`.

**Multi-ron (double/triple ron on the same discard) is intentionally not supported.** `resolveCalls` always checks the human seat first; if the human can ron and declines, the tile is *not* then offered to AI seats for ron even if they technically could also ron it — the human's decision is final for that discard. If the human has no ron option, the first AI seat (in turn order after the discarder) that can ron does so automatically. This single-candidate simplification was chosen to avoid the complexity (and bug surface) of splitting one discard's payment across multiple simultaneous winners.

Pon similarly only ever resolves to a single caller (human first if eligible, then the first AI in turn order that both can and heuristically wants to pon via `aiWantsPon`).

### Kan: ankan only

**Only 暗槓 (ankan / concealed kan) is implemented.** There is no 大明槓 (daiminkan, calling kan on someone else's discard) and no 加槓 (shouminkan, upgrading an existing pon to a kan) — `doPon` never offers an upgrade path, and `resolveCalls` never checks for a kan-on-discard option. Ankan can only be declared immediately after drawing the 4th copy of a tile on your own turn (via `findAnkanOption`, called from `processDrawnTile`/AI logic and via the "暗槓" button for the human); it is not offered for tiles that have been sitting in a 4-of-a-kind in hand at other points in the turn. Ankan is also disallowed entirely once a seat is in riichi (real rules sometimes permit an ankan that doesn't change the wait; this app simplifies to "no kan after riichi" to avoid that wait-preservation check). If more than one ankan option exists simultaneously (rare), only the first tile kind found is offered.

### Furiten

`isPermanentFuriten(seat)` checks, for every distinct tile kind the seat has ever discarded, whether adding it back to the seat's current hand would complete a win — if any of them would, the seat is furiten and cannot ron *any* tile until their hand shape changes (this matches the real rule that furiten blocks all ron, not just the specific missed tile). `seat.tempFuriten` additionally blocks ron for the remainder of the current go-around when a human explicitly declines an offered ron (real-rules "temporary furiten" from passing a call); it's cleared the next time that seat discards. AI seats never get offered a ron choice to decline — they always ron when eligible — so `tempFuriten` in practice only ever applies to the human seat.

### Dealer rotation, honba, and round wind

Only an 東 (East) round is implemented — there is no 南入 (South round), so `ROUND_WIND` is a constant (27, i.e. z1/East) for the entire game, and match length is chosen up front as a flat hand count (1/4/8) rather than "until 南4局 ends." The dealer seat rotates to the next seat whenever a non-dealer wins or the dealer is noten at ryuukyoku; the dealer repeats (with honba incrementing) when the dealer wins or is tenpai at ryuukyoku. Honba resets to 0 only when the dealer changes following a non-dealer win — it is **not** reset when the dealer changes after a ryuukyoku (i.e. honba keeps accumulating across a dealer-rotating draw). This is one of several valid honba conventions used across real rule sets; it was chosen for implementation simplicity, not because it's the only "correct" one.

### AI

`aiChooseDiscard` is a simple per-tile heuristic (pairs/triplets are protected, suited tiles get value for having neighbors within ±2, terminals/honors are slightly deprioritized when otherwise tied) — **not** a shanten-counting or lookahead AI. `aiWantsPon` only pons yakuhai tiles or when the hand already looks toitoi-ish (already has a triplet or an open meld). AI always riichis when reaching tenpai on a legal discard (if closed and score ≥ 1000) and always ankans/tsumos/rons when legally able to. None of this claims to be strong play — it exists to keep games moving and occasionally win/lose plausibly, not to be a challenging opponent.

## Testing performed

The engine section was extracted (the `<script>` body between `<script>`/`</script>`, which is guarded by the `module.exports` early-return) and run under Node.js as a standalone module:

- **Unit tests** (`analyzeWin`/`computePayments`/`isTenpai` on hand-built tile arrays): a pinfu ryanmen-ron hand, a yakuhai (white dragon) tsumo hand, a chiitoitsu hand, a hand engineered to have **no** valid yaku (open hand, all sequences, non-yakuhai pair, contains a terminal so no tanyao) confirmed to correctly return `null` (no win), a riichi+tanyao+pinfu stacked hand with a manual han/fu check, a double-East-wind (dealer, round=East) yakuhai double-count check, a toitoi hand, and a honitsu hand — all produced the expected yaku lists, han, and fu.
- **Full-game simulation**: 300 complete hands played end-to-end by simple random-but-legal AI logic occupying all 4 seats (draw → tsumo/ankan/discard → ron/pon/advance → ryuukyoku-or-win → next hand), checking after every hand that total points (all 4 scores + riichi-stick bank × 1000) still sum to exactly 100,000 — i.e. no point leaks or duplication anywhere in the payment code paths. Result: 300/300 hands completed with zero exceptions and zero score-conservation violations (237 wins split between tsumo/ron, 63 ryuukyoku, 32 ankans, 1038 pons exercised across the run).
- These test scripts were scratch files used to validate the shipped `index.html`, not committed into the repo (per the no-report-files convention) — they can be regenerated by extracting the `<script>...</script>` body of `index.html` into a `.js` file and `require()`-ing it from Node (the module-export guard at the top of the UI section makes this work without a DOM shim).

**Not tested**: the DOM/rendering code path itself (button wiring, call-panel display, animations) was not exercised by an automated browser test — only manually reasoned through. Visual rendering of the Unicode Mahjong Tile glyphs (U+1F000–U+1F02B) was not visually verified in an actual browser in this environment; the always-present kanji label under each tile is the deliberate hedge against that risk.

## Honest confidence assessment

High confidence in: win/no-win detection (conservative — never claims a win the hand doesn't have), the specific yaku listed above as implemented, fu/han→point arithmetic (verified against hand-computed expected values), turn/call state-machine not crashing across hundreds of simulated hands, and score conservation (no point creation/destruction bugs).

Lower confidence in: whether the "best decomposition" picked by `estimateScoreRank` always exactly matches what a human scorer would pick in genuinely ambiguous multi-interpretation hands (rare shapes with several simultaneous valid decompositions); the AI's play quality (it is deliberately simple and will make what a real player would consider bad decisions, e.g. keeping a slow toitoi shape when a fast tanyao is available); and general UI edge cases (e.g. rapid taps during an in-flight `setTimeout` AI turn) that weren't specifically stress-tested.

## Versioning

Per the repo-wide convention (see root `CLAUDE.md`), bump `.app-version` in `index.html` on every change to this app (patch for fixes, minor for features).
