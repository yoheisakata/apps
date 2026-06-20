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

// Format a population count like 21800000 -> "約 2,180万人".
export function formatPop(n) {
  if (!n) return null;
  if (n >= 10000) {
    const man = Math.round(n / 10000);
    return "約 " + man.toLocaleString("ja-JP") + "万人";
  }
  return n.toLocaleString("ja-JP") + "人";
}
