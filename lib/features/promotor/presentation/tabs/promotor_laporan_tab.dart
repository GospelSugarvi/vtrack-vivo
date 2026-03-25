import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/foundation.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/app_route_names.dart';

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
      final displayName = nickname.isNotEmpty ? nickname : fullName;

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

      final today = DateTime.now();
      final todayStr = DateFormat('yyyy-MM-dd').format(today);
      final tomorrowStr = DateFormat(
        'yyyy-MM-dd',
      ).format(today.add(const Duration(days: 1)));

      final clockInReq = Supabase.instance.client
          .from('attendance')
          .select('id')
          .eq('user_id', userId)
          .gte('created_at', todayStr)
          .lt('created_at', tomorrowStr)
          .limit(1);

      final salesReq = Supabase.instance.client
          .from('sales_sell_out')
          .select('id')
          .eq('promotor_id', userId)
          .gte('transaction_date', todayStr)
          .lt('transaction_date', tomorrowStr)
          .limit(1);

      final validateReq = Supabase.instance.client
          .from('stock_validations')
          .select('id')
          .eq('promotor_id', userId)
          .gte('validation_date', todayStr)
          .lt('validation_date', tomorrowStr)
          .limit(1);
      final stockInputReq = Supabase.instance.client
          .from('stock_movement_log')
          .select('id')
          .eq('moved_by', userId)
          .inFilter('movement_type', ['initial', 'transfer_in', 'adjustment'])
          .gte('moved_at', todayStr)
          .lt('moved_at', tomorrowStr)
          .limit(1);
      final promotionReq = Supabase.instance.client
          .from('promotion_reports')
          .select('id')
          .eq('promotor_id', userId)
          .gte('created_at', todayStr)
          .lt('created_at', tomorrowStr)
          .limit(1);
      final followerReq = Supabase.instance.client
          .from('follower_reports')
          .select('id')
          .eq('promotor_id', userId)
          .gte('created_at', todayStr)
          .lt('created_at', tomorrowStr)
          .limit(1);
      final allBrandReq = Supabase.instance.client
          .from('allbrand_reports')
          .select('id')
          .eq('promotor_id', userId)
          .gte('report_date', todayStr)
          .lt('report_date', tomorrowStr)
          .limit(1);

      final results = await Future.wait([
        clockInReq,
        salesReq,
        validateReq,
        stockInputReq,
        promotionReq,
        followerReq,
        allBrandReq,
      ]);

      if (mounted) {
        setState(() {
          _hasClockInToday = (results[0] as List).isNotEmpty;
          _hasSalesReportToday = (results[1] as List).isNotEmpty;
          _hasStockTaskToday =
              (results[2] as List).isNotEmpty || (results[3] as List).isNotEmpty;
          _hasPromotionToday = (results[4] as List).isNotEmpty;
          _hasFollowerToday = (results[5] as List).isNotEmpty;
          _hasAllBrandToday = (results[6] as List).isNotEmpty;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading activities: $e');
      if (mounted) setState(() => _isLoading = false);
    }
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
            _buildProgressCard(),
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
          // Notification bell lebih premium
          Container(
            width: 38,
            height: 38,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: c.t.surface1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: c.t.surface3),
              boxShadow: [
                BoxShadow(
                  color: c.t.shellBackground.withValues(alpha: 0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  color: c.muted,
                  size: 19,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: c.red,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.t.surface1, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: c.red.withValues(alpha: 0.5),
                          blurRadius: 4,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    double pct = _totalTasks > 0 ? (_finishedTasks / _totalTasks) * 100 : 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 14, 18, 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
            color: c.gold.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Shine garis di atas
          Positioned(
            top: -14,
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
          // Glow radial kanan atas
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 140,
              height: 140,
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
          // Glow radial kiri bawah
          Positioned(
            bottom: -20,
            left: -20,
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    c.t.primaryAccentLight.withValues(alpha: 0.08),
                    c.gold.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Column(
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Progress hari ini',
                        style: AppTextStyle.bodyMd(c.muted),
                      ),
                      const SizedBox(height: 3),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: '$_finishedTasks ',
                              style: AppTextStyle.headingSm(
                                c.gold,
                                weight: FontWeight.bold,
                              ),
                            ),
                            TextSpan(
                              text: 'dari $_totalTasks selesai',
                              style: AppTextStyle.bodyMd(
                                c.cream2,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${pct.toInt()}%',
                        style: AppTextStyle.heroNum(
                          pct >= 100 ? c.green : c.gold,
                          weight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'SELESAI',
                        style: AppTextStyle.micro(
                          c.muted,
                          weight: FontWeight.w600,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 6,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: c.t.surface3,
                  borderRadius: BorderRadius.circular(100),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: pct / 100,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [c.gold, c.goldLt]),
                      borderRadius: BorderRadius.circular(100),
                      boxShadow: [
                        BoxShadow(
                          color: c.goldGlow,
                          blurRadius: 10,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
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
            chips: [
              _MetaChip(icon: Icons.gps_fixed, text: 'GPS aktif'),
              _MetaChip(icon: Icons.portrait, text: 'Foto selfie'),
            ],
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
            chips: _hasStockTaskToday
                ? [_MetaChip(text: 'Input tersimpan', isGreen: true)]
                : [_MetaChip(text: 'Fresh · Chip · Display')],
            onTap: () => context.push('/promotor/stock-input'),
          ),

          _TimelineItem(
            icon: Icons.inventory_2_outlined,
            dotType: _hasStockTaskToday ? _DotType.done : _DotType.gold,
            title: 'Stok Toko',
            titleColor: _hasStockTaskToday ? c.green : c.cream2,
            badge: _hasStockTaskToday
                ? _StatusBadge.done('✓ Selesai', c)
                : _StatusBadge.red('Belum', c),
            chips: _hasStockTaskToday
                ? []
                : [_MetaChip(text: '16 item perlu dicek', isHighlight: true)],
            onTap: () => context.push('/promotor/stok-toko'),
          ),

          _TimelineItem(
            icon: Icons.account_balance_wallet_outlined,
            dotType: _DotType.gold,
            title: 'VAST Finance',
            badge: _StatusBadge.dim('Buka', c),
            chips: [
              _MetaChip(text: 'Input'),
              _MetaChip(text: 'Pending'),
              _MetaChip(text: 'History'),
              _MetaChip(text: 'Reminder'),
            ],
            onTap: () => context.pushNamed('promotor-vast'),
          ),

          _TimelineItem(
            icon: Icons.point_of_sale,
            dotType: _hasSalesReportToday ? _DotType.done : _DotType.gold,
            title: 'Lapor Jual',
            titleColor: _hasSalesReportToday ? c.green : c.cream2,
            badge: _hasSalesReportToday
                ? _StatusBadge.done('✓ Terinput', c)
                : _StatusBadge.red('Belum', c),
            onTap: () => context.push('/promotor/sell-out'),
          ),

          const SizedBox(height: 8),
          _buildGroupLabel('JADWAL & PENORMALAN'),

          _TimelineItem(
            icon: Icons.calendar_month,
            dotType: _DotType.done,
            title: 'Jadwal Bulanan',
            titleColor: c.green,
            badge: _StatusBadge.done('✓ Disetujui', c),
            chips: [
              _MetaChip(text: 'Submit ke SATOR', isGreen: true),
              _MetaChip(text: 'Buka Jadwal', isGreen: true),
            ],
            onTap: () => context.push('/promotor/jadwal-bulanan'),
          ),

          _TimelineItem(
            icon: Icons.qr_code_scanner,
            dotType: _DotType.purple,
            title: 'Penormalan IMEI',
            badge: _StatusBadge.dim('10 pending', c),
            chips: [_MetaChip(text: '10 perlu dikirim', isHighlight: true)],
            onTap: () => context.push('/promotor/imei-normalization'),
          ),

          const SizedBox(height: 8),
          _buildGroupLabel('LAPORAN TAMBAHAN'),

          _TimelineItem(
            icon: Icons.assignment_outlined,
            dotType: _finishedTasks == _totalTasks ? _DotType.done : _DotType.gold,
            title: 'Laporan Aktivitas',
            titleColor: _finishedTasks == _totalTasks ? c.green : c.cream2,
            badge: _finishedTasks == _totalTasks
                ? _StatusBadge.done('$_finishedTasks/$_totalTasks', c)
                : _StatusBadge.gold('$_finishedTasks/$_totalTasks', c),
            onTap: () => context.pushNamed(AppRouteNames.aktivitasHarian),
          ),

          _TimelineItem(
            icon: Icons.account_balance_wallet_outlined,
            dotType: _DotType.done,
            title: 'Detail Bonus',
            badge: _StatusBadge.gold('34%', c),
            hasProgressBar: true,
            progressValue: 0.34,
            progressLabelLeft: 'Rp 1.000.000',
            progressLabelRight: 'dari Rp 3.000.000',
            onTap: () => context.pushNamed(AppRouteNames.promotorBonusDetail),
          ),

          _TimelineItem(
            icon: Icons.campaign_outlined,
            dotType: _hasPromotionToday ? _DotType.done : _DotType.red,
            title: 'Lapor Promosi',
            titleColor: _hasPromotionToday ? c.green : c.cream2,
            badge: _hasPromotionToday
                ? _StatusBadge.done('✓ Terkirim', c)
                : _StatusBadge.red('Belum', c),
            chips: [
              _MetaChip(text: 'TikTok'),
              _MetaChip(text: 'Instagram'),
            ],
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
            chips: [_MetaChip(text: 'Samsung · OPPO · Xiaomi')],
            isLast: true,
            onTap: () => context.push('/promotor/laporan-allbrand'),
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
            style: AppTextStyle.micro(
              c.muted2,
              weight: FontWeight.w800,
              letterSpacing: 1.6,
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

class _MetaChip {
  final String text;
  final IconData? icon;
  final bool isHighlight;
  final bool isGreen;

  _MetaChip({
    required this.text,
    this.icon,
    this.isHighlight = false,
    this.isGreen = false,
  });
}

class _TimelineItem extends StatelessWidget {
  final bool isFirst;
  final bool isLast;
  final IconData icon;
  final _DotType dotType;
  final String title;
  final Color? titleColor;
  final _StatusBadge badge;
  final List<_MetaChip>? chips;

  final bool hasProgressBar;
  final double progressValue;
  final String progressLabelLeft;
  final String progressLabelRight;

  final VoidCallback onTap;

  const _TimelineItem({
    this.isFirst = false,
    this.isLast = false,
    required this.icon,
    required this.dotType,
    required this.title,
    this.titleColor,
    required this.badge,
    this.chips,
    this.hasProgressBar = false,
    this.progressValue = 0,
    this.progressLabelLeft = '',
    this.progressLabelRight = '',
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = _C.of(context);
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

    return InkWell(
      onTap: onTap,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Left Column: Dot & Line
            SizedBox(
              width: 32,
              child: Column(
                children: [
                  const SizedBox(height: 3),
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: dotBg,
                      shape: BoxShape.circle,
                      border: Border.all(color: dotBorder, width: 1.5),
                    ),
                    child: Icon(icon, color: iconColor, size: 15),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 1,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        color: c.s3.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
            // Right Column: Content
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 12,
                  bottom: isLast ? 4 : 16,
                  top: 4,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: AppTextStyle.bodyMd(
                              titleColor ?? c.cream2,
                              weight: FontWeight.w700,
                            ),
                          ),
                        ),
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
                    if (chips != null && chips!.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Wrap(
                        spacing: 5,
                        runSpacing: 5,
                        children: chips!.map((chip) {
                          Color cColor = c.muted2;
                          Color cBg = c.s2;
                          Color cBorder = c.s3;

                          if (chip.isHighlight) {
                            cColor = c.gold;
                            cBg = c.goldDimBg;
                            cBorder = c.gold.withValues(alpha: 0.2);
                          } else if (chip.isGreen) {
                            cColor = c.green;
                            cBg = c.greenDim;
                            cBorder = c.green.withValues(alpha: 0.2);
                          }

                          return Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: cBg,
                              border: Border.all(color: cBorder),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (chip.icon != null) ...[
                                  Icon(chip.icon, size: 8, color: cColor),
                                  const SizedBox(width: 3),
                                ],
                                Text(
                                  chip.text,
                                  style: AppTextStyle.micro(
                                    cColor,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    if (hasProgressBar) ...[
                      const SizedBox(height: 7),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            progressLabelLeft,
                            style: AppTextStyle.micro(
                              c.gold,
                              weight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            progressLabelRight,
                            style: AppTextStyle.micro(c.muted),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Container(
                        height: 3,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: c.s3,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progressValue,
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [c.gold, c.goldLt],
                              ),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
