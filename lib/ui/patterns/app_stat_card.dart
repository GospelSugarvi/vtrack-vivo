import 'package:flutter/material.dart';

import '../components/app_card.dart';
import '../foundation/app_spacing.dart';
import '../foundation/app_theme_extensions.dart';

class AppStatCard extends StatelessWidget {
  const AppStatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.caption,
    this.tone = AppCardTone.defaultTone,
  });

  final String label;
  final String value;
  final IconData icon;
  final String? caption;
  final AppCardTone tone;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tone: tone,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: context.appTokens.primary),
          const SizedBox(height: AppSpace.md),
          Text(
            value,
            style: context.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(label, style: context.textTheme.bodyMedium),
          if (caption != null) ...[
            const SizedBox(height: AppSpace.sm),
            Text(caption!, style: context.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
