import 'package:flutter/material.dart';

final _baseColorScheme = ColorScheme.fromSeed(seedColor: const Color(0xFF6750A4));

ThemeData buildTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  final scheme = isDark
      ? _baseColorScheme.copyWith(brightness: Brightness.dark)
      : _baseColorScheme.copyWith(brightness: Brightness.light);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    brightness: scheme.brightness,
    snackBarTheme: SnackBarThemeData(
      backgroundColor: scheme.primary,
      contentTextStyle: TextStyle(color: scheme.onPrimary),
    ),
  );
}
