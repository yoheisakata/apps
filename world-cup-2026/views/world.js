// World map of participating nations: a static Leaflet world map with a flag
// marker at each country's capital. The map is fixed (no panning/zooming);
// clicking a flag opens a centered modal that lazily loads the country's photo
// + summary from Wikipedia, plus its group / confederation / FIFA ranking.

import { fetchWiki } from "./wiki.js?v=27";

const CONFED_NAME = {
  UEFA: "欧州 (UEFA)",
  CONMEBOL: "南米 (CONMEBOL)",
  CONCACAF: "北中米カリブ (CONCACAF)",
  CAF: "アフリカ (CAF)",
  AFC: "アジア (AFC)",
  OFC: "オセアニア (OFC)",
  TBD: "未定 (大陸間プレーオフ)",
};

const CONFED_SHORT = {
  all: "All",
  UEFA: "UEFA",
  CONMEBOL: "CONMEBOL",
  CONCACAF: "CONCACAF",
  CAF: "CAF",
  AFC: "AFC",
  OFC: "OFC",
};

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

export function createWorld({ container, data, onTeam }) {
  let map = null;
  const markers = {};
  let openCode = null;
  let filter = "all";

  // Only teams with real coordinates (skip the play-off placeholder at 0,0).
  const located = data.teams.filter((t) => t.lat || t.lon);

  // Collect unique confederations in display order
  const confedOrder = ["UEFA", "CONMEBOL", "CONCACAF", "CAF", "AFC", "OFC"];
  const confeds = confedOrder.filter((c) => located.some((t) => t.confed === c));

  function flagIcon(team) {
    return L.divIcon({
      className: "flag-marker",
      html: `<span class="flag-pin">${team.flag}</span>`,
      iconSize: [26, 20],
      iconAnchor: [13, 10],
    });
  }

  function imgEl(src, alt, loading) {
    return src
      ? `<img class="cm-img" src="${esc(src)}" alt="${esc(alt)}" />`
      : `<div class="cm-img placeholder">${loading ? "🖼️ 読み込み中…" : "📷 写真なし"}</div>`;
  }

  function detailCard(t, wikiData, loading) {
    const confed = CONFED_NAME[t.confed] || t.confed;
    const text = wikiData?.extract || "";
    const link = wikiData?.pageUrl
      ? `<a class="popup-link" href="${esc(wikiData.pageUrl)}" target="_blank" rel="noopener">Wikipediaで読む →</a>`
      : "";
    const facts = [
      ["FIFAランキング", t.rank ? `${t.rank}位 ※` : null],
      ["所属連盟", confed],
      ["グループ", t.group + "組"],
      t.host ? ["開催国", "🏠 はい"] : null,
    ]
      .filter(Boolean)
      .filter(([, v]) => v != null && v !== "")
      .map(([k, v]) => `<div class="popup-meta-row"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`)
      .join("");

    return `<div class="cm-card">
      <div class="cm-header">
        <span class="cm-flag">${t.flag}</span>
        <div>
          <div class="cm-title">${esc(t.name)}</div>
          <div class="cm-sub">${esc(confed)}</div>
        </div>
      </div>
      <figure class="cm-photo cm-photo-single">${imgEl(wikiData?.thumb, t.name, loading)}</figure>
      <div class="popup-meta">${facts}</div>
      ${text ? `<p class="popup-text">${esc(text)}</p>` : ""}
      <button class="btn cm-team-btn" data-team="${esc(t.code)}">👥 チームページへ</button>
      <div class="cm-links">${link}</div>
    </div>`;
  }

  function closeModal() {
    openCode = null;
    container.querySelector("#country-modal")?.classList.add("hidden");
  }

  function showModal(html) {
    const ov = container.querySelector("#country-modal");
    if (!ov) return;
    ov.querySelector(".city-modal-body").innerHTML = html;
    ov.classList.remove("hidden");
    ov.querySelector(".cm-team-btn")?.addEventListener("click", (e) => {
      closeModal();
      onTeam?.(e.currentTarget.dataset.team);
    });
  }

  async function openTeam(t) {
    openCode = t.code;
    showModal(detailCard(t, null, true));
    const wiki = await fetchWiki(t.wiki, "ja");
    if (openCode === t.code) showModal(detailCard(t, wiki, false));
  }

  function filteredTeams() {
    if (filter === "all") return located;
    return located.filter((t) => t.confed === filter);
  }

  function confedCount(c) {
    return located.filter((t) => t.confed === c).length;
  }

  function applyFilter() {
    const visible = filteredTeams();
    const visibleCodes = new Set(visible.map((t) => t.code));
    for (const [code, marker] of Object.entries(markers)) {
      if (visibleCodes.has(code)) {
        if (!map.hasLayer(marker)) marker.addTo(map);
      } else {
        if (map.hasLayer(marker)) map.removeLayer(marker);
      }
    }
    // Update chip active state
    container.querySelectorAll(".chip[data-confed]").forEach((el) => {
      el.classList.toggle("active", el.dataset.confed === filter);
    });
    // Update count
    const countEl = container.querySelector("#world-count");
    if (countEl) countEl.textContent = `${visible.length}か国`;
  }

  function buildMap() {
    const mapEl = container.querySelector("#world-map");
    map = L.map(mapEl, {
      attributionControl: true,
      zoomControl: false,
      dragging: false,
      scrollWheelZoom: false,
      doubleClickZoom: false,
      boxZoom: false,
      keyboard: false,
      touchZoom: false,
      tap: false,
      worldCopyJump: false,
    });
    L.tileLayer(
      "https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png",
      {
        maxZoom: 18,
        subdomains: "abcd",
        attribution: "© OpenStreetMap contributors © CARTO",
      }
    ).addTo(map);

    for (const t of located) {
      const marker = L.marker([t.lat, t.lon], { icon: flagIcon(t) })
        .addTo(map)
        .bindTooltip(`${t.flag} ${t.name}`, { direction: "top" });
      marker.on("click", () => openTeam(t));
      markers[t.code] = marker;
    }
    frameWorld();
  }

  function frameWorld() {
    const markerBounds = L.latLngBounds(located.map((t) => [t.lat, t.lon]));
    map.setMinZoom(0);
    map.setMaxBounds(null);
    map.fitBounds(markerBounds, { animate: false, padding: [15, 25] });
    map.setMinZoom(map.getZoom());
    map.setMaxBounds(map.getBounds().pad(0.05));
  }

  function bindChips() {
    container.querySelectorAll(".chip[data-confed]").forEach((el) => {
      el.addEventListener("click", () => {
        filter = el.dataset.confed;
        applyFilter();
      });
    });
  }

  function render() {
    if (!map) {
      const playoff = data.teams.length - located.length;
      const chips = [
        `<button class="chip active" data-confed="all">All (${located.length})</button>`,
        ...confeds.map(
          (c) => `<button class="chip" data-confed="${c}">${CONFED_SHORT[c]} (${confedCount(c)})</button>`
        ),
      ].join("");

      container.innerHTML = `
        <h2 class="section-title">🌍 参加国 <span class="sub" id="world-count">${located.length}か国${playoff ? ` + プレーオフ${playoff}枠` : ""}</span></h2>
        <div class="toolbar">${chips}</div>
        <div class="banner">国旗マーカーをクリックすると、写真・FIFAランキング・所属連盟・グループ・特徴が表示されます（写真と解説は Wikipedia から取得）。マーカーは首都の位置に配置。組分けは実際の抽選結果（2026-06-18 時点）。<br>※ FIFAランキングは概数（2025年後半時点の目安）。</div>
        <div class="map-shell">
          <div id="world-map" class="leaflet-host"></div>
          <div id="country-modal" class="city-modal hidden">
            <div class="city-modal-backdrop"></div>
            <div class="city-modal-card">
              <button class="city-modal-close" aria-label="閉じる">✕</button>
              <div class="city-modal-body"></div>
            </div>
          </div>
        </div>`;
      buildMap();
      bindChips();
      container.querySelector(".city-modal-backdrop").addEventListener("click", closeModal);
      container.querySelector(".city-modal-close").addEventListener("click", closeModal);
    } else {
      setTimeout(() => {
        map.invalidateSize();
        applyFilter();
      }, 0);
    }
  }

  return { render };
}
