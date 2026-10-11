import 'package:flutter/material.dart';

/// Centralized Material 3 dark theme for ShiftR.
ThemeData buildShiftRTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    colorScheme: const ColorScheme.dark(
      primary: Colors.blueAccent,
      surface: Colors.black,
    ),
    scaffoldBackgroundColor: Colors.black,
    cardTheme: CardThemeData(
      color: Colors.grey[900],
      margin: const EdgeInsets.only(bottom: 12),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
    ),
  );
}
