// Schedule view: BBC-style match cards grouped by round, plus group standings.
// Group results come from live data; knockout fixtures show real dates/venues
// with predicted teams filled in (from the prediction engine).

import { groupStandings } from "./standings.js?v=24";
import { createCountry } from "./country.js?v=24";
import { localHM, localYMD } from "./util.js?v=24";

const STAGE_LABELS = {
  group: "Group",
  r32: "R32",
  r16: "R16",
  qf: "QF",
  sf: "SF",
  third: "3rd",
  final: "Final",
};
const KO_STAGES = ["r32", "r16", "qf", "sf", "third", "final"];

// Slot label (English) -> short Japanese, for unresolved knockout slots.
function jpLabel(label) {
  if (!label) return "未定";
  return label
    .replace(/Winner Group ([A-L])/, "$1組 1位")
    .replace(/Runner-up Group ([A-L])/, "$1組 2位")
    .replace(/3rd Group ([A-L/]+)/, "3位 ($1組)")
    .replace(/Winner Match (\d+)/, "第$1試合 勝者")
    .replace(/Loser Match (\d+)/, "第$1試合 敗者");
}

export function createSchedule({ container, data }) {
  let filter = "groups"; // "groups" | "all" | group key A-L | a ko stage
  let mode = "list"; // "list" | "country"

  // Default "back" returns to the schedule list; overridden when opened from
  // another tab so the back button returns there instead.
  const backToList = () => {
    mode = "list";
    render();
  };
  let backHandler = backToList;

  // Country detail sub-view, rendered into the same container.
  const country = createCountry({
    container,
    data,
    onBack: () => backHandler(),
  });

  // `back` (optional) = { label, run } overrides the back button's text and
  // action — used when arriving from another tab (e.g. the team list). The
  // schedule always resets to its list first, then runs any external action
  // (e.g. switching tabs) so it's clean when revisited.
  function openCountry(code, back) {
    if (!data.byCode[code]) return;
    mode = "country";
    backHandler = back?.run
      ? () => {
          backToList();
          back.run();
        }
      : backToList;
    country.setTeam(code, back?.label);
    country.render();
  }

  // Exposed so other tabs can jump to a country page, optionally specifying
  // where the back button should return to.
  function showCountry(code, back) {
    openCountry(code, back);
  }

  function flagName(code) {
    const t = data.byCode[code];
    if (!t) return "";
    return `<span class="team-link" data-team="${code}" role="button" tabindex="0"><span class="flag">${t.flag}</span><span class="tname">${t.name}</span></span>`;
  }

  function flagNamePlain(code) {
    const t = data.byCode[code];
    if (!t) return "";
    return `<span class="flag">${t.flag}</span><span class="tname">${t.name}</span>`;
  }

  // Render one side of a match card: a real team, a predicted team, or a label.
  function side(code, label, { predicted } = {}) {
    if (code) {
      return `<div class="m-team${predicted ? " predicted" : ""}">${flagNamePlain(code)}${
        predicted ? '<span class="pred-badge">予想</span>' : ""
      }</div>`;
    }
    return `<div class="m-team tbd">${jpLabel(label)}</div>`;
  }

  // A BBC-style match card. Knockout fixtures show the real slot labels
  // (e.g. "A組 1位 vs B組 2位") with their real date/venue — no predicted
  // teams here (predictions live only in the 優勝予想 tab).
  function fmtTime(iso) {
    if (!iso) return "";
    const d = new Date(iso);
    if (isNaN(d)) return "";
    const p = (n) => String(n).padStart(2, "0");
    return ` ${p(d.getHours())}:${p(d.getMinutes())}`;
  }

  function matchCard(m) {
    const venue = data.venueById[m.venue];
    const played = Array.isArray(m.result);
    const isLive = m.status === "live" || m.status === "halftime" || m.status === "extra_time" || m.status === "penalties";

    const liveLabel = { live: "LIVE", halftime: "HT", extra_time: "延長", penalties: "PK" };

    let center;
    if (played) {
      const pen = m.penalties ? `<div class="m-pen">PK ${m.penalties[0]}-${m.penalties[1]}</div>` : "";
      center = `<div class="m-score">${m.result[0]}<span>-</span>${m.result[1]}</div>${pen}`;
    } else if (isLive) {
      center = `<div class="m-score m-live-score">${m.result ? m.result[0] : "0"}<span>-</span>${m.result ? m.result[1] : "0"}</div>
        <div class="m-live-badge">${liveLabel[m.status] || "LIVE"}</div>`;
    } else {
      center = `<div class="m-vs">vs</div>`;
    }

    const timeStr = localHM(m);

    return `<div class="m-card${isLive ? " m-card-live" : ""}" data-match-id="${m.id}" role="button" tabindex="0">
      <div class="m-side home">${side(m.home, m.homeLabel)}</div>
      ${center}
      <div class="m-side away">${side(m.away, m.awayLabel)}</div>
      <div class="m-meta">
        ${timeStr ? `<span class="m-date">${timeStr}</span>` : ""}
        ${venue ? `<span class="m-venue">🏟 ${venue.stadium ? venue.stadium + " · " : ""}${venue.city}</span>` : ""}
      </div>
    </div>`;
  }

  function renderGroupCard(groupKey) {
    const rows = groupStandings(data, groupKey)
      .map(
        (r, i) => `<tr>
          <td class="team ${i < 2 ? "qual" : ""}">${flagName(r.code)}</td>
          <td>${r.pld}</td><td>${r.w}</td><td>${r.d}</td><td>${r.l}</td>
          <td>${r.gd > 0 ? "+" : ""}${r.gd}</td><td><strong>${r.pts}</strong></td>
        </tr>`
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

  // Cards grouped by date, with a date sub-header (BBC style).
  function cardsByDate(matches) {
    const byDate = new Map();
    for (const m of matches) {
      const key = localYMD(m) || "日程未定";
      if (!byDate.has(key)) byDate.set(key, []);
      byDate.get(key).push(m);
    }
    const keys = [...byDate.keys()].sort((a, b) =>
      a === "日程未定" ? 1 : b === "日程未定" ? -1 : a < b ? -1 : 1
    );
    return keys
      .map(
        (d) => `<div class="date-group">
        <div class="date-head">${d}</div>
        <div class="card-list">${byDate.get(d).map((m) => matchCard(m)).join("")}</div>
      </div>`
      )
      .join("");
  }

  // Knockout: one section per stage, in bracket order.
  function renderKnockout(stage) {
    const ms = data.matches.filter((m) => m.stage === stage);
    if (!ms.length) return `<p class="sub">該当する試合がありません。</p>`;
    return `<div class="ko-section">
      <h3 class="ko-title">${STAGE_LABELS[stage]}</h3>
      ${cardsByDate(ms)}
    </div>`;
  }

  function todaySection() {
    const now = new Date();
    const todayStr = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}-${String(now.getDate()).padStart(2, "0")}`;

    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate());
    const opening = new Date(2026, 5, 12);
    const dayNum = Math.floor((today - opening) / 86400000) + 1;
    const dayLabel = dayNum >= 1 ? ` — 大会${dayNum}日目` : "";

    const groupKeys = Object.keys(data.groups);
    let todayMatches = data.matches.filter((m) => localYMD(m) === todayStr);
    if (filter !== "groups" && groupKeys.includes(filter)) {
      todayMatches = todayMatches.filter((m) => m.group === filter);
    } else if (KO_STAGES.includes(filter)) {
      todayMatches = todayMatches.filter((m) => m.stage === filter);
    }

    if (todayMatches.length === 0) {
      return `<div class="today-section">
        <h3 class="today-title">📺 今日の試合${dayLabel}</h3>
        <p class="today-none">今日の試合はありません</p>
      </div>`;
    }
    return `<div class="today-section">
      <h3 class="today-title">📺 今日の試合${dayLabel}</h3>
      <div class="card-list">${todayMatches.map((m) => matchCard(m)).join("")}</div>
    </div>`;
  }

  function render() {
    // When a country is open, re-render it (e.g. after a live data refresh).
    if (mode === "country") {
      country.render();
      return;
    }
    const groupKeys = Object.keys(data.groups);

    const chips = [
      `<button class="chip ${filter === "groups" ? "active" : ""}" data-f="groups">All</button>`,
      ...groupKeys.map(
        (g) => `<button class="chip ${filter === g ? "active" : ""}" data-f="${g}">${g}</button>`
      ),
      ...KO_STAGES.map(
        (s) => `<button class="chip ${filter === s ? "active" : ""}" data-f="${s}">${STAGE_LABELS[s]}</button>`
      ),
    ].join("");

    const today = todaySection();

    let body;
    if (filter === "groups") {
      const groupMatches = data.matches.filter((m) => m.stage === "group");
      body = cardsByDate(groupMatches);
    } else if (groupKeys.includes(filter)) {
      const ms = data.matches.filter((m) => m.stage === "group" && m.group === filter);
      body = `<div class="groups-grid single">${renderGroupCard(filter)}</div>${cardsByDate(ms)}`;
    } else {
      body = renderKnockout(filter);
    }

    container.innerHTML = `
      <h2 class="section-title">📅 日程・結果 <span class="sub">全${data.matches.length}試合</span></h2>
      <div class="banner">組分け・結果は自動取得（${data.asOf || "—"} 時点）。順位表はスコアから自動集計。試合カードをクリックで詳細（得点者・分・アシスト・審判等）。</div>
      <div class="toolbar">${chips}</div>
      ${today}
      ${body}
    `;

    container.querySelectorAll(".chip").forEach((c) =>
      c.addEventListener("click", () => {
        filter = c.dataset.f;
        render();
      })
    );
    // Clicking a team in the standings table opens its country page.
    container.querySelectorAll(".group-card .team-link").forEach((el) => {
      el.addEventListener("click", () => openCountry(el.dataset.team));
      el.addEventListener("keydown", (e) => {
        if (e.key === "Enter" || e.key === " ") {
          e.preventDefault();
          openCountry(el.dataset.team);
        }
      });
    });
  }

  return { render, showCountry };
}
