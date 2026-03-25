import 'package:flutter/material.dart';

import '../../ui/foundation/app_elevation.dart';
import '../../ui/foundation/app_font_tokens.dart';
import '../../ui/foundation/app_radius.dart';
import '../../ui/foundation/app_spacing.dart';
import '../../ui/foundation/app_theme_extensions.dart';
import '../../ui/foundation/app_type_scale.dart';
import '../../ui/foundation/field_theme_extensions.dart';

// =============================================================================
// AppTheme — entry point untuk MaterialApp
//
// Dua tema resmi:
//   • AppTheme.darkTheme  → FieldThemeTokens.dark  (gelap, default promotor)
//   • AppTheme.lightTheme → FieldThemeTokens.light (terang, warm cream)
//
// Keduanya menggunakan warna accent yang sama (gold C9923A).
// =============================================================================
class AppTheme {
  // ─── Legacy compatibility layer (untuk admin pages, belum direfactor) ───────
  static const Color primaryBlue    = Color(0xFF0F7B6C);
  static const Color accentBlue     = Color(0xFF0B5E53);
  static const Color successGreen   = Color(0xFF2E7D32);
  static const Color warningYellow  = Color(0xFFF59E0B);
  static const Color errorRed       = Color(0xFFDC2626);
  static const Color goldOrange     = Color(0xFFF97316);
  static const Color backgroundLight= Color(0xFFF5F6F8);
  static const Color textPrimary    = Color(0xFF111827);
  static const Color textSecondary  = Color(0xFF4B5563);
  // ─── Dark Theme ─────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    const t = FieldThemeTokens.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: t.primaryAccent,
        secondary: t.primaryAccentLight,
        surface: t.surface1,
        onSurface: t.textPrimary,
        error: t.danger,
      ),
      scaffoldBackgroundColor: t.background,
      textTheme: _textTheme(t.textPrimary, t.textSecondary),
      extensions: const [AppThemeTokens.dark, FieldThemeTokens.dark],
      appBarTheme: AppBarTheme(
        backgroundColor: t.surface1,
        foregroundColor: t.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppFontTokens.resolve(
          AppFontRole.primary,
          fontSize: AppTypeScale.title,
          fontWeight: FontWeight.w700,
          color: t.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: t.surface1,
        elevation: AppElevation.low,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgBorder),
      ),
      dividerTheme: DividerThemeData(
        color: t.divider,
        thickness: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primaryAccent,
          foregroundColor: t.textOnAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          textStyle: AppFontTokens.resolve(
            AppFontRole.primary,
            fontSize: AppTypeScale.bodyStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.surface3),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(color: t.surface3),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(color: t.surface3),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(color: t.primaryAccent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(color: t.danger),
        ),
        hintStyle: AppFontTokens.resolve(
          AppFontRole.primary,
          fontSize: AppTypeScale.support,
          color: t.textMuted,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: t.bottomBarBackground,
        selectedItemColor: t.primaryAccent,
        unselectedItemColor: t.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.primaryAccent,
        foregroundColor: t.textOnAccent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.primaryAccent,
      ),
    );
  }

  // ─── Light Theme ─────────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    const t = FieldThemeTokens.light;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: t.primaryAccent,
        secondary: t.primaryAccentLight,
        surface: t.surface1,
        onSurface: t.textPrimary,
        error: t.danger,
      ),
      scaffoldBackgroundColor: t.background,
      textTheme: _textTheme(t.textPrimary, t.textSecondary),
      extensions: const [AppThemeTokens.light, FieldThemeTokens.light],
      appBarTheme: AppBarTheme(
        backgroundColor: t.surface1,
        foregroundColor: t.textPrimary,
        elevation: 0,
        centerTitle: false,
        shadowColor: const Color(0x14000000),
        titleTextStyle: AppFontTokens.resolve(
          AppFontRole.primary,
          fontSize: AppTypeScale.title,
          fontWeight: FontWeight.w700,
          color: t.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: t.surface1,
        elevation: AppElevation.low,
        shadowColor: const Color(0x14000000),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgBorder),
      ),
      dividerTheme: DividerThemeData(
        color: t.divider,
        thickness: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: t.primaryAccent,
          foregroundColor: t.textOnAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
          textStyle: AppFontTokens.resolve(
            AppFontRole.primary,
            fontSize: AppTypeScale.bodyStrong,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.surface3),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdBorder),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surface2,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.md,
        ),
        border: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(color: t.surface3),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(color: t.surface3),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(color: t.primaryAccent, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.mdBorder,
          borderSide: BorderSide(color: t.danger),
        ),
        hintStyle: AppFontTokens.resolve(
          AppFontRole.primary,
          fontSize: AppTypeScale.support,
          color: t.textMuted,
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: t.bottomBarBackground,
        selectedItemColor: t.primaryAccent,
        unselectedItemColor: t.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 8,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.primaryAccent,
        foregroundColor: t.textOnAccent,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.primaryAccent,
      ),
    );
  }

  // ─── Shared text theme helper ────────────────────────────────────────────────
  static TextTheme _textTheme(Color primary, Color secondary) {
    return AppFontTokens.primaryTextTheme().copyWith(
      headlineSmall: AppFontTokens.resolve(
        AppFontRole.display,
        fontSize: AppTypeScale.heading,
        fontWeight: FontWeight.w800,
        color: primary,
        height: 1.2,
      ),
      titleLarge: AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.title,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      titleMedium: AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.bodyStrong,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
      bodyLarge: AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.bodyStrong,
        fontWeight: FontWeight.w500,
        color: primary,
      ),
      bodyMedium: AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.body,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodySmall: AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.support,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      labelLarge: AppFontTokens.resolve(
        AppFontRole.primary,
        fontSize: AppTypeScale.bodyStrong,
        fontWeight: FontWeight.w700,
        color: primary,
      ),
    );
  }

  // ─── Semantic achievement color (dipakai di banyak tempat) ──────────────────
  static Color achievementColor(double pct, {bool isDark = true}) {
    final t = isDark ? FieldThemeTokens.dark : FieldThemeTokens.light;
    if (pct >= 1.0) return t.success;
    if (pct >= 0.85) return t.primaryAccent;
    if (pct >= 0.6) return t.warning;
    return t.danger;
  }
}
