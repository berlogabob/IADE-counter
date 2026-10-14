import 'package:flutter/material.dart';

const calmColor = Color(0xFF10151C);
const warnColor = Color(0xFFB36B00);

Color stageColor(String stage) => switch (stage) {
  'setup' => const Color(0xFF1565C0),
  'talk' => const Color(0xFF2E7D32),
  'qa' => const Color(0xFF6A1B9A),
  'pack' => const Color(0xFF455A64),
  _ => calmColor,
};

ThemeData appTheme() => ThemeData.dark(useMaterial3: true).copyWith(
  scaffoldBackgroundColor: calmColor,
  filledButtonTheme: const FilledButtonThemeData(
    style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(120, 52))),
  ),
  outlinedButtonTheme: const OutlinedButtonThemeData(
    style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(120, 52))),
  ),
  textButtonTheme: const TextButtonThemeData(
    style: ButtonStyle(minimumSize: WidgetStatePropertyAll(Size(64, 52))),
  ),
);
