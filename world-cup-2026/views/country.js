// Country detail view: squad list (number, position, name, age-less, club,
// caps/career goals) plus this tournament's goalscorers for the team.
// Squad data is fetched lazily from Wikipedia on first open and cached.

import { loadSquads, tournamentScorers, teamGoalsByPlayer, teamOwnGoals } from "./livedata.js?v=3";
import { fetchWiki } from "./wiki.js?v=3";

const POS_ORDER = { GK: 0, DF: 1, MF: 2, FW: 3 };
const POS_LABEL = { GK: "GK", DF: "DF", MF: "MF", FW: "FW" };
const CONFED_NAME = {
  UEFA: "欧州", CONMEBOL: "南米", CONCACAF: "北中米カリブ",
  CAF: "アフリカ", AFC: "アジア", OFC: "オセアニア", TBD: "未定",
};
// Teams highlighted with extra detail. Japan is highlighted per request; this
// only affects the ★ standout marker (all players with an article are
// clickable regardless).
const FULL_DETAIL_TEAMS = new Set(["JPN"]);

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

export function createCountry({ container, data, onBack }) {
  let code = null;
  let backLabel = "← 日程に戻る";

  function setTeam(teamCode, label) {
    code = teamCode;
    if (label) backLabel = label;
  }

  // Squads are fetched once and shared across views (cached in livedata.js).
  const ensureSquads = () => loadSquads(data.teams);

  // Deduplicated full-name -> goals map for the current team, set in render().
  // Each tournament goal is assigned to exactly one squad player.
  let goalsMap = {};
  const gp = (fullName) => goalsMap[fullName] || 0;

  const STAGE_LABEL = {
    group: "グループ", r32: "R32", r16: "R16", qf: "準々決勝",
    sf: "準決勝", third: "3位決定戦", final: "決勝",
  };

  function allTeamMatches() {
    return data.matches
      .filter((m) => m.home === code || m.away === code)
      .sort((a, b) => (a.date || "").localeCompare(b.date || ""));
  }

  function playedMatches() {
    return allTeamMatches().filter((m) => m.result);
  }

  function nextMatch() {
    return allTeamMatches().find((m) => !m.result);
  }

  function teamName(c) {
    const t = data.byCode[c];
    return t ? `${t.flag} ${t.name}` : "未定";
  }

  function nextMatchCard() {
    const m = nextMatch();
    if (!m) return "";
    const opp = m.home === code ? m.away : m.home;
    const oppTeam = data.byCode[opp];
    const venue = data.venueById[m.venue];
    const timeStr = m.time || "";
    return `<div class="card next-match-card" data-match-id="${m.id}" role="button" tabindex="0">
      <h3>📅 次の試合</h3>
      <div class="nm-teams">
        <span class="nm-team">${teamName(code)}</span>
        <span class="nm-vs">vs</span>
        <span class="nm-team">${oppTeam ? teamName(opp) : "未定"}</span>
      </div>
      <div class="nm-info">
        ${m.date ? `<span>${m.date}${timeStr ? ` ${timeStr}` : ""}</span>` : ""}
        ${venue ? `<span>${esc(venue.city)} · ${esc(venue.stadium)}</span>` : ""}
        <span>${STAGE_LABEL[m.stage] || ""}${m.group ? " " + m.group : ""}</span>
      </div>
    </div>`;
  }

  function resultsTable(matches) {
    if (!matches.length) return `<p class="sub">まだ試合結果がありません。</p>`;
    return `<div class="result-list">${matches
      .map((m) => {
        const isHome = m.home === code;
        const opp = isHome ? m.away : m.home;
        const [hs, as] = m.result;
        const my = isHome ? hs : as;
        const opGoals = isHome ? as : hs;
        const outcome = my > opGoals ? "win" : my < opGoals ? "loss" : "draw";
        const mark = outcome === "win" ? "○" : outcome === "loss" ? "●" : "△";
        const venue = data.venueById[m.venue];
        return `<div class="result-row ${outcome}" data-match-id="${m.id}" role="button" tabindex="0">
          <span class="r-mark">${mark}</span>
          <span class="r-stage">${STAGE_LABEL[m.stage] || ""}${m.group ? " " + m.group : ""}</span>
          <span class="r-opp">vs ${esc(teamName(opp))}</span>
          <span class="r-score">${my} - ${opGoals}</span>
          <span class="r-date">${m.date || ""}${venue ? " · " + esc(venue.city) : ""}</span>
        </div>`;
      })
      .join("")}</div>`;
  }

  function header(t) {
    return `<div class="country-head">
      <button class="btn" id="country-back">${esc(backLabel)}</button>
      <div class="country-title">
        <span class="c-flag">${t.flag}</span>
        <span class="c-name">${t.name}</span>
        <span class="c-meta">${CONFED_NAME[t.confed] || t.confed} · ${t.group}組${
      t.rank ? ` · FIFA ${t.rank}位` : ""
    }</span>
      </div>
    </div>`;
  }

  function scorerTable(players, ownGoals) {
    const byName = Object.fromEntries(players.map((p) => [p.name, p]));
    const rows = Object.entries(goalsMap)
      .map(([name, tg]) => ({ name, tg, player: byName[name] || null }))
      .sort((a, b) => b.tg - a.tg);

    if (!rows.length && !ownGoals) return `<p class="sub">本大会での得点はまだありません。</p>`;

    const scorerRows = rows
      .map(({ name, tg, player }) => {
        const nameHtml = player?.wiki
          ? `<span class="player-link" data-wiki="${esc(player.wiki)}" data-name="${esc(name)}" role="button" tabindex="0">${esc(name)} ★</span>`
          : esc(name);
        return `<div class="scorer-row">
          <span class="s-goals">${"⚽".repeat(Math.min(tg, 5))}${tg > 5 ? ` ×${tg}` : ""}</span>
          <span class="s-name">${nameHtml}</span>
          <span class="s-num">${tg}点</span>
        </div>`;
      })
      .join("");
    // Own goals the team benefited from — shown so the total matches the score.
    const ogRow = ownGoals
      ? `<div class="scorer-row">
          <span class="s-goals">${"⚽".repeat(Math.min(ownGoals, 5))}</span>
          <span class="s-name"><span class="og-label">相手オウンゴール</span></span>
          <span class="s-num">${ownGoals}点</span>
        </div>`
      : "";
    return `<div class="scorer-list">${scorerRows}${ogRow}</div>`;
  }

  // Render a player's name as a clickable popup link when they have a
  // Wikipedia article; players without one stay as plain text. A ★ marks
  // standout names (omitted for full-detail teams to avoid clutter).
  function playerName(p, tg) {
    if (!p.wiki) return esc(p.name);
    const standout =
      !FULL_DETAIL_TEAMS.has(code) && (p.goals >= 20 || p.caps >= 80 || (tg || 0) > 0);
    const star = standout ? " ★" : "";
    return `<span class="player-link" data-wiki="${esc(p.wiki)}" data-name="${esc(p.name)}" role="button" tabindex="0">${esc(p.name)}${star}</span>`;
  }

  function squadTable(players) {
    const sorted = [...players].sort(
      (a, b) => (POS_ORDER[a.pos] ?? 9) - (POS_ORDER[b.pos] ?? 9) || (a.no || 99) - (b.no || 99)
    );
    const rows = sorted
      .map(
        (p) => `<tr>
        <td class="p-no">${p.no ?? ""}</td>
        <td class="p-pos pos-${p.pos}">${POS_LABEL[p.pos] || p.pos}</td>
        <td class="p-name">${playerName(p, gp(p.name))}</td>
        <td class="p-club">${esc(p.club || "")}</td>
        <td class="p-num">${p.caps}</td>
        <td class="p-num">${p.goals}</td>
      </tr>`
      )
      .join("");
    return `<table class="squad-table">
      <thead><tr><th>#</th><th>位置</th><th>選手</th><th>所属クラブ</th><th title="代表通算出場">出場</th><th title="代表通算得点">得点</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>`;
  }

  async function render() {
    const t = data.byCode[code];
    if (!t) {
      container.innerHTML = `<p class="sub">チームが見つかりません。</p>`;
      return;
    }
    container.innerHTML = `
      ${header(t)}
      <div class="banner">出場メンバーと本大会の得点は Wikipedia から取得。出場・得点（右2列）は<b>代表通算</b>の数字です。</div>
      <div id="country-body"><p class="sub">選手データを読み込み中…</p></div>
    `;
    container.querySelector("#country-back").addEventListener("click", () => onBack());

    let squads;
    try {
      squads = await ensureSquads();
    } catch (e) {
      container.querySelector("#country-body").innerHTML =
        `<p class="sub">選手データの取得に失敗しました（ネット接続をご確認ください）。</p>`;
      return;
    }
    // guard: user may have navigated away
    if (data.byCode[code] !== t) return;

    const players = squads.byCode[code] || [];
    const teamScorers = tournamentScorers(data.matches)[code] || {};
    // Assign each scorer's goals to exactly one squad player (deduplicated).
    goalsMap = teamGoalsByPlayer(squads, code, teamScorers);
    const ownGoals = teamOwnGoals(data.matches)[code] || 0;
    // Total = players' goals + own goals benefited from, so it matches the
    // scoreline (e.g. USA scored 6: 5 by players + 1 own goal).
    const totalGoals = Object.values(teamScorers).reduce((a, b) => a + b, 0) + ownGoals;

    const body = container.querySelector("#country-body");
    if (!body) return;
    const results = playedMatches();
    body.innerHTML = `
      ${nextMatchCard()}
      <div class="country-grid">
        <div class="country-col">
          <div class="card">
            <h3>⚽ 本大会の得点 <span class="sub">${totalGoals}得点</span></h3>
            ${scorerTable(players, ownGoals)}
          </div>
          <div class="card">
            <h3>📋 試合結果 <span class="sub">${results.length}試合</span></h3>
            ${resultsTable(results)}
          </div>
        </div>
        <div class="card">
          <h3>👥 登録メンバー <span class="sub">${players.length}名</span></h3>
          ${players.length ? squadTable(players) : `<p class="sub">名簿データがありません。</p>`}
        </div>
      </div>
      <div id="player-modal" class="city-modal hidden">
        <div class="city-modal-backdrop"></div>
        <div class="city-modal-card">
          <button class="city-modal-close" aria-label="閉じる">✕</button>
          <div class="city-modal-body"></div>
        </div>
      </div>
    `;

    bindPlayerLinks();
  }

  // ---- player detail modal (reuses the .city-modal styles) ----
  let openWiki = null;

  function closePlayer() {
    openWiki = null;
    container.querySelector("#player-modal")?.classList.add("hidden");
  }
  function showPlayer(html) {
    const ov = container.querySelector("#player-modal");
    if (!ov) return;
    ov.querySelector(".city-modal-body").innerHTML = html;
    ov.classList.remove("hidden");
  }

  function playerCard(name, w, loading) {
    const img = w?.thumb
      ? `<img class="cm-img cm-img-portrait" src="${esc(w.thumb)}" alt="${esc(name)}" />`
      : `<div class="cm-img placeholder">${loading ? "🖼️ 読み込み中…" : "📷 写真なし"}</div>`;
    const text = w?.extract || "";
    const link = w?.pageUrl
      ? `<a class="popup-link" href="${esc(w.pageUrl)}" target="_blank" rel="noopener">Wikipediaで読む →</a>`
      : "";
    return `<div class="cm-card">
      <div class="cm-header"><span class="cm-flag">⭐</span>
        <div><div class="cm-title">${esc(name)}</div><div class="cm-sub">選手プロフィール</div></div>
      </div>
      <figure class="cm-photo cm-photo-single">${img}</figure>
      ${text ? `<p class="popup-text">${esc(text)}</p>` : `<p class="sub">${loading ? "" : "情報が見つかりませんでした。"}</p>`}
      <div class="cm-links">${link}</div>
    </div>`;
  }

  async function openPlayer(wiki, name) {
    openWiki = wiki;
    showPlayer(playerCard(name, null, true));
    const w = await fetchWiki(wiki, "en"); // player articles live on en.wikipedia
    if (openWiki === wiki) showPlayer(playerCard(name, w, false));
  }

  function bindPlayerLinks() {
    container.querySelectorAll(".player-link").forEach((el) => {
      const open = () => openPlayer(el.dataset.wiki, el.dataset.name);
      el.addEventListener("click", open);
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          open();
        }
      });
    });
    container.querySelector("#player-modal .city-modal-backdrop")?.addEventListener("click", closePlayer);
    container.querySelector("#player-modal .city-modal-close")?.addEventListener("click", closePlayer);
  }

  return { setTeam, render };
}
