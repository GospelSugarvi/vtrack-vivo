import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class AdminSatorRewardPage extends StatelessWidget {
  const AdminSatorRewardPage({super.key});

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
            if (isDesktop) Text('SATOR Reward Settings', style: Theme.of(context).textTheme.headlineMedium),
            if (isDesktop) const SizedBox(height: 24),

            _buildSection(context, 'KPI Categories', [
              _buildKpiRow('Sell Out Achievement', '40%'),
              _buildKpiRow('Tim Compliance', '30%'),
              _buildKpiRow('Stock Accuracy', '20%'),
              _buildKpiRow('Report Quality', '10%'),
            ]),
            const SizedBox(height: 16),

            _buildSection(context, 'Point System', [
              _buildPointRow('Tim capai 100%', '+100 pts'),
              _buildPointRow('Tim capai 110%', '+150 pts'),
              _buildPointRow('Zero stock issue', '+50 pts'),
              _buildPointRow('Tim tidak clock-in', '-20 pts'),
            ]),
            const SizedBox(height: 16),

            _buildSection(context, 'Special Product Rewards', [
              _buildRewardRow('X200 Pro', 'Rp 20.000/unit'),
              _buildRewardRow('V60 Lite', 'Rp 15.000/unit'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(BuildContext context, String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                IconButton(icon: const Icon(Icons.add), onPressed: () {}),
              ],
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildKpiRow(String name, String weight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(name)),
          Text(weight, style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildPointRow(String action, String points) {
    final isPositive = points.startsWith('+');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(action)),
          Text(points, style: TextStyle(fontWeight: FontWeight.bold, color: isPositive ? AppTheme.successGreen : AppTheme.errorRed)),
          IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () {}),
        ],
      ),
    );
  }

  Widget _buildRewardRow(String product, String reward) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Text(product)),
          Text(reward, style: const TextStyle(fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: () {}),
        ],
      ),
    );
  }
}
