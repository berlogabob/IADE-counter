import 'package:flutter_test/flutter_test.dart';
import 'package:iade_counter/session.dart';

void main() {
  test('snapshot roundtrips setup, pack, stage and done', () {
    const s = Snapshot(
      totalMs: 900000,
      warnMs: 60000,
      qaMs: 600000,
      student: 1,
      setupMs: 180000,
      packMs: 90000,
      stage: 'pack',
      done: [0, 2],
    );
    expect(Snapshot.fromJson(s.toJson()), s);
  });
  test('old snapshot JSON loads new field defaults', () {
    final s = Snapshot.fromJson({});
    expect(s.setupMs, 120000);
    expect(s.packMs, 60000);
    expect(s.stage, '');
    expect(s.done, isEmpty);
  });
  test('snapshot done compares and hashes list contents', () {
    final done = [0, 2];
    final a = Snapshot.fromJson({'done': done});
    final b = Snapshot.fromJson({'done': List<int>.of(done)});
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a, isNot(Snapshot.fromJson({'done': done.reversed.toList()})));
  });
  test('snapshot stage roundtrips', () {
    for (final stage in ['', 'setup', 'talk', 'qa', 'pack', 'draw']) {
      final s = Snapshot.fromJson({'stage': stage});
      expect(Snapshot.fromJson(s.toJson()).stage, stage);
    }
  });
  test('parseRoute: /admin is the admin role with no tokens', () {
    final r = parseRoute('/admin');
    expect(r.role, 'admin');
    expect(r.tokens, isEmpty);
  });

  test('parseRoute: /host with one (edit) token', () {
    final r = parseRoute('/host/ABC123');
    expect(r.role, 'host');
    expect(r.tokens, ['ABC123']);
  });

  test('parseRoute: /host with two (edit, notes) tokens, in order', () {
    final r = parseRoute('/host/ab/cd');
    expect(r.role, 'host');
    expect(r.tokens, ['ab', 'cd']);
  });

  test('parseRoute: /host with three (edit, notes, read) tokens, in order', () {
    final r = parseRoute('/host/ab/cd/EF');
    expect(r.role, 'host');
    expect(r.tokens, ['ab', 'cd', 'EF']);
  });

  test('parseRoute: /view with one (read) token', () {
    final r = parseRoute('/view/xyz789');
    expect(r.role, 'viewer');
    expect(r.tokens, ['xyz789']);
  });

  test('parseRoute: a non-alphanumeric token segment makes it standalone', () {
    expect(parseRoute('/host/AB-CD').role, 'standalone');
    expect(parseRoute('/host/AB-CD').tokens, isEmpty);
    expect(parseRoute('/view/ab-cd').role, 'standalone');
  });

  test(
    'parseRoute: empty, empty segments and unknown fragments are standalone',
    () {
      expect(parseRoute('').role, 'standalone');
      expect(parseRoute('/host/').role, 'standalone');
      expect(parseRoute('/view/').role, 'standalone');
      expect(parseRoute('?total=15').role, 'standalone');
    },
  );

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
      finished: true,
      si: 0,
      spinAtMs: 1_700_000_005_000,
      spinWinner: 2,
      breakEndMs: 1_700_000_060_000,
      breakLabel: 'Setup',
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
