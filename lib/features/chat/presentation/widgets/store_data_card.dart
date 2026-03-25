import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/store_daily_data.dart';
import '../theme/chat_theme.dart';

class StoreDataCard extends StatelessWidget {
  final StoreDailyData data;

  const StoreDataCard({
    super.key,
    required this.data,
  });

  @override
  Widget build(BuildContext context) {
    final c = chatPaletteOf(context);
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [c.blueSoft, c.greenSoft],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(
                Icons.store,
                color: c.blue,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  data.storeName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: c.blue,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.blueSoft,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  DateFormat('dd MMM yyyy').format(data.dateChecked),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: c.blue,
                  ),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Attendance Section
          _buildSection(
            title: 'ATTENDANCE',
            icon: Icons.people,
            color: c.amber,
            children: [
              _buildDataRow(
                context,
                'Present',
                '${data.presentPromotors}/${data.totalPromotors}',
                c.green,
              ),
              _buildDataRow(
                context,
                'Absent',
                '${data.absentPromotors}',
                c.red,
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Sales Section
          _buildSection(
            title: 'SALES TODAY',
            icon: Icons.trending_up,
            color: c.green,
            children: [
              _buildDataRow(
                context,
                'Total Sales',
                '${data.totalSales} units',
                c.blue,
              ),
              _buildDataRow(
                context,
                'Sell Out',
                formatter.format(data.totalOmzet),
                c.green,
              ),
              _buildDataRow(
                context,
                'Fokus Sales',
                '${data.totalFokus} units',
                c.purple,
              ),
            ],
          ),
          
          const SizedBox(height: 12),
          
          // Performance Section
          Row(
            children: [
              Expanded(
                child: _buildMetricCard(
                  context: context,
                  title: 'Stock',
                  value: '${data.totalStock}',
                  subtitle: 'units',
                  color: c.blue,
                  icon: Icons.inventory,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricCard(
                  context: context,
                  title: 'Achievement',
                  value: '${data.achievementPercentage.toStringAsFixed(1)}%',
                  subtitle: 'target',
                  color: _getAchievementColor(context, data.achievementPercentage),
                  icon: Icons.track_changes,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: color,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ...children,
      ],
    );
  }

  Widget _buildDataRow(
    BuildContext context,
    String label,
    String value,
    Color valueColor,
  ) {
    final c = chatPaletteOf(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: c.muted2,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required BuildContext context,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
  }) {
    final c = chatPaletteOf(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.s3),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: c.muted2,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: c.muted2,
            ),
          ),
        ],
      ),
    );
  }

  Color _getAchievementColor(BuildContext context, double percentage) {
    final c = chatPaletteOf(context);
    if (percentage >= 100) return c.green;
    if (percentage >= 75) return c.amber;
    return c.red;
  }
}
