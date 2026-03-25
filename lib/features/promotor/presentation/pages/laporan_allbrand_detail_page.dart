import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import '../../../allbrand/presentation/widgets/allbrand_report_detail_panel.dart';
import '../../../../ui/promotor/promotor.dart';

class LaporanAllbrandDetailPage extends StatefulWidget {
  final String reportId;

  const LaporanAllbrandDetailPage({super.key, required this.reportId});

  @override
  State<LaporanAllbrandDetailPage> createState() =>
      _LaporanAllbrandDetailPageState();
}

class _LaporanAllbrandDetailPageState extends State<LaporanAllbrandDetailPage> {
  FieldThemeTokens get t => context.fieldTokens;
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: Container(
        color: t.background,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                decoration: BoxDecoration(
                  color: t.background,
                  border: Border(bottom: BorderSide(color: t.surface2)),
                ),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => Navigator.of(context).maybePop(),
                      borderRadius: BorderRadius.circular(10),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: t.surface3),
                        ),
                        child: Icon(
                          Icons.arrow_back_ios_new_rounded,
                          color: t.textSecondary,
                          size: 17,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Text(
                      'Hasil AllBrand',
                      style: PromotorText.display(
                        size: 18,
                        color: t.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: AllbrandReportDetailPanel(reportId: widget.reportId),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
