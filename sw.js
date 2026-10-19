const CACHE="carniere-v4";
const SHELL=["./","index.html","manifest.webmanifest","icon-192.png","icon-512.png",
 "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.js",
 "https://cdnjs.cloudflare.com/ajax/libs/leaflet/1.9.4/leaflet.min.css",
 "https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.117.2/dist/umd/supabase.js"];
self.addEventListener("install",e=>{e.waitUntil(caches.open(CACHE).then(c=>c.addAll(SHELL)).then(()=>self.skipWaiting()))});
self.addEventListener("activate",e=>{e.waitUntil(caches.keys().then(ks=>Promise.all(ks.filter(k=>k!==CACHE).map(k=>caches.delete(k)))).then(()=>self.clients.claim()))});
self.addEventListener("fetch",e=>{const u=new URL(e.request.url);
 // dati meteo/mare sempre dalla rete
 if(/open-meteo|emodnet|nominatim|supabase\.co/.test(u.hostname)&&!/\/wms/.test(u.pathname))return;
 if(e.request.mode==="navigate"){e.respondWith(fetch(e.request).then(r=>{const cl=r.clone();caches.open(CACHE).then(c=>c.put("index.html",cl));return r}).catch(()=>caches.match("index.html")));return}
 e.respondWith(caches.match(e.request).then(hit=>{const net=fetch(e.request).then(r=>{if(r.ok&&(u.origin===location.origin||/cdnjs|jsdelivr|fonts\.g|tile\.openstreetmap|openseamap/.test(u.hostname))){const cl=r.clone();caches.open(CACHE).then(c=>c.put(e.request,cl))}return r}).catch(()=>hit);return hit||net}))});
