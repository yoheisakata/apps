// Knockout-stage results view: the REAL 32-team bracket, every round shown as a
// column (R32 → R16 → QF → SF → 決勝 → 優勝), so you can follow each team as it
// advances. Filled with real data only — confirmed teams, actual dates, and
// final scores. No predictions: a slot stays as its qualification label
// (e.g. "2A") or "TBD" until the result that fills it is in.
//
// Teams flow forward structurally (winner of tie i feeds tie ⌊i/2⌋ of the next
// round — the standard single-elim fold), the same ordering the 優勝予想 bracket
// uses, but here the winner is the ACTUAL match result rather than a prediction.
// A confirmed team from the live source always overrides the folded slot.

import { groupStandings } from "./standings.js?v=27";
import { localHM, localMDW, tzLabel } from "./util.js?v=27";

const ROUND_NAMES = {
  r32: "Round of 32",
  r16: "Round of 16",
  qf: "Quarter-finals",
  sf: "Semi-finals",
  final: "Final",
};

// FIFA Annex C: which group's third-placed team each group winner faces in the
// R32, keyed by the SORTED set of the eight groups whose thirds qualify. The full
// official table has 495 combinations; the per-slot candidate lists alone never
// pin down a unique pairing, so we encode the combinations we can verify against
// the official source. Unlisted combinations fall back to TBD (awaiting live
// data). Value: { winnerGroup: thirdGroup }.
const THIRD_ASSIGN = {
  // Combination #67 — thirds of B, D, E, F, I, J, K, L qualify (2026 outcome).
  // Verified against the 2026 FIFA World Cup knockout-stage bracket.
  BDEFIJKL: { A: "E", B: "J", D: "B", E: "D", G: "I", I: "F", K: "L", L: "K" },
};

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

// Source slot label -> compact bracket notation (for unresolved R32 slots).
// "Winner Group A" -> "1A", "Runner-up Group B" -> "2B", "3rd Group A/B" -> "3rd A/B".
function shortLabel(label) {
  if (!label) return "TBD";
  return label
    .replace(/Winner Group ([A-L])/, "1$1")
    .replace(/Runner-up Group ([A-L])/, "2$1")
    .replace(/3rd Group ([A-L/]+)/, "3rd $1");
}

// The team that advanced from a played match: higher score, or the penalty
// winner on a draw. Uses the match's own home/away orientation (which the live
// source always sets together with the result). Null while unplayed/undecided.
function winnerOf(m) {
  if (!m || !Array.isArray(m.result) || !m.home || !m.away) return null;
  const [h, a] = m.result;
  if (h !== a) return h > a ? m.home : m.away;
  if (m.penalties) return m.penalties[0] > m.penalties[1] ? m.home : m.away;
  return null;
}
function loserOf(m) {
  const w = winnerOf(m);
  if (!w) return null;
  return w === m.home ? m.away : m.home;
}

export function createKnockout({ container, data }) {
  const TZ = tzLabel();
  let lastBr = null; // most recent resolved bracket, for redrawing lines on resize
  const isGroupLabel = (label) => label && /Group [A-L]/.test(label);

  function name(code) {
    const t = data.byCode[code];
    return t
      ? `<span class="slot-team"><span class="bk-flag">${t.flag}</span><span class="slot-tname">${esc(t.name)}</span></span>`
      : null;
  }
  function enName(code) {
    const t = data.byCode[code];
    return t ? t.name : null;
  }

  // How an R32 team qualified, e.g. "1I" (winner I), "2B" (runner-up B), "3E"
  // (third of E). When the team is known, derive its real group position from the
  // standings; otherwise fall back to the slot label.
  function qualText(code, label) {
    const t = code && data.byCode[code];
    if (t && t.group && data.groups?.[t.group]) {
      const pos = groupStandings(data, t.group).findIndex((r) => r.code === code);
      if (pos >= 0) return `${pos + 1}${t.group}`;
    }
    return isGroupLabel(label) ? shortLabel(label) : "";
  }

  // Compact match date + kickoff in the viewer's timezone, e.g. "6/28(日) 13:00".
  function tieMeta(m) {
    const md = localMDW(m);
    if (!md) return "";
    const t = localHM(m);
    return `<div class="tie-meta">📅 ${md}${t ? ` ${t} <span class="m-tz">${TZ}</span>` : ""}</div>`;
  }

  // One side of a tie. `code` is the resolved team (or null), `label` its source
  // slot label, `won` whether it advanced, `score` its goals (or null), and
  // `tbd` the placeholder text when no team is resolved yet.
  function slotBox(code, label, { won, score, isR32, tbd } = {}) {
    const teamHtml =
      (code && name(code)) ||
      `<span class="slot-team tbd">${esc(isGroupLabel(label) ? shortLabel(label) : tbd || "TBD")}</span>`;
    let right = "";
    if (score != null) right = `<span class="slot-score">${score}</span>`;
    else if (code && isR32) {
      const q = qualText(code, label);
      if (q) right = `<span class="slot-qual">${esc(q)}</span>`;
    }
    return `<div class="slot${won ? " picked" : ""}">${teamHtml}${right}</div>`;
  }

  // Render one tie (two slots + date), wired to open the match-detail modal.
  // Keyed by stage + index so the symmetric two-sided line-drawing can find it.
  function tieHtml(t, stage, i, { tbdHome, tbdAway } = {}) {
    const m = t.m;
    const isR32 = stage === "r32";
    const win = winnerOf(m);
    const played = Array.isArray(m.result);
    const pen = m.penalties ? `<div class="tie-pk">PK ${m.penalties[0]}-${m.penalties[1]}</div>` : "";
    return `<div class="tie" data-stage="${stage}" data-i="${i}" data-match-id="${m.id}" role="button" tabindex="0">
      ${tieMeta(m)}
      ${slotBox(t.home, m.homeLabel, { won: win && t.home === win, score: played ? m.result[0] : null, isR32, tbd: tbdHome })}
      ${slotBox(t.away, m.awayLabel, { won: win && t.away === win, score: played ? m.result[1] : null, isR32, tbd: tbdAway })}
      ${pen}
    </div>`;
  }

  // When a group has finished all its matches, fill an R32 slot from our own
  // standings instead of waiting for the live bracket source: "Winner Group X" ->
  // that group's 1st place, "Runner-up Group X" -> 2nd. Third-placed-team slots
  // ("3rd Group …") need the cross-group combination table — see fillThirds().
  // Returns a team code, or null while the group is still in progress / not a
  // group-position label.
  function teamFromGroupLabel(label) {
    const mt = label && /^(Winner|Runner-up) Group ([A-L])$/.exec(label);
    if (!mt) return null;
    const teams = data.groups?.[mt[2]];
    if (!teams) return null;
    const rows = groupStandings(data, mt[2]);
    const complete = rows.length === teams.length && rows.every((r) => r.pld === teams.length - 1);
    if (!complete) return null;
    return (mt[1] === "Winner" ? rows[0] : rows[1])?.code || null;
  }

  // Fill the eight "3rd Group …" R32 slots once every group is complete: rank all
  // twelve third-placed teams (pts, gd, gf), take the best eight, then look up the
  // Annex C pairing for that exact set of qualifying groups and drop each third
  // into its winner's slot. No-op until all groups are done (the qualifying set
  // isn't known before then) or if the combination isn't in THIRD_ASSIGN.
  function fillThirds(r32) {
    const groupKeys = Object.keys(data.groups || {});
    const thirds = [];
    for (const g of groupKeys) {
      const teams = data.groups[g];
      const rows = groupStandings(data, g);
      const complete = rows.length === teams.length && rows.every((r) => r.pld === teams.length - 1);
      if (!complete) return; // qualifying set unknown until every group has finished
      if (rows[2]) thirds.push({ group: g, ...rows[2] });
    }
    const best = thirds
      .sort((a, b) => b.pts - a.pts || b.gd - a.gd || b.gf - a.gf)
      .slice(0, 8);
    if (best.length < 8) return;
    const map = THIRD_ASSIGN[best.map((t) => t.group).sort().join("")];
    if (!map) return; // combination not encoded yet — leave the slots as TBD
    const codeOfThird = Object.fromEntries(best.map((t) => [t.group, t.code]));

    // The opposing side of a third-place slot is a group winner. Read its group
    // from the "Winner Group X" label, or — when the live source has confirmed the
    // winner and dropped the label — from the resolved team's own group.
    const winnerGroupOf = (code, label) => {
      const ml = /^Winner Group ([A-L])$/.exec(label || "");
      return ml ? ml[1] : (code && data.byCode[code]?.group) || null;
    };
    for (const t of r32) {
      // A third-place slot pairs a group winner with a "3rd Group …" placeholder;
      // handle the third on either side (data currently always puts it on away).
      if (!t.away && /^3rd Group/.test(t.m.awayLabel || "")) {
        const wg = winnerGroupOf(t.home, t.m.homeLabel);
        if (wg && map[wg]) t.away = codeOfThird[map[wg]] || null;
      } else if (!t.home && /^3rd Group/.test(t.m.homeLabel || "")) {
        const wg = winnerGroupOf(t.away, t.m.awayLabel);
        if (wg && map[wg]) t.home = codeOfThird[map[wg]] || null;
      }
    }
  }

  // Resolve every round's two teams. R32 uses confirmed teams, falling back to the
  // group winner/runner-up once that group is complete, plus the Annex C third-
  // place assignment; later rounds take the confirmed team if the source has it,
  // else fold the winner of the feeding tie forward.
  // Returns { r32:[...], r16:[...], ..., final:[...], third }.
  function resolveBracket() {
    const byStage = (s) => data.matches.filter((m) => m.stage === s);
    const out = {};
    let prev = byStage("r32").map((m) => ({
      home: m.home || teamFromGroupLabel(m.homeLabel) || null,
      away: m.away || teamFromGroupLabel(m.awayLabel) || null,
      m,
    }));
    fillThirds(prev);
    out.r32 = prev;
    for (const stage of ["r16", "qf", "sf", "final"]) {
      const cur = byStage(stage).map((m, i) => ({
        home: m.home || winnerOf(prev[i * 2]?.m) || null,
        away: m.away || winnerOf(prev[i * 2 + 1]?.m) || null,
        m,
      }));
      out[stage] = cur;
      prev = cur;
    }
    const thirdM = byStage("third")[0];
    if (thirdM && out.sf.length === 2) {
      out.third = {
        home: thirdM.home || loserOf(out.sf[0].m) || null,
        away: thirdM.away || loserOf(out.sf[1].m) || null,
        m: thirdM,
      };
    }
    return out;
  }

  function render() {
    const br = resolveBracket();
    lastBr = br;

    // Symmetric two-sided bracket (like the old 優勝予想): the half of the draw
    // that feeds the left semi-final fans out on the LEFT, the other half on the
    // RIGHT, both folding inward to the final + champion in the CENTRE.
    //   Left  half: r32[0..7]  → r16[0..3] → qf[0..1] → sf[0]
    //   Right half: r32[8..15] → r16[4..7] → qf[2..3] → sf[1]
    const range = (a, b) => Array.from({ length: b - a }, (_, k) => a + k);
    const col = (stage, indices, side) => {
      const ties = indices
        .map((i) => tieHtml(br[stage][i], stage, i, { tbdHome: "TBD", tbdAway: "TBD" }))
        .join("");
      return `<div class="round" data-side="${side}"><h4>${ROUND_NAMES[stage]}</h4><div class="ties">${ties}</div></div>`;
    };
    const leftCols =
      col("r32", range(0, 8), "L") + col("r16", range(0, 4), "L") + col("qf", range(0, 2), "L") + col("sf", [0], "L");
    // Right side runs center-outward: SF nearest the centre, R32 furthest out.
    const rightCols =
      col("sf", [1], "R") + col("qf", range(2, 4), "R") + col("r16", range(4, 8), "R") + col("r32", range(8, 16), "R");

    // Champion = winner of the played final; shown in the centre under the final.
    const champ = winnerOf(br.final[0]?.m);
    const centerCol = `<div class="round kc-center">
      <h4>${ROUND_NAMES.final}</h4>
      <div class="ties"><div class="center-stack">
        ${tieHtml(br.final[0], "final", 0, { tbdHome: "TBD", tbdAway: "TBD" })}
        <div class="kc-champ" id="champ-box">
          <div class="trophy">🏆</div>
          <div class="kc-champ-name">${champ ? name(champ) : "?"}</div>
        </div>
      </div></div>
    </div>`;

    // Third-place play-off, shown as a standalone card under the bracket.
    let thirdHtml = "";
    if (br.third) {
      thirdHtml = `<div class="ko-third">
        <h4 class="ko-third-title">🥉 Third-place Play-off</h4>
        ${tieHtml(br.third, "third", 0, { tbdHome: "TBD", tbdAway: "TBD" })}
      </div>`;
    }

    const playedKo = data.matches.filter(
      (m) => ["r32", "r16", "qf", "sf", "third", "final"].includes(m.stage) && Array.isArray(m.result)
    ).length;
    // A team confirmed in R16+ means the knockout is under way even if a score
    // hasn't been recorded yet (some sources advance teams before the result).
    const advanced = data.matches.some(
      (m) => ["r16", "qf", "sf", "third", "final"].includes(m.stage) && (m.home || m.away)
    );

    let calloutHtml;
    if (champ) {
      calloutHtml = `<div class="champ-callout">
        <div class="cc-head">🏆 Champion</div>
        <div class="cc-team">${data.byCode[champ].flag} ${esc(enName(champ))}</div>
        <div class="cc-note">Actual knockout-stage result (auto-updated)</div>
      </div>`;
    } else {
      let note;
      if (playedKo > 0) note = `${playedKo} ${playedKo === 1 ? "match" : "matches"} played so far. Winners advance to the next round. Tap a match for details.`;
      else if (advanced) note = "Knockout stage under way. Teams that have advanced appear in each round. Tap a match for details.";
      else note = "The knockout stage hasn't started yet. Tap a match for details.";
      calloutHtml = `<div class="champ-callout">
        <div class="cc-head">⚽ Knockout Stage</div>
        <div class="cc-note">${note}</div>
      </div>`;
    }

    container.innerHTML = `
      <h2 class="section-title">🏆 Knockout Stage <span class="sub">Round of 32 → Final</span></h2>
      ${calloutHtml}
      <div class="bracket-wrap"><div class="bracket bracket-2sided">
        <svg class="bracket-lines" aria-hidden="true"></svg>
        ${leftCols}${centerCol}${rightCols}
      </div></div>
      ${thirdHtml}
    `;

    requestAnimationFrame(() => drawLines(br));
  }

  // Connector lines for the symmetric bracket: each tie feeds tie ⌊i/2⌋ of the
  // next round, folding inward toward the centre final. A tie is on the LEFT half
  // when its index is in the lower half of the round (i < count/2), else RIGHT;
  // left ties connect right-edge→left-edge, right ties left-edge→right-edge. A
  // line goes green once the feeding tie has a winner, lighting up the path.
  function drawLines(br) {
    const svg = container.querySelector(".bracket-lines");
    const bracket = container.querySelector(".bracket");
    if (!svg || !bracket) return;
    const base = bracket.getBoundingClientRect();
    svg.setAttribute("viewBox", `0 0 ${base.width} ${base.height}`);
    svg.setAttribute("width", base.width);
    svg.setAttribute("height", base.height);

    const rel = (el) => {
      const r = el.getBoundingClientRect();
      return { left: r.left - base.left, right: r.right - base.left, midY: r.top - base.top + r.height / 2 };
    };
    const tie = (stage, i) => container.querySelector(`.tie[data-stage="${stage}"][data-i="${i}"]`);
    const finalEl = tie("final", 0);

    const FOLD = ["r32", "r16", "qf", "sf"];
    const lines = [];
    for (let s = 0; s < FOLD.length; s++) {
      const stage = FOLD[s];
      const arr = br[stage];
      const next = s < FOLD.length - 1 ? FOLD[s + 1] : "final";
      for (let i = 0; i < arr.length; i++) {
        const from = tie(stage, i);
        const target = next === "final" ? finalEl : tie(next, Math.floor(i / 2));
        if (!from || !target) continue;
        const left = i < arr.length / 2; // left half of this round
        const a = rel(from);
        const b = rel(target);
        const x1 = left ? a.right : a.left;
        const x2 = left ? b.left : b.right;
        const mx = (x1 + x2) / 2;
        const live = winnerOf(arr[i].m) ? " live" : "";
        lines.push(`<path d="M${x1},${a.midY} H${mx} V${b.midY} H${x2}" class="conn${live}"/>`);
      }
    }
    svg.innerHTML = lines.join("");
  }

  if (typeof window !== "undefined") {
    window.addEventListener("resize", () => {
      if (lastBr && container.querySelector(".bracket-lines")) drawLines(lastBr);
    });
  }

  return { render };
}
