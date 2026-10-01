enum Phase { running, warning, done }

Phase phaseFor(Duration remaining, Duration warn) {
  if (remaining <= Duration.zero) return Phase.done;
  if (remaining <= warn) return Phase.warning;
  return Phase.running;
}

/// One session-log entry, e.g. `#3  talk 16:12 (+01:12)  Q&A 08:40`.
String logLine(int n, Duration talk, Duration limit, Duration qa) {
  final over = talk > limit ? ' (+${formatRemaining(talk - limit)})' : '';
  final qaPart = qa > Duration.zero ? '  Q&A ${formatRemaining(qa)}' : '';
  return '#$n  talk ${formatRemaining(talk)}$over$qaPart';
}

/// `MM:SS` while counting down, `+MM:SS` in overtime.
String formatRemaining(Duration remaining) {
  final over = remaining < Duration.zero;
  // Round up while counting down so the display hits 00:00 exactly at the end.
  final s = over
      ? -remaining.inSeconds
      : (remaining.inMilliseconds / 1000).ceil();
  final mm = (s ~/ 60).toString().padLeft(2, '0');
  final ss = (s % 60).toString().padLeft(2, '0');
  return '${over ? '+' : ''}$mm:$ss';
}
