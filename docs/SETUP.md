# Setup and open items

## How sessions work
The app is static (GitHub Pages). The Cloudflare Worker `iade-sync` (`worker/worker.js`) proxies Nextcloud.
`POST /new` on the Worker creates `sessions/<random>/state.json` + `notes.json` and three public shares
(edit, notes, read-only), using the Worker secrets `NC_USER` and `NC_PASS`. The browser never sees a password.
Routes: `#/host/<edit>/<notes>/<read>`, `#/view/<read>`, anything else = standalone timer.

## Worker secrets (run in `worker/`, values are prompted, never put them in git or chat)
    npx wrangler secret put NC_USER    # Nextcloud user ID (not the email)
    npx wrangler secret put NC_PASS    # a dedicated app password (Settings > Security > Devices & sessions)
    npx wrangler deploy
Check: `curl -s -X POST -H "Origin: https://berlogabob.github.io" "https://iade-sync.counter-iade.workers.dev/new?days=1"`
should return JSON with `edit`, `notes`, `read`. Revoke the app password in the same Nextcloud page to cut the Worker off.

## Open items (as of 2026-10-14)
- `POST /new` currently returns `{"error":"folder: HTTP 401"}`: Nextcloud rejects the stored NC_USER / NC_PASS.
  Likely a wrong user ID (email instead of user ID) or a mistyped password.
- The first app password (`iade-sync`) was pasted into a chat. Revoke it and make a new one before real use.
- `/new` has no caller check beyond the Origin header (curl can fake it). If abused, add a Cloudflare rate-limit rule on `/new`.
- Old test shares in `sessions/test/` are removed; their tokens remain in git history (harmless once the shares are gone).
- Not yet tested in a real browser: new-session page, host restore after reload, sound on viewer devices (autoplay policy),
  viewer clock within 1 s of host with a wrong device clock, wheel smoothness on a phone.
- Seen once on the old admin page: "Null check operator used on a null value" (cause not found; page replaced).
- Deferred: split `lib/main.dart` (F7), key notes by index instead of group name (F12), web UX audit
  (the Maestro Chromium run hung; retry with `maestro test`).

## Task runner
`tasks/PLAN.md`, `tasks/Txx.md`, `tasks/run.sh Txx` (runs `pi` or `codex`, gates the diff, commits, logs to `tasks/LOG.md`).
