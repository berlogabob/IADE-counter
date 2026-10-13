# Plan: fix the audit findings with ornith 35b (pi) and codex

Source: ponytail audit of 2026-10-13 (findings F1-F13). Claude tokens: spec + one final review only. Everything between is `tasks/run.sh`.
Baseline: commit `aa58e2b`+, 23 tests, `flutter analyze` clean.

## How a task runs (no Claude involved)
`tasks/run.sh T01` reads `tasks/T01.md` (header: title, runner, finding, files, max_diff, tests_min), runs the runner, then gates:
1. only the listed `files` changed (stops the pubspec wipe seen earlier);
2. diff lines <= `max_diff`;
3. `flutter analyze` clean, `flutter test` passes, test count >= `tests_min`;
then commits as `T01 (F1): <title>` and appends one row to `tasks/LOG.md` (date, task, runner, result, tests, diff lines, seconds, commit). Any gate fails: nothing is committed, the log row says why, rollback command is printed.
Runners: `pi` = ornith 35b on the Studio PC, for small single-file edits (told not to run commands, it loops when it tries). `codex` = codex exec, for tasks that need to run tests or touch pubspec/CI.

## Tasks (run in this order; each is one commit)
| Task | Finding | Runner | Files | Measurable target |
|---|---|---|---|---|
| T00 | F5 prereq | pi | sync.dart | `Sync(token, client:)` injectable; tests stay 23 |
| T01 | F1 clock never corrected | codex | sync.dart, test/sync_test.dart | tests >= 26; parser returns exact epoch for 2 real dates |
| T02 | F4 bad JSON crashes poll | pi | sync.dart, test | tests >= 28; 2 bad bodies return null |
| T03 | F3 out-of-order pushes | codex | sync.dart, test | tests >= 29; server sees exactly `[a, c]` |
| T04 | F2+F6 choppy wheel / 20 Hz | pi | main.dart, wheel.dart, test | tests >= 30; viewer calls `_ensureRepaint` on spin; interval 50 ms only while wheel active |
| T05 | F8 notes overwritten | pi | main.dart | merge keeps local edits; tests stay >= 30 |
| T06 | F9 stuck session name | pi | admin.dart | hint text on failure after folder created |
| T07 | F10 unused dep | codex | pubspec | `cupertino_icons` gone; web build passes |
| T08 | F13 unpinned Flutter | codex | pages.yml | `flutter-version: 3.47.7` present |
| T09 | F11 localhost origin | pi | worker.js | one origin left; then owner redeploys Worker |

Run all, stopping at the first failure: `for t in T00 T01 T02 T03 T04 T05 T06 T07 T08 T09; do tasks/run.sh $t || break; done`
Expected end state: 10 commits, tests >= 30, `tasks/LOG.md` has 10 OK rows.

## Manual steps (owner)
- After T09: `cd worker && npx wrangler deploy`, then `curl -i -X OPTIONS <worker>/ocs/... -H 'Origin: http://localhost:8080'` must not return that origin.
- Revoke the two test shares in Nextcloud (`sessions/test/`).
- Browser check after T01+T04 (the two user-visible fixes): put a tablet or phone with a wrong clock on the viewer link; countdown must match the host within 1 s; spin the wheel and watch it on the viewer (smooth, not 4 fps).

## Review (Claude, once, at the end)
`git diff aa58e2b..HEAD --stat`, then read only `lib/sync.dart` and the `lib/main.dart` hunks. Budget: one read, one fix commit if needed.

## Deferred (not specified, do not start)
- F7 split `main.dart` (963 lines) into overlay/notes widgets: do after the above is green, one widget per task, target `main.dart` <= 800 lines.
- F12 notes keyed by group name: key by index.
- UX audit (/app-audit web): Maestro Chromium hung on the first screenshot (Flutter canvas). Retry with `maestro test` CLI flows after the fixes land; screens to cover: standalone, admin, host (fake tokens), viewer.
- Browser audio on viewers (autoplay policy), admin page against real Nextcloud: unverified.
