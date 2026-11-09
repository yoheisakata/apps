// ==UserScript==
// @name         Brightwheel Utilities
// @namespace    yosakata-tools
// @version      2.0.0
// @description  Brightwheel: フィードのjpg一括抽出/DL + メッセージ画面の幅拡大と添付一括DL
// @match        https://schools.mybrightwheel.com/*
// @grant        GM_setClipboard
// @grant        GM_download
// @grant        GM_getValue
// @grant        GM_setValue
// @grant        GM_addStyle
// @run-at       document-idle
// ==/UserScript==

(function () {
  'use strict';

  const isFeed = () => /^\/students\/[^/]+\/feed/.test(location.pathname);
  const isMessages = () => location.pathname.startsWith('/messages');

  // ======================================================================
  // メッセージ画面: 幅拡大 CSS(常時注入。該当要素がある時だけ効く)
  // ======================================================================
  GM_addStyle(`
    [data-testid="thread-container"] {
      max-width: none !important;
      width: 100% !important;
      flex: 1 1 auto !important;
    }
    [data-testid="thread-content-message-list"] {
      max-width: none !important;
      width: 100% !important;
    }
    [data-testid="messages-table"] {
      max-width: 360px !important;
    }
    #bw-dl-all {
      position: fixed; right: 24px; bottom: 24px; z-index: 99999;
      padding: 10px 16px; border: none; border-radius: 24px;
      background: #5463D6; color: #fff; font-size: 14px; font-weight: bold;
      cursor: pointer; box-shadow: 0 2px 8px rgba(0,0,0,.3);
      display: none;
    }
    #bw-dl-all:hover { background: #3f4cb0; }
  `);

  // ======================================================================
  // メッセージ画面: 添付一括DL
  // ======================================================================
  let msgBusy = false;

  function attachmentName(url) {
    try {
      const path = decodeURIComponent(new URL(url).pathname);
      const seg = path.split('/').pop();
      return (seg.substring(seg.indexOf('_') + 1) || 'attachment').replace(/\+/g, ' ');
    } catch { return 'attachment'; }
  }

  function attachmentLinks() {
    const container = document.querySelector('[data-testid="thread-container"]');
    if (!container) return [];
    const links = container.querySelectorAll('a[href*="cdn.mybrightwheel.com/attachments"]');
    return [...new Set([...links].map((a) => a.href))];
  }

  function downloadAttachments() {
    if (msgBusy) return;
    const btn = msgBtn;
    const urls = attachmentLinks();
    if (!urls.length) {
      btn.textContent = '添付なし';
      setTimeout(() => (btn.textContent = '📥 添付を一括DL'), 2000);
      return;
    }
    msgBusy = true;
    let done = 0;
    btn.textContent = `⬇️ 0/${urls.length}`;
    const finish = () => {
      done++;
      btn.textContent = `⬇️ ${done}/${urls.length}`;
      if (done === urls.length) {
        msgBusy = false;
        btn.textContent = `✅ 完了 (${urls.length})`;
        setTimeout(() => (btn.textContent = '📥 添付を一括DL'), 3000);
      }
    };
    urls.forEach((url, i) => {
      setTimeout(() => {
        GM_download({
          url,
          name: attachmentName(url),
          onload: finish,
          onerror: (e) => { console.warn('DL失敗:', url, e); finish(); },
          ontimeout: finish,
        });
      }, i * 500);
    });
  }

  const msgBtn = document.createElement('button');
  msgBtn.id = 'bw-dl-all';
  msgBtn.textContent = '📥 添付を一括DL';
  msgBtn.addEventListener('click', downloadAttachments);

  // ======================================================================
  // フィード画面: JPG Link Extractor(ロジックは従来どおり)
  // ======================================================================
  const JPG_RE = /\.jpe?g(\?|#|$)/i;
  const THUMB_PATH_RE = /(thumb|small|_\d{2,4}x\d{2,4})/i;
  const THUMB_QUERY_RE = /[?&](w|h|width|height|size|resize)=/i;
  const DATE_RE = /(\d{2})\/(\d{2})\/(\d{4})/; // MM/DD/YYYY
  const found = new Map(); // url -> { date }
  let autoScrolling = false;

  const HIST_KEY = 'downloadedPaths';
  const LAST_DATE_KEY = 'lastDownloadedDate';
  const history = new Set(GM_getValue(HIST_KEY, []));
  function urlKey(u) {
    try { return new URL(u).pathname; } catch { return u.split('?')[0]; }
  }
  const isDownloaded = (u) => history.has(urlKey(u));

  function isThumb(u) {
    try {
      const url = new URL(u);
      return THUMB_PATH_RE.test(url.pathname) || THUMB_QUERY_RE.test(url.search);
    } catch { return THUMB_PATH_RE.test(u); }
  }

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
      if (l.el.compareDocumentPosition(el) & Node.DOCUMENT_POSITION_FOLLOWING) date = l.date;
      else break;
    }
    return date;
  }

  function collect() {
    if (!isFeed()) return 0; // メッセージ画面のアバター等を拾わない
    const items = [];
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
        prev.date = dateFor(el, labels);
      }
    });
    if (added) updateCount();
    return added;
  }

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
        idleRounds++;
      }
      await new Promise((r) => setTimeout(r, 1500));
      collect();
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

  function targets() {
    let all = [...found.keys()];
    if (chkNewOnly.checked) all = all.filter((u) => !isDownloaded(u));
    const urls = chkThumbs.checked ? all : (all.filter((u) => !isThumb(u)).length ? all.filter((u) => !isThumb(u)) : all);
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

  // --- フィード用 UI -------------------------------------------------------
  const panel = document.createElement('div');
  panel.style.cssText =
    'position:fixed;bottom:16px;right:16px;z-index:99999;background:#1e293b;color:#fff;' +
    'padding:10px 12px;border-radius:10px;font:12px/1.6 -apple-system,sans-serif;' +
    'box-shadow:0 4px 16px rgba(0,0,0,.35);display:none;flex-direction:column;gap:6px;min-width:170px';

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

  function updateCount() {
    const urls = [...found.keys()];
    const done = urls.filter(isDownloaded).length;
    const dated = targets().filter((u) => found.get(u).date).length;
    countEl.textContent = `対象: ${targets().length} 件(日付あり ${dated} / DL済 ${done})`;
    const last = GM_getValue(LAST_DATE_KEY, '');
    if (last) {
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

  // ======================================================================
  // 共通: SPA のページ遷移に合わせて UI を出し分け(300ms デバウンス)
  // ======================================================================
  document.body.append(panel, msgBtn);

  function syncUI() {
    panel.style.display = isFeed() ? 'flex' : 'none';
    msgBtn.style.display =
      isMessages() && document.querySelector('[data-testid="thread-container"]') ? 'block' : 'none';
  }

  let syncTimer = null;
  new MutationObserver(() => {
    if (!syncTimer) {
      syncTimer = setTimeout(() => {
        syncTimer = null;
        collect(); // フィード画面のときだけ中で動く
        syncUI();
      }, 300);
    }
  }).observe(document.body, { childList: true, subtree: true });

  collect();
  syncUI();
  updateCount();
})();
