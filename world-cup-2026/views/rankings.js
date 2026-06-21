// Rankings view: tournament goalscorer ranking, aggregated from match data.
//
// Assists are intentionally NOT shown: Wikipedia's match data records only
// scorers (name + minute), with no assist information, so an assist ranking
// can't be built without fabricating it. The view notes this explicitly.

import { goalRanking, loadSquads, resolvePlayer } from "./livedata.js?v=2";

export function createRankings({ container, data, onTeam }) {
  let squads = null; // filled in asynchronously; enables full-name display
  function teamCell(code) {
    const t = data.byCode[code];
    if (!t) return code || "";
    return `<span class="team-link" data-team="${code}" role="button" tabindex="0">
      <span class="flag">${t.flag}</span>${t.name}</span>`;
  }

  // Player name cell. Once squads are loaded, a player matched to a Wikipedia
  // article becomes a clickable link to that article (opens in a new tab).
  // Unmatched players (no squad/article) stay as plain text.
  function nameCell(scorer, code) {
    if (!squads) return scorer;
    const p = resolvePlayer(squads, code, scorer);
    if (!p) return scorer;
    if (!p.wiki) return p.name;
    const url = `https://en.wikipedia.org/wiki/${encodeURIComponent(p.wiki.replace(/ /g, "_"))}`;
    return `<a class="player-link" href="${url}" target="_blank" rel="noopener">${p.name} ↗</a>`;
  }

  // Group rows by goal count so ties share a rank number.
  function rankedRows(rows) {
    let lastGoals = null;
    let rank = 0;
    return rows.map((r, idx) => {
      if (r.goals !== lastGoals) {
        rank = idx + 1;
        lastGoals = r.goals;
      }
      return { ...r, rank };
    });
  }

  function render() {
    const ranking = rankedRows(goalRanking(data.matches));
    const totalGoals = ranking.reduce((a, b) => a + b.goals, 0);

    const body = ranking.length
      ? `<table class="rank-table">
          <thead><tr><th>#</th><th>選手</th><th>代表</th><th>得点</th></tr></thead>
          <tbody>${ranking
            .map(
              (r) => `<tr>
              <td class="r-rank">${r.rank}</td>
              <td class="r-name">${nameCell(r.name, r.code)}</td>
              <td class="r-team">${teamCell(r.code)}</td>
              <td class="r-goals"><span class="goal-bar" style="--g:${r.goals}"></span>${r.goals}</td>
            </tr>`
            )
            .join("")}</tbody>
        </table>`
      : `<p class="sub">まだ得点がありません。</p>`;

    container.innerHTML = `
      <h2 class="section-title">🥇 得点ランキング <span class="sub">${ranking.length}選手 / ${totalGoals}得点</span></h2>
      <div class="banner">本大会の得点を Wikipedia の試合データから集計（${data.asOf || "—"} 時点）。選手名（リンク付き ↗）をクリックすると選手の Wikipedia ページへ、代表名をクリックすると国ページへ。<br>※ アシスト・出場時間などは Wikipedia の試合データに無いため、得点のみのランキングです。オウンゴールは加算していません。</div>
      <div class="rank-wrap card">${body}</div>
    `;

    container.querySelectorAll(".team-link").forEach((el) => {
      const open = () => onTeam?.(el.dataset.team);
      el.addEventListener("click", open);
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          open();
        }
      });
    });

    // Lazily load squads to upgrade surnames -> full names, then re-render once.
    if (!squads) {
      loadSquads(data.teams)
        .then((s) => {
          squads = s;
          render();
        })
        .catch(() => {});
    }
  }

  return { render };
}
