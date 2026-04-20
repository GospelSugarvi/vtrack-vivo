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
