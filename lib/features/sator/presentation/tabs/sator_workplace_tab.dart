// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/features/notifications/presentation/widgets/app_notification_bell_button.dart';
import '../../../../core/utils/avatar_refresh_bus.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../ui/promotor/promotor.dart';

class SatorWorkplaceTab extends StatefulWidget {
  const SatorWorkplaceTab({super.key});

  @override
  State<SatorWorkplaceTab> createState() => _SatorWorkplaceTabState();
}

class _SatorWorkplaceTabState extends State<SatorWorkplaceTab> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  int _attendanceMissing = 0;
  int _schedulePendingCount = 0;
  int _permissionPendingCount = 0;

  bool _visitingDone = false;

  int _sellInPendingCount = 0;

  int _imeiPendingCount = 0;

  bool get _isLightMode => Theme.of(context).brightness == Brightness.light;
  Color get _warmSurface => _isLightMode
      ? Color.lerp(t.surface1, t.primaryAccentSoft, 0.14) ?? t.surface1
      : t.surface1;
  Color get _warmSurfaceAlt => _isLightMode
      ? Color.lerp(t.background, t.primaryAccentSoft, 0.1) ?? t.background
      : t.surface2;
  Color get _warmBorder => _isLightMode
      ? Color.lerp(t.surface3, t.primaryAccent, 0.12) ?? t.surface3
      : t.surface3;

  @override
  void initState() {
    super.initState();
    _loadData();
    avatarRefreshTick.addListener(_handleAvatarRefresh);
  }

  void _handleAvatarRefresh() {
    if (!mounted) return;
    _loadData();
  }

  @override
  void dispose() {
    avatarRefreshTick.removeListener(_handleAvatarRefresh);
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final authUser = _supabase.auth.currentUser;
      Map<String, dynamic> snapshot = <String, dynamic>{};
      Map<String, dynamic> liveProfile = <String, dynamic>{};
      Map<String, dynamic> homeProfile = <String, dynamic>{};

      try {
        final snapshotRaw = await _supabase.rpc(
          'get_sator_workplace_snapshot',
          params: {
            'p_sator_id': userId,
            'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          },
        );
        if (snapshotRaw is Map) {
          snapshot = Map<String, dynamic>.from(snapshotRaw);
        }
      } catch (_) {}

      try {
        final profileRaw = await _supabase.rpc('get_my_profile_snapshot');
        if (profileRaw is Map) {
          liveProfile = Map<String, dynamic>.from(profileRaw);
        }
      } catch (_) {}

      try {
        final homeRaw = await _supabase.rpc(
          'get_sator_home_snapshot',
          params: <String, dynamic>{'p_sator_id': userId},
        );
        if (homeRaw is Map) {
          final homeMap = Map<String, dynamic>.from(homeRaw);
          homeProfile = Map<String, dynamic>.from(
            homeMap['profile'] as Map? ?? const <String, dynamic>{},
          );
        }
      } catch (_) {}

      final authMetadata = Map<String, dynamic>.from(
        authUser?.userMetadata ?? const <String, dynamic>{},
      );
      final authProfile = <String, dynamic>{
        'full_name': authMetadata['full_name'] ?? authMetadata['name'],
        'nickname': authMetadata['nickname'] ?? authMetadata['display_name'],
        'area': authMetadata['area'],
        'avatar_url': authUser?.userMetadata?['avatar_url'],
      };
      final mergedProfile = <String, dynamic>{
        ...authProfile,
        ...homeProfile,
        ...Map<String, dynamic>.from(snapshot['profile'] as Map? ?? const {}),
        ...liveProfile,
      };

      if (mounted) {
        setState(() {
          _profile = mergedProfile;
          _attendanceMissing = _toInt(snapshot['attendance_missing']);
          _schedulePendingCount = _toInt(snapshot['schedule_pending_count']);
          _permissionPendingCount = _toInt(
            snapshot['permission_pending_count'],
          );
          _visitingDone = snapshot['visiting_done'] == true;
          _sellInPendingCount = _toInt(snapshot['sell_in_pending_count']);
          _imeiPendingCount = _toInt(snapshot['imei_pending_count']);
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: t.primaryAccent,
      child: Container(
        color: t.background,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(0, 10, 0, 120),
          children: [
            _buildHeader(),
            _buildHeaderControls(),
            if (_isLoading)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  color: t.primaryAccent,
                  backgroundColor: t.surface3,
                ),
              ),
            _buildTimeline(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final rawFullName = '${_profile?['full_name'] ?? ''}'.trim();
    final rawNickname = '${_profile?['nickname'] ?? ''}'.trim();
    final fullName = rawFullName.isNotEmpty
        ? rawFullName
        : (rawNickname.isNotEmpty ? rawNickname : 'SATOR');
    final area = '${_profile?['area'] ?? '-'}';
    final avatarUrl = '${_profile?['avatar_url'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [t.surface1, t.surface2]
              : [_warmSurface, _warmSurfaceAlt],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _warmBorder),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? t.background.withValues(alpha: 0.16)
                : const Color(0xFF000000).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Workplace',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.display(
                    size: 20,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              _buildHeaderIconButton(),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.primaryAccentGlow),
                ),
                child: UserAvatar(
                  key: ValueKey(avatarUrl),
                  avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
                  fullName: fullName,
                  radius: 22,
                  showBorder: false,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fullName,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.display(
                        size: 24,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(
                          area.isNotEmpty && area != '-' ? area : 'Area: -',
                          style: PromotorText.outfit(
                            size: 12,
                            weight: FontWeight.w700,
                            color: t.primaryAccent,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderControls() {
    final dateLabel = DateFormat(
      'EEEE, d MMM yyyy',
      'id_ID',
    ).format(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: _buildDateBadge(dateLabel),
      ),
    );
  }

  Widget _buildDateBadge(String label, {double fontSize = 11}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: _warmSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _warmBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_rounded, size: 11, color: t.primaryAccent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: fontSize,
                weight: FontWeight.w700,
                color: t.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton() {
    return AppNotificationBellButton(
      backgroundColor: _warmSurface,
      borderColor: _warmBorder,
      iconColor: t.textMuted,
      badgeColor: t.danger,
      badgeTextColor: t.textOnAccent,
      routePath: '/sator/notifications',
    );
  }

  BoxDecoration _menuCardDecoration() {
    final tone = t.primaryAccent;
    if (_isLightMode) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _warmSurface,
            Color.lerp(_warmSurface, tone, 0.045) ?? _warmSurface,
            _warmSurfaceAlt,
          ],
          stops: const [0, 0.6, 1],
        ),
        borderRadius: BorderRadius.circular(t.radiusMd),
        border: Border.all(color: _warmBorder),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: tone.withValues(alpha: 0.05),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      );
    }

    return BoxDecoration(
      color: _warmSurface,
      borderRadius: BorderRadius.circular(t.radiusMd),
      border: Border.all(color: _warmBorder),
    );
  }

  Widget _buildTimeline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGroupTitle('Prioritas Utama'),
          _buildTimelineItem(
            title: 'Sell Out Insight',
            badge: 'Monitor tim',
            badgeColor: t.info,
            dotColor: t.info,
            icon: Icons.insights_rounded,
            onTap: () => context.push('/sator/sell-out-insight'),
          ),
          _buildTimelineItem(
            title: 'Sell In',
            badge: _sellInPendingCount > 0
                ? '$_sellInPendingCount pending'
                : '✓ Aman',
            badgeColor: _sellInPendingCount > 0 ? t.primaryAccent : t.success,
            dotColor: _sellInPendingCount > 0 ? t.primaryAccent : t.success,
            icon: Icons.inventory_2_outlined,
            onTap: () => context.push('/sator/sell-in'),
          ),
          _buildTimelineItem(
            title: 'VAST Finance',
            badge: 'Monitor tim',
            badgeColor: t.primaryAccent,
            dotColor: t.primaryAccent,
            icon: Icons.account_balance_wallet_outlined,
            onTap: () => context.pushNamed('sator-vast'),
          ),
          _buildTimelineItem(
            title: 'Aktivitas Tim',
            badge: _attendanceMissing > 0
                ? '$_attendanceMissing belum absen'
                : '✓ Lengkap',
            badgeColor: _attendanceMissing > 0 ? t.danger : t.success,
            dotColor: _attendanceMissing > 0 ? t.danger : t.success,
            icon: Icons.people_outline,
            onTap: () => context.push('/sator/aktivitas-tim'),
          ),
          const SizedBox(height: 8),
          _buildGroupTitle('Operasional Harian'),
          _buildTimelineItem(
            title: 'Visiting',
            badge: _visitingDone ? '✓ Selesai' : 'Pending',
            badgeColor: _visitingDone ? t.success : t.danger,
            dotColor: _visitingDone ? t.success : t.danger,
            icon: _visitingDone ? Icons.check : Icons.location_on_outlined,
            onTap: () => context.push('/sator/visiting'),
          ),
          _buildTimelineItem(
            title: 'Penormalan IMEI',
            badge: _imeiPendingCount > 0
                ? '$_imeiPendingCount pending'
                : '✓ Aman',
            badgeColor: _imeiPendingCount > 0 ? t.warning : t.success,
            dotColor: Color.lerp(t.info, t.primaryAccentLight, 0.55)!,
            icon: Icons.qr_code_2,
            onTap: () => context.push('/sator/imei-normalisasi'),
          ),
          const SizedBox(height: 8),
          _buildTimelineItem(
            title: 'Import Stok Excel',
            badge: 'Operasional',
            badgeColor: t.primaryAccent,
            dotColor: t.primaryAccent,
            icon: Icons.upload_file_rounded,
            onTap: () => context.push('/sator/import-stok'),
          ),
          const SizedBox(height: 8),
          _buildGroupTitle('Laporan & Approval'),
          _buildTimelineItem(
            title: 'AllBrand',
            badge: 'Rekap tim',
            badgeColor: t.textMuted,
            dotColor: Color.lerp(t.info, t.primaryAccentLight, 0.55)!,
            icon: Icons.bar_chart,
            onTap: () => context.push('/sator/allbrand'),
          ),
          _buildTimelineItem(
            title: 'Data Konsumen',
            badge: 'Riwayat tim',
            badgeColor: t.info,
            dotColor: t.info,
            icon: Icons.people_alt_outlined,
            onTap: () => context.push('/sator/data-konsumen'),
          ),
          _buildTimelineItem(
            title: 'KPI Monitoring',
            badge: 'Bulanan',
            badgeColor: t.info,
            dotColor: t.info,
            icon: Icons.query_stats_rounded,
            onTap: () => context.pushNamed('sator-kpi-bonus'),
          ),
          _buildTimelineItem(
            title: 'Export',
            badge: 'Download',
            badgeColor: t.textMuted,
            dotColor: t.info,
            icon: Icons.file_download,
            onTap: () => context.push('/sator/export'),
          ),
          _buildTimelineItem(
            title: 'Approve Jadwal',
            badge: _schedulePendingCount > 0
                ? '$_schedulePendingCount pending'
                : '✓ Aman',
            badgeColor: _schedulePendingCount > 0 ? t.primaryAccent : t.success,
            dotColor: _schedulePendingCount > 0 ? t.primaryAccent : t.success,
            icon: Icons.calendar_month,
            onTap: () => context.push('/sator/jadwal'),
          ),
          _buildTimelineItem(
            title: 'Approval Perijinan',
            badge: _permissionPendingCount > 0
                ? '$_permissionPendingCount pending'
                : '✓ Aman',
            badgeColor: _permissionPendingCount > 0 ? t.warning : t.success,
            dotColor: _permissionPendingCount > 0 ? t.warning : t.success,
            icon: Icons.assignment_turned_in_outlined,
            onTap: () => context.push('/sator/permission-approval'),
            showLine: false,
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 10, top: 4),
      child: Row(
        children: [
          Text(
            title,
            style: PromotorText.outfit(
              size: 14,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: t.surface2)),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required String title,
    required String badge,
    required Color badgeColor,
    required Color dotColor,
    required IconData icon,
    VoidCallback? onTap,
    bool showLine = true,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: _menuCardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(t.radiusMd),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: dotColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: dotColor.withValues(alpha: 0.28),
                      width: 1.2,
                    ),
                  ),
                  child: Icon(icon, color: dotColor, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: PromotorText.outfit(
                      size: 14,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildBadge(badge, badgeColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 8,
          weight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }
}
