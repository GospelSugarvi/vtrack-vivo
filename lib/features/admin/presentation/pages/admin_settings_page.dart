import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({super.key});

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
            if (isDesktop) Text('Settings', style: Theme.of(context).textTheme.headlineMedium),
            if (isDesktop) const SizedBox(height: 24),

            _buildSettingsCard(
              context,
              title: 'Aplikasi',
              items: [
                _SettingsItem(icon: Icons.color_lens, label: 'Tema', value: 'Light', onTap: () {}),
                _SettingsItem(icon: Icons.language, label: 'Bahasa', value: 'Indonesia', onTap: () {}),
              ],
            ),
            const SizedBox(height: 16),

            _buildSettingsCard(
              context,
              title: 'Notifikasi',
              items: [
                _SettingsItem(icon: Icons.notifications, label: 'Push Notification', value: 'Aktif', onTap: () {}),
                _SettingsItem(icon: Icons.email, label: 'Email Report', value: 'Nonaktif', onTap: () {}),
              ],
            ),
            const SizedBox(height: 16),

            _buildSettingsCard(
              context,
              title: 'Data',
              items: [
                _SettingsItem(icon: Icons.backup, label: 'Export Data', onTap: () {}),
                _SettingsItem(icon: Icons.delete_sweep, label: 'Clear Cache', onTap: () {}),
              ],
            ),
            const SizedBox(height: 16),

            _buildSettingsCard(
              context,
              title: 'Akun',
              items: [
                _SettingsItem(icon: Icons.lock, label: 'Ganti Password', onTap: () {}),
                _SettingsItem(
                  icon: Icons.logout,
                  label: 'Logout',
                  color: AppTheme.errorRed,
                  onTap: () async {
                    await supabase.auth.signOut();
                    if (context.mounted) context.go('/login');
                  },
                ),
              ],
            ),
            
            const SizedBox(height: 32),
            Center(
              child: Text('VTrack v1.0.0', style: Theme.of(context).textTheme.bodySmall),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard(BuildContext context, {required String title, required List<_SettingsItem> items}) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...items.map((item) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(item.icon, color: item.color ?? AppTheme.primaryBlue),
              title: Text(item.label, style: TextStyle(color: item.color)),
              trailing: item.value != null
                  ? Text(item.value!, style: TextStyle(color: AppTheme.textSecondary))
                  : const Icon(Icons.chevron_right),
              onTap: item.onTap,
            )),
          ],
        ),
      ),
    );
  }
}

class _SettingsItem {
  final IconData icon;
  final String label;
  final String? value;
  final Color? color;
  final VoidCallback onTap;

  _SettingsItem({required this.icon, required this.label, this.value, this.color, required this.onTap});
}
