import 'package:flutter/material.dart';

import '../foundation/app_radius.dart';
import '../foundation/app_spacing.dart';
import '../foundation/app_theme_extensions.dart';

class AppListItem extends StatelessWidget {
  const AppListItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.isSelected = false,
    this.isCompact = false,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isSelected;
  final bool isCompact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;
    final content = Container(
      padding: EdgeInsets.all(isCompact ? AppSpace.sm : AppSpace.md),
      decoration: BoxDecoration(
        color: isSelected
            ? tokens.primary.withValues(alpha: 0.08)
            : tokens.surface,
        borderRadius: AppRadius.mdBorder,
        border: Border.all(
          color: isSelected
              ? tokens.primary.withValues(alpha: 0.28)
              : tokens.border,
        ),
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpace.md),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: context.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSelected ? tokens.primary : null,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpace.xs),
                  Text(subtitle!, style: context.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpace.md),
            trailing!,
          ],
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdBorder,
      child: content,
    );
  }
}
