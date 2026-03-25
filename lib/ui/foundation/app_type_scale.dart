final class AppTypeScale {
  // Secondary / metadata only
  static const double micro = 8;
  static const double caption = 10;
  static const double support = 12;

  // Primary UI copy
  static const double body = 14;
  static const double bodyStrong = 16;

  // Structural hierarchy
  static const double title = 18;
  static const double heading = 24;
  static const double hero = 32;

  // Compatibility aliases
  static const double label = support;
  static const double bodySm = support;
  static const double bodyMd = body;
  static const double bodyLg = bodyStrong;
  static const double titleSm = title;
  static const double titleMd = title;
  static const double headingSm = title;
  static const double headingMd = heading;
  static const double headingLg = heading;
  static const double numberSm = bodyStrong;
  static const double heroNum = hero;

  const AppTypeScale._();
}
