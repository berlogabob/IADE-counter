// CORS proxy for Nextcloud: public-share WebDAV (the share token is the credential),
// plus POST /new, which creates a session with the NC_USER / NC_PASS secrets (wrangler secret put) so no password reaches the browser.
const NC = 'https://nextcloud.soundingdoubts.pt';
const ORIGINS = ['https://berlogabob.github.io']; // shortcut: static allowlist, edit when the Pages URL changes
const PUBLIC = /^\/public\.php\/dav\/files\/[A-Za-z0-9]+(\/[\w.\-\/]*)?$/;

export default {
  async fetch(req, env) {
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
    if (path === '/new' && req.method === 'POST' && ORIGINS.includes(origin)) return newSession(env, url, cors);
    if (path === '/join' && req.method === 'POST' && ORIGINS.includes(origin)) return join(env, url, cors);
    if (path.includes('..') || !isPublic) return new Response('forbidden', { status: 403, headers: cors });
    const h = { 'Content-Type': req.headers.get('Content-Type') || 'application/json' };
    for (const k of ['If-None-Match', 'Depth']) if (req.headers.get(k)) h[k] = req.headers.get(k);
    const res = await fetch(NC + path + url.search, {
      method: req.method, headers: h,
      body: req.method === 'GET' ? undefined : req.body,
    });
    const out = new Response(res.body, res);
    for (const [k, v] of Object.entries(cors)) out.headers.set(k, v);
    out.headers.delete('Set-Cookie');
    out.headers.delete('WWW-Authenticate'); // keep the browser from popping its own password dialog
    return out;
  },
};

// Creates sessions/<random>/{state,notes,jury}.json and their shares; returns the tokens.
// shortcut: no caller check beyond Origin (curl can fake it); add a Cloudflare rate-limit rule if it gets abused.
async function newSession(env, url, cors) {
  const json = (o, status = 200) =>
    new Response(JSON.stringify(o), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
  const auth = 'Basic ' + btoa(`${env.NC_USER}:${env.NC_PASS}`);
  const nc = (path, init) => fetch(NC + path, { ...init, headers: { Authorization: auth, ...init.headers } });
  const days = Math.min(30, Math.max(1, parseInt(url.searchParams.get('days')) || 3));
  const name = 's-' + [...crypto.getRandomValues(new Uint8Array(6))].map((b) => (b % 36).toString(36)).join('');
  const dav = `/remote.php/dav/files/${env.NC_USER}/sessions`;
  try {
    await nc(dav, { method: 'MKCOL' }); // 405 = already there
    let r = await nc(`${dav}/${name}`, { method: 'MKCOL' });
    if (r.status !== 201) return json({ error: `folder: HTTP ${r.status}` }, 502);
    for (const f of ['state.json', 'notes.json', 'jury.json']) {
      r = await nc(`${dav}/${name}/${f}`, { method: 'PUT', body: '{}', headers: { 'Content-Type': 'application/json' } });
      if (r.status !== 201 && r.status !== 204) return json({ error: `file: HTTP ${r.status}` }, 502);
    }
    const expire = new Date(Date.now() + days * 864e5).toISOString().slice(0, 10);
    const share = async (file, perm) => {
      const res = await nc('/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json', {
        method: 'POST',
        headers: { 'OCS-APIRequest': 'true', Accept: 'application/json', 'Content-Type': 'application/x-www-form-urlencoded' },
        body: `path=${encodeURIComponent(`/sessions/${name}/${file}`)}&shareType=3&permissions=${perm}&expireDate=${expire}`,
      });
      const token = (await res.json())?.ocs?.data?.token;
      if (res.status !== 200 || typeof token !== 'string') throw new Error(`share: HTTP ${res.status}`);
      return token;
    };
    return json({ edit: await share('state.json', 3), notes: await share('notes.json', 3), read: await share('state.json', 1), jury: await share('jury.json', 1) });
  } catch (e) {
    return json({ error: String(e.message || e) }, 502);
  }
}

// A professor opens the jury link and gives a name: find (or make) sessions/<s>/notes-<name>.json and return an edit share for it.
// The jury token is a read-only share of jury.json; it tells us which session folder to use.
async function join(env, url, cors) {
  const json = (o, status = 200) =>
    new Response(JSON.stringify(o), { status, headers: { ...cors, 'Content-Type': 'application/json' } });
  const auth = 'Basic ' + btoa(`${env.NC_USER}:${env.NC_PASS}`);
  const nc = (path, init) => fetch(NC + path, { ...init, headers: { Authorization: auth, ...init.headers } });
  const OCS = '/ocs/v2.php/apps/files_sharing/api/v1/shares';
  const ocs = { 'OCS-APIRequest': 'true', Accept: 'application/json' };
  const t = url.searchParams.get('t') || '';
  const slug = (url.searchParams.get('name') || '').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 24);
  if (!/^[A-Za-z0-9]+$/.test(t) || !slug) return json({ error: 'bad request' }, 400);
  try {
    const all = (await (await nc(`${OCS}?format=json`, { method: 'GET', headers: ocs })).json())?.ocs?.data || [];
    const j = all.find((s) => s.token === t && /^\/sessions\/s-[a-z0-9]+\/jury\.json$/.test(s.path));
    if (!j) return json({ error: 'link expired or unknown' }, 404);
    const file = j.path.replace(/jury\.json$/, `notes-${slug}.json`);
    const have = all.find((s) => s.path === file && s.share_type === 3 && (s.permissions & 2));
    if (have) return json({ notes: have.token });
    const r = await nc(`/remote.php/dav/files/${env.NC_USER}${file}`, {
      method: 'PUT', body: '{}', headers: { 'Content-Type': 'application/json', 'If-None-Match': '*' },
    });
    if (![201, 204, 412].includes(r.status)) return json({ error: `file: HTTP ${r.status}` }, 502);
    const exp = j.expiration ? `&expireDate=${j.expiration.slice(0, 10)}` : '';
    const res = await nc(`${OCS}?format=json`, {
      method: 'POST',
      headers: { ...ocs, 'Content-Type': 'application/x-www-form-urlencoded' },
      body: `path=${encodeURIComponent(file)}&shareType=3&permissions=3${exp}`,
    });
    const token = (await res.json())?.ocs?.data?.token;
    if (res.status !== 200 || typeof token !== 'string') return json({ error: `share: HTTP ${res.status}` }, 502);
    return json({ notes: token });
  } catch (e) {
    return json({ error: String(e.message || e) }, 502);
  }
}
