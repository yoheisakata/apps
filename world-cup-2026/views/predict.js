// Automatic prediction engine.
// Computes a "strength" score per team and resolves every knockout tie by
// comparing scores, advancing the higher-scored team. All inputs are real,
// locally-available data — no fabricated head-to-head records:
//
//   1. FIFA ranking      — lower rank number = stronger (teams[].rank)
//   2. Tournament form    — points + goal difference from played group matches
//   3. Head-to-head       — if the two sides already met in this tournament,
//                           the actual result nudges the prediction
//
// The weights are deliberately simple and transparent; tweak WEIGHTS to taste.

import { groupStandings } from "./standings.js?v=5";

const WEIGHTS = {
  ranking: 1.0, // per ranking-position-better (relative to worst rank)
  points: 4.0, // per tournament point
  goalDiff: 1.5, // per goal of tournament goal difference
  h2hWin: 6.0, // bonus if it beat the opponent in this tournament
  h2hDraw: 1.5, // smaller bonus for a draw
};

// Build a per-team form record (points, gd) from played group matches.
function buildForm(data) {
  const form = {};
  for (const g of Object.keys(data.groups)) {
    for (const r of groupStandings(data, g)) {
      form[r.code] = { pts: r.pts, gd: r.gd, gf: r.gf };
    }
  }
  return form;
}

// Head-to-head lookup from played matches: h2h[A][B] = result for A vs B
// stored as "W" | "D" | "L" from A's perspective.
function buildH2H(data) {
  const h2h = {};
  const put = (a, b, res) => {
    (h2h[a] ||= {})[b] = res;
  };
  for (const m of data.matches) {
    if (!m.result || !m.home || !m.away) continue;
    const [hs, as] = m.result;
    const hr = hs > as ? "W" : hs < as ? "L" : "D";
    const ar = hr === "W" ? "L" : hr === "L" ? "W" : "D";
    put(m.home, m.away, hr);
    put(m.away, m.home, ar);
  }
  return h2h;
}

// Worst (highest) rank among participants, used to normalize ranking into a
// "higher is better" scale. Teams without a rank get the worst.
function worstRank(data) {
  let w = 0;
  for (const t of data.teams) if (typeof t.rank === "number") w = Math.max(w, t.rank);
  return w || 100;
}

export function createPredictor(data) {
  const form = buildForm(data);
  const h2h = buildH2H(data);
  const maxRank = worstRank(data);

  // Base strength independent of the specific opponent.
  function baseScore(code) {
    const t = data.byCode[code];
    if (!t) return 0;
    const rank = typeof t.rank === "number" ? t.rank : maxRank;
    const rankScore = (maxRank - rank + 1) * WEIGHTS.ranking;
    const f = form[code] || { pts: 0, gd: 0 };
    return rankScore + f.pts * WEIGHTS.points + f.gd * WEIGHTS.goalDiff;
  }

  // Opponent-aware score: base + head-to-head bonus against `opp`.
  function scoreVs(code, opp) {
    let s = baseScore(code);
    const res = h2h[code]?.[opp];
    if (res === "W") s += WEIGHTS.h2hWin;
    else if (res === "D") s += WEIGHTS.h2hDraw;
    return s;
  }

  // Decide the winner of a tie between two team codes.
  // Returns the winning code, or null if either side is missing.
  function winner(a, b) {
    if (!a || !b) return null;
    const sa = scoreVs(a, b);
    const sb = scoreVs(b, a);
    if (sa === sb) {
      // deterministic tie-break: better FIFA rank, else alphabetical
      const ra = data.byCode[a]?.rank ?? maxRank;
      const rb = data.byCode[b]?.rank ?? maxRank;
      if (ra !== rb) return ra < rb ? a : b;
      return a < b ? a : b;
    }
    return sa > sb ? a : b;
  }

  const sign = (n) => (n > 0 ? `+${n}` : `${n}`);

  // Structured facts for the predicted champion, used to render a clear
  // callout at the top of the bracket. `finalOpp` is the other finalist.
  // Returns { rankTxt, formTxt, oppCode } (oppCode may be null).
  function championInfo(code, finalOpp) {
    const t = data.byCode[code];
    if (!t) return null;
    const rankTxt =
      typeof t.rank === "number" ? `FIFAランキング ${t.rank}位` : "FIFAランキング 圏外";
    const f = form[code] || { pts: 0, gd: 0 };
    const formTxt =
      f.pts > 0 || f.gd !== 0
        ? `本大会 勝点${f.pts} / 得失点${sign(f.gd)}`
        : "本大会はこれから本領発揮";
    return { rankTxt, formTxt, oppCode: finalOpp || null };
  }

  // Resolve the knockout bracket into predicted teams, keyed by "stage:index"
  // (e.g. "r32:0", "sf:1") so views can look up each fixture's predicted teams.
  //
  // The Round of 32 fixtures carry real slot labels ("Winner Group C",
  // "Runner-up Group F", "3rd Group A/B/C/D/F") which we resolve from current
  // standings. From the Round of 16 on, Wikipedia links slots by an internal
  // match numbering that doesn't match the score-link numbers, so instead we
  // advance winners structurally: the R32 fixtures, taken in article order,
  // pair up (1v2, 3v4, …) into R16, and so on — the standard single-elim fold.
  //
  // `koMatches` is the knockout match array in bracket/article order
  // (R32 ×16 → R16 ×8 → QF ×4 → SF ×2 → third → final). Returns a Map
  // matchNo -> { home, away, winner }.
  function resolveKnockout(koMatches) {
    const standCache = {};
    const stand = (g) => (standCache[g] ||= groupStandings(data, g));
    const usedThirds = new Set();

    function bestThird(groupLetters) {
      const cands = groupLetters
        .map((g) => stand(g)[2])
        .filter((r) => r && !usedThirds.has(r.code))
        .sort((a, b) => b.pts - a.pts || b.gd - a.gd || b.gf - a.gf);
      const pick = cands[0];
      if (pick) usedThirds.add(pick.code);
      return pick ? pick.code : null;
    }

    function resolveR32Label(label) {
      if (!label) return null;
      let m;
      if ((m = label.match(/Winner Group ([A-L])/))) return stand(m[1])[0]?.code ?? null;
      if ((m = label.match(/Runner-up Group ([A-L])/))) return stand(m[1])[1]?.code ?? null;
      if ((m = label.match(/3rd Group ([A-L/]+)/)))
        return bestThird(m[1].split("/").filter(Boolean));
      return null;
    }

    const byStage = (s) => koMatches.filter((m) => m.stage === s);
    // Key by stage + index (NOT matchNo): Wikipedia reuses match numbers across
    // rounds (R16 scorelinks repeat 73, 74, …), which would collide in a Map.
    const resolved = new Map();
    const setRes = (stage, i, home, away) => {
      const w = winner(home, away) || home || away || null;
      resolved.set(`${stage}:${i}`, { home, away, winner: w });
      return w;
    };

    // Round of 32 from real slot labels (article order).
    const r32 = byStage("r32");

    // Some R32 slots have an empty label in the source (e.g. the host's slot is
    // pre-seeded without a "Winner Group X" tag). Find which group winners are
    // never referenced and use them to fill those blanks, so no team is missing.
    const referencedWinners = new Set();
    for (const m of r32) {
      for (const lbl of [m.homeLabel, m.awayLabel]) {
        const w = lbl && lbl.match(/Winner Group ([A-L])/);
        if (w) referencedWinners.add(w[1]);
      }
    }
    const missingWinnerGroups = Object.keys(data.groups).filter((g) => !referencedWinners.has(g));
    const fillBlank = () => {
      const g = missingWinnerGroups.shift();
      return g ? stand(g)[0]?.code ?? null : null;
    };
    const resolveSlot = (lbl) => (lbl ? resolveR32Label(lbl) : fillBlank());

    let prevWinners = r32.map((m, i) =>
      setRes("r32", i, resolveSlot(m.homeLabel), resolveSlot(m.awayLabel))
    );

    // Fold each subsequent round: winners[2k] vs winners[2k+1].
    for (const stage of ["r16", "qf", "sf"]) {
      const ms = byStage(stage);
      const next = [];
      for (let i = 0; i < ms.length; i++) {
        next.push(setRes(stage, i, prevWinners[i * 2] ?? null, prevWinners[i * 2 + 1] ?? null));
      }
      prevWinners = next;
    }

    // Final: the two SF winners. Third place: the two SF losers.
    if (byStage("final").length) {
      setRes("final", 0, prevWinners[0] ?? null, prevWinners[1] ?? null);
    }
    const sf = byStage("sf");
    if (byStage("third").length && sf.length === 2) {
      const loserOf = (i) => {
        const r = resolved.get(`sf:${i}`);
        if (!r || !r.home || !r.away) return null;
        return r.winner === r.home ? r.away : r.home;
      };
      setRes("third", 0, loserOf(0), loserOf(1));
    }
    return resolved;
  }

  return { resolveKnockout, championInfo };
}
