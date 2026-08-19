// World Cup 2026 — entry point.
// Owns global data + tab state, wires events, lazily builds each view.
// Each view is a factory: createXxx({ container, data, ... }) -> { render() }.
//
// The tournament is over (final: 2026-07-19) — this is now a fully static app.
// Data flow: bundled JSON in data/*.json loads once at boot; there is no live
// refresh or network merge anymore (see git history for the old Wikipedia /
// openfootball live-update pipeline if it's ever needed again).

import { createSchedule } from "./views/schedule.js?v=27";
import { createKnockout } from "./views/knockout.js?v=36";
import { createCities } from "./views/cities.js?v=27";
import { createWorld } from "./views/world.js?v=27";
import { createRankings } from "./views/rankings.js?v=27";
import { createStandings } from "./views/standingstab.js?v=27";
import { createTeamList } from "./views/teamlist.js?v=28";
import { createCountry } from "./views/country.js?v=27";
import { createMatchModal } from "./views/matchmodal.js?v=28";

const $ = (id) => document.getElementById(id);
const APP_VERSION = 46; // bump on every release; shown in the header.

// Show the app version in the header. Single source of truth: APP_VERSION.
function showVersion() {
  const el = $("app-ver");
  if (el) el.textContent = `v${APP_VERSION}`;
}

// ---- shared data, loaded once ----
const data = { teams: null, groups: null, venues: null, matches: null, byCode: {} };

// ---- tab state ----
let activeTab = "japan";
const views = {}; // lazily created view instances
const VALID_TABS = ["schedule", "knockout", "standings", "cities", "world", "teams", "rankings", "japan"];

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
  data.asOf = matches._asOf || "2026-07-19";
  reindex();
}

function reindex() {
  data.byCode = Object.fromEntries(data.teams.map((t) => [t.code, t]));
  data.venueById = Object.fromEntries(data.venues.map((v) => [v.id, v]));
}

function rerenderAll() {
  for (const name of Object.keys(views)) views[name].render?.();
}

function setTab(name, skipHash) {
  activeTab = name;
  document.querySelectorAll(".tab").forEach((b) =>
    b.classList.toggle("active", b.dataset.tab === name)
  );
  document.querySelectorAll(".view").forEach((v) =>
    v.classList.toggle("hidden", v.id !== `tab-${name}`)
  );
  ensureView(name);
  $("main")?.scrollTo(0, 0);
  if (!skipHash) {
    history.replaceState(null, "", `#${name}`);
  }
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
  setTab("schedule", true);
  const back =
    origin && ORIGIN_LABEL[origin]
      ? { label: ORIGIN_LABEL[origin], run: () => setTab(origin) }
      : null;
  views.schedule?.showCountry?.(code, back);
  history.replaceState(null, "", origin ? `#country/${code}/${origin}` : `#country/${code}`);
}

function ensureView(name) {
  if (views[name]) {
    views[name].render?.();
    return;
  }
  const container = $(`tab-${name}`);
  if (name === "schedule") views[name] = createSchedule({ container, data });
  else if (name === "knockout") views[name] = createKnockout({ container, data });
  else if (name === "cities") views[name] = createCities({ container, data });
  else if (name === "world")
    views[name] = createWorld({ container, data, onTeam: (c) => goToCountry(c, "world") });
  else if (name === "rankings")
    views[name] = createRankings({ container, data, onTeam: (c) => goToCountry(c, "rankings") });
  else if (name === "standings")
    views[name] = createStandings({ container, data, onTeam: (c) => goToCountry(c, "standings") });
  else if (name === "teams")
    views[name] = createTeamList({ container, data, onTeam: (c) => goToCountry(c, "teams") });
  else if (name === "japan") {
    // The 日本 tab reuses the shared country page (no separate Japan view).
    const jp = createCountry({ container, data, onBack: null });
    views[name] = { render: () => { jp.setTeam("JPN"); jp.render(); } };
  }
  views[name].render();
}

// Static data-provenance footer: source + as-of date. Shown on every tab.
function updateProvenance() {
  const el = $("data-provenance");
  if (!el) return;
  el.innerHTML = `<span class="dp-src">📡 出典 — Wikipedia・openfootball（大会終了時点の最終結果）</span><span class="dp-when">🕒 データ基準 ${data.asOf}</span>`;
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

function parseHash() {
  const h = location.hash.replace(/^#/, "");
  if (!h) return { tab: "japan" };
  if (h.startsWith("country/")) {
    const parts = h.split("/");
    return { tab: "japan", country: parts[1], origin: parts[2] || null };
  }
  if (VALID_TABS.includes(h)) return { tab: h };
  return { tab: "japan" };
}

function applyHash() {
  const { tab, country, origin } = parseHash();
  if (country && data.byCode[country]) {
    goToCountry(country, origin);
  } else {
    setTab(tab);
  }
}

function bind() {
  document.querySelectorAll(".tab").forEach((b) =>
    b.addEventListener("click", () => setTab(b.dataset.tab))
  );
  document.querySelector(".brand")?.addEventListener("click", () => setTab("schedule"));
  $("theme-btn")?.addEventListener("click", toggleTheme);
  applyThemeButton();

  window.addEventListener("hashchange", () => applyHash());

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
  showVersion();
  // One-time cleanup of localStorage keys from the old live-update era (the
  // tournament is over — there is no live pipeline to cache anymore).
  try {
    for (const k of Object.keys(localStorage)) {
      if (k.startsWith("wc2026-livedata") || k.startsWith("wc2026-rankings")) {
        localStorage.removeItem(k);
      }
    }
  } catch (_) {}

  try {
    await loadStatic();
  } catch (e) {
    $("loading").textContent = "データの読み込みに失敗しました: " + e.message;
    return;
  }
  bind();
  applyHash();
  updateProvenance();
  $("loading").classList.add("hidden");
})();
