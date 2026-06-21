// Rankings view: tournament goalscorer ranking, aggregated from match data.
// Top 10 displayed. Player names open a centered modal with Wikipedia data.

import { goalRanking, loadSquads, resolvePlayer } from "./livedata.js?v=3";
import { fetchWiki } from "./wiki.js?v=3";

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

export function createRankings({ container, data, onTeam }) {
  let squads = null;
  let openWiki = null;

  function teamCell(code) {
    const t = data.byCode[code];
    if (!t) return code || "";
    return `<span class="team-link" data-team="${code}" role="button" tabindex="0">
      <span class="flag">${t.flag}</span>${t.name}</span>`;
  }

  function nameCell(scorer, code) {
    if (!squads) return esc(scorer);
    const p = resolvePlayer(squads, code, scorer);
    if (!p) return esc(scorer);
    if (!p.wiki) return esc(p.name);
    return `<span class="player-link" data-wiki="${esc(p.wiki)}" data-name="${esc(p.name)}" data-code="${esc(code)}" role="button" tabindex="0">${esc(p.name)}</span>`;
  }

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

  // --- Player modal ---
  function closePlayer() {
    openWiki = null;
    container.querySelector("#player-modal-rankings")?.classList.add("hidden");
  }

  function showPlayer(html) {
    const ov = container.querySelector("#player-modal-rankings");
    if (!ov) return;
    ov.querySelector(".city-modal-body").innerHTML = html;
    ov.classList.remove("hidden");
  }

  function playerCard(name, code, goals, w, loading) {
    const t = data.byCode[code];
    const flag = t ? t.flag : "🏳️";
    const teamName = t ? t.name : code;
    const img = w?.thumb
      ? `<img class="cm-img cm-img-portrait" src="${esc(w.thumb)}" alt="${esc(name)}" />`
      : `<div class="cm-img placeholder">${loading ? "🖼️ 読み込み中…" : "📷 写真なし"}</div>`;
    const text = w?.extract || "";
    const link = w?.pageUrl
      ? `<a class="popup-link" href="${esc(w.pageUrl)}" target="_blank" rel="noopener">Wikipediaで読む →</a>`
      : "";
    return `<div class="cm-card">
      <div class="cm-header"><span class="cm-flag">${flag}</span>
        <div><div class="cm-title">${esc(name)}</div><div class="cm-sub">${esc(teamName)} · ${goals}得点</div></div>
      </div>
      <figure class="cm-photo cm-photo-single">${img}</figure>
      ${text ? `<p class="popup-text">${esc(text)}</p>` : `<p class="sub">${loading ? "" : "情報が見つかりませんでした。"}</p>`}
      <div class="cm-links">${link}</div>
    </div>`;
  }

  async function openPlayer(wiki, name, code, goals) {
    openWiki = wiki;
    showPlayer(playerCard(name, code, goals, null, true));
    const w = await fetchWiki(wiki, "en");
    if (openWiki === wiki) showPlayer(playerCard(name, code, goals, w, false));
  }

  function bindEvents() {
    container.querySelectorAll(".team-link").forEach((el) => {
      const open = () => onTeam?.(el.dataset.team);
      el.addEventListener("click", open);
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); open(); }
      });
    });

    container.querySelectorAll(".player-link").forEach((el) => {
      const open = () => {
        const row = el.closest("tr");
        const goalsCell = row?.querySelector(".r-goals");
        const goals = goalsCell ? parseInt(goalsCell.textContent) || 0 : 0;
        openPlayer(el.dataset.wiki, el.dataset.name, el.dataset.code, goals);
      };
      el.addEventListener("click", open);
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); open(); }
      });
    });

    container.querySelector("#player-modal-rankings .city-modal-backdrop")?.addEventListener("click", closePlayer);
    container.querySelector("#player-modal-rankings .city-modal-close")?.addEventListener("click", closePlayer);
  }

  function render() {
    const ranking = rankedRows(goalRanking(data.matches));
    const top10 = ranking.filter((r) => r.rank <= 10);
    const totalGoals = ranking.reduce((a, b) => a + b.goals, 0);

    const body = top10.length
      ? `<table class="rank-table">
          <thead><tr><th>#</th><th>選手</th><th>代表</th><th>得点</th></tr></thead>
          <tbody>${top10
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
      <h2 class="section-title">🥇 得点ランキング TOP10 <span class="sub">${ranking.length}選手 / ${totalGoals}得点</span></h2>
      <div class="banner">本大会の得点を試合データから集計（${data.asOf || "—"} 時点）。選手名をクリックするとプロフィールを表示、代表名をクリックすると国ページへ。<br>※ オウンゴールは加算していません。</div>
      <div class="rank-wrap card">${body}</div>
      <div id="player-modal-rankings" class="city-modal hidden">
        <div class="city-modal-backdrop"></div>
        <div class="city-modal-card">
          <button class="city-modal-close" aria-label="閉じる">✕</button>
          <div class="city-modal-body"></div>
        </div>
      </div>
    `;

    bindEvents();

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
