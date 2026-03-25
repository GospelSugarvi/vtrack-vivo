import 'package:flutter/material.dart';

/// Extension untuk Color yang menggantikan withOpacity deprecated
extension ColorOpacity on Color {
  /// Mengembalikan color dengan opacity tertentu tanpa precision loss
  Color withOpacityValue(double opacity) {
    return Color.fromRGBO(
      (r * 255.0).round().clamp(0, 255),
      (g * 255.0).round().clamp(0, 255),
      (b * 255.0).round().clamp(0, 255),
      opacity,
    );
  }
}
