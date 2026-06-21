const STAGE_LABEL = {
  group: "グループステージ",
  r32: "ラウンド32",
  r16: "ラウンド16",
  qf: "準々決勝",
  sf: "準決勝",
  third: "3位決定戦",
  final: "決勝",
};

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

function jpLabel(label) {
  if (!label) return "未定";
  return label
    .replace(/Winner Group ([A-L])/, "$1組 1位")
    .replace(/Runner-up Group ([A-L])/, "$1組 2位")
    .replace(/3rd Group ([A-L/]+)/, "3位 ($1組)")
    .replace(/Winner Match (\d+)/, "第$1試合 勝者")
    .replace(/Loser Match (\d+)/, "第$1試合 敗者");
}

function teamBlock(code, label, data) {
  if (code) {
    const t = data.byCode[code];
    if (!t) return `<div class="mm-team-block"><span class="mm-flag">🏳️</span><span class="mm-tname">${esc(code)}</span></div>`;
    return `<div class="mm-team-block">
      <span class="mm-flag">${t.flag}</span>
      <span class="mm-tname">${esc(t.name)}</span>
      <span class="mm-tmeta">${t.group ? t.group + "組" : ""}${t.rank ? " · FIFA " + t.rank + "位" : ""}</span>
    </div>`;
  }
  return `<div class="mm-team-block tbd"><span class="mm-flag">🏳️</span><span class="mm-tname">${jpLabel(label)}</span></div>`;
}

function scorerList(scorers) {
  if (!scorers || !scorers.length) return "";
  const counts = {};
  for (const s of scorers) counts[s] = (counts[s] || 0) + 1;
  return Object.entries(counts)
    .map(([name, n]) => `<span class="mm-scorer">⚽ ${esc(name)}${n > 1 ? ` ×${n}` : ""}</span>`)
    .join("");
}

function youtubeSearchUrl(homeName, awayName) {
  const q = `${homeName} vs ${awayName} FIFA World Cup 2026 highlights`;
  return `https://www.youtube.com/results?search_query=${encodeURIComponent(q)}`;
}

const YT_API_KEY = "AIzaSyDBbXxm-TIAF5Vq4a8WGZQPrcOURWptLII";
const YT_CACHE = new Map();

async function searchYouTube(homeName, awayName) {
  const key = `${homeName}|${awayName}`;
  if (YT_CACHE.has(key)) return YT_CACHE.get(key);
  const q = `${homeName} vs ${awayName} FIFA World Cup 2026 highlights`;
  const params = new URLSearchParams({
    part: "snippet",
    q,
    type: "video",
    maxResults: "1",
    key: YT_API_KEY,
  });
  try {
    const res = await fetch(`https://www.googleapis.com/youtube/v3/search?${params}`);
    if (!res.ok) throw new Error("YT API " + res.status);
    const json = await res.json();
    const item = json.items?.[0];
    const result = item ? { videoId: item.id.videoId, title: item.snippet.title } : null;
    YT_CACHE.set(key, result);
    return result;
  } catch (e) {
    YT_CACHE.set(key, null);
    return null;
  }
}

export function createMatchModal() {
  const overlay = document.getElementById("match-modal");
  if (!overlay) return { open() {}, close() {} };

  const body = overlay.querySelector(".mm-body");
  const closeBtn = overlay.querySelector(".city-modal-close");
  const backdrop = overlay.querySelector(".city-modal-backdrop");

  function close() {
    overlay.classList.add("hidden");
  }

  closeBtn?.addEventListener("click", close);
  backdrop?.addEventListener("click", close);
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && !overlay.classList.contains("hidden")) close();
  });

  function open(match, data) {
    if (!match) return;
    const m = match;
    const venue = data.venueById?.[m.venue];
    const played = Array.isArray(m.result);
    const stageText = STAGE_LABEL[m.stage] || m.stage;
    const groupText = m.group ? ` ${m.group}` : "";

    const scoreSection = played
      ? `<div class="mm-score-wrap">
          <div class="mm-score-num">${m.result[0]}</div>
          <div class="mm-score-sep">-</div>
          <div class="mm-score-num">${m.result[1]}</div>
        </div>`
      : `<div class="mm-score-wrap"><div class="mm-vs-label">VS</div></div>`;

    const homeScorers = scorerList(m.scorers1);
    const awayScorers = scorerList(m.scorers2);

    const scorersSection = (homeScorers || awayScorers)
      ? `<div class="mm-scorers">
          <div class="mm-scorers-side home">${homeScorers || '<span class="mm-no-goal">—</span>'}</div>
          <div class="mm-scorers-divider"></div>
          <div class="mm-scorers-side away">${awayScorers || '<span class="mm-no-goal">—</span>'}</div>
        </div>`
      : played
        ? `<div class="mm-scorers"><div class="mm-scorers-empty">得点者データなし</div></div>`
        : "";

    const statusText = played
      ? "試合終了"
      : m.date
        ? "未実施"
        : "日程未定";
    const statusClass = played ? "finished" : "upcoming";

    const homeTeam = data.byCode?.[m.home];
    const awayTeam = data.byCode?.[m.away];
    const showHighlight = played && homeTeam && awayTeam;

    body.innerHTML = `
      <div class="mm-header">
        <span class="mm-stage">${esc(stageText)}${esc(groupText)}</span>
        <span class="mm-match-id">${esc(m.id)}</span>
      </div>
      <div class="mm-status ${statusClass}">${statusText}</div>
      <div class="mm-teams">
        ${teamBlock(m.home, m.homeLabel, data)}
        ${scoreSection}
        ${teamBlock(m.away, m.awayLabel, data)}
      </div>
      ${scorersSection}
      ${showHighlight ? '<div id="mm-yt-area"><div class="mm-yt-loading">🎬 ハイライト動画を検索中…</div></div>' : ""}
      <div class="mm-details">
        ${m.date ? `<div class="mm-detail-row"><span class="mm-dk">日付</span><span class="mm-dv">${esc(m.date)}</span></div>` : ""}
        ${venue ? `<div class="mm-detail-row"><span class="mm-dk">スタジアム</span><span class="mm-dv">${esc(venue.stadium)}</span></div>` : ""}
        ${venue ? `<div class="mm-detail-row"><span class="mm-dk">都市</span><span class="mm-dv">${esc(venue.city)}</span></div>` : ""}
        ${venue?.capacity ? `<div class="mm-detail-row"><span class="mm-dk">収容人数</span><span class="mm-dv">${venue.capacity.toLocaleString()}人</span></div>` : ""}
      </div>
    `;

    overlay.classList.remove("hidden");

    if (showHighlight) {
      const ytArea = body.querySelector("#mm-yt-area");
      const result = await searchYouTube(homeTeam.name, awayTeam.name);
      if (!ytArea || overlay.classList.contains("hidden")) return;
      if (result) {
        ytArea.innerHTML = `
          <div class="mm-yt-embed">
            <iframe src="https://www.youtube.com/embed/${result.videoId}" title="${esc(result.title)}"
              frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture"
              allowfullscreen></iframe>
          </div>
          <a class="mm-yt-more" href="${youtubeSearchUrl(homeTeam.name, awayTeam.name)}" target="_blank" rel="noopener">
            YouTubeでもっと見る →
          </a>`;
      } else {
        ytArea.innerHTML = `
          <a class="mm-highlight-btn" href="${youtubeSearchUrl(homeTeam.name, awayTeam.name)}" target="_blank" rel="noopener">
            <span class="mm-yt-icon">▶</span> YouTubeでハイライトを検索
          </a>`;
      }
    }
  }

  return { open, close };
}
