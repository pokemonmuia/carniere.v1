const CACHE="carniere-v2";
const SHELL=["./","index.html","manifest.webmanifest","icon-192.png","icon-512.png",
 "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js",
 "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",e=>{const u=new URL(e.request.url);
 // dati meteo/mare sempre dalla rete
 if(/open-meteo|emodnet|nominatim/.test(u.hostname)&&!/\/wms/.test(u.pathname))return;
 e.respondWith(caches.match(e.request).then(hit=>{const net=fetch(e.request).then(r=>{if(r.ok&&(u.origin===location.origin||/cdnjs|fonts\.g|tile\.openstreetmap|openseamap/.test(u.hostname))){const cl=r.clone();caches.open(CACHE).then(c=>c.put(e.request,cl))}return r}).catch(()=>hit);return hit||net}))});
