enum Stage { setup, talk, qa, pack }

class Cycle {
  const Cycle({
    required this.setup,
    required this.talk,
    required this.warn,
    required this.qa,
    required this.pack,
  });

  final Duration setup, talk, warn, qa, pack;

  Duration lengthOf(Stage s) => switch (s) {
    Stage.setup => setup,
    Stage.talk => talk,
    Stage.qa => qa,
    Stage.pack => pack,
  };

  /// Advances through the loop, skipping zero-length stages except talk.
  Stage next(Stage s) {
    var next = s;
    do {
      next = Stage.values[(next.index + 1) % Stage.values.length];
    } while (next != Stage.talk && lengthOf(next) == Duration.zero);
    return next;
  }

  bool warning(Stage s, Duration remaining) =>
      s == Stage.talk && remaining > Duration.zero && remaining <= warn;
}

String stageLabel(Stage s) => switch (s) {
  Stage.setup => 'Setup',
  Stage.talk => 'Presentation',
  Stage.qa => 'Q&A',
  Stage.pack => 'Pack',
};
