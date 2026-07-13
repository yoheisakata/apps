// FIFA rankings via the Cloudflare Worker proxy (free api.fifa.com endpoint).
// The worker handles CORS server-side; no API key involved.
//
// Football-Data.org integration used to live here too, but it was removed:
// the paid tier isn't worth it when Wikipedia + openfootball cover matches,
// standings and scorers for free (see livedata.js / openfootball.js).

const BASE = "https://wc2026-api.yoheisakata.workers.dev";

const FIFA_NAME_TO_CODE = {
  "argentina": "ARG", "algeria": "ALG", "australia": "AUS", "austria": "AUT",
  "belgium": "BEL", "bosnia and herzegovina": "BIH", "bosnia-herzegovina": "BIH",
  "brazil": "BRA", "canada": "CAN", "cape verde": "CPV", "cabo verde": "CPV",
  "cape verde islands": "CPV", "colombia": "COL", "costa rica": "CRC",
  "côte d'ivoire": "CIV", "cote d'ivoire": "CIV", "ivory coast": "CIV",
  "croatia": "CRO", "curaçao": "CUW", "curacao": "CUW",
  "czech republic": "CZE", "czechia": "CZE",
  "dr congo": "COD", "congo dr": "COD", "democratic republic of the congo": "COD",
  "ecuador": "ECU", "egypt": "EGY", "england": "ENG",
  "france": "FRA", "germany": "GER", "ghana": "GHA", "haiti": "HAI",
  "iran": "IRN", "ir iran": "IRN", "iraq": "IRQ",
  "japan": "JPN", "jordan": "JOR",
  "korea republic": "KOR", "south korea": "KOR", "republic of korea": "KOR",
  "mexico": "MEX", "morocco": "MAR",
  "netherlands": "NED", "new zealand": "NZL", "norway": "NOR",
  "panama": "PAN", "paraguay": "PAR", "portugal": "POR",
  "qatar": "QAT", "saudi arabia": "KSA",
  "scotland": "SCO", "senegal": "SEN",
  "south africa": "RSA", "spain": "ESP", "sweden": "SWE",
  "switzerland": "SUI", "tunisia": "TUN",
  "türkiye": "TUR", "turkey": "TUR",
  "united states": "USA", "usa": "USA",
  "uruguay": "URU", "uzbekistan": "UZB",
};

export async function fetchFifaRankings(knownTeams) {
  const res = await fetch(`${BASE}/fifa-rankings`);
  if (!res.ok) throw new Error(`FIFA rankings ${res.status}`);
  const json = await res.json();
  // FIFA API v3 shape: { Results: [{ TeamName:[{Description}], IdCountry, Rank,
  // TotalPoints }] }. Tolerate an older flat { rankings:[...] } shape too.
  const rankings = json?.Results || json?.rankings || [];
  if (!rankings.length) throw new Error("empty rankings");

  const codeByName = {};
  for (const t of knownTeams) codeByName[t.name.toLowerCase()] = t.code;
  const knownCodes = new Set(knownTeams.map((t) => t.code));

  const result = {};
  for (const entry of rankings) {
    const item = entry.rankingItem || entry;
    const rank = item.Rank ?? item.rank;
    const name =
      (Array.isArray(item.TeamName) ? item.TeamName[0]?.Description : item.TeamName) ||
      item.name || item.teamName || "";
    const points = item.TotalPoints ?? item.totalPoints ?? null;
    if (!rank) continue;
    // Resolve to our code: FIFA's 3-letter IdCountry when it's one we use,
    // otherwise map by team name.
    let code = item.IdCountry && knownCodes.has(item.IdCountry) ? item.IdCountry : null;
    if (!code && name) {
      code = FIFA_NAME_TO_CODE[name.toLowerCase()] || codeByName[name.toLowerCase()] || null;
    }
    if (code && !result[code]) result[code] = { rank, points };
  }
  return result;
}
