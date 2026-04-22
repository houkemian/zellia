import 'package:flutter/material.dart';

/// PRD: body ≥ 18pt, titles ≥ 24pt, high contrast, large tap targets.
ThemeData buildZelliaTheme() {
  const base = TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w600),
    headlineLarge: TextStyle(fontSize: 28, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 20, height: 1.35),
    bodyMedium: TextStyle(fontSize: 18, height: 1.35),
    labelLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
  );

  final colorScheme = ColorScheme.fromSeed(
    // Brand green from logo palette.
    seedColor: const Color(0xFF5BCFB0),
    brightness: Brightness.light,
    surface: Colors.white,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    textTheme: base,
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 56),
        textStyle: const TextStyle(fontSize: 18),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      labelStyle: TextStyle(fontSize: 18),
    ),
  );
}
