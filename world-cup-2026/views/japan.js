import { groupStandings } from "./standings.js?v=3";
import { loadSquads, tournamentScorers, teamGoalsByPlayer, teamOwnGoals } from "./livedata.js?v=3";
import { fetchWiki } from "./wiki.js?v=3";

const CODE = "JPN";
const POS_ORDER = { GK: 0, DF: 1, MF: 2, FW: 3 };
const POS_LABEL = { GK: "GK", DF: "DF", MF: "MF", FW: "FW" };
const STAGE_LABEL = {
  group: "グループ", r32: "R32", r16: "R16", qf: "準々決勝",
  sf: "準決勝", third: "3位決定戦", final: "決勝",
};

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

export function createJapan({ container, data }) {
  let goalsMap = {};
  let countdownInterval = null;

  function teamMatches() {
    return data.matches
      .filter((m) => m.home === CODE || m.away === CODE)
      .sort((a, b) => (a.date || "").localeCompare(b.date || ""));
  }

  function playedMatches() {
    return teamMatches().filter((m) => m.result);
  }

  function nextMatch() {
    return teamMatches().find((m) => !m.result);
  }

  function teamName(c) {
    const t = data.byCode[c];
    return t ? `${t.flag} ${t.name}` : "未定";
  }

  function countdownHtml(m) {
    if (!m || !m.date) return "";
    const opp = m.home === CODE ? m.away : m.home;
    const oppTeam = data.byCode[opp];
    const venue = data.venueById[m.venue];
    return `<div class="japan-countdown" id="japan-countdown">
      <div class="jc-label">次の試合まで</div>
      <div class="jc-timer" id="jc-timer">--:--:--:--</div>
      <div class="jc-match">
        <span class="jc-team">🇯🇵 Japan</span>
        <span class="jc-vs">vs</span>
        <span class="jc-team">${oppTeam ? oppTeam.flag + " " + oppTeam.name : "未定"}</span>
      </div>
      <div class="jc-info">${m.date}${venue ? " · " + esc(venue.city) + " · " + esc(venue.stadium) : ""}</div>
    </div>`;
  }

  function startCountdown(m) {
    if (countdownInterval) clearInterval(countdownInterval);
    if (!m || !m.date) return;
    const target = new Date(m.date + "T00:00:00Z");
    function tick() {
      const el = document.getElementById("jc-timer");
      if (!el) { clearInterval(countdownInterval); return; }
      const now = new Date();
      const diff = target - now;
      if (diff <= 0) { el.textContent = "試合日！"; clearInterval(countdownInterval); return; }
      const d = Math.floor(diff / 86400000);
      const h = Math.floor((diff % 86400000) / 3600000);
      const min = Math.floor((diff % 3600000) / 60000);
      const s = Math.floor((diff % 60000) / 1000);
      const p = (n) => String(n).padStart(2, "0");
      el.textContent = `${d}日 ${p(h)}:${p(min)}:${p(s)}`;
    }
    tick();
    countdownInterval = setInterval(tick, 1000);
  }

  function standingsCard() {
    const t = data.byCode[CODE];
    if (!t) return "";
    const groupKey = t.group;
    const standing = groupStandings(data, groupKey);
    const rows = standing
      .map((r, i) => {
        const isJpn = r.code === CODE;
        return `<tr class="${isJpn ? "japan-row" : ""}">
          <td class="team ${i < 2 ? "qual" : ""}">${teamName(r.code)}</td>
          <td>${r.pld}</td><td>${r.w}</td><td>${r.d}</td><td>${r.l}</td>
          <td>${r.gd > 0 ? "+" : ""}${r.gd}</td><td><strong>${r.pts}</strong></td>
        </tr>`;
      })
      .join("");
    return `<div class="group-card japan-group-card">
      <h3>グループ ${groupKey}</h3>
      <table class="standings">
        <tr><th>チーム</th><th>試</th><th>勝</th><th>分</th><th>負</th><th>差</th><th>点</th></tr>
        ${rows}
      </table>
    </div>`;
  }

  function matchesCard() {
    const all = teamMatches();
    return `<div class="japan-matches">
      <h3>📋 全試合日程・結果</h3>
      <div class="japan-match-list">${all.map((m) => {
        const isHome = m.home === CODE;
        const opp = isHome ? m.away : m.home;
        const played = Array.isArray(m.result);
        const venue = data.venueById[m.venue];

        if (!played) {
          return `<div class="japan-match-card upcoming" data-match-id="${m.id}" role="button" tabindex="0">
            <div class="jm-date">${m.date || "未定"}</div>
            <div class="jm-teams">
              <span class="jm-team">${teamName(m.home)}</span>
              <span class="jm-vs">vs</span>
              <span class="jm-team">${teamName(m.away)}</span>
            </div>
            <div class="jm-venue">${venue ? esc(venue.city) + " · " + esc(venue.stadium) : ""}</div>
            <div class="jm-status">未実施</div>
          </div>`;
        }

        const [hs, as] = m.result;
        const my = isHome ? hs : as;
        const opGoals = isHome ? as : hs;
        const outcome = my > opGoals ? "win" : my < opGoals ? "loss" : "draw";
        const outcomeLabel = outcome === "win" ? "勝ち" : outcome === "loss" ? "負け" : "引き分け";
        return `<div class="japan-match-card ${outcome}" data-match-id="${m.id}" role="button" tabindex="0">
          <div class="jm-date">${m.date || ""}</div>
          <div class="jm-teams">
            <span class="jm-team">${teamName(m.home)}</span>
            <span class="jm-score">${hs} - ${as}</span>
            <span class="jm-team">${teamName(m.away)}</span>
          </div>
          <div class="jm-venue">${venue ? esc(venue.city) : ""}</div>
          <div class="jm-result-label ${outcome}">${outcomeLabel}</div>
        </div>`;
      }).join("")}</div>
    </div>`;
  }

  function scorerSection(players) {
    const entries = Object.entries(goalsMap)
      .sort((a, b) => b[1] - a[1]);
    if (!entries.length) return `<p class="sub">本大会での得点はまだありません。</p>`;
    return `<div class="scorer-list">${entries.map(([name, tg]) => {
      const p = players.find((pl) => pl.name === name);
      const nameHtml = p?.wiki
        ? `<span class="player-link" data-wiki="${esc(p.wiki)}" data-name="${esc(name)}" role="button" tabindex="0">${esc(name)}</span>`
        : esc(name);
      return `<div class="scorer-row">
        <span class="s-goals">${"⚽".repeat(Math.min(tg, 5))}${tg > 5 ? ` ×${tg}` : ""}</span>
        <span class="s-name">${nameHtml}</span>
        <span class="s-num">${tg}点</span>
      </div>`;
    }).join("")}</div>`;
  }

  function squadTable(players) {
    const sorted = [...players].sort(
      (a, b) => (POS_ORDER[a.pos] ?? 9) - (POS_ORDER[b.pos] ?? 9) || (a.no || 99) - (b.no || 99)
    );
    const rows = sorted
      .map((p) => {
        const tg = goalsMap[p.name] || 0;
        const nameHtml = p.wiki
          ? `<span class="player-link" data-wiki="${esc(p.wiki)}" data-name="${esc(p.name)}" role="button" tabindex="0">${esc(p.name)}</span>`
          : esc(p.name);
        return `<tr>
          <td class="p-no">${p.no ?? ""}</td>
          <td class="p-pos pos-${p.pos}">${POS_LABEL[p.pos] || p.pos}</td>
          <td class="p-name">${nameHtml}</td>
          <td class="p-club">${esc(p.club || "")}</td>
          <td class="p-num">${p.caps}</td>
          <td class="p-num">${p.goals}${tg ? ` <span style="color:var(--accent)">(+${tg})</span>` : ""}</td>
        </tr>`;
      })
      .join("");
    return `<table class="squad-table">
      <thead><tr><th>#</th><th>位置</th><th>選手</th><th>所属クラブ</th><th>出場</th><th>得点</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>`;
  }

  async function render() {
    const t = data.byCode[CODE];
    if (!t) {
      container.innerHTML = `<p class="sub">日本代表のデータが見つかりません。</p>`;
      return;
    }

    const next = nextMatch();
    const played = playedMatches();
    const totalPlayed = played.length;
    const wins = played.filter((m) => {
      const [hs, as] = m.result;
      const my = m.home === CODE ? hs : as;
      const op = m.home === CODE ? as : hs;
      return my > op;
    }).length;
    const draws = played.filter((m) => m.result[0] === m.result[1]).length;
    const losses = totalPlayed - wins - draws;

    container.innerHTML = `
      <div class="japan-page">
        <div class="japan-header">
          <span class="japan-flag">🇯🇵</span>
          <div>
            <h2 class="japan-title">日本代表</h2>
            <div class="japan-meta">FIFA ${t.rank}位 · ${t.group}組 · アジア (AFC)</div>
          </div>
          <div class="japan-stats">
            <div class="japan-stat"><span class="js-num">${totalPlayed}</span><span class="js-label">試合</span></div>
            <div class="japan-stat win"><span class="js-num">${wins}</span><span class="js-label">勝</span></div>
            <div class="japan-stat draw"><span class="js-num">${draws}</span><span class="js-label">分</span></div>
            <div class="japan-stat loss"><span class="js-num">${losses}</span><span class="js-label">負</span></div>
          </div>
        </div>
        ${countdownHtml(next)}
        <div class="japan-grid">
          <div class="japan-col">
            ${standingsCard()}
            ${matchesCard()}
          </div>
          <div class="japan-col">
            <div class="japan-section">
              <h3>⚽ 本大会の得点者</h3>
              <div id="japan-scorers"><p class="sub">読み込み中…</p></div>
            </div>
            <div class="japan-section">
              <h3>👥 登録メンバー <span class="sub" id="japan-squad-count"></span></h3>
              <div id="japan-squad"><p class="sub">選手データを読み込み中…</p></div>
            </div>
          </div>
        </div>
      </div>
      <div id="player-modal-japan" class="city-modal hidden">
        <div class="city-modal-backdrop"></div>
        <div class="city-modal-card">
          <button class="city-modal-close" aria-label="閉じる">✕</button>
          <div class="city-modal-body"></div>
        </div>
      </div>
    `;

    startCountdown(next);

    let squads;
    try {
      squads = await loadSquads(data.teams);
    } catch (e) {
      const el = container.querySelector("#japan-squad");
      if (el) el.innerHTML = `<p class="sub">選手データの取得に失敗しました。</p>`;
      return;
    }

    const players = squads.byCode[CODE] || [];
    const teamScorers = tournamentScorers(data.matches)[CODE] || {};
    goalsMap = teamGoalsByPlayer(squads, CODE, teamScorers);
    const ownGoals = teamOwnGoals(data.matches)[CODE] || 0;

    const scorersEl = container.querySelector("#japan-scorers");
    if (scorersEl) scorersEl.innerHTML = scorerSection(players);

    const squadEl = container.querySelector("#japan-squad");
    const countEl = container.querySelector("#japan-squad-count");
    if (squadEl) squadEl.innerHTML = players.length ? squadTable(players) : `<p class="sub">名簿データがありません。</p>`;
    if (countEl) countEl.textContent = players.length ? `${players.length}名` : "";

    bindPlayerLinks();
  }

  let openWiki = null;

  function closePlayer() {
    openWiki = null;
    container.querySelector("#player-modal-japan")?.classList.add("hidden");
  }

  function showPlayer(html) {
    const ov = container.querySelector("#player-modal-japan");
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
      <div class="cm-header"><span class="cm-flag">🇯🇵</span>
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
    const w = await fetchWiki(wiki, "en");
    if (openWiki === wiki) showPlayer(playerCard(name, w, false));
  }

  function bindPlayerLinks() {
    container.querySelectorAll(".player-link").forEach((el) => {
      const open = () => openPlayer(el.dataset.wiki, el.dataset.name);
      el.addEventListener("click", open);
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); open(); }
      });
    });
    container.querySelector("#player-modal-japan .city-modal-backdrop")?.addEventListener("click", closePlayer);
    container.querySelector("#player-modal-japan .city-modal-close")?.addEventListener("click", closePlayer);
  }

  return { render };
}
