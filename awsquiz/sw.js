// AWS SAP 対策 — オフラインキャッシュ
// キャッシュ対象を変えたら CACHE_NAME を必ず上げること（古いキャッシュが残り続けるため）
var CACHE_NAME = "awsquiz-v1";
var ASSETS = ["./", "./index.html", "./questions.js", "./manifest.json"];

self.addEventListener("install", function (e) {
  e.waitUntil(
    caches.open(CACHE_NAME).then(function (c) { return c.addAll(ASSETS); }).then(function () {
      return self.skipWaiting();
    })
  );
});

self.addEventListener("activate", function (e) {
  e.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(keys.map(function (k) {
        return k === CACHE_NAME ? null : caches.delete(k);
      }));
    }).then(function () { return self.clients.claim(); })
  );
});

// 同一オリジンのみ network-first（オフライン時だけキャッシュにフォールバック）。
// cache-first にすると問題を追加しても古い questions.js が返り続けるので、
// 「オンラインなら常に最新・オフラインでも動く」を優先している。
// Google Fonts などのクロスオリジンは素通し。
self.addEventListener("fetch", function (e) {
  if (e.request.method !== "GET") return;
  if (new URL(e.request.url).origin !== location.origin) return;
  e.respondWith(
    fetch(e.request).then(function (res) {
      var copy = res.clone();
      caches.open(CACHE_NAME).then(function (c) { c.put(e.request, copy); });
      return res;
    }).catch(function () {
      return caches.match(e.request).then(function (hit) {
        return hit || caches.match("./index.html");
      });
    })
  );
});
