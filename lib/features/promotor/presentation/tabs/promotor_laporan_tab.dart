import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/app_route_names.dart';
import '../../../../features/notifications/presentation/widgets/app_notification_bell_button.dart';

class _C {
  const _C(this.t);

  factory _C.of(BuildContext context) => _C(context.fieldTokens);

  final FieldThemeTokens t;

  Color get bg => t.background;
  Color get pageBg => t.background;
  Color get s1 => t.surface1;
  Color get s2 => t.surface2;
  Color get s3 => t.surface3;
  Color get s4 => t.surface4;
  Color get gold => t.primaryAccent;
  Color get goldLt => t.primaryAccentLight;
  Color get goldDim => t.primaryAccentSoft;
  Color get goldGlow => t.primaryAccentGlow;
  Color get goldDimBg => t.primaryAccentSoft.withValues(alpha: 0.2);
  Color get cream => t.textPrimary;
  Color get cream2 => t.textSecondary;
  Color get muted => t.textMuted;
  Color get muted2 => t.textMutedStrong;
  Color get green => t.success;
  Color get greenDim => t.successSoft;
  Color get red => t.danger;
  Color get redDim => t.dangerSoft;
  Color get blue => t.info;
  Color get blueDim => t.infoSoft;
  Color get purple => Color.lerp(t.info, t.primaryAccentLight, 0.55)!;
  Color get purpleDim => purple.withValues(alpha: 0.14);
}

class PromotorLaporanTab extends StatefulWidget {
  const PromotorLaporanTab({super.key});

  @override
  State<PromotorLaporanTab> createState() => _PromotorLaporanTabState();
}

class _PromotorLaporanTabState extends State<PromotorLaporanTab> {
  FieldThemeTokens get t => context.fieldTokens;
  _C get c => _C(t);
  bool _isLoading = true;

  bool _hasClockInToday = false;
  bool _hasSalesReportToday = false;
  bool _hasStockTaskToday = false;
  bool _hasPromotionToday = false;
  bool _hasFollowerToday = false;
  bool _hasAllBrandToday = false;

  String _storeName = 'King Cell';
  String _displayName = 'Promotor';

  int get _finishedTasks {
    int count = 0;
    if (_hasClockInToday) count++;
    if (_hasSalesReportToday) count++;
    if (_hasStockTaskToday) count++;
    if (_hasPromotionToday) count++;
    if (_hasFollowerToday) count++;
    if (_hasAllBrandToday) count++;
    return count;
  }

  final int _totalTasks = 6;

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final nickname = '${metadata['nickname'] ?? ''}'.trim();
    final fullName =
        '${metadata['full_name'] ?? metadata['name'] ?? 'Promotor'}'.trim();
    _displayName = fullName.isNotEmpty
        ? fullName
        : (nickname.isNotEmpty ? nickname : 'Promotor');
    _loadTodayActivities();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final storeRows = await Supabase.instance.client
          .from('assignments_promotor_store')
          .select('store_id, stores(store_name)')
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1);
      final assignments = List<Map<String, dynamic>>.from(storeRows);
      final storeData = assignments.isNotEmpty ? assignments.first : null;
      final userRow = await Supabase.instance.client
          .from('users')
          .select('full_name, nickname')
          .eq('id', userId)
          .maybeSingle();
      final nickname = '${userRow?['nickname'] ?? ''}'.trim();
      final fullName = '${userRow?['full_name'] ?? 'Promotor'}'.trim();
      final displayName = fullName.isNotEmpty ? fullName : nickname;

      if (!mounted) return;
      setState(() {
        _displayName = displayName.isEmpty ? 'Promotor' : displayName;
        if (storeData != null && storeData['stores'] != null) {
          _storeName = storeData['stores']['store_name'] ?? 'Toko';
        }
      });
    } catch (e) {
      debugPrint('Error loader user profile on laporan tab: $e');
    }
  }

  Future<void> _loadTodayActivities() async {
    setState(() => _isLoading = true);
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final snapshot = await Supabase.instance.client.rpc(
        'get_promotor_activity_snapshot',
        params: {'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now())},
      );
      final payload = Map<String, dynamic>.from(
        (snapshot as Map?) ?? const <String, dynamic>{},
      );
      final sellOutData = _asListOfMaps(payload['sell_out_data']);
      final stockInputData = _asListOfMaps(payload['stock_input_data']);
      final promotionData = _asListOfMaps(payload['promotion_data']);
      final followerData = _asListOfMaps(payload['follower_data']);

      if (mounted) {
        setState(() {
          _hasClockInToday = _asMap(payload['attendance_data']) != null;
          _hasSalesReportToday = sellOutData.isNotEmpty;
          _hasStockTaskToday =
              _asMap(payload['stock_validation_data']) != null ||
              stockInputData.isNotEmpty;
          _hasPromotionToday = promotionData.isNotEmpty;
          _hasFollowerToday = followerData.isNotEmpty;
          _hasAllBrandToday = _asMap(payload['all_brand_data']) != null;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading activities: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => row.map((key, val) => MapEntry(key.toString(), val)))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: c.pageBg,
        body: Center(child: CircularProgressIndicator(color: c.gold)),
      );
    }

    return Scaffold(
      backgroundColor: c.pageBg,
      body: RefreshIndicator(
        onRefresh: _loadTodayActivities,
        color: c.gold,
        backgroundColor: c.s1,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(top: 12, bottom: 85),
          children: [
            _buildHeader(),
            _buildBonusHeroCard(),
            _buildTimelineSection(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final todayLabel = DateFormat(
      'EEEE, d MMMM yyyy',
      'id_ID',
    ).format(DateTime.now());

    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: BoxDecoration(
        // Gradient subtle di header area
        gradient: LinearGradient(
          colors: [c.t.heroGradientStart, c.t.background],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(bottom: BorderSide(color: c.t.divider, width: 1.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Dot gold dengan glow
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: c.gold,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: c.goldGlow,
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'WORKPALCE',
                      style: AppTextStyle.bodyMd(
                        c.gold,
                        weight: FontWeight.w700,
                        letterSpacing: 1.4,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  _displayName,
                  style: AppFontTokens.resolve(
                    AppFontRole.display,
                    fontSize: AppTypeScale.heading,
                    fontWeight: FontWeight.w900,
                    color: c.cream,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$_storeName · $todayLabel',
                  style: AppTextStyle.bodySm(c.muted),
                ),
              ],
            ),
          ),
          Container(
            width: 40,
            height: 40,
            margin: const EdgeInsets.only(top: 4),
            alignment: Alignment.center,
            child: AppNotificationBellButton(
              backgroundColor: c.t.surface2,
              borderColor: c.t.surface3,
              iconColor: c.muted,
              badgeColor: c.red,
              badgeTextColor: c.t.textOnAccent,
              routePath: '/promotor/notifications',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusHeroCard() {
    return GestureDetector(
      onTap: () => context.pushNamed(AppRouteNames.promotorBonusDetail),
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 12, 18, 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [c.t.heroGradientStart, c.t.heroGradientEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: c.gold.withValues(alpha: 0.25)),
          boxShadow: [
            BoxShadow(
              color: c.gold.withValues(alpha: 0.06),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              top: -10,
              left: 0,
              right: 0,
              child: Container(
                height: 1.5,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      c.gold.withValues(alpha: 0),
                      c.gold.withValues(alpha: 0.6),
                      c.gold.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
            Positioned(
              top: -24,
              right: -24,
              child: Container(
                width: 110,
                height: 110,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      c.gold.withValues(alpha: 0.12),
                      c.gold.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.7],
                  ),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Detail Bonus',
                            style: AppTextStyle.titleMd(
                              c.gold,
                              weight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: c.gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: c.gold.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Icon(
                        Icons.workspace_premium_rounded,
                        color: c.gold,
                        size: 20,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineSection() {
    return Padding(
      padding: const EdgeInsets.only(left: 22, right: 20, top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGroupLabel('WAJIB HARIAN'),

          _TimelineItem(
            isFirst: true,
            icon: Icons.camera_alt_outlined,
            dotType: _hasClockInToday ? _DotType.done : _DotType.red,
            title: 'Foto Kehadiran',
            titleColor: _hasClockInToday ? c.green : c.cream2,
            badge: _hasClockInToday
                ? _StatusBadge.done('✓ Sudah', c)
                : _StatusBadge.red('Belum', c),
            onTap: () => context.push('/promotor/clock-in'),
          ),

          _TimelineItem(
            icon: Icons.move_to_inbox,
            dotType: _hasStockTaskToday ? _DotType.done : _DotType.red,
            title: 'Input Stok',
            titleColor: _hasStockTaskToday ? c.green : c.cream2,
            badge: _hasStockTaskToday
                ? _StatusBadge.done('✓ Selesai', c)
                : _StatusBadge.red('Belum', c),
            onTap: () => context.push('/promotor/stock-input'),
          ),

          _TimelineItem(
            icon: Icons.point_of_sale,
            dotType: _hasSalesReportToday ? _DotType.done : _DotType.gold,
            title: 'Input Penjualan',
            titleColor: _hasSalesReportToday ? c.green : c.cream2,
            badge: _hasSalesReportToday
                ? _StatusBadge.done('✓ Terinput', c)
                : _StatusBadge.red('Belum', c),
            onTap: () => context.push('/promotor/sell-out'),
          ),

          _TimelineItem(
            icon: Icons.inventory_2_outlined,
            dotType: _hasStockTaskToday ? _DotType.done : _DotType.gold,
            title: 'Stok Toko',
            titleColor: _hasStockTaskToday ? c.green : c.cream2,
            badge: _hasStockTaskToday
                ? _StatusBadge.done('✓ Selesai', c)
                : _StatusBadge.red('Belum', c),
            onTap: () => context.push('/promotor/stok-toko'),
          ),

          _TimelineItem(
            icon: Icons.account_balance_wallet_outlined,
            dotType: _DotType.gold,
            title: 'VAST Finance',
            badge: _StatusBadge.dim('Buka', c),
            onTap: () => context.pushNamed('promotor-vast'),
          ),

          _TimelineItem(
            icon: Icons.insights_outlined,
            dotType: _DotType.blue,
            title: 'Sell Out Insight',
            badge: _StatusBadge.dim('Analisa', c),
            onTap: () =>
                context.pushNamed(AppRouteNames.promotorSelloutInsight),
          ),

          const SizedBox(height: 8),
          _buildGroupLabel('LAPORAN TAMBAHAN'),

          _TimelineItem(
            icon: Icons.assignment_outlined,
            dotType: _finishedTasks == _totalTasks
                ? _DotType.done
                : _DotType.gold,
            title: 'Laporan Aktivitas',
            titleColor: _finishedTasks == _totalTasks ? c.green : c.cream2,
            badge: _finishedTasks == _totalTasks
                ? _StatusBadge.done('$_finishedTasks/$_totalTasks', c)
                : _StatusBadge.gold('$_finishedTasks/$_totalTasks', c),
            onTap: () => context.pushNamed(AppRouteNames.aktivitasHarian),
          ),

          _TimelineItem(
            icon: Icons.campaign_outlined,
            dotType: _hasPromotionToday ? _DotType.done : _DotType.red,
            title: 'Lapor Promosi',
            titleColor: _hasPromotionToday ? c.green : c.cream2,
            badge: _hasPromotionToday
                ? _StatusBadge.done('✓ Terkirim', c)
                : _StatusBadge.red('Belum', c),
            onTap: () => context.push('/promotor/laporan-promosi'),
          ),

          _TimelineItem(
            icon: Icons.group_add_outlined,
            dotType: _hasFollowerToday ? _DotType.done : _DotType.blue,
            title: 'Lapor Follower',
            titleColor: _hasFollowerToday ? c.green : c.cream2,
            badge: _hasFollowerToday
                ? _StatusBadge.done('✓ Terkirim', c)
                : _StatusBadge.red('Belum', c),
            onTap: () => context.push('/promotor/laporan-follower'),
          ),

          _TimelineItem(
            icon: Icons.hub_outlined,
            dotType: _hasAllBrandToday ? _DotType.done : _DotType.purple,
            title: 'Lapor AllBrand',
            titleColor: _hasAllBrandToday ? c.green : c.cream2,
            badge: _hasAllBrandToday
                ? _StatusBadge.done('✓ Terkirim', c)
                : _StatusBadge.red('Belum', c),
            onTap: () => context.push('/promotor/laporan-allbrand'),
          ),

          const SizedBox(height: 8),
          _buildGroupLabel('JADWAL & PENORMALAN'),

          _TimelineItem(
            icon: Icons.calendar_month,
            dotType: _DotType.done,
            title: 'Jadwal Bulanan',
            titleColor: c.green,
            badge: _StatusBadge.done('✓ Disetujui', c),
            onTap: () => context.push('/promotor/jadwal-bulanan'),
          ),

          _TimelineItem(
            icon: Icons.qr_code_scanner,
            dotType: _DotType.purple,
            title: 'Penormalan IMEI',
            badge: _StatusBadge.dim('10 pending', c),
            onTap: () => context.push('/promotor/imei-normalization'),
          ),

          _TimelineItem(
            icon: Icons.people_alt_outlined,
            dotType: _DotType.blue,
            title: 'Data Konsumen',
            badge: _StatusBadge.dim('Riwayat', c),
            isLast: true,
            onTap: () => context.pushNamed(AppRouteNames.promotorCustomerData),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 10, top: 4),
      child: Row(
        children: [
          // Accent dot group label
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(color: c.muted2, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            text,
            style: AppTextStyle.bodyMd(
              c.muted2,
              weight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [c.t.divider, c.t.divider.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DotType { done, gold, blue, red, purple }

class _StatusBadge {
  final String text;
  final Color color;
  final Color bg;
  final Color border;

  _StatusBadge({
    required this.text,
    required this.color,
    required this.bg,
    required this.border,
  });

  factory _StatusBadge.red(String text, _C c) => _StatusBadge(
    text: text,
    color: c.red,
    bg: c.redDim,
    border: c.red.withValues(alpha: 0.2),
  );
  factory _StatusBadge.done(String text, _C c) => _StatusBadge(
    text: text,
    color: c.green,
    bg: c.greenDim,
    border: c.green.withValues(alpha: 0.2),
  );
  factory _StatusBadge.gold(String text, _C c) => _StatusBadge(
    text: text,
    color: c.gold,
    bg: c.goldDim,
    border: c.gold.withValues(alpha: 0.2),
  );
  factory _StatusBadge.dim(String text, _C c) =>
      _StatusBadge(text: text, color: c.muted, bg: c.s2, border: c.s3);
}

class _TimelineItem extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final IconData icon;
  final _DotType dotType;
  final String title;
  final Color? titleColor;
  final _StatusBadge badge;

  final VoidCallback onTap;

  const _TimelineItem({
    this.isFirst = false,
    this.isLast = false,
    required this.icon,
    required this.dotType,
    required this.title,
    this.titleColor,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
    final isLightMode = Theme.of(context).brightness == Brightness.light;
    final warmSurface = isLightMode
        ? Color.lerp(c.s1, c.goldDim, 0.12) ?? c.s1
        : c.s1;
    final warmSurfaceAlt = isLightMode
        ? Color.lerp(c.bg, c.goldDim, 0.08) ?? c.bg
        : c.s2;
    final warmBorder = isLightMode
        ? Color.lerp(c.s3, c.gold, 0.12) ?? c.s3
        : c.s3;

    BoxDecoration menuCardDecoration() {
      if (isLightMode) {
        return BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              warmSurface,
              Color.lerp(warmSurface, c.gold, 0.045) ?? warmSurface,
              warmSurfaceAlt,
            ],
            stops: const [0, 0.6, 1],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: warmBorder),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.04),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: c.gold.withValues(alpha: 0.05),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        );
      }

      return BoxDecoration(
        color: warmSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: warmBorder),
      );
    }

    Color dotBg = c.s2;
    Color dotBorder = c.s4;
    Color iconColor = c.muted;

    switch (dotType) {
      case _DotType.done:
        dotBg = c.greenDim;
        dotBorder = c.green.withValues(alpha: 0.35);
        iconColor = c.green;
        break;
      case _DotType.gold:
        dotBg = c.goldDimBg;
        dotBorder = c.gold.withValues(alpha: 0.35);
        iconColor = c.gold;
        break;
      case _DotType.blue:
        dotBg = c.blueDim;
        dotBorder = c.blue.withValues(alpha: 0.3);
        iconColor = c.blue;
        break;
      case _DotType.red:
        dotBg = c.redDim;
        dotBorder = c.red.withValues(alpha: 0.25);
        iconColor = c.red;
        break;
      case _DotType.purple:
        dotBg = c.purpleDim;
        dotBorder = c.purple.withValues(alpha: 0.3);
        iconColor = c.purple;
        break;
    }

    return Container(
      margin: EdgeInsets.only(bottom: isLast ? 4 : 9),
      decoration: menuCardDecoration(),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: dotBg,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: dotBorder, width: 1.3),
                  ),
                  child: Icon(icon, color: iconColor, size: 16),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyle.bodyMd(
                      titleColor ?? c.cream2,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: badge.bg,
                    border: Border.all(color: badge.border),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    badge.text,
                    style: AppTextStyle.micro(
                      badge.color,
                      weight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
