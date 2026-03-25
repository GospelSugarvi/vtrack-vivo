import 'package:flutter/material.dart';

import '../foundation/app_radius.dart';
import '../foundation/app_spacing.dart';
import '../foundation/app_theme_extensions.dart';

enum AppButtonVariant { primary, secondary, danger }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
    this.variant = AppButtonVariant.primary,
    this.isExpanded = false,
    this.isLoading = false,
    this.isEnabled = true,
  });

  final String label;
  final VoidCallback? onPressed;
  final Widget? icon;
  final AppButtonVariant variant;
  final bool isExpanded;
  final bool isLoading;
  final bool isEnabled;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final enabled = isEnabled && !isLoading && onPressed != null;
    final foreground = switch (variant) {
      AppButtonVariant.primary => tokens.textInverse,
      AppButtonVariant.secondary => tokens.textPrimary,
      AppButtonVariant.danger => tokens.textInverse,
    };
    final background = switch (variant) {
      AppButtonVariant.primary => tokens.primary,
      AppButtonVariant.secondary => tokens.surface,
      AppButtonVariant.danger => tokens.danger,
    };
    final border = switch (variant) {
      AppButtonVariant.secondary => tokens.border,
      _ => background,
    };
    final resolvedBackground = enabled ? background : tokens.disabled;
    final resolvedForeground = enabled
        ? foreground
        : tokens.textSecondary.withValues(alpha: 0.9);

    final child = isLoading
        ? SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(resolvedForeground),
            ),
          )
        : icon == null
        ? Text(label)
        : Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              icon!,
              const SizedBox(width: AppSpace.sm),
              Text(label),
            ],
          );

    return SizedBox(
      width: isExpanded ? double.infinity : null,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpace.lg,
            vertical: AppSpace.md,
          ),
          backgroundColor: resolvedBackground,
          foregroundColor: resolvedForeground,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.mdBorder,
            side: BorderSide(color: enabled ? border : tokens.borderSubtle),
          ),
        ),
        child: child,
      ),
    );
  }
}
