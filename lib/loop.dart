import 'dart:math';

/// Indexes 0..count-1 that are not in [done], ascending.
List<int> remaining(int count, List<int> done) => [
  for (var i = 0; i < count; i++)
    if (!done.contains(i)) i,
];

/// A random remaining index; null when none is left.
int? drawNext(int count, List<int> done, Random rnd) {
  final left = remaining(count, done);
  return left.isEmpty ? null : left[rnd.nextInt(left.length)];
}

/// The next stage, skipping disabled setup, qa and pack stages.
String nextStage(
  String stage, {
  required bool hasSetup,
  required bool hasQa,
  required bool hasPack,
}) => switch (stage) {
  'draw' => hasSetup ? 'setup' : 'talk',
  'setup' => 'talk',
  'talk' => hasQa ? 'qa' : (hasPack ? 'pack' : 'draw'),
  'qa' => hasPack ? 'pack' : 'draw',
  _ => 'draw',
};
