import 'package:flutter_test/flutter_test.dart';
import 'package:iade_counter/cycle.dart';

void main() {
  Cycle cycle({int setup = 2, int talk = 15, int qa = 5, int pack = 3}) =>
      Cycle(
        setup: Duration(minutes: setup),
        talk: Duration(minutes: talk),
        warn: const Duration(minutes: 1),
        qa: Duration(minutes: qa),
        pack: Duration(minutes: pack),
      );

  test('lengths', () {
    final c = cycle();
    expect(c.lengthOf(Stage.setup), const Duration(minutes: 2));
    expect(c.lengthOf(Stage.talk), const Duration(minutes: 15));
    expect(c.lengthOf(Stage.qa), const Duration(minutes: 5));
    expect(c.lengthOf(Stage.pack), const Duration(minutes: 3));
  });

  test('next follows the stage order', () {
    final c = cycle();
    expect(c.next(Stage.setup), Stage.talk);
    expect(c.next(Stage.talk), Stage.qa);
    expect(c.next(Stage.qa), Stage.pack);
    expect(c.next(Stage.pack), Stage.setup);
  });

  test('zero qa is skipped', () {
    expect(cycle(qa: 0).next(Stage.talk), Stage.pack);
  });

  test('zero pack is skipped', () {
    expect(cycle(pack: 0).next(Stage.qa), Stage.setup);
  });

  test('zero setup is skipped', () {
    expect(cycle(setup: 0).next(Stage.pack), Stage.talk);
  });

  test('talk is never skipped even when all lengths are zero', () {
    final c = cycle(setup: 0, talk: 0, qa: 0, pack: 0);
    for (final stage in Stage.values) {
      expect(c.next(stage), Stage.talk);
    }
  });

  test('warning boundaries apply only to talk', () {
    final c = cycle();
    expect(c.warning(Stage.talk, c.warn), isTrue);
    expect(c.warning(Stage.talk, const Duration(seconds: 1)), isTrue);
    expect(c.warning(Stage.talk, Duration.zero), isFalse);
    expect(c.warning(Stage.talk, const Duration(seconds: -1)), isFalse);
    expect(c.warning(Stage.talk, const Duration(seconds: 61)), isFalse);
    for (final stage in [Stage.setup, Stage.qa, Stage.pack]) {
      expect(c.warning(stage, c.warn), isFalse);
    }
  });

  test('labels', () {
    expect(stageLabel(Stage.setup), 'Setup');
    expect(stageLabel(Stage.talk), 'Presentation');
    expect(stageLabel(Stage.qa), 'Q&A');
    expect(stageLabel(Stage.pack), 'Pack');
  });
}
