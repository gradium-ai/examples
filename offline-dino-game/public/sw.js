// The offline dino game's service worker, registered only in a build.
// - On install it saves every page file listed in precache.json, so after a single visit the page
//   reopens with no network at all.
// - Page files are served network first, falling back to that copy.
// - Every page file it serves gets the cross-origin isolation headers. Phonon needs them for its
//   threads, and this way any static host works, even one that cannot set headers (the page
//   reloads itself once to pick them up).
// Phonon's weights are not stored here: phonon-tts keeps its own cache.
// Every path is relative to this worker's scope, the page's folder, so the game can live under a
// sub-path such as gradium.ai/demos/phonon-in-browser/.
const CACHE = 'offline-fm-v2';
const SCOPE = self.registration.scope;
const ISOLATION = {
  'Cross-Origin-Opener-Policy': 'same-origin',
  'Cross-Origin-Embedder-Policy': 'require-corp',
  'Cross-Origin-Resource-Policy': 'same-origin',
};

self.addEventListener('install', (e) => {
  e.waitUntil((async () => {
    const cache = await caches.open(CACHE);
    try {
      const { urls } = await (await fetch(new URL('precache.json', SCOPE), { cache: 'no-store' })).json();
      await cache.addAll(urls.map((u) => new Request(new URL(u, SCOPE), { cache: 'reload' })));
    } catch (err) {
      console.warn('[sw] could not save the page files', err);
    }
    await self.skipWaiting();
  })());
});

self.addEventListener('activate', (e) => {
  e.waitUntil((async () => {
    for (const key of await caches.keys()) {
      if (key.startsWith('offline-fm-') && key !== CACHE) await caches.delete(key);
    }
    await self.clients.claim();
  })());
});

self.addEventListener('fetch', (e) => {
  const req = e.request;
  if (req.method !== 'GET' || new URL(req.url).origin !== location.origin) return;

  e.respondWith((async () => {
    const cache = await caches.open(CACHE);
    try {
      const res = await fetch(req);
      if (res.ok && res.type === 'basic') cache.put(req, res.clone()).catch(() => {});   // e.g. storage full
      return isolate(res);
    } catch (err) {
      const navigate = req.mode === 'navigate';
      const hit = await cache.match(req, { ignoreSearch: navigate }) || (navigate && await cache.match(SCOPE));
      if (hit) return isolate(hit);
      throw err;
    }
  })());
});

function isolate(res) {
  if (res.type === 'opaque' || res.type === 'opaqueredirect' || res.status === 0) return res;
  const headers = new Headers(res.headers);
  for (const [k, v] of Object.entries(ISOLATION)) headers.set(k, v);
  return new Response(res.body, { status: res.status, statusText: res.statusText, headers });
}
