/// Mirrors the host's timer state so a viewer can mirror it exactly.
///
/// A plain data object: no logic beyond serialisation and the remaining-time
/// rule (kept identical to `_remaining` in main.dart).
class Snapshot {
  const Snapshot({
    this.endMs,
    this.pausedMs,
    this.inQa = false,
    required this.totalMs,
    required this.warnMs,
    required this.qaMs,
    required this.student,
    this.log = const [],
    this.rev = 0,
  });

  /// Epoch ms the run ends at, while running (server-adjusted).
  final int? endMs;

  /// Epoch ms of remaining time while paused.
  final int? pausedMs;
  final bool inQa;
  final int totalMs;
  final int warnMs;
  final int qaMs;

  /// 1-based student number.
  final int student;
  final List<String> log;

  /// Host increments on every push; viewer applies a snapshot only when it
  /// differs from the last one it applied.
  final int rev;

  @override
  bool operator ==(Object other) =>
      other is Snapshot &&
      other.runtimeType == runtimeType &&
      endMs == other.endMs &&
      pausedMs == other.pausedMs &&
      inQa == other.inQa &&
      totalMs == other.totalMs &&
      warnMs == other.warnMs &&
      qaMs == other.qaMs &&
      student == other.student &&
      _listEquals(log, other.log) &&
      rev == other.rev;

  @override
  int get hashCode => Object.hash(
    endMs,
    pausedMs,
    inQa,
    totalMs,
    warnMs,
    qaMs,
    student,
    Object.hashAll(log),
    rev,
  );

  Map<String, dynamic> toJson() => {
    'endMs': endMs,
    'pausedMs': pausedMs,
    'inQa': inQa,
    'totalMs': totalMs,
    'warnMs': warnMs,
    'qaMs': qaMs,
    'student': student,
    'log': log,
    'rev': rev,
  };

  factory Snapshot.fromJson(Map<String, dynamic> json) => Snapshot(
    endMs: json['endMs'] as int?,
    pausedMs: json['pausedMs'] as int?,
    inQa: (json['inQa'] as bool? ?? false),
    totalMs: json['totalMs'] as int? ?? 0,
    warnMs: json['warnMs'] as int? ?? 0,
    qaMs: json['qaMs'] as int? ?? 0,
    student: json['student'] as int? ?? 1,
    log: (json['log'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(),
    rev: json['rev'] as int? ?? 0,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Remaining time, mirroring `_remaining` in main.dart:
  /// running -> time until [endMs], paused -> [pausedMs], else the limit.
  Duration remaining(int nowMs) {
    if (endMs != null) return Duration(milliseconds: endMs! - nowMs);
    if (pausedMs != null) return Duration(milliseconds: pausedMs!);
    return Duration(milliseconds: inQa ? qaMs : totalMs);
  }
}
