import { groupStandings } from "./standings.js?v=25";
import { loadSquads, tournamentScorers, teamGoalsByPlayer, teamOwnGoals } from "./livedata.js?v=25";
import { fetchWiki, fetchPlayerInfo, renderPlayerInfoHtml } from "./wiki.js?v=25";
import { localHM, localYMD } from "./util.js?v=25";

const POS_ORDER = { GK: 0, DF: 1, MF: 2, FW: 3 };
const POS_LABEL = { GK: "GK", DF: "DF", MF: "MF", FW: "FW" };
const CONFED_NAME = {
  UEFA: "欧州", CONMEBOL: "南米", CONCACAF: "北中米カリブ",
  CAF: "アフリカ", AFC: "アジア", OFC: "オセアニア", TBD: "未定",
};
const STAGE_LABEL = {
  group: "グループ", r32: "R32", r16: "R16", qf: "準々決勝",
  sf: "準決勝", third: "3位決定戦", final: "決勝",
};

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

export function createCountry({ container, data, onBack }) {
  let code = null;
  let backLabel = "← 日程に戻る";
  let goalsMap = {};
  let countdownInterval = null;

  function setTeam(teamCode, label) {
    code = teamCode;
    if (label) backLabel = label;
  }

  function teamMatches() {
    return data.matches
      .filter((m) => m.home === code || m.away === code)
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
    const t = data.byCode[code];
    const opp = m.home === code ? m.away : m.home;
    const oppTeam = data.byCode[opp];
    const venue = data.venueById[m.venue];
    const stageText = STAGE_LABEL[m.stage] || "";
    const hm = localHM(m);
    const timeStr = hm ? ` ${hm}` : "";
    return `<div class="japan-countdown" id="country-countdown" data-match-id="${m.id}" role="button" tabindex="0">
      <div class="jc-label">次の試合まで</div>
      <div class="jc-timer" id="cc-timer">--:--:--:--</div>
      <div class="jc-match">
        <span class="jc-team">${t ? t.flag + " " + t.name : code}</span>
        <span class="jc-vs">vs</span>
        <span class="jc-team">${oppTeam ? oppTeam.flag + " " + oppTeam.name : "未定"}</span>
      </div>
      <div class="jc-info">${localYMD(m)}${timeStr}${venue ? " · " + esc(venue.city) + " · " + esc(venue.stadium) : ""}${stageText ? " · " + stageText : ""}${m.group ? " " + m.group : ""}</div>
    </div>`;
  }

  function startCountdown(m) {
    if (countdownInterval) clearInterval(countdownInterval);
    if (!m || !m.date) return;
    const target = m.kickoff ? new Date(m.kickoff) : new Date(m.date + "T00:00:00");
    function tick() {
      const el = container.querySelector("#cc-timer");
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
    const t = data.byCode[code];
    if (!t || !t.group) return "";
    const groupKey = t.group;
    const standing = groupStandings(data, groupKey);
    if (!standing.length) return "";
    const rows = standing
      .map((r, i) => {
        const isCurrent = r.code === code;
        return `<tr class="${isCurrent ? "japan-row" : ""}">
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

  // One match card — an upcoming fixture or a played result.
  function matchCardHtml(m) {
    const isHome = m.home === code;
    const played = Array.isArray(m.result);
    const venue = data.venueById[m.venue];
    const timeStr = localHM(m);
    const dateStr = localYMD(m);
    const left = isHome ? m.home : m.away;
    const right = isHome ? m.away : m.home;
    if (!played) {
      return `<div class="japan-match-card upcoming" data-match-id="${m.id}" role="button" tabindex="0">
        <div class="jm-date">${dateStr || "未定"}${timeStr ? ` ${timeStr}` : ""}</div>
        <div class="jm-teams">
          <span class="jm-team">${teamName(left)}</span>
          <span class="jm-vs">vs</span>
          <span class="jm-team">${teamName(right)}</span>
        </div>
        <div class="jm-venue">${venue ? esc(venue.city) + " · " + esc(venue.stadium) : ""}</div>
        <div class="jm-status">未実施</div>
      </div>`;
    }
    const [hs, as] = m.result;
    const myGoals = isHome ? hs : as;
    const opGoals = isHome ? as : hs;
    const outcome = myGoals > opGoals ? "win" : myGoals < opGoals ? "loss" : "draw";
    const outcomeLabel = outcome === "win" ? "勝ち" : outcome === "loss" ? "負け" : "引き分け";
    return `<div class="japan-match-card ${outcome}" data-match-id="${m.id}" role="button" tabindex="0">
      <div class="jm-date">${dateStr || ""}${timeStr ? ` ${timeStr}` : ""}</div>
      <div class="jm-teams">
        <span class="jm-team">${teamName(left)}</span>
        <span class="jm-score">${myGoals} - ${opGoals}</span>
        <span class="jm-team">${teamName(right)}</span>
      </div>
      <div class="jm-venue">${venue ? esc(venue.city) : ""}</div>
      <div class="jm-result-label ${outcome}">${outcomeLabel}</div>
    </div>`;
  }

  // Split into 日程 (upcoming, on top) and 結果 (played, below).
  function matchesCard() {
    const all = teamMatches();
    const upcoming = all.filter((m) => !Array.isArray(m.result));
    const results = all.filter((m) => Array.isArray(m.result));
    const section = (title, list, emptyMsg) =>
      `<h3>${title}</h3>` +
      (list.length
        ? `<div class="japan-match-list">${list.map(matchCardHtml).join("")}</div>`
        : `<p class="sub">${emptyMsg}</p>`);
    return `<div class="japan-matches">
      ${section("📅 日程（今後の試合）", upcoming, "今後の試合はありません。")}
      ${section("✅ これまでの結果", results, "まだ結果がありません。")}
    </div>`;
  }

  function scorerSection(players, ownGoals) {
    const entries = Object.entries(goalsMap).sort((a, b) => b[1] - a[1]);
    if (!entries.length && !ownGoals) return `<p class="sub">本大会での得点はまだありません。</p>`;
    const scorerRows = entries.map(([name, tg]) => {
      const p = players.find((pl) => pl.name === name);
      const nameHtml = p?.wiki
        ? `<span class="player-link" data-wiki="${esc(p.wiki)}" data-name="${esc(name)}" role="button" tabindex="0">${esc(name)}</span>`
        : esc(name);
      return `<div class="scorer-row">
        <span class="s-goals">${"⚽".repeat(Math.min(tg, 5))}${tg > 5 ? ` ×${tg}` : ""}</span>
        <span class="s-name">${nameHtml}</span>
        <span class="s-num">${tg}点</span>
      </div>`;
    }).join("");
    const ogRow = ownGoals
      ? `<div class="scorer-row">
          <span class="s-goals">${"⚽".repeat(Math.min(ownGoals, 5))}</span>
          <span class="s-name"><span class="og-label">相手オウンゴール</span></span>
          <span class="s-num">${ownGoals}点</span>
        </div>`
      : "";
    return `<div class="scorer-list">${scorerRows}${ogRow}</div>`;
  }

  function squadTable(players) {
    const sorted = [...players].sort(
      (a, b) => (POS_ORDER[a.pos] ?? 9) - (POS_ORDER[b.pos] ?? 9) || (a.no || 99) - (b.no || 99)
    );
    const rows = sorted.map((p) => {
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
    }).join("");
    return `<table class="squad-table">
      <thead><tr><th>#</th><th>位置</th><th>選手</th><th>所属クラブ</th><th>出場</th><th>得点</th></tr></thead>
      <tbody>${rows}</tbody>
    </table>`;
  }

  async function render() {
    const t = data.byCode[code];
    if (!t) {
      container.innerHTML = `<p class="sub">チームが見つかりません。</p>`;
      return;
    }

    const next = nextMatch();
    const played = playedMatches();
    const wins = played.filter((m) => {
      const [hs, as] = m.result;
      const my = m.home === code ? hs : as;
      const op = m.home === code ? as : hs;
      return my > op;
    }).length;
    const draws = played.filter((m) => m.result[0] === m.result[1]).length;
    const losses = played.length - wins - draws;

    container.innerHTML = `
      <div class="japan-page">
        ${onBack ? `<button class="btn" id="country-back">${esc(backLabel)}</button>` : ""}
        <div class="japan-header">
          <span class="japan-flag">${t.flag}</span>
          <div>
            <h2 class="japan-title">${esc(t.name)}</h2>
            <div class="japan-meta">FIFA ${t.rank || "—"}位 · ${t.group || "—"}組 · ${CONFED_NAME[t.confed] || t.confed}</div>
          </div>
          <div class="japan-stats">
            <div class="japan-stat"><span class="js-num">${played.length}</span><span class="js-label">試合</span></div>
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
              <div id="country-scorers"><p class="sub">読み込み中…</p></div>
            </div>
            <div class="japan-section">
              <h3>👥 登録メンバー <span class="sub" id="country-squad-count"></span></h3>
              <div id="country-squad"><p class="sub">選手データを読み込み中…</p></div>
            </div>
          </div>
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

    if (onBack) container.querySelector("#country-back")?.addEventListener("click", () => onBack());
    startCountdown(next);

    let squads;
    try {
      squads = await loadSquads(data.teams);
    } catch (e) {
      const el = container.querySelector("#country-squad");
      if (el) el.innerHTML = `<p class="sub">選手データの取得に失敗しました。</p>`;
      return;
    }
    if (data.byCode[code] !== t) return;

    const players = squads.byCode[code] || [];
    const teamScorers = tournamentScorers(data.matches)[code] || {};
    goalsMap = teamGoalsByPlayer(squads, code, teamScorers);
    const ownGoals = teamOwnGoals(data.matches)[code] || 0;

    const scorersEl = container.querySelector("#country-scorers");
    if (scorersEl) scorersEl.innerHTML = scorerSection(players, ownGoals);

    const squadEl = container.querySelector("#country-squad");
    const countEl = container.querySelector("#country-squad-count");
    if (squadEl) squadEl.innerHTML = players.length ? squadTable(players) : `<p class="sub">名簿データがありません。</p>`;
    if (countEl) countEl.textContent = players.length ? `${players.length}名` : "";

    bindPlayerLinks();
  }

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

  function playerCard(name, w, info, loading) {
    const t = data.byCode[code];
    const flag = t ? t.flag : "⭐";
    const img = w?.thumb
      ? `<img class="cm-img cm-img-portrait" src="${esc(w.thumb)}" alt="${esc(name)}" />`
      : `<div class="cm-img placeholder">${loading ? "🖼️ 読み込み中…" : "📷 写真なし"}</div>`;
    const text = w?.extract || "";
    const link = w?.pageUrl
      ? `<a class="popup-link" href="${esc(w.pageUrl)}" target="_blank" rel="noopener">Wikipediaで読む →</a>`
      : "";
    return `<div class="cm-card">
      <div class="cm-header"><span class="cm-flag">${flag}</span>
        <div><div class="cm-title">${esc(name)}</div><div class="cm-sub">選手プロフィール</div></div>
      </div>
      <figure class="cm-photo cm-photo-single">${img}</figure>
      ${text ? `<p class="popup-text">${esc(text)}</p>` : `<p class="sub">${loading ? "" : "情報が見つかりませんでした。"}</p>`}
      ${renderPlayerInfoHtml(info)}
      <div class="cm-links">${link}</div>
    </div>`;
  }

  async function openPlayer(wiki, name) {
    openWiki = wiki;
    showPlayer(playerCard(name, null, null, true));
    const [w, info] = await Promise.all([fetchWiki(wiki, "en"), fetchPlayerInfo(wiki, "en")]);
    if (openWiki === wiki) showPlayer(playerCard(name, w, info, false));
  }

  function bindPlayerLinks() {
    container.querySelectorAll(".player-link").forEach((el) => {
      const open = () => openPlayer(el.dataset.wiki, el.dataset.name);
      el.addEventListener("click", open);
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") { e.preventDefault(); open(); }
      });
    });
    container.querySelector("#player-modal .city-modal-backdrop")?.addEventListener("click", closePlayer);
    container.querySelector("#player-modal .city-modal-close")?.addEventListener("click", closePlayer);
  }

  return { setTeam, render };
}
