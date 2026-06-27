// Team list view: all 48 participating nations in one FIFA-ranking order list,
// with a confederation filter (multi-select chips + ALL). Unselected
// confederations are hidden. Clicking a team opens its country page (owned by
// the schedule tab) via the onTeam callback.

const CONFED_NAME = {
  UEFA: "欧州 (UEFA)",
  CAF: "アフリカ (CAF)",
  AFC: "アジア (AFC)",
  CONCACAF: "北中米カリブ (CONCACAF)",
  CONMEBOL: "南米 (CONMEBOL)",
  OFC: "オセアニア (OFC)",
  TBD: "未定 (大陸間プレーオフ)",
};
// Chip display order (largest allocations first).
const CONFED_ORDER = ["UEFA", "CONMEBOL", "CONCACAF", "CAF", "AFC", "OFC", "TBD"];

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

export function createTeamList({ container, data, onTeam }) {
  // Confederations actually present, in display order.
  function confeds() {
    const set = new Set(data.teams.map((t) => t.confed));
    return [
      ...CONFED_ORDER.filter((c) => set.has(c)),
      ...[...set].filter((c) => !CONFED_ORDER.includes(c)),
    ];
  }

  // Selected confederations — all by default.
  let selected = new Set(confeds());

  function teamCard(t) {
    return `<button class="tl-card team-link" data-team="${esc(t.code)}">
      <span class="tl-flag">${t.flag}</span>
      <span class="tl-info">
        <span class="tl-name">${esc(t.name)}</span>
        <span class="tl-grp">${esc(t.group)}組 · ${esc(t.confed)}${t.host ? " · 🏠開催国" : ""}</span>
      </span>
      <span class="tl-rank">${t.rank ? `FIFA ${t.rank}位` : "—"}</span>
    </button>`;
  }

  function chipBar() {
    const all = confeds();
    const allActive = all.every((c) => selected.has(c));
    const chip = (key, label, active) =>
      `<button class="chip ${active ? "active" : ""}" data-c="${key}">${label}</button>`;
    return [
      chip("ALL", "ALL", allActive),
      ...all.map((c) => chip(c, c, selected.has(c))),
    ].join("");
  }

  function render() {
    const teams = data.teams
      .filter((t) => selected.has(t.confed))
      .sort((a, b) => (a.rank || 999) - (b.rank || 999));

    const list = teams.length
      ? `<div class="tl-grid">${teams.map((t) => teamCard(t)).join("")}</div>`
      : `<p class="sub">表示する連盟（カンファレンス）が選択されていません。</p>`;

    container.innerHTML = `
      <h2 class="section-title">👥 出場チーム一覧 <span class="sub">${teams.length} / ${data.teams.length}チーム</span></h2>
      <div class="banner">FIFAランキング順に表示。連盟（カンファレンス）で絞り込めます（複数選択可・ALLで全選択）。チームをクリックすると登録メンバー・本大会得点のページへ。<br>※ 順位は FIFA 公式ランキング（最新）。出典・取得時刻はページ下部に表示。</div>
      <div class="toolbar">${chipBar()}</div>
      ${list}
    `;

    container.querySelectorAll(".chip").forEach((el) =>
      el.addEventListener("click", () => {
        const c = el.dataset.c;
        const all = confeds();
        if (c === "ALL") {
          selected = all.every((x) => selected.has(x)) ? new Set() : new Set(all);
        } else if (selected.has(c)) {
          selected.delete(c);
        } else {
          selected.add(c);
        }
        render();
      })
    );

    container.querySelectorAll(".team-link").forEach((el) =>
      el.addEventListener("click", () => onTeam?.(el.dataset.team))
    );
  }

  return { render };
}
