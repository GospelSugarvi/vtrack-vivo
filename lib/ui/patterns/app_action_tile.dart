import 'package:flutter/material.dart';

import '../foundation/app_elevation.dart';
import '../foundation/app_radius.dart';
import '../foundation/app_spacing.dart';
import '../foundation/app_theme_extensions.dart';

class AppActionTile extends StatelessWidget {
  const AppActionTile({
    super.key,
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    return Material(
      color: tokens.background.withValues(alpha: 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.xlBorder,
        child: Container(
          padding: const EdgeInsets.all(AppSpace.md),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: AppRadius.xlBorder,
            border: Border.all(color: tokens.border),
            boxShadow: AppElevation.soft(tokens.textPrimary),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpace.md),
                decoration: BoxDecoration(
                  color: tokens.primary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: tokens.primary, size: 24),
              ),
              const SizedBox(height: AppSpace.md),
              Text(
                label,
                textAlign: TextAlign.center,
                style: context.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpace.xs),
              Text(
                description,
                textAlign: TextAlign.center,
                style: context.textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
