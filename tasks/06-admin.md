# 06 admin screen: create sessions, read-only viewer token, invites

The Worker (worker/worker.js, already deployed) proxies, with CORS and only for the allowed origin:
- `POST|GET|DELETE /ocs/v2.php/apps/files_sharing/api/v1/shares[/<id>]` (forwards Authorization, OCS-APIRequest, Accept)
- `MKCOL|PUT|PROPFIND /remote.php/dav/files/<user>/sessions[/<name>[/<file>]]`
- public shares `GET|PUT /public.php/dav/files/<token>` (unchanged)
Base URL = `Sync.worker` in lib/sync.dart. Do not edit the Worker, pubspec, or lib/phase.dart.

## 1. Route parsing (lib/session.dart + test)
Replace the ad hoc parsing in `main()` with a pure function in session.dart:
`({String role, List<String> tokens}) parseRoute(String fragment)`
- `/admin` -> role `admin`, no tokens
- `/host/<edit>` , `/host/<edit>/<notes>` , `/host/<edit>/<notes>/<read>` -> role `host`, tokens in that order
- `/view/<read>` -> role `viewer`, one token
- anything else -> role `standalone`
Tokens only `[A-Za-z0-9]+`; if a segment is not, treat the whole route as standalone. `main()` uses it: `TimerPage(sync: Sync(tokens[0]), notesSync: Sync(tokens[1]) if present, readToken: tokens[2] if present, viewer: role == 'viewer')`; admin -> `AdminPage`. `test/session_test.dart`: cases for each form, a bad token, and empty.

## 2. QR uses the read-only token
`TimerPage` gets `String? readToken`. In `_shareLink`, the viewer URL token is `widget.readToken ?? widget.sync!.token`.

## 3. Admin page (NEW lib/admin.dart, `class AdminPage extends StatefulWidget`)
Fields: Nextcloud user, app password (obscured), session name (letters/digits/dash only; validate), expiry in days (default 3). "Remember on this device" checkbox: stores user + app password in `window.localStorage` via `package:web`? No new packages: use `dart:html`-free approach, i.e. keep credentials in memory only and add one line saying "app password is kept in memory, re-enter after reload". (Ponytail: no persistence.)
Button "Create session":
1. Basic auth header `base64('user:pass')` on every call. Base: `${Sync.worker}/remote.php/dav/files/$user/sessions`.
2. `MKCOL .../sessions` (accept any of 201, 405 = exists), `MKCOL .../sessions/<name>` (201; 405 -> show "session name already exists" and stop).
3. `PUT .../sessions/<name>/state.json` body `{}` and `.../notes.json` body `{}`.
4. Three shares via `POST ${Sync.worker}/ocs/v2.php/apps/files_sharing/api/v1/shares?format=json`, form-encoded body, headers `OCS-APIRequest: true`, `Accept: application/json`:
   - `path=/sessions/<name>/state.json&shareType=3&permissions=3&expireDate=YYYY-MM-DD` -> edit token (host)
   - `path=/sessions/<name>/notes.json&shareType=3&permissions=3&expireDate=...` -> notes token
   - `path=/sessions/<name>/state.json&shareType=3&permissions=1&expireDate=...` -> read-only token (viewer)
   Token = `jsonDecode(body)['ocs']['data']['token']`. Any non-2xx (or `ocs.meta.statuscode` not 100/200) -> show the HTTP status and body text in a red `SelectableText`, stop.
5. Show the results: host URL `${base}#/host/<edit>/<notes>/<read>`, viewer URL `${base}#/view/<read>` where `base = Uri.base.replace(fragment: '').toString()` minus trailing `#`. Each in a `SelectableText` with a Copy button (reuse the `Clipboard.setData` pattern) and a `QrImageView`. Two `mailto:` links via `Uri(scheme:'mailto', queryParameters:{'subject':..., 'body': url})`: "Email host link", "Email viewer link" (open with `url_launcher`? NOT allowed, no new package: show the mailto URL as a copyable text field and a note "paste into your mail client").
Show a progress text line per step ("Creating folder…") and a busy indicator.
Layout: single column, max width 480, dark theme like the rest. No emoji.

## Tests
`parseRoute` tests only. `flutter analyze`, `flutter test`, `flutter build web` must pass.

## Out of scope
Listing or deleting old sessions (do it in Nextcloud).
