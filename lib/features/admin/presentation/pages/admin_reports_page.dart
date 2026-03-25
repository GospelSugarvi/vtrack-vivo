import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: SingleChildScrollView(
        padding: EdgeInsets.all(isDesktop ? 24 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isDesktop) Text('Reports & Analytics', style: Theme.of(context).textTheme.headlineMedium),
            if (isDesktop) const SizedBox(height: 24),

            _buildReportSection(context, 'Sales Reports', [
              _ReportItem(icon: Icons.today, label: 'Penjualan Harian', onTap: () {}),
              _ReportItem(icon: Icons.date_range, label: 'Penjualan Mingguan', onTap: () {}),
              _ReportItem(icon: Icons.calendar_month, label: 'Penjualan Bulanan', onTap: () {}),
            ]),
            const SizedBox(height: 16),

            _buildReportSection(context, 'Achievement Reports', [
              _ReportItem(icon: Icons.emoji_events, label: 'Achievement per Promotor', onTap: () {}),
              _ReportItem(icon: Icons.groups, label: 'Achievement per SATOR', onTap: () {}),
              _ReportItem(icon: Icons.area_chart, label: 'Achievement per Area', onTap: () {}),
            ]),
            const SizedBox(height: 16),

            _buildReportSection(context, 'Bonus Reports', [
              _ReportItem(icon: Icons.attach_money, label: 'Bonus Calculation', onTap: () {}),
              _ReportItem(icon: Icons.receipt_long, label: 'Bonus History', onTap: () {}),
            ]),
            const SizedBox(height: 16),

            _buildReportSection(context, 'Stock Reports', [
              _ReportItem(icon: Icons.inventory_2, label: 'Stock per Toko', onTap: () {}),
              _ReportItem(icon: Icons.swap_horiz, label: 'Transfer History', onTap: () {}),
              _ReportItem(icon: Icons.warning, label: 'Discrepancy Report', onTap: () {}),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildReportSection(BuildContext context, String title, List<_ReportItem> items) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            ...items.map((item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.icon, color: AppTheme.primaryBlue),
              title: Text(item.label),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.download, size: 20),
                    tooltip: 'Export Excel',
                    onPressed: item.onTap,
                  ),
                  IconButton(
                    icon: const Icon(Icons.image, size: 20),
                    tooltip: 'Export Image',
                    onPressed: item.onTap,
                  ),
                ],
              ),
              onTap: item.onTap,
            )),
          ],
        ),
      ),
    );
  }
}

class _ReportItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  _ReportItem({required this.icon, required this.label, required this.onTap});
}
