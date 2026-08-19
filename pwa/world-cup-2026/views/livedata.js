// Wikipedia squads + scorer-matching helpers.
//
// The tournament is over — the live match/knockout-result fetch pipeline that
// used to live in this file (fetchLiveData, wikitext parsers) was removed
// once the final result was baked into data/matches.json; see git history if
// it's ever needed again. What remains: fetching the player squads article
// (still used by country.js / rankings.js to show full names + bios for
// scorers) and the scorer-name matching / tournament-tally helpers built on
// top of it and on data/matches.json.

const API = "https://en.wikipedia.org/w/api.php";

const SQUADS_TITLE = "2026 FIFA World Cup squads";

// Wikipedia squad headings -> our team codes, for names that don't match
// teams.json exactly. Anything not listed is matched by normalized name.
const SQUAD_NAME_ALIASES = {
  "czech republic": "CZE",
  "south korea": "KOR",
  korea: "KOR",
  "united states": "USA",
  "ivory coast": "CIV",
  "cote d'ivoire": "CIV",
  "cape verde": "CPV",
  "dr congo": "COD",
  "republic of ireland": null,
  curacao: "CUW",
  turkey: "TUR",
  "türkiye": "TUR",
};

// Parse one {{nat fs g player|...}} row into a player object.
// Fields can contain nested {{...}} (e.g. age), so we capture up to the next
// top-level "|<key>=" rather than the first "}".
function parsePlayerRow(row) {
  const get = (k) => {
    const m = row.match(new RegExp("\\|\\s*" + k + "\\s*=\\s*([\\s\\S]*?)(?=\\|\\s*\\w+\\s*=|$)"));
    return m ? m[1].trim() : "";
  };
  // Resolve a wikilink to its display text, then drop any "(disambiguation)"
  // parenthetical like "Raúl Rangel (footballer)".
  const linkText = (s) => {
    const m = s.match(/\[\[[^\]|]*\|([^\]]+)\]\]|\[\[([^\]]+)\]\]/);
    const t = m ? (m[1] || m[2]) : s.replace(/\[\[|\]\]/g, "");
    return t.replace(/\s*\([^)]*\)\s*$/, "").trim();
  };
  // The wikilink TARGET (article title) — used to open the player's page.
  const linkTarget = (s) => {
    const m = s.match(/\[\[([^\]|]+)(?:\|[^\]]+)?\]\]/);
    return m ? m[1].trim() : null;
  };
  const nameField = get("name");
  return {
    no: Number(get("no")) || null,
    pos: get("pos"),
    name: linkText(nameField),
    wiki: linkTarget(nameField), // en.wikipedia article title, may be null
    caps: Number(get("caps")) || 0,
    goals: Number(get("goals")) || 0,
    club: linkText(get("club")),
  };
}

// Fetch + parse the squads article. Returns { byCode: { USA: [player...] } }.
// `teams` is data.teams, used to map English headings to team codes.
export async function fetchSquads(teams) {
  const norm = (s) =>
    s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").replace(/[^a-z ]/g, "").trim();
  const nameToCode = {};
  for (const t of teams) nameToCode[norm(t.name)] = t.code;

  const params = new URLSearchParams({
    action: "query",
    prop: "revisions",
    rvprop: "content",
    rvslots: "main",
    titles: SQUADS_TITLE,
    format: "json",
    formatversion: "2",
    origin: "*",
  });
  const res = await fetch(`${API}?${params}`);
  if (!res.ok) throw new Error("squads HTTP " + res.status);
  const json = await res.json();
  const wt = json?.query?.pages?.[0]?.revisions?.[0]?.slots?.main?.content;
  if (!wt) throw new Error("squads: no content");

  // headings (=== Country ===) in document order
  const heads = [...wt.matchAll(/\n=+\s*([^=\n]+?)\s*=+\n/g)].map((m) => ({
    pos: m.index,
    title: m[1].trim(),
  }));
  const codeForPos = (pos) => {
    const pre = heads.filter((h) => h.pos < pos);
    if (!pre.length) return null;
    const title = pre[pre.length - 1].title;
    const n = norm(title);
    if (n in SQUAD_NAME_ALIASES) return SQUAD_NAME_ALIASES[n];
    return nameToCode[n] || null;
  };

  const byCode = {};
  const blocks = [...wt.matchAll(/\{\{nat fs g start[\s\S]*?\{\{nat fs (?:g )?end\}\}/g)];
  for (const b of blocks) {
    const code = codeForPos(b.index);
    if (!code) continue;
    // Each player is a single line "{{nat fs g player|...}}"; match the whole
    // line (it contains a nested {{age}} template, so we can't stop at "}}").
    const rows = [...b[0].matchAll(/\{\{nat fs g player(.*)$/gm)].map((m) =>
      parsePlayerRow(m[1])
    );
    byCode[code] = rows.filter((p) => p.name);
  }
  return { byCode };
}

// Shared squads cache so multiple views fetch the (large) squads article once.
let _squadsCache = null;
let _squadsPromise = null;
export function loadSquads(teams) {
  if (_squadsCache) return Promise.resolve(_squadsCache);
  if (!_squadsPromise) _squadsPromise = fetchSquads(teams).then((s) => (_squadsCache = s));
  return _squadsPromise;
}

const _norm = (s) => s.toLowerCase().normalize("NFD").replace(/[̀-ͯ]/g, "").trim();

// Find the squad player that best matches a short scorer name. Scorer names are
// usually a surname ("Messi"), sometimes initial+surname ("J. David",
// "M. Araújo") to disambiguate same-surname team-mates. Returns the player
// object or null. Matching, strongest first:
//   1. exact full-name match
//   2. initial+surname: surname matches AND the player's first name starts with
//      that initial (so "J. David" => Jonathan, not Promise David)
//   3. plain surname: the player's surname (last word) equals the scorer
function matchScorerPlayer(players, scorer) {
  if (!players) return null;
  const sn = _norm(scorer);
  const initialMatch = sn.match(/^([a-z])\.?\s+(.+)$/); // "j. david" -> j / david
  const wantInitial = initialMatch ? initialMatch[1] : null;
  const wantSurname = (initialMatch ? initialMatch[2] : sn).split(" ").pop();

  let exact = null;
  let initialHit = null;
  let surnameHit = null;
  let firstNameHit = null; // for players known by their first name (e.g. "Vinícius Júnior")
  for (const p of players) {
    const pn = _norm(p.name);
    const words = pn.split(" ");
    const pSurname = words[words.length - 1];
    if (pn === sn) { exact = p; break; }
    if (pSurname === wantSurname || pn.endsWith(" " + sn)) {
      if (wantInitial) {
        if (words[0] && words[0][0] === wantInitial && !initialHit) initialHit = p;
      } else if (!surnameHit) {
        surnameHit = p;
      }
    } else if (!wantInitial && words[0] === wantSurname && !firstNameHit) {
      // scorer is a single name that matches the player's FIRST name (common
      // for Brazilian players). Lower priority than a surname match.
      firstNameHit = p;
    }
  }
  return exact || initialHit || surnameHit || firstNameHit || null;
}

// Resolve a short scorer name to a player's full name, falling back to the
// scorer name itself when no squad match is found.
export function resolveFullName(squads, code, scorer) {
  const p = matchScorerPlayer(squads?.byCode?.[code], scorer);
  return p ? p.name : scorer;
}

// Resolve a short scorer name to the matching squad player object (with full
// name + Wikipedia article title), or null when no squad match is found.
export function resolvePlayer(squads, code, scorer) {
  return matchScorerPlayer(squads?.byCode?.[code], scorer);
}

// Build a deduplicated player -> goals map for a team from its tournament
// scorers, assigning each scorer's goals to exactly one squad player (so
// same-surname team-mates aren't double-counted). Unmatched scorers are kept
// under their original short name.
export function teamGoalsByPlayer(squads, code, teamScorers) {
  const players = squads?.byCode?.[code] || null;
  const out = {};
  for (const [scorer, goals] of Object.entries(teamScorers || {})) {
    const p = players ? matchScorerPlayer(players, scorer) : null;
    const key = p ? p.name : scorer;
    out[key] = (out[key] || 0) + goals;
  }
  return out;
}

// Aggregate tournament goals per player from match scorer lists.
// Returns a Map: teamCode -> Map(playerName -> goals).
export function tournamentScorers(matches) {
  const byTeam = {};
  const bump = (code, name) => {
    if (!code || !name) return;
    (byTeam[code] ||= {});
    byTeam[code][name] = (byTeam[code][name] || 0) + 1;
  };
  for (const m of matches) {
    if (!m.result) continue;
    for (const s of m.scorers1 || []) bump(m.home, s);
    for (const s of m.scorers2 || []) bump(m.away, s);
  }
  return byTeam;
}

// Own goals credited TO each team (i.e. goals it benefited from), summed over
// the tournament. Returns a Map: teamCode -> count.
export function teamOwnGoals(matches) {
  const byTeam = {};
  for (const m of matches) {
    if (!m.result) continue;
    if (m.ownGoals1) byTeam[m.home] = (byTeam[m.home] || 0) + m.ownGoals1;
    if (m.ownGoals2) byTeam[m.away] = (byTeam[m.away] || 0) + m.ownGoals2;
  }
  return byTeam;
}

// Flat tournament goal ranking across all teams.
// Returns [{ name, code, goals }] sorted by goals desc, then name.
export function goalRanking(matches) {
  const byTeam = tournamentScorers(matches);
  const rows = [];
  for (const [code, scorers] of Object.entries(byTeam)) {
    for (const [name, goals] of Object.entries(scorers)) rows.push({ name, code, goals });
  }
  return rows.sort((a, b) => b.goals - a.goals || a.name.localeCompare(b.name));
}
