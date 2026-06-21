// Football-Data.org v4 API integration.
// Primary live data source; falls back to Wikipedia on failure.
// Free plan: 10 requests/minute, competition code WC for World Cup.

const BASE = "https://api.football-data.org/v4";
const TOKEN = "65bcaec3f8df4bc3bfe5fd88f8d42131";
const COMP = "WC"; // FIFA World Cup

// Football-Data.org uses FIFA country codes which mostly match ours,
// but a few differ. Map their codes to ours (from data/teams.json).
const CODE_MAP = {
  GRE: "GRC",
  NED: "NLD",
  SUI: "CHE",
  GER: "GER",
  CRC: "CRC",
  KSA: "KSA",
  RSA: "RSA",
  // Add more as needed — most 3-letter codes match already
};

function mapCode(apiCode) {
  return CODE_MAP[apiCode] || apiCode;
}

async function apiFetch(path) {
  const res = await fetch(`${BASE}${path}`, {
    headers: { "X-Auth-Token": TOKEN },
  });
  if (!res.ok) throw new Error(`football-data.org ${res.status}`);
  return res.json();
}

// Map API match status to a result array [home, away] or null.
function matchResult(m) {
  if (m.status === "FINISHED" || m.status === "AWARDED") {
    const ft = m.score?.fullTime;
    if (ft && ft.home != null && ft.away != null) {
      return [ft.home, ft.away];
    }
  }
  return null;
}

// Map API stage strings to our internal stage keys.
function mapStage(apiStage) {
  const m = {
    GROUP_STAGE: "group",
    ROUND_OF_32: "r32",
    LAST_32: "r32",
    ROUND_OF_16: "r16",
    LAST_16: "r16",
    QUARTER_FINALS: "qf",
    SEMI_FINALS: "sf",
    THIRD_PLACE: "third",
    FINAL: "final",
  };
  return m[apiStage] || apiStage?.toLowerCase() || "group";
}

// Extract group letter from API group string like "GROUP_A".
function groupLetter(apiGroup) {
  const m = (apiGroup || "").match(/GROUP_([A-L])/);
  return m ? m[1] : null;
}

// Map venue city to our venue id (same mapping as livedata.js).
const CITY_TO_VENUE = {
  "Mexico City": "mex",
  Zapopan: "gdl",
  Guadalajara: "gdl",
  Monterrey: "mty",
  Toronto: "tor",
  Vancouver: "van",
  Atlanta: "atl",
  Foxborough: "bos",
  Boston: "bos",
  Arlington: "dal",
  Dallas: "dal",
  Houston: "hou",
  "Kansas City": "kan",
  Inglewood: "lax",
  "Los Angeles": "lax",
  "Miami Gardens": "mia",
  Miami: "mia",
  "East Rutherford": "nyc",
  "New York": "nyc",
  Philadelphia: "phi",
  "Santa Clara": "sfo",
  "San Francisco": "sfo",
  Seattle: "sea",
};

function mapVenue(apiMatch) {
  const city = apiMatch.venue?.city || "";
  for (const [k, v] of Object.entries(CITY_TO_VENUE)) {
    if (city.includes(k)) return v;
  }
  return null;
}

// Format an ISO date string to YYYY-MM-DD.
function fmtDate(iso) {
  if (!iso) return null;
  return iso.slice(0, 10);
}

// Parse goal scorers from the API goals array (if available).
// Returns an array of scorer display names (one entry per goal).
function parseGoals(goals, teamId) {
  if (!Array.isArray(goals)) return [];
  return goals
    .filter((g) => g.team?.id === teamId && g.type !== "OWN")
    .map((g) => g.scorer?.name?.split(" ").pop() || "Unknown");
}

// Rich goal detail: { name, minute, type, assist }
function parseGoalDetails(goals, teamId) {
  if (!Array.isArray(goals)) return [];
  return goals
    .filter((g) => g.team?.id === teamId)
    .map((g) => ({
      name: g.scorer?.name?.split(" ").pop() || "Unknown",
      fullName: g.scorer?.name || "Unknown",
      minute: g.minute ?? null,
      injuryTime: g.injuryTime ?? null,
      type: g.type || "REGULAR",
      assist: g.assist?.name || null,
    }));
}

function countOwnGoalsForTeam(goals, teamId) {
  if (!Array.isArray(goals)) return 0;
  return goals.filter((g) => g.team?.id === teamId && g.type === "OWN").length;
}

// Parse referees from the API.
function parseReferees(referees) {
  if (!Array.isArray(referees)) return [];
  return referees.map((r) => ({
    name: r.name,
    type: r.type,
    nationality: r.nationality,
  }));
}

// Map API status to a display-friendly status.
function mapStatus(status) {
  const m = {
    SCHEDULED: "scheduled",
    TIMED: "timed",
    IN_PLAY: "live",
    PAUSED: "halftime",
    EXTRA_TIME: "extra_time",
    PENALTY_SHOOTOUT: "penalties",
    FINISHED: "finished",
    SUSPENDED: "suspended",
    POSTPONED: "postponed",
    CANCELLED: "cancelled",
    AWARDED: "finished",
  };
  return m[status] || "scheduled";
}

// Fetch detailed match info (including statistics) for a single match.
// The v4 API returns head2head and match details including statistics.
const STATS_CACHE = new Map();

export async function fetchMatchStats(matchApiId) {
  if (!matchApiId) return null;
  if (STATS_CACHE.has(matchApiId)) return STATS_CACHE.get(matchApiId);
  try {
    const json = await apiFetch(`/matches/${matchApiId}`);
    const stats = {};
    if (json.homeTeam?.statistics && json.awayTeam?.statistics) {
      const hStats = json.homeTeam.statistics;
      const aStats = json.awayTeam.statistics;
      const mapStat = (arr) => {
        const obj = {};
        if (Array.isArray(arr)) arr.forEach((s) => { obj[s.type] = s.value; });
        return obj;
      };
      const h = mapStat(hStats);
      const a = mapStat(aStats);
      const keys = [
        ["ball_possession", "ポゼッション", "%"],
        ["shots", "シュート", ""],
        ["shots_on_goal", "枠内シュート", ""],
        ["corner_kicks", "コーナーキック", ""],
        ["fouls", "ファウル", ""],
        ["offsides", "オフサイド", ""],
        ["yellow_cards", "イエローカード", ""],
        ["red_cards", "レッドカード", ""],
        ["saves", "セーブ", ""],
      ];
      stats.rows = [];
      for (const [key, label, unit] of keys) {
        if (h[key] != null || a[key] != null) {
          stats.rows.push({
            label,
            home: h[key] != null ? `${h[key]}${unit}` : "-",
            away: a[key] != null ? `${a[key]}${unit}` : "-",
            homeVal: Number(h[key]) || 0,
            awayVal: Number(a[key]) || 0,
          });
        }
      }
    }
    const result = stats.rows?.length ? stats : null;
    STATS_CACHE.set(matchApiId, result);
    return result;
  } catch (e) {
    STATS_CACHE.set(matchApiId, null);
    return null;
  }
}

// Fetch matches + standings from Football-Data.org and return the same
// { groups, matches, asOf } shape that fetchLiveData() in livedata.js uses.
// `knownTeams` is data.teams (used to validate/map codes).
export async function fetchFootballData(knownTeams) {
  const [matchData, standingsData] = await Promise.all([
    apiFetch(`/competitions/${COMP}/matches`),
    apiFetch(`/competitions/${COMP}/standings`),
  ]);

  const codeByName = {};
  for (const t of knownTeams) {
    codeByName[t.name.toLowerCase()] = t.code;
  }

  // Build team-id -> our code mapping from the API's team objects.
  const idToCode = {};
  function resolveCode(apiTeam) {
    if (!apiTeam) return null;
    const tla = apiTeam.tla;
    if (tla) {
      const mapped = mapCode(tla);
      const known = knownTeams.find((t) => t.code === mapped);
      if (known) { idToCode[apiTeam.id] = mapped; return mapped; }
    }
    const name = (apiTeam.name || "").toLowerCase();
    if (codeByName[name]) { idToCode[apiTeam.id] = codeByName[name]; return codeByName[name]; }
    const shortName = (apiTeam.shortName || "").toLowerCase();
    if (codeByName[shortName]) { idToCode[apiTeam.id] = codeByName[shortName]; return codeByName[shortName]; }
    if (tla) { idToCode[apiTeam.id] = mapCode(tla); return mapCode(tla); }
    return null;
  }

  // Build groups from standings.
  const groups = {};
  for (const s of standingsData.standings || []) {
    const g = groupLetter(s.group);
    if (!g) continue;
    const codes = [];
    for (const row of s.table || []) {
      const code = resolveCode(row.team);
      if (code) codes.push(code);
    }
    if (codes.length) groups[g] = codes;
  }

  // Build matches array.
  const matches = [];
  let mid = 1;
  let latestDate = null;

  // Sort API matches by date, then matchday.
  const apiMatches = (matchData.matches || []).sort(
    (a, b) => (a.utcDate || "").localeCompare(b.utcDate || "") || (a.matchday || 0) - (b.matchday || 0)
  );

  for (const am of apiMatches) {
    const stage = mapStage(am.stage);
    const group = groupLetter(am.group);
    const home = resolveCode(am.homeTeam);
    const away = resolveCode(am.awayTeam);
    const result = matchResult(am);
    const date = fmtDate(am.utcDate);

    const scorers1 = parseGoals(am.goals, am.homeTeam?.id);
    const scorers2 = parseGoals(am.goals, am.awayTeam?.id);
    const ownGoals1 = countOwnGoalsForTeam(am.goals, am.homeTeam?.id);
    const ownGoals2 = countOwnGoalsForTeam(am.goals, am.awayTeam?.id);

    // Rich details from Football-Data.org
    const goalDetails1 = parseGoalDetails(am.goals, am.homeTeam?.id);
    const goalDetails2 = parseGoalDetails(am.goals, am.awayTeam?.id);
    const halfTime = am.score?.halfTime;
    const extraTime = am.score?.extraTime;
    const penalties = am.score?.penalties;
    const referees = parseReferees(am.referees);
    const status = mapStatus(am.status);
    const kickoff = am.utcDate || null;
    const matchday = am.matchday || null;

    const entry = {
      id: `M${String(mid).padStart(3, "0")}`,
      apiId: am.id || null,
      stage,
      date,
      venue: mapVenue(am),
      home: home || null,
      away: away || null,
      result,
      scorers1,
      scorers2,
      ownGoals1,
      ownGoals2,
      goalDetails1,
      goalDetails2,
      halfTime: halfTime?.home != null ? [halfTime.home, halfTime.away] : null,
      extraTime: extraTime?.home != null ? [extraTime.home, extraTime.away] : null,
      penalties: penalties?.home != null ? [penalties.home, penalties.away] : null,
      referees,
      status,
      kickoff,
      matchday,
    };
    if (stage === "group" && group) entry.group = group;
    if (stage !== "group") {
      entry.slot = mid;
      entry.matchNo = am.id || null;
      if (!home) entry.homeLabel = am.homeTeam?.name || null;
      if (!away) entry.awayLabel = am.awayTeam?.name || null;
    }

    matches.push(entry);
    mid++;
    if (result && date && (!latestDate || date > latestDate)) latestDate = date;
  }

  return { groups, matches, asOf: latestDate || fmtDate(new Date().toISOString()) };
}
