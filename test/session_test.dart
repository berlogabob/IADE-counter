import 'package:flutter_test/flutter_test.dart';
import 'package:iade_counter/session.dart';

void main() {
  test('toJson/fromJson roundtrip equals', () {
    const s = Snapshot(
      endMs: 1_700_000_000_000,
      pausedMs: null,
      inQa: true,
      totalMs: 900_000,
      warnMs: 60_000,
      qaMs: 600_000,
      student: 3,
      log: ['#1  talk 15:00', '#2  talk 16:12 (+01:12)  Q&A 08:40'],
      rev: 7,
    );
    expect(Snapshot.fromJson(s.toJson()), s);
  });

  test('remaining: running returns time until endMs', () {
    const s = Snapshot(
      endMs: 1_000_000,
      totalMs: 900_000,
      warnMs: 60_000,
      qaMs: 600_000,
      student: 1,
    );
    final r = s.remaining(800_000);
    expect(r, const Duration(seconds: 200));
  });

  test('remaining: paused returns pausedMs', () {
    const s = Snapshot(
      pausedMs: 123_000,
      totalMs: 900_000,
      warnMs: 60_000,
      qaMs: 600_000,
      student: 1,
    );
    expect(s.remaining(0), const Duration(milliseconds: 123_000));
  });

  test('remaining: idle returns the limit for talk and Q&A', () {
    const talk = Snapshot(
      inQa: false,
      totalMs: 900_000,
      warnMs: 60_000,
      qaMs: 600_000,
      student: 1,
    );
    const qa = Snapshot(
      inQa: true,
      totalMs: 900_000,
      warnMs: 60_000,
      qaMs: 600_000,
      student: 1,
    );
    expect(talk.remaining(0), const Duration(milliseconds: 900_000));
    expect(qa.remaining(0), const Duration(milliseconds: 600_000));
  });

  test('remaining: caller can apply a nonzero offset via nowMs', () {
    const s = Snapshot(
      endMs: 1_000_000,
      totalMs: 900_000,
      warnMs: 60_000,
      qaMs: 600_000,
      student: 1,
    );
    // Server is 10s ahead of the local clock.
    final r = s.remaining(800_000 + 10_000);
    expect(r, const Duration(seconds: 190));
  });
}
