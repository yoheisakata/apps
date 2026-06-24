// Shared helper: fetch a photo + summary from the Wikipedia REST summary API.
// Results are cached per (lang, title) so re-opening is instant and we don't
// re-hit the API. Also exposes formatPop() for population formatting.
//
// API: https://<lang>.wikipedia.org/api/rest_v1/page/summary/<title>
// Returns { thumb, extract, pageUrl }.

const cache = new Map();

// Fetch a photo + summary. `lang` selects the Wikipedia edition ("ja" default,
// "en" for e.g. stadium articles that don't exist in Japanese).
export async function fetchWiki(title, lang = "ja") {
  if (!title) return null;
  const key = `${lang}:${title}`;
  if (cache.has(key)) return cache.get(key);
  const url =
    `https://${lang}.wikipedia.org/api/rest_v1/page/summary/` +
    encodeURIComponent(title);
  try {
    const res = await fetch(url, { headers: { accept: "application/json" } });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json();
    const out = {
      thumb: data.thumbnail ? data.thumbnail.source : null,
      extract: data.extract || "",
      pageUrl: data.content_urls?.desktop?.page || null,
    };
    cache.set(key, out);
    return out;
  } catch (e) {
    cache.set(key, null); // remember the failure too
    return null;
  }
}

// --- Player infobox (Wikipedia "Infobox football biography") ---------------
// fetchPlayerInfo() pulls the page wikitext and parses the biography infobox
// into structured fields (full name, birth, height, position, club + national
// career tables). renderPlayerInfoHtml() turns that into a compact table.
const infoCache = new Map();

const _esc = (s) =>
  String(s).replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]));

// Strip wiki markup (links, refs, bold, simple templates) to plain text.
function stripWiki(s) {
  if (!s) return "";
  return String(s)
    .replace(/<ref[^>]*\/>/gi, "")
    .replace(/<ref[^>]*>[\s\S]*?<\/ref>/gi, "")
    .replace(/<br\s*\/?>/gi, " ")
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/\{\{\s*[Nn]owrap\s*\|([^{}]*)\}\}/g, "$1")
    .replace(/\[\[[^\]|]*\|([^\]]+)\]\]/g, "$1")
    .replace(/\[\[([^\]]+)\]\]/g, "$1")
    .replace(/'''?/g, "")
    .replace(/&nbsp;/g, " ")
    .replace(/\[\d+\]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

// Brace-match the {{Infobox football biography ...}} template text.
function extractInfobox(wikitext) {
  const m = /\{\{\s*Infobox football biography/i.exec(wikitext);
  if (!m) return null;
  const start = m.index;
  let depth = 0;
  for (let i = start; i < wikitext.length - 1; i++) {
    const two = wikitext.substr(i, 2);
    if (two === "{{") { depth++; i++; }
    else if (two === "}}") { depth--; i++; if (depth === 0) return wikitext.slice(start, i + 1); }
  }
  return null;
}

// Split the infobox into top-level "key = value" params (ignoring "|" nested
// inside templates/links).
function parseParams(box) {
  const inner = box
    .replace(/^\{\{\s*Infobox football biography\s*/i, "")
    .replace(/\}\}\s*$/, "");
  const parts = [];
  let buf = "", dc = 0, db = 0;
  for (let i = 0; i < inner.length; i++) {
    const two = inner.substr(i, 2);
    if (two === "{{") { dc++; buf += two; i++; continue; }
    if (two === "}}") { dc--; buf += two; i++; continue; }
    if (two === "[[") { db++; buf += two; i++; continue; }
    if (two === "]]") { db--; buf += two; i++; continue; }
    const ch = inner[i];
    if (ch === "|" && dc === 0 && db === 0) { parts.push(buf); buf = ""; continue; }
    buf += ch;
  }
  parts.push(buf);
  const params = {};
  for (const p of parts) {
    const eq = p.indexOf("=");
    if (eq < 0) continue;
    const key = p.slice(0, eq).trim().toLowerCase();
    if (key) params[key] = p.slice(eq + 1).trim();
  }
  return params;
}

function ageFrom(y, mo, d) {
  const now = new Date();
  let a = now.getFullYear() - y;
  const mNow = now.getMonth() + 1;
  if (mNow < mo || (mNow === mo && now.getDate() < d)) a--;
  return a >= 0 && a < 120 ? a : null;
}

function parseBirth(val) {
  const m = /birth date(?: and age)?\s*\|([^}]*)/i.exec(val);
  if (m) {
    const nums = m[1].split("|").map((s) => s.trim()).filter((s) => /^\d+$/.test(s));
    if (nums.length >= 3) {
      const [y, mo, d] = nums.map(Number);
      const age = ageFrom(y, mo, d);
      return `${y}年${mo}月${d}日${age != null ? `（${age}歳）` : ""}`;
    }
  }
  return stripWiki(val);
}

function parseHeight(val) {
  const m = /height\s*\|\s*m\s*=\s*([\d.]+)/i.exec(val);
  if (m) return `${m[1]} m`;
  const ft = /height\s*\|\s*ft\s*=\s*(\d+)\s*\|\s*in\s*=\s*(\d+)/i.exec(val);
  if (ft) return `${ft[1]} ft ${ft[2]} in`;
  return stripWiki(val);
}

// Collect indexed career rows (years{i}/clubs{i}/caps{i}/goals{i}, or the
// national* variants) into [{ years, team, apps, goals }].
function careerRows(params, keys) {
  const rows = [];
  for (let i = 1; i <= 30; i++) {
    const years = params[`${keys.years}${i}`];
    const team = params[`${keys.team}${i}`];
    if (years === undefined && team === undefined) continue;
    const teamTxt = stripWiki(team || "");
    if (!teamTxt) continue;
    rows.push({
      years: stripWiki(years || ""),
      team: teamTxt,
      apps: stripWiki(params[`${keys.caps}${i}`] || ""),
      goals: stripWiki(params[`${keys.goals}${i}`] || ""),
    });
  }
  return rows;
}

function buildInfo(p) {
  return {
    fullName: stripWiki(p.full_name || p.fullname || ""),
    birth: p.birth_date ? parseBirth(p.birth_date) : "",
    birthPlace: stripWiki(p.birth_place || p.cityofbirth || ""),
    height: p.height ? parseHeight(p.height) : "",
    position: stripWiki(p.position || ""),
    currentClub: stripWiki(p.currentclub || p["current club"] || ""),
    number: stripWiki(p.clubnumber || p.number || ""),
    club: careerRows(p, { years: "years", team: "clubs", caps: "caps", goals: "goals" }),
    national: careerRows(p, { years: "nationalyears", team: "nationalteam", caps: "nationalcaps", goals: "nationalgoals" }),
  };
}

export async function fetchPlayerInfo(title, lang = "en") {
  if (!title) return null;
  const key = `info:${lang}:${title}`;
  if (infoCache.has(key)) return infoCache.get(key);
  const params = new URLSearchParams({
    action: "query", prop: "revisions", rvprop: "content", rvslots: "main",
    titles: title, format: "json", formatversion: "2", origin: "*", redirects: "1",
  });
  try {
    const res = await fetch(`https://${lang}.wikipedia.org/w/api.php?${params}`);
    if (!res.ok) throw new Error("HTTP " + res.status);
    const json = await res.json();
    const content = json?.query?.pages?.[0]?.revisions?.[0]?.slots?.main?.content;
    const box = content ? extractInfobox(content) : null;
    const info = box ? buildInfo(parseParams(box)) : null;
    infoCache.set(key, info);
    return info;
  } catch (e) {
    infoCache.set(key, null);
    return null;
  }
}

// Render the structured player info as a compact info block. Returns "" when
// there's nothing useful to show.
export function renderPlayerInfoHtml(info) {
  if (!info) return "";
  const rows = [];
  const row = (k, v) => v ? rows.push(`<div class="pinfo-row"><span class="pk">${k}</span><span class="pv">${_esc(v)}</span></div>`) : null;
  row("フルネーム", info.fullName);
  row("生年月日", info.birth);
  row("出身地", info.birthPlace);
  row("身長", info.height);
  row("ポジション", info.position);
  row("所属クラブ", info.currentClub + (info.number ? `（#${info.number}）` : ""));

  const table = (title, list) => {
    if (!list || !list.length) return "";
    const body = list.map((r) =>
      `<tr><td class="pc-yr">${_esc(r.years)}</td><td class="pc-team">${_esc(r.team)}</td><td class="pc-num">${_esc(r.apps)}</td><td class="pc-num">${r.goals !== "" ? "(" + _esc(r.goals) + ")" : ""}</td></tr>`
    ).join("");
    return `<div class="pinfo-sub">${title}</div>
      <table class="pinfo-table"><thead><tr><th>年</th><th>所属</th><th>出場</th><th>(得点)</th></tr></thead><tbody>${body}</tbody></table>`;
  };

  if (!rows.length && !info.club.length && !info.national.length) return "";
  return `<div class="pinfo">
    ${rows.length ? `<div class="pinfo-grid">${rows.join("")}</div>` : ""}
    ${table("クラブ経歴", info.club)}
    ${table("代表経歴", info.national)}
  </div>`;
}

// Format a population count like 21800000 -> "約 2,180万人".
export function formatPop(n) {
  if (!n) return null;
  if (n >= 10000) {
    const man = Math.round(n / 10000);
    return "約 " + man.toLocaleString("ja-JP") + "万人";
  }
  return n.toLocaleString("ja-JP") + "人";
}
