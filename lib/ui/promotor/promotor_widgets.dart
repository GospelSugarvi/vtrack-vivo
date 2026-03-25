import 'package:flutter/material.dart';

import '../foundation/app_text_style.dart';
import '../foundation/field_theme_extensions.dart';

// =============================================================================
// Shared widgets — pakai context.fieldTokens agar theme-aware
// =============================================================================

class PromotorCard extends StatelessWidget {
  const PromotorCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: t.lgRadius,
        border: Border.all(color: t.surface3),
        boxShadow: [
          // Shadow utama — lebih dramatis di light, subtil di dark
          BoxShadow(
            color: isDark
                ? t.shellBackground.withValues(alpha: 0.55)
                : const Color(0xFF000000).withValues(alpha: 0.06),
            blurRadius: isDark ? 24 : 18,
            offset: const Offset(0, 8),
          ),
          // Shadow pendek untuk kesan "lifted"
          BoxShadow(
            color: isDark
                ? t.shellBackground.withValues(alpha: 0.25)
                : const Color(0xFF000000).withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: t.lgRadius,
        child: Stack(
          children: [
            // Glow line di atas card — lebih tebal & vivid
            Positioned(
              top: 0,
              left: 14,
              right: 14,
              child: Container(
                height: isDark ? 1.5 : 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      t.background.withValues(alpha: 0),
                      isDark
                          ? t.primaryAccentGlow
                          : t.primaryAccent.withValues(alpha: 0.65),
                      t.background.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

class PromotorSectionLabel extends StatelessWidget {
  const PromotorSectionLabel(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Dot accent kecil + glow mikro
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: t.primaryAccent,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: t.primaryAccentGlow,
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        // Garis pendek accent
        Container(width: 10, height: 1.5, color: t.primaryAccent),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: AppTextStyle.label(
            t.primaryAccent,
            weight: FontWeight.w800,
            letterSpacing: 1.5,
          ),
        ),
      ],
    );
  }
}

class PromotorProgressBar extends StatelessWidget {
  const PromotorProgressBar({
    super.key,
    required this.value,
    this.height = 8,
    this.useGreen = false,
    this.useAmber = false,
  });

  final double value;
  final double height;
  final bool useGreen;
  final bool useAmber;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final clamped = value.clamp(0.0, 1.0);

    final LinearGradient gradient;
    if (useGreen) {
      gradient = LinearGradient(
        colors: [t.success.withValues(alpha: 0.7), t.success],
      );
    } else if (useAmber) {
      gradient = LinearGradient(
        colors: [t.warning.withValues(alpha: 0.7), t.warning],
      );
    } else {
      gradient = LinearGradient(
        colors: [t.primaryAccent, t.primaryAccentLight],
      );
    }

    final activeColor = useGreen
        ? t.success
        : useAmber
        ? t.warning
        : t.primaryAccent;

    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: t.surface3,
            borderRadius: t.pillRadius,
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Container(
              width: constraints.maxWidth * clamped,
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: t.pillRadius,
                boxShadow: clamped > 0.05
                    ? [
                        BoxShadow(
                          color: activeColor.withValues(alpha: 0.35),
                          blurRadius: 8,
                          offset: Offset.zero,
                        ),
                      ]
                    : null,
              ),
            ),
          ),
        );
      },
    );
  }
}

class PromotorPill extends StatelessWidget {
  const PromotorPill({
    super.key,
    required this.label,
    required this.subLabel,
    this.dotColor,
  });

  final String label;
  final String subLabel;
  final Color? dotColor;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final dot = dotColor ?? t.success;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: t.pillRadius,
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: dot,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: dot.withValues(alpha: 0.6), blurRadius: 6),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: AppTextStyle.label(t.textPrimary, weight: FontWeight.w800),
          ),
          const SizedBox(width: 6),
          Text(
            subLabel,
            style: AppTextStyle.label(t.textMuted, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
