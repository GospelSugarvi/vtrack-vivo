// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:vtrack/ui/foundation/foundation.dart';
import '../../../../core/theme/app_font_preference_provider.dart';
import '../../../../core/theme/theme_mode_provider.dart';

class SatorProfilTab extends StatefulWidget {
  const SatorProfilTab({super.key});

  @override
  State<SatorProfilTab> createState() => _SatorProfilTabState();
}

class _SatorProfilTabState extends State<SatorProfilTab> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _kpiSummary;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final userId = _supabase.auth.currentUser!.id;
      
      final profile = await _supabase
          .from('users')
          .select('*')
          .eq('id', userId)
          .single();

      // Load KPI summary
      final kpi = await _supabase.rpc('get_sator_kpi_summary', params: {
        'p_sator_id': userId,
      }).catchError((e) => null);

      if (mounted) {
        setState(() {
          _userProfile = profile;
          _kpiSummary = kpi;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(
        children: [
          _buildHeader(),
          _buildKpiSummary(),
          _buildMenuList(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final areaName = _userProfile?['area'] ?? 'Area';
    
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 48, 20, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.primaryAccent, t.info],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 45,
            backgroundColor: t.textPrimary,
            child: Text(
              (_userProfile?['full_name'] ?? 'S')[0].toUpperCase(),
              style: AppFontTokens.resolve(
                AppFontRole.display,
                fontSize: AppTypeScale.hero,
                fontWeight: FontWeight.bold,
                color: t.primaryAccent,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _userProfile?['full_name'] ?? 'SATOR',
            style: AppTextStyle.headingMd(
              t.textPrimary,
              weight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: t.textPrimary.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '🎯 SATOR',
              style: AppTextStyle.bodyMd(t.textPrimary),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            areaName,
            style: AppTextStyle.bodyMd(t.textPrimary.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiSummary() {
    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final totalScore = (_kpiSummary?['total_score'] ?? 0).toDouble();
    final totalBonus = _kpiSummary?['total_bonus'] ?? 0;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.warning, t.primaryAccentLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: t.warning.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'KPI Bulanan Ini',
                  style: AppTextStyle.bodyMd(t.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  '${totalScore.toStringAsFixed(0)}%',
                  style: AppTextStyle.heroNum(
                    t.textPrimary,
                    weight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 50,
            color: t.textPrimary.withValues(alpha: 0.3),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Estimasi Bonus',
                  style: AppTextStyle.bodyMd(t.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  formatter.format(totalBonus),
                  style: AppFontTokens.resolve(
                    AppFontRole.display,
                    fontSize: AppTypeScale.title,
                    fontWeight: FontWeight.bold,
                    color: t.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuList() {
    final menuItems = [
      _MenuItem(
        icon: Icons.analytics,
        label: 'Laporan Kinerja',
        subtitle: 'KPI breakdown + Trend',
        onTap: () => context.push('/sator/laporan-kinerja'),
      ),
      _MenuItem(
        icon: Icons.card_giftcard,
        label: 'Riwayat Reward',
        subtitle: 'History + Status cair',
        onTap: () => context.push('/sator/riwayat-reward'),
      ),
      _MenuItem(
        icon: Icons.notifications,
        label: 'Pengaturan Notifikasi',
        subtitle: 'Toggle per kategori',
        onTap: () {
          // TODO: Navigate to notification settings
        },
      ),
      _MenuItem(
        icon: Icons.palette_outlined,
        label: 'Tema & Font',
        subtitle: 'Tema aplikasi dan pilihan font',
        onTap: () => _showThemeSelector(),
      ),
      _MenuItem(
        icon: Icons.help_outline,
        label: 'Bantuan',
        subtitle: 'FAQ + Hubungi Support',
        onTap: () {
          // TODO: Navigate to help
        },
      ),
      _MenuItem(
        icon: Icons.info_outline,
        label: 'Tentang Aplikasi',
        subtitle: 'Versi 1.0.0',
        onTap: () {
          // TODO: Show about dialog
        },
      ),
      _MenuItem(
        icon: Icons.logout,
        label: 'Logout',
        subtitle: 'Keluar dari akun',
        color: t.danger,
        onTap: () => _handleLogout(),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          children: menuItems.asMap().entries.map((entry) {
            final index = entry.key;
            final item = entry.value;
            return Column(
              children: [
                ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (item.color ?? t.primaryAccent).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      item.icon,
                      color: item.color ?? t.primaryAccent,
                      size: 22,
                    ),
                  ),
                  title: Text(
                    item.label,
                    style: AppTextStyle.bodyMd(
                      item.color ?? t.textPrimary,
                      weight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    item.subtitle,
                    style: AppTextStyle.bodySm(t.textSecondary),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: t.surface4,
                  ),
                  onTap: item.onTap,
                ),
                if (index < menuItems.length - 1)
                  Divider(
                    height: 1,
                    indent: 70,
                    color: t.surface3,
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        final colors = theme.colorScheme;
        return Consumer(
          builder: (context, ref, _) {
            final mode = ref.watch(themeModeProvider);
            final fontPreference = ref.watch(appFontPreferenceProvider);
            return SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tampilan',
                        style: AppTextStyle.titleSm(
                          colors.onSurface,
                          weight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tema',
                        style: AppTextStyle.bodyMd(
                          colors.onSurface,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _themeTile(
                        context,
                        ref,
                        title: 'Ikuti Sistem',
                        subtitle: 'Gunakan tema dari perangkat',
                        value: ThemeMode.system,
                        group: mode,
                        textColor: colors.onSurface,
                        subtitleColor: colors.onSurfaceVariant,
                        activeColor: colors.primary,
                      ),
                      const SizedBox(height: 8),
                      _themeTile(
                        context,
                        ref,
                        title: 'Gelap',
                        subtitle: 'Tampilan dominan hitam',
                        value: ThemeMode.dark,
                        group: mode,
                        textColor: colors.onSurface,
                        subtitleColor: colors.onSurfaceVariant,
                        activeColor: colors.primary,
                      ),
                      const SizedBox(height: 8),
                      _themeTile(
                        context,
                        ref,
                        title: 'Terang',
                        subtitle: 'Tampilan dominan putih',
                        value: ThemeMode.light,
                        group: mode,
                        textColor: colors.onSurface,
                        subtitleColor: colors.onSurfaceVariant,
                        activeColor: colors.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Font',
                        style: AppTextStyle.bodyMd(
                          colors.onSurface,
                          weight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...AppFontTokens.preferences.map(
                        (preference) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _fontTile(
                            context,
                            ref,
                            value: preference,
                            group: fontPreference,
                            textColor: colors.onSurface,
                            subtitleColor: colors.onSurfaceVariant,
                            activeColor: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _themeTile(
    BuildContext context,
    WidgetRef ref, {
    required String title,
    required String subtitle,
    required ThemeMode value,
    required ThemeMode group,
    required Color textColor,
    required Color subtitleColor,
    required Color activeColor,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          title,
          style: AppTextStyle.bodyMd(textColor, weight: FontWeight.w600),
        ),
        subtitle: Text(subtitle, style: AppTextStyle.bodyMd(subtitleColor)),
        trailing: Radio<ThemeMode>(
          value: value,
          groupValue: group,
          activeColor: activeColor,
          onChanged: (val) async {
            if (val == null) return;
            await ref.read(themeModeProvider.notifier).setMode(val);
          },
        ),
        onTap: () async {
          await ref.read(themeModeProvider.notifier).setMode(value);
        },
      ),
    );
  }

  Widget _fontTile(
    BuildContext context,
    WidgetRef ref, {
    required AppFontPreference value,
    required AppFontPreference group,
    required Color textColor,
    required Color subtitleColor,
    required Color activeColor,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        title: Text(
          AppFontTokens.preferenceNameOf(value),
          style: AppFontTokens.preview(
            value,
            fontSize: AppTypeScale.bodyStrong,
            fontWeight: FontWeight.w700,
            color: textColor,
          ),
        ),
        subtitle: Text(
          AppFontTokens.preferenceDescriptionOf(value),
          style: AppTextStyle.bodySm(subtitleColor),
        ),
        trailing: Radio<AppFontPreference>(
          value: value,
          groupValue: group,
          activeColor: activeColor,
          onChanged: (val) async {
            if (val == null) return;
            await ref.read(appFontPreferenceProvider.notifier).setPreference(val);
          },
        ),
        onTap: () async {
          await ref.read(appFontPreferenceProvider.notifier).setPreference(value);
        },
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Apakah Anda yakin ingin keluar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: t.danger),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _supabase.auth.signOut();
      if (mounted) context.go('/login');
    }
  }
}

class _MenuItem {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color? color;
  final VoidCallback onTap;

  _MenuItem({
    required this.icon,
    required this.label,
    required this.subtitle,
    this.color,
    required this.onTap,
  });
}
