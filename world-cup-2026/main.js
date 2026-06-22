// World Cup 2026 — entry point.
// Owns global data + tab state, wires events, lazily builds each view.
// Each view is a factory: createXxx({ container, data, ... }) -> { render() }.
//
// Data flow: bundled static JSON loads first (instant, offline-safe), then we
// try to refresh groups + results live from Wikipedia. Live data is cached in
// localStorage so a cold start shows the last fetched results immediately.

import { createSchedule } from "./views/schedule.js?v=4";
import { createBracket } from "./views/bracket.js?v=4";
import { createCities } from "./views/cities.js?v=4";
import { createWorld } from "./views/world.js?v=4";
import { createRankings } from "./views/rankings.js?v=4";
import { createStandings } from "./views/standingstab.js?v=4";
import { createTeamList } from "./views/teamlist.js?v=4";
import { createJapan } from "./views/japan.js?v=4";
import { createMatchModal } from "./views/matchmodal.js?v=4";
import { fetchLiveData } from "./views/livedata.js?v=4";
import { fetchFootballData } from "./views/footballapi.js?v=4";

const $ = (id) => document.getElementById(id);
const APP_VERSION = 4;
const LIVE_CACHE_KEY = "wc2026-livedata-v4";

// ---- shared data, loaded once ----
const data = { teams: null, groups: null, venues: null, matches: null, byCode: {} };

// ---- tab state ----
let activeTab = "schedule";
const views = {}; // lazily created view instances

async function loadStatic() {
  const cb = `?_=${Date.now()}`;
  const [teams, groups, venues, matches] = await Promise.all([
    fetch(`./data/teams.json${cb}`).then((r) => r.json()),
    fetch(`./data/groups.json${cb}`).then((r) => r.json()),
    fetch(`./data/venues.json${cb}`).then((r) => r.json()),
    fetch(`./data/matches.json${cb}`).then((r) => r.json()),
  ]);
  data.teams = teams.teams;
  data.groups = groups.groups;
  data.venues = venues.venues;
  data.matches = matches.matches;
  data.asOf = matches._asOf || "2026-06-18";
  reindex();
}

function reindex() {
  data.byCode = Object.fromEntries(data.teams.map((t) => [t.code, t]));
  data.venueById = Object.fromEntries(data.venues.map((v) => [v.id, v]));
}

// Merge a live { groups, matches, asOf } payload into the shared data and
// re-sync each team's group field so all views stay consistent.
function applyLive(live, source) {
  // Only overwrite groups if the live data has them (API may return empty).
  if (live.groups && Object.keys(live.groups).length > 0) {
    data.groups = live.groups;
    const groupOf = {};
    for (const [g, codes] of Object.entries(live.groups)) for (const c of codes) groupOf[c] = g;
    for (const t of data.teams) if (groupOf[t.code]) t.group = groupOf[t.code];
  }
  data.matches = live.matches;
  data.asOf = live.asOf || data.asOf;
  data.source = source;
  reindex();
}

function rerenderAll() {
  for (const name of Object.keys(views)) views[name].render?.();
}

function setTab(name) {
  activeTab = name;
  document.querySelectorAll(".tab").forEach((b) =>
    b.classList.toggle("active", b.dataset.tab === name)
  );
  document.querySelectorAll(".view").forEach((v) =>
    v.classList.toggle("hidden", v.id !== `tab-${name}`)
  );
  ensureView(name);
  $("main")?.scrollTo(0, 0);
}

// Jump to a country page (owned by the schedule view) from another tab.
// `origin` (a tab name) makes the country page's back button return there.
const ORIGIN_LABEL = {
  teams: "← チーム一覧に戻る",
  rankings: "← 得点王に戻る",
  standings: "← 順位表に戻る",
  world: "← 参加国に戻る",
};
function goToCountry(code, origin) {
  setTab("schedule");
  const back =
    origin && ORIGIN_LABEL[origin]
      ? { label: ORIGIN_LABEL[origin], run: () => setTab(origin) }
      : null;
  views.schedule?.showCountry?.(code, back);
}

function ensureView(name) {
  if (views[name]) {
    views[name].render?.();
    return;
  }
  const container = $(`tab-${name}`);
  if (name === "schedule") views[name] = createSchedule({ container, data });
  else if (name === "bracket") views[name] = createBracket({ container, data });
  else if (name === "cities") views[name] = createCities({ container, data });
  else if (name === "world")
    views[name] = createWorld({ container, data, onTeam: (c) => goToCountry(c, "world") });
  else if (name === "rankings")
    views[name] = createRankings({ container, data, onTeam: (c) => goToCountry(c, "rankings") });
  else if (name === "standings")
    views[name] = createStandings({ container, data, onTeam: (c) => goToCountry(c, "standings") });
  else if (name === "teams")
    views[name] = createTeamList({ container, data, onTeam: (c) => goToCountry(c, "teams") });
  else if (name === "japan")
    views[name] = createJapan({ container, data });
  views[name].render();
}

// ---- live update status UI (in the header) ----
function setStatus(text, state) {
  const el = $("update-status");
  if (el) {
    el.textContent = text;
    el.className = "update-status" + (state ? " " + state : "");
  }
}

// Format an ISO timestamp as local "M/D HH:MM" (date + time to the minute).
function fmtDateTime(iso) {
  if (!iso) return "";
  const d = new Date(iso);
  if (isNaN(d)) return "";
  const p = (n) => String(n).padStart(2, "0");
  return `${d.getMonth() + 1}/${d.getDate()} ${p(d.getHours())}:${p(d.getMinutes())}`;
}

async function refreshLive({ silent } = {}) {
  const btn = $("refresh-btn");
  if (btn) btn.disabled = true;
  if (!silent) setStatus("更新中…", "loading");
  try {
    let live;
    let source;
    try {
      live = await fetchFootballData(data.teams);
      source = "api";
    } catch (_) {
      live = await fetchLiveData();
      source = "wiki";
    }
    applyLive(live, source);
    const fetchedAt = new Date().toISOString();
    try {
      localStorage.setItem(LIVE_CACHE_KEY, JSON.stringify({ ...live, fetchedAt }));
    } catch (_) {}
    const played = live.matches.filter((m) => m.result).length;
    setStatus(`更新: ${fmtDateTime(fetchedAt)} / ${played}試合`, "ok");
    rerenderAll();
  } catch (e) {
    console.warn("[live] fetch failed:", e.message);
    const played = data.matches.filter((m) => m.result).length;
    if (data.source === "cache") {
      setStatus(`保存データを表示中 / ${played}試合`, "");
    } else {
      setStatus(`オフラインモード — 静的データ (${data.asOf || "—"}) / ${played}試合`, "");
    }
  } finally {
    if (btn) btn.disabled = false;
  }
}

function loadCache() {
  try {
    const raw = localStorage.getItem(LIVE_CACHE_KEY);
    if (!raw) return false;
    const live = JSON.parse(raw);
    if (live.groups && live.matches) {
      applyLive(live, "cache");
      const played = live.matches.filter((m) => m.result).length;
      const when = fmtDateTime(live.fetchedAt);
      setStatus(`保存データ${when ? ` (${when})` : ""} / ${played}試合`, "");
      return true;
    }
  } catch (_) {}
  return false;
}


function applyThemeButton() {
  const dark = document.documentElement.getAttribute("data-theme") === "dark";
  const btn = $("theme-btn");
  if (btn) btn.textContent = dark ? "☀️" : "🌙";
}

function toggleTheme() {
  const root = document.documentElement;
  const dark = root.getAttribute("data-theme") === "dark";
  if (dark) root.removeAttribute("data-theme");
  else root.setAttribute("data-theme", "dark");
  try {
    localStorage.setItem("wc2026-theme", dark ? "light" : "dark");
  } catch (_) {}
  applyThemeButton();
}

const matchModal = createMatchModal({ onTeam: (code) => goToCountry(code) });

function bind() {
  document.querySelectorAll(".tab").forEach((b) =>
    b.addEventListener("click", () => setTab(b.dataset.tab))
  );
  document.querySelector(".brand")?.addEventListener("click", () => setTab("schedule"));
  $("refresh-btn")?.addEventListener("click", () => refreshLive({}));
  $("theme-btn")?.addEventListener("click", toggleTheme);
  applyThemeButton();

  // Global delegated handler: clicking any match card opens its detail modal.
  document.addEventListener("click", (e) => {
    const card = e.target.closest("[data-match-id]");
    if (!card) return;
    const id = card.dataset.matchId;
    const m = data.matches.find((mm) => mm.id === id);
    if (m) matchModal.open(m, data);
  });
}

(async function boot() {
  // Clean up old localStorage keys from previous versions
  try { localStorage.removeItem("wc2026-livedata"); } catch (_) {}
  try { localStorage.removeItem("wc2026-livedata-v3"); } catch (_) {}

  try {
    await loadStatic();
  } catch (e) {
    $("loading").textContent = "データの読み込みに失敗しました: " + e.message;
    return;
  }
  loadCache();
  bind();
  setTab("schedule");
  $("loading").classList.add("hidden");
  refreshLive({ silent: false });
})();
