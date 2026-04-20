// ignore_for_file: deprecated_member_use
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:vtrack/ui/foundation/foundation.dart';
import '../../../../core/utils/avatar_refresh_bus.dart';
import '../../../../core/utils/app_download_qr_dialog.dart';
import '../../../../core/utils/cloudinary_upload_helper.dart';
import '../../../../core/theme/app_font_preference_provider.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../ui/promotor/promotor.dart';

class SatorProfilTab extends StatefulWidget {
  const SatorProfilTab({super.key});

  @override
  State<SatorProfilTab> createState() => _SatorProfilTabState();
}

class _SatorProfilTabState extends State<SatorProfilTab> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _isUploading = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _supabase.rpc('get_my_profile_snapshot');

      if (mounted) {
        setState(() {
          _userProfile = Map<String, dynamic>.from(
            (profile as Map?) ?? const <String, dynamic>{},
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading profile: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadPhoto() async {
    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 78,
    );
    if (image == null || !mounted) return;

    setState(() => _isUploading = true);
    try {
      final upload = await CloudinaryUploadHelper.uploadXFile(
        image,
        folder: 'vtrack/profiles',
        fileName: 'sator_${DateTime.now().millisecondsSinceEpoch}.jpg',
        maxWidth: 1280,
        quality: 80,
      );
      final imageUrl = upload?.url;
      if (imageUrl == null || imageUrl.isEmpty) {
        throw Exception('URL foto tidak valid');
      }

      final result = await _supabase.rpc(
        'update_my_avatar_url',
        params: {'p_avatar_url': imageUrl},
      );
      final payload = Map<String, dynamic>.from(
        (result as Map?) ?? const <String, dynamic>{},
      );
      if (payload['success'] != true) {
        throw Exception('${payload['message'] ?? 'Gagal memperbarui avatar'}');
      }
      final currentMetadata =
          _supabase.auth.currentUser?.userMetadata ?? const <String, dynamic>{};
      await _supabase.auth.updateUser(
        UserAttributes(
          data: <String, dynamic>{...currentMetadata, 'avatar_url': imageUrl},
        ),
      );
      final userId = _supabase.auth.currentUser?.id;
      if (userId != null) {
        final prefs = await SharedPreferences.getInstance();
        final raw = prefs.getString('sator_home.profile.$userId');
        final cached = raw == null || raw.trim().isEmpty
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(raw) as Map);
        cached['avatar_url'] = imageUrl;
        await prefs.setString('sator_home.profile.$userId', jsonEncode(cached));
      }

      await _loadProfile();
      notifyAvatarRefresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Foto profil berhasil diperbarui'),
          backgroundColor: t.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal upload foto: $e'),
          backgroundColor: t.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      child: Column(children: [_buildHeader(), _buildMenuList()]),
    );
  }

  Widget _buildHeader() {
    final areaName = '${_userProfile?['area'] ?? 'Area'}';
    final fullName = '${_userProfile?['full_name'] ?? 'SATOR'}';
    final role = '${_userProfile?['role'] ?? 'sator'}'.toUpperCase();
    final avatarUrl = ('${_userProfile?['avatar_url'] ?? ''}').trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 40, 18, 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.primaryAccent, t.info],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: t.surface1,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.textOnAccent, width: 3),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatarUrl.isNotEmpty
                    ? Image.network(
                        avatarUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, error, stackTrace) => Center(
                          child: Text(
                            fullName.isNotEmpty
                                ? fullName[0].toUpperCase()
                                : 'S',
                            style: PromotorText.display(
                              size: 30,
                              color: t.primaryAccent,
                            ),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : 'S',
                          style: PromotorText.display(
                            size: 30,
                            color: t.primaryAccent,
                          ),
                        ),
                      ),
              ),
              Positioned(
                right: -4,
                bottom: -4,
                child: InkWell(
                  onTap: _isUploading ? null : _pickAndUploadPhoto,
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: t.textOnAccent,
                      shape: BoxShape.circle,
                      border: Border.all(color: t.primaryAccent, width: 2.2),
                    ),
                    child: _isUploading
                        ? Padding(
                            padding: const EdgeInsets.all(7),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.primaryAccent,
                            ),
                          )
                        : Icon(
                            Icons.camera_alt_rounded,
                            size: 16,
                            color: t.primaryAccent,
                          ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            fullName,
            style: PromotorText.display(size: 22, color: t.textOnAccent),
          ),
          const SizedBox(height: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: t.textOnAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.textOnAccent.withValues(alpha: 0.25)),
            ),
            child: Text(
              role,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w800,
                color: t.textOnAccent,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.textOnAccent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  color: t.textOnAccent,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    areaName,
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: t.textOnAccent,
                    ),
                  ),
                ),
                _actionChip(
                  label: 'Ubah Foto',
                  onTap: _isUploading ? null : _pickAndUploadPhoto,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({required String label, VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: t.textOnAccent.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.textOnAccent.withValues(alpha: 0.3)),
        ),
        child: Text(
          label,
          style: PromotorText.outfit(
            size: 9.5,
            weight: FontWeight.w800,
            color: t.textOnAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuList() {
    final menuItems = [
      _MenuItem(
        icon: Icons.palette_outlined,
        label: 'Tema & Tampilan',
        subtitle: 'Tema aplikasi dan pilihan font',
        onTap: () => _showThemeSelector(),
      ),
      _MenuItem(
        icon: Icons.system_update_alt_rounded,
        label: 'Cek Update',
        subtitle: 'Download versi terbaru',
        onTap: _openLatestRelease,
      ),
      _MenuItem(
        icon: Icons.info_outline,
        label: 'Tentang Aplikasi',
        subtitle: 'Versi 1.0.0',
        onTap: _showAboutApp,
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
      child: Column(
        children: [
          _buildAccountSummaryCard(),
          const SizedBox(height: 12),
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
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
                          color: (item.color ?? t.primaryAccent).withValues(
                            alpha: 0.1,
                          ),
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
                        style: PromotorText.outfit(
                          size: 12.5,
                          weight: FontWeight.w800,
                          color: item.color ?? t.textPrimary,
                        ),
                      ),
                      subtitle: Text(
                        item.subtitle,
                        style: PromotorText.outfit(
                          size: 9.5,
                          weight: FontWeight.w700,
                          color: t.textMutedStrong,
                        ),
                      ),
                      trailing: Icon(Icons.chevron_right, color: t.surface4),
                      onTap: item.onTap,
                    ),
                    if (index < menuItems.length - 1)
                      Divider(height: 1, indent: 70, color: t.surface3),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSummaryCard() {
    final joinRaw =
        '${_userProfile?['hire_date'] ?? _userProfile?['created_at'] ?? ''}'
            .trim();
    final joinDate = DateTime.tryParse(joinRaw);
    final joinLabel = joinDate == null
        ? '-'
        : DateFormat('d MMMM yyyy', 'id_ID').format(joinDate);
    final statusLabel = '${_userProfile?['status'] ?? 'Aktif'}';

    Widget tile({
      required IconData icon,
      required String label,
      required String value,
    }) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.surface3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: t.primaryAccent),
              const SizedBox(height: 10),
              Text(
                label,
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: PromotorText.outfit(
                  size: 12,
                  weight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Info Akun',
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                tile(
                  icon: Icons.calendar_month_rounded,
                  label: 'Tanggal Bergabung',
                  value: joinLabel,
                ),
                const SizedBox(width: 10),
                tile(
                  icon: Icons.verified_user_rounded,
                  label: 'Status Akun',
                  value: statusLabel,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showThemeSelector() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: false,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Consumer(
          builder: (context, ref, _) {
            final colors = Theme.of(context).colorScheme;
            final mode = ref.watch(themeModeProvider);
            final fontPreference = ref.watch(appFontPreferenceProvider);
            return SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(22),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Tema & Font',
                                style: PromotorText.outfit(
                                  size: 14,
                                  weight: FontWeight.w800,
                                  color: colors.onSurface,
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => Navigator.pop(context),
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: colors.surfaceContainerHigh,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: colors.outlineVariant,
                                  ),
                                ),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 16,
                                  color: colors.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Tema',
                          style: PromotorText.outfit(
                            size: 11,
                            weight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
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
                          surfaceColor: colors.surfaceContainerLow,
                          borderColor: colors.outlineVariant,
                          mutedColor: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 4),
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
                          surfaceColor: colors.surfaceContainerLow,
                          borderColor: colors.outlineVariant,
                          mutedColor: colors.onSurfaceVariant,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Font',
                          style: PromotorText.outfit(
                            size: 11,
                            weight: FontWeight.w800,
                            color: colors.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ...AppFontTokens.preferences.map(
                          (preference) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: _fontTile(
                              context,
                              ref,
                              value: preference,
                              group: fontPreference,
                              textColor: colors.onSurface,
                              subtitleColor: colors.onSurfaceVariant,
                              activeColor: colors.primary,
                              surfaceColor: colors.surfaceContainerLow,
                              borderColor: colors.outlineVariant,
                              mutedColor: colors.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
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
    required Color surfaceColor,
    required Color borderColor,
    required Color mutedColor,
  }) {
    final active = group == value;
    return Container(
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.10) : surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? activeColor : borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await ref.read(themeModeProvider.notifier).setMode(value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: PromotorText.outfit(
                  size: 8.5,
                  weight: FontWeight.w700,
                  color: subtitleColor,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: active ? activeColor : mutedColor,
              ),
            ],
          ),
        ),
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
    required Color surfaceColor,
    required Color borderColor,
    required Color mutedColor,
  }) {
    final active = group == value;
    return Container(
      decoration: BoxDecoration(
        color: active ? activeColor.withValues(alpha: 0.10) : surfaceColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: active ? activeColor : borderColor),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () async {
          await ref
              .read(appFontPreferenceProvider.notifier)
              .setPreference(value);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  AppFontTokens.preferenceNameOf(value),
                  style: AppFontTokens.preview(
                    value,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppFontTokens.preferenceDescriptionOf(value),
                style: PromotorText.outfit(
                  size: 8.5,
                  weight: FontWeight.w700,
                  color: subtitleColor,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                active
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 16,
                color: active ? activeColor : mutedColor,
              ),
            ],
          ),
        ),
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

  void _showAboutApp() {
    showAppAboutWithDownloadQr(context);
  }

  Future<void> _openLatestRelease() async {
    await openLatestAppDownload(context);
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
