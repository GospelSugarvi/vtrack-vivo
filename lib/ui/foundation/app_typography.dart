import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_font_tokens.dart';
import 'app_type_scale.dart';

final class AppTypography {
  static TextTheme lightTextTheme() {
    return AppFontTokens.altSansTextTheme().copyWith(
      headlineSmall: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.heading,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
      titleLarge: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.title,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      titleMedium: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.bodyStrong,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      bodyLarge: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.bodyStrong,
        height: 1.45,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      bodyMedium: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.body,
        height: 1.45,
        fontWeight: FontWeight.w500,
        color: AppColors.textPrimary,
      ),
      bodySmall: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.support,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
      ),
      labelLarge: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.bodyStrong,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
      ),
      labelMedium: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.support,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.textSecondary,
      ),
    );
  }

  static TextTheme darkTextTheme(TextTheme base) {
    return AppFontTokens.altSansTextTheme(base).copyWith(
      headlineSmall: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.heading,
        height: 1.2,
        fontWeight: FontWeight.w800,
        color: AppColors.darkTextPrimary,
      ),
      titleLarge: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.title,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: AppColors.darkTextPrimary,
      ),
      titleMedium: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.bodyStrong,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: AppColors.darkTextPrimary,
      ),
      bodyLarge: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.bodyStrong,
        height: 1.45,
        fontWeight: FontWeight.w500,
        color: AppColors.darkTextPrimary,
      ),
      bodyMedium: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.body,
        height: 1.45,
        fontWeight: FontWeight.w500,
        color: AppColors.darkTextPrimary,
      ),
      bodySmall: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.support,
        height: 1.4,
        fontWeight: FontWeight.w500,
        color: AppColors.darkTextSecondary,
      ),
      labelLarge: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.bodyStrong,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.darkTextPrimary,
      ),
      labelMedium: AppFontTokens.resolve(
        AppFontRole.altSans,
        fontSize: AppTypeScale.support,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.darkTextSecondary,
      ),
    );
  }

  const AppTypography._();
}
