// openfootball/worldcup.json data source.
//
// A clean, CORS-friendly static dataset (no API key, no proxy) that carries the
// full 2026 fixture list with results, GROUNDS, the knockout bracket, and —
// crucially — per-match scorers with minute / penalty / own-goal flags, which
// the Football-Data tier we use does not expose. Auto-generated upstream, so it
// can lag live results by a few days; we therefore use it as a SUPPLEMENT for
// scorer detail (preferred over scraping Wikipedia) and as a deeper FALLBACK for
// the whole dataset, never as the primary results source.
//
// Returns the same { groups, matches, scorers, asOf } shape as footballapi.js /
// livedata.js so main.js can merge or swap it in transparently.

const SOURCES = [
  "https://cdn.jsdelivr.net/gh/openfootball/worldcup.json@master/2026/worldcup.json",
  "https://raw.githubusercontent.com/openfootball/worldcup.json/master/2026/worldcup.json",
];

const STAGE_BY_ROUND = {
  "Round of 32": "r32",
  "Round of 16": "r16",
  "Quarter-final": "qf",
  "Semi-final": "sf",
  "Match for third place": "third",
  Final: "final",
};

// openfootball ground string (contains a city/area token) -> our venue id.
const GROUND_TO_VENUE = {
  "Mexico City": "mex", Guadalajara: "gdl", Zapopan: "gdl",
  Monterrey: "mty", Guadalupe: "mty", Toronto: "tor", Vancouver: "van",
  Atlanta: "atl", Foxborough: "bos", Boston: "bos", Arlington: "dal",
  Dallas: "dal", Houston: "hou", "Kansas City": "kan", Inglewood: "lax",
  "Los Angeles": "lax", Miami: "mia", "East Rutherford": "nyc",
  "New York": "nyc", Philadelphia: "phi", "Santa Clara": "sfo",
  "San Francisco": "sfo", Seattle: "sea",
};

// openfootball team names that differ from our teams.json names.
const NAME_ALIASES = {
  "bosnia & herzegovina": "BIH",
  "czech republic": "CZE",
  "ivory coast": "CIV",
  turkey: "TUR",
  usa: "USA",
};

function venueForGround(ground) {
  if (!ground) return null;
  for (const [k, v] of Object.entries(GROUND_TO_VENUE)) if (ground.includes(k)) return v;
  return null;
}

// Build an absolute UTC kickoff (ISO) from openfootball's date + venue-local
// time string, e.g. "2026-06-28" + "12:00 UTC-7" -> "...T19:00:00.000Z". This
// lets every view render kickoff in the viewer's own timezone.
function toKickoff(date, time) {
  const m = /(\d{1,2}):(\d{2})\s*UTC([+-]\d+)/.exec(time || "");
  if (!date || !m) return null;
  const [y, mo, d] = date.split("-").map(Number);
  const utcMs = Date.UTC(y, mo - 1, d, Number(m[1]) - Number(m[3]), Number(m[2]));
  return isNaN(utcMs) ? null : new Date(utcMs).toISOString();
}

// A still-undecided slot, e.g. "1I" (group winner), "3A/B/C/D/F" (a 3rd place),
// "W73"/"L101" (winner/loser of match N). Map to the app's English label form so
// the existing predictor/label code resolves them.
function isPlaceholder(s) {
  return !s || /^[0-9]/.test(s) || /^[WL]\d+$/.test(s);
}
function slotLabel(s) {
  let m;
  if ((m = /^1([A-L])$/.exec(s))) return `Winner Group ${m[1]}`;
  if ((m = /^2([A-L])$/.exec(s))) return `Runner-up Group ${m[1]}`;
  if ((m = /^3([A-L/]+)$/.exec(s))) return `3rd Group ${m[1]}`;
  if ((m = /^W(\d+)$/.exec(s))) return `Winner Match ${m[1]}`;
  if ((m = /^L(\d+)$/.exec(s))) return `Loser Match ${m[1]}`;
  return s;
}

export async function fetchOpenFootball(knownTeams) {
  let json = null;
  let lastErr;
  for (const url of SOURCES) {
    try {
      const res = await fetch(url);
      if (!res.ok) throw new Error("HTTP " + res.status);
      json = await res.json();
      break;
    } catch (e) {
      lastErr = e;
    }
  }
  if (!json) throw lastErr || new Error("openfootball fetch failed");

  const byName = {};
  for (const t of knownTeams || []) byName[t.name.toLowerCase()] = t.code;
  const codeFor = (name) => {
    if (!name) return null;
    const key = String(name).toLowerCase();
    return byName[key] || NAME_ALIASES[key] || null;
  };

  // Real (non-own) goal scorer names, rich details, and own-goal counts. In
  // openfootball an own goal is listed under the BENEFITING team's array with
  // owngoal:true (same convention our app uses).
  const goalNames = (arr) => (arr || []).filter((g) => !g.owngoal).map((g) => g.name);
  const goalDetails = (arr) =>
    (arr || []).map((g) => ({
      name: g.name,
      minute: g.minute != null ? String(g.minute) : null,
      pen: !!g.penalty,
      og: !!g.owngoal,
    }));
  const ownGoals = (arr) => (arr || []).filter((g) => g.owngoal).length;

  const groups = {};
  const matches = [];
  let mid = 1;
  let latestDate = null;

  for (const m of json.matches || []) {
    const groupLetter = (m.group || "").match(/Group ([A-L])/)?.[1] || null;
    const stage = m.group ? "group" : STAGE_BY_ROUND[m.round] || "group";
    const home = codeFor(m.team1);
    const away = codeFor(m.team2);
    const result = Array.isArray(m.score?.ft) ? m.score.ft.slice(0, 2) : null;

    if (stage === "group" && groupLetter) {
      for (const c of [home, away])
        if (c && !(groups[groupLetter] ||= []).includes(c)) groups[groupLetter].push(c);
    }

    const entry = {
      id: `M${String(mid).padStart(3, "0")}`,
      stage,
      date: m.date || null,
      time: m.time || null,
      kickoff: toKickoff(m.date, m.time),
      venue: venueForGround(m.ground),
      home: home || null,
      away: away || null,
      result,
      scorers1: goalNames(m.goals1),
      scorers2: goalNames(m.goals2),
      scorerDetails1: goalDetails(m.goals1),
      scorerDetails2: goalDetails(m.goals2),
      ownGoals1: ownGoals(m.goals1),
      ownGoals2: ownGoals(m.goals2),
    };
    if (stage === "group" && groupLetter) {
      entry.group = groupLetter;
    } else {
      if (!home) entry.homeLabel = isPlaceholder(m.team1) ? slotLabel(m.team1) : null;
      if (!away) entry.awayLabel = isPlaceholder(m.team2) ? slotLabel(m.team2) : null;
    }

    matches.push(entry);
    mid++;
    if (result && m.date && (!latestDate || m.date > latestDate)) latestDate = m.date;
  }

  // Tournament scorer ranking from the per-match goals (own goals excluded).
  const tally = {};
  const bump = (code, names) => {
    if (!code) return;
    tally[code] ||= {};
    for (const n of names) tally[code][n] = (tally[code][n] || 0) + 1;
  };
  for (const mm of matches) {
    bump(mm.home, mm.scorers1);
    bump(mm.away, mm.scorers2);
  }
  const scorers = [];
  for (const [code, names] of Object.entries(tally))
    for (const [name, goals] of Object.entries(names)) scorers.push({ name, code, goals });
  scorers.sort((a, b) => b.goals - a.goals || a.name.localeCompare(b.name));

  return { groups, matches, scorers, asOf: latestDate };
}
