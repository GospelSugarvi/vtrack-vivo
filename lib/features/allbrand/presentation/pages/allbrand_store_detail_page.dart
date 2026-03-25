import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../widgets/allbrand_report_detail_panel.dart';

class AllbrandStoreDetailPage extends StatelessWidget {
  final String storeId;
  final String storeName;
  final DateTime? targetDate;

  const AllbrandStoreDetailPage({
    super.key,
    required this.storeId,
    required this.storeName,
    this.targetDate,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Detail All Brand',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            Text(
              storeName,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                t.primaryAccentSoft.withValues(alpha: 0.18),
                t.textOnAccent,
                t.textOnAccent,
              ],
            ),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      t.surface1,
                      t.primaryAccentSoft.withValues(alpha: 0.22),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: t.surface3),
                  boxShadow: [
                    BoxShadow(
                      color: t.primaryAccentSoft.withValues(alpha: 0.12),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: t.primaryAccentSoft,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.analytics_rounded,
                        color: t.primaryAccent,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            targetDate == null
                                ? 'Ringkasan toko'
                                : 'Ringkasan ${targetDate!.day}/${targetDate!.month}/${targetDate!.year}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                              color: t.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Format detail siap dibaca dan disalin',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: t.textMutedStrong,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              AllbrandReportDetailPanel(
                storeId: storeId,
                initialStoreName: storeName,
                targetDate: targetDate,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
