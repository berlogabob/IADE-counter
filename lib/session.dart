/// One roster line: a group name, an optional planned start time and the
/// students expected in it.
class Group {
  const Group({
    required this.name,
    this.planned = '',
    this.students = const [],
  });

  /// Group name shown in the label and log.
  final String name;

  /// Planned start as 'HH:MM', or '' when none was given.
  final String planned;

  /// Students named for this group (may be empty).
  final List<String> students;

  Map<String, dynamic> toJson() => {
    'name': name,
    'planned': planned,
    'students': students,
  };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
    name: (json['name'] as String? ?? ''),
    planned: (json['planned'] as String? ?? ''),
    students: (json['students'] as List<dynamic>? ?? const [])
        .map((e) => e.toString())
        .toList(),
  );

  @override
  bool operator ==(Object other) =>
      other is Group &&
      other.name == name &&
      other.planned == planned &&
      _sameList(students, other.students);

  @override
  int get hashCode => Object.hash(name, planned, Object.hashAll(students));

  static bool _sameList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Parse a roster into [Group]s, one per non-empty line.
///
/// Each line is `'HH:MM Group name: student, student'`; the time is optional,
/// so is the student list. Lines that are blank are ignored.
List<Group> parseRoster(String text) {
  final lineRe = RegExp(r'^(\d{1,2}:\d{2})?\s*([^:]+?)\s*(?::\s*(.*))?$');
  final groups = <Group>[];
  for (final rawLine in text.split('\n')) {
    final line = rawLine.trim();
    if (line.isEmpty) continue;
    final m = lineRe.firstMatch(line);
    if (m == null || m.end != line.length) continue;
    final planned = m.group(1) ?? '';
    final name = (m.group(2) ?? '').trim();
    final studentsRaw = m.group(3) ?? '';
    final students = studentsRaw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    groups.add(Group(name: name, planned: planned, students: students));
  }
  return groups;
}

/// Minutes the [actual] start was after (positive) or before (negative) the
/// planned 'HH:MM' time. Null when [planned] is empty or malformed. Same-day
/// arithmetic only.
int? startDelta(String planned, DateTime actual) {
  if (planned.isEmpty) return null;
  final parts = planned.split(':');
  if (parts.length != 2) return null;
  final h = int.tryParse(parts[0]);
  final mi = int.tryParse(parts[1]);
  if (h == null || mi == null) return null;
  final plannedAt = DateTime(actual.year, actual.month, actual.day, h, mi);
  return actual.difference(plannedAt).inMinutes;
}

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
    this.groups = const [],
    this.gi = 0,
    this.si = 0,
    this.finished = false,
    this.spinAtMs,
    this.spinWinner = 0,
    this.breakEndMs,
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

  /// Roster groups parsed from the host's roster field (empty when none).
  final List<Group> groups;

  /// Index of the current group within [groups].
  final int gi;

  /// Index of the current student within its group.
  final int si;

  /// True once the last student of the last group is done ("All done").
  final bool finished;

  /// Epoch ms the roulette spin started, while the wheel is animating.
  final int? spinAtMs;

  /// Group index the wheel stopped on (0 while not spinning).
  final int spinWinner;

  /// Epoch ms the break ends, or null when there is no break running.
  final int? breakEndMs;

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
      _listEquals(groups, other.groups) &&
      gi == other.gi &&
      finished == other.finished &&
      si == other.si &&
      spinAtMs == other.spinAtMs &&
      spinWinner == other.spinWinner &&
      breakEndMs == other.breakEndMs &&
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
    Object.hashAll(groups),
    gi,
    finished,
    si,
    spinAtMs,
    spinWinner,
    breakEndMs,
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
    'groups': groups.map((g) => g.toJson()).toList(),
    'gi': gi,
    'finished': finished,
    'si': si,
    'spinAtMs': spinAtMs,
    'spinWinner': spinWinner,
    'breakEndMs': breakEndMs,
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
    groups: (json['groups'] as List<dynamic>? ?? const [])
        .map((e) => Group.fromJson(e as Map<String, dynamic>))
        .toList(),
    gi: json['gi'] as int? ?? 0,
    finished: json['finished'] as bool? ?? false,
    si: json['si'] as int? ?? 0,
    spinAtMs: json['spinAtMs'] as int?,
    spinWinner: json['spinWinner'] as int? ?? 0,
    breakEndMs: json['breakEndMs'] as int?,
    rev: json['rev'] as int? ?? 0,
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
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

/// The role and share tokens a page URL fragment selects.
///
/// [role] is one of `admin`, `host`, `viewer` or `standalone`; [tokens] carries
/// the share tokens in route order for the host/viewer roles and is empty for
/// the others.
({String role, List<String> tokens}) parseRoute(String fragment) {
  // A single token is alphanumeric only; anything else falls back to the
  // standalone timer rather than guessing.
  final tokenRe = RegExp(r'^[A-Za-z0-9]+$');

  if (fragment == '/admin') return (role: 'admin', tokens: const []);

  if (fragment.startsWith('/host/')) {
    final segments = fragment.substring('/host/'.length).split('/');
    final tokens = <String>[];
    for (final seg in segments) {
      if (!tokenRe.hasMatch(seg)) return (role: 'standalone', tokens: const []);
      tokens.add(seg);
    }
    return (role: 'host', tokens: tokens);
  }

  if (fragment.startsWith('/view/')) {
    final token = fragment.substring('/view/'.length);
    if (!tokenRe.hasMatch(token)) return (role: 'standalone', tokens: const []);
    return (role: 'viewer', tokens: [token]);
  }

  return (role: 'standalone', tokens: const []);
}
