import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../foundation/app_spacing.dart';
import '../foundation/field_theme_extensions.dart';
import '../promotor/promotor_theme.dart';

class AppTargetHeroCard extends StatelessWidget {
  const AppTargetHeroCard({
    super.key,
    required this.title,
    required this.nominal,
    required this.realisasi,
    required this.percentage,
    required this.sisa,
    this.ringLabel = 'Hari ini',
    this.metaLeftText = 'Progress hari ini',
    this.progressColor,
    this.ringColor,
    this.useCompactNominal = true,
    this.bottomContent,
    this.onTap,
  });

  final String title;
  final num nominal;
  final num realisasi;
  final double percentage;
  final num sisa;
  final String ringLabel;
  final String metaLeftText;
  final Color? progressColor;
  final Color? ringColor;
  final bool useCompactNominal;
  final Widget? bottomContent;
  final VoidCallback? onTap;

  String _formatCompactNumber(num value) {
    return NumberFormat.decimalPattern('id_ID').format(value);
  }

  String _formatRupiah(num value) {
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(value);
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final safePercentage = percentage.isNaN ? 0.0 : percentage.clamp(0, 100);
    final pct = safePercentage / 100;
    final resolvedProgressColor = progressColor ?? t.primaryAccent;
    final resolvedRingColor = ringColor ?? resolvedProgressColor;
    final borderColor = resolvedProgressColor.withValues(alpha: 0.22);

    final card = Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.heroGradientStart, t.heroGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: borderColor),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  t.background.withValues(alpha: 0),
                  resolvedProgressColor.withValues(alpha: 0.6),
                  t.background.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: t.primaryAccentSoft,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: t.primaryAccentGlow),
                        ),
                        child: Text(
                          title,
                          style: PromotorText.outfit(
                            size: 11,
                            weight: FontWeight.w800,
                            color: t.primaryAccent,
                            letterSpacing: 0.08,
                          ),
                        ),
                      ),
                      const SizedBox(height: 5),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Rp ',
                              style: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w600,
                                color: t.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: useCompactNominal
                                  ? _formatCompactNumber(nominal)
                                  : NumberFormat.decimalPattern(
                                      'id_ID',
                                    ).format(nominal),
                              style: PromotorText.display(
                                size: useCompactNominal ? 28 : 24,
                                color: t.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            'Pencapaian',
                            style: PromotorText.outfit(
                              size: 13,
                              weight: FontWeight.w700,
                              color: t.textPrimary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _formatRupiah(realisasi),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PromotorText.outfit(
                                size: 15,
                                weight: FontWeight.w700,
                                color: t.success,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 62,
                        height: 62,
                        child: CircularProgressIndicator(
                          value: pct,
                          strokeWidth: 5,
                          backgroundColor: t.surface3,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            resolvedProgressColor,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${safePercentage.toStringAsFixed(0)}%',
                            style: PromotorText.display(
                              size: 13,
                              color: resolvedRingColor,
                            ),
                          ),
                          Text(
                            ringLabel,
                            style: PromotorText.outfit(
                              size: 10,
                              color: t.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (metaLeftText.trim().isNotEmpty)
                  Expanded(
                    child: Text(
                      metaLeftText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                const SizedBox(width: 10),
                Flexible(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: Text(
                      'Sisa ${_formatRupiah(sisa)}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.bold,
                        color: t.primaryAccentLight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(100),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 5,
                backgroundColor: t.surface3,
                valueColor: AlwaysStoppedAnimation(resolvedProgressColor),
              ),
            ),
          ),
          if (bottomContent case final Widget content) content,
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return GestureDetector(onTap: onTap, child: card);
  }
}
