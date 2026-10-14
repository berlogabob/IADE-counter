import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iade_counter/loop.dart';

void main() {
  test(
    'wheelPool keeps all names and the winner slot when nothing is done',
    () {
      final pool = wheelPool(['A', 'B', 'C'], [], 1);
      expect(pool.labels, ['A', 'B', 'C']);
      expect(pool.winnerSlot, 1);
    },
  );
  test('wheelPool removes done names and shifts the winner slot', () {
    final pool = wheelPool(['A', 'B', 'C', 'D'], [0, 2], 3);
    expect(pool.labels, ['B', 'D']);
    expect(pool.winnerSlot, 1);
  });
  test('wheelPool has no winner slot for done or out-of-range winners', () {
    for (final winner in [1, -1, 3]) {
      final pool = wheelPool(['A', 'B', 'C'], [1], winner);
      expect(pool.labels, ['A', 'C']);
      expect(pool.winnerSlot, -1);
    }
    final empty = wheelPool([], [], 0);
    expect(empty.labels, isEmpty);
    expect(empty.winnerSlot, -1);
  });
  test('remaining ignores done and out-of-range entries', () {
    expect(remaining(4, []), [0, 1, 2, 3]);
    expect(remaining(4, [2, 0, 2, -1, 4, 99]), [1, 3]);
  });
  test('drawNext handles exhausted and single-choice rosters', () {
    expect(drawNext(3, [0, 1, 2], Random(1)), isNull);
    expect(drawNext(0, [], Random(1)), isNull);
    expect(drawNext(3, [0, 2], Random(1)), 1);
  });
  test('drawNext never draws a done index', () {
    final rnd = Random(1);
    for (var i = 0; i < 200; i++) {
      expect(drawNext(5, [0, 2, 4], rnd), isIn([1, 3]));
    }
  });
  test('nextStage full loop and unknown stage', () {
    const stages = ['', 'draw', 'setup', 'talk', 'qa', 'pack', 'draw'];
    for (var i = 0; i < stages.length - 1; i++) {
      expect(
        nextStage(stages[i], hasSetup: true, hasQa: true, hasPack: true),
        stages[i + 1],
      );
    }
    expect(
      nextStage('unknown', hasSetup: true, hasQa: true, hasPack: true),
      'draw',
    );
  });
  test('nextStage skips each disabled stage and combined skips', () {
    expect(
      nextStage('draw', hasSetup: false, hasQa: true, hasPack: true),
      'talk',
    );
    expect(
      nextStage('talk', hasSetup: true, hasQa: false, hasPack: true),
      'pack',
    );
    expect(
      nextStage('qa', hasSetup: true, hasQa: true, hasPack: false),
      'draw',
    );
    expect(
      nextStage('talk', hasSetup: false, hasQa: false, hasPack: false),
      'draw',
    );
  });
}
