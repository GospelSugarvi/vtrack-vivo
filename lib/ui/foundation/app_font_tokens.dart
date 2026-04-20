import 'package:flutter/material.dart';

enum AppFontRole {
  primary,
  display,
  altSans,
  accent,
  mono,
}

enum AppFontPreference {
  outfit,
  inter,
  manrope,
  playfair,
  jetbrainsMono,
}

final class AppFontTokens {
  static AppFontPreference _preference = AppFontPreference.outfit;

  static const AppFontRole defaultBody = AppFontRole.primary;
  static const AppFontRole defaultHeading = AppFontRole.display;
  static const AppFontRole defaultMono = AppFontRole.mono;

  static const List<AppFontRole> available = <AppFontRole>[
    AppFontRole.primary,
    AppFontRole.display,
    AppFontRole.altSans,
    AppFontRole.accent,
    AppFontRole.mono,
  ];

  static const List<AppFontPreference> preferences = <AppFontPreference>[
    AppFontPreference.outfit,
    AppFontPreference.inter,
    AppFontPreference.manrope,
    AppFontPreference.playfair,
    AppFontPreference.jetbrainsMono,
  ];

  static AppFontPreference get preference => _preference;

  static void setPreference(AppFontPreference preference) {
    _preference = preference;
  }

  static String nameOf(AppFontRole role) {
    switch (role) {
      case AppFontRole.primary:
        return 'Outfit';
      case AppFontRole.display:
        return 'Playfair Display';
      case AppFontRole.altSans:
        return 'Inter';
      case AppFontRole.accent:
        return 'Manrope';
      case AppFontRole.mono:
        return 'JetBrains Mono';
    }
  }

  static String preferenceNameOf(AppFontPreference preference) {
    switch (preference) {
      case AppFontPreference.outfit:
        return 'Outfit';
      case AppFontPreference.inter:
        return 'Inter';
      case AppFontPreference.manrope:
        return 'Manrope';
      case AppFontPreference.playfair:
        return 'Playfair Display';
      case AppFontPreference.jetbrainsMono:
        return 'JetBrains Mono';
    }
  }

  static String preferenceDescriptionOf(AppFontPreference preference) {
    switch (preference) {
      case AppFontPreference.outfit:
        return 'Default app yang paling seimbang';
      case AppFontPreference.inter:
        return 'Netral dan modern';
      case AppFontPreference.manrope:
        return 'Lebih tegas untuk dashboard';
      case AppFontPreference.playfair:
        return 'Lebih editorial dan dekoratif';
      case AppFontPreference.jetbrainsMono:
        return 'Monospace teknis';
    }
  }

  static TextStyle resolve(
    AppFontRole role, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    if (role == AppFontRole.mono) {
      return _resolvePreference(
        AppFontPreference.jetbrainsMono,
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
      );
    }

    return _resolvePreference(
      _preference,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle preview(
    AppFontPreference preference, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return _resolvePreference(
      preference,
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextStyle _resolvePreference(
    AppFontPreference preference, {
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    return TextStyle(
      fontFamily: _fontFamilyForPreference(preference),
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      height: height,
      letterSpacing: letterSpacing,
    );
  }

  static TextTheme primaryTextTheme([TextTheme? base]) {
    return _resolveTextTheme(_preference, base);
  }

  static TextTheme altSansTextTheme([TextTheme? base]) {
    return _resolveTextTheme(_preference, base);
  }

  static TextTheme _resolveTextTheme(
    AppFontPreference preference, [
    TextTheme? base,
  ]) {
    final seed = base ?? Typography.material2021().black;
    final family = _fontFamilyForPreference(preference);
    return seed.apply(
      fontFamily: family,
      displayColor: seed.bodyMedium?.color,
      bodyColor: seed.bodyMedium?.color,
    );
  }

  static String _fontFamilyForPreference(AppFontPreference preference) {
    switch (preference) {
      case AppFontPreference.outfit:
      case AppFontPreference.inter:
      case AppFontPreference.manrope:
        return 'sans-serif';
      case AppFontPreference.playfair:
        return 'serif';
      case AppFontPreference.jetbrainsMono:
        return 'monospace';
    }
  }

  const AppFontTokens._();
}
