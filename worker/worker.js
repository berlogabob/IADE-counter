// CORS proxy for Nextcloud: public-share WebDAV (the share token is the credential)
// and the few admin calls the #/admin page needs (the caller's own Authorization header is forwarded; no secrets live here).
const NC = 'https://nextcloud.soundingdoubts.pt';
const ORIGINS = ['https://berlogabob.github.io', 'http://localhost:8080']; // shortcut: static allowlist, edit when the Pages URL changes
const PUBLIC = /^\/public\.php\/dav\/files\/[A-Za-z0-9]+(\/[\w.\-\/]*)?$/;
const ADMIN = [
  [/^\/ocs\/v2\.php\/apps\/files_sharing\/api\/v1\/shares(\/\d+)?$/, ['POST', 'GET', 'DELETE']],
  [/^\/remote\.php\/dav\/files\/[\w.\-@]+\/sessions(\/[\w.\-]+){0,2}\/?$/, ['MKCOL', 'PUT', 'PROPFIND']],
];

export default {
  async fetch(req) {
    const origin = req.headers.get('Origin');
    const cors = {
      'Access-Control-Allow-Origin': ORIGINS.includes(origin) ? origin : ORIGINS[0],
      'Access-Control-Allow-Methods': 'GET, PUT, POST, DELETE, MKCOL, PROPFIND, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, If-None-Match, Authorization, OCS-APIRequest, Depth',
      'Access-Control-Expose-Headers': 'ETag, Date',
      'Vary': 'Origin',
    };
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    const url = new URL(req.url);
    const path = url.pathname;
    const isPublic = PUBLIC.test(path) && ['GET', 'PUT'].includes(req.method);
    const isAdmin = ADMIN.some(([re, methods]) => re.test(path) && methods.includes(req.method));
    if (path.includes('..') || !(isPublic || isAdmin) || !ORIGINS.includes(origin) && isAdmin)
      return new Response('forbidden', { status: 403, headers: cors });
    const h = { 'Content-Type': req.headers.get('Content-Type') || 'application/json' };
    for (const k of ['If-None-Match', 'Depth'].concat(isAdmin ? ['Authorization', 'OCS-APIRequest', 'Accept'] : []))
      if (req.headers.get(k)) h[k] = req.headers.get(k);
    const res = await fetch(NC + path + url.search, {
      method: req.method, headers: h,
      body: ['GET', 'MKCOL', 'DELETE'].includes(req.method) ? undefined : req.body,
    });
    const out = new Response(res.body, res);
    for (const [k, v] of Object.entries(cors)) out.headers.set(k, v);
    out.headers.delete('Set-Cookie');
    out.headers.delete('WWW-Authenticate'); // keep the browser from popping its own password dialog
    return out;
  },
};
