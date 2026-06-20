// Shared standings logic. Used by the schedule table and the prediction engine.
// Points: win=3, draw=1. Tiebreakers (simplified): points, goal difference, goals for.

// Compute the ordered standings array for one group.
// Each row: { code, pld, w, d, l, gf, ga, gd, pts }.
export function groupStandings(data, groupKey) {
  const teams = data.groups[groupKey];
  const row = Object.fromEntries(
    teams.map((c) => [c, { code: c, pld: 0, w: 0, d: 0, l: 0, gf: 0, ga: 0, pts: 0 }])
  );
  for (const m of data.matches) {
    if (m.stage !== "group" || m.group !== groupKey || !m.result) continue;
    const H = row[m.home];
    const A = row[m.away];
    if (!H || !A) continue;
    const [hs, as] = m.result;
    H.pld++; A.pld++;
    H.gf += hs; H.ga += as; A.gf += as; A.ga += hs;
    if (hs > as) { H.w++; A.l++; H.pts += 3; }
    else if (hs < as) { A.w++; H.l++; A.pts += 3; }
    else { H.d++; A.d++; H.pts++; A.pts++; }
  }
  return Object.values(row)
    .map((r) => ({ ...r, gd: r.gf - r.ga }))
    .sort((a, b) => b.pts - a.pts || b.gd - a.gd || b.gf - a.gf);
}

