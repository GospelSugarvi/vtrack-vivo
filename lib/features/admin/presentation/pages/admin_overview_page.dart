import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';

class AdminOverviewPage extends StatefulWidget {
  const AdminOverviewPage({super.key});

  @override
  State<AdminOverviewPage> createState() => _AdminOverviewPageState();
}

class _AdminOverviewPageState extends State<AdminOverviewPage> {
  Map<String, int> _stats = {
    'users': 0,
    'stores': 0,
    'products': 0,
    'sales_today': 0,
  };
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      // Count users
      final usersCount = await supabase
          .from('users')
          .select('id')
          .count();

      // Count stores
      final storesCount = await supabase
          .from('stores')
          .select('id')
          .count();

      // Count products
      final productsCount = await supabase
          .from('products')
          .select('id')
          .count();

      if (!mounted) return;
      setState(() {
        _stats = {
          'users': usersCount.count,
          'stores': storesCount.count,
          'products': productsCount.count,
          'sales_today': 0, // TODO: Implement
        };
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: isDesktop ? null : null, // AppBar handled by parent
      body: RefreshIndicator(
        onRefresh: _loadStats,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isDesktop ? 24 : 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (isDesktop) ...[
                Text(
                  'Overview',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'Selamat datang di Panel Admin VTrack',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
              ],

              // Stats Grid
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else
                _buildStatsGrid(isDesktop),

              const SizedBox(height: 24),

              // Quick Actions
              Text(
                'Aksi Cepat',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              _buildQuickActions(isDesktop),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsGrid(bool isDesktop) {
    final stats = [
      _StatItem(
        icon: Icons.people,
        label: 'Total User',
        value: _stats['users'].toString(),
        color: AppColors.info,
      ),
      _StatItem(
        icon: Icons.store,
        label: 'Total Toko',
        value: _stats['stores'].toString(),
        color: AppColors.success,
      ),
      _StatItem(
        icon: Icons.phone_android,
        label: 'Total Produk',
        value: _stats['products'].toString(),
        color: AppColors.warning,
      ),
      _StatItem(
        icon: Icons.shopping_cart,
        label: 'Penjualan Hari Ini',
        value: _stats['sales_today'].toString(),
        color: Colors.purple,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: stats.map((stat) => Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _buildStatCard(stat),
          ),
        )).toList(),
      );
    } else {
      return GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        childAspectRatio: 1.5,
        children: stats.map((stat) => _buildStatCard(stat)).toList(),
      );
    }
  }

  Widget _buildStatCard(_StatItem stat) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: stat.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(stat.icon, color: stat.color, size: 20),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              stat.value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              stat.label,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions(bool isDesktop) {
    final actions = [
      _ActionItem(icon: Icons.person_add, label: 'Tambah User', color: AppColors.info),
      _ActionItem(icon: Icons.store, label: 'Tambah Toko', color: AppColors.success),
      _ActionItem(icon: Icons.phone_android, label: 'Tambah Produk', color: AppColors.warning),
      _ActionItem(icon: Icons.campaign, label: 'Pengumuman', color: AppColors.danger),
      _ActionItem(icon: Icons.track_changes, label: 'Set Target', color: Colors.purple),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: actions.map((action) => InkWell(
        onTap: () {
          // If label is 'Kelola Chat', navigate to it
          // Note: In this architecture, we should use a callback or global state to change dashboard tab
          // For now, let's keep it as a visual indicator unless we refactor the dashboard
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Buka menu ${action.label} di sidebar')),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: isDesktop ? 150 : (MediaQuery.of(context).size.width - 44) / 2,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(color: action.color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(12),
            color: action.color.withValues(alpha: 0.05),
          ),
          child: Column(
            children: [
              Icon(action.icon, color: action.color, size: 28),
              const SizedBox(height: 8),
              Text(
                action.label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: action.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      )).toList(),
    );
  }
}

class _StatItem {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  _StatItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _ActionItem {
  final IconData icon;
  final String label;
  final Color color;

  _ActionItem({
    required this.icon,
    required this.label,
    required this.color,
  });
}
