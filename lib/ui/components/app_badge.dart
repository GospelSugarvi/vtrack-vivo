import 'package:flutter/material.dart';

import '../foundation/app_radius.dart';
import '../foundation/app_spacing.dart';
import '../foundation/app_theme_extensions.dart';

enum AppBadgeVariant { primary, secondary, success, warning, danger }

class AppBadge extends StatelessWidget {
  const AppBadge({
    super.key,
    required this.label,
    this.variant = AppBadgeVariant.secondary,
  });

  final String label;
  final AppBadgeVariant variant;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final color = switch (variant) {
      AppBadgeVariant.primary => tokens.primary,
      AppBadgeVariant.success => tokens.success,
      AppBadgeVariant.warning => tokens.warning,
      AppBadgeVariant.danger => tokens.danger,
      AppBadgeVariant.secondary => tokens.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpace.sm,
        vertical: AppSpace.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.pillBorder,
      ),
      child: Text(
        label,
        style: context.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
