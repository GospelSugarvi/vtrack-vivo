// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import '../../../../ui/foundation/field_theme_extensions.dart';

class SatorStockTab extends StatelessWidget {
  const SatorStockTab({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Stock Management'),
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
        surfaceTintColor: t.background,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: () => context.pushNamed('sator-profil'),
            icon: const Icon(Icons.person_outline),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Kelola Stok',
              style: TextStyle(
                fontSize: AppTypeScale.heading,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Pantau dan update stok gudang dan toko',
              style: TextStyle(color: t.textSecondary),
            ),
            const SizedBox(height: 24),

            // Menu Cards
            _buildMenuCard(
              context,
              icon: Icons.warehouse,
              title: 'Stok Gudang',
              subtitle: 'Lihat dan update stok gudang harian',
              color: t.primaryAccent,
              onTap: () => context.pushNamed('sator-stok-gudang'),
            ),
            const SizedBox(height: 12),

            _buildMenuCard(
              context,
              icon: Icons.store,
              title: 'Stok Toko',
              subtitle: 'Cek stok per outlet dan buat rekomendasi order',
              color: t.warning,
              onTap: () => context.pushNamed('sator-list-toko'),
            ),
            const SizedBox(height: 12),

            _buildMenuCard(
              context,
              icon: Icons.task_alt,
              title: 'Finalisasi Sell In',
              subtitle: 'Finalisasi order pending satu per satu',
              color: t.success,
              onTap: () => context.pushNamed('sator-finalisasi-sellin'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMenuCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final t = context.fieldTokens;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.surface1, color.withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: t.surface1.withValues(alpha: 0),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [color.withValues(alpha: 0.8), color],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Icon(icon, color: t.textOnAccent, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: AppTypeScale.bodyStrong,
                          letterSpacing: 0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: t.textSecondary,
                          fontSize: AppTypeScale.body,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.arrow_forward_ios, color: color, size: 16),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
