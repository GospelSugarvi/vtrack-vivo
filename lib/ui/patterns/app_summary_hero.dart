import 'package:flutter/material.dart';

import '../components/app_card.dart';
import '../foundation/app_spacing.dart';
import '../foundation/app_theme_extensions.dart';

class AppSummaryHero extends StatelessWidget {
  const AppSummaryHero({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.metrics,
  });

  final String eyebrow;
  final String title;
  final String description;
  final List<Widget> metrics;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      tone: AppCardTone.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            eyebrow,
            style: context.textTheme.labelLarge?.copyWith(
              color: context.appTokens.primary,
            ),
          ),
          const SizedBox(height: AppSpace.sm),
          Text(
            title,
            style: context.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Text(description, style: context.textTheme.bodyMedium),
          const SizedBox(height: AppSpace.md),
          Wrap(
            spacing: AppSpace.sm,
            runSpacing: AppSpace.sm,
            children: metrics,
          ),
        ],
      ),
    );
  }
}
