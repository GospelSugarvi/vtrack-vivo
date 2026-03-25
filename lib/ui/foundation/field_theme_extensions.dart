import 'package:flutter/material.dart';

// =============================================================================
// FieldThemeTokens — Single source of truth untuk seluruh UI proyek.
//
// Dua varian resmi:
//   • FieldThemeTokens.dark  → tema gelap (default promotor)
//   • FieldThemeTokens.light → tema terang (warm cream/sand)
//
// Cara pakai di widget:
//   final t = context.fieldTokens;
//   color: t.primaryAccent
// =============================================================================

@immutable
class FieldThemeTokens extends ThemeExtension<FieldThemeTokens> {
  const FieldThemeTokens({
    // Backgrounds
    required this.shellBackground,
    required this.background,
    required this.surface1,
    required this.surface2,
    required this.surface3,
    required this.surface4,

    // Accent (Gold / Primary brand color)
    required this.primaryAccent,
    required this.primaryAccentSoft,
    required this.primaryAccentGlow,
    required this.primaryAccentLight,

    // Text
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.textMutedStrong,
    required this.textOnAccent,

    // Semantic colors
    required this.success,
    required this.successSoft,
    required this.warning,
    required this.warningSoft,
    required this.danger,
    required this.dangerSoft,
    required this.info,
    required this.infoSoft,

    // Hero / Card gradient
    required this.heroGradientStart,
    required this.heroGradientEnd,
    required this.heroHighlight,

    // Structural
    required this.bottomBarBackground,
    required this.islandBackground,
    required this.divider,

    // Radius tokens
    required this.radiusSm,
    required this.radiusMd,
    required this.radiusLg,
    required this.radiusXl,
  });

  // ─── Backgrounds ────────────────────────────────────────────────────────────
  final Color shellBackground;
  final Color background;
  final Color surface1;
  final Color surface2;
  final Color surface3;
  final Color surface4;

  // ─── Accent ─────────────────────────────────────────────────────────────────
  final Color primaryAccent;
  final Color primaryAccentSoft;
  final Color primaryAccentGlow;
  final Color primaryAccentLight;

  // ─── Text ───────────────────────────────────────────────────────────────────
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color textMutedStrong;
  final Color textOnAccent;

  // ─── Semantic ───────────────────────────────────────────────────────────────
  final Color success;
  final Color successSoft;
  final Color warning;
  final Color warningSoft;
  final Color danger;
  final Color dangerSoft;
  final Color info;
  final Color infoSoft;

  // ─── Hero Gradient ──────────────────────────────────────────────────────────
  final Color heroGradientStart;
  final Color heroGradientEnd;
  final Color heroHighlight;

  // ─── Structural ─────────────────────────────────────────────────────────────
  final Color bottomBarBackground;
  final Color islandBackground;
  final Color divider;

  // ─── Radius ─────────────────────────────────────────────────────────────────
  final double radiusSm;
  final double radiusMd;
  final double radiusLg;
  final double radiusXl;

  // ─── Convenience getters ────────────────────────────────────────────────────
  BorderRadius get smRadius => BorderRadius.circular(radiusSm);
  BorderRadius get mdRadius => BorderRadius.circular(radiusMd);
  BorderRadius get lgRadius => BorderRadius.circular(radiusLg);
  BorderRadius get xlRadius => BorderRadius.circular(radiusXl);
  BorderRadius get pillRadius => BorderRadius.circular(999);

  // ─── DARK THEME (Promotor standard — warm dark amber) ───────────────────────
  static const dark = FieldThemeTokens(
    // Backgrounds
    shellBackground: Color(0xFF000000),
    background: Color(0xFF1A1510),
    surface1: Color(0xFF211C16),
    surface2: Color(0xFF2A2318),
    surface3: Color(0xFF332B1E),
    surface4: Color(0xFF3D3325),

    // Accent — gold
    primaryAccent: Color(0xFFC9923A),
    primaryAccentSoft: Color(0x1FC9923A),
    primaryAccentGlow: Color(0x47C9923A),
    primaryAccentLight: Color(0xFFE8B06A),

    // Text
    textPrimary: Color(0xFFF4EDE0),
    textSecondary: Color(0xFFD8CFBE),
    textMuted: Color(0xFFA89A86),
    textMutedStrong: Color(0xFF7B6D59),
    textOnAccent: Color(0xFF1A0E00),

    // Semantic
    success: Color(0xFF6AAB7A),
    successSoft: Color(0x1F6AAB7A),
    warning: Color(0xFFD4853A),
    warningSoft: Color(0x1FD4853A),
    danger: Color(0xFFC05A4A),
    dangerSoft: Color(0x1AC05A4A),
    info: Color(0xFF5B8DD9),
    infoSoft: Color(0x1F5B8DD9),

    // Hero
    heroGradientStart: Color(0xFF261F13),
    heroGradientEnd: Color(0xFF1C1610),
    heroHighlight: Color(0x14C9923A),

    // Structural
    bottomBarBackground: Color(0xF714100A),
    islandBackground: Color(0xFF080503),
    divider: Color(0xFF2A2318),

    // Radius
    radiusSm: 10,
    radiusMd: 14,
    radiusLg: 18,
    radiusXl: 50,
  );

  // ─── LIGHT THEME (Warm cream / sand) — Revised for visual depth ────────────
  static const light = FieldThemeTokens(
    // Backgrounds — lebih berjenjang, bukan flat white
    shellBackground: Color(0xFFE8DDD0),   // outer shell lebih gelap dari bg
    background: Color(0xFFF5EFE6),        // warm cream (bukan putih)
    surface1: Color(0xFFFFF9F2),          // warm white — hint golden, bukan #FFF murni
    surface2: Color(0xFFEEE5D5),          // kontras jelas vs surface1
    surface3: Color(0xFFE2D4BE),          // divider & border visible
    surface4: Color(0xFFD6C5A8),          // strong border / separator

    // Accent — gold (sama dengan dark)
    primaryAccent: Color(0xFFB8822E),
    primaryAccentSoft: Color(0x28B8822E), // sedikit lebih opaque agar chip visible
    primaryAccentGlow: Color(0x55B8822E), // glow lebih vivid di light
    primaryAccentLight: Color(0xFFD4A05A),

    // Text — tetap sama, sudah kontras
    textPrimary: Color(0xFF1C1208),
    textSecondary: Color(0xFF3D3020),
    textMuted: Color(0xFF7A6850),
    textMutedStrong: Color(0xFF8A7458),   // lebih gelap dari sebelumnya agar group label kontras
    textOnAccent: Color(0xFFFFFBF5),

    // Semantic — tetap sama
    success: Color(0xFF3A8C52),
    successSoft: Color(0x1A3A8C52),
    warning: Color(0xFFC07030),
    warningSoft: Color(0x1AC07030),
    danger: Color(0xFFA83A2A),
    dangerSoft: Color(0x16A83A2A),
    info: Color(0xFF3A6AB8),
    infoSoft: Color(0x163A6AB8),

    // Hero — gradient lebih visible, glow lebih kuat
    heroGradientStart: Color(0xFFEDE5D5),  // lebih gelap dari bg, gradient terasa
    heroGradientEnd: Color(0xFFE3D8C5),    // kontras vs gradientStart
    heroHighlight: Color(0x35B8822E),      // glow gold lebih visible

    // Structural
    bottomBarBackground: Color(0xF7F5EDE2), // bottom bar punya depth, bukan transparan
    islandBackground: Color(0xFFDDD0B8),   // lebih gelap dari surface4
    divider: Color(0xFFD9CCB5),            // divider nyata, tidak melebur

    // Radius — tetap
    radiusSm: 10,
    radiusMd: 14,
    radiusLg: 18,
    radiusXl: 50,
  );

  // ─── Backwards-compat alias ─────────────────────────────────────────────────
  /// Legacy: pakai [dark] sebelum light theme ada.
  static const standard = dark;

  // ─── copyWith ───────────────────────────────────────────────────────────────
  @override
  FieldThemeTokens copyWith({
    Color? shellBackground,
    Color? background,
    Color? surface1,
    Color? surface2,
    Color? surface3,
    Color? surface4,
    Color? primaryAccent,
    Color? primaryAccentSoft,
    Color? primaryAccentGlow,
    Color? primaryAccentLight,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? textMutedStrong,
    Color? textOnAccent,
    Color? success,
    Color? successSoft,
    Color? warning,
    Color? warningSoft,
    Color? danger,
    Color? dangerSoft,
    Color? info,
    Color? infoSoft,
    Color? heroGradientStart,
    Color? heroGradientEnd,
    Color? heroHighlight,
    Color? bottomBarBackground,
    Color? islandBackground,
    Color? divider,
    double? radiusSm,
    double? radiusMd,
    double? radiusLg,
    double? radiusXl,
  }) {
    return FieldThemeTokens(
      shellBackground: shellBackground ?? this.shellBackground,
      background: background ?? this.background,
      surface1: surface1 ?? this.surface1,
      surface2: surface2 ?? this.surface2,
      surface3: surface3 ?? this.surface3,
      surface4: surface4 ?? this.surface4,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      primaryAccentSoft: primaryAccentSoft ?? this.primaryAccentSoft,
      primaryAccentGlow: primaryAccentGlow ?? this.primaryAccentGlow,
      primaryAccentLight: primaryAccentLight ?? this.primaryAccentLight,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      textMutedStrong: textMutedStrong ?? this.textMutedStrong,
      textOnAccent: textOnAccent ?? this.textOnAccent,
      success: success ?? this.success,
      successSoft: successSoft ?? this.successSoft,
      warning: warning ?? this.warning,
      warningSoft: warningSoft ?? this.warningSoft,
      danger: danger ?? this.danger,
      dangerSoft: dangerSoft ?? this.dangerSoft,
      info: info ?? this.info,
      infoSoft: infoSoft ?? this.infoSoft,
      heroGradientStart: heroGradientStart ?? this.heroGradientStart,
      heroGradientEnd: heroGradientEnd ?? this.heroGradientEnd,
      heroHighlight: heroHighlight ?? this.heroHighlight,
      bottomBarBackground: bottomBarBackground ?? this.bottomBarBackground,
      islandBackground: islandBackground ?? this.islandBackground,
      divider: divider ?? this.divider,
      radiusSm: radiusSm ?? this.radiusSm,
      radiusMd: radiusMd ?? this.radiusMd,
      radiusLg: radiusLg ?? this.radiusLg,
      radiusXl: radiusXl ?? this.radiusXl,
    );
  }

  // ─── lerp ───────────────────────────────────────────────────────────────────
  @override
  ThemeExtension<FieldThemeTokens> lerp(
    covariant ThemeExtension<FieldThemeTokens>? other,
    double t,
  ) {
    if (other is! FieldThemeTokens) return this;
    return FieldThemeTokens(
      shellBackground: Color.lerp(shellBackground, other.shellBackground, t) ?? shellBackground,
      background: Color.lerp(background, other.background, t) ?? background,
      surface1: Color.lerp(surface1, other.surface1, t) ?? surface1,
      surface2: Color.lerp(surface2, other.surface2, t) ?? surface2,
      surface3: Color.lerp(surface3, other.surface3, t) ?? surface3,
      surface4: Color.lerp(surface4, other.surface4, t) ?? surface4,
      primaryAccent: Color.lerp(primaryAccent, other.primaryAccent, t) ?? primaryAccent,
      primaryAccentSoft: Color.lerp(primaryAccentSoft, other.primaryAccentSoft, t) ?? primaryAccentSoft,
      primaryAccentGlow: Color.lerp(primaryAccentGlow, other.primaryAccentGlow, t) ?? primaryAccentGlow,
      primaryAccentLight: Color.lerp(primaryAccentLight, other.primaryAccentLight, t) ?? primaryAccentLight,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textMuted: Color.lerp(textMuted, other.textMuted, t) ?? textMuted,
      textMutedStrong: Color.lerp(textMutedStrong, other.textMutedStrong, t) ?? textMutedStrong,
      textOnAccent: Color.lerp(textOnAccent, other.textOnAccent, t) ?? textOnAccent,
      success: Color.lerp(success, other.success, t) ?? success,
      successSoft: Color.lerp(successSoft, other.successSoft, t) ?? successSoft,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      warningSoft: Color.lerp(warningSoft, other.warningSoft, t) ?? warningSoft,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      dangerSoft: Color.lerp(dangerSoft, other.dangerSoft, t) ?? dangerSoft,
      info: Color.lerp(info, other.info, t) ?? info,
      infoSoft: Color.lerp(infoSoft, other.infoSoft, t) ?? infoSoft,
      heroGradientStart: Color.lerp(heroGradientStart, other.heroGradientStart, t) ?? heroGradientStart,
      heroGradientEnd: Color.lerp(heroGradientEnd, other.heroGradientEnd, t) ?? heroGradientEnd,
      heroHighlight: Color.lerp(heroHighlight, other.heroHighlight, t) ?? heroHighlight,
      bottomBarBackground: Color.lerp(bottomBarBackground, other.bottomBarBackground, t) ?? bottomBarBackground,
      islandBackground: Color.lerp(islandBackground, other.islandBackground, t) ?? islandBackground,
      divider: Color.lerp(divider, other.divider, t) ?? divider,
      radiusSm: radiusSm + (other.radiusSm - radiusSm) * t,
      radiusMd: radiusMd + (other.radiusMd - radiusMd) * t,
      radiusLg: radiusLg + (other.radiusLg - radiusLg) * t,
      radiusXl: radiusXl + (other.radiusXl - radiusXl) * t,
    );
  }
}

// =============================================================================
// BuildContext extension — akses token dari mana saja
// =============================================================================
extension FieldThemeContext on BuildContext {
  FieldThemeTokens get fieldTokens =>
      Theme.of(this).extension<FieldThemeTokens>() ?? FieldThemeTokens.dark;
}
