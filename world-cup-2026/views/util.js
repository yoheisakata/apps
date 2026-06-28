// Shared time/date helpers. The app renders every match time in the VIEWER's
// own timezone, derived from the absolute UTC `kickoff` instant. When a match
// has no kickoff we fall back to the source date / venue-local time string.

const WD = ["日", "月", "火", "水", "木", "金", "土"];
const two = (n) => String(n).padStart(2, "0");

// The kickoff as a local Date, or null.
export function kickoffDate(m) {
  if (m && m.kickoff) {
    const d = new Date(m.kickoff);
    if (!isNaN(d)) return d;
  }
  return null;
}

// "HH:MM" in the viewer's timezone (falls back to the time string's clock part).
export function localHM(m) {
  const d = kickoffDate(m);
  if (d) return `${two(d.getHours())}:${two(d.getMinutes())}`;
  return ((m && m.time) || "").match(/\d{1,2}:\d{2}/)?.[0] || "";
}

// "YYYY-MM-DD" in the viewer's timezone (used for grouping / comparisons).
export function localYMD(m) {
  const d = kickoffDate(m);
  if (d) return `${d.getFullYear()}-${two(d.getMonth() + 1)}-${two(d.getDate())}`;
  return (m && m.date) || "";
}

// "M/D(曜)" in the viewer's timezone.
export function localMDW(m) {
  const d = kickoffDate(m);
  if (d) return `${d.getMonth() + 1}/${d.getDate()}(${WD[d.getDay()]})`;
  const ymd = (m && m.date) || "";
  if (!ymd) return "";
  const dd = new Date(ymd + "T00:00:00");
  const md = ymd.slice(5).replace("-", "/").replace(/^0/, "");
  return isNaN(dd) ? md : `${md}(${WD[dd.getDay()]})`;
}
