// シンプルなオフラインキャッシュ
var CACHE_NAME = "manabi-v10";
importScripts("audio-manifest.js"); // AUDIO_FILES (tools/generate_audio.py が生成)
var ASSETS = [
  ".",
  "index.html",
  "style.css",
  "app.js",
  "hiragana-strokes.js",
  "audio-manifest.js",
  "manifest.json",
  "icon.svg"
].concat(AUDIO_FILES);

self.addEventListener("install", function (e) {
  e.waitUntil(
    caches.open(CACHE_NAME).then(function (cache) {
      return cache.addAll(ASSETS);
    })
  );
  self.skipWaiting();
});

self.addEventListener("activate", function (e) {
  e.waitUntil(
    caches.keys().then(function (keys) {
      return Promise.all(
        keys.filter(function (k) { return k !== CACHE_NAME; })
            .map(function (k) { return caches.delete(k); })
      );
    })
  );
  self.clients.claim();
});

self.addEventListener("fetch", function (e) {
  e.respondWith(
    caches.match(e.request).then(function (cached) {
      return cached || fetch(e.request);
    })
  );
});
