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
      groups: [
        Group(name: 'Group A', planned: '14:30', students: ['Ana', 'Rui']),
        Group(name: 'Group B', planned: '', students: ['Sam']),
      ],
      gi: 1,
      si: 0,
      rev: 7,
    );
    expect(Snapshot.fromJson(s.toJson()), s);
  });

  test('parseRoster: time, students, and extra spaces', () {
    final groups = parseRoster(
      '14:30 Group A: Ana, Rui\n15:00 Group B\nGroup C:   Solo   ',
    );
    expect(groups, [
      const Group(name: 'Group A', planned: '14:30', students: ['Ana', 'Rui']),
      const Group(name: 'Group B', planned: '15:00', students: []),
      const Group(name: 'Group C', planned: '', students: ['Solo']),
    ]);
  });

  test('parseRoster: blank lines ignored, no students list', () {
    final groups = parseRoster('\n\nSolo Group\n\n');
    expect(groups, [
      const Group(name: 'Solo Group', planned: '', students: []),
    ]);
  });

  test('startDelta: late, early, on time', () {
    final actual = DateTime(2024, 1, 1, 14, 35);
    expect(startDelta('14:30', actual), 5);
    expect(startDelta('14:40', actual), -5);
    expect(startDelta('14:30', DateTime(2024, 1, 1, 14, 30)), 0);
  });

  test('startDelta: empty or malformed planned returns null', () {
    expect(startDelta('', DateTime.now()), null);
    expect(startDelta('14', DateTime.now()), null);
    expect(startDelta('aa:bb', DateTime.now()), null);
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
