// Live data: fetch the real group draw + match results at runtime from the
// English Wikipedia MediaWiki API (CORS-enabled via origin=*), parsing the
// {{#invoke:football box}} templates in each group's sub-article.
//
// This mirrors the offline extraction that seeded data/*.json, so the parsed
// shape matches: { groups: {A:[...]}, matches: [...], asOf }.
// On any failure the caller falls back to the bundled static JSON.

const API = "https://en.wikipedia.org/w/api.php";
const GROUP_KEYS = "ABCDEFGHIJKL".split("");

// Wikipedia city strings -> our venue ids (matches data/venues.json).
const CITY_TO_VENUE = {
  "Mexico City": "mex",
  Zapopan: "gdl",
  "Guadalupe, Nuevo León": "mty",
  Toronto: "tor",
  Vancouver: "van",
  Atlanta: "atl",
  "Foxborough, Massachusetts": "bos",
  "Arlington, Texas": "dal",
  Houston: "hou",
  "Kansas City, Missouri": "kan",
  "Inglewood, California": "lax",
  "Miami Gardens, Florida": "mia",
  "East Rutherford, New Jersey": "nyc",
  Philadelphia: "phi",
  "Santa Clara, California": "sfo",
  Seattle: "sea",
};

function field(body, key) {
  // Capture "|key= ... " up to the next top-level "\n|". Only spaces/tabs are
  // consumed after "=" (NOT newlines) — otherwise an empty field like
  // "|goals1=\n|goals2=..." would swallow the following field's content.
  const re = new RegExp("\\|\\s*" + key + "\\s*=[ \\t]*([\\s\\S]*?)(?=\\n\\|)");
  const m = body.match(re);
  return m ? m[1].trim() : "";
}

function flagCode(s) {
  const m = s.match(/\{\{#invoke:flag\|[a-z-]+\|([A-Z]{3})/);
  return m ? m[1] : null;
}

function parseScore(s) {
  const m = s.match(/(\d+)\s*[–-]\s*(\d+)/);
  return m ? [Number(m[1]), Number(m[2])] : null;
}

function parseDate(s) {
  const m = s.match(/Start date\|(\d+)\|(\d+)\|(\d+)/);
  if (!m) return null;
  const p = (n) => String(n).padStart(2, "0");
  return `${m[1]}-${p(m[2])}-${p(m[3])}`;
}

function parseTime(s) {
  const m = s.match(/(\d{1,2}):(\d{2})/);
  return m ? `${m[1].padStart(2, "0")}:${m[2]}` : null;
}

function parseCity(s) {
  // last [[...]] link in the stadium field is the city
  const links = [...s.matchAll(/\[\[([^\]|]+?)(?:\|[^\]]+)?\]\]/g)].map((m) => m[1]);
  return links.length ? links[links.length - 1] : s.trim();
}

// Match number referenced inside a {{score link|...|Match 73}} field.
function parseMatchNo(s) {
  const m = s.match(/Match (\d+)/);
  return m ? Number(m[1]) : null;
}

// Strip an unresolved slot label like "Winner Group A" / "Runner-up Group B"
// / "Winner Match 73" down to readable text (no flag templates / comments).
function cleanSlotLabel(s) {
  return s
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/\{\{#invoke:flag[^}]*\}\}/g, "")
    .replace(/\[\[[^\]|]*\|([^\]]*)\]\]/g, "$1")
    .replace(/\[\[([^\]]*)\]\]/g, "$1")
    .trim();
}

// Extract a CONFIRMED team code from a knockout slot field. On Wikipedia an
// unfilled slot is a commented-out flag with a placeholder label, e.g.
//   <!--{{#invoke:flag|fb-rt|}}-->Runner-up Group A
// whereas a confirmed slot has a live flag invoke with a 3-letter code:
//   {{#invoke:flag|fb-rt|GER}}
// Strip HTML comments first so the empty commented invoke can't false-match,
// then read the code. Returns the code (e.g. "GER") or null when still a slot.
function knockoutTeamCode(s) {
  return flagCode(s.replace(/<!--[\s\S]*?-->/g, ""));
}

// Parse the knockout-stage article. Each football box has a date, stadium,
// a match number (in the score link) and two slots. A slot is either a
// confirmed team (code1/code2) or, until then, a placeholder (label1/label2).
// Also captures the result + scorers once a knockout match is played. Returns
// an array ordered as in the article (bracket order).
function parseKnockoutArticle(wikitext) {
  const stageFor = (sec) =>
    sec.startsWith("R32") ? "r32"
    : sec.startsWith("R16") ? "r16"
    : sec.startsWith("QF") ? "qf"
    : sec.startsWith("SF") ? "sf"
    : sec === "3rd" ? "third"
    : sec.startsWith("F") ? "final"
    : null;

  const out = [];
  // Case-insensitive template name: the round-of-32 article writes
  // {{#invoke:Football box|main (capital F), the knockout article lowercase.
  const re = /\{\{#invoke:[Ff]ootball box\|main([\s\S]*?)\n\}\}/g;
  let m;
  while ((m = re.exec(wikitext))) {
    const body = "|" + m[1];
    // nearest preceding <section begin="..."> gives the round id
    const pre = wikitext.slice(0, m.index);
    const secs = [...pre.matchAll(/<section begin="?([A-Za-z0-9-]+)"?/g)];
    const sec = secs.length ? secs[secs.length - 1][1] : "?";
    const t1 = field(body, "team1");
    const t2 = field(body, "team2");
    const g1 = field(body, "goals1");
    const g2 = field(body, "goals2");
    out.push({
      stage: stageFor(sec),
      matchNo: parseMatchNo(field(body, "score")),
      date: parseDate(field(body, "date")),
      time: parseTime(field(body, "time")),
      city: parseCity(field(body, "stadium")),
      code1: knockoutTeamCode(t1),
      code2: knockoutTeamCode(t2),
      label1: cleanSlotLabel(t1),
      label2: cleanSlotLabel(t2),
      result: parseScore(field(body, "score")),
      // Penalty-shootout score (e.g. |penaltyscore=3–4) — without it a drawn
      // knockout tie can't fold its winner into the next round of the bracket.
      penalties: parseScore(field(body, "penaltyscore")),
      scorers1: parseScorers(g1),
      scorers2: parseScorers(g2),
      scorerDetails1: parseScorerDetails(g1),
      scorerDetails2: parseScorerDetails(g2),
      ownGoals1: countOwnGoals(g1),
      ownGoals2: countOwnGoals(g2),
    });
  }
  return out;
}

// Extract scorer display names from a goals field like:
//   *[[Kai Havertz|Havertz]] 45+5' pen., 88'   *[[Manzambi]] 74, 90
// One line per scorer; the number of goals is the count of minute markers on
// that line (the apostrophe after the minute is optional, e.g. "74, 90"). Own
// goals ("o.g.") credit the opponent, so we skip them. Returns one entry per
// goal (a two-goal line yields two entries).
function parseScorers(s) {
  const out = [];
  for (const line of s.split("\n")) {
    const t = line.trim();
    // A scorer line contains a player wikilink. It may or may not start with a
    // "*" bullet (Wikipedia is inconsistent), so we key off the link, not "*".
    if (!t) continue;
    if (/o\.g\./i.test(t)) continue; // own goal: not credited to this scorer
    const m = t.match(/\[\[[^\]|]*\|([^\]]+)\]\]|\[\[([^\]]+)\]\]/);
    if (!m) continue;
    const name = (m[1] || m[2]).trim();
    // Count minute markers AFTER stripping the wikilink (so digits in a name
    // can't be miscounted). Minutes look like 9, 45+5, 90+2 with an optional ’.
    const after = t.replace(/\[\[[^\]]*\]\]/g, "");
    const goals = (after.match(/\d+(?:\+\d+)?/g) || []).length || 1;
    for (let i = 0; i < goals; i++) out.push(name);
  }
  return out;
}

// Rich scorer detail: { name, minute, pen } for each goal.
// Parses the same format as parseScorers but keeps the minute markers.
function parseScorerDetails(s) {
  const out = [];
  for (const line of s.split("\n")) {
    const t = line.trim();
    if (!t) continue;
    const isOG = /o\.g\./i.test(t);
    const m = t.match(/\[\[[^\]|]*\|([^\]]+)\]\]|\[\[([^\]]+)\]\]/);
    if (!m) continue;
    const name = (m[1] || m[2]).trim();
    const isPen = /pen\./i.test(t);
    const after = t.replace(/\[\[[^\]]*\]\]/g, "");
    const mins = after.match(/\d+(?:\+\d+)?/g) || [];
    if (mins.length) {
      for (const min of mins) {
        out.push({ name, minute: min, pen: isPen && mins.indexOf(min) === 0, og: isOG });
      }
    } else {
      out.push({ name, minute: null, pen: isPen, og: isOG });
    }
  }
  return out;
}

// Count own goals in a goals field. In Wikipedia, an own goal appears in the
// goals list of the team that BENEFITED (the scoring side), marked "o.g.".
function countOwnGoals(s) {
  return (s.match(/o\.g\./gi) || []).length;
}

function parseGroupArticle(wikitext) {
  const matches = [];
  const re = /\{\{#invoke:football box\|main/g;
  let m;
  while ((m = re.exec(wikitext))) {
    // wide slice so goals fields aren't truncated for high-scoring games
    const body = wikitext.slice(m.index, m.index + 2600);
    const g1 = field(body, "goals1");
    const g2 = field(body, "goals2");
    matches.push({
      home: flagCode(field(body, "team1")),
      away: flagCode(field(body, "team2")),
      result: parseScore(field(body, "score")),
      date: parseDate(field(body, "date")),
      time: parseTime(field(body, "time")),
      city: parseCity(field(body, "stadium")),
      scorers1: parseScorers(g1),
      scorers2: parseScorers(g2),
      scorerDetails1: parseScorerDetails(g1),
      scorerDetails2: parseScorerDetails(g2),
      ownGoals1: countOwnGoals(g1),
      ownGoals2: countOwnGoals(g2),
    });
  }
  return matches;
}

const KNOCKOUT_TITLE = "2026 FIFA World Cup knockout stage";
// The R32 football boxes live in their own article; the knockout-stage article
// only transcludes them via {{#lst:...}} (which the raw wikitext API does not
// expand), so we must fetch this article too.
const R32_TITLE = "2026 FIFA World Cup round of 32";

// Fetch + parse all 12 groups + the knockout articles. Returns
// { groups, matches, asOf } or throws.
export async function fetchLiveData() {
  const titles = [
    ...GROUP_KEYS.map((g) => `2026 FIFA World Cup Group ${g}`),
    R32_TITLE,
    KNOCKOUT_TITLE,
  ].join("|");
  const params = new URLSearchParams({
    action: "query",
    prop: "revisions",
    rvprop: "content",
    rvslots: "main",
    titles,
    format: "json",
    formatversion: "2",
    origin: "*",
  });
  const res = await fetch(`${API}?${params}`);
  if (!res.ok) throw new Error("API HTTP " + res.status);
  const json = await res.json();
  const pages = json?.query?.pages || [];

  // Index page content by group letter (from the "... Group X" title).
  const byGroup = {};
  let koContent = null;
  let r32Content = null;
  for (const p of pages) {
    const content = p?.revisions?.[0]?.slots?.main?.content;
    if (!content) continue;
    const g = (p.title.match(/Group ([A-L])$/) || [])[1];
    if (g) byGroup[g] = content;
    else if (p.title === KNOCKOUT_TITLE) koContent = content;
    else if (p.title === R32_TITLE) r32Content = content;
  }
  if (Object.keys(byGroup).length === 0) {
    throw new Error("no group articles found");
  }

  const groups = {};
  const matches = [];
  let mid = 1;
  let latestDate = null;

  for (const g of GROUP_KEYS) {
    const parsed = parseGroupArticle(byGroup[g]);
    if (parsed.length === 0) continue;

    // group membership = team codes in order of first appearance
    const seen = [];
    for (const mm of parsed) {
      for (const c of [mm.home, mm.away]) if (c && !seen.includes(c)) seen.push(c);
    }
    groups[g] = seen;

    for (const mm of parsed) {
      const venue = CITY_TO_VENUE[mm.city] || null;
      matches.push({
        id: `M${String(mid).padStart(3, "0")}`,
        stage: "group",
        group: g,
        date: mm.date,
        time: mm.time,
        venue,
        home: mm.home,
        away: mm.away,
        result: mm.result,
        scorers1: mm.scorers1,
        scorers2: mm.scorers2,
        scorerDetails1: mm.scorerDetails1,
        scorerDetails2: mm.scorerDetails2,
        ownGoals1: mm.ownGoals1,
        ownGoals2: mm.ownGoals2,
      });
      mid++;
      if (mm.result && mm.date && (!latestDate || mm.date > latestDate)) latestDate = mm.date;
    }
  }

  // Knockout matches: use the real schedule/venue/slot-labels from the
  // knockout articles when available; otherwise fall back to bare placeholders.
  // R32 boxes come from their own article; both articles tag each box with a
  // <section begin="R32-…/R16-…"> marker, so one concatenated parse works.
  const koSpec = [["r32", 16], ["r16", 8], ["qf", 4], ["sf", 2], ["third", 1], ["final", 1]];
  const koParsed = parseKnockoutArticle((r32Content || "") + "\n" + (koContent || ""));
  const koByStage = {};
  for (const b of koParsed) (koByStage[b.stage] ||= []).push(b);

  for (const [stage, count] of koSpec) {
    const bucket = koByStage[stage] || [];
    for (let i = 0; i < count; i++) {
      const b = bucket[i];
      matches.push({
        id: `M${String(mid).padStart(3, "0")}`,
        stage,
        slot: i + 1,
        // Single-match stages have a fixed official number (third place = 103,
        // final = 104); multi-match stages get theirs from the openfootball
        // supplement (matched by team pair) since the articles don't carry it.
        matchNo: b?.matchNo ?? (stage === "third" ? 103 : stage === "final" ? 104 : null),
        date: b?.date ?? null,
        time: b?.time ?? null,
        venue: b ? CITY_TO_VENUE[b.city] || null : null,
        // A confirmed slot resolves to a real team code; otherwise stays a
        // placeholder label ("Winner Group C", "3rd Group A/B/…").
        home: b?.code1 || null,
        away: b?.code2 || null,
        homeLabel: b?.label1 || null,
        awayLabel: b?.label2 || null,
        result: b?.result ?? null,
        penalties: b?.penalties ?? null,
        scorers1: b?.scorers1 || [],
        scorers2: b?.scorers2 || [],
        scorerDetails1: b?.scorerDetails1 || [],
        scorerDetails2: b?.scorerDetails2 || [],
        ownGoals1: b?.ownGoals1 || 0,
        ownGoals2: b?.ownGoals2 || 0,
      });
      mid++;
      if (b?.result && b?.date && (!latestDate || b.date > latestDate)) latestDate = b.date;
    }
  }

  return { groups, matches, asOf: latestDate };
}

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
