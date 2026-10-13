// CORS proxy for Nextcloud public-share WebDAV only. No secrets: the share token in the path is the credential.
const NC = 'https://nextcloud.soundingdoubts.pt';
const ORIGINS = ['https://berlogabob.github.io', 'http://localhost:8080']; // shortcut: static allowlist, edit when the Pages URL changes
const PATH = /^\/public\.php\/dav\/files\/[A-Za-z0-9]+(\/[\w.\-\/]*)?$/;

export default {
  async fetch(req) {
    const origin = req.headers.get('Origin');
    const cors = {
      'Access-Control-Allow-Origin': ORIGINS.includes(origin) ? origin : ORIGINS[0],
      'Access-Control-Allow-Methods': 'GET, PUT, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, If-None-Match',
      'Access-Control-Expose-Headers': 'ETag, Date',
      'Vary': 'Origin',
    };
    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    const url = new URL(req.url);
    if (!['GET', 'PUT'].includes(req.method) || !PATH.test(url.pathname) || url.pathname.includes('..'))
      return new Response('forbidden', { status: 403, headers: cors });
    const res = await fetch(NC + url.pathname, {
      method: req.method,
      headers: { 'Content-Type': req.headers.get('Content-Type') || 'application/json',
                 ...(req.headers.get('If-None-Match') && { 'If-None-Match': req.headers.get('If-None-Match') }) },
      body: req.method === 'PUT' ? req.body : undefined,
    });
    const out = new Response(res.body, res);
    for (const [k, v] of Object.entries(cors)) out.headers.set(k, v);
    out.headers.delete('Set-Cookie');
    return out;
  },
};
