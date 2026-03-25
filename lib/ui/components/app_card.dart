import 'package:flutter/material.dart';

import '../foundation/app_elevation.dart';
import '../foundation/app_radius.dart';
import '../foundation/app_spacing.dart';
import '../foundation/app_theme_extensions.dart';

enum AppCardTone { defaultTone, primary, success, warning, danger }

class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.onTap,
    this.tone = AppCardTone.defaultTone,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final VoidCallback? onTap;
  final AppCardTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = context.appTokens;

    final content = Container(
      margin: margin,
      padding: padding ?? AppSpace.card,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.lgBorder,
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: AppElevation.soft(tokens.textPrimary),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lgBorder,
      child: content,
    );
  }
}
