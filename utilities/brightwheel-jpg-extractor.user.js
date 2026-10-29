// ==UserScript==
// @name         Brightwheel JPG Link Extractor
// @namespace    yosakata-tools
// @version      1.6.0
// @description  Brightwheel のフィードページから jpg 画像リンクを一括抽出(自動スクロール・コピー・txt保存)
// @match        https://schools.mybrightwheel.com/students/*/feed*
// @grant        GM_setClipboard
// @grant        GM_download
// @grant        GM_getValue
// @grant        GM_setValue
// @run-at       document-idle
// ==/UserScript==

(function () {
  'use strict';

  const JPG_RE = /\.jpe?g(\?|#|$)/i;
  // サムネイル判定: パスに thumb/small/「幅x高さ」が入る、またはリサイズ系クエリ付き
  const THUMB_PATH_RE = /(thumb|small|_\d{2,4}x\d{2,4})/i;
  const THUMB_QUERY_RE = /[?&](w|h|width|height|size|resize)=/i;
  const DATE_RE = /(\d{2})\/(\d{2})\/(\d{4})/; // MM/DD/YYYY
  const found = new Map(); // url -> { date: 'YYYY-MM-DD' | '' }
  let autoScrolling = false;

  // --- DL 済み履歴(署名クエリは変わるのでパス名で照合) --------------------
  const HIST_KEY = 'downloadedPaths';
  const LAST_DATE_KEY = 'lastDownloadedDate';
  const history = new Set(GM_getValue(HIST_KEY, []));
  function urlKey(u) {
    try {
      return new URL(u).pathname;
    } catch {
      return u.split('?')[0];
    }
  }
  const isDownloaded = (u) => history.has(urlKey(u));

  function isThumb(u) {
    try {
      const url = new URL(u);
      return THUMB_PATH_RE.test(url.pathname) || THUMB_QUERY_RE.test(url.search);
    } catch {
      return THUMB_PATH_RE.test(u);
    }
  }

  // --- 日付の紐付け -------------------------------------------------------
  // 各画像の「直前にある日付ラベル (MM/DD/YYYY)」をその写真の日付とみなす
  function buildDateIndex() {
    const labels = [];
    document.querySelectorAll('[class*="dayLabel"]').forEach((el) => {
      const m = el.textContent.match(DATE_RE);
      if (m) labels.push({ el, date: `${m[3]}-${m[1]}-${m[2]}` });
    });
    return labels;
  }

  function dateFor(el, labels) {
    let date = '';
    for (const l of labels) {
      // ラベルが el より文書順で前にあれば候補。最後に前にあったものが「直前」
      if (l.el.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) date = l.date;
      else break;
    }
    return date;
  }

  // --- 収集 -------------------------------------------------------------
  function collect() {
    const items = []; // { url, el }
    document.querySelectorAll('img[src], img[srcset], a[href], [style*="background-image"]').forEach((el) => {
      if (el.tagName === 'IMG') {
        if (el.src) items.push({ url: el.src, el });
        if (el.srcset) {
          el.srcset.split(',').forEach((part) => {
            const u = part.trim().split(/\s+/)[0];
            if (u) items.push({ url: u, el });
          });
        }
      } else if (el.tagName === 'A') {
        items.push({ url: el.href, el });
      } else {
        const m = el.style.backgroundImage.match(/url\(["']?(.+?)["']?\)/);
        if (m) items.push({ url: m[1], el });
      }
    });
    const labels = buildDateIndex();
    let added = 0;
    items.forEach(({ url, el }) => {
      if (!JPG_RE.test(url)) return;
      const prev = found.get(url);
      if (!prev) {
        found.set(url, { date: dateFor(el, labels) });
        added++;
      } else if (!prev.date) {
        prev.date = dateFor(el, labels); // 後から日付が取れたら補完
      }
    });
    if (added) updateCount();
    return added;
  }

  // --- Load more を自動クリックしてフィードを最後まで読み込む --------------
  async function autoLoad() {
    if (autoScrolling) { autoScrolling = false; return; }
    autoScrolling = true;
    btnScroll.textContent = '停止';
    let idleRounds = 0;
    while (autoScrolling && idleRounds < 5) {
      window.scrollTo(0, document.body.scrollHeight);
      const loadBtn = document.querySelector('button[data-testid="load-button"]');
      if (loadBtn && !loadBtn.disabled) {
        loadBtn.click();
        idleRounds = 0;
      } else {
        idleRounds++; // ボタンが消えた/無効 = 読み込み完了か通信待ち
      }
      await new Promise((r) => setTimeout(r, 1500));
      collect();
      // 新規のみモード: DL 済み最終日より古い日付が見えたら、それ以上遡らない
      const lastDate = GM_getValue(LAST_DATE_KEY, '');
      if (chkNewOnly.checked && lastDate && buildDateIndex().some((l) => l.date < lastDate)) {
        flash(`${lastDate} 以前に到達、読み込み停止`);
        break;
      }
    }
    autoScrolling = false;
    btnScroll.textContent = '全件読み込み';
    updateCount();
    flash('読み込み完了');
  }

  // --- 出力 -------------------------------------------------------------
  function targets() {
    let all = [...found.keys()];
    if (chkNewOnly.checked) all = all.filter((u) => !isDownloaded(u));
    const urls = chkThumbs.checked ? all : (all.filter((u) => !isThumb(u)).length ? all.filter((u) => !isThumb(u)) : all);
    // 日付順 → 同日内は収集順
    return urls.sort((a, b) => (found.get(a).date || '9999').localeCompare(found.get(b).date || '9999'));
  }
  const list = () => targets().map((u) => `${found.get(u).date || 'unknown'}\t${u}`).join('\n');

  function copyAll() {
    const n = targets().length;
    if (!n) return;
    if (typeof GM_setClipboard === 'function') GM_setClipboard(list());
    else navigator.clipboard.writeText(list());
    flash(`${n} 件コピーしました`);
  }

  function saveTxt() {
    if (!targets().length) return;
    const blob = new Blob([list()], { type: 'text/plain' });
    const a = document.createElement('a');
    a.href = URL.createObjectURL(blob);
    a.download = `brightwheel-jpg-links-${new Date().toISOString().slice(0, 10)}.txt`;
    a.click();
    URL.revokeObjectURL(a.href);
  }

  function downloadAll() {
    const t = targets();
    if (!t.length || typeof GM_download !== 'function') return;
    // 2026-04-04 → 2026_0404。同日複数枚は 2026_0404_02.jpg … と連番
    const fname = (date) => (date ? `${date.slice(0, 4)}_${date.slice(5, 7)}${date.slice(8, 10)}` : 'unknown');
    const total = {};
    t.forEach((u) => {
      const k = fname(found.get(u).date);
      total[k] = (total[k] || 0) + 1;
    });
    const seen = {};
    let lastDate = GM_getValue(LAST_DATE_KEY, '');
    t.forEach((u) => {
      const k = fname(found.get(u).date);
      seen[k] = (seen[k] || 0) + 1;
      const suffix = total[k] > 1 ? `_${String(seen[k]).padStart(2, '0')}` : '';
      GM_download({ url: u, name: `brightwheel/${k}${suffix}.jpg` });
      history.add(urlKey(u));
      const d = found.get(u).date;
      if (d && d > lastDate) lastDate = d;
    });
    GM_setValue(HIST_KEY, [...history]);
    GM_setValue(LAST_DATE_KEY, lastDate);
    updateCount();
    flash(`${t.length} 件のダウンロードを開始`);
  }

  // --- UI ---------------------------------------------------------------
  const panel = document.createElement('div');
  panel.style.cssText =
    'position:fixed;bottom:16px;right:16px;z-index:99999;background:#1e293b;color:#fff;' +
    'padding:10px 12px;border-radius:10px;font:12px/1.6 -apple-system,sans-serif;' +
    'box-shadow:0 4px 16px rgba(0,0,0,.35);display:flex;flex-direction:column;gap:6px;min-width:170px';

  const countEl = document.createElement('div');
  countEl.style.cssText = 'font-weight:600';
  const lastEl = document.createElement('div');
  lastEl.style.cssText = 'color:#fbbf24';
  const msgEl = document.createElement('div');
  msgEl.style.cssText = 'color:#86efac;min-height:1em';

  function mkBtn(label, fn) {
    const b = document.createElement('button');
    b.textContent = label;
    b.style.cssText =
      'background:#3b82f6;color:#fff;border:0;border-radius:6px;padding:5px 8px;cursor:pointer;font:inherit';
    b.onclick = fn;
    return b;
  }

  const btnScroll = mkBtn('全件読み込み', autoLoad);

  function mkCheck(label, checked) {
    const wrap = document.createElement('label');
    wrap.style.cssText = 'display:flex;align-items:center;gap:4px;cursor:pointer';
    const chk = document.createElement('input');
    chk.type = 'checkbox';
    chk.checked = checked;
    chk.onchange = updateCount;
    wrap.append(chk, document.createTextNode(label));
    return [wrap, chk];
  }
  const [chkLabel, chkThumbs] = mkCheck('サムネイルも含める', false);
  const [chkNewLabel, chkNewOnly] = mkCheck('DL済みを除外', true);

  // 再DLせずに、現在の対象を「DL済み」として履歴登録(初回移行用)
  function markAsDownloaded() {
    const t = targets();
    if (!t.length) return;
    let lastDate = GM_getValue(LAST_DATE_KEY, '');
    t.forEach((u) => {
      history.add(urlKey(u));
      const d = found.get(u).date;
      if (d && d > lastDate) lastDate = d;
    });
    GM_setValue(HIST_KEY, [...history]);
    GM_setValue(LAST_DATE_KEY, lastDate);
    updateCount();
    flash(`${t.length} 件を DL 済みに登録`);
  }

  function resetHistory() {
    if (!confirm('DL 済み履歴をリセットしますか?')) return;
    history.clear();
    GM_setValue(HIST_KEY, []);
    GM_setValue(LAST_DATE_KEY, '');
    updateCount();
    flash('履歴をリセットしました');
  }

  panel.append(
    countEl,
    lastEl,
    btnScroll,
    chkLabel,
    chkNewLabel,
    mkBtn('リンクをコピー', copyAll),
    mkBtn('txt で保存', saveTxt),
    mkBtn('画像を一括DL', downloadAll),
    mkBtn('DL済みに登録', markAsDownloaded),
    mkBtn('履歴リセット', resetHistory),
    msgEl
  );
  document.body.appendChild(panel);

  function updateCount() {
    const urls = [...found.keys()];
    const done = urls.filter(isDownloaded).length;
    const dated = targets().filter((u) => found.get(u).date).length;
    countEl.textContent = `対象: ${targets().length} 件(日付あり ${dated} / DL済 ${done})`;
    const last = GM_getValue(LAST_DATE_KEY, '');
    if (last) {
      // 翌日を MM/DD/YYYY で表示(Range ピッカーの開始日に入れる値)
      const next = new Date(last + 'T00:00:00');
      next.setDate(next.getDate() + 1);
      const mm = String(next.getMonth() + 1).padStart(2, '0');
      const dd = String(next.getDate()).padStart(2, '0');
      lastEl.textContent = `DL済: 〜${last}(次回開始日: ${mm}/${dd}/${next.getFullYear()})`;
    } else {
      lastEl.textContent = '';
    }
  }
  let msgTimer;
  function flash(text) {
    msgEl.textContent = text;
    clearTimeout(msgTimer);
    msgTimer = setTimeout(() => (msgEl.textContent = ''), 3000);
  }

  // --- 動的読み込み対応 ---------------------------------------------------
  new MutationObserver(() => collect()).observe(document.body, { childList: true, subtree: true });
  collect();
  updateCount();
})();
