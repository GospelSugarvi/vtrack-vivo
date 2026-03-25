import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/theme/app_font_preference_provider.dart';
import '../../../../core/theme/theme_mode_provider.dart';
import '../../../../core/utils/error_handler.dart';
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
  FieldThemeTokens get t => context.fieldTokens;
  Map<String, dynamic>? _userProfile;
  Map<String, dynamic>? _storeInfo;
  Map<String, dynamic>? _monthlyStats;
  String? _satorName;
  bool _isLoading = true;
  bool _isUploading = false;

  // Cloudinary config
  static const String _cloudinaryCloudName = 'dkkbwu8hj';
  static const String _cloudinaryUploadPreset = 'vtrack_uploads';

  num _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  Map<String, dynamic> _normalizeBonusSummary(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is List && value.isNotEmpty && value.first is Map) {
      return Map<String, dynamic>.from(value.first as Map);
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _loadMonthlyBonusSummary({
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final summary = await supabase.rpc(
      'get_promotor_bonus_summary',
      params: {
        'p_promotor_id': userId,
        'p_start_date': startDate.toIso8601String().split('T')[0],
        'p_end_date': endDate.toIso8601String().split('T')[0],
      },
    );
    return _normalizeBonusSummary(summary);
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

      debugPrint('🗑️ Attempting to delete old image: $publicId');

      // Note: Cloudinary delete requires authenticated request with API key & secret
      // For security, this should be done via backend/cloud function
      // For now, we'll just log it. Old images will remain in Cloudinary.
      // To implement proper delete, create a Supabase Edge Function

      debugPrint('⚠️ Old image not deleted (requires backend implementation)');
      debugPrint('💡 Public ID: $publicId');
    } catch (e) {
      debugPrint('❌ Error extracting public_id: $e');
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        throw SessionExpiredException();
      }

      // Load user profile with timeout
      final profile = await supabase
          .from('users')
          .select('*')
          .eq('id', userId)
          .single()
          .timeout(const Duration(seconds: 10));

      // Load store info with timeout
      final storeAssignmentRows = await supabase
          .from('assignments_promotor_store')
          .select('store_id')
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(const Duration(seconds: 10));

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
      final satorLinkRows = await supabase
          .from('hierarchy_sator_promotor')
          .select(
            'sator:users!hierarchy_sator_promotor_sator_id_fkey(full_name)',
          )
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(const Duration(seconds: 10));
      final satorLinks = List<Map<String, dynamic>>.from(satorLinkRows);
      if (satorLinks.isNotEmpty) {
        final sator = satorLinks.first['sator'];
        if (sator is Map<String, dynamic>) {
          satorName = sator['full_name']?.toString();
        } else if (sator is Map) {
          satorName = sator['full_name']?.toString();
        }
      }

      // Load monthly stats from the same bonus summary RPC used by dashboard/detail.
      final now = DateTime.now();
      final startOfMonthDate = DateTime(now.year, now.month, 1);
      final monthlySummary = await _loadMonthlyBonusSummary(
        userId: userId,
        startDate: startOfMonthDate,
        endDate: DateTime(now.year, now.month + 1, 0),
      );

      setState(() {
        _userProfile = profile;
        _storeInfo = storeInfo;
        _monthlyStats = {
          'sales_count': _toNum(monthlySummary['total_sales']).toInt(),
          'total_sales': _toNum(monthlySummary['total_revenue']),
          'total_bonus': _toNum(monthlySummary['total_bonus']),
        };
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
    } on TimeoutException catch (e) {
      debugPrint('Error loading profile (timeout): $e');
      if (mounted) {
        ErrorHandler.showErrorDialog(
          context,
          e as AppException,
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
              style: TextStyle(fontSize: AppTypeScale.title, fontWeight: FontWeight.bold),
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
                        border: Border.all(color: t.info.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.camera_alt,
                            size: 40,
                            color: t.info,
                          ),
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
                        border: Border.all(color: t.success.withValues(alpha: 0.2)),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.photo_library,
                            size: 40,
                            color: t.success,
                          ),
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
      final bytes = await File(image.path).readAsBytes();
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$_cloudinaryCloudName/image/upload',
      );

      // Get old avatar URL before uploading new one
      final userId = supabase.auth.currentUser!.id;
      final oldProfile = await supabase
          .from('users')
          .select('avatar_url')
          .eq('id', userId)
          .single();
      final oldAvatarUrl = oldProfile['avatar_url'] as String?;

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = _cloudinaryUploadPreset
        ..fields['folder'] = 'vtrack/profiles'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            bytes,
            filename: 'profile_${DateTime.now().millisecondsSinceEpoch}.jpg',
          ),
        );

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.toBytes();
        final result = json.decode(String.fromCharCodes(responseData));
        final imageUrl = result['secure_url'];

        // Update user profile in database
        await supabase
            .from('users')
            .update({'avatar_url': imageUrl})
            .eq('id', userId);

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
      } else {
        throw Exception('Upload gagal dengan status: ${response.statusCode}');
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
          ? Center(
              child: CircularProgressIndicator(color: t.primaryAccent),
            )
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
                      style: PromotorText.display(size: 20, color: t.textPrimary),
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
                          _buildProfileSection(
                            label: 'Informasi Kepegawaian',
                            children: _buildEmploymentItems(),
                          ),
                          const SizedBox(height: 20),
                          _buildProfileSection(
                            label: 'Keamanan & Aplikasi',
                            children: _buildAppItems(),
                          ),
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
    final fullName = _userProfile?['full_name'] ?? 'Promotor';
    final nickname = ((_userProfile?['nickname'] ?? '') as String).trim();
    final displayName = nickname.isNotEmpty ? nickname : fullName;
    final avatarUrl = _userProfile?['avatar_url'] as String?;

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
                child: avatarUrl != null
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            _buildAvatarFallback(displayName),
                      )
                    : _buildAvatarFallback(displayName),
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
          displayName.toString().toUpperCase(),
          textAlign: TextAlign.center,
          style: PromotorText.display(size: 22, color: t.textPrimary),
        ),
        const SizedBox(height: 4),
        Text(
          _profileIdLabel(),
          style: PromotorText.outfit(
            size: 15,
            weight: FontWeight.w700,
            color: t.primaryAccent,
            letterSpacing: 1.4,
          ),
        ),
      ],
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

  Widget _buildProfileSection({
    required String label,
    required List<Widget> children,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            label,
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w800,
              color: t.textMutedStrong,
              letterSpacing: 1.4,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: t.surface3),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildProfileItem({
    required IconData icon,
    required String title,
    required String description,
    VoidCallback? onTap,
    Color? iconColor,
    Color? titleColor,
    bool showArrow = false,
    bool isLast = false,
  }) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.surface3),
            ),
            child: Icon(icon, color: iconColor ?? t.primaryAccent, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: titleColor ?? t.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: PromotorText.outfit(
                    size: 13,
                    color: t.textMuted,
                  ),
                ),
              ],
            ),
          ),
          if (showArrow)
            Icon(
              Icons.chevron_right_rounded,
              color: t.textMutedStrong,
              size: 20,
            ),
        ],
      ),
    );

    final child = onTap == null
        ? row
        : Material(
            color: t.background.withValues(alpha: 0),
            child: InkWell(onTap: onTap, child: row),
          );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        if (!isLast)
          Divider(
            height: 1,
            thickness: 1,
            color: t.surface2,
            indent: 68,
          ),
      ],
    );
  }

  List<Widget> _buildEmploymentItems() {
    final items = <Map<String, dynamic>>[
      {
        'icon': Icons.location_on_outlined,
        'title': 'Area Kerja',
        'description': _employmentAreaLabel(),
      },
      {
        'icon': Icons.verified_user_outlined,
        'title': 'Sator Lapangan',
        'description': (_satorName?.trim().isNotEmpty ?? false)
            ? _satorName!.trim()
            : 'Belum terhubung',
      },
      {
        'icon': Icons.calendar_today_outlined,
        'title': 'Tanggal Bergabung',
        'description': _joinedDateLabel(),
      },
    ];

    return [
      for (var i = 0; i < items.length; i++)
        _buildProfileItem(
          icon: items[i]['icon'] as IconData,
          title: items[i]['title'] as String,
          description: items[i]['description'] as String,
          isLast: i == items.length - 1,
        ),
    ];
  }

  List<Widget> _buildAppItems() {
    final bonus = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(_monthlyStats?['total_bonus'] ?? 0);

    final items = <Map<String, dynamic>>[
      {
        'icon': Icons.calendar_month_outlined,
        'title': 'Jadwal Saya',
        'description': 'Lihat jadwal bulanan dan status persetujuan',
        'onTap': () => context.go('/promotor/jadwal-bulanan'),
      },
      {
        'icon': Icons.history_rounded,
        'title': 'Aktivitas Harian',
        'description': 'Riwayat aktivitas, void, dan absensi harian',
        'onTap': () => context.go('/promotor/aktivitas-harian'),
      },
      {
        'icon': Icons.attach_money_rounded,
        'title': 'Detail Bonus',
        'description': 'Estimasi bonus bulan ini $bonus',
        'onTap': () => context.go('/promotor/bonus-detail'),
      },
      {
        'icon': Icons.palette_outlined,
        'title': 'Tema & Font',
        'description': 'Atur tema aplikasi dan pilihan font',
        'onTap': _showThemeSelector,
      },
      {
        'icon': Icons.help_outline_rounded,
        'title': 'Bantuan',
        'description': 'Kontak support dan jam operasional bantuan',
        'onTap': _showHelp,
      },
    ];

    return [
      for (var i = 0; i < items.length; i++)
        _buildProfileItem(
          icon: items[i]['icon'] as IconData,
          title: items[i]['title'] as String,
          description: items[i]['description'] as String,
          onTap: items[i]['onTap'] as VoidCallback,
          showArrow: true,
          isLast: i == items.length - 1,
        ),
    ];
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
            border: Border.all(
              color: t.danger.withValues(alpha: 0.22),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.logout_rounded,
                color: t.danger,
                size: 18,
              ),
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

  String _profileIdLabel() {
    final employeeId = _userProfile?['employee_id']?.toString().trim();
    if (employeeId != null && employeeId.isNotEmpty) {
      return 'ID: $employeeId';
    }

    final userId = _userProfile?['id']?.toString() ?? '';
    if (userId.isEmpty) return 'ID: PROMOTOR';
    final shortId = userId.substring(0, userId.length >= 8 ? 8 : userId.length);
    return 'ID: ${shortId.toUpperCase()}';
  }

  String _employmentAreaLabel() {
    final storeName = _storeInfo?['store_name']?.toString().trim();
    final area = _userProfile?['area']?.toString().trim();
    final parts = [
      if (area != null && area.isNotEmpty) area,
      if (storeName != null && storeName.isNotEmpty) storeName,
    ];
    return parts.isEmpty ? 'Belum ada penempatan toko' : parts.join(' · ');
  }

  String _joinedDateLabel() {
    final raw = _userProfile?['created_at']?.toString();
    if (raw == null || raw.isEmpty) return '-';

    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return '-';
    return DateFormat('d MMMM yyyy', 'id_ID').format(parsed.toLocal());
  }

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Bantuan'),
        content: const SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Kontak Support:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('📞 WhatsApp: 0812-3456-7890'),
              Text('📧 Email: support@vtrack.com'),
              SizedBox(height: 16),
              Text(
                'Jam Operasional:',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 8),
              Text('Senin - Jumat: 08:00 - 17:00 WITA'),
              Text('Sabtu: 08:00 - 12:00 WITA'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
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
                        style: TextStyle(
                          fontSize: AppTypeScale.title,
                          fontWeight: FontWeight.bold,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Tema',
                        style: TextStyle(
                          fontSize: AppTypeScale.body,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
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
                        style: TextStyle(
                          fontSize: AppTypeScale.body,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
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
    return RadioGroup<ThemeMode>(
      groupValue: group,
      onChanged: (val) async {
        if (val == null) return;
        await ref.read(themeModeProvider.notifier).setMode(val);
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
          title: Text(
            title,
            style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
          ),
          subtitle: Text(subtitle, style: TextStyle(color: subtitleColor)),
          trailing: Radio<ThemeMode>(value: value, activeColor: activeColor),
          onTap: () async {
            await ref.read(themeModeProvider.notifier).setMode(value);
          },
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
  }) {
    final colors = Theme.of(context).colorScheme;
    return RadioGroup<AppFontPreference>(
      groupValue: group,
      onChanged: (val) async {
        if (val == null) return;
        await ref.read(appFontPreferenceProvider.notifier).setPreference(val);
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 4,
          ),
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
            style: TextStyle(color: subtitleColor),
          ),
          trailing: Radio<AppFontPreference>(
            value: value,
            activeColor: activeColor,
          ),
          onTap: () async {
            await ref.read(appFontPreferenceProvider.notifier).setPreference(value);
          },
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
