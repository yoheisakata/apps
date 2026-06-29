// Knockout-stage results view: the REAL 32-team bracket, every round shown as a
// column (R32 → R16 → QF → SF → 決勝 → 優勝), so you can follow each team as it
// advances. Filled with real data only — confirmed teams, actual dates, and
// final scores. No predictions: a slot stays as its qualification label
// (e.g. "A組 2位") or "勝者待ち" until the result that fills it is in.
//
// Teams flow forward structurally (winner of tie i feeds tie ⌊i/2⌋ of the next
// round — the standard single-elim fold), the same ordering the 優勝予想 bracket
// uses, but here the winner is the ACTUAL match result rather than a prediction.
// A confirmed team from the live source always overrides the folded slot.

import { groupStandings } from "./standings.js?v=27";
import { localHM, localMDW, tzLabel } from "./util.js?v=27";

const ROUND_NAMES = {
  r32: "ラウンド32",
  r16: "ラウンド16",
  qf: "準々決勝",
  sf: "準決勝",
  final: "決勝",
};

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

// English slot label -> short Japanese (for unresolved R32 slots).
function jpLabel(label) {
  if (!label) return "未定";
  return label
    .replace(/Winner Group ([A-L])/, "$1組 1位")
    .replace(/Runner-up Group ([A-L])/, "$1組 2位")
    .replace(/3rd Group ([A-L/]+)/, "3位 ($1組)");
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
      ? `<span class="slot-team"><span class="bk-flag">${t.flag}</span><span class="slot-tname">${esc(t.wiki || t.name)}</span></span>`
      : null;
  }
  function jpName(code) {
    const t = data.byCode[code];
    return t ? t.wiki || t.name : null;
  }

  // How an R32 team qualified, e.g. "I組 1位". Prefer the slot label; for a
  // confirmed team (label dropped) derive the group position from standings.
  function qualText(code, label) {
    if (isGroupLabel(label)) return jpLabel(label);
    const t = data.byCode[code];
    if (!t || !t.group || !data.groups?.[t.group]) return "";
    const pos = groupStandings(data, t.group).findIndex((r) => r.code === code);
    return pos >= 0 ? `${t.group}組 ${pos + 1}位` : "";
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
      `<span class="slot-team tbd">${esc(isGroupLabel(label) ? jpLabel(label) : tbd || "勝者待ち")}</span>`;
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

  // Resolve every round's two teams. R32 uses confirmed teams; later rounds take
  // the confirmed team if the source has it, else fold the winner of the feeding
  // tie forward. Returns { r32:[...], r16:[...], ..., final:[...], third }.
  function resolveBracket() {
    const byStage = (s) => data.matches.filter((m) => m.stage === s);
    const out = {};
    let prev = byStage("r32").map((m) => ({ home: m.home || null, away: m.away || null, m }));
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
        .map((i) => tieHtml(br[stage][i], stage, i, { tbdHome: "勝者待ち", tbdAway: "勝者待ち" }))
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
        ${tieHtml(br.final[0], "final", 0, { tbdHome: "勝者待ち", tbdAway: "勝者待ち" })}
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
        <h4 class="ko-third-title">🥉 3位決定戦</h4>
        ${tieHtml(br.third, "third", 0, { tbdHome: "敗者待ち", tbdAway: "敗者待ち" })}
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
        <div class="cc-head">🏆 優勝</div>
        <div class="cc-team">${data.byCode[champ].flag} ${esc(jpName(champ))}</div>
        <div class="cc-note">決勝トーナメントの実際の結果（自動取得）</div>
      </div>`;
    } else {
      let note;
      if (playedKo > 0) note = `これまでに ${playedKo} 試合が終了。勝者が次のラウンドへ進みます。各試合をタップで詳細。`;
      else if (advanced) note = "決勝トーナメント進行中。勝ち上がったチームが各ラウンドに表示されます。各試合をタップで詳細。";
      else note = "決勝トーナメントはまだ始まっていません。各試合をタップで詳細を表示します。";
      calloutHtml = `<div class="champ-callout">
        <div class="cc-head">⚽ 決勝トーナメント</div>
        <div class="cc-note">${note}</div>
      </div>`;
    }

    container.innerHTML = `
      <h2 class="section-title">🏆 決勝トーナメント表 <span class="sub">ラウンド32 → 決勝</span></h2>
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
