import 'package:flutter/material.dart';

import 'app_colors.dart';

@immutable
class AppThemeTokens extends ThemeExtension<AppThemeTokens> {
  const AppThemeTokens({
    required this.primary,
    required this.primaryStrong,
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.successSurface,
    required this.warningSurface,
    required this.dangerSurface,
    required this.infoSurface,
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.textPrimary,
    required this.textSecondary,
    required this.textInverse,
    required this.border,
    required this.borderStrong,
    required this.borderSubtle,
    required this.overlay,
    required this.disabled,
  });

  final Color primary;
  final Color primaryStrong;
  final Color background;
  final Color surface;
  final Color surfaceVariant;
  final Color successSurface;
  final Color warningSurface;
  final Color dangerSurface;
  final Color infoSurface;
  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color textPrimary;
  final Color textSecondary;
  final Color textInverse;
  final Color border;
  final Color borderStrong;
  final Color borderSubtle;
  final Color overlay;
  final Color disabled;

  static const light = AppThemeTokens(
    primary: AppColors.primary,
    primaryStrong: AppColors.primaryStrong,
    background: AppColors.background,
    surface: AppColors.surface,
    surfaceVariant: AppColors.surfaceVariant,
    successSurface: AppColors.successSurface,
    warningSurface: AppColors.warningSurface,
    dangerSurface: AppColors.dangerSurface,
    infoSurface: AppColors.infoSurface,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
    info: AppColors.info,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textInverse: AppColors.textInverse,
    border: AppColors.border,
    borderStrong: AppColors.borderStrong,
    borderSubtle: AppColors.borderSubtle,
    overlay: AppColors.overlay,
    disabled: AppColors.disabled,
  );

  static const dark = AppThemeTokens(
    primary: AppColors.primary,
    primaryStrong: AppColors.primaryStrong,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceVariant: AppColors.darkSurfaceVariant,
    successSurface: AppColors.successSurface,
    warningSurface: AppColors.warningSurface,
    dangerSurface: AppColors.dangerSurface,
    infoSurface: AppColors.infoSurface,
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
    info: AppColors.info,
    textPrimary: AppColors.darkTextPrimary,
    textSecondary: AppColors.darkTextSecondary,
    textInverse: AppColors.textInverse,
    border: AppColors.darkBorder,
    borderStrong: AppColors.darkBorder,
    borderSubtle: AppColors.darkSurfaceVariant,
    overlay: AppColors.overlay,
    disabled: AppColors.disabled,
  );

  @override
  AppThemeTokens copyWith({
    Color? primary,
    Color? primaryStrong,
    Color? background,
    Color? surface,
    Color? surfaceVariant,
    Color? successSurface,
    Color? warningSurface,
    Color? dangerSurface,
    Color? infoSurface,
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? textPrimary,
    Color? textSecondary,
    Color? textInverse,
    Color? border,
    Color? borderStrong,
    Color? borderSubtle,
    Color? overlay,
    Color? disabled,
  }) {
    return AppThemeTokens(
      primary: primary ?? this.primary,
      primaryStrong: primaryStrong ?? this.primaryStrong,
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceVariant: surfaceVariant ?? this.surfaceVariant,
      successSurface: successSurface ?? this.successSurface,
      warningSurface: warningSurface ?? this.warningSurface,
      dangerSurface: dangerSurface ?? this.dangerSurface,
      infoSurface: infoSurface ?? this.infoSurface,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textInverse: textInverse ?? this.textInverse,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      overlay: overlay ?? this.overlay,
      disabled: disabled ?? this.disabled,
    );
  }

  @override
  ThemeExtension<AppThemeTokens> lerp(
    covariant ThemeExtension<AppThemeTokens>? other,
    double t,
  ) {
    if (other is! AppThemeTokens) return this;
    return AppThemeTokens(
      primary: Color.lerp(primary, other.primary, t) ?? primary,
      primaryStrong: Color.lerp(primaryStrong, other.primaryStrong, t) ?? primaryStrong,
      background: Color.lerp(background, other.background, t) ?? background,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceVariant:
          Color.lerp(surfaceVariant, other.surfaceVariant, t) ?? surfaceVariant,
      successSurface:
          Color.lerp(successSurface, other.successSurface, t) ?? successSurface,
      warningSurface:
          Color.lerp(warningSurface, other.warningSurface, t) ?? warningSurface,
      dangerSurface:
          Color.lerp(dangerSurface, other.dangerSurface, t) ?? dangerSurface,
      infoSurface: Color.lerp(infoSurface, other.infoSurface, t) ?? infoSurface,
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      info: Color.lerp(info, other.info, t) ?? info,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t) ?? textPrimary,
      textSecondary:
          Color.lerp(textSecondary, other.textSecondary, t) ?? textSecondary,
      textInverse: Color.lerp(textInverse, other.textInverse, t) ?? textInverse,
      border: Color.lerp(border, other.border, t) ?? border,
      borderStrong:
          Color.lerp(borderStrong, other.borderStrong, t) ?? borderStrong,
      borderSubtle:
          Color.lerp(borderSubtle, other.borderSubtle, t) ?? borderSubtle,
      overlay: Color.lerp(overlay, other.overlay, t) ?? overlay,
      disabled: Color.lerp(disabled, other.disabled, t) ?? disabled,
    );
  }
}

extension AppThemeContext on BuildContext {
  AppThemeTokens get appTokens =>
      Theme.of(this).extension<AppThemeTokens>() ?? AppThemeTokens.light;

  TextTheme get textTheme => Theme.of(this).textTheme;
}
