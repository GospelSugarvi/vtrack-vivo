// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';
import '../../../../core/router/app_route_names.dart';
import '../../../../core/utils/success_dialog.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../ui/ui.dart';
import '../../../../ui/patterns/app_target_hero_card.dart';
import '../../../../ui/promotor/promotor.dart';

class PromotorHomeTab extends StatefulWidget {
  const PromotorHomeTab({super.key});

  @override
  State<PromotorHomeTab> createState() => _PromotorHomeTabState();
}

class _PromotorHomeTabState extends State<PromotorHomeTab> {
  FieldThemeTokens get t => context.fieldTokens;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _hasClockInToday = false;
  String? _clockInTimeLabel;
  Map<String, dynamic>? _targetData;
  Map<String, dynamic>? _dailyTargetData;
  Map<String, dynamic>? _yesterdayAchievementData;
  Map<String, dynamic>? _todayActivityData;
  Map<String, dynamic>? _dailyBonusData;
  Map<String, dynamic>? _weeklyBonusData;
  List<Map<String, dynamic>> _weeklySnapshots = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _dailySpecialRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _weeklySpecialRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _monthlySpecialRows = <Map<String, dynamic>>[];
  Map<String, dynamic>? _bonusSummary;
  num _previousMonthOmzet = 0;
  num _monthlySellOutTarget = 0;
  String? _selectedWeeklyKey;
  final NumberFormat _rupiahFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  StreamSubscription<AuthState>? _authSub;
  String? _activeUserId;

  // Tab state
  String _selectedTab = 'harian'; // 'harian', 'mingguan', 'bulanan'

  num _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  String _formatRupiah(num value) => _rupiahFormat.format(value);

  num _nonNegative(num value) => value < 0 ? 0 : value;

  int _roundUpUnitTarget(num value) {
    if (value <= 0) return 0;
    return value.ceil();
  }

  String _formatUnitTarget(num value) => _roundUpUnitTarget(value).toString();

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    }
    return const [];
  }

  String _formatCompactNumber(num value) {
    return NumberFormat.decimalPattern('id_ID').format(value);
  }

  @override
  void initState() {
    super.initState();
    _activeUserId = Supabase.instance.client.auth.currentUser?.id;
    _loadData();
    _loadHomeSnapshot();
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      final newUserId = event.session?.user.id;
      if (newUserId == null || newUserId == _activeUserId) return;
      _activeUserId = newUserId;
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _userProfile = null;
        _targetData = null;
        _dailyTargetData = null;
        _yesterdayAchievementData = null;
        _todayActivityData = null;
        _dailyBonusData = null;
        _weeklyBonusData = null;
        _weeklySnapshots = <Map<String, dynamic>>[];
        _dailySpecialRows = <Map<String, dynamic>>[];
        _weeklySpecialRows = <Map<String, dynamic>>[];
        _monthlySpecialRows = <Map<String, dynamic>>[];
        _bonusSummary = null;
        _previousMonthOmzet = 0;
        _hasClockInToday = false;
        _clockInTimeLabel = null;
        _selectedWeeklyKey = null;
      });
      _loadData();
      _loadHomeSnapshot();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadHomeSnapshot() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await Supabase.instance.client.rpc(
        'get_promotor_home_snapshot',
        params: {
          'p_user_id': userId,
          'p_date': DateTime.now().toIso8601String().split('T')[0],
        },
      );

      Map<String, dynamic> snapshot = <String, dynamic>{};
      if (response is Map<String, dynamic>) {
        snapshot = Map<String, dynamic>.from(response);
      } else if (response is List &&
          response.isNotEmpty &&
          response.first is Map) {
        snapshot = Map<String, dynamic>.from(response.first as Map);
      }

      Map<String, dynamic>? asMap(dynamic value) {
        if (value is Map<String, dynamic>) {
          return Map<String, dynamic>.from(value);
        }
        if (value is Map) {
          return Map<String, dynamic>.from(value);
        }
        return null;
      }

      List<Map<String, dynamic>> asList(dynamic value) {
        if (value is List) {
          return value
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
        return <Map<String, dynamic>>[];
      }

      final dailyTarget = asMap(snapshot['daily_target']);
      final monthlyTarget = asMap(snapshot['monthly_target']);
      final weeklySnapshots = asList(snapshot['weekly_snapshots']);
      final activeWeekNumber = _toNum(
        snapshot['active_week_number'] ?? dailyTarget?['active_week_number'],
      ).toInt();
      final resolvedSelectedWeeklyKey = _resolveSelectedWeeklyKey(
        weeklySnapshots,
        preferredKey: _selectedWeeklyKey,
        activeWeekNumber: activeWeekNumber,
      );
      if (!mounted) return;
      setState(() {
        _dailyTargetData = dailyTarget;
        _targetData = monthlyTarget;
        _dailyBonusData = asMap(snapshot['daily_bonus']);
        _weeklyBonusData = asMap(snapshot['weekly_bonus']);
        _weeklySnapshots = weeklySnapshots;
        _bonusSummary = asMap(snapshot['monthly_bonus']);
        _dailySpecialRows = asList(snapshot['daily_special_rows']);
        _weeklySpecialRows = asList(snapshot['weekly_special_rows']);
        _monthlySpecialRows = asList(snapshot['monthly_special_rows']);
        _previousMonthOmzet = _toNum(snapshot['previous_month_omzet']);
        _yesterdayAchievementData = asMap(snapshot['yesterday_achievement']);
        _todayActivityData = asMap(snapshot['today_activity']);
        _hasClockInToday = snapshot['clock_in_today'] == true;
        _clockInTimeLabel = snapshot['clock_in_time']?.toString();
        _monthlySellOutTarget = _toNum(monthlyTarget?['target_omzet']);
        _selectedWeeklyKey = resolvedSelectedWeeklyKey;
      });
    } catch (e) {
      debugPrint('Error loading home snapshot: $e');
      if (!mounted) return;
      setState(() {
        _targetData = null;
        _dailyTargetData = null;
        _yesterdayAchievementData = null;
        _todayActivityData = null;
        _dailyBonusData = null;
        _weeklyBonusData = null;
        _weeklySnapshots = <Map<String, dynamic>>[];
        _dailySpecialRows = <Map<String, dynamic>>[];
        _weeklySpecialRows = <Map<String, dynamic>>[];
        _monthlySpecialRows = <Map<String, dynamic>>[];
        _bonusSummary = null;
        _previousMonthOmzet = 0;
        _hasClockInToday = false;
        _clockInTimeLabel = null;
        _monthlySellOutTarget = 0;
        _selectedWeeklyKey = null;
      });
    }
  }

  Future<void> _loadData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final userData = await Supabase.instance.client
          .from('users')
          .select(
            'full_name, nickname, area, role, personal_bonus_target, avatar_url',
          )
          .eq('id', userId)
          .single();
      String? storeName;
      String? satorName;
      try {
        final storeRows = await Supabase.instance.client
            .from('assignments_promotor_store')
            .select('store_id, stores(store_name)')
            .eq('promotor_id', userId)
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(1);
        final assignments = List<Map<String, dynamic>>.from(storeRows);
        final storeData = assignments.isNotEmpty ? assignments.first : null;
        storeName = storeData?['stores']?['store_name'];
      } catch (storeError) {
        debugPrint('Error loading store: $storeError');
        storeName = null;
      }
      try {
        final hierarchyRows = await Supabase.instance.client
            .from('hierarchy_sator_promotor')
            .select(
              'sator_id, users!hierarchy_sator_promotor_sator_id_fkey(full_name, nickname)',
            )
            .eq('promotor_id', userId)
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(1);
        final hierarchy = List<Map<String, dynamic>>.from(hierarchyRows);
        final satorData = hierarchy.isNotEmpty
            ? Map<String, dynamic>.from(hierarchy.first)
            : null;
        final satorUser = satorData?['users'] is Map
            ? Map<String, dynamic>.from(satorData!['users'] as Map)
            : null;
        final satorNickname = (satorUser?['nickname'] ?? '').toString().trim();
        final satorFullName = (satorUser?['full_name'] ?? '').toString().trim();
        satorName = satorNickname.isNotEmpty ? satorNickname : satorFullName;
      } catch (hierarchyError) {
        debugPrint('Error loading sator: $hierarchyError');
        satorName = null;
      }
      final combinedData = {
        ...userData,
        'store_name': storeName,
        'sator_name': satorName,
      };
      if (mounted) {
        setState(() {
          _userProfile = combinedData;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _currentWeekData() {
    final weeklyData = _asMapList(_targetData?['weekly_breakdown']);
    if (weeklyData.isEmpty) return null;
    final now = _dateOnly(DateTime.now());
    for (final row in weeklyData) {
      final start = _parseDate(row['start_date']);
      final end = _parseDate(row['end_date']);
      if (start == null || end == null) continue;
      if (!now.isBefore(_dateOnly(start)) && !now.isAfter(_dateOnly(end))) {
        return row;
      }
    }
    return weeklyData.first;
  }

  String _weeklySnapshotKey(Map<String, dynamic> snapshot) {
    final weekNumber = _toNum(snapshot['week_number']).toInt();
    final startDate = '${snapshot['start_date'] ?? ''}';
    final endDate = '${snapshot['end_date'] ?? ''}';
    return '$weekNumber|$startDate|$endDate';
  }

  String? _resolveSelectedWeeklyKey(
    List<Map<String, dynamic>> snapshots, {
    String? preferredKey,
    int? activeWeekNumber,
  }) {
    if (snapshots.isEmpty) return null;

    if (preferredKey != null && preferredKey.isNotEmpty) {
      for (final snapshot in snapshots) {
        if (_weeklySnapshotKey(snapshot) == preferredKey) {
          return preferredKey;
        }
      }
    }

    final resolvedActiveWeek = activeWeekNumber ?? 0;
    if (resolvedActiveWeek > 0) {
      for (final snapshot in snapshots) {
        if (_toNum(snapshot['week_number']).toInt() == resolvedActiveWeek) {
          return _weeklySnapshotKey(snapshot);
        }
      }
    }

    for (final snapshot in snapshots) {
      if (snapshot['is_active'] == true) {
        return _weeklySnapshotKey(snapshot);
      }
    }

    return _weeklySnapshotKey(snapshots.first);
  }

  Map<String, dynamic>? _selectedWeeklySnapshot() {
    if (_weeklySnapshots.isEmpty) return null;
    final selectedKey = _selectedWeeklyKey;
    if (selectedKey != null && selectedKey.isNotEmpty) {
      for (final snapshot in _weeklySnapshots) {
        if (_weeklySnapshotKey(snapshot) == selectedKey) {
          return snapshot;
        }
      }
    }
    return _weeklySnapshots.first;
  }

  double _targetAchievementPct() {
    if (_targetData == null) return 0.0;
    final value = _targetData?['achievement_omzet_pct'];
    return (value is num) ? value.toDouble() : 0.0;
  }

  num _resolvedMonthlyAllTypeTarget() {
    if (_monthlySellOutTarget > 0) return _monthlySellOutTarget;
    return _toNum(_targetData?['target_omzet']);
  }

  double _safePct(num actual, num target, [double raw = 0]) {
    if (raw > 0) return raw;
    if (target <= 0) return 0;
    return (actual / target) * 100;
  }

  num _getTotalBonus() {
    return _toNum(
      _bonusSummary?['total_bonus'] ?? _bonusSummary?['bonus_total'],
    );
  }

  num _getPersonalTarget() => _toNum(_userProfile?['personal_bonus_target']);

  Widget _buildTargetLoadingCard(String title) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.heroGradientStart, t.heroGradientEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: t.primaryAccent.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: t.primaryAccentSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: t.primaryAccentGlow),
                  ),
                  child: Text(
                    title,
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w800,
                      color: t.primaryAccent,
                      letterSpacing: 0.08,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'Memuat target harian...',
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: t.primaryAccent,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    if (_isLoading) {
      return const AppLoadingScaffold();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([_loadData(), _loadHomeSnapshot()]);
        if (!context.mounted) return;
        await showSuccessDialog(
          context,
          title: 'Berhasil!',
          message: 'Data berhasil di-refresh',
        );
      },
      color: t.primaryAccent,
      strokeWidth: 2.5,
      child: Container(
        color: t.shellBackground,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _buildHeaderInfoChip(
                          icon: Icons.calendar_today_rounded,
                          label: DateFormat(
                            'd MMM yyyy',
                            'id_ID',
                          ).format(DateTime.now()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildTabBar(),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              if (_selectedTab == 'harian') ...[
                _buildAbsenRow(),
                const SizedBox(height: 8),
              ],
              if (_selectedTab == 'harian') ...[
                _buildHarianTab(),
                const SizedBox(height: 10),
                _buildActivityCard(),
              ] else if (_selectedTab == 'mingguan') ...[
                _buildMingguanTab(),
              ] else ...[
                _buildBulananTab(),
                const SizedBox(height: 8),
                _buildFocusProductCard(),
                const SizedBox(height: 8),
                _buildBonusCard(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final nickname = (_userProfile?['nickname'] ?? '').toString().trim();
    final fullName = (_userProfile?['full_name'] ?? 'Promotor').toString();
    final name = nickname.isNotEmpty ? nickname : fullName;
    final store = (_userProfile?['store_name'] ?? 'No Store').toString();
    final sator = (_userProfile?['sator_name'] ?? '').toString().trim();
    final avatarUrl = (_userProfile?['avatar_url'] ?? '').toString().trim();
    final storeLabel = store.isNotEmpty && store != 'null' ? store : 'No Store';
    final satorLabel = sator.isNotEmpty && sator != 'null'
        ? 'Sator: $sator'
        : 'Sator: -';

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [t.surface1, t.surface2]
              : [t.surface1, t.background],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.surface3),
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: t.primaryAccentGlow),
                ),
                child: UserAvatar(
                  avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
                  fullName: name,
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
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.display(
                        size: 24,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      storeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 12,
                        weight: FontWeight.w700,
                        color: t.primaryAccent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      satorLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 11,
                        weight: FontWeight.w700,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Row(
                children: [
                  _buildHeaderIcon(Icons.search_rounded),
                  const SizedBox(width: 7),
                  _buildHeaderIcon(Icons.notifications_none_rounded, dot: true),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderInfoChip({required IconData icon, required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: t.primaryAccent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIcon(IconData icon, {bool dot = false}) {
    return Stack(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.surface3),
          ),
          child: Icon(icon, color: t.textMuted, size: 13),
        ),
        if (dot)
          Positioned(
            top: 7,
            right: 7,
            child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: t.danger,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTabBar() {
    final tabs = [
      {'key': 'harian', 'label': 'Harian'},
      {'key': 'mingguan', 'label': 'Mingguan'},
      {'key': 'bulanan', 'label': 'Bulanan'},
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: tabs.map((tab) {
          final isSelected = _selectedTab == tab['key'];
          return GestureDetector(
            onTap: () => setState(() => _selectedTab = tab['key'] as String),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? t.primaryAccent
                    : t.surface1.withValues(alpha: 0),
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                tab['label'] as String,
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w700,
                  color: isSelected ? t.textOnAccent : t.textMuted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAbsenRow() {
    final status = _hasClockInToday ? 'Sudah absen' : 'Belum absen';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Align(
        alignment: Alignment.centerRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(color: t.surface3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: _hasClockInToday ? t.success : t.warning,
                  shape: BoxShape.circle,
                  boxShadow: _hasClockInToday
                      ? [
                          BoxShadow(
                            color: t.success.withValues(alpha: 0.6),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                _hasClockInToday ? 'Absen Masuk' : status,
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w600,
                  color: t.textSecondary,
                ),
              ),
              if (_hasClockInToday) ...[
                const SizedBox(width: 5),
                Text(
                  _clockInTimeLabel ?? '--:--',
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w600,
                    color: t.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHarianTab() {
    if (_dailyTargetData == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _buildTargetLoadingCard('Target Harian'),
            const SizedBox(height: 12),
            _buildBonusSummaryCard(
              title: 'Bonus Harian',
              subtitle: '',
              data: _dailyBonusData,
            ),
            const SizedBox(height: 12),
            _buildPencapaianKemarin(),
          ],
        ),
      );
    }

    final dailyTarget = _toNum(
      _dailyTargetData?['target_daily_all_type'] ??
          _dailyTargetData?['target_omzet'] ??
          _dailyTargetData?['target'],
    );
    final safeDailyTarget = dailyTarget;
    final dailyActual = _toNum(
      _dailyTargetData?['actual_daily_all_type'] ??
          _dailyTargetData?['actual_omzet'] ??
          _dailyTargetData?['actual'],
    );
    final dailyPct = _safePct(
      dailyActual,
      safeDailyTarget,
      _toNum(_dailyTargetData?['achievement_daily_all_type_pct']).toDouble(),
    );
    final focusPct = _toNum(
      _dailyTargetData?['achievement_daily_focus_pct'],
    ).toDouble();
    final focusTarget = _toNum(_dailyTargetData?['target_daily_focus']);
    final focusActual = _toNum(_dailyTargetData?['actual_daily_focus']);
    final dailySisa = _nonNegative(safeDailyTarget - dailyActual);
    final focusSisa = _nonNegative(
      _roundUpUnitTarget(focusTarget) - focusActual.toInt(),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildHeroCard(
            title: 'Target Harian',
            nominal: safeDailyTarget,
            realisasi: dailyActual,
            percentage: dailyPct,
            sisa: dailySisa,
            metaLeftText: '',
            useCompactNominal: false,
            onTap: () => context.pushNamed(AppRouteNames.targetDetail),
            bottomContent: _buildDailyFocusContent(
              focusTarget: focusTarget,
              focusActual: focusActual,
              focusPct: focusPct,
              focusSisa: focusSisa,
              specialRows: _dailySpecialRows,
            ),
          ),
          const SizedBox(height: 12),
          _buildBonusSummaryCard(
            title: 'Bonus Harian',
            subtitle: '',
            data: _dailyBonusData,
          ),
          const SizedBox(height: 12),
          _buildPencapaianKemarin(),
        ],
      ),
    );
  }

  Widget _buildDailyFocusContent({
    required num focusTarget,
    required num focusActual,
    required double focusPct,
    required num focusSisa,
    required List<Map<String, dynamic>> specialRows,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.surface3)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: t.textOnAccent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.surface3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCardTitleBadge('Produk Fokus'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _buildFocusSummaryItem(
                      'Target',
                      _formatUnitTarget(focusTarget),
                      null,
                    ),
                    _buildFocusSummaryItem(
                      'Terjual',
                      focusActual.toInt().toString(),
                      t.success,
                    ),
                    _buildFocusSummaryItem(
                      'Sisa',
                      _nonNegative(focusSisa).toInt().toString(),
                      t.warning,
                    ),
                    _buildFocusSummaryItem(
                      'Progress',
                      '${focusPct.toStringAsFixed(0)}%',
                      t.primaryAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (specialRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSpecialInsightCard(rows: specialRows),
          ],
        ],
      ),
    );
  }

  Widget _buildMingguanTab() {
    if (_dailyTargetData == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            _buildTargetLoadingCard('Target Mingguan'),
            const SizedBox(height: 12),
            _buildMingguanHeroContent(),
          ],
        ),
      );
    }

    final selectedSnapshot = _selectedWeeklySnapshot();
    final weeklyTarget = _toNum(
      selectedSnapshot?['target_weekly_all_type'] ??
          _dailyTargetData?['target_weekly_all_type'],
    );
    final weeklyActual = _toNum(
      selectedSnapshot?['actual_weekly_all_type'] ??
          _dailyTargetData?['actual_weekly_all_type'],
    );
    final weeklyPct = _safePct(
      weeklyActual,
      weeklyTarget,
      _toNum(
        selectedSnapshot?['achievement_weekly_all_type_pct'] ??
            _dailyTargetData?['achievement_weekly_all_type_pct'],
      ).toDouble(),
    );
    final weeklySisa = _nonNegative(weeklyTarget - weeklyActual);
    final weekNumber = _toNum(
      selectedSnapshot?['week_number'] ??
          _dailyTargetData?['active_week_number'],
    ).toInt();
    final isActiveWeek = selectedSnapshot?['is_active'] == true;
    final isFutureWeek = selectedSnapshot?['is_future'] == true;
    final ringLabel = isFutureWeek
        ? 'Belum berjalan'
        : isActiveWeek
        ? 'Minggu aktif'
        : 'Riwayat minggu';
    final metaLabel =
        selectedSnapshot?['status_label']?.toString().trim() ?? '';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildHeroCard(
            title: 'Target Mingguan',
            nominal: weeklyTarget,
            realisasi: weeklyActual,
            percentage: weeklyPct,
            sisa: weeklySisa,
            ringLabel: ringLabel,
            metaLeftText: weekNumber > 0
                ? metaLabel.isNotEmpty
                      ? 'Minggu ke-$weekNumber · $metaLabel'
                      : 'Minggu ke-$weekNumber'
                : 'Progress minggu ini',
            progressColor: t.warning,
            ringColor: t.warning,
            useCompactNominal: false,
            bottomContent: _buildWeeklyHeroProgressContent(),
          ),
          const SizedBox(height: 12),
          _buildMingguanHeroContent(),
        ],
      ),
    );
  }

  Widget _buildWeeklyHeroProgressContent() {
    final selectedSnapshot = _selectedWeeklySnapshot();
    if (selectedSnapshot != null) {
      final selectedWeekNumber = _toNum(
        selectedSnapshot['week_number'],
      ).toInt();
      final selectedWeekStart = _parseDate(selectedSnapshot['start_date']);
      final selectedWeekEnd = _parseDate(selectedSnapshot['end_date']);
      final selectedWorkingDays = _toNum(
        selectedSnapshot['working_days'],
      ).toInt();
      final selectedElapsedDays = _toNum(
        selectedSnapshot['elapsed_working_days'],
      ).toInt();
      final selectedRangeLabel = _formatWeekRange(
        selectedWeekStart,
        selectedWeekEnd,
      );
      final statusLabel =
          selectedSnapshot['status_label']?.toString().trim().isNotEmpty == true
          ? selectedSnapshot['status_label'].toString().trim()
          : 'Minggu admin';

      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surface1.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.surface3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildCardTitleBadge('Pilih Minggu'),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      selectedRangeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w600,
                        color: t.textMuted,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _buildWeeklySelectorStrip(),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.surface3),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        selectedWeekNumber > 0
                            ? 'Minggu ke-$selectedWeekNumber · $statusLabel'
                            : statusLabel,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                    Text(
                      '$selectedElapsedDays/$selectedWorkingDays hari kerja',
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w600,
                        color: t.primaryAccent,
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

    final weeklyData = _asMapList(_targetData?['weekly_breakdown']);
    final periodStart = _parseDate(_targetData?['start_date']);
    final monthLabel = periodStart == null
        ? 'Minggu Aktif'
        : 'Minggu aktif · ${DateFormat('d MMM', 'id_ID').format(_parseDate(_dailyTargetData?['active_week_start']) ?? periodStart)}'
              ' - ${DateFormat('d MMM', 'id_ID').format(_parseDate(_dailyTargetData?['active_week_end']) ?? periodStart)}';
    final weekStart = _parseDate(_dailyTargetData?['active_week_start']);
    final weekEnd = _parseDate(_dailyTargetData?['active_week_end']);
    final workingDays = _toNum(_dailyTargetData?['working_days']).toInt();
    final elapsedDays = weekStart == null || weekEnd == null
        ? 0
        : _elapsedWorkingDays(weekStart, weekEnd, DateTime.now());
    final activeWeekNumber = _toNum(
      _dailyTargetData?['active_week_number'] ??
          _currentWeekData()?['week_number'],
    ).toInt();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: t.surface1.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.surface3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildCardTitleBadge('Progress per Minggu'),
                const Spacer(),
                Flexible(
                  child: Text(
                    monthLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w600,
                      color: t.textMuted,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.surface3),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      activeWeekNumber > 0
                          ? 'Minggu ke-$activeWeekNumber aktif'
                          : 'Belum ada minggu aktif',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                  Text(
                    '$elapsedDays/$workingDays hari kerja',
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w600,
                      color: t.primaryAccent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: weeklyData.isEmpty
                  ? [
                      Expanded(
                        child: _buildWkDot(
                          'Belum ada data',
                          0,
                          t.surface3,
                          false,
                        ),
                      ),
                    ]
                  : List.generate(weeklyData.length, (index) {
                      final item = weeklyData[index];
                      final pct = _toNum(
                        item['achievement_omzet_pct'] ??
                            item['achievement_pct'],
                      ).toDouble();
                      final start = _parseDate(item['start_date']);
                      final end = _parseDate(item['end_date']);
                      final isCurrent =
                          start != null &&
                          end != null &&
                          !_dateOnly(
                            DateTime.now(),
                          ).isBefore(_dateOnly(start)) &&
                          !_dateOnly(DateTime.now()).isAfter(_dateOnly(end));
                      final isDone = pct >= 100;
                      final label = isDone
                          ? 'Mg ${index + 1} ✓'
                          : isCurrent
                          ? 'Mg ${index + 1} ←'
                          : 'Mg ${index + 1}';
                      final color = isDone
                          ? t.success
                          : isCurrent
                          ? t.warning
                          : t.primaryAccent;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: index == weeklyData.length - 1 ? 0 : 6,
                          ),
                          child: _buildWkDot(
                            label,
                            pct,
                            color,
                            _toNum(item['target_omzet']) > 0,
                            isCurrent: isCurrent,
                          ),
                        ),
                      );
                    }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMingguanHeroContent() {
    if (_dailyTargetData == null) {
      return const SizedBox.shrink();
    }

    final selectedSnapshot = _selectedWeeklySnapshot();
    final weeklyFocusTarget = _toNum(
      selectedSnapshot?['target_weekly_focus'] ??
          _dailyTargetData?['target_weekly_focus'],
    );
    final weeklyFocusActual = _toNum(
      selectedSnapshot?['actual_weekly_focus'] ??
          _dailyTargetData?['actual_weekly_focus'],
    );
    final weeklyFocusPct = _toNum(
      selectedSnapshot?['achievement_weekly_focus_pct'] ??
          _dailyTargetData?['achievement_weekly_focus_pct'],
    ).toDouble();
    final roundedWeeklyFocusTarget = _roundUpUnitTarget(weeklyFocusTarget);
    final weeklyFocusSisa = (roundedWeeklyFocusTarget - weeklyFocusActual)
        .clamp(0, double.infinity);
    final weeklyTargetAll = _toNum(
      selectedSnapshot?['target_weekly_all_type'] ??
          _dailyTargetData?['target_weekly_all_type'],
    );
    final weeklyActualAll = _toNum(
      selectedSnapshot?['actual_weekly_all_type'] ??
          _dailyTargetData?['actual_weekly_all_type'],
    );
    final workingDays = _toNum(
      selectedSnapshot?['working_days'] ?? _dailyTargetData?['working_days'],
    ).toInt();
    final fallbackWeekStart = _parseDate(
      _dailyTargetData?['active_week_start'],
    );
    final fallbackWeekEnd = _parseDate(_dailyTargetData?['active_week_end']);
    final elapsedDays = selectedSnapshot != null
        ? _toNum(selectedSnapshot['elapsed_working_days']).toInt()
        : fallbackWeekStart == null || fallbackWeekEnd == null
        ? 0
        : _elapsedWorkingDays(
            fallbackWeekStart,
            fallbackWeekEnd,
            DateTime.now(),
          );
    final avgPerDay = _toNum(
      selectedSnapshot?['avg_per_day'] ??
          (elapsedDays > 0 ? weeklyActualAll / elapsedDays : 0),
    );
    final projectedWeekly = _toNum(
      selectedSnapshot?['projected_weekly'] ??
          (avgPerDay * (workingDays <= 0 ? 1 : workingDays)),
    );
    final weeklyGap = _toNum(
      selectedSnapshot?['weekly_gap'] ??
          (weeklyTargetAll - weeklyActualAll).clamp(0, double.infinity),
    );
    final weeklySpecialRows = selectedSnapshot?['special_rows'] is List
        ? _asMapList(selectedSnapshot?['special_rows'])
        : _weeklySpecialRows;
    final weeklyBonusData = selectedSnapshot?['bonus'] is Map
        ? Map<String, dynamic>.from(selectedSnapshot!['bonus'] as Map)
        : _weeklyBonusData;
    final focusLabel = selectedSnapshot?['is_future'] == true
        ? 'Target fokus dari admin'
        : 'Progress fokus minggu ini';

    final safeWeeklyGap = weeklyGap.clamp(0, double.infinity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildWeeklySectionCard(
          title: 'Target Produk Fokus',
          child: Column(
            children: [
              _buildFocusInsightCard(
                title: 'Produk Fokus',
                targetValue: roundedWeeklyFocusTarget.toString(),
                actualValue: weeklyFocusActual.toInt().toString(),
                remainingValue: weeklyFocusSisa.toInt().toString(),
                progressText: '${weeklyFocusPct.toStringAsFixed(0)}%',
                progressValue: weeklyFocusPct,
                leftLabel: focusLabel,
              ),
              if (weeklySpecialRows.isNotEmpty) ...[
                const SizedBox(height: 12),
                _buildSpecialInsightCard(rows: weeklySpecialRows),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        _buildWeeklySectionCard(
          title: 'Analisa Mingguan',
          child: Row(
            children: [
              _buildStatMiniCard(
                'Avg/Hari',
                _formatCompactRupiah(avgPerDay),
                selectedSnapshot != null
                    ? '$elapsedDays/$workingDays hari kerja'
                    : 'Sell Out kerja',
                t.info,
              ),
              _buildStatMiniCard(
                'Proyeksi',
                _formatCompactRupiah(projectedWeekly),
                'Akhir minggu',
                projectedWeekly >= weeklyTargetAll ? t.success : t.warning,
              ),
              _buildStatMiniCard(
                'Gap',
                _formatCompactRupiah(safeWeeklyGap),
                'Ke target',
                t.primaryAccent,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildBonusSummaryCard(
          title: 'Bonus Mingguan',
          subtitle: '',
          data: weeklyBonusData,
        ),
      ],
    );
  }

  Widget _buildWeeklySelectorStrip() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(_weeklySnapshots.length, (index) {
          final snapshot = _weeklySnapshots[index];
          final weekKey = _weeklySnapshotKey(snapshot);
          final isSelected = weekKey == _selectedWeeklyKey;
          final isActive = snapshot['is_active'] == true;
          final isFuture = snapshot['is_future'] == true;
          final weekNumber = _toNum(snapshot['week_number']).toInt();
          final weekStart = _parseDate(snapshot['start_date']);
          final weekEnd = _parseDate(snapshot['end_date']);
          final rangeLabel = _formatWeekRange(weekStart, weekEnd);
          final stateLabel = isActive
              ? 'Aktif'
              : isFuture
              ? 'Next'
              : 'Selesai';
          final chipColor = isSelected
              ? t.primaryAccent
              : isActive
              ? t.warning
              : t.surface3;

          return Padding(
            padding: EdgeInsets.only(
              right: index == _weeklySnapshots.length - 1 ? 0 : 8,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => setState(() => _selectedWeeklyKey = weekKey),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 128,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: isSelected ? t.primaryAccentSoft : t.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isSelected
                        ? t.primaryAccent
                        : isActive
                        ? t.warning.withValues(alpha: 0.4)
                        : t.surface3,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: t.primaryAccent.withValues(alpha: 0.14),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            weekNumber > 0 ? 'Mg $weekNumber' : 'Minggu',
                            style: PromotorText.outfit(
                              size: 12,
                              weight: FontWeight.w800,
                              color: isSelected
                                  ? t.primaryAccent
                                  : t.textPrimary,
                            ),
                          ),
                        ),
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: chipColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      rangeLabel,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w700,
                        color: t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      stateLabel,
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w700,
                        color: isSelected ? t.primaryAccent : t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildWkDot(
    String label,
    double pct,
    Color color,
    bool active, {
    bool isCurrent = false,
  }) {
    return Column(
      children: [
        Container(
          height: 4,
          decoration: BoxDecoration(
            color: active ? color.withValues(alpha: 0.3) : t.surface3,
            borderRadius: BorderRadius.circular(100),
          ),
          child: FractionallySizedBox(
            widthFactor: (pct / 100).clamp(0, 1),
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: PromotorText.outfit(
            size: 10,
            weight: isCurrent ? FontWeight.w700 : FontWeight.w600,
            color: isCurrent ? t.primaryAccent : t.textMuted,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${pct.clamp(0, 999).toStringAsFixed(0)}%',
          style: PromotorText.outfit(
            size: 10,
            weight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklySectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w700,
              color: t.textSecondary,
              letterSpacing: 0.04,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w600,
                color: t.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildMetricProgressBar({
    required double value,
    required Color color,
    required String leftLabel,
    required String rightLabel,
    bool dense = false,
  }) {
    final safeValue = value.isNaN ? 0.0 : value.clamp(0, 100).toDouble();
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                leftLabel,
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w700,
                  color: t.textMuted,
                ),
              ),
            ),
            Text(
              rightLabel,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
        SizedBox(height: dense ? 4 : 5),
        Container(
          height: dense ? 4 : 5,
          decoration: BoxDecoration(
            color: t.surface3,
            borderRadius: BorderRadius.circular(100),
          ),
          child: FractionallySizedBox(
            widthFactor: (safeValue / 100).clamp(0, 1),
            alignment: Alignment.centerLeft,
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBulananTab() {
    final achievement = _targetAchievementPct();
    final targetOmzet = _resolvedMonthlyAllTypeTarget();
    final actualOmzet = _toNum(_targetData?['actual_omzet']);
    final sisaTarget = _nonNegative(targetOmzet - actualOmzet);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _buildHeroCard(
        title: 'Target Bulanan',
        nominal: targetOmzet,
        realisasi: actualOmzet,
        percentage: achievement,
        sisa: sisaTarget,
        ringLabel: 'Bulanan',
        metaLeftText: '',
        useCompactNominal: false,
        bottomContent: _buildBulananHeroContent(),
      ),
    );
  }

  Widget _buildBulananHeroContent() {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 1);
    final periodStart = _parseDate(_targetData?['start_date']);
    final periodEnd = _parseDate(_targetData?['end_date']);
    final actualOmzet = _toNum(_targetData?['actual_omzet']);
    final targetOmzet = _toNum(_targetData?['target_omzet']);
    final focusTarget = _toNum(_targetData?['target_fokus_total']);
    final focusActual = _toNum(_targetData?['actual_fokus_total']);
    final focusPct = _toNum(_targetData?['achievement_fokus_pct']).toDouble();
    final focusRemaining = _nonNegative(
      _roundUpUnitTarget(focusTarget) - focusActual.toInt(),
    );
    final remainingTarget = (targetOmzet - actualOmzet).clamp(
      0,
      double.infinity,
    );
    final totalWorkingDays = periodStart == null || periodEnd == null
        ? 0
        : _workingDaysBetween(periodStart, periodEnd);
    final elapsedWorkingDays = periodStart == null || periodEnd == null
        ? 0
        : _elapsedWorkingDays(periodStart, periodEnd, DateTime.now());
    final remainingWorkingDays = (totalWorkingDays - elapsedWorkingDays).clamp(
      0,
      totalWorkingDays,
    );
    final targetPerRemainingDay = remainingWorkingDays > 0
        ? remainingTarget / remainingWorkingDays
        : remainingTarget;
    final avgPerWorkingDay = elapsedWorkingDays > 0
        ? actualOmzet / elapsedWorkingDays
        : 0;
    final projectedMonth =
        avgPerWorkingDay * (totalWorkingDays <= 0 ? 1 : totalWorkingDays);
    final vsPrevPct = _previousMonthOmzet > 0
        ? ((actualOmzet - _previousMonthOmzet) / _previousMonthOmzet) * 100
        : 0.0;
    final isVsPositive = actualOmzet >= _previousMonthOmzet;

    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.surface3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: t.surface3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'HARI KERJA',
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w700,
                          color: t.textMuted,
                          letterSpacing: 0.07,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$elapsedWorkingDays/$totalWorkingDays',
                        style: PromotorText.display(
                          size: 13,
                          color: t.textPrimary,
                        ),
                      ),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Sisa ',
                              style: PromotorText.outfit(
                                size: 10,
                                color: t.textMuted,
                              ),
                            ),
                            TextSpan(
                              text: '$remainingWorkingDays hari',
                              style: PromotorText.outfit(
                                size: 10,
                                weight: FontWeight.w700,
                                color: t.primaryAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: t.surface3)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        'TARGET/HARI',
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w700,
                          color: t.textMuted,
                          letterSpacing: 0.07,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _formatCompactRupiah(targetPerRemainingDay),
                        style: PromotorText.display(
                          size: 13,
                          color: t.textPrimary,
                        ),
                      ),
                      Text(
                        'sisa hari kerja',
                        style: PromotorText.outfit(
                          size: 10,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  child: Column(
                    children: [
                      Text(
                        'VS ${DateFormat('MMM', 'id_ID').format(previousMonth).toUpperCase()}',
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w700,
                          color: t.textMuted,
                          letterSpacing: 0.07,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${isVsPositive ? '↑' : '↓'} ${vsPrevPct.abs().toStringAsFixed(0)}%',
                        style: PromotorText.display(
                          size: 13,
                          color: isVsPositive ? t.success : t.danger,
                        ),
                      ),
                      Text(
                        isVsPositive ? 'lebih baik' : 'di bawah bulan lalu',
                        style: PromotorText.outfit(
                          size: 10,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: t.surface3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    _buildFocusInsightCard(
                      title: 'Produk Fokus',
                      targetValue: _formatUnitTarget(focusTarget),
                      actualValue: focusActual.toInt().toString(),
                      remainingValue: focusRemaining.toInt().toString(),
                      progressText: '${focusPct.toStringAsFixed(0)}%',
                      progressValue: focusPct,
                      leftLabel: 'Progress produk fokus',
                    ),
                    if (_monthlySpecialRows.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      _buildSpecialInsightCard(rows: _monthlySpecialRows),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _buildStatMiniCard(
                      'Avg/Hari',
                      _formatPlainRupiah(avgPerWorkingDay),
                      'Sell Out kerja',
                      t.info,
                    ),
                    _buildStatMiniCard(
                      'Proyeksi',
                      _formatPlainRupiah(projectedMonth),
                      'Akhir bulan',
                      projectedMonth >= targetOmzet ? t.success : t.warning,
                    ),
                    _buildStatMiniCard(
                      'Need/Hari',
                      _formatPlainRupiah(targetPerRemainingDay),
                      'Ke target',
                      t.primaryAccent,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard({
    required String title,
    required num nominal,
    required num realisasi,
    required double percentage,
    required num sisa,
    String ringLabel = 'Hari ini',
    String metaLeftText = 'Progress hari ini',
    Color? progressColor,
    Color? ringColor,
    bool useCompactNominal = true,
    VoidCallback? onTap,
    Widget? bottomContent,
  }) {
    return AppTargetHeroCard(
      title: title,
      nominal: nominal,
      realisasi: realisasi,
      percentage: percentage,
      sisa: sisa,
      ringLabel: ringLabel,
      metaLeftText: metaLeftText,
      progressColor: progressColor ?? t.primaryAccent,
      ringColor: ringColor ?? t.primaryAccent,
      useCompactNominal: useCompactNominal,
      onTap: onTap,
      bottomContent: bottomContent,
    );
  }

  Widget _buildPencapaianKemarin() {
    final allTypeActual = _toNum(_yesterdayAchievementData?['all_type_actual']);
    final allTypeTarget = _toNum(_yesterdayAchievementData?['all_type_target']);
    final focusActual = _toNum(_yesterdayAchievementData?['focus_actual']);
    final focusTarget = _toNum(_yesterdayAchievementData?['focus_target']);
    final vastActual = _toNum(_yesterdayAchievementData?['vast_actual']);
    final vastTarget = _toNum(_yesterdayAchievementData?['vast_target']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
          child: _buildCardTitleBadge('Pencapaian Kemarin'),
        ),
        Container(
          decoration: BoxDecoration(
            color: t.surface1,
            border: Border.all(color: t.surface3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _buildCompareArea(
                name: 'All Type',
                value: _formatCompactNumber(allTypeActual),
                target: _formatRupiah(allTypeTarget),
                percentage: _calculatePercentage(allTypeActual, allTypeTarget),
                color: t.success,
                isCurrency: true,
              ),
              Container(width: 1, height: 80, color: t.surface3),
              _buildCompareArea(
                name: 'Fokus Produk',
                value: focusActual.toInt().toString(),
                target: '${_formatUnitTarget(focusTarget)} unit',
                percentage: _calculatePercentage(focusActual, focusTarget),
                color: t.primaryAccent,
                isCurrency: false,
              ),
              Container(width: 1, height: 80, color: t.surface3),
              _buildCompareArea(
                name: 'VAST',
                value: vastActual.toInt().toString(),
                target: '${_formatUnitTarget(vastTarget)} pengajuan',
                percentage: _calculatePercentage(vastActual, vastTarget),
                color: t.warning,
                isCurrency: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompareArea({
    required String name,
    required String value,
    required String target,
    required double percentage,
    required Color color,
    required bool isCurrency,
  }) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              name,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textMuted,
                letterSpacing: 0.08,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: PromotorText.display(
                size: isCurrency ? 15 : 22,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Container(
              height: 4,
              width: 80,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(100),
              ),
              child: FractionallySizedBox(
                widthFactor: (percentage / 100).clamp(0, 1),
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Target',
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textMuted,
                letterSpacing: 0.06,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              target,
              style: PromotorText.outfit(
                size: isCurrency ? 11 : 12,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 5),
            Text(
              percentage >= 100
                  ? '✓ ${percentage.toStringAsFixed(0)}%'
                  : '${percentage.toStringAsFixed(0)}%',
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: percentage >= 100 ? color : t.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityCard() {
    final completedCount =
        (_todayActivityData?['completed_count'] as int?) ?? 0;
    final hasAbsen = _todayActivityData?['absen'] == true;
    final hasStock = _todayActivityData?['stock'] == true;
    final hasSellOut = _todayActivityData?['sell_out'] == true;
    final hasPromotion = _todayActivityData?['promotion'] == true;
    final hasFollower = _todayActivityData?['follower'] == true;
    final hasAllBrand = _todayActivityData?['allbrand'] == true;
    final totalCount =
        (_todayActivityData?['total_count'] as int?) ??
        <bool>[
          hasAbsen,
          hasStock,
          hasSellOut,
          hasPromotion,
          hasFollower,
          hasAllBrand,
        ].length;
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    return GestureDetector(
      onTap: () => context.pushNamed(AppRouteNames.aktivitasHarian),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: t.surface1,
          border: Border.all(color: t.surface3),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: t.background.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 3,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [t.primaryAccent, t.warning],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: t.primaryAccentSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.checklist_outlined,
                color: t.primaryAccent,
                size: 17,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildCardTitleBadge('Aktivitas Hari Ini'),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: t.surface3,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: FractionallySizedBox(
                            widthFactor: progress.clamp(0, 1),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    t.primaryAccent,
                                    t.primaryAccentLight,
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '$completedCount/$totalCount',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.primaryAccent,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      _buildActivityPill('Absen', hasAbsen),
                      _buildActivityPill('Stok', hasStock),
                      _buildActivityPill('Jual', hasSellOut),
                      _buildActivityPill('Promosi', hasPromotion),
                      _buildActivityPill('Follower', hasFollower),
                      _buildActivityPill('AllBrand', hasAllBrand),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$completedCount',
                  style: PromotorText.display(size: 22, color: t.primaryAccent),
                ),
                Text(
                  '/$totalCount',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w600,
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Icon(
                  Icons.arrow_forward_ios,
                  color: t.textMutedStrong,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityPill(String label, bool done) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: done ? t.success.withValues(alpha: 0.1) : t.surface2,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: done ? t.success.withValues(alpha: 0.2) : t.surface3,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (done)
            Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                color: t.success,
                shape: BoxShape.circle,
              ),
            ),
          if (done) const SizedBox(width: 3),
          Text(
            label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w600,
              color: done ? t.success : t.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusProductCard() {
    final targetFokus = _toNum(_targetData?['target_fokus_total']);
    final actualFokus = _toNum(_targetData?['actual_fokus_total']);
    final achievementFokus = _toNum(_targetData?['achievement_fokus_pct']);
    final fokusDetails = List<Map<String, dynamic>>.from(
      (_targetData?['fokus_details'] as List?) ?? const [],
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border.all(color: t.surface3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.surface3, width: 1)),
            ),
            child: Row(
              children: [
                _buildCardTitleBadge('Produk Fokus'),
                const Spacer(),
                _buildChip('${fokusDetails.length} Tipe'),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.surface3, width: 1)),
            ),
            child: Row(
              children: [
                _buildFocusSummaryItem(
                  'Target',
                  _formatUnitTarget(targetFokus),
                  null,
                ),
                _buildFocusSummaryItem(
                  'Terjual',
                  actualFokus.toInt().toString(),
                  t.success,
                ),
                _buildFocusSummaryItem(
                  'Sisa',
                  _nonNegative(
                    _roundUpUnitTarget(targetFokus) - actualFokus.toInt(),
                  ).toInt().toString(),
                  t.warning,
                ),
                _buildFocusSummaryItem(
                  'Progress',
                  '${achievementFokus.toStringAsFixed(0)}%',
                  t.primaryAccent,
                ),
              ],
            ),
          ),
          if (fokusDetails.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...List.generate(
              fokusDetails.length.clamp(0, 3),
              (index) => _buildFocusProductItem(fokusDetails[index], index + 1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: t.primaryAccentSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: t.primaryAccentGlow),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 10,
          weight: FontWeight.w700,
          color: t.primaryAccent,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildCardTitleBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: t.primaryAccentSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.primaryAccentGlow),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 11,
          weight: FontWeight.w800,
          color: t.primaryAccent,
          letterSpacing: 0.08,
        ),
      ),
    );
  }

  Widget _buildFocusSummaryItem(String label, String value, Color? valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w600,
              color: t.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: PromotorText.display(
              size: 20,
              color: valueColor ?? t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailySpecialItem({
    required Map<String, dynamic> detail,
    required int index,
    required Color tone,
  }) {
    final bundleName = (detail['bundle_name'] ?? 'Tipe Khusus').toString();
    final targetQty = _toNum(detail['target_qty']).toInt();
    final actualQty = _toNum(detail['actual_qty']).toInt();
    final pct = _toNum(detail['pct']).toDouble();
    final safePct = pct.isNaN ? 0.0 : pct.clamp(0, 100).toDouble();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.textOnAccent.withValues(alpha: 0.84),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Text(
              '$index',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bundleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$actualQty / $targetQty unit',
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  height: 4,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: (safePct / 100).clamp(0, 1),
                    alignment: Alignment.centerLeft,
                    child: Container(
                      decoration: BoxDecoration(
                        color: tone,
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusInsightCard({
    required String title,
    required String targetValue,
    required String actualValue,
    required String remainingValue,
    required String progressText,
    required double progressValue,
    String? leftLabel,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.textOnAccent,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildCardTitleBadge(title),
              const Spacer(),
              Text(
                progressText,
                style: PromotorText.display(size: 16, color: t.primaryAccent),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildFocusSummaryItem('Target', targetValue, null),
              _buildFocusSummaryItem('Terjual', actualValue, t.success),
              _buildFocusSummaryItem('Sisa', remainingValue, t.warning),
              _buildFocusSummaryItem('Progress', progressText, t.primaryAccent),
            ],
          ),
          const SizedBox(height: 10),
          _buildMetricProgressBar(
            value: progressValue,
            color: t.primaryAccent,
            leftLabel: leftLabel ?? 'Progress produk fokus',
            rightLabel: progressText,
            dense: true,
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialInsightCard({
    required List<Map<String, dynamic>> rows,
    String title = 'Tipe Khusus',
  }) {
    final specialBg = Color.lerp(t.warningSoft, t.primaryAccentSoft, 0.42)!;
    final specialBorder = Color.lerp(t.warning, t.primaryAccent, 0.34)!;
    final specialHeader = Color.lerp(t.warning, t.primaryAccent, 0.2)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: specialBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: specialBorder.withValues(alpha: 0.34)),
        boxShadow: [
          BoxShadow(
            color: specialBorder.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: t.textOnAccent.withValues(alpha: 0.88),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: specialBorder.withValues(alpha: 0.2)),
            ),
            child: Text(
              title,
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w800,
                color: specialHeader,
                letterSpacing: 0.08,
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...rows.asMap().entries.map(
            (entry) => _buildDailySpecialItem(
              detail: entry.value,
              index: entry.key + 1,
              tone: specialHeader,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusProductItem(Map<String, dynamic> detail, int index) {
    final bundleName = (detail['bundle_name'] ?? 'Produk').toString();
    final targetQty = _toNum(detail['target_qty']);
    final actualQty = _toNum(detail['actual_qty']);
    final roundedTargetQty = _roundUpUnitTarget(targetQty);
    final pct = roundedTargetQty > 0
        ? ((actualQty / roundedTargetQty) * 100)
        : 0.0;
    final isComplete = pct >= 100;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: t.surface3.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: Text(
              '$index',
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bundleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w600,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: t.surface3,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: (pct / 100).clamp(0, 1),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: isComplete
                                  ? LinearGradient(
                                      colors: [t.success, t.success],
                                    )
                                  : LinearGradient(
                                      colors: [
                                        t.primaryAccent,
                                        t.primaryAccentLight,
                                      ],
                                    ),
                              borderRadius: BorderRadius.circular(100),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    SizedBox(
                      width: 26,
                      child: Text(
                        '${pct.toStringAsFixed(0)}%',
                        textAlign: TextAlign.right,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: isComplete ? t.success : t.primaryAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: actualQty.toInt().toString(),
                      style: PromotorText.display(
                        size: 16,
                        color: t.textPrimary,
                      ),
                    ),
                    TextSpan(
                      text: '/$roundedTargetQty',
                      style: PromotorText.outfit(
                        size: 15,
                        weight: FontWeight.w600,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'unit',
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w600,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBonusCard() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totalBonus = _getTotalBonus();
    final personalTarget = _getPersonalTarget();
    final totalSales = _toNum(_bonusSummary?['total_sales']).toInt();
    final byBonusType = Map<String, dynamic>.from(
      (_bonusSummary?['by_bonus_type'] as Map?) ?? const {},
    );
    final bonusPct = personalTarget > 0
        ? ((totalBonus / personalTarget) * 100).clamp(0, 100).toDouble()
        : 0.0;
    final statusLabel = bonusPct >= 100
        ? 'Target Tercapai'
        : bonusPct >= 70
        ? 'On Track'
        : totalBonus > 0
        ? 'Perlu Dikejar'
        : 'Belum Ada Bonus';
    final statusColor = bonusPct >= 100
        ? t.success
        : bonusPct >= 70
        ? t.primaryAccent
        : totalBonus > 0
        ? t.warning
        : t.textMuted;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [t.surface2, t.background]
              : [t.surface1, t.background],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(
          color: isDark
              ? t.primaryAccent.withValues(alpha: 0.18)
              : t.primaryAccent.withValues(alpha: 0.24),
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? t.background.withValues(alpha: 0.4)
                : const Color(0xFF000000).withValues(alpha: 0.05),
            blurRadius: isDark ? 32 : 22,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: t.primaryAccent.withValues(alpha: isDark ? 0.04 : 0.06),
            blurRadius: isDark ? 40 : 24,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: isDark ? 1 : 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  t.primaryAccent.withValues(alpha: 0),
                  t.primaryAccent.withValues(alpha: isDark ? 0.6 : 0.82),
                  t.primaryAccent.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          if (!isDark)
            Container(
              height: 10,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    t.primaryAccent.withValues(alpha: 0.04),
                    t.primaryAccent.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: t.primaryAccent.withValues(
                    alpha: isDark ? 0.08 : 0.16,
                  ),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Row(
                    children: [
                      const PromotorSectionLabel('Bonus Bulan Ini'),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              statusLabel,
                              style: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w700,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: t.surface2,
                            border: Border.all(color: t.surface3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Unit Bulan Ini',
                                style: PromotorText.outfit(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  color: t.textMuted,
                                  letterSpacing: 0.8,
                                ),
                              ),
                              const SizedBox(height: 4),
                              RichText(
                                text: TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '$totalSales ',
                                      style: PromotorText.display(
                                        size: 18,
                                        color: t.primaryAccentLight,
                                      ),
                                    ),
                                    TextSpan(
                                      text: 'unit',
                                      style: PromotorText.outfit(
                                        size: 15,
                                        weight: FontWeight.w600,
                                        color: t.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Total Estimasi',
                              style: PromotorText.outfit(
                                size: 10,
                                weight: FontWeight.w700,
                                color: t.textMuted,
                                letterSpacing: 0.8,
                              ),
                            ),
                            const SizedBox(height: 3),
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: 'Rp ',
                                    style: PromotorText.outfit(
                                      size: 13,
                                      weight: FontWeight.w600,
                                      color: t.textMuted,
                                    ),
                                  ),
                                  TextSpan(
                                    text: _formatCompactNumber(totalBonus),
                                    style: PromotorText.display(
                                      size: 26,
                                      weight: FontWeight.w900,
                                      color: t.primaryAccentLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Target: ${_formatCompactRupiah(personalTarget)}',
                              style: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w600,
                                color: t.textMuted,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  'Progress',
                                  style: PromotorText.outfit(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    color: t.textMuted,
                                  ),
                                ),
                                Text(
                                  '${bonusPct.toStringAsFixed(0)}%',
                                  style: PromotorText.outfit(
                                    size: 13,
                                    weight: FontWeight.w700,
                                    color: t.primaryAccent,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 5),
                            Container(
                              height: 6,
                              decoration: BoxDecoration(
                                color: t.surface3,
                                borderRadius: BorderRadius.circular(100),
                              ),
                              child: FractionallySizedBox(
                                widthFactor: (bonusPct / 100).clamp(0, 1),
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        t.primaryAccent,
                                        t.primaryAccentLight,
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(100),
                                  ),
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
          ),
          _buildBonusBreakdown(totalBonus, personalTarget, byBonusType),
          Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () async {
                  await context.pushNamed(AppRouteNames.promotorBonusDetail);
                  if (!mounted) return;
                  await Future.wait([_loadData(), _loadHomeSnapshot()]);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.primaryAccent,
                  foregroundColor: t.textOnAccent,
                  elevation: 0,
                  shadowColor: t.primaryAccent.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11),
                  ),
                ),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Lihat Detail Bonus',
                        maxLines: 1,
                        style: PromotorText.outfit(
                          size: 15,
                          weight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        '→',
                        style: TextStyle(
                          fontSize: AppTypeScale.body,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusSummaryCard({
    required String title,
    required String subtitle,
    required Map<String, dynamic>? data,
  }) {
    final totalBonus = _toNum(data?['total_bonus'] ?? data?['bonus_total']);
    final totalSales = _toNum(data?['total_sales']).toInt();
    final totalRevenue = _toNum(data?['total_revenue']);
    final personalTarget = _getPersonalTarget();
    final byBonusType = Map<String, dynamic>.from(
      (data?['by_bonus_type'] as Map?) ?? const {},
    );
    final bonusPct = personalTarget > 0
        ? ((totalBonus / personalTarget) * 100).clamp(0, 100).toDouble()
        : 0.0;
    final statusLabel = bonusPct >= 100
        ? 'Target Tercapai'
        : bonusPct >= 70
        ? 'On Track'
        : totalBonus > 0
        ? 'Perlu Dikejar'
        : 'Belum Ada Bonus';
    final statusColor = bonusPct >= 100
        ? t.success
        : bonusPct >= 70
        ? t.primaryAccent
        : totalBonus > 0
        ? t.warning
        : t.textMuted;
    final accentSoft = Color.lerp(t.primaryAccentSoft, t.warningSoft, 0.32)!;
    final accentLine = Color.lerp(t.primaryAccent, t.warning, 0.28)!;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accentSoft, t.surface1],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: accentLine.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: t.background.withValues(alpha: 0.4),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(color: accentLine.withValues(alpha: 0.06), blurRadius: 36),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 380;

              Widget buildTotalCard() {
                return Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  decoration: BoxDecoration(
                    color: t.textOnAccent,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: accentLine.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Total Estimasi',
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w700,
                          color: t.textMuted,
                          letterSpacing: 0.7,
                        ),
                      ),
                      const SizedBox(height: 6),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: RichText(
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: 'Rp ',
                                style: PromotorText.outfit(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: t.textMutedStrong,
                                ),
                              ),
                              TextSpan(
                                text: _formatCompactNumber(totalBonus),
                                style: PromotorText.display(
                                  size: 28,
                                  weight: FontWeight.w900,
                                  color: t.primaryAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatCompactRupiah(totalRevenue),
                        style: PromotorText.outfit(
                          size: 12,
                          weight: FontWeight.w700,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                );
              }

              Widget buildStatusChip() {
                return Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    statusLabel,
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                );
              }

              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (compact)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      t.primaryAccent,
                                      t.primaryAccentLight,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.workspace_premium_rounded,
                                  color: t.textOnAccent,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: PromotorText.outfit(
                                        size: 16,
                                        weight: FontWeight.w800,
                                        color: t.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      subtitle.isNotEmpty
                                          ? subtitle
                                          : 'Ringkasan bonus yang sudah terbentuk',
                                      style: PromotorText.outfit(
                                        size: 10,
                                        weight: FontWeight.w600,
                                        color: t.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          buildStatusChip(),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [t.primaryAccent, t.primaryAccentLight],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.workspace_premium_rounded,
                              color: t.textOnAccent,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  title,
                                  style: PromotorText.outfit(
                                    size: 16,
                                    weight: FontWeight.w800,
                                    color: t.textPrimary,
                                  ),
                                ),
                                Text(
                                  subtitle.isNotEmpty
                                      ? subtitle
                                      : 'Ringkasan bonus yang sudah terbentuk',
                                  style: PromotorText.outfit(
                                    size: 10,
                                    weight: FontWeight.w600,
                                    color: t.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          buildStatusChip(),
                        ],
                      ),
                    const SizedBox(height: 14),
                    if (compact)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _buildBonusMiniStat(
                                  label: 'Transaksi',
                                  value: '$totalSales',
                                  hint: 'Bonus masuk',
                                  tone: t.primaryAccent,
                                  background: t.textOnAccent,
                                ),
                                const SizedBox(height: 10),
                                _buildBonusMiniStat(
                                  label: 'Target',
                                  value: '${bonusPct.toStringAsFixed(0)}%',
                                  hint: _formatCompactRupiah(personalTarget),
                                  tone: statusColor,
                                  background: t.textOnAccent,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: buildTotalCard()),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              children: [
                                _buildBonusMiniStat(
                                  label: 'Transaksi',
                                  value: '$totalSales',
                                  hint: 'Bonus masuk',
                                  tone: t.primaryAccent,
                                  background: t.textOnAccent,
                                ),
                                const SizedBox(height: 10),
                                _buildBonusMiniStat(
                                  label: 'Target',
                                  value: '${bonusPct.toStringAsFixed(0)}%',
                                  hint: _formatCompactRupiah(personalTarget),
                                  tone: statusColor,
                                  background: t.textOnAccent,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(child: Column(children: [buildTotalCard()])),
                        ],
                      ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: t.textOnAccent.withValues(alpha: 0.72),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: accentLine.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Text(
                                'Progress bonus',
                                style: PromotorText.outfit(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: t.textMutedStrong,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${bonusPct.toStringAsFixed(0)}%',
                                style: PromotorText.outfit(
                                  size: 12,
                                  weight: FontWeight.w800,
                                  color: statusColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 7,
                            decoration: BoxDecoration(
                              color: t.surface3,
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: FractionallySizedBox(
                              widthFactor: (bonusPct / 100).clamp(0, 1),
                              alignment: Alignment.centerLeft,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      t.primaryAccent,
                                      t.primaryAccentLight,
                                    ],
                                  ),
                                  borderRadius: BorderRadius.circular(100),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          _buildBonusBreakdown(totalBonus, personalTarget, byBonusType),
        ],
      ),
    );
  }

  Widget _buildBonusMiniStat({
    required String label,
    required String value,
    required String hint,
    required Color tone,
    required Color background,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 5),
          Text(value, style: PromotorText.display(size: 20, color: tone)),
          const SizedBox(height: 2),
          Text(
            hint,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusBreakdown(
    num totalBonus,
    num personalTarget,
    Map<String, dynamic> byBonusType,
  ) {
    final sisa = personalTarget - totalBonus;
    final typedRows = _bonusTypeRows(byBonusType);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Column(
        children: [
          if (typedRows.isNotEmpty)
            ...typedRows.map(
              (row) => _buildBonusRow(
                row['label']!.toString(),
                _formatRupiah(_toNum(row['value'])),
                true,
              ),
            ),
          _buildBonusRow(
            'Kekurangan',
            _formatRupiah(sisa > 0 ? sisa : 0),
            false,
          ),
        ],
      ),
    );
  }

  Widget _buildBonusRow(String label, String value, bool highlight) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: highlight ? t.textOnAccent.withValues(alpha: 0.72) : t.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight
              ? t.primaryAccent.withValues(alpha: 0.1)
              : t.surface3,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
          Text(
            value,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: highlight ? t.primaryAccent : t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatMiniCard(
    String label,
    String value,
    String hint,
    Color color,
  ) {
    final isRupiah = value.startsWith('Rp ');
    final nominalText = isRupiah ? value.replaceFirst('Rp ', '') : value;

    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.surface3),
        ),
        child: Column(
          children: [
            Text(
              label,
              textAlign: TextAlign.center,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textMuted,
                letterSpacing: 0.08,
              ),
            ),
            const SizedBox(height: 4),
            if (isRupiah)
              Column(
                children: [
                  Text(
                    'Rp',
                    textAlign: TextAlign.center,
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    nominalText,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PromotorText.outfit(
                      size: 14,
                      weight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                ],
              )
            else
              Text(
                value,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w800,
                  color: color,
                ),
              ),
            const SizedBox(height: 3),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w600,
                color: t.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatCompactRupiah(num value) {
    return 'Rp ${NumberFormat.decimalPattern('id_ID').format(value)}';
  }

  String _formatWeekRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '-';
    final formatter = DateFormat('d MMM', 'id_ID');
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  String _formatPlainRupiah(num value) {
    final roundedToThousand = (value / 1000).round() * 1000;
    return 'Rp ${NumberFormat.decimalPattern('id_ID').format(roundedToThousand)}';
  }

  double _calculatePercentage(num actual, num target) {
    if (target <= 0) return 0;
    return ((actual / target) * 100).clamp(0, 100).toDouble();
  }

  List<Map<String, Object>> _bonusTypeRows(Map<String, dynamic> byBonusType) {
    final orderedKeys = ['ratio', 'chip', 'excluded'];
    final rows = <Map<String, Object>>[];
    for (final key in orderedKeys) {
      final value = _toNum(byBonusType[key]);
      if (value <= 0) continue;
      rows.add({'label': _bonusTypeLabel(key), 'value': value});
    }
    return rows.take(3).toList();
  }

  String _bonusTypeLabel(String key) {
    switch (key) {
      case 'range':
        return 'Bonus range';
      case 'flat':
        return 'Bonus flat';
      case 'ratio':
        return 'Bonus rasio';
      case 'chip':
        return 'Bonus chip';
      case 'excluded':
        return 'Bonus dikecualikan';
      default:
        return key;
    }
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  DateTime _dateOnly(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  int _workingDaysBetween(DateTime start, DateTime end) {
    if (end.isBefore(start)) return 0;
    int days = 0;
    for (
      var current = DateTime(start.year, start.month, start.day);
      !current.isAfter(end);
      current = current.add(const Duration(days: 1))
    ) {
      if (current.weekday != DateTime.sunday) {
        days++;
      }
    }
    return days;
  }

  int _elapsedWorkingDays(DateTime start, DateTime end, DateTime now) {
    final cappedNow = now.isAfter(end) ? end : now;
    if (cappedNow.isBefore(start)) return 0;
    return _workingDaysBetween(start, cappedNow);
  }
}
