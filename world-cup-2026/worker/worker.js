const API_BASE = "https://api.football-data.org/v4";
const ALLOWED_PATHS = [
  /^\/competitions\/WC\/matches/,
  /^\/competitions\/WC\/standings/,
  /^\/competitions\/WC\/scorers/,
  /^\/matches\/\d+$/,
];

export default {
  async fetch(request, env) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: corsHeaders() });
    }

    const url = new URL(request.url);
    const path = url.pathname;

    if (!ALLOWED_PATHS.some((re) => re.test(path))) {
      return json({ error: "Not found" }, 404);
    }

    const apiUrl = `${API_BASE}${path}${url.search}`;
    const token = env.FOOTBALL_API_TOKEN || "";

    try {
      const res = await fetch(apiUrl, {
        headers: {
          "X-Auth-Token": token,
          "Accept": "application/json",
        },
      });

      const body = await res.text();
      return new Response(body, {
        status: res.status,
        headers: {
          ...corsHeaders(),
          "Content-Type": "application/json",
          "Cache-Control": "public, max-age=60",
        },
      });
    } catch (e) {
      return json({ error: e.message }, 502);
    }
  },
};

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "GET, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
  };
}

function json(obj, status = 200) {
  return new Response(JSON.stringify(obj), {
    status,
    headers: { ...corsHeaders(), "Content-Type": "application/json" },
  });
}
