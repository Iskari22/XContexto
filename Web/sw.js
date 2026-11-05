// Service worker: guarda la app para abrirla sin conexión. NUNCA guarda llamadas a la API ni a Wikipedia.
const VERSION = "xcx-v1";
const SHELL = ["./", "index.html", "oembed.html", "css/app.css", "js/app.js", "js/core.js", "js/net.js", "js/prompts.js",
  "manifest.webmanifest", "icons/icon.svg", "icons/apple-touch-icon.png", "icons/icon-192.png", "icons/icon-512.png"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k))))
    .then(() => self.clients.claim()));
});

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== self.location.origin) return; // API, Wikipedia, X: directo a la red
  // Red primero (para recibir actualizaciones), caché si no hay conexión.
  e.respondWith(
    fetch(e.request).then((r) => {
      if (r.ok && !url.search) { const copy = r.clone(); caches.open(VERSION).then((c) => c.put(e.request, copy)); }
      return r;
    }).catch(() => caches.match(e.request, { ignoreSearch: true }).then((r) => r || caches.match("index.html")))
  );
});
