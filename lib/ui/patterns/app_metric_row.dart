import 'package:flutter/material.dart';

import '../foundation/app_radius.dart';
import '../foundation/app_spacing.dart';
import '../foundation/app_theme_extensions.dart';

class AppMetricRow extends StatelessWidget {
  const AppMetricRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpace.sm),
      decoration: BoxDecoration(
        color: context.appTokens.surface,
        borderRadius: AppRadius.mdBorder,
        border: Border.all(color: context.appTokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: context.textTheme.labelMedium?.copyWith(
              color: context.appTokens.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(
            value,
            style: context.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
