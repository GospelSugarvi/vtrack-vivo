import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';

class AdminAiSettingsPage extends StatefulWidget {
  const AdminAiSettingsPage({super.key});

  @override
  State<AdminAiSettingsPage> createState() => _AdminAiSettingsPageState();
}

class _AdminAiSettingsPageState extends State<AdminAiSettingsPage> {
  bool _businessReviewEnabled = true;
  bool _motivatorEnabled = true;
  bool _salesCommentEnabled = true;

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
            if (isDesktop) Text('AI Settings', style: Theme.of(context).textTheme.headlineMedium),
            if (isDesktop) const SizedBox(height: 8),
            if (isDesktop) Text('Kontrol semua AI features', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),

            _buildAiCard(
              title: 'AI Business Review',
              description: 'Review mingguan otomatis untuk SATOR',
              isEnabled: _businessReviewEnabled,
              onToggle: (v) => setState(() => _businessReviewEnabled = v),
              settings: const ['Periode: Mingguan', 'Hari: Senin 08:00'],
            ),
            const SizedBox(height: 16),

            _buildAiCard(
              title: 'AI Motivator',
              description: 'Motivasi otomatis di leaderboard feed',
              isEnabled: _motivatorEnabled,
              onToggle: (v) => setState(() => _motivatorEnabled = v),
              settings: const ['Frekuensi: Setiap 2 jam', 'Jam: 08:00 - 20:00'],
            ),
            const SizedBox(height: 16),

            _buildAiCard(
              title: 'AI Sales Comment',
              description: 'Komentar otomatis untuk penjualan',
              isEnabled: _salesCommentEnabled,
              onToggle: (v) => setState(() => _salesCommentEnabled = v),
              settings: const ['Delay: 30 detik', 'Triggers: First sale, Big deal, Milestone'],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAiCard({
    required String title,
    required String description,
    required bool isEnabled,
    required Function(bool) onToggle,
    required List<String> settings,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Theme.of(context).textTheme.titleMedium),
                      Text(description, style: TextStyle(color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
                Switch(value: isEnabled, activeThumbColor: AppTheme.successGreen, onChanged: onToggle),
              ],
            ),
            if (isEnabled) ...[
              const Divider(height: 24),
              ...settings.map((s) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    const Icon(Icons.check, size: 16, color: AppTheme.successGreen),
                    const SizedBox(width: 8),
                    Text(s),
                  ],
                ),
              )),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit Prompt'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
