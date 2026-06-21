// Host-city map: a real Leaflet/OSM map with a marker per venue.
// Clicking a marker opens a popup that lazily loads the city's photo + summary
// from Wikipedia, alongside static facts (country, stadium, capacity, population).

import { fetchWiki, formatPop } from "./wiki.js?v=3";

const COUNTRY_NAME = { USA: "アメリカ", CAN: "カナダ", MEX: "メキシコ" };
const COUNTRY_COLOR = { USA: "#4a90e2", CAN: "#e25555", MEX: "#3cba54" };

function esc(s) {
  return String(s).replace(/[&<>"]/g, (c) =>
    ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])
  );
}

export function createCities({ container, data }) {
  let map = null;
  const markers = {};

  function dotIcon(color, city) {
    // Dot + an always-visible city-name label to its right. The icon anchors on
    // the dot center; the label flows right and doesn't affect positioning.
    return L.divIcon({
      className: "venue-marker",
      html: `<span class="venue-pin" style="background:${color};color:${color}"></span><span class="venue-label">${esc(city)}</span>`,
      iconSize: [0, 0],
      iconAnchor: [7, 7],
    });
  }

  // Image element or a placeholder while loading / when unavailable.
  function imgEl(src, alt, loading) {
    return src
      ? `<img class="cm-img" src="${esc(src)}" alt="${esc(alt)}" />`
      : `<div class="cm-img placeholder">${loading ? "🖼️ 読み込み中…" : "📷 写真なし"}</div>`;
  }

  // The full city detail card. `cityW`/`stadW` are the fetched wiki payloads
  // (null while loading or unavailable). `loading` shows placeholders.
  function detailCard(v, cityW, stadW, loading) {
    const countryName = COUNTRY_NAME[v.country] || v.country;
    const cityText = cityW?.extract || v.desc || "";
    const cityLink = cityW?.pageUrl
      ? `<a class="popup-link" href="${esc(cityW.pageUrl)}" target="_blank" rel="noopener">都市の記事 →</a>`
      : "";
    const stadLink = stadW?.pageUrl
      ? `<a class="popup-link" href="${esc(stadW.pageUrl)}" target="_blank" rel="noopener">スタジアムの記事 →</a>`
      : "";

    const facts = [
      ["国", `${v.flag || ""} ${countryName}`],
      ["スタジアム", v.stadium],
      ["収容人数", v.capacity.toLocaleString("ja-JP") + "人"],
      ["都市圏人口", formatPop(v.pop)],
    ]
      .filter(([, val]) => val != null && val !== "")
      .map(([k, val]) => `<div class="popup-meta-row"><span class="k">${esc(k)}</span><span class="v">${esc(val)}</span></div>`)
      .join("");

    return `<div class="cm-card">
      <div class="cm-header">
        <span class="cm-flag">${v.flag || ""}</span>
        <div>
          <div class="cm-title">${esc(v.city)}</div>
          <div class="cm-sub">${esc(countryName)} · ${esc(v.stadium)}</div>
        </div>
      </div>
      <div class="cm-photos">
        <figure class="cm-photo">
          ${imgEl(cityW?.thumb, v.city, loading)}
          <figcaption>🏙️ 都市</figcaption>
        </figure>
        <figure class="cm-photo">
          ${imgEl(stadW?.thumb, v.stadium, loading)}
          <figcaption>🏟️ スタジアム</figcaption>
        </figure>
      </div>
      <div class="popup-meta">${facts}</div>
      ${cityText ? `<p class="popup-text">${esc(cityText)}</p>` : ""}
      ${stadW?.extract ? `<p class="popup-text cm-stad-text"><b>${esc(v.stadium)}:</b> ${esc(stadW.extract)}</p>` : ""}
      <div class="cm-links">${cityLink}${stadLink}</div>
    </div>`;
  }

  // The detail card is shown in a fixed, centered overlay (not a Leaflet popup)
  // so opening it never moves the map. `openId` tracks which city is showing.
  let openId = null;

  function closeModal() {
    openId = null;
    const ov = container.querySelector("#city-modal");
    if (ov) ov.classList.add("hidden");
  }

  function showModal(html) {
    const ov = container.querySelector("#city-modal");
    if (!ov) return;
    ov.querySelector(".city-modal-body").innerHTML = html;
    ov.classList.remove("hidden");
  }

  async function openCity(v) {
    openId = v.id;
    showModal(detailCard(v, null, null, true));
    // City summary from Japanese wiki, stadium from English wiki (the stadium
    // articles generally don't exist in Japanese). Fetch in parallel.
    const [cityW, stadW] = await Promise.all([
      fetchWiki(v.wiki, "ja"),
      fetchWiki(v.stadium, "en"),
    ]);
    if (openId === v.id) showModal(detailCard(v, cityW, stadW, false));
  }

  function buildMap() {
    const mapEl = container.querySelector("#cities-map");
    // Fully static map: no panning, no zooming. The only interaction is
    // clicking a marker to open its popup. All drag/zoom handlers are off.
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
    });
    // CARTO "Voyager" tiles — a clean, light, colourful basemap (roads/labels
    // clearly visible) that's much easier to read than the dark variant.
    L.tileLayer(
      "https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}{r}.png",
      {
        maxZoom: 18,
        subdomains: "abcd",
        attribution: "© OpenStreetMap contributors © CARTO",
      }
    ).addTo(map);

    const latlngs = [];
    for (const v of data.venues) {
      const color = COUNTRY_COLOR[v.country] || "#00d4a0";
      // No Leaflet popup — clicking opens the centered modal instead, so the
      // map never pans. The city name is shown as an always-on label.
      const marker = L.marker([v.lat, v.lon], { icon: dotIcon(color, v.city) }).addTo(map);
      marker.on("click", () => openCity(v));
      markers[v.id] = marker;
      latlngs.push([v.lat, v.lon]);
    }
    map.fitBounds(latlngs, { padding: [40, 40] });
    map.setMinZoom(map.getZoom());
    map.setMaxBounds(map.getBounds());
  }

  function render() {
    if (!map) {
      container.innerHTML = `
        <h2 class="section-title">🏟️ 開催都市 <span class="sub">16都市</span></h2>
        <div class="banner">地図上のマーカーをクリックすると、その都市の写真・人口・特徴が表示されます（写真と解説は Wikipedia から取得）。<span class="legend-inline"><b style="color:#4a90e2">●</b> 🇺🇸 USA <b style="color:#e25555">●</b> 🇨🇦 Canada <b style="color:#3cba54">●</b> 🇲🇽 Mexico</span></div>
        <div class="map-shell">
          <div id="cities-map" class="leaflet-host"></div>
          <div id="city-modal" class="city-modal hidden">
            <div class="city-modal-backdrop"></div>
            <div class="city-modal-card">
              <button class="city-modal-close" aria-label="閉じる">✕</button>
              <div class="city-modal-body"></div>
            </div>
          </div>
        </div>`;
      buildMap();
      // Close handlers: backdrop click and the ✕ button.
      container.querySelector(".city-modal-backdrop").addEventListener("click", closeModal);
      container.querySelector(".city-modal-close").addEventListener("click", closeModal);
    } else {
      // Tab re-shown: recalc size, then re-frame the venues identically.
      setTimeout(() => {
        map.invalidateSize();
        const latlngs = data.venues.map((v) => [v.lat, v.lon]);
        map.setMinZoom(0);
        map.setMaxBounds(null);
        map.fitBounds(latlngs, { padding: [40, 40] });
        map.setMinZoom(map.getZoom());
        map.setMaxBounds(map.getBounds());
      }, 0);
    }
  }

  return { render };
}
