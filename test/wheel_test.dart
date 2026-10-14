import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:iade_counter/wheel.dart';

void main() {
  // At t == 1 the wheel has turned full turns minus (winner + 0.5)*s, so the
  // winner's slice centre lands under the top pointer: the leftover, modulo a
  // full turn, is zero.
  test('wheelAngle: winner lands under the pointer at t == 1', () {
    for (final n in [2, 5, 7]) {
      final s = (2 * pi) / n;
      for (var w = 0; w < n; w++) {
        final r = ((w + 0.5) * s + wheelAngle(n, w, 1)) % (2 * pi);
        expect(r, closeTo(0, 1e-9), reason: 'n=$n w=$w -> $r');
      }
    }
  });

  test('wheelAngle: starts at zero', () {
    for (final n in [2, 5, 7]) {
      for (var w = 0; w < n; w++) {
        expect(wheelAngle(n, w, 0), 0.0, reason: 'n=$n w=$w');
      }
    }
  });

  test('wheelAngle: t is clamped outside 0..1', () {
    for (final n in [2, 5, 7]) {
      for (var w = 0; w < n; w++) {
        expect(wheelAngle(n, w, -1), wheelAngle(n, w, 0));
        expect(wheelAngle(n, w, 2), wheelAngle(n, w, 1));
      }
    }
  });

  test('repaintInterval: 50 ms while active, 250 ms at rest', () {
    expect(
      repaintInterval(wheelActive: true),
      const Duration(milliseconds: 50),
    );
    expect(
      repaintInterval(wheelActive: false),
      const Duration(milliseconds: 250),
    );
  });

  test('wheelAngle: monotonic and within one full turn', () {
    for (final n in [2, 5, 7]) {
      var prev = 0.0;
      for (var i = 0; i <= 20; i++) {
        final a = wheelAngle(n, 0, i / 20);
        expect(a >= prev, true, reason: 'n=$n');
        expect(a <= 2 * pi * 6 + 1e-9, true, reason: 'n=$n');
        prev = a;
      }
    }
  });
}
