import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iade_counter/theme.dart';

void main() {
  test('stage colours and calm fallback', () {
    expect(stageColor('setup'), const Color(0xFF1565C0));
    expect(stageColor('talk'), const Color(0xFF2E7D32));
    expect(stageColor('qa'), const Color(0xFF6A1B9A));
    expect(stageColor('pack'), const Color(0xFF455A64));
    expect(stageColor(''), calmColor);
    expect(stageColor('unknown'), calmColor);
    expect(calmColor, const Color(0xFF10151C));
    expect(warnColor, const Color(0xFFB36B00));
  });

  test('app theme is dark', () {
    expect(appTheme().brightness, Brightness.dark);
  });
}
