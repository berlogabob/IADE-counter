# 02 sync core: host pushes state, viewer mirrors it

Spike passed (worker + Nextcloud public share PUT/GET/ETag/304 all work from github.io).
Implement with the smallest diff. No new abstractions, no router package, no state-management package.

## Files
- `pubspec.yaml`: `flutter pub add http` (only new dependency).
- NEW `lib/sync.dart` (~60 lines)
- NEW `lib/session.dart` (~40 lines)
- `lib/main.dart`: small edits (below)
- `test/session_test.dart`: one test file

## session.dart: `Snapshot`
Plain class, fields: `int? endMs` (epoch ms, server-adjusted), `int? pausedMs`, `bool inQa`, `int totalMs`, `warnMs`, `qaMs`, `int student` (1-based), `List<String> log`, `int rev` (host increments on every push).
- `toJson()` / `Snapshot.fromJson(Map)`.
- `Duration remaining(int nowMs)`: if `endMs != null` -> `endMs - nowMs`; else if `pausedMs != null` -> that; else the limit (`inQa ? qaMs : totalMs`). Same rule as `_remaining` in main.dart.

## sync.dart: `Sync`
```
class Sync {
  Sync(this.token);
  static const worker = 'https://iade-sync.counter-iade.workers.dev';
  final String token;
  int offsetMs = 0; // server clock minus local clock
  int nowMs() => DateTime.now().millisecondsSinceEpoch + offsetMs;
  Future<Snapshot?> poll();        // GET with If-None-Match (keep last ETag); 304 -> null; updates offsetMs from the Date header (HttpDate.parse)
  Future<void> push(Snapshot s);   // PUT json, Content-Type application/json; ignore errors (host keeps running offline)
}
```
URL = `$worker/public.php/dav/files/$token`. Wrap network calls in try/catch, return null / swallow on failure. Empty or invalid body (new empty share) -> return null.
Both ETag and Date are readable in the browser (the worker exposes them).

## main.dart edits
1. Route by URL fragment, parsed by hand from `Uri.base.fragment`: `/host/<token>` -> host, `/view/<token>` -> viewer, anything else -> today's standalone behaviour (no Sync, nothing changes).
2. `TimerPage({this.sync, this.viewer = false})`.
3. Host (sync != null, !viewer): after each of `_run`, `_pause`, `_startQa`, `_nextStudent`, `_reset` call `_push()`, which builds a Snapshot from the existing fields (`_end` -> `endMs` via `sync.offsetMs`) and calls `sync.push`. Also push once every 5 s while running (viewer recovery).
4. Viewer: `Timer.periodic(1s)` -> `sync.poll()`; on a new snapshot (`rev` changed) set `_total/_warn/_qa/_inQa/_end/_paused` and `_log` from it, start the existing 200 ms `_ticker` if running, stop it if not. The existing `_tick()` already drives phase colours and alert sounds, keep using it. Hide the setup fields, the buttons, and the log buttons when `viewer` (show only student label + clock + log text). Do not call `WakelockPlus` differently; viewer keeps the screen on while running as before.
5. Do not touch `phase.dart`.

## Test (`test/session_test.dart`, plain `flutter test`)
- toJson/fromJson roundtrip equals.
- `remaining`: running (endMs in future), paused, idle (returns limit for talk and for Q&A), and with a nonzero offset applied by the caller.

## Acceptance
- `flutter analyze` and `flutter test` pass.
- `flutter build web` passes.
- Manual (Claude does it, not you): host tab at `#/host/LnfqGMop8n3ktyt`, viewer tab at `#/view/LnfqGMop8n3ktyt`; Start/Pause/Q&A/Next student on host appear on viewer within ~2 s; reload viewer mid-talk resumes at the right time.

## Out of scope (later steps)
Roster, notes, roulette, break timer, QR, admin screen, per-role tokens.
