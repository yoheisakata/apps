// Bracket view: a symmetric two-sided knockout bracket (R32 on the left and
// right, folding inward to the predicted CHAMPION in the centre). Slots are
// filled with confirmed teams where known, otherwise predicted via predict.js.

import { createPredictor } from "./predict.js?v=22";
import { groupStandings } from "./standings.js?v=22";

const KO_STAGES = ["r32", "r16", "qf", "sf", "final"];
const WD = ["日", "月", "火", "水", "木", "金", "土"];

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

// English slot label -> short Japanese (for still-unresolved R32 slots).
function jpLabel(label) {
  if (!label) return "未定";
  return label
    .replace(/Winner Group ([A-L])/, "$1組 1位")
    .replace(/Runner-up Group ([A-L])/, "$1組 2位")
    .replace(/3rd Group ([A-L/]+)/, "3位 ($1組)");
}

export function createBracket({ container, data }) {
  const isGroupLabel = (label) => label && /Group [A-L]/.test(label);

  // Japanese country name (teams.json `wiki` holds it), falling back to name.
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

  // Match date + kickoff, stacked: "6/30(火)" / "05:30".
  function fmtDT(m) {
    if (!m.date) return "";
    const d = new Date(m.date + "T00:00:00");
    const wd = isNaN(d) ? "" : WD[d.getDay()];
    const md = m.date.slice(5).replace("-", "/").replace(/^0/, "");
    const t = (m.time || "").match(/\d{1,2}:\d{2}/)?.[0] || "";
    return `${md}${wd ? `(${wd})` : ""}${t ? `<br>${t}` : ""}`;
  }

  function teamRow(code, label, picked) {
    const t = code ? data.byCode[code] : null;
    if (!t) {
      const tbd = isGroupLabel(label) ? jpLabel(label) : "勝者待ち";
      return `<div class="bk-team tbd"><div class="bk-line1"><span class="bk-tname">${esc(tbd)}</span></div></div>`;
    }
    const rank = t.rank ? ` <span class="bk-rank">(${t.rank}位)</span>` : "";
    const qual = qualText(code, label);
    return `<div class="bk-team${picked ? " picked" : ""}">
      <div class="bk-line1"><span class="bk-flag">${t.flag}</span><span class="bk-tname">${esc(t.wiki || t.name)}</span>${rank}</div>
      ${qual ? `<div class="bk-qual">${esc(qual)}</div>` : ""}
    </div>`;
  }

  function tieHtml(m, i, side, resolved) {
    const res = resolved.get(`r32:${i}`) || {};
    const home = res.home || null;
    const away = res.away || null;
    const win = res.winner || null;
    const teams = `<div class="bk-teams">
      ${teamRow(home, m.homeLabel, win && home === win)}
      ${teamRow(away, m.awayLabel, win && away === win)}
    </div>`;
    const time = `<div class="bk-time">${fmtDT(m)}</div>`;
    return `<div class="bk-tie" data-side="${side}" data-i="${i}">${
      side === "L" ? teams + time : time + teams
    }</div>`;
  }

  function render() {
    const predictor = createPredictor(data);
    const resolved = predictor.resolveKnockout(
      data.matches.filter((m) => KO_STAGES.includes(m.stage) || m.stage === "third")
    );

    const r32 = data.matches.filter((m) => m.stage === "r32");
    const left = r32.slice(0, 8);
    const right = r32.slice(8, 16);

    const leftHtml = left.map((m, i) => tieHtml(m, i, "L", resolved)).join("");
    const rightHtml = right.map((m, i) => tieHtml(m, i + 8, "R", resolved)).join("");

    // Predicted champion (winner of the final).
    const finalRes = resolved.get("final:0") || {};
    const champ = finalRes.winner || null;
    const finalOpp = champ ? (finalRes.home === champ ? finalRes.away : finalRes.home) : null;
    const info = champ ? predictor.championInfo(champ, finalOpp) : null;

    let calloutHtml = "";
    if (champ && info) {
      const chips = [
        `<span class="cr-chip">🥇 ${info.rankTxt}</span>`,
        `<span class="cr-chip">📊 ${info.formTxt}</span>`,
        info.oppCode && jpName(info.oppCode)
          ? `<span class="cr-chip">⚔️ 決勝で ${data.byCode[info.oppCode].flag} ${esc(jpName(info.oppCode))} を撃破</span>`
          : "",
      ].join("");
      calloutHtml = `<div class="champ-callout">
        <div class="cc-head">🏆 優勝予想</div>
        <div class="cc-team">${data.byCode[champ].flag} ${esc(jpName(champ))}</div>
        <div class="cc-reasons">${chips}</div>
        <div class="cc-note">FIFAランキング・本大会の成績・直接対戦から自動算出（暫定）</div>
      </div>`;
    }

    const champBox = `<div class="bk-champ">
      <div class="bk-trophy">🏆</div>
      <div class="bk-champ-label">優勝<br><small>(CHAMPION)</small></div>
      ${champ ? `<div class="bk-champ-team">${data.byCode[champ].flag} ${esc(jpName(champ))}</div>` : ""}
    </div>`;

    container.innerHTML = `
      <h2 class="section-title">🔮 優勝予想ブラケット <span class="sub">ラウンド32 → 決勝</span></h2>
      ${calloutHtml}
      <div class="bracket2-wrap"><div class="bracket2">
        <svg class="bk-lines" aria-hidden="true"></svg>
        <div class="bk-side left">${leftHtml}</div>
        <div class="bk-center">${champBox}</div>
        <div class="bk-side right">${rightHtml}</div>
      </div></div>
    `;

    requestAnimationFrame(drawLines);
  }

  // Right-angle connector between two points.
  function conn(x1, y1, x2, y2) {
    const mx = (x1 + x2) / 2;
    return `<path d="M${x1},${y1} H${mx} V${y2} H${x2}" class="conn"/>`;
  }

  // Fold the connector tree for the bracket: every R32 tie's inner edge folds
  // pairwise toward the champion in the centre.
  function drawLines() {
    const svg = container.querySelector(".bk-lines");
    const wrap = container.querySelector(".bracket2");
    const champEl = container.querySelector(".bk-champ");
    if (!svg || !wrap || !champEl) return;
    const base = wrap.getBoundingClientRect();
    svg.setAttribute("viewBox", `0 0 ${base.width} ${base.height}`);
    svg.setAttribute("width", base.width);
    svg.setAttribute("height", base.height);

    const cr = champEl.getBoundingClientRect();
    const champLeftX = cr.left - base.left;
    const champRightX = cr.right - base.left;
    const champY = cr.top - base.top + cr.height / 2;

    const collect = (side) =>
      [...container.querySelectorAll(`.bk-tie[data-side="${side}"]`)].map((t) => {
        const r = t.getBoundingClientRect();
        return {
          x: (side === "L" ? r.right : r.left) - base.left,
          y: r.top - base.top + r.height / 2,
        };
      });

    const lines = [];
    const fold = (pts, targetX, targetY) => {
      if (pts.length < 2) {
        if (pts[0]) lines.push(conn(pts[0].x, pts[0].y, targetX, targetY));
        return;
      }
      const innerX = pts[0].x;
      const folds = Math.round(Math.log2(pts.length));
      const span = targetX - innerX;
      let level = pts.map((p) => ({ ...p }));
      for (let f = 1; f <= folds; f++) {
        const px = innerX + (span * f) / folds;
        const next = [];
        for (let k = 0; k + 1 < level.length; k += 2) {
          const a = level[k], b = level[k + 1];
          const py = (a.y + b.y) / 2;
          lines.push(conn(a.x, a.y, px, py));
          lines.push(conn(b.x, b.y, px, py));
          next.push({ x: px, y: py });
        }
        level = next;
      }
      if (level[0]) lines.push(conn(level[0].x, level[0].y, targetX, targetY));
    };

    fold(collect("L"), champLeftX, champY);
    fold(collect("R"), champRightX, champY);
    svg.innerHTML = lines.join("");
  }

  if (typeof window !== "undefined") {
    window.addEventListener("resize", () => {
      if (container.querySelector(".bk-lines")) drawLines();
    });
  }

  return { render };
}
