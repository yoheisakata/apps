// Team list view: all 48 participating nations grouped by confederation,
// each card showing the flag, name, group, and FIFA ranking. Clicking a team
// opens its country page (owned by the schedule tab) via the onTeam callback.

const CONFED_NAME = {
  UEFA: "欧州 (UEFA)",
  CAF: "アフリカ (CAF)",
  AFC: "アジア (AFC)",
  CONCACAF: "北中米カリブ (CONCACAF)",
  CONMEBOL: "南米 (CONMEBOL)",
  OFC: "オセアニア (OFC)",
  TBD: "未定 (大陸間プレーオフ)",
};
// Display order (largest allocations first, host confederation grouped in).
const CONFED_ORDER = ["UEFA", "CONMEBOL", "CONCACAF", "CAF", "AFC", "OFC", "TBD"];

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

export function createTeamList({ container, data, onTeam }) {
  function teamCard(t) {
    return `<button class="tl-card team-link" data-team="${esc(t.code)}">
      <span class="tl-flag">${t.flag}</span>
      <span class="tl-info">
        <span class="tl-name">${esc(t.name)}</span>
        <span class="tl-grp">${esc(t.group)}組${t.host ? " · 🏠開催国" : ""}</span>
      </span>
      <span class="tl-rank">${t.rank ? `${t.rank}位` : "—"}</span>
    </button>`;
  }

  function section(confed, teams) {
    // sort by FIFA ranking ascending (best first); unranked last
    const sorted = [...teams].sort((a, b) => (a.rank || 999) - (b.rank || 999));
    return `<div class="tl-section">
      <h3 class="tl-confed">${CONFED_NAME[confed] || confed} <span class="sub">${teams.length}チーム</span></h3>
      <div class="tl-grid">${sorted.map(teamCard).join("")}</div>
    </div>`;
  }

  function render() {
    const byConfed = {};
    for (const t of data.teams) (byConfed[t.confed] ||= []).push(t);
    const order = [
      ...CONFED_ORDER.filter((c) => byConfed[c]),
      ...Object.keys(byConfed).filter((c) => !CONFED_ORDER.includes(c)),
    ];

    container.innerHTML = `
      <h2 class="section-title">👥 出場チーム一覧 <span class="sub">${data.teams.length}チーム</span></h2>
      <div class="banner">連盟（カンファレンス）ごとに、FIFAランキング順で表示。チームをクリックすると登録メンバー・本大会得点のページへ。<br>※ FIFAランキングは概数（2025年後半時点の目安）。</div>
      ${order.map((c) => section(c, byConfed[c])).join("")}
    `;

    container.querySelectorAll(".team-link").forEach((el) =>
      el.addEventListener("click", () => onTeam?.(el.dataset.team))
    );
  }

  return { render };
}
