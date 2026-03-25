import 'package:flutter/material.dart';

import '../foundation/app_radius.dart';
import '../foundation/app_spacing.dart';
import '../foundation/app_theme_extensions.dart';

enum AppInfoBannerVariant { info, success, warning, danger }

class AppInfoBanner extends StatelessWidget {
  const AppInfoBanner({
    super.key,
    required this.title,
    required this.message,
    this.variant = AppInfoBannerVariant.info,
  });

  final String title;
  final String message;
  final AppInfoBannerVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final (icon, surface, color) = switch (variant) {
      AppInfoBannerVariant.success => (
        Icons.check_circle_outline,
        tokens.successSurface,
        tokens.success,
      ),
      AppInfoBannerVariant.warning => (
        Icons.warning_amber_rounded,
        tokens.warningSurface,
        tokens.warning,
      ),
      AppInfoBannerVariant.danger => (
        Icons.error_outline,
        tokens.dangerSurface,
        tokens.danger,
      ),
      AppInfoBannerVariant.info => (
        Icons.info_outline,
        tokens.infoSurface,
        tokens.info,
      ),
    };

    return Container(
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: AppRadius.lgBorder,
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: context.appTokens.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(message, style: context.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
