/* Will It Fit service worker: network-first with cache fallback, so the installed
   app keeps working offline with the last version it saw (boards live in
   localStorage and survive regardless). */
const CACHE = 'wf-v1';

self.addEventListener('install', () => self.skipWaiting());

self.addEventListener('activate', e => {
  e.waitUntil(
    caches.keys()
      .then(ks => Promise.all(ks.filter(k => k !== CACHE).map(k => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (url.origin !== location.origin) return; /* fonts, CDNs, proxies: leave alone */
  e.respondWith(
    fetch(req).then(r => {
      if (r.ok) { const cp = r.clone(); caches.open(CACHE).then(c => c.put(req, cp)); }
      return r;
    }).catch(() =>
      caches.match(req).then(m => m || (req.mode === 'navigate' ? caches.match('./') : Promise.reject(new Error('offline'))))
    )
  );
});
