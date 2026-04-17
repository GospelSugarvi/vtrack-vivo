import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_font_preference_provider.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/app_download_qr_dialog.dart';
import '../../../../core/utils/avatar_refresh_bus.dart';
import '../../../../core/utils/cloudinary_upload_helper.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_font_tokens.dart';
import '../../../../ui/foundation/app_type_scale.dart';
import '../../../../ui/promotor/promotor.dart';

class PromotorProfilTab extends StatefulWidget {
  const PromotorProfilTab({super.key});

  @override
  State<PromotorProfilTab> createState() => _PromotorProfilTabState();
}

class _PromotorProfilTabState extends State<PromotorProfilTab> {
  static final Uri _latestReleaseUri = Uri.parse(
    'https://github.com/GospelSugarvi/vtrack-vivo/releases/latest',
  );
  FieldThemeTokens get t => context.fieldTokens;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _storeInfo;
  String? _satorName;
  ImageProvider? _avatarImageProvider;
  bool _isLoading = true;
  bool _isUploading = false;

  Future<ImageProvider?> _resolveAvatarProvider(String? avatarUrl) async {
    final normalizedUrl = avatarUrl?.trim();
    if (normalizedUrl == null || normalizedUrl.isEmpty) return null;

    try {
      final provider = CachedNetworkImageProvider(normalizedUrl);
      await precacheImage(
        provider,
        context,
      ).timeout(const Duration(seconds: 4));
      return provider;
    } catch (_) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  /// Delete old image from Cloudinary
  /// Note: This requires API key & secret for authenticated delete
  /// For now, we'll just extract public_id and attempt delete
  void _deleteOldCloudinaryImage(String imageUrl) async {
    try {
      // Extract public_id from URL
      // Example URL: https://res.cloudinary.com/dkkbwu8hj/image/upload/v1234567890/vtrack/profiles/profile_1234567890.jpg
      final uri = Uri.parse(imageUrl);
      final pathSegments = uri.pathSegments;

      // Find index of 'upload' and get everything after version
      final uploadIndex = pathSegments.indexOf('upload');
      if (uploadIndex == -1 || uploadIndex + 2 >= pathSegments.length) return;

      // public_id is path after version (skip 'v1234567890')
      final publicIdParts = pathSegments.sublist(uploadIndex + 2);
      final publicId = publicIdParts
          .join('/')
          .replaceAll(RegExp(r'\.[^.]+$'), ''); // Remove extension
      if (publicId.isEmpty) return;
    } catch (_) {}
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw SessionExpiredException();
      }

      final results = await Future.wait<dynamic>([
        supabase
            .from('users')
            .select(
              'id, full_name, nickname, area, created_at, hire_date, avatar_url, status, promotor_status',
            )
            .eq('id', userId)
            .single()
            .timeout(const Duration(seconds: 10)),
        supabase
            .from('assignments_promotor_store')
            .select('store_id')
            .eq('promotor_id', userId)
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(1)
            .timeout(const Duration(seconds: 10)),
        supabase
            .from('hierarchy_sator_promotor')
            .select(
              'sator:users!hierarchy_sator_promotor_sator_id_fkey(full_name)',
            )
            .eq('promotor_id', userId)
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(1)
            .timeout(const Duration(seconds: 10)),
      ]);

      final profile = Map<String, dynamic>.from(results[0] as Map);
      final storeAssignmentRows = results[1] as List<dynamic>;
      final satorLinkRows = results[2] as List<dynamic>;

      final storeAssignments = List<Map<String, dynamic>>.from(
        storeAssignmentRows,
      );
      final storeAssignment = storeAssignments.isNotEmpty
          ? storeAssignments.first
          : null;

      Map<String, dynamic>? storeInfo;
      if (storeAssignment != null) {
        final storeData = await supabase
            .from('stores')
            .select('store_name, address')
            .eq('id', storeAssignment['store_id'])
            .single()
            .timeout(const Duration(seconds: 10));
        storeInfo = storeData;
      }

      String? satorName;
      final satorLinks = List<Map<String, dynamic>>.from(satorLinkRows);
      if (satorLinks.isNotEmpty) {
        final sator = satorLinks.first['sator'];
        if (sator is Map<String, dynamic>) {
          satorName = sator['full_name']?.toString();
        } else if (sator is Map) {
          satorName = sator['full_name']?.toString();
        }
      }

      final avatarProvider = await _resolveAvatarProvider(
        profile['avatar_url']?.toString(),
      );

      if (!mounted) return;
      setState(() {
        _userProfile = profile;
        _storeInfo = storeInfo;
        _avatarImageProvider = avatarProvider;
        _satorName = satorName;
        _isLoading = false;
      });
    } on SocketException catch (e) {
      debugPrint('Error loading profile (network): $e');
      if (mounted) {
        ErrorHandler.showErrorDialog(
          context,
          NetworkException(originalError: e),
          onRetry: _loadProfile,
        );
      }
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading profile: $e');
      final exception = ErrorHandler.handleError(e);
      if (mounted) {
        // Don't show error for permission denied - just show empty state
        if (exception is PermissionException) {
          ErrorHandler.showErrorSnackBar(context, exception.message);
        }
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickAndUploadImage() async {
    // Show option: Camera or Gallery
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Pilih Sumber Foto',
              style: TextStyle(
                fontSize: AppTypeScale.title,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.pop(context, ImageSource.camera),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: t.infoSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: t.info.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.camera_alt, size: 40, color: t.info),
                          const SizedBox(height: 8),
                          Text(
                            'Kamera',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: t.info,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.pop(context, ImageSource.gallery),
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: t.successSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: t.success.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(Icons.photo_library, size: 40, color: t.success),
                          const SizedBox(height: 8),
                          Text(
                            'Galeri',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: t.success,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
          ],
        ),
      ),
    );

    if (source == null) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: source,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 75,
    );

    if (image == null) return;

    // Show preview and confirm
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Preview Foto'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(image.path),
                width: 200,
                height: 200,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Gunakan foto ini sebagai foto profil?',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primaryAccent,
              foregroundColor: t.textOnAccent,
            ),
            child: const Text('Upload'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    if (!mounted) return;
    setState(() => _isUploading = true);

    try {
      // Get old avatar URL before uploading new one
      final userId = supabase.auth.currentUser!.id;
      final oldProfile = await supabase
          .from('users')
          .select('avatar_url')
          .eq('id', userId)
          .single();
      final oldAvatarUrl = oldProfile['avatar_url'] as String?;

      final upload = await CloudinaryUploadHelper.uploadXFile(
        image,
        folder: 'vtrack/profiles',
        fileName: 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
        maxWidth: 1280,
        quality: 80,
      );
      final imageUrl = upload?.url;

      if (imageUrl != null && imageUrl.isNotEmpty) {
        // Update user profile in database
        await supabase
            .from('users')
            .update({'avatar_url': imageUrl})
            .eq('id', userId);

        final currentMetadata =
            supabase.auth.currentUser?.userMetadata ??
            const <String, dynamic>{};
        await supabase.auth.updateUser(
          UserAttributes(data: {...currentMetadata, 'avatar_url': imageUrl}),
        );
        final prefs = await SharedPreferences.getInstance();
        final cacheKey = 'promotor_home.profile.$userId';
        final raw = prefs.getString(cacheKey);
        if (raw != null && raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            final cached = Map<String, dynamic>.from(decoded)
              ..['avatar_url'] = imageUrl;
            await prefs.setString(cacheKey, jsonEncode(cached));
          }
        }

        // Delete old photo from Cloudinary if exists
        if (oldAvatarUrl != null && oldAvatarUrl.isNotEmpty) {
          _deleteOldCloudinaryImage(oldAvatarUrl);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(Icons.check_circle, color: t.textOnAccent),
                  SizedBox(width: 12),
                  Text('Foto profil berhasil diperbarui!'),
                ],
              ),
              backgroundColor: t.success,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }

        // Reload profile
        _loadProfile();
        notifyAvatarRefresh();
      } else {
        throw Exception('Upload foto profil gagal');
      }
    } catch (e) {
      debugPrint('Error uploading image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(Icons.error_outline, color: t.textOnAccent),
                const SizedBox(width: 12),
                Expanded(child: Text('Gagal upload foto: ${e.toString()}')),
              ],
            ),
            backgroundColor: t.danger,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
          : RefreshIndicator(
              onRefresh: _loadProfile,
              color: t.primaryAccent,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverAppBar(
                    pinned: true,
                    elevation: 0,
                    backgroundColor: t.background.withValues(alpha: 0.96),
                    surfaceTintColor: t.background.withValues(alpha: 0),
                    centerTitle: true,
                    title: Text(
                      'Profil Saya',
                      style: PromotorText.display(
                        size: 20,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProfileIdentity(),
                          const SizedBox(height: 28),
                          _buildAccountSummaryCard(),
                          const SizedBox(height: 12),
                          _buildProfileMenuCard(),
                          const SizedBox(height: 20),
                          _buildLogoutButton(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileIdentity() {
    final fullName =
        (_userProfile?['full_name']?.toString().trim().isNotEmpty ?? false)
        ? _userProfile!['full_name'].toString().trim()
        : ((_userProfile?['nickname'] ?? 'Promotor') as String).trim();
    final areaLabel = _userProfile?['area']?.toString().trim();

    return Column(
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(32),
                border: Border.all(color: t.surface3, width: 3),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: _avatarImageProvider != null
                    ? Image(
                        image: _avatarImageProvider!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : _buildAvatarFallback(fullName),
              ),
            ),
            Positioned(
              right: -4,
              bottom: -4,
              child: Material(
                color: t.background.withValues(alpha: 0),
                child: InkWell(
                  onTap: _isUploading ? null : _pickAndUploadImage,
                  borderRadius: BorderRadius.circular(10),
                  child: Ink(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: t.primaryAccent,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.background, width: 3),
                    ),
                    child: _isUploading
                        ? Padding(
                            padding: EdgeInsets.all(7),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.textOnAccent,
                            ),
                          )
                        : Icon(
                            Icons.camera_alt_outlined,
                            size: 17,
                            color: t.textOnAccent,
                          ),
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          fullName.toUpperCase(),
          textAlign: TextAlign.center,
          style: PromotorText.display(size: 22, color: t.textPrimary),
        ),
        const SizedBox(height: 4),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            if (areaLabel != null && areaLabel.isNotEmpty)
              _buildMetaChip(Icons.location_on_outlined, areaLabel),
            if ((_storeInfo?['store_name']?.toString().trim().isNotEmpty ??
                false))
              _buildMetaChip(
                Icons.storefront_outlined,
                _storeInfo!['store_name'].toString().trim(),
              ),
            if ((_satorName?.trim().isNotEmpty ?? false))
              _buildMetaChip(Icons.groups_2_outlined, _satorName!.trim()),
          ],
        ),
      ],
    );
  }

  Widget _buildMetaChip(IconData icon, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: t.primaryAccent),
          const SizedBox(width: 6),
          Text(
            value,
            style: PromotorText.outfit(
              size: 10.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSummaryCard() {
    final joinLabel = _joinedDateLabel();
    final statusLabel = _promotorStatusLabel();

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

  String _promotorStatusLabel() {
    final promotorStatus =
        '${_userProfile?['promotor_status'] ?? _userProfile?['promotor_type'] ?? ''}'
            .trim()
            .toLowerCase();
    if (promotorStatus == 'official') return 'Official';
    if (promotorStatus == 'training') return 'Training';

    final accountStatus = '${_userProfile?['status'] ?? ''}'.trim();
    if (accountStatus.isEmpty) return 'Aktif';
    return accountStatus[0].toUpperCase() + accountStatus.substring(1);
  }

  Widget _buildProfileMenuCard() {
    final menuItems = [
      (
        icon: Icons.palette_outlined,
        label: 'Tema & Tampilan',
        subtitle: 'Tema aplikasi dan pilihan font',
        color: t.primaryAccent,
        onTap: _showThemeSelector,
      ),
      (
        icon: Icons.system_update_alt_rounded,
        label: 'Cek Update',
        subtitle: 'Download versi terbaru',
        color: t.info,
        onTap: _openLatestRelease,
      ),
      (
        icon: Icons.info_outline,
        label: 'Tentang Aplikasi',
        subtitle: 'Info versi aplikasi',
        color: t.primaryAccent,
        onTap: _showAboutApp,
      ),
    ];

    return Card(
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
                    color: item.color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(item.icon, color: item.color, size: 22),
                ),
                title: Text(
                  item.label,
                  style: PromotorText.outfit(
                    size: 12.5,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
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
    );
  }

  Widget _buildAvatarFallback(String displayName) {
    return Center(
      child: Text(
        displayName.isEmpty ? 'P' : displayName[0].toUpperCase(),
        style: PromotorText.display(size: 34, color: t.primaryAccent),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return Material(
      color: t.background.withValues(alpha: 0),
      child: InkWell(
        onTap: _handleLogout,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: t.danger.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: t.danger.withValues(alpha: 0.22)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout_rounded, color: t.danger, size: 18),
              const SizedBox(width: 10),
              Text(
                'Keluar dari Akun',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w800,
                  color: t.danger,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _joinedDateLabel() {
    final raw =
        _userProfile?['hire_date']?.toString() ??
        _userProfile?['created_at']?.toString();
    if (raw == null || raw.isEmpty) return '-';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '-';
    return DateFormat('d MMMM yyyy', 'id_ID').format(parsed.toLocal());
  }

  void _showAboutApp() {
    showAppAboutWithDownloadQr(context);
  }

  Future<void> _openLatestRelease() async {
    final launched = await launchUrl(
      _latestReleaseUri,
      mode: LaunchMode.externalApplication,
    );
    if (launched || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Link update tidak bisa dibuka')),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: t.danger,
              foregroundColor: t.textOnAccent,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await supabase.auth.signOut();
      if (mounted) context.go('/login');
    }
  }
}
