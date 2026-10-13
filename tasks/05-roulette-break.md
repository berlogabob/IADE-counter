# 05 roulette wheel + break timer (one spec, two features)

Steps 2-4 work. Host pushes a `Snapshot` (lib/session.dart) every action and every 5 s while running; viewer polls it each second and mirrors. Both features follow the same pattern: host writes timestamps (server clock = `widget.sync!.nowMs()`), every screen computes what to show from them. No new packages. Do not touch `lib/phase.dart` or pubspec.

## Snapshot (session.dart)
Add three fields, default null/0, in constructor, `toJson`, `fromJson`, `==`, `hashCode`:
`int? spinAtMs` (server ms when the spin started), `int spinWinner` (group index, default 0), `int? breakEndMs` (server ms when the break ends).

## Wheel (NEW lib/wheel.dart)
```
const spinMs = 5000;      // animation length
const holdMs = 3000;      // winner stays visible after it stops
double wheelAngle(int n, int winner, double t) // t in 0..1 (clamp). Clockwise radians.
```
Slice i spans `[i*s, (i+1)*s)` with `s = 2*pi/n`, drawn starting at the top (-pi/2) and rotated by the angle. The pointer is fixed at the top. Final rotation `R = 2*pi*6 - (winner + 0.5) * s`; `wheelAngle = R * easeOutCubic(t)` where `easeOutCubic(x) = 1 - pow(1-x, 3)`. So at t=1 the winner's slice centre sits under the pointer.
`class WheelPainter extends CustomPainter` (labels = group names, alternating two theme colours, a small triangle pointer at the top, text centred in each slice, text shrinks to fit). Repaints from the angle passed in.
`Widget`: none needed; main.dart builds the overlay.

## Roulette flow (main.dart)
- Host-only button "Spin" (icon `Icons.casino`) in the bottom button `Wrap`, enabled only when idle and `_groups.length >= 2` and not finished.
- Press: `_spinWinner = Random().nextInt(_groups.length)`, `_spinAtMs = sync.nowMs()`, `_gi = _spinWinner`, `_si = 0`, then `_push()`. Add the three fields to `_push`; viewer applies them from the snapshot in `_startSync`.
- Overlay (host and viewer): a `Stack` over the whole `Scaffold` body while `elapsed = sync.nowMs() - spinAtMs` is in `0 .. spinMs + holdMs` and `_groups.length >= 2`: black 90% background, big `CustomPaint(WheelPainter)` sized to the shortest side * 0.8, `t = elapsed / spinMs`. After the spin ends show the winner name large under the wheel. A viewer that joins mid-spin shows the correct angle because it derives everything from timestamps.
- Add a UI repaint ticker for sync mode: `Timer.periodic(250 ms)` calling `setState` while an overlay could be visible (simplest: always on when `widget.sync != null`; during the spin use 50 ms). Cancel in `dispose`.

## Break flow (main.dart)
- Host-only button "Break" (icon `Icons.free_breakfast`), idle only. Opens an `AlertDialog` with a minutes field (default `10`, same `_minutes` parser) and Start/Cancel. Start sets `_breakEndMs = sync.nowMs() + minutes`, `_push()`.
- Overlay (host and viewer) while `_breakEndMs != null`: full screen, text "Break" and the clock `formatRemaining(Duration(milliseconds: _breakEndMs! - sync.nowMs()))` as big as possible (use `FittedBox` like the main clock). Background calm colour, turns red when remaining <= 0 (overtime, `+MM:SS`). It stays until the host presses an "End break" button shown on the host's overlay only: sets `_breakEndMs = null`, `_push()`.
- The break overlay replaces the wheel overlay if both are active.
- Standalone mode (no sync): neither button appears.

## Tests
- `test/wheel_test.dart`: for n = 2, 5, 7 and every winner, `((winner + 0.5) * s + wheelAngle(n, winner, 1)) % (2*pi)` is ~0 (or ~2*pi) within 1e-9; `wheelAngle(n, w, 0) == 0`; `t` is clamped outside 0..1.
- Extend the Snapshot roundtrip test with the three new fields.

## Acceptance
`flutter analyze`, `flutter test`, `flutter build web` pass.
