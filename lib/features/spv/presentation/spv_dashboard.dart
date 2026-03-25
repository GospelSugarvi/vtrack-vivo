import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

import '../../../core/router/app_route_names.dart';
import '../../../core/utils/test_account_switcher.dart';
import '../../chat/presentation/pages/chat_list_page.dart';
import '../../../ui/components/field_segmented_control.dart';
import '../../../ui/foundation/field_theme_extensions.dart';
import '../../../ui/patterns/app_target_hero_card.dart';
import '../../../ui/promotor/promotor.dart';

class SpvDashboard extends StatefulWidget {
  const SpvDashboard({super.key});

  @override
  State<SpvDashboard> createState() => _SpvDashboardState();
}

class _SpvDashboardState extends State<SpvDashboard> {
  FieldThemeTokens get t => context.fieldTokens;
  int _currentIndex = 0;
  int _homeFrameIndex = 0;

  String _spvName = 'SPV';
  String _spvArea = '-';

  Map<String, dynamic>? _teamTargetData;
  Map<String, dynamic>? _scheduleSummary;
  Map<String, dynamic>? _attendanceSummary;
  List<Map<String, dynamic>> _satorTargetBreakdown = [];
  List<Map<String, dynamic>> _weeklySnapshots = [];
  String? _selectedWeeklyKey;

  int _todayOmzet = 0;
  int _weekOmzet = 0;
  int _monthOmzet = 0;
  int _todayUnits = 0;
  int _weekFocusUnits = 0;

  final NumberFormat _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  TextStyle _display({
    double size = 28,
    FontWeight weight = FontWeight.w800,
    Color? color,
  }) =>
      PromotorText.display(size: size, weight: weight, color: color ?? _cream);

  TextStyle _outfit({
    double size = 12,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = 0,
  }) => PromotorText.outfit(
    size: size,
    weight: weight,
    color: color ?? _cream,
    letterSpacing: letterSpacing,
  );

  FieldThemeTokens get _t => context.fieldTokens;
  Color get _bg => _t.background;
  Color get _s1 => _t.surface1;
  Color get _s2 => _t.surface2;
  Color get _s3 => _t.surface3;
  Color get _gold => _t.primaryAccent;
  Color get _goldLt => _t.primaryAccentLight;
  Color get _goldDim => _t.primaryAccentSoft;
  Color get _goldGlow => _t.primaryAccentGlow;
  Color get _cream => _t.textPrimary;
  Color get _cream2 => _t.textSecondary;
  Color get _muted => _t.textMuted;
  Color get _muted2 => _t.textMutedStrong;
  Color get _green => _t.success;
  Color get _greenDim => _t.successSoft;
  Color get _red => _t.danger;
  Color get _redDim => _t.dangerSoft;
  Color get _amber => _t.warning;
  Color get _blue => _t.info;
  Color get _shellBg => _t.shellBackground;
  Color get _heroStart => _t.heroGradientStart;
  Color get _heroEnd => _t.heroGradientEnd;
  Color get _heroHighlight => _t.heroHighlight;
  Color get _bottomBarBg => _t.bottomBarBackground;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  Future<void> _refreshAll() async {
    if (!mounted) return;
    await Future.wait([_loadHomeSnapshot(), _loadWeeklySnapshots()]);
    if (mounted) setState(() {});
  }

  // --- LOGIKA DATA (TETAP TERINTEGRASI) ---
  Future<void> _loadHomeSnapshot() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final response = await Supabase.instance.client.rpc(
        'get_spv_home_snapshot',
        params: {
          'p_spv_id': userId,
          'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        },
      );
      if (!mounted || response == null) return;

      final snapshot = Map<String, dynamic>.from(response as Map);
      final profile = Map<String, dynamic>.from(
        snapshot['profile'] ?? const {},
      );
      final teamTargetData = Map<String, dynamic>.from(
        snapshot['team_target_data'] ?? const {},
      );
      final metrics = Map<String, dynamic>.from(
        snapshot['metrics'] ?? const {},
      );
      final scheduleSummary = Map<String, dynamic>.from(
        snapshot['schedule_summary'] ?? const {},
      );
      final attendanceSummary = Map<String, dynamic>.from(
        snapshot['attendance_summary'] ?? const {},
      );
      final satorCards = List<Map<String, dynamic>>.from(
        (snapshot['sator_cards'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );

      setState(() {
        _spvName = (profile['full_name'] ?? 'SPV').toString();
        _spvArea = (profile['area'] ?? '-').toString();
        _teamTargetData = teamTargetData;
        _scheduleSummary = scheduleSummary;
        _attendanceSummary = attendanceSummary;
        _satorTargetBreakdown = satorCards;
        _todayOmzet = _toInt(metrics['today_omzet']);
        _weekOmzet = _toInt(metrics['week_omzet']);
        _monthOmzet = _toInt(metrics['month_omzet']);
        _todayUnits = _toInt(metrics['today_units']);
        _weekFocusUnits = _toInt(metrics['week_focus_units']);
      });
    } catch (_) {}
  }

  Future<void> _loadWeeklySnapshots() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final response = await Supabase.instance.client.rpc(
        'get_spv_home_weekly_snapshots',
        params: {
          'p_spv_id': userId,
          'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        },
      );
      if (!mounted || response == null) return;

      final payload = Map<String, dynamic>.from(response as Map);
      final snapshots = List<Map<String, dynamic>>.from(
        (payload['weekly_snapshots'] as List? ?? const []).map(
          (item) => Map<String, dynamic>.from(item as Map),
        ),
      );
      final resolvedSelectedWeeklyKey = _resolveInitialWeeklyKey(
        snapshots,
        preferredKey: _selectedWeeklyKey,
        activeWeekNumber: _toInt(payload['active_week_number']),
      );

      setState(() {
        _weeklySnapshots = snapshots;
        _selectedWeeklyKey = resolvedSelectedWeeklyKey;
      });
    } catch (_) {}
  }

  int _toInt(dynamic value) => value is int
      ? value
      : (value is num ? value.toInt() : (int.tryParse('${value ?? ''}') ?? 0));

  String _weeklySnapshotKey(Map<String, dynamic> snapshot) {
    final weekNumber = _toInt(snapshot['week_number']);
    final startDate = '${snapshot['start_date'] ?? ''}';
    final endDate = '${snapshot['end_date'] ?? ''}';
    return '$weekNumber|$startDate|$endDate';
  }

  String? _resolveInitialWeeklyKey(
    List<Map<String, dynamic>> snapshots, {
    String? preferredKey,
    int activeWeekNumber = 0,
  }) {
    if (snapshots.isEmpty) return null;

    if (preferredKey != null) {
      for (final snapshot in snapshots) {
        if (_weeklySnapshotKey(snapshot) == preferredKey) {
          return preferredKey;
        }
      }
    }

    for (final snapshot in snapshots) {
      if (_toInt(snapshot['week_number']) == activeWeekNumber) {
        return _weeklySnapshotKey(snapshot);
      }
    }

    return _weeklySnapshotKey(snapshots.first);
  }

  Map<String, dynamic>? _selectedWeeklySnapshot() {
    if (_weeklySnapshots.isEmpty) return null;
    final selectedKey = _selectedWeeklyKey;
    if (selectedKey != null) {
      for (final snapshot in _weeklySnapshots) {
        if (_weeklySnapshotKey(snapshot) == selectedKey) {
          return snapshot;
        }
      }
    }
    return _weeklySnapshots.first;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatWeekRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '-';
    final formatter = DateFormat('d MMM', 'id_ID');
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _shellBg,
      body: Stack(
        children: [
          Column(
            children: [
              const SizedBox(height: 24),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(_t.radiusXl),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: _bg,
                        blurRadius: 140,
                        offset: Offset(0, 50),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(_t.radiusXl),
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: _refreshAll,
                            color: _gold,
                            backgroundColor: _s1,
                            child: ListView(
                              padding: const EdgeInsets.only(bottom: 100),
                              children: [_buildHeader(), _buildContentPanel()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const TestAccountSwitcherFab(),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_heroStart, _bg],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(bottom: BorderSide(color: _t.divider, width: 1.5)),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selamat datang,',
                      style: _outfit(
                        size: 13,
                        weight: FontWeight.w600,
                        color: _muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _spvName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _display(size: 26, weight: FontWeight.w800),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _goldDim,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: _goldGlow),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: _gold,
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: _goldGlow,
                                  blurRadius: 6,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              _spvRole,
                              overflow: TextOverflow.ellipsis,
                              style: _outfit(
                                size: 13,
                                weight: FontWeight.w700,
                                color: _gold,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final dateLabel = DateFormat(
                'EEEE, d MMM yyyy',
                'id_ID',
              ).format(DateTime.now());
              if (_currentIndex == 1) {
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    dateLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _outfit(size: 11, color: _muted),
                  ),
                );
              }

              final compact = constraints.maxWidth < 360;
              final segmented = Container(
                padding: const EdgeInsets.all(3),
                child: FieldSegmentedControl(
                  labels: const ['Harian', 'Mingguan', 'Bulanan'],
                  selectedIndex: _homeFrameIndex,
                  onSelected: (index) =>
                      setState(() => _homeFrameIndex = index),
                ),
              );

              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(dateLabel, style: _outfit(size: 11, color: _muted)),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerLeft, child: segmented),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(
                    child: Text(
                      dateLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _outfit(size: 11, color: _muted),
                    ),
                  ),
                  const SizedBox(width: 12),
                  segmented,
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildContentPanel() {
    if (_currentIndex == 1) return _buildWorkplacePanel();
    return _buildTabPanel();
  }

  Widget _buildTabPanel() {
    if (_homeFrameIndex == 0) return _buildHarianTab();
    if (_homeFrameIndex == 1) return _buildMingguanTab();
    return _buildBulananTab();
  }

  Widget _buildWorkplacePanel() {
    final submitted = _toInt(_scheduleSummary?['submitted']);
    final noReport = _toInt(_attendanceSummary?['no_report_count']);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Workplace', style: _display(size: 22, color: _cream)),
          const SizedBox(height: 6),
          Text('Shortcut kerja SPV', style: _outfit(size: 12, color: _muted)),
          const SizedBox(height: 14),
          _buildWorkplaceItem(
            title: 'Monitor Masuk Kerja Hari Ini',
            icon: Icons.how_to_reg_rounded,
            badge: noReport > 0 ? '$noReport follow-up' : 'Absensi',
            onTap: () => context.pushNamed('spv-attendance-monitor'),
          ),
          _buildWorkplaceItem(
            title: 'Monitor Sell-In',
            icon: Icons.trending_up_rounded,
            badge: 'Hari ini',
            onTap: () => context.pushNamed('spv-sellin-monitor'),
          ),
          _buildWorkplaceItem(
            title: 'Monitor Sell Out',
            icon: Icons.point_of_sale_rounded,
            badge: 'Hari ini',
            onTap: () => context.pushNamed('spv-sellout-monitor'),
          ),
          _buildWorkplaceItem(
            title: 'Monitor Jadwal Bulanan',
            icon: Icons.calendar_month_rounded,
            badge: submitted > 0 ? '$submitted pending' : 'Bulanan',
            onTap: () => context.pushNamed('spv-jadwal-monitor'),
          ),
          _buildWorkplaceItem(
            title: 'Monitor All Brand',
            icon: Icons.analytics_rounded,
            badge: 'Harian',
            onTap: () => context.pushNamed('spv-allbrand'),
          ),
          _buildWorkplaceItem(
            title: 'VAST Finance',
            icon: Icons.account_balance_wallet_outlined,
            badge: 'Monitor',
            onTap: () => context.pushNamed('spv-vast'),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkplaceItem({
    required String title,
    required IconData icon,
    String? subtitle,
    String? badge,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Card(
        elevation: 8,
        shadowColor: _bg.withValues(alpha: 0.18),
        color: _s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_t.radiusLg),
          side: BorderSide(color: _s3),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: _goldDim,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: _gold, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: _outfit(size: 12, weight: FontWeight.w700),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 4),
                      Text(subtitle, style: _outfit(size: 10, color: _muted)),
                    ],
                  ],
                ),
              ),
              if (badge != null) ...[
                Container(
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _goldDim,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _goldGlow),
                  ),
                  child: Text(
                    badge,
                    style: _outfit(
                      size: 9,
                      weight: FontWeight.w700,
                      color: _gold,
                    ),
                  ),
                ),
              ],
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: _s2,
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _s3),
                ),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  color: _gold,
                  size: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ==================== TAB HARIAN ====================
  Widget _buildHarianTab() {
    final targetHarian = _toInt(_teamTargetData?['target_sell_out_daily']);
    final achievement = targetHarian > 0 ? (_todayOmzet / targetHarian) : 0.0;
    int totalP = _satorTargetBreakdown.fold(
      0,
      (sum, g) => sum + _toInt(g['promotor_count']),
    );

    return Column(
      children: [
        AppTargetHeroCard(
          title: 'Target Harian Gabungan',
          nominal: targetHarian,
          realisasi: _todayOmzet,
          percentage: achievement * 100,
          sisa: math.max(0, targetHarian - _todayOmzet),
          ringLabel: '',
          metaLeftText: '',
          progressColor: _gold,
          ringColor: _gold,
          useCompactNominal: false,
          onTap: () => context.pushNamed(AppRouteNames.targetDetail),
          bottomContent: _buildDailyFocusContent(),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: _buildStat3Box(
                  icon: Icons.people_outline,
                  iconColor: _green,
                  iconBg: _greenDim,
                  val: '$totalP',
                  valSub: '/$totalP',
                  label: 'Promotor',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStat3Box(
                  icon: Icons.shopping_cart_outlined,
                  iconColor: _gold,
                  iconBg: _goldDim,
                  val: '$_todayUnits',
                  label: 'Unit Total',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStat3Box(
                  icon: Icons.business_center_outlined,
                  iconColor: _blue,
                  iconBg: _blue.withValues(alpha: 0.10),
                  val: '${_satorTargetBreakdown.length}',
                  valSub: '/${_satorTargetBreakdown.length}',
                  label: 'Sator',
                ),
              ),
            ],
          ),
        ),
        _buildSectionHead('Target Harian Sator'),
        ..._satorTargetBreakdown.map(
          (s) => _buildSatorCard(s, isWeekly: false),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDailyFocusContent() {
    final focusTarget = _toInt(_teamTargetData?['target_focus_daily']);
    final focusActual = _satorTargetBreakdown.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['actual_focus_daily']),
    );
    final focusSisa = math.max(0, focusTarget - focusActual);
    final focusPct = focusTarget > 0 ? (focusActual * 100 / focusTarget) : 0.0;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _s3)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target Produk Fokus Harian',
            style: _outfit(
              size: 13,
              weight: FontWeight.w700,
              color: _muted,
              letterSpacing: 0.08,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDailyFocusMetric(
                  label: 'Target',
                  value: '$focusTarget',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDailyFocusMetric(
                  label: 'Terjual',
                  value: '$focusActual',
                  valueColor: _green,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDailyFocusMetric(
                  label: 'Sisa',
                  value: '$focusSisa',
                  valueColor: _amber,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDailyFocusMetric(
                  label: 'Progress',
                  value: '${focusPct.toStringAsFixed(0)}%',
                  valueColor: _gold,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== TAB MINGGUAN ====================
  Widget _buildMingguanTab() {
    final selectedSnapshot = _selectedWeeklySnapshot();
    final summary = Map<String, dynamic>.from(
      selectedSnapshot?['summary'] ?? const <String, dynamic>{},
    );
    final weekNum = _toInt(
      selectedSnapshot?['week_number'] ?? _teamTargetData?['active_week_number'],
    );
    final workingDays = _toInt(
      selectedSnapshot?['working_days'] ?? _teamTargetData?['working_days'],
    );
    final elapsedWorkingDays = _toInt(selectedSnapshot?['elapsed_working_days']);
    final targetW = _toInt(
      summary['target_sell_out_weekly'] ?? _teamTargetData?['target_sell_out_weekly'],
    );
    final actualW = _toInt(
      summary['actual_sell_out_weekly'] ?? _weekOmzet,
    );
    final achievement = targetW > 0 ? (actualW / targetW) : 0.0;
    final focusTarget = _toInt(
      summary['target_focus_weekly'] ?? _teamTargetData?['target_focus_weekly'],
    );
    final focusActual = _toInt(summary['actual_focus_weekly'] ?? _weekFocusUnits);
    final focusPct = focusTarget > 0 ? (focusActual / focusTarget) : 0.0;
    final satorRows = List<Map<String, dynamic>>.from(
      (selectedSnapshot?['sator_cards'] as List? ?? _satorTargetBreakdown).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
    final rangeLabel = _formatWeekRange(
      _parseDate(selectedSnapshot?['start_date']),
      _parseDate(selectedSnapshot?['end_date']),
    );
    final statusLabel = '${selectedSnapshot?['status_label'] ?? 'Minggu aktif'}';

    return Column(
      children: [
        _buildHeroCard(
          label: 'Target Mingguan Gabungan',
          nominal: targetW,
          actualLabel: 'Realisasi',
          actualVal: actualW,
          pct: achievement,
          pctLabel: statusLabel,
          progressLabel: weekNum > 0
              ? 'Minggu ke-$weekNum · $rangeLabel'
              : rangeLabel,
          progressNote:
              '$elapsedWorkingDays/$workingDays hari kerja · Sisa ${_currency.format(math.max(0, targetW - actualW))}',
          chips: _spvArea
              .split(RegExp(r'[,·]'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .take(2)
              .toList(),
          bottomContent: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              _buildWeeklySelectorCard(),
            ],
          ),
        ),
        _buildSectionHead('Pencapaian Mingguan'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildMetricRingBox('All Type', achievement.clamp(0, 1), _amber),
              const SizedBox(width: 8),
              _buildMetricRingBox('Fokus', focusPct.clamp(0, 1), _green),
              const SizedBox(width: 8),
              _buildMetricRingBox('Aktivitas', 1.0, _amber),
            ],
          ),
        ),
        _buildSectionHead('Target Mingguan SATOR'),
        ...satorRows.map((s) => _buildSatorCard(s, isWeekly: true)),
        const SizedBox(height: 20),
      ],
    );
  }

  // ==================== TAB BULANAN ====================
  Widget _buildBulananTab() {
    final now = DateTime.now();
    final daysInMonth = math.max(
      1,
      DateUtils.getDaysInMonth(now.year, now.month),
    );
    final targetM = _toInt(_teamTargetData?['target_sell_out_monthly']);
    final achievement = targetM > 0 ? (_monthOmzet / targetM) : 0.0;

    return Column(
      children: [
        _buildHeroCard(
          label: 'Target Bulanan Gabungan',
          nominal: targetM,
          actualLabel: 'Realisasi',
          actualVal: _monthOmzet,
          pct: achievement,
          pctLabel: 'Bulanan',
          progressLabel: 'Progress ${DateFormat('MMMM yyyy').format(now)}',
          progressNote:
              'Sisa ${_currency.format(math.max(0, targetM - _monthOmzet))}',
          chips: _spvArea
              .split(RegExp(r'[,·]'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .take(2)
              .toList(),
          bottomContent: Container(
            margin: const EdgeInsets.only(top: 12),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: _s3)),
            ),
            child: Row(
              children: [
                _buildHeroStripItem('Hari Kerja', '${now.day}/$daysInMonth'),
                _buildHeroStripItem(
                  'Target/Hari',
                  _currency
                      .format(
                        math.max(0, targetM - _monthOmzet) /
                            math.max(1, daysInMonth - now.day),
                      )
                      .replaceAll('Rp ', 'Rp')
                      .replaceAll(',00', ''),
                ),
                _buildHeroStripItem('vs Feb', '↑ +4%', valColor: _green),
              ],
            ),
          ),
        ),
        _buildSectionHead('Perbandingan Area'),
        _buildCompareCard(),
        _buildSectionHead('Target Bulanan Sator'),
        ..._satorTargetBreakdown.map(
          (s) => _buildSatorCard(s, isWeekly: false, isMonthly: true),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  // ==================== UI COMPONENTS (100% IDENTIK CSS) ====================

  Widget _buildHeroCard({
    required String label,
    required int nominal,
    required String actualLabel,
    required int actualVal,
    required double pct,
    required String pctLabel,
    required String progressLabel,
    required String progressNote,
    required List<String> chips,
    Widget? bottomContent,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_heroStart, _heroEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: _goldGlow),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _gold.withValues(alpha: 0),
                    _gold.withValues(alpha: 0.6),
                    _gold.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            top: -30,
            right: -30,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [_heroHighlight, _heroHighlight.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.toUpperCase(),
                          style: _outfit(
                            size: 11,
                            weight: FontWeight.w700,
                            color: _muted,
                            letterSpacing: 1.08,
                          ),
                        ),
                        const SizedBox(height: 5),
                        RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Rp ',
                                style: _outfit(size: 13, color: _muted),
                              ),
                              TextSpan(
                                text: _currency
                                    .format(nominal)
                                    .replaceAll('Rp ', ''),
                                style: _display(
                                  size: 28,
                                  weight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 4),
                        RichText(
                          text: TextSpan(
                            style: _outfit(size: 11, color: _muted),
                            children: [
                              TextSpan(text: '$actualLabel: '),
                              TextSpan(
                                text: _currency.format(actualVal),
                                style: _outfit(
                                  size: 11,
                                  color: _cream2,
                                  weight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: chips
                              .map(
                                (c) => Container(
                                  margin: const EdgeInsets.only(right: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _s2,
                                    border: Border.all(color: _s3),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
                                  child: Text(
                                    c,
                                    style: _outfit(
                                      size: 8,
                                      weight: FontWeight.w600,
                                      color: _muted2,
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 62,
                      height: 62,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: 1,
                            strokeWidth: 5,
                            backgroundColor: _s3,
                            valueColor: AlwaysStoppedAnimation(
                              _s1.withValues(alpha: 0),
                            ),
                          ),
                          CircularProgressIndicator(
                            value: pct.clamp(0, 1),
                            strokeWidth: 5,
                            strokeCap: StrokeCap.round,
                            backgroundColor: _s1.withValues(alpha: 0),
                            valueColor: AlwaysStoppedAnimation(
                              pct < 0.6 ? _red : (pct < 0.8 ? _amber : _gold),
                            ),
                          ),
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '${(pct * 100).toStringAsFixed(0)}%',
                                style: _display(
                                  size: 13,
                                  weight: FontWeight.w800,
                                  color: pct < 0.6
                                      ? _red
                                      : (pct < 0.8 ? _amber : _gold),
                                ),
                              ),
                              Text(
                                pctLabel,
                                style: _outfit(size: 7, color: _muted),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final shouldStack =
                        progressLabel.length + progressNote.length > 44 ||
                        constraints.maxWidth < 320;
                    if (shouldStack) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            progressLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _outfit(size: 11, color: _muted),
                          ),
                          const SizedBox(height: 4),
                          Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              progressNote,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.right,
                              style: _outfit(
                                size: 11,
                                color: _goldLt,
                                weight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(
                          child: Text(
                            progressLabel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _outfit(size: 11, color: _muted),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            progressNote,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.right,
                            style: _outfit(
                              size: 11,
                              color: _goldLt,
                              weight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(100),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0, 1),
                    minHeight: 5,
                    backgroundColor: _s3,
                    valueColor: AlwaysStoppedAnimation(
                      pct < 0.6 ? _red : (pct < 0.8 ? _amber : _gold),
                    ),
                  ),
                ),
                if (bottomContent case final Widget content) content,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat3Box({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String val,
    String? valSub,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _s1,
        border: Border.all(color: _s3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, color: iconColor, size: 15),
          ),
          const SizedBox(height: 6),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: val,
                  style: _display(
                    size: 20,
                    weight: FontWeight.w800,
                    color: iconColor,
                  ),
                ),
                if (valSub != null)
                  TextSpan(
                    text: valSub,
                    style: _outfit(size: 13, color: _muted),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: _outfit(
              size: 7,
              color: _muted,
              weight: FontWeight.w700,
              letterSpacing: 0.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyFocusMetric({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _s2,
        border: Border.all(color: _s3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 8, color: _muted)),
          const SizedBox(height: 3),
          Text(
            value,
            style: _display(
              size: 11,
              weight: FontWeight.w800,
              color: valueColor ?? _cream,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHead(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          // Accent dot + garis pendek
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _gold,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _goldGlow, blurRadius: 6, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Container(width: 8, height: 1.5, color: _gold),
          const SizedBox(width: 6),
          Text(
            title,
            style: _outfit(size: 13, weight: FontWeight.w700, color: _cream2),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklySelectorCard() {
    if (_weeklySnapshots.isEmpty) return const SizedBox.shrink();
    final selectedSnapshot = _selectedWeeklySnapshot();
    final rangeLabel = _formatWeekRange(
      _parseDate(selectedSnapshot?['start_date']),
      _parseDate(selectedSnapshot?['end_date']),
    );

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _s1.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Pilih Minggu',
                style: _outfit(size: 11, weight: FontWeight.w800, color: _cream),
              ),
              const Spacer(),
              Text(
                rangeLabel,
                style: _outfit(size: 9, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List<Widget>.generate(_weeklySnapshots.length, (index) {
                final snapshot = _weeklySnapshots[index];
                final weekKey = _weeklySnapshotKey(snapshot);
                final isSelected = weekKey == _selectedWeeklyKey;
                final isActive = snapshot['is_active'] == true;
                final isFuture = snapshot['is_future'] == true;
                final weekNumber = _toInt(snapshot['week_number']);
                final chipTone = isSelected
                    ? _gold
                    : isActive
                    ? _amber
                    : _cream2;

                return Padding(
                  padding: EdgeInsets.only(
                    right: index == _weeklySnapshots.length - 1 ? 0 : 8,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _selectedWeeklyKey = weekKey),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 126,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: isSelected ? _goldDim : _s2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? _goldGlow
                              : isActive
                              ? _amber.withValues(alpha: 0.35)
                              : _s3,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Mg $weekNumber',
                                  style: _outfit(
                                    size: 12,
                                    weight: FontWeight.w800,
                                    color: chipTone,
                                  ),
                                ),
                              ),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: chipTone,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatWeekRange(
                              _parseDate(snapshot['start_date']),
                              _parseDate(snapshot['end_date']),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _outfit(size: 9, color: _muted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isFuture
                                ? 'Belum berjalan'
                                : '${snapshot['status_label'] ?? 'Riwayat minggu'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _outfit(size: 9, weight: FontWeight.w700, color: _cream2),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSatorCard(
    Map<String, dynamic> data, {
    required bool isWeekly,
    bool isMonthly = false,
  }) {
    final targetSellOut = isMonthly
        ? _toInt(data['target_sell_out_monthly'])
        : isWeekly
        ? _toInt(data['target_sell_out_weekly'])
        : _toInt(data['target_sell_out_daily']);
    final actualSellOut = isMonthly
        ? _toInt(data['actual_sell_out_monthly'])
        : isWeekly
        ? _toInt(data['actual_sell_out_weekly'])
        : _toInt(data['actual_sell_out_daily']);
    final targetFocus = isMonthly
        ? _toInt(data['target_focus_monthly'])
        : isWeekly
        ? _toInt(data['target_focus_weekly'])
        : _toInt(data['target_focus_daily']);
    final actualFocus = isMonthly
        ? _toInt(data['actual_focus_monthly'])
        : isWeekly
        ? _toInt(data['actual_focus_weekly'])
        : _toInt(data['actual_focus_daily']);
    final pct = targetSellOut > 0 ? (actualSellOut * 100 / targetSellOut) : 0.0;
    final focusPct = targetFocus > 0 ? (actualFocus * 100 / targetFocus) : 0.0;
    final isWarn = pct < 60;
    final color = isWarn ? _red : (pct < 80 ? _amber : _green);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: _s1,
        border: Border.all(color: isWarn ? _red.withValues(alpha: 0.3) : _s3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: _s2,
                    border: Border.all(color: _s3),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    data['sator_name'].toString().substring(0, 1),
                    style: _display(
                      size: 13,
                      weight: FontWeight.w800,
                      color: _cream2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        data['sator_name'],
                        style: _outfit(
                          size: 15,
                          weight: FontWeight.w700,
                          color: _cream,
                        ),
                      ),
                      Text(
                        '${_toInt(data['promotor_count'])} promotor · ${data['sator_area']}',
                        style: _outfit(size: 8, color: _muted),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${pct.toStringAsFixed(0)}%',
                      style: _display(
                        size: 20,
                        weight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                    Text(
                      isWeekly
                          ? 'Minggu ini'
                          : (isMonthly ? 'Target bulanan' : 'Target hari ini'),
                      style: _outfit(size: 7, color: _muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildSatorRow(
            isMonthly ? 'Sell Out' : (isWeekly ? 'Sell Out' : 'Target Harian'),
            pct / 100,
            color,
            '${_currency.format(actualSellOut / 1000000).replaceAll(',00', '')}/${_currency.format(targetSellOut / 1000000).replaceAll(',00', '')}Jt',
          ),
          _buildSatorRow(
            isMonthly ? 'Sell Out Fokus' : 'Fokus',
            focusPct / 100,
            _amber,
            '$actualFocus / $targetFocus',
          ),
          if (isMonthly) _buildSatorRow('Sell In', 0.11, _amber, 'Rp 214Jt'),
          if (!isWeekly && !isMonthly) _buildSatorAgenda(data),
          _buildSatorPeek(data),
        ],
      ),
    );
  }

  Widget _buildSatorRow(String label, double pct, Color color, String val) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surface2)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 76,
            child: Text(label, style: _outfit(size: 11, color: _muted)),
          ),
          Expanded(
            child: Container(
              height: 3,
              decoration: BoxDecoration(
                color: _s3,
                borderRadius: BorderRadius.circular(100),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: pct.clamp(0, 1),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${(pct * 100).toStringAsFixed(0)}%',
            style: _outfit(size: 15, weight: FontWeight.w800, color: color),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 52,
            child: Text(
              val,
              textAlign: TextAlign.right,
              style: _outfit(size: 8, color: _muted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSatorAgenda(Map<String, dynamic> data) {
    final pending = _toInt(data['pending_jadwal_count']);
    final visit = _toInt(data['visit_count']);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _s3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'AGENDA HARI INI',
            style: _outfit(
              size: 7,
              weight: FontWeight.w800,
              color: _muted2,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 5),
          _buildAgendaItem(
            'Approve Jadwal — $pending pending',
            pending > 0 ? _red : _green,
            pending > 0 ? 'Belum' : '✓',
            pending > 0 ? _redDim : _greenDim,
            pending > 0 ? _red : _green,
          ),
          _buildAgendaItem(
            'Visiting Area — $visit selesai',
            visit > 0 ? _green : _gold,
            visit > 0 ? '✓' : 'Terjadwal',
            visit > 0 ? _greenDim : _goldDim,
            visit > 0 ? _green : _gold,
          ),
          _buildAgendaItem(
            'Penormalan IMEI — selesai',
            _green,
            '✓',
            _greenDim,
            _green,
          ),
        ],
      ),
    );
  }

  Widget _buildAgendaItem(
    String name,
    Color dotColor,
    String badge,
    Color badgeBg,
    Color badgeBorder,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(name, style: _outfit(size: 11, color: _cream2)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: badgeBg,
              border: Border.all(color: badgeBorder.withValues(alpha: 0.2)),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Text(
              badge,
              style: _outfit(size: 7, weight: FontWeight.w700, color: dotColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSatorPeek(Map<String, dynamic> data) {
    final list = List<Map<String, dynamic>>.from(data['top_promotors'] ?? []);
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          if (list.isEmpty) ...[
            _buildPeekChip('Dian K.', '0u', _red),
            _buildPeekChip('Rina S.', '6u', _green),
            _buildPeekChip('Budi W.', '4u', _amber),
          ] else
            ...list.map(
              (p) => _buildPeekChip(
                p['name'] ?? '-',
                '${p['units'] ?? 0}u',
                _green,
              ),
            ),
          Center(
            child: Text(
              '+${list.length > 3 ? list.length - 3 : 5} →',
              style: _outfit(size: 8, weight: FontWeight.w700, color: _gold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeekChip(String name, String val, Color color) {
    return Container(
      margin: const EdgeInsets.only(right: 5, top: 7, bottom: 9),
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: _s2,
        border: Border.all(color: color.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        children: [
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            name,
            style: _outfit(size: 8, weight: FontWeight.w700, color: _cream2),
          ),
          const SizedBox(width: 4),
          Text(
            val,
            style: _outfit(size: 8, weight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRingBox(String label, double pct, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: _s1,
          border: Border.all(color: _s3),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: _outfit(
                size: 7,
                weight: FontWeight.w700,
                color: _muted,
                letterSpacing: 0.49,
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 48,
              height: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CircularProgressIndicator(
                    value: 1,
                    strokeWidth: 4,
                    backgroundColor: _s3,
                    valueColor: AlwaysStoppedAnimation(
                      _s1.withValues(alpha: 0),
                    ),
                  ),
                  CircularProgressIndicator(
                    value: pct.clamp(0, 1),
                    strokeWidth: 4,
                    strokeCap: StrokeCap.round,
                    backgroundColor: _s1.withValues(alpha: 0),
                    valueColor: AlwaysStoppedAnimation(color),
                  ),
                  Text(
                    '${(pct * 100).toStringAsFixed(0)}%',
                    style: _display(
                      size: 13,
                      weight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStripItem(String label, String val, {Color? valColor}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 9),
        child: Column(
          children: [
            Text(
              label.toUpperCase(),
              style: _outfit(
                size: 7,
                weight: FontWeight.w700,
                color: _muted,
                letterSpacing: 0.35,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              val,
              style: _display(
                size: 13,
                weight: FontWeight.w800,
                color: valColor ?? _cream,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompareCard() {
    if (_satorTargetBreakdown.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: _s1,
        border: Border.all(color: _s3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: _s3)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'KPI Bulanan per Area',
                  style: _outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: _cream2,
                  ),
                ),
                Text('Target: 100%', style: _outfit(size: 8, color: _muted)),
              ],
            ),
          ),
          Row(
            children: [
              Builder(
                builder: (context) {
                  return _buildCompareArea(
                    _satorTargetBreakdown[0]['sator_name'],
                    _toInt(_satorTargetBreakdown[0]['achievement_pct_monthly']),
                    _red,
                  );
                },
              ),
              Container(width: 1, height: 60, color: _s3),
              if (_satorTargetBreakdown.length > 1)
                Builder(
                  builder: (context) {
                    return _buildCompareArea(
                      _satorTargetBreakdown[1]['sator_name'],
                      _toInt(
                        _satorTargetBreakdown[1]['achievement_pct_monthly'],
                      ),
                      _amber,
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCompareArea(String name, int pct, Color color) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Text(
              name.toUpperCase(),
              style: _outfit(
                size: 8,
                weight: FontWeight.w700,
                color: _muted,
                letterSpacing: 0.64,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$pct%',
              style: _display(size: 26, weight: FontWeight.w800, color: color),
            ),
            const SizedBox(height: 4),
            Container(
              width: 80,
              height: 4,
              decoration: BoxDecoration(
                color: _s3,
                borderRadius: BorderRadius.circular(100),
              ),
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: (pct / 100).clamp(0, 1),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 22),
      decoration: BoxDecoration(
        color: _bottomBarBg,
        border: Border(top: BorderSide(color: _s3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildNavItem(Icons.home_outlined, Icons.home, 'Home', 0),
          _buildNavItem(
            Icons.analytics_outlined,
            Icons.analytics,
            'Workplace',
            1,
          ),
          _buildNavItem(
            Icons.business_center_outlined,
            Icons.business_center,
            'Ranking',
            2,
          ),
          _buildNavItem(
            Icons.chat_bubble_outline,
            Icons.chat_bubble,
            'Chat',
            3,
          ),
          _buildNavItem(Icons.person_outline, Icons.person, 'Profil', 4),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    IconData icon,
    IconData activeIcon,
    String label,
    int index,
  ) {
    final active = _currentIndex == index;
    return GestureDetector(
      onTap: () {
        setState(() => _currentIndex = index);
        if (index == 2) context.push('/spv/leaderboard');
        if (index == 3) {
          Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (context) => const ChatListPage()));
        }
        if (index == 4) _showLogoutDialog();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: active ? _goldDim : _goldDim.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? activeIcon : icon,
              color: active ? _gold : _muted2,
              size: 18,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: _outfit(
                size: 11,
                weight: FontWeight.w700,
                color: active ? _gold : _muted2,
                letterSpacing: 0.32,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (alertContext) => AlertDialog(
        backgroundColor: _s1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _s3),
        ),
        title: Text(
          'Profil & Akun',
          style: _display(size: 18, weight: FontWeight.w800),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Login sebagai: $_spvName',
              style: _outfit(size: 13, color: _cream2),
            ),
            const SizedBox(height: 20),
            ListTile(
              leading: Icon(Icons.swap_horiz, color: _gold),
              title: Text(
                'Switch Account',
                style: _outfit(size: 16, color: _gold, weight: FontWeight.bold),
              ),
              onTap: () {
                Navigator.pop(alertContext);
                TestAccountSwitcher.show(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.logout, color: _red),
              title: Text('Logout', style: _outfit(size: 16, color: _red)),
              onTap: () async {
                Navigator.pop(alertContext);
                await Supabase.instance.client.auth.signOut();
                if (mounted) {
                  // ignore: use_build_context_synchronously
                  context.go('/login');
                }
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(alertContext),
            child: Text('Tutup', style: _outfit(size: 13, color: _muted)),
          ),
        ],
      ),
    );
  }
}

String get _spvRole => 'SPV';
