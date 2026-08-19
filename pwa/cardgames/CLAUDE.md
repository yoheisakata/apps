# CLAUDE.md (cardgames)

Single self-contained `index.html` (inline CSS + JS), no build step — same convention as the other GitHub-Pages web apps in this repo. Unlike the board-game apps (`shogi/`, `othello/`, etc., one game per directory), this is a **multi-game launcher within one app**: a home screen lets the player pick from several card games, each with its own setup screen, game screen, and result screen (all `<div class="screen">` toggled via `goScreen`/`goSetup`/`goHome`).

## Structure

Everything lives in one `<script>` block in `index.html`:

- **Common utilities**: `makeDeck(withJoker)` builds a 52 or 53-card deck (`{id, suit, rank, color}`), `shuffle()` is Fisher-Yates, `rankValue()` maps `A..K` to `1..13` (no wraparound anywhere in this app), `cardHTML()`/`backHTML()` render a card face/back as an HTML string with a size class (`sz-sm`/`sz-md`/`sz-lg`).
- **Screen routing**: `goHome()`/`goSetup(game)`/`goScreen(id)` toggle `.screen.active`; `stopAllLoops()` clears the スピード `setInterval` so leaving that screen doesn't leave a background timer running.
- Each game keeps its own state object (`shinkei`, `baba`, `speed`, `daifugo`, `sevens`, `tw`, `poker`, `bj`) and its own `*Cfg` object for setup-screen choices, and its own `start*()`/`quit*()` functions. No shared game state across games.
- `calcHandValue(hand)` (blackjack-style ace-flexible total: A counts 11 unless that busts, then drops to 1) is shared by 21 and ブラックジャック — the only cross-game helper besides the deck/render utilities.

### 神経衰弱 (Concentration)

- `shinkei.cards` is a flat shuffled array; deck size (24/52) picks N/2 random ranks out of the 13, then keeps every card of those ranks from the full 4-suit deck (so pairing is always same-rank, suit ignored, same as real 神経衰弱).
- **CPU memory model**: `shinkeiCfg.diff` sets a recall probability (0.3/0.55/0.85). Every time *any* card is flipped (by either player), `shinkeiMemorize` records the card's board index in `shinkei.cpuMemory` with that probability, else deletes any existing memory of it — this simulates imperfect recall without tracking a separate "seen" log. `cpuShinkeiTurn` looks for a known same-rank pair in memory first, else flips one remembered card + one random unknown card, else two random cards.
- **Important gotcha already hit once**: `shinkeiFlip(i)` is the public/click-facing entry point and includes the `mode==='ai' && turn===1` guard that blocks human clicks during the CPU's turn. The CPU's own move logic must call `shinkeiDoFlip(i)` directly (no guard) — calling `shinkeiFlip` from `cpuShinkeiTurn` would block the CPU from ever flipping anything, since the guard can't distinguish "human trying to click during CPU turn" from "the CPU logic itself running while turn===1". Keep this split if touching flip logic.

### ババ抜き (Old Maid)

- `baba.players` is an array (index 0 = human, id 0), with `seatOrder` fixed at creation. AI mode adds 2 or 3 CPU players; 2人対戦 mode is exactly 2 human players sharing the device (no privacy screen between turns — both hands are visible on the shared screen at all times, which is a deliberate simplification; drawing is still "blind" only in the sense that the UI doesn't reveal a card's rank until it's already been moved into the drawer's hand).
- `removePairs(hand)` groups by rank (ignoring `JOKER`, which can never pair) and discards any complete same-rank pairs found *within a single hand* — called once at deal time for every player, and again on the current player's hand after every draw.
- **Turn flow is fully automatic and cascades**: on each turn the current player draws from `babaNextActive(currentId)` (the next player around `seatOrder` that still has cards). If the current player is a CPU, the draw happens automatically after a delay and `babaTurn()` is scheduled again for the new current player (whoever was drawn from) — this can chain through several CPU turns in a row before control returns to a human. This is correct/intended, not a bug — verified during manual testing that a single human draw can trigger 2+ automatic CPU-vs-CPU draws before the human's next turn (including a CPU drawing from the human out of turn, since the human is just another seat in the circle).
- Game ends when only one player still holds cards (`finishedOrder` records exit order; the last name pushed — i.e. the sole remaining player — is the loser holding the joker).

### スピード (Speed)

- Simplified rules, documented in the README: no suit restriction, `rankValue` diff must be exactly 1 (no A/K wraparound), each player has a 5-card visible hand backed by a personal stock (25 cards each after 2 cards seed the two center piles from a 52-card deck: `2 + 5*2 + 25*2 = 52`).
- **Stuck resolution is a deliberate departure from real Speed/Spit**: real Speed resolves a mutual stall via both players agreeing and simultaneously flipping a new card. Here, `speedTick()` (running on a 250ms `setInterval`) detects "neither player has any legal move" and, after that condition holds continuously for 900ms (`speed.stuckSince`), `speedResolveStuck()` pops one card from each player's stock (falling back to their hand if the stock is empty) directly onto the two center piles, replacing whatever was there. This keeps the game from ever deadlocking without needing real two-player negotiation UI.
- CPU (in AI mode) only ever plays from `speed.hand[1]`, checked once per tick with a per-difficulty "reaction chance" (0.5/0.85/1.0) gating whether it acts that tick at all — this is what makes ゆっくり/ふつう/はやい feel different, not a variable delay.
- 2人対戦 is both hands controllable on the same screen simultaneously (no turn structure — it's inherently real-time), verified working via automated click tests on both the top (`speed.hand[1]`) and bottom (`speed.hand[0]`) hand rows.
- Both players' hands are always shown face-up (readable) even for the CPU/opponent — real Speed hides the opponent's hand, but since this is a single shared screen (and the CPU is not "cheating" by reading your hand, since it isn't scripted to look at `speed.hand[0]`), this was kept as a simplification for a casual digital version.

### 大富豪 (Daifugo)

- `DAIFUGO_ORDER` is the strength ladder `3,4,...,K,A,2` (index = strength); `daifugoValue(rank)` maps into it and `JOKER` is hard-coded to `100` (always strongest). This is a different ordering from `rankValue()`/`RANKS` (used by スピード/神経衰弱/７並べ), which is plain `A..K`  — don't conflate the two rank-ordering functions when touching either game.
- Deal is round-robin over a 53-card deck (52+joker) to `daifugo.players`; the player holding `3♦` is looked up to set `startId`, but the CPU-move heuristic (`daifugoCpuMove`) just plays the lowest-`daifugoValue` **group** it holds when leading, which is not necessarily the 3♦ specifically if the leader holds multiple 3s — i.e. the real-table convention "must open with 3♦" is not enforced, only "3♦'s holder leads the first trick with whatever they choose." This was verified during manual testing (the opening card was 3♠, not 3♦) and is an intentional simplification, not a bug.
- Turn/pass/pile-clear state machine: `daifugo.pile`/`requiredCount`/`passedIds`/`lastPlayerId`. A play resets `passedIds` (everyone else gets a fresh chance to beat the new pile) and sets `requiredCount` to the played group's size; a pass adds the passer to `passedIds` and, once `daifugoNextTurnId` cycles all the way back to `lastPlayerId` (the last person to successfully play), the pile clears and that player leads again free-form (`requiredCount=null`).
- **8-切り (eight-cut)**: playing a group led by an `8` immediately clears the pile and keeps the turn with the same player — *unless* that play also emptied their hand, in which case turn must pass to `daifugoNextTurnId` instead (fixed during implementation: the original code handed the turn back to a player with 0 cards left, which stalled the game since `daifugoTurn` no-ops when the current player's hand is empty).
- Joker can only be played alone (`daifugoValidSelection` rejects a joker mixed into a multi-card group); it wins any single-card comparison since its value (100) is always highest.
- Ranking on game end (`daifugoEnd`) labels finish order 大富豪/富豪/平民/貧民/大貧民 by position, clamped to that 5-label array regardless of player count.

### ７並べ (Sevens)

- `sevens.board[suit]` is `{min, max}` (rank-value bounds of the contiguous run already placed for that suit); a card is legal if it's a `7` (opens the suit) or extends `min-1`/`max+1` of an already-open suit. No suit ever "closes" — a full A..K run just stops producing legal moves for that suit once both ends are placed.
- No forced-play rule: a human (or the CPU logic, though the CPU never chooses to) can pass even holding a legal card — matches common casual house rules, documented as a simplification.
- CPU (`sevensCpuMove`) prefers playing a `7` (to open a new suit) over any other legal card, otherwise plays the first legal card found in hand order; no lookahead/strategy beyond that.

### 21 (multiplayer bust game, distinct from ブラックジャック below)

- No dealer — every seat (human or CPU) is a peer competing directly, unlike casino blackjack. Each player starts with **one** card (`startTw` deals 1, not 2) and may keep hitting multiple times within their own turn (`twCpuStep` recurses via `setTimeout` until the CPU's total reaches 17+ or busts; a human clicks "引く" repeatedly).
- CPU strategy is the fixed dealer-style threshold (hit while `<17`, i.e. reuses `calcHandValue` shared with ブラックジャック) — no difficulty setting for this game, only 対AI対戦 (CPU 2/3 people) vs 2人対戦.
- Winner = highest `calcHandValue` among non-busted players; a full bust-out (`winners.length===0`) is reported as "全員バースト" with no winner rather than crashing on an empty winner list.

### ポーカー (5-card draw, no betting)

- Always exactly 2 hands (`poker.hand[0]`/`[1]`), same 2-participant shape as スピード — `pokerName(p)` swaps between あなた/CPU and プレイヤー1/プレイヤー2 depending on `poker.mode`.
- Single draw round only, no betting: `poker.phase` walks `'p1' → ('pass2' → 'p2' in 2人対戦, or straight to CPU auto-draw in 対AI対戦) → reveal`. `pokerDraw(p)` removes the selected indices (sorted descending first, so splicing doesn't shift not-yet-removed indices) and refills to 5 from `poker.deck`.
- `pokerEvaluate(hand)` returns `{rank 0-8, name, tiebreak[]}` covering ブタ through ロイヤルストレートフラッシュ, including the wheel straight (`A-5-4-3-2`, `straightHigh=5`). `pokerCompare` breaks ties by walking `tiebreak` left to right — this is a reasonable but not fully rigorous kicker comparison (e.g. two-pair kicker order), documented as a simplification rather than tournament-exact.
- `pokerCpuDiscardIdx` is a simple heuristic: keep the whole hand as-is if it's already a made straight or flush, otherwise discard every card that's part of no pair/trip/quad and ranked below Q. Not game-theoretically optimal, just plausible.

### ブラックジャック (dealer-based, distinct from 21 above)

- `bj.players` holds 1 (対AI対戦) or 2 (2人対戦) **human** players; the dealer (`bj.dealer`) is always CPU-controlled and shared by both players in 2人対戦 — both play their own hand against the same dealer hand, not against each other.
- No double-down, no split, no insurance — hit/stand only. Dealer hits while `<17` (`bjDealerStep`, same threshold convention as 21's CPU and real casino rules), and only bothers drawing further if at least one player hasn't busted (`anyoneAlive` check) — a no-op optimization, not a rule change, since a dealer total is irrelevant once every player has busted.
- Dealer's second card is rendered face-down (`backHTML`) throughout `bj.phase==='player'` and only revealed once `bj.phase` leaves `'player'`.

## Known simplifications (intentional, not bugs)

- No suit-based rules anywhere except 大富豪 (single-rank groups only) and ７並べ (suit defines the sequence track) — 神経衰弱 pairs on rank only, スピード sequences ignore suit.
- ババ抜き / 大富豪 / ７並べ 2人対戦 have no "pass the device" privacy screen between turns; ポーカー is the only game with a "交代" pass screen (`poker.phase==='pass2'`) since hidden hands actually matter there.
- スピード has no real ace/king wraparound option, and stuck resolution is a simplified auto-reset rather than a true simultaneous-flip negotiation (see above).
- 大富豪 does not enforce "must lead with 3♦ specifically", has no revolution (rank-order reversal), no shibari (suit-lock), and no rule against passing back a joker.
- 21 and ブラックジャック are two separate, differently-structured games (no dealer + multi-hit-per-turn vs single CPU dealer) despite both being blackjack-family bust games — don't merge their logic if refactoring, they're intentionally distinct rule sets per the original feature request.
- No score history, no save/resume, no chip/betting economy in ポーカー or ブラックジャック — every game starts fresh from the setup screen.

If any of these get implemented later, update this file and the README's ルール実装メモ-equivalent sections.

## Versioning

Per the repo-wide convention (see root `CLAUDE.md`), bump `.app-version` in `index.html` on every change to this app (patch for fixes, minor for features — e.g. adding a new game like 大富豪/７並べ/ポーカー/ブラックジャック/21 is a minor bump).
