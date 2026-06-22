// Bracket view: the real 32-team knockout bracket with AUTOMATIC predictions.
//
// Structure (matchups, dates) comes from the actual tournament bracket fetched
// from Wikipedia — the same Round-of-32 layout shown on ESPN (2A v 2B, 1E v a
// 3rd-placed team, …). Each slot is then filled with a PREDICTED team using
// FIFA ranking + tournament form + head-to-head (see predict.js).
//
// The R32 fixtures are resolved from real group-position labels; later rounds
// advance the predicted winners by folding the bracket (the same order
// resolveKnockout uses), so the connector lines stay consistent.

import { createPredictor } from "./predict.js?v=7";

const KO_STAGES = ["r32", "r16", "qf", "sf", "final"];
const ROUND_NAMES = {
  r32: "ラウンド32",
  r16: "ラウンド16",
  qf: "準々決勝",
  sf: "準決勝",
  final: "決勝",
};

// English slot label -> short Japanese (for unresolved R32 slots).
function jpLabel(label) {
  if (!label) return "未定";
  return label
    .replace(/Winner Group ([A-L])/, "$1組 1位")
    .replace(/Runner-up Group ([A-L])/, "$1組 2位")
    .replace(/3rd Group ([A-L/]+)/, "3位 ($1組)");
}

export function createBracket({ container, data }) {
  function name(code) {
    const t = data.byCode[code];
    return t ? `${t.flag} ${t.name}` : null;
  }

  // Matches for a stage, in bracket (article) order.
  function stageMatches(stage) {
    return data.matches.filter((m) => m.stage === stage);
  }

  // A group-position label (only meaningful in the Round of 32).
  const isGroupLabel = (label) => label && /Group [A-L]/.test(label);

  function slotBox(code, label, picked) {
    const cls = picked ? "slot picked" : "slot";
    const teamHtml = code
      ? name(code)
      : `<span class="tbd">${isGroupLabel(label) ? jpLabel(label) : "勝者待ち"}</span>`;
    // For a resolved R32 team, also show how it qualified (e.g. "A組 1位").
    const qual = code && isGroupLabel(label) ? `<span class="slot-qual">${jpLabel(label)}</span>` : "";
    return `<div class="${cls}">${teamHtml}${qual}</div>`;
  }

  function render() {
    const predictor = createPredictor(data);
    const resolved = predictor.resolveKnockout(
      data.matches.filter((m) => KO_STAGES.includes(m.stage) || m.stage === "third")
    );

    // Build each round from the real matches, resolving predicted teams.
    const roundsHtml = [];
    KO_STAGES.forEach((stage, r) => {
      const ms = stageMatches(stage);
      const ties = ms
        .map((m, i) => {
          const res = resolved.get(`${stage}:${i}`) || {};
          const home = res.home || null;
          const away = res.away || null;
          const win = res.winner || null;
          return `<div class="tie" data-r="${r}" data-i="${i}">
            ${slotBox(home, m.homeLabel, win && home && win === home)}
            ${slotBox(away, m.awayLabel, win && away && win === away)}
          </div>`;
        })
        .join("");
      roundsHtml.push(`<div class="round"><h4>${ROUND_NAMES[stage]}</h4><div class="ties">${ties}</div></div>`);
    });

    // Champion = predicted winner of the final, with a clear summary callout.
    const finalRes = resolved.get("final:0") || {};
    const champ = finalRes.winner || null;
    const finalOpp = champ ? (finalRes.home === champ ? finalRes.away : finalRes.home) : null;
    const info = champ ? predictor.championInfo(champ, finalOpp) : null;

    let calloutHtml = "";
    if (champ && info) {
      const chips = [
        `<span class="cr-chip">🥇 ${info.rankTxt}</span>`,
        `<span class="cr-chip">📊 ${info.formTxt}</span>`,
        info.oppCode && name(info.oppCode)
          ? `<span class="cr-chip">⚔️ 決勝で ${name(info.oppCode)} を撃破</span>`
          : "",
      ].join("");
      calloutHtml = `<div class="champ-callout">
        <div class="cc-head">🏆 優勝予想</div>
        <div class="cc-team">${name(champ)}</div>
        <div class="cc-reasons">${chips}</div>
        <div class="cc-note">FIFAランキング・本大会の成績・直接対戦から自動算出（暫定）</div>
      </div>`;
    }

    const champBox = `<div class="round champion-box">
      <h4>優勝予想</h4>
      <div class="ties" id="champ-box">
        <div class="trophy">🏆</div>
        <div class="name">${champ ? name(champ) : "?"}</div>
      </div>
    </div>`;

    container.innerHTML = `
      <h2 class="section-title">🔮 優勝予想ブラケット <span class="sub">ラウンド32 → 決勝</span></h2>
      ${calloutHtml}
      <div class="bracket-wrap"><div class="bracket">
        <svg class="bracket-lines" aria-hidden="true"></svg>
        ${roundsHtml.join("")}${champBox}
      </div></div>
    `;

    requestAnimationFrame(drawLines);
  }

  // Connector lines: each tie feeds tie floor(i/2) of the next round; the final
  // feeds the champion box. Highlight a line when the feeding tie's predicted
  // winner advanced into the next round's pick.
  function drawLines() {
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
    const tie = (r, i) => container.querySelector(`.tie[data-r="${r}"][data-i="${i}"]`);

    const lines = [];
    for (let r = 0; r < KO_STAGES.length; r++) {
      const ms = stageMatches(KO_STAGES[r]);
      for (let i = 0; i < ms.length; i++) {
        const from = tie(r, i);
        if (!from) continue;
        const target =
          r < KO_STAGES.length - 1 ? tie(r + 1, Math.floor(i / 2)) : container.querySelector("#champ-box");
        if (!target) continue;
        const a = rel(from);
        const b = rel(target);
        const x1 = a.right, y1 = a.midY, x2 = b.left, y2 = b.midY;
        const mx = (x1 + x2) / 2;
        lines.push(`<path d="M${x1},${y1} H${mx} V${y2} H${x2}" class="conn"/>`);
      }
    }
    svg.innerHTML = lines.join("");
  }

  if (typeof window !== "undefined") {
    window.addEventListener("resize", () => {
      if (container.querySelector(".bracket-lines")) drawLines();
    });
  }

  return { render };
}
