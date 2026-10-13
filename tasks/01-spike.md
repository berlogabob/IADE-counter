# 01 spike: CORS proxy + WebDAV round trip
Gate for all later steps. Done by hand, not delegated.
1. In Nextcloud create folder `sessions/test/` with empty `state.json`; share the FILE (or folder) as public link, edit permission, no password. Token = last path part of the link.
2. `cd worker && npx wrangler deploy` -> note the workers.dev URL.
3. Verify: `curl -i -X OPTIONS <worker>/public.php/dav/files/<token>/state.json -H 'Origin: https://berlogabob.github.io' -H 'Access-Control-Request-Method: PUT'` -> 204 + Access-Control-* headers.
4. Push; open `https://berlogabob.github.io/IADE-counter/spike.html#<worker>|<token>`.
Pass: PUT 2xx, GET 200 with ETag + Date visible, If-None-Match -> 304.
Fails with 404 on the dav path: Nextcloud is older than 31; switch the path to `/public.php/webdav/` with Basic auth `<token>:` and update PATH in worker.js.
