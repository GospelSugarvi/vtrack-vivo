import 'package:flutter/material.dart';

import '../components/app_badge.dart';
import '../components/app_button.dart';
import '../components/app_section_header.dart';
import '../foundation/app_spacing.dart';

class AppPageHeader extends StatelessWidget {
  const AppPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.badgeLabel,
    this.actionLabel,
    this.onActionTap,
  });

  final String title;
  final String? subtitle;
  final String? badgeLabel;
  final String? actionLabel;
  final VoidCallback? onActionTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppSectionHeader(title: title, subtitle: subtitle),
            ),
            if (badgeLabel != null) ...[
              const SizedBox(width: AppSpace.md),
              AppBadge(label: badgeLabel!),
            ],
          ],
        ),
        if (actionLabel != null && onActionTap != null) ...[
          const SizedBox(height: AppSpace.md),
          AppButton(
            label: actionLabel!,
            onPressed: onActionTap,
            variant: AppButtonVariant.secondary,
          ),
        ],
      ],
    );
  }
}
