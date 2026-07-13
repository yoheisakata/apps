// CORS proxy for the free FIFA rankings API.
// The paid Football-Data.org proxying was removed — match data now comes from
// Wikipedia + openfootball, fetched directly by the browser (both are
// CORS-friendly and need no key), so this worker only serves /fifa-rankings.
const FIFA_API_BASE = "https://api.fifa.com/api/v3";

export default {
  async fetch(request, env, ctx) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const url = new URL(request.url);
    if (url.pathname === "/fifa-rankings") {
      return handleFifaRankings(url, ctx);
    }
    return json({ error: "Not found" }, 404);
  },
};

async function handleFifaRankings(url, ctx) {
  const cache = caches.default;
  const cacheKey = new Request(url.toString(), { method: "GET" });
  const cached = await cache.match(cacheKey);
  if (cached) return addCors(cached);

  const fifaUrl = `${FIFA_API_BASE}/fifarankings/rankings/live?gender=1&sportType=0&language=en`;
  try {
    const res = await fetch(fifaUrl, {
      headers: { "Accept": "application/json" },
    });
    const body = await res.text();
    const response = new Response(body, {
      status: res.status,
      headers: {
        ...corsHeaders(),
        "Content-Type": "application/json",
        "Cache-Control": "public, max-age=3600",
      },
    });
    if (res.ok) {
      ctx.waitUntil(cache.put(cacheKey, response.clone()));
    }
    return response;
  } catch (e) {
    return json({ error: e.message }, 502);
  }
}

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
  };
}

function addCors(response) {
  const headers = new Headers(response.headers);
  for (const [k, v] of Object.entries(corsHeaders())) headers.set(k, v);
  return new Response(response.body, { status: response.status, headers });
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}
