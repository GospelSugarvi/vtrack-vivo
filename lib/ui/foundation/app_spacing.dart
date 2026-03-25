import 'package:flutter/widgets.dart';

final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 40;

  static const EdgeInsets page = EdgeInsets.all(md);
  static const EdgeInsets card = EdgeInsets.all(md);
  static const EdgeInsets section = EdgeInsets.symmetric(
    horizontal: md,
    vertical: lg,
  );

  const AppSpace._();
}
