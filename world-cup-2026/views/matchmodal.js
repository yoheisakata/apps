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

// Rich goal detail list with minute, type (PK/OG), and assist.
function goalDetailList(details) {
  if (!details || !details.length) return "";
  return details.map((g) => {
    const min = g.minute != null
      ? `${g.minute}${g.injuryTime ? `+${g.injuryTime}` : ""}'`
      : "";
    const tag = g.type === "OWN" ? ' <span class="mm-og-tag">OG</span>'
      : g.type === "PENALTY" ? ' <span class="mm-pk-tag">PK</span>'
      : "";
    const assist = g.assist ? ` <span class="mm-assist">(${esc(g.assist.split(" ").pop())})</span>` : "";
    return `<div class="mm-goal-detail">
      <span class="mm-goal-min">${min}</span>
      <span class="mm-goal-icon">${g.type === "OWN" ? "🔴" : "⚽"}</span>
      <span class="mm-goal-name">${esc(g.name)}${tag}${assist}</span>
    </div>`;
  }).join("");
}

function formatKickoff(iso) {
  if (!iso) return null;
  const d = new Date(iso);
  if (isNaN(d)) return null;
  const p = (n) => String(n).padStart(2, "0");
  return `${p(d.getHours())}:${p(d.getMinutes())}`;
}

const STATUS_LABEL = {
  scheduled: "未実施",
  timed: "未実施",
  live: "🔴 試合中",
  halftime: "🔴 ハーフタイム",
  extra_time: "🔴 延長戦",
  penalties: "🔴 PK戦",
  finished: "試合終了",
  suspended: "中断",
  postponed: "延期",
  cancelled: "中止",
};

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

  async function open(match, data) {
    if (!match) return;
    const m = match;
    const venue = data.venueById?.[m.venue];
    const played = Array.isArray(m.result);
    const stageText = STAGE_LABEL[m.stage] || m.stage;
    const groupText = m.group ? ` ${m.group}` : "";

    const hasRichGoals = m.goalDetails1?.length || m.goalDetails2?.length;
    const isLive = m.status === "live" || m.status === "halftime" || m.status === "extra_time" || m.status === "penalties";

    const scoreSection = played || isLive
      ? `<div class="mm-score-wrap">
          <div class="mm-score-num">${m.result ? m.result[0] : "0"}</div>
          <div class="mm-score-sep">-</div>
          <div class="mm-score-num">${m.result ? m.result[1] : "0"}</div>
        </div>`
      : `<div class="mm-score-wrap"><div class="mm-vs-label">VS</div></div>`;

    // Sub-scores: half-time, extra time, penalties
    let subScores = "";
    if (m.halfTime) subScores += `<span class="mm-sub-score">前半 ${m.halfTime[0]}-${m.halfTime[1]}</span>`;
    if (m.extraTime) subScores += `<span class="mm-sub-score">延長 ${m.extraTime[0]}-${m.extraTime[1]}</span>`;
    if (m.penalties) subScores += `<span class="mm-sub-score mm-pk-score">PK ${m.penalties[0]}-${m.penalties[1]}</span>`;
    const subScoreSection = subScores ? `<div class="mm-sub-scores">${subScores}</div>` : "";

    // Use rich goal details if available (from Football-Data.org), else simple list
    let scorersSection = "";
    if (hasRichGoals) {
      const homeGoals = goalDetailList(m.goalDetails1);
      const awayGoals = goalDetailList(m.goalDetails2);
      scorersSection = `<div class="mm-scorers rich">
        <div class="mm-scorers-side home">${homeGoals || '<span class="mm-no-goal">—</span>'}</div>
        <div class="mm-scorers-divider"></div>
        <div class="mm-scorers-side away">${awayGoals || '<span class="mm-no-goal">—</span>'}</div>
      </div>`;
    } else {
      const homeScorers = scorerList(m.scorers1);
      const awayScorers = scorerList(m.scorers2);
      scorersSection = (homeScorers || awayScorers)
        ? `<div class="mm-scorers">
            <div class="mm-scorers-side home">${homeScorers || '<span class="mm-no-goal">—</span>'}</div>
            <div class="mm-scorers-divider"></div>
            <div class="mm-scorers-side away">${awayScorers || '<span class="mm-no-goal">—</span>'}</div>
          </div>`
        : played
          ? `<div class="mm-scorers"><div class="mm-scorers-empty">得点者データなし</div></div>`
          : "";
    }

    const statusText = STATUS_LABEL[m.status] || (played ? "試合終了" : m.date ? "未実施" : "日程未定");
    const statusClass = isLive ? "live" : played ? "finished" : "upcoming";

    const homeTeam = data.byCode?.[m.home];
    const awayTeam = data.byCode?.[m.away];
    const showHighlight = played && homeTeam && awayTeam;

    // Kickoff time
    const kickoffTime = formatKickoff(m.kickoff);

    // Referee info
    const mainRef = m.referees?.find((r) => r.type === "REFEREE");
    const refHtml = mainRef
      ? `<div class="mm-detail-row"><span class="mm-dk">主審</span><span class="mm-dv">${esc(mainRef.name)}${mainRef.nationality ? ` (${esc(mainRef.nationality)})` : ""}</span></div>`
      : "";

    // Matchday info
    const matchdayHtml = m.matchday
      ? `<div class="mm-detail-row"><span class="mm-dk">節</span><span class="mm-dv">第${m.matchday}節</span></div>`
      : "";

    body.innerHTML = `
      <div class="mm-header">
        <span class="mm-stage">${esc(stageText)}${esc(groupText)}</span>
        <span class="mm-match-id">${esc(m.id)}</span>
      </div>
      <div class="mm-status ${statusClass}">${esc(statusText)}</div>
      <div class="mm-teams">
        ${teamBlock(m.home, m.homeLabel, data)}
        ${scoreSection}
        ${teamBlock(m.away, m.awayLabel, data)}
      </div>
      ${subScoreSection}
      ${scorersSection}
      ${showHighlight ? '<div id="mm-yt-area"><div class="mm-yt-loading">🎬 ハイライト動画を検索中…</div></div>' : ""}
      <div class="mm-details">
        ${m.date ? `<div class="mm-detail-row"><span class="mm-dk">日付</span><span class="mm-dv">${esc(m.date)}${kickoffTime ? ` ${kickoffTime} (現地)` : ""}</span></div>` : ""}
        ${matchdayHtml}
        ${venue ? `<div class="mm-detail-row"><span class="mm-dk">スタジアム</span><span class="mm-dv">${esc(venue.stadium)}</span></div>` : ""}
        ${venue ? `<div class="mm-detail-row"><span class="mm-dk">都市</span><span class="mm-dv">${esc(venue.city)}</span></div>` : ""}
        ${venue?.capacity ? `<div class="mm-detail-row"><span class="mm-dk">収容人数</span><span class="mm-dv">${venue.capacity.toLocaleString()}人</span></div>` : ""}
        ${refHtml}
      </div>
    `;

    overlay.classList.remove("hidden");

    if (showHighlight) {
      const ytArea = body.querySelector("#mm-yt-area");
      const result = await searchYouTube(homeTeam.name, awayTeam.name);
      if (!ytArea || overlay.classList.contains("hidden")) return;
      if (result) {
        const ytUrl = `https://www.youtube.com/watch?v=${result.videoId}`;
        const thumbUrl = `https://i.ytimg.com/vi/${result.videoId}/hqdefault.jpg`;
        ytArea.innerHTML = `
          <a class="mm-yt-thumb-link" href="${ytUrl}" target="_blank" rel="noopener">
            <div class="mm-yt-thumb">
              <img src="${thumbUrl}" alt="${esc(result.title)}" />
              <div class="mm-yt-play-overlay"><span class="mm-yt-play-btn">▶</span></div>
            </div>
            <div class="mm-yt-thumb-title">${esc(result.title)}</div>
          </a>
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
