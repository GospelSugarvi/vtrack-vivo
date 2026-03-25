import 'package:flutter/material.dart';

final class AppElevation {
  static const double low = 1;
  static const double medium = 3;
  static const double high = 8;

  static List<BoxShadow> soft(Color baseColor) => [
    BoxShadow(
      color: baseColor.withValues(alpha: 0.08),
      blurRadius: 18,
      offset: const Offset(0, 8),
    ),
  ];

  static List<BoxShadow> mediumShadow(Color baseColor) => [
    BoxShadow(
      color: baseColor.withValues(alpha: 0.1),
      blurRadius: 24,
      offset: const Offset(0, 12),
    ),
  ];

  const AppElevation._();
}
