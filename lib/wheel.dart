import 'dart:math';

import 'package:flutter/material.dart';

/// How long the wheel spins before it stops.
const Duration spinMs = Duration(seconds: 5);

/// How long the winning slice stays under the pointer after it stops.
const Duration holdMs = Duration(seconds: 3);

/// The angle the wheel has rotated through for a fraction [t] of the spin.
///
/// [t] is clamped to 0..1. The wheel turns clockwise, easing from a fast
/// start to a slow stop, so that at t == 1 the winner's slice centre sits
/// exactly under the fixed top pointer.
double wheelAngle(int n, int winner, double t) {
  final s = (2 * pi) / n;
  // Full turns plus the winner's centre reversed into place.
  final r = (2 * pi * 6) - (winner + 0.5) * s;
  final x = t.clamp(0.0, 1.0);
  // easeOutCubic.
  return r * (1 - pow(1 - x, 3));
}

/// Draws [n] equal slices (group names in [labels]) with a fixed pointer at
/// the top, rotated by [angle] clockwise radians from the start position.
class WheelPainter extends CustomPainter {
  WheelPainter({
    required this.labels,
    required this.angle,
    required this.colourA,
    required this.colourB,
  });

  /// One label per slice, in slice order.
  final List<String> labels;

  /// Clockwise radians the wheel has turned from the top-start position.
  final double angle;

  final Color colourA;
  final Color colourB;

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n == 0) return;
    final s = (2 * pi) / n;
    final centre = Offset(size.width / 2, size.height / 2);
    final radius = (min(size.width, size.height) / 2) - 4;

    final paint = Paint()..style = PaintingStyle.fill;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..color = Colors.white
      ..strokeWidth = 2;

    for (var i = 0; i < n; i++) {
      final start = -pi / 2 + angle + i * s;
      paint.color = i.isEven ? colourA : colourB;
      canvas
        ..drawArc(
          Rect.fromCircle(center: centre, radius: radius),
          start,
          s,
          true,
          paint,
        )
        ..drawArc(
          Rect.fromCircle(center: centre, radius: radius),
          start,
          s,
          true,
          border,
        );
    }

    // Slice labels, drawn radially and centred in their slice.
    for (var i = 0; i < n; i++) {
      final mid = -pi / 2 + angle + (i + 0.5) * s;
      final text = labels[i];
      var fontSize = 60.0;
      TextPainter tp;
      // Shrink the font until it fits inside the slice arc.
      do {
        tp = TextPainter(
          text: TextSpan(
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: fontSize,
            ),
            text: text,
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        fontSize -= 2;
      } while (tp.width > s * radius * 0.9 && fontSize > 8);
      final textRadius = radius * 0.72;
      final offset = Offset(
        centre.dx + textRadius * cos(mid),
        centre.dy + textRadius * sin(mid),
      );
      tp.paint(
        canvas,
        Offset(offset.dx - tp.width / 2, offset.dy - tp.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(CustomPainter old) =>
      old is WheelPainter && (old.angle != angle || old.labels != labels);
}
