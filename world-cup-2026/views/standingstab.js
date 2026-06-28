// Standings view: all 12 group tables collected in one dedicated tab.
// Standings are computed from played results (see standings.js). Clicking a
// team opens its country page (via the onTeam callback, like the other tabs).

import { groupStandings } from "./standings.js?v=24";

export function createStandings({ container, data, onTeam }) {
  function flagName(code) {
    const t = data.byCode[code];
    if (!t) return "";
    return `<span class="team-link" data-team="${code}" role="button" tabindex="0"><span class="flag">${t.flag}</span><span class="tname">${t.name}</span></span>`;
  }

  // Determine which teams have qualified for R32.
  // Top 2 per group + best 8 third-place teams advance.
  // A team is "confirmed" only when all 3 group matches are played.
  function qualifiedTeams() {
    const groupKeys = Object.keys(data.groups);
    const qualified = new Set();
    const thirdPlace = [];

    for (const g of groupKeys) {
      const standing = groupStandings(data, g);
      const allPlayed = standing.every((r) => r.pld === 3);
      if (!allPlayed) continue;
      if (standing[0]) qualified.add(standing[0].code);
      if (standing[1]) qualified.add(standing[1].code);
      if (standing[2]) thirdPlace.push(standing[2]);
    }

    // Best 8 third-place teams qualify (same tiebreaker: pts, gd, gf)
    thirdPlace
      .sort((a, b) => b.pts - a.pts || b.gd - a.gd || b.gf - a.gf)
      .slice(0, 8)
      .forEach((r) => qualified.add(r.code));

    return qualified;
  }

  function groupCard(groupKey) {
    const qualified = qualifiedTeams();
    const rows = groupStandings(data, groupKey)
      .map(
        (r, i) => {
          const isQual = qualified.has(r.code);
          return `<tr class="${isQual ? "r32-qualified" : ""} ${i < 2 ? "" : ""}">
          <td class="team ${i < 2 ? "qual" : ""}">${flagName(r.code)}</td>
          <td>${r.pld}</td><td>${r.w}</td><td>${r.d}</td><td>${r.l}</td>
          <td>${r.gd > 0 ? "+" : ""}${r.gd}</td><td><strong>${r.pts}</strong></td>
        </tr>`;
        }
      )
      .join("");
    return `<div class="group-card">
      <h3>グループ ${groupKey}</h3>
      <table class="standings">
        <tr><th>チーム</th><th>試</th><th>勝</th><th>分</th><th>負</th><th>差</th><th>点</th></tr>
        ${rows}
      </table>
    </div>`;
  }

  function render() {
    const groupKeys = Object.keys(data.groups);
    container.innerHTML = `
      <h2 class="section-title">📊 順位表 <span class="sub">グループステージ</span></h2>
      <div class="banner">順位表はスコアから自動集計。各組の上位2チーム（＋各組3位の上位8チーム）が決勝トーナメントに進出。緑のラインは突破圏内。</div>
      <div class="groups-grid">${groupKeys.map(groupCard).join("")}</div>
    `;
    // Clicking a team opens its country page (owned by the schedule view).
    container.querySelectorAll(".team-link").forEach((el) => {
      el.addEventListener("click", () => onTeam?.(el.dataset.team));
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          onTeam?.(el.dataset.team);
        }
      });
    });
  }

  return { render };
}
