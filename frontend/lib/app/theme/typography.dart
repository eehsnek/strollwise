import 'package:flutter/material.dart';

TextTheme buildTypography() {
  return const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 30,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.8,
    ),
    headlineMedium: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w800,
      letterSpacing: -0.4,
    ),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
    bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
  );
}
