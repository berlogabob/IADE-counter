import 'package:flutter_test/flutter_test.dart';
import 'package:iade_counter/phase.dart';

void main() {
  const warn = Duration(minutes: 1);

  test('phase boundaries', () {
    expect(phaseFor(const Duration(seconds: 61), warn), Phase.running);
    expect(phaseFor(warn, warn), Phase.warning);
    expect(phaseFor(const Duration(milliseconds: 1), warn), Phase.warning);
    expect(phaseFor(Duration.zero, warn), Phase.done);
    expect(phaseFor(const Duration(seconds: -5), warn), Phase.done);
  });

  test('log line', () {
    const limit = Duration(minutes: 15);
    expect(
      logLine(1, const Duration(minutes: 14, seconds: 5), limit, Duration.zero),
      '#1  talk 14:05',
    );
    expect(
      logLine(
        3,
        const Duration(minutes: 16, seconds: 12),
        limit,
        const Duration(minutes: 8, seconds: 40),
      ),
      '#3  talk 16:12 (+01:12)  Q&A 08:40',
    );
  });

  test('format', () {
    expect(formatRemaining(const Duration(minutes: 15)), '15:00');
    expect(formatRemaining(const Duration(milliseconds: 59001)), '01:00');
    expect(formatRemaining(Duration.zero), '00:00');
    expect(formatRemaining(const Duration(seconds: -83)), '+01:23');
  });
}
