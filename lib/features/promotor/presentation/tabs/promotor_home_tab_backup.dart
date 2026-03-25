// ignore_for_file: unused_local_variable, unused_element
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/success_dialog.dart';
import '../../../../ui/ui.dart';
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
  bool _isLoadingDailyTarget = true;
  bool _isLoadingActivity = true;

  BoxDecoration _iosCardDecoration({
    Color? color,
    Color? borderColor,
    double radius = 24,
    bool elevated = true,
  }) {
    return BoxDecoration(
      color: color ?? AppColors.textPrimary,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: borderColor ?? Colors.white.withValues(alpha: 0.08),
      ),
      boxShadow: elevated
          ? [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.35),
                blurRadius: 24,
                offset: const Offset(0, 12),
              ),
            ]
          : [],
    );
  }

  bool _hasClockInToday = false;
  String? _clockInTimeLabel;
  Map<String, dynamic>? _targetData;
  Map<String, dynamic>? _dailyTargetData;
  Map<String, dynamic>? _bonusSummary;
  final NumberFormat _rupiahFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  StreamSubscription<AuthState>? _authSub;
  String? _activeUserId;

  num _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value) ?? 0;
    return 0;
  }

  String _formatRupiah(num value) => _rupiahFormat.format(value);

  String _formatCompactNumber(num value) {
    return NumberFormat.decimalPattern('id_ID').format(value);
  }

  @override
  void initState() {
    super.initState();
    _activeUserId = Supabase.instance.client.auth.currentUser?.id;
    _loadData();
    _loadTargetData();
    _loadDailyTargetData();
    _loadBonusSummary();
    _loadTodayActivityStatus();
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
        _bonusSummary = null;
        _isLoadingActivity = true;
        _hasClockInToday = false;
        _clockInTimeLabel = null;
      });
      _loadData();
      _loadTargetData();
      _loadDailyTargetData();
      _loadBonusSummary();
      _loadTodayActivityStatus();
    });
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _loadBonusSummary() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final now = DateTime.now();
      final startDate = DateTime(now.year, now.month, 1);
      final endDate = DateTime(now.year, now.month + 1, 0);

      final summary = await Supabase.instance.client.rpc(
        'get_promotor_bonus_summary',
        params: {
          'p_promotor_id': userId,
          'p_start_date': startDate.toIso8601String().split('T')[0],
          'p_end_date': endDate.toIso8601String().split('T')[0],
        },
      );

      Map<String, dynamic> summaryMap = {};
      if (summary is Map<String, dynamic>) {
        summaryMap = Map<String, dynamic>.from(summary);
      } else if (summary is List &&
          summary.isNotEmpty &&
          summary.first is Map) {
        summaryMap = Map<String, dynamic>.from(summary.first as Map);
      }

      // Fallback: if RPC summary empty/zero, calculate from detail RPC.
      final rpcTotalBonus = _toNum(
        summaryMap['total_bonus'] ?? summaryMap['bonus_total'],
      );
      if (rpcTotalBonus <= 0) {
        final fallbackRows = await Supabase.instance.client.rpc(
          'get_promotor_bonus_details',
          params: {
            'p_promotor_id': userId,
            'p_start_date': startDate.toIso8601String().split('T')[0],
            'p_end_date': endDate.toIso8601String().split('T')[0],
            'p_limit': 500,
            'p_offset': 0,
          },
        );

        num computedBonus = 0;
        for (final row in (fallbackRows as List? ?? const [])) {
          if (row is Map<String, dynamic>) {
            computedBonus += _toNum(row['bonus_amount']);
          }
        }
        summaryMap['total_bonus'] = computedBonus;
      }

      if (mounted) {
        setState(() {
          _bonusSummary = summaryMap;
        });
      }
    } catch (e) {
      debugPrint('Error loading bonus summary: $e');
    }
  }

  Future<void> _loadTargetData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        return;
      }

      debugPrint('=== DEBUG HomeTab _loadTargetData ===');
      debugPrint('HomeTab target userId: $userId');
      final primary = await _fetchTargetDashboard(userId, null);
      debugPrint('HomeTab primary target response: $primary');
      if (primary != null) {
        if (mounted) setState(() => _targetData = primary);
      } else {
        final fallback = await _fetchLatestTargetDashboard(userId);
        debugPrint('HomeTab fallback target response: $fallback');
        if (mounted) setState(() => _targetData = fallback);
      }
      debugPrint('=== DEBUG HomeTab _loadTargetData END ===');
    } catch (e) {
      debugPrint('Error loading target data: $e');
      if (mounted) {
        final message = e.toString().toLowerCase();
        final isNoTargetCase =
            message.contains('no rows') ||
            message.contains('target') && message.contains('not found') ||
            message.contains('no target');
        if (isNoTargetCase) {
          final userId = Supabase.instance.client.auth.currentUser?.id;
          if (userId != null) {
            final fallback = await _fetchLatestTargetDashboard(userId);
            if (mounted) setState(() => _targetData = fallback);
            return;
          }
        }
        if (mounted) setState(() => _targetData = null);
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchTargetDashboard(
    String userId,
    String? periodId,
  ) async {
    final response = await Supabase.instance.client.rpc(
      'get_target_dashboard',
      params: {'p_user_id': userId, 'p_period_id': periodId},
    );
    if (response is List && response.isNotEmpty && response.first is Map) {
      return Map<String, dynamic>.from(response.first as Map);
    }
    if (response is Map<String, dynamic> && response.isNotEmpty) {
      return response;
    }
    return null;
  }

  Future<Map<String, dynamic>?> _fetchLatestTargetDashboard(
    String userId,
  ) async {
    final latest = await Supabase.instance.client
        .from('user_targets')
        .select('period_id')
        .eq('user_id', userId)
        .order('updated_at', ascending: false)
        .limit(1)
        .maybeSingle();
    final periodId = latest?['period_id']?.toString();
    if (periodId == null || periodId.isEmpty) return null;
    return _fetchTargetDashboard(userId, periodId);
  }

  Future<void> _loadDailyTargetData() async {
    if (!mounted) return;
    setState(() => _isLoadingDailyTarget = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoadingDailyTarget = false);
        return;
      }

      final response = await Supabase.instance.client.rpc(
        'get_daily_target_dashboard',
        params: {
          'p_user_id': userId,
          'p_date': DateTime.now().toIso8601String().split('T')[0],
        },
      );

      Map<String, dynamic>? result;
      if (response is List && response.isNotEmpty && response.first is Map) {
        result = Map<String, dynamic>.from(response.first as Map);
      } else if (response is Map<String, dynamic> && response.isNotEmpty) {
        result = Map<String, dynamic>.from(response);
      }

      if (mounted) {
        setState(() {
          _dailyTargetData = result;
          _isLoadingDailyTarget = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading daily target data: $e');
      if (mounted) {
        setState(() {
          _dailyTargetData = null;
          _isLoadingDailyTarget = false;
        });
      }
    }
  }

  Future<void> _loadTodayActivityStatus() async {
    if (!mounted) return;
    setState(() => _isLoadingActivity = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoadingActivity = false);
        return;
      }

      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));

      final rows = await Supabase.instance.client
          .from('attendance')
          .select('created_at')
          .eq('user_id', userId)
          .gte('created_at', start.toIso8601String())
          .lt('created_at', end.toIso8601String())
          .order('created_at')
          .limit(1);

      String? clockInTime;
      if (rows.isNotEmpty) {
        final createdAt = rows.first['created_at']?.toString();
        final parsed = createdAt == null ? null : DateTime.tryParse(createdAt);
        if (parsed != null) {
          clockInTime = DateFormat('HH:mm').format(parsed.toLocal());
        }
      }

      if (mounted) {
        setState(() {
          _hasClockInToday = rows.isNotEmpty;
          _clockInTimeLabel = clockInTime;
          _isLoadingActivity = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading today activity status: $e');
      if (mounted) {
        setState(() {
          _isLoadingActivity = false;
          _hasClockInToday = false;
          _clockInTimeLabel = null;
        });
      }
    }
  }

  Future<void> _loadData() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      debugPrint('=== DEBUG HomeTab _loadData ===');
      debugPrint('userId: $userId');
      if (userId == null) {
        debugPrint('userId is NULL, returning');
        return;
      }

      // Get user profile - include personal_bonus_target
      debugPrint('HomeTab Step 1: Fetching user data...');
      final userData = await Supabase.instance.client
          .from('users')
          .select(
            'full_name, nickname, area, role, personal_bonus_target, avatar_url',
          )
          .eq('id', userId)
          .single();
      debugPrint('HomeTab Step 1 OK: userData = $userData');

      // Get store assignment through junction table
      debugPrint('HomeTab Step 2: Fetching store assignment...');
      String? storeName;
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
        debugPrint('HomeTab Step 2 OK: storeData = $storeData');
        storeName = storeData?['stores']?['store_name'];
      } catch (storeError) {
        debugPrint('HomeTab Step 2 ERROR: $storeError');
        storeName = null;
      }

      // Combine the data
      final combinedData = {...userData, 'store_name': storeName};
      debugPrint('HomeTab Step 3: combinedData = $combinedData');

      if (mounted) {
        setState(() {
          _userProfile = combinedData;
          _isLoading = false;
        });
      }
      debugPrint('=== DEBUG HomeTab END ===');
    } catch (e, stackTrace) {
      debugPrint('=== DEBUG HomeTab ERROR ===');
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _selectedTab = 'bulanan'; // 'harian', 'mingguan', 'bulanan'

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppLoadingScaffold();
    }

    return RefreshIndicator(
      onRefresh: () async {
        await Future.wait([
          _loadData(),
          _loadTargetData(),
          _loadDailyTargetData(),
          _loadBonusSummary(),
          _loadTodayActivityStatus(),
        ]);

        if (!context.mounted) return;
        await showSuccessDialog(
          context,
          title: 'Berhasil!',
          message: 'Data berhasil di-refresh',
        );
      },
      color: PromotorColors.gold,
      strokeWidth: 2.5,
      child: Container(
        color: PromotorColors.bgOuter,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(0, 20, 0, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderV3(),
              const SizedBox(height: 8),
              _buildAbsenRowV3(),
              const SizedBox(height: 8),
              _selectedTab == 'harian'
                  ? _buildHarianTabV3()
                  : _selectedTab == 'mingguan'
                  ? _buildMingguanTabV3()
                  : _buildBulananTabV3(),
              const SizedBox(height: 8),
              _buildActivityCardV3(),
              const SizedBox(height: 8),
              _buildFocusAndBonusRowV3(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderV3() {
    final nickname = (_userProfile?['nickname'] ?? '').toString().trim();
    final fullName = (_userProfile?['full_name'] ?? 'Promotor').toString();
    final name = nickname.isNotEmpty ? nickname : fullName;
    final store = (_userProfile?['store_name'] ?? 'No Store').toString();
    final area = (_userProfile?['area'] ?? '').toString();
    final storeDisplay = area.isNotEmpty && area != 'null'
        ? '$store · $area'
        : store;
    final avatarUrl = _userProfile?['avatar_url'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: greeting, name, store + icons
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Selamat datang,',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w600,
                        color: PromotorColors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(name, style: PromotorText.display(size: 26)),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: PromotorColors.goldDim,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: PromotorColors.goldGlow),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: const BoxDecoration(
                              color: PromotorColors.gold,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            storeDisplay.toUpperCase(),
                            style: PromotorText.outfit(
                              size: 13,
                              weight: FontWeight.w700,
                              color: PromotorColors.gold,
                              letterSpacing: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: PromotorColors.s1,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: PromotorColors.s3),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatarUrl != null && avatarUrl.isNotEmpty
                        ? Image(
                            image: CachedNetworkImageProvider(avatarUrl),
                            fit: BoxFit.cover,
                          )
                        : const Icon(
                            Icons.person,
                            color: PromotorColors.muted,
                            size: 18,
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildHeaderIconButtonV3(Icons.search_rounded),
                      const SizedBox(width: 7),
                      _buildHeaderIconButtonV3(
                        Icons.notifications_none_rounded,
                        dot: true,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // Bottom row: date + tab bar
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now()),
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: PromotorColors.muted,
                ),
              ),
              _buildTabBarV3(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButtonV3(IconData icon, {bool dot = false}) {
    return Stack(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: PromotorColors.s1,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: PromotorColors.s3),
          ),
          child: Icon(icon, color: PromotorColors.muted, size: 13),
        ),
        if (dot)
          Positioned(
            top: 7,
            right: 7,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: PromotorColors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTabBarV3() {
    final tabs = [
      {'key': 'harian', 'label': 'Harian'},
      {'key': 'mingguan', 'label': 'Mingguan'},
      {'key': 'bulanan', 'label': 'Bulanan'},
    ];

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: PromotorColors.s2,
        borderRadius: BorderRadius.circular(100),
        border: Border.all(color: PromotorColors.s3),
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
                color: isSelected ? PromotorColors.gold : Colors.transparent,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                tab['label'] as String,
                style: PromotorText.outfit(
                  size: 8,
                  weight: FontWeight.w700,
                  color: isSelected
                      ? const Color(0xFF1a0e00)
                      : PromotorColors.muted,
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildAbsenRowV3() {
    final dateLabel = DateFormat(
      'EEEE, d MMMM yyyy',
      'id_ID',
    ).format(DateTime.now());
    final status = _isLoadingActivity
        ? 'Memeriksa'
        : (_hasClockInToday ? 'Sudah absen' : 'Belum absen');
    final timeLabel = _clockInTimeLabel ?? '--:--';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            dateLabel,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: PromotorColors.muted,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: PromotorColors.s2,
              borderRadius: BorderRadius.circular(100),
              border: Border.all(color: PromotorColors.s3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: _hasClockInToday
                        ? PromotorColors.green
                        : PromotorColors.amber,
                    shape: BoxShape.circle,
                    boxShadow: _hasClockInToday
                        ? [
                            BoxShadow(
                              color: PromotorColors.green.withValues(
                                alpha: 0.6,
                              ),
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
                    color: PromotorColors.cream2,
                  ),
                ),
                if (_hasClockInToday) ...[
                  const SizedBox(width: 5),
                  Text(
                    timeLabel,
                    style: PromotorText.outfit(
                      size: 15,
                      weight: FontWeight.w600,
                      color: PromotorColors.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHarianTabV3() {
    final dailyPct = _toNum(
      _dailyTargetData?['achievement_daily_all_type_pct'],
    ).toDouble();
    final dailyTarget = _toNum(
      _dailyTargetData?['target_omzet'] ?? _dailyTargetData?['target'],
    );
    final dailyActual = _toNum(
      _dailyTargetData?['actual_omzet'] ?? _dailyTargetData?['actual'],
    );
    final dailySisa = dailyTarget - dailyActual;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Hero card
          _buildHeroCardV3(
            title: 'Target Harian',
            nominal: dailyTarget,
            realisasi: dailyActual,
            percentage: dailyPct,
            sisa: dailySisa,
          ),
          const SizedBox(height: 12),
          // Pencapaian kemarin
          _buildPencapaianKemarinV3(),
        ],
      ),
    );
  }

  Widget _buildMingguanTabV3() {
    final weekly = _currentWeekData();
    final weeklyPct = _toNum(
      weekly?['achievement_omzet_pct'] ?? weekly?['achievement_pct'],
    ).toDouble();
    final weeklyTarget = _toNum(weekly?['target_omzet'] ?? weekly?['target']);
    final weeklyActual = _toNum(weekly?['actual_omzet'] ?? weekly?['actual']);
    final weeklySisa = weeklyTarget - weeklyActual;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          _buildHeroCardV3(
            title: 'Target Mingguan',
            nominal: weeklyTarget,
            realisasi: weeklyActual,
            percentage: weeklyPct,
            sisa: weeklySisa,
          ),
          const SizedBox(height: 12),
          _buildWeeklyProgressV3(),
        ],
      ),
    );
  }

  Widget _buildBulananTabV3() {
    final achievement = _targetAchievementPct();
    final targetOmzet = _toNum(_targetData?['target_omzet']);
    final actualOmzet = _toNum(_targetData?['actual_omzet']);
    final sisaTarget = targetOmzet - actualOmzet;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _buildHeroCardV3(
        title: 'Target Bulanan',
        nominal: targetOmzet,
        realisasi: actualOmzet,
        percentage: achievement,
        sisa: sisaTarget,
      ),
    );
  }

  Widget _buildHeroCardV3({
    required String title,
    required num nominal,
    required num realisasi,
    required double percentage,
    required num sisa,
  }) {
    final safePercentage = percentage.isNaN ? 0.0 : percentage.clamp(0, 100);
    final ringOffset = 157 * (1 - safePercentage / 100);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF261f13), Color(0xFF1c1610)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: PromotorColors.gold.withValues(alpha: 0.22)),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  PromotorColors.gold.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: PromotorColors.muted,
                          letterSpacing: 0.12,
                        ),
                      ),
                      const SizedBox(height: 5),
                      RichText(
                        text: TextSpan(
                          children: [
                            TextSpan(
                              text: 'Rp ',
                              style: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w600,
                                color: PromotorColors.muted,
                              ),
                            ),
                            TextSpan(
                              text: _formatCompactNumber(nominal),
                              style: PromotorText.display(size: 28),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Pencapaian hari ini: ${_formatRupiah(realisasi)}',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w600,
                          color: PromotorColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                // Ring progress
                SizedBox(
                  width: 62,
                  height: 62,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 62,
                        height: 62,
                        child: CircularProgressIndicator(
                          value: safePercentage / 100,
                          strokeWidth: 5,
                          backgroundColor: PromotorColors.s3,
                          valueColor: const AlwaysStoppedAnimation<Color>(
                            PromotorColors.gold,
                          ),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${safePercentage.toStringAsFixed(0)}%',
                            style: PromotorText.display(
                              size: 13,
                              color: PromotorColors.gold,
                            ),
                          ),
                          Text(
                            'Hari ini',
                            style: PromotorText.outfit(
                              size: 7,
                              weight: FontWeight.w600,
                              color: PromotorColors.muted,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progress hari ini',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: PromotorColors.muted,
                  ),
                ),
                Text(
                  'Sisa ${_formatRupiah(sisa)}',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: PromotorColors.goldLt,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: PromotorColors.s3,
                borderRadius: BorderRadius.circular(100),
              ),
              child: FractionallySizedBox(
                widthFactor: (safePercentage / 100).clamp(0, 1),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [PromotorColors.gold, PromotorColors.goldLt],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(100),
                    boxShadow: [
                      BoxShadow(color: PromotorColors.goldGlow, blurRadius: 8),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // Bottom strip
          Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 0, 0),
            height: 1,
            color: PromotorColors.s3,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 9),
                    decoration: BoxDecoration(
                      border: Border(
                        right: BorderSide(color: PromotorColors.s3, width: 1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Target',
                          style: PromotorText.outfit(
                            size: 7,
                            weight: FontWeight.w700,
                            color: PromotorColors.muted,
                            letterSpacing: 0.07,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatCompactNumber(nominal),
                          style: PromotorText.display(
                            size: 13,
                            color: PromotorColors.cream,
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
                      border: Border(
                        right: BorderSide(color: PromotorColors.s3, width: 1),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Pencapaian',
                          style: PromotorText.outfit(
                            size: 7,
                            weight: FontWeight.w700,
                            color: PromotorColors.muted,
                            letterSpacing: 0.07,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatCompactNumber(realisasi),
                          style: PromotorText.display(
                            size: 13,
                            color: PromotorColors.cream,
                          ),
                        ),
                        Text(
                          '${(safePercentage).toStringAsFixed(0)}%',
                          style: PromotorText.outfit(
                            size: 8,
                            weight: FontWeight.w700,
                            color: PromotorColors.gold,
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
                          'Sisa',
                          style: PromotorText.outfit(
                            size: 7,
                            weight: FontWeight.w700,
                            color: PromotorColors.muted,
                            letterSpacing: 0.07,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _formatCompactNumber(sisa),
                          style: PromotorText.display(
                            size: 13,
                            color: PromotorColors.amber,
                          ),
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

  Widget _buildPencapaianKemarinV3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Pencapaian Kemarin',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: PromotorColors.cream2,
                ),
              ),
              Text(
                'Rabu, 11 Mar',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w600,
                  color: PromotorColors.muted,
                ),
              ),
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: PromotorColors.s1,
            border: Border.all(color: PromotorColors.s3),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            children: [
              _buildCompareAreaV3(
                name: 'All Type',
                value: '3.000.000',
                target: 'Rp 3.800.000',
                percentage: 80,
                color: PromotorColors.green,
                isCurrency: true,
              ),
              Container(width: 1, height: 80, color: PromotorColors.s3),
              _buildCompareAreaV3(
                name: 'Fokus Produk',
                value: '3',
                target: '5 unit',
                percentage: 60,
                color: PromotorColors.gold,
                isCurrency: false,
              ),
              Container(width: 1, height: 80, color: PromotorColors.s3),
              _buildCompareAreaV3(
                name: 'Vast Finance',
                value: '2',
                target: '5 unit',
                percentage: 40,
                color: PromotorColors.blue,
                isCurrency: false,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompareAreaV3({
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
          children: [
            Text(
              name,
              style: PromotorText.outfit(
                size: 8,
                weight: FontWeight.w700,
                color: PromotorColors.muted,
                letterSpacing: 0.08,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: PromotorText.display(
                size: isCurrency ? 16 : 22,
                color: color,
              ),
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
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: 'Target ',
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w600,
                      color: PromotorColors.muted,
                    ),
                  ),
                  TextSpan(
                    text: target,
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w700,
                      color: PromotorColors.cream2,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 5),
            Text(
              percentage >= 100
                  ? '✓ ${percentage.toStringAsFixed(0)}%'
                  : '${percentage.toStringAsFixed(0)}%',
              style: PromotorText.outfit(
                size: 8,
                weight: FontWeight.w700,
                color: percentage >= 100 ? color : PromotorColors.amber,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyProgressV3() {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PromotorColors.s1,
        border: Border.all(color: PromotorColors.s3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PromotorSectionLabel('Progress Mingguan'),
          const SizedBox(height: 12),
          _buildWeekRowV3('Senin', 75, true),
          const SizedBox(height: 4),
          _buildWeekRowV3('Selasa', 60, false),
          const SizedBox(height: 4),
          _buildWeekRowV3('Rabu', 80, false),
          const SizedBox(height: 4),
          _buildWeekRowV3('Kamis', 45, false),
          const SizedBox(height: 4),
          _buildWeekRowV3('Jumat', 0, false),
        ],
      ),
    );
  }

  Widget _buildWeekRowV3(String day, int percentage, bool isActive) {
    return Row(
      children: [
        SizedBox(
          width: 50,
          child: Text(
            day,
            style: PromotorText.outfit(
              size: 7,
              weight: isActive ? FontWeight.w700 : FontWeight.w600,
              color: isActive ? PromotorColors.gold : PromotorColors.muted,
            ),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            height: 4,
            decoration: BoxDecoration(
              color: PromotorColors.s3,
              borderRadius: BorderRadius.circular(100),
            ),
            child: FractionallySizedBox(
              widthFactor: (percentage / 100).clamp(0, 1),
              child: Container(
                decoration: BoxDecoration(
                  color: isActive
                      ? PromotorColors.gold
                      : PromotorColors.gold.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 30,
          child: Text(
            '$percentage%',
            style: PromotorText.outfit(
              size: 7,
              weight: FontWeight.w700,
              color: isActive ? PromotorColors.gold : PromotorColors.muted,
            ),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildPromotorHeaderV2() {
    final nickname = (_userProfile?['nickname'] ?? '').toString().trim();
    final fullName = (_userProfile?['full_name'] ?? 'Promotor').toString();
    final name = nickname.isNotEmpty ? nickname : fullName;
    final store = (_userProfile?['store_name'] ?? 'No Store').toString();
    final avatarUrl = _userProfile?['avatar_url'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SELAMAT DATANG',
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w700,
                    color: PromotorColors.muted2,
                    letterSpacing: 2.0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(name, style: PromotorText.display(size: 28)),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: PromotorColors.goldDim,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: PromotorColors.goldGlow),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: const BoxDecoration(
                          color: PromotorColors.gold,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        store.toUpperCase(),
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: PromotorColors.gold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: PromotorColors.s1,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: PromotorColors.s3),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image(
                        image: CachedNetworkImageProvider(avatarUrl),
                        fit: BoxFit.cover,
                      )
                    : const Icon(Icons.person, color: PromotorColors.cream2),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  _buildHeaderIconButtonV2(Icons.search_rounded),
                  const SizedBox(width: 8),
                  _buildHeaderIconButtonV2(
                    Icons.notifications_none_rounded,
                    dot: true,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButtonV2(IconData icon, {bool dot = false}) {
    return Stack(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: PromotorColors.s1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PromotorColors.s3),
          ),
          child: Icon(icon, color: PromotorColors.muted, size: 18),
        ),
        if (dot)
          Positioned(
            top: 6,
            right: 6,
            child: Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: PromotorColors.red,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDateRowV2() {
    final dateLabel = DateFormat(
      'EEEE, d MMMM',
      'id_ID',
    ).format(DateTime.now());
    final status = _isLoadingActivity
        ? 'Memeriksa'
        : (_hasClockInToday ? 'Sudah absen' : 'Belum absen');
    final timeLabel = _clockInTimeLabel ?? '--:--';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            dateLabel,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: PromotorColors.muted,
            ),
          ),
          PromotorPill(
            label: status,
            subLabel: timeLabel,
            dotColor: _hasClockInToday
                ? PromotorColors.green
                : PromotorColors.amber,
          ),
        ],
      ),
    );
  }

  Widget _buildTargetAllTypeCardV2() {
    final achievement = _targetAchievementPct();
    final targetOmzet = _toNum(_targetData?['target_omzet']);
    final actualOmzet = _toNum(_targetData?['actual_omzet']);
    final weekly = _currentWeekData();
    final weeklyPct = _toNum(
      weekly?['achievement_omzet_pct'] ?? weekly?['achievement_pct'],
    ).toDouble();
    final weeklyTarget = _toNum(
      weekly?['target_omzet'] ?? weekly?['target'],
    ).toDouble();
    final weeklyActual = _toNum(
      weekly?['actual_omzet'] ?? weekly?['actual'],
    ).toDouble();
    final dailyPct = _toNum(
      _dailyTargetData?['achievement_daily_all_type_pct'],
    ).toDouble();
    final dailyTarget = _toNum(
      _dailyTargetData?['target_omzet'] ?? _dailyTargetData?['target'],
    ).toDouble();
    final dailyActual = _toNum(
      _dailyTargetData?['actual_omzet'] ?? _dailyTargetData?['actual'],
    ).toDouble();
    final sisaTarget = (targetOmzet - actualOmzet).toDouble();

    return PromotorCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Body - Nominal target + realisasi
          _buildTargetCardBodyV2(
            achievement,
            targetOmzet,
            actualOmzet,
            sisaTarget,
          ),
          // Period section - Harian & Mingguan
          _buildTargetPeriodSectionV2(
            dailyPct,
            dailyActual.toDouble(),
            dailyTarget.toDouble(),
            weeklyPct,
            weeklyActual.toDouble(),
            weeklyTarget.toDouble(),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCardBodyV2(
    double achievement,
    num targetOmzet,
    num actualOmzet,
    num sisaTarget,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: PromotorColors.s3, width: 1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const PromotorSectionLabel('Target All-Type'),
              const Spacer(),
              _buildChip('Bulanan'),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nominal Target Bulan Ini',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: PromotorColors.muted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _targetData == null
                          ? 'Belum di-set'
                          : _formatRupiah(targetOmzet),
                      style: PromotorText.display(size: 30),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _targetData == null
                          ? 'Target belum diset'
                          : 'Pencapaian saat ini: ${_formatRupiah(actualOmzet)}',
                      style: PromotorText.outfit(
                        size: 15,
                        weight: FontWeight.w600,
                        color: PromotorColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildAchievementBoxV2(achievement),
              const SizedBox(width: 10),
              Expanded(
                child: _buildProgressSectionV2(
                  achievement,
                  actualOmzet,
                  sisaTarget,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementBoxV2(double achievement) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: PromotorColors.s2,
        border: Border.all(color: PromotorColors.s4),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            _targetData == null ? '-' : '${achievement.toStringAsFixed(0)}%',
            style: PromotorText.display(size: 22, color: PromotorColors.gold),
          ),
          const SizedBox(height: 2),
          Text(
            'Tercapai',
            style: PromotorText.outfit(
              size: 8,
              weight: FontWeight.w700,
              color: PromotorColors.muted,
              letterSpacing: 0.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressSectionV2(
    double achievement,
    num actualOmzet,
    num sisaTarget,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Tercapai: ${_formatCompactRupiah(actualOmzet)}',
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w600,
                color: PromotorColors.cream2,
              ),
            ),
            Text(
              'Sisa: ${_formatCompactRupiah(sisaTarget)}',
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w600,
                color: PromotorColors.cream2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        PromotorProgressBar(value: (achievement / 100).clamp(0, 1), height: 5),
      ],
    );
  }

  Widget _buildTargetPeriodSectionV2(
    double dailyPct,
    double dailyActual,
    double dailyTarget,
    double weeklyPct,
    double weeklyActual,
    double weeklyTarget,
  ) {
    return Row(
      children: [
        Expanded(
          child: _buildPeriodItemV2(
            label: 'Target Harian',
            percentage: dailyPct,
            actual: dailyActual.toDouble(),
            target: dailyTarget.toDouble(),
          ),
        ),
        Container(width: 1, height: 60, color: PromotorColors.s3),
        Expanded(
          child: _buildPeriodItemV2(
            label: 'Target Mingguan',
            percentage: weeklyPct,
            actual: weeklyActual.toDouble(),
            target: weeklyTarget.toDouble(),
          ),
        ),
      ],
    );
  }

  Widget _buildPeriodItemV2({
    required String label,
    required double percentage,
    required double actual,
    required double target,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: PromotorText.outfit(
                  size: 8,
                  weight: FontWeight.w700,
                  color: PromotorColors.muted,
                  letterSpacing: 1.0,
                ),
              ),
              if (_targetData != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: PromotorColors.goldDim,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '${percentage.toStringAsFixed(0)}%',
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w700,
                      color: PromotorColors.gold,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _targetData == null ? 'Belum di-set' : _formatRupiah(actual),
            style: PromotorText.display(size: 16, color: PromotorColors.cream2),
          ),
          const SizedBox(height: 2),
          Text(
            _targetData == null ? '' : 'dari ${_formatRupiah(target)}',
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w600,
              color: PromotorColors.muted,
            ),
          ),
          const SizedBox(height: 6),
          PromotorProgressBar(
            value: _targetData == null ? 0 : (percentage / 100).clamp(0, 1),
            height: 3,
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: PromotorColors.goldDim,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: PromotorColors.goldGlow),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 8,
          weight: FontWeight.w700,
          color: PromotorColors.gold,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildActivityCardV2() {
    // Get activity data from targetData or default values
    final completedCount = _getActivityCompletedCount();
    final totalCount = 5; // Default: Absen, Stok, Jual, Jadwal, +2 more
    final progress = totalCount > 0 ? completedCount / totalCount : 0.0;

    return GestureDetector(
      onTap: () => context.push('/promotor/workplace'),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: PromotorColors.s1,
          border: Border.all(color: PromotorColors.s3),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 24,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          children: [
            // Left accent bar
            Container(
              width: 3,
              height: 60,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [PromotorColors.gold, PromotorColors.amber],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(14),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Icon
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: PromotorColors.goldDim,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.checklist_outlined,
                color: PromotorColors.gold,
                size: 17,
              ),
            ),
            const SizedBox(width: 12),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Aktivitas Hari Ini',
                    style: PromotorText.outfit(
                      size: 15,
                      weight: FontWeight.w700,
                      color: PromotorColors.cream,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 3,
                          decoration: BoxDecoration(
                            color: PromotorColors.s3,
                            borderRadius: BorderRadius.circular(100),
                          ),
                          child: FractionallySizedBox(
                            widthFactor: progress.clamp(0, 1),
                            child: Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    PromotorColors.gold,
                                    PromotorColors.goldLt,
                                  ],
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                ),
                                borderRadius: BorderRadius.circular(100),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      Text(
                        '$completedCount/$totalCount selesai',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: PromotorColors.gold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _buildActivityPillsV2(),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Right side
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$completedCount',
                  style: PromotorText.display(
                    size: 22,
                    color: PromotorColors.gold,
                  ),
                ),
                Text(
                  '/$totalCount',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w600,
                    color: PromotorColors.muted,
                  ),
                ),
                const SizedBox(height: 4),
                const Icon(
                  Icons.arrow_forward_ios,
                  color: PromotorColors.muted2,
                  size: 16,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // Keep V3 call sites valid in this backup file by forwarding to the
  // latest implemented backup widgets.
  Widget _buildActivityCardV3() => _buildActivityCardV2();

  Widget _buildActivityPillsV2() {
    // Mock data - in real implementation, fetch from attendance/activity table
    final activities = [
      {'label': 'Absen Masuk', 'done': _hasClockInToday},
      {'label': 'Input Stok', 'done': false},
      {'label': 'Lapor Jual', 'done': false},
      {'label': 'Jadwal', 'done': false},
    ];

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: activities.map((activity) {
        final isDone = activity['done'] as bool;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(
            color: isDone
                ? PromotorColors.green.withValues(alpha: 0.1)
                : PromotorColors.s2,
            borderRadius: BorderRadius.circular(100),
            border: Border.all(
              color: isDone
                  ? PromotorColors.green.withValues(alpha: 0.2)
                  : PromotorColors.s3,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isDone)
                Container(
                  width: 4,
                  height: 4,
                  decoration: const BoxDecoration(
                    color: PromotorColors.green,
                    shape: BoxShape.circle,
                  ),
                ),
              if (isDone) const SizedBox(width: 3),
              Text(
                activity['label'] as String,
                style: PromotorText.outfit(
                  size: 8,
                  weight: FontWeight.w600,
                  color: isDone ? PromotorColors.green : PromotorColors.muted,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  int _getActivityCompletedCount() {
    int count = 0;
    if (_hasClockInToday) count++;
    // Add more logic here to check other activities
    return count;
  }

  Widget _buildMiniStatV2({
    required String label,
    required String value,
    required double progress,
    bool amber = false,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PromotorColors.s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PromotorColors.s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: PromotorColors.muted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: PromotorText.outfit(
              size: 16,
              weight: FontWeight.w700,
              color: PromotorColors.cream,
            ),
          ),
          const SizedBox(height: 6),
          PromotorProgressBar(
            value: progress.clamp(0, 1),
            height: 6,
            useAmber: amber,
          ),
        ],
      ),
    );
  }

  Widget _buildFocusAndBonusRowV2() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        if (isNarrow) {
          return Column(
            children: [
              _buildFocusCardV2(),
              const SizedBox(height: 8),
              _buildBonusCardV2(),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: _buildFocusCardV2()),
            const SizedBox(width: 8),
            Expanded(child: _buildBonusCardV2()),
          ],
        );
      },
    );
  }

  Widget _buildFocusAndBonusRowV3() => _buildFocusAndBonusRowV2();

  Widget _buildFocusCardV2() {
    final targetFokus = _toNum(_targetData?['target_fokus_total']).toDouble();
    final actualFokus = _toNum(_targetData?['actual_fokus_total']).toDouble();
    final achievementFokus = _toNum(
      _targetData?['achievement_fokus_pct'],
    ).toDouble();
    final sisaFokus = (targetFokus - actualFokus).toDouble();
    final fokusDetails = List<Map<String, dynamic>>.from(
      (_targetData?['fokus_details'] as List?) ?? const [],
    );
    final topDetails = fokusDetails.take(3).toList();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: PromotorColors.s1,
        border: Border.all(color: PromotorColors.s3),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with chip
          Container(
            padding: const EdgeInsets.fromLTRB(16, 13, 16, 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: PromotorColors.s3, width: 1),
              ),
            ),
            child: Row(
              children: [
                const PromotorSectionLabel('Fokus Produk'),
                const Spacer(),
                _buildChip('${fokusDetails.length} Tipe Aktif'),
              ],
            ),
          ),
          // Summary row (4 columns)
          _buildFocusSummaryRowV2(
            targetFokus.toDouble(),
            actualFokus.toDouble(),
            sisaFokus.toDouble(),
            achievementFokus,
          ),
          // Product list
          if (topDetails.isNotEmpty) ...[
            const SizedBox(height: 4),
            ...List.generate(
              topDetails.length,
              (index) => _buildFocusProductItemV2(topDetails[index], index + 1),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusSummaryRowV2(
    double target,
    double actual,
    double sisa,
    double achievement,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: PromotorColors.s3, width: 1)),
      ),
      child: Row(
        children: [
          _buildFocusSummaryItemV2('Target', target.toInt().toString(), null),
          _buildFocusSummaryItemV2(
            'Terjual',
            actual.toInt().toString(),
            PromotorColors.green,
          ),
          _buildFocusSummaryItemV2(
            'Sisa',
            sisa.toInt().toString(),
            PromotorColors.amber,
          ),
          _buildFocusSummaryItemV2(
            'Progress',
            '${achievement.toStringAsFixed(0)}%',
            PromotorColors.gold,
          ),
        ],
      ),
    );
  }

  Widget _buildFocusSummaryItemV2(
    String label,
    String value,
    Color? valueColor,
  ) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 8,
              weight: FontWeight.w600,
              color: PromotorColors.muted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: PromotorText.display(
              size: 20,
              color: valueColor ?? PromotorColors.cream,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusProductItemV2(Map<String, dynamic> detail, int index) {
    final bundleName = (detail['bundle_name'] ?? 'Produk').toString();
    final targetQty = _toNum(detail['target_qty']);
    final actualQty = _toNum(detail['actual_qty']);
    final pct = targetQty > 0 ? ((actualQty / targetQty) * 100) : 0.0;
    final isComplete = pct >= 100;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: PromotorColors.s3.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: [
          // Number
          SizedBox(
            width: 14,
            child: Text(
              '$index',
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: PromotorColors.muted2,
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Product info
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
                    color: PromotorColors.cream2,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          color: PromotorColors.s3,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: FractionallySizedBox(
                          widthFactor: (pct / 100).clamp(0, 1),
                          child: Container(
                            decoration: BoxDecoration(
                              gradient: isComplete
                                  ? LinearGradient(
                                      colors: [
                                        PromotorColors.green,
                                        PromotorColors.green.withValues(
                                          alpha: 0.6,
                                        ),
                                      ],
                                    )
                                  : LinearGradient(
                                      colors: [
                                        PromotorColors.gold,
                                        PromotorColors.goldLt,
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
                          color: isComplete
                              ? PromotorColors.green
                              : PromotorColors.gold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Count
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RichText(
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$actualQty',
                      style: PromotorText.display(
                        size: 16,
                        color: PromotorColors.cream,
                      ),
                    ),
                    TextSpan(
                      text: '/$targetQty',
                      style: PromotorText.outfit(
                        size: 15,
                        weight: FontWeight.w600,
                        color: PromotorColors.muted,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                'unit',
                style: PromotorText.outfit(
                  size: 8,
                  weight: FontWeight.w600,
                  color: PromotorColors.muted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBonusCardV2() {
    final totalBonus = _getTotalBonus();
    final personalTarget = _getPersonalTarget();
    final bonusPct = personalTarget > 0
        ? ((totalBonus / personalTarget) * 100).clamp(0, 100).toDouble()
        : 0.0;
    final dailyBonus = _getDailyBonus();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF231c12), Color(0xFF1c1610)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: PromotorColors.gold.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 32,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: PromotorColors.gold.withValues(alpha: 0.04),
            blurRadius: 40,
            spreadRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top border glow
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  PromotorColors.gold.withValues(alpha: 0.6),
                  Colors.transparent,
                ],
              ),
            ),
          ),
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: PromotorColors.gold.withValues(alpha: 0.08),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                const PromotorSectionLabel('Bonus'),
                const Spacer(),
                _buildBonusStatusBadge(),
              ],
            ),
          ),
          // Bonus columns (Daily + Total)
          _buildBonusColumnsV2(dailyBonus, totalBonus, personalTarget),
          // Progress bar
          Container(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Progress',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: PromotorColors.muted,
                      ),
                    ),
                    Text(
                      '${bonusPct.toStringAsFixed(0)}%',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: PromotorColors.gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Container(
                  height: 6,
                  decoration: BoxDecoration(
                    color: PromotorColors.s3,
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: FractionallySizedBox(
                    widthFactor: (bonusPct / 100).clamp(0, 1),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [PromotorColors.gold, PromotorColors.goldLt],
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        ),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Breakdown rows
          _buildBonusBreakdownV2(totalBonus, personalTarget),
          // CTA Button
          Container(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => context.push('/promotor/bonus-detail'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: PromotorColors.gold,
                  foregroundColor: const Color(0xFF1a1208),
                  elevation: 0,
                  shadowColor: PromotorColors.gold.withValues(alpha: 0.3),
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
                  child: Text(
                    'Lihat Detail Bonus',
                    maxLines: 1,
                    style: PromotorText.outfit(
                      size: 15,
                      weight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusStatusBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: PromotorColors.goldDim,
        border: Border.all(color: PromotorColors.gold.withValues(alpha: 0.2)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 4,
            height: 4,
            decoration: const BoxDecoration(
              color: PromotorColors.gold,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Aktif',
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: PromotorColors.gold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusColumnsV2(
    num dailyBonus,
    num totalBonus,
    num personalTarget,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // Daily bonus
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: PromotorColors.s2,
                border: Border.all(color: PromotorColors.s3),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Harian',
                    style: PromotorText.outfit(
                      size: 8,
                      weight: FontWeight.w700,
                      color: PromotorColors.muted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Rp ',
                          style: PromotorText.outfit(
                            size: 15,
                            weight: FontWeight.w600,
                            color: PromotorColors.muted,
                          ),
                        ),
                        TextSpan(
                          text: _formatCompactRupiah(
                            dailyBonus,
                          ).replaceAll('Rp ', ''),
                          style: PromotorText.display(
                            size: 18,
                            color: PromotorColors.goldLt,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Bonus hari ini',
                    style: PromotorText.outfit(
                      size: 8,
                      weight: FontWeight.w600,
                      color: PromotorColors.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Total bonus
          Expanded(
            flex: 11,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Bonus',
                  style: PromotorText.outfit(
                    size: 8,
                    weight: FontWeight.w700,
                    color: PromotorColors.muted,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(
                        text: _formatRupiah(totalBonus).substring(
                          0,
                          _formatRupiah(totalBonus).lastIndexOf(' '),
                        ),
                        style: PromotorText.display(
                          size: 26,
                          weight: FontWeight.w900,
                          color: PromotorColors.goldLt,
                        ),
                      ),
                      TextSpan(
                        text: ' ${_formatRupiah(totalBonus).split(' ').last}',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w600,
                          color: PromotorColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'dari ${_formatCompactRupiah(personalTarget)} target',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w600,
                    color: PromotorColors.muted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusBreakdownV2(num totalBonus, num personalTarget) {
    final breakdown = [
      {
        'label': 'Bonus All-Type',
        'value': _formatRupiah(totalBonus * 0.6),
        'highlight': true,
      },
      {'label': 'Bonus Fokus', 'value': _formatRupiah(totalBonus * 0.3)},
      {'label': 'Bonus Harian', 'value': _formatRupiah(totalBonus * 0.1)},
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(0, 2, 0, 12),
      child: Column(
        children: breakdown.map((item) {
          final isHighlight = item['highlight'] as bool;
          return Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withValues(alpha: 0.03),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  item['label'] as String,
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w600,
                    color: PromotorColors.muted,
                  ),
                ),
                Text(
                  item['value'] as String,
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: isHighlight
                        ? PromotorColors.gold
                        : PromotorColors.cream2,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  num _getDailyBonus() {
    // Mock daily bonus - in real implementation, fetch from database
    return _toNum(_bonusSummary?['daily_bonus'] ?? 0);
  }

  Widget _buildReferenceHeader() {
    final nickname = (_userProfile?['nickname'] ?? '').toString().trim();
    final fullName = (_userProfile?['full_name'] ?? 'Promotor').toString();
    final name = nickname.isNotEmpty ? nickname : fullName;
    final store = (_userProfile?['store_name'] ?? 'No Store').toString();
    final avatarUrl = _userProfile?['avatar_url'] as String?;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.textPrimary,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.textPrimary),
                ),
                clipBehavior: Clip.antiAlias,
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? Image(
                        image: CachedNetworkImageProvider(avatarUrl),
                        fit: BoxFit.cover,
                      )
                    : const Icon(Icons.person, color: Colors.white),
              ),
              const SizedBox(height: 12),
              const Text(
                'Welcome Back,',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppTypeScale.body,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppTypeScale.hero,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                store,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppTypeScale.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        Row(
          children: [
            _buildHeaderIconButton(Icons.search_rounded),
            const SizedBox(width: 12),
            _buildHeaderIconButton(Icons.notifications_none_rounded, dot: true),
          ],
        ),
      ],
    );
  }

  Widget _buildHeaderIconButton(IconData icon, {bool dot = false}) {
    return Stack(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.textPrimary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Icon(icon, color: Colors.white, size: 20),
        ),
        if (dot)
          Positioned(
            top: 10,
            right: 10,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Color(0xFFDC2626),
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAllTypeSummaryCard() {
    final achievement = _targetAchievementPct();
    final targetOmzet = _toNum(_targetData?['target_omzet']);
    final actualOmzet = _toNum(_targetData?['actual_omzet']);
    final weekly = _currentWeekData();
    final weeklyPct = _toNum(
      weekly?['achievement_omzet_pct'] ?? weekly?['achievement_pct'],
    );
    final dailyPct = _toNum(
      _dailyTargetData?['achievement_daily_all_type_pct'],
    );
    final nowLabel = DateFormat('d MMMM', 'id_ID').format(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: _iosCardDecoration(
        color: const Color(0xFFA6E3E9),
        borderColor: Colors.white.withValues(alpha: 0.45),
        radius: 32,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.check_circle, size: 16, color: Colors.black),
                        SizedBox(width: 8),
                        Text(
                          'Target All-Type',
                          style: TextStyle(
                            color: Colors.black,
                            fontSize: AppTypeScale.body,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _targetData == null
                          ? 'Belum di-set'
                          : '${achievement.toStringAsFixed(0)}%',
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: AppTypeScale.hero,
                        fontWeight: FontWeight.w700,
                        height: 0.95,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$nowLabel achievement',
                      style: const TextStyle(
                        color: Colors.black54,
                        fontSize: AppTypeScale.support,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              _buildCircularTargetMeter(
                progress: achievement / 100,
                mainLabel: _targetData == null
                    ? '-'
                    : _formatCompactRupiah(actualOmzet),
                subLabel: _targetData == null ? 'Target' : 'Actual',
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _buildMiniProgressPanel(
                  label: 'Weekly Progress',
                  value: weekly == null
                      ? 'Belum di-set'
                      : '${weeklyPct.toStringAsFixed(0)}%',
                  progress: weekly == null ? 0 : weeklyPct / 100,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildMiniProgressPanel(
                  label: 'Daily Progress',
                  value: _dailyTargetData == null
                      ? (_isLoadingDailyTarget ? 'Memuat...' : 'Belum di-set')
                      : '${dailyPct.toStringAsFixed(0)}%',
                  progress: _dailyTargetData == null ? 0 : dailyPct / 100,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (achievement / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: Colors.black.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _targetData == null
                    ? 'Target belum diset'
                    : _formatRupiah(targetOmzet),
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: AppTypeScale.support,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                _targetData == null ? '-' : _formatRupiah(actualOmzet),
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: AppTypeScale.support,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCircularTargetMeter({
    required double progress,
    required String mainLabel,
    required String subLabel,
  }) {
    final safeProgress = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
          ),
          SizedBox(
            width: 80,
            height: 80,
            child: CircularProgressIndicator(
              value: safeProgress,
              strokeWidth: 8,
              backgroundColor: const Color(0xFFE0E0E0),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.black),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                mainLabel,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: AppTypeScale.support,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                subLabel,
                style: const TextStyle(
                  color: Colors.black54,
                  fontSize: AppTypeScale.support,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniProgressPanel({
    required String label,
    required String value,
    required double progress,
  }) {
    final safeProgress = progress.clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: _iosCardDecoration(
        color: Colors.black.withValues(alpha: 0.08),
        radius: 18,
        elevated: false,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Colors.black54,
              fontSize: AppTypeScale.support,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: AppTypeScale.title,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: 48,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: safeProgress,
                    minHeight: 4,
                    backgroundColor: Colors.black.withValues(alpha: 0.1),
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.black,
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

  Widget _buildActivityStatusCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: _iosCardDecoration(color: AppColors.textPrimary, radius: 24),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.login, color: Colors.white, size: 16),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Absen Masuk',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: AppTypeScale.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _isLoadingActivity
                      ? 'Memeriksa absensi...'
                      : (_clockInTimeLabel ?? 'Belum absen hari ini'),
                  style: const TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: AppTypeScale.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Text(
            _isLoadingActivity
                ? 'Memuat'
                : (_hasClockInToday ? 'Selesai' : 'Pending'),
            style: const TextStyle(
              color: Color(0xFFA6E3E9),
              fontSize: AppTypeScale.body,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightGrid() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildFocusProductCard()),
        const SizedBox(width: 12),
        Expanded(child: _buildBonusCard()),
      ],
    );
  }

  Widget _buildFocusProductCard() {
    final targetFokus = _toNum(_targetData?['target_fokus_total']);
    final actualFokus = _toNum(_targetData?['actual_fokus_total']);
    final achievementFokus = _toNum(_targetData?['achievement_fokus_pct']);
    final fokusDetails = List<Map<String, dynamic>>.from(
      (_targetData?['fokus_details'] as List?) ?? const [],
    );
    final topDetails = fokusDetails.take(2).toList();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _iosCardDecoration(color: AppColors.textPrimary, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Focus Product',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppTypeScale.support,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _targetData == null
                ? 'Belum di-set'
                : '${actualFokus.toInt()}/${targetFokus.toInt()}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppTypeScale.heading,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Units sold this month',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppTypeScale.support,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (achievementFokus / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFA6E3E9),
              ),
            ),
          ),
          if (topDetails.isNotEmpty) ...[
            const SizedBox(height: 18),
            ...topDetails.map(_buildFocusDetailItem),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusDetailItem(Map<String, dynamic> detail) {
    final bundleName = (detail['bundle_name'] ?? 'Produk fokus').toString();
    final targetQty = _toNum(detail['target_qty']);
    final actualQty = _toNum(detail['actual_qty']);
    final pct = targetQty > 0 ? ((actualQty / targetQty) * 100) : 0.0;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  bundleName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: AppTypeScale.support,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${actualQty.toInt()}/${targetQty.toInt()}',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: AppTypeScale.support,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: (pct / 100).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.06),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFA6E3E9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusCard() {
    final totalBonus = _getTotalBonus();
    final personalTarget = _getPersonalTarget();
    final bonusPct = personalTarget > 0
        ? ((totalBonus / personalTarget) * 100).clamp(0, 100).toDouble()
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _iosCardDecoration(color: AppColors.textPrimary, radius: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Bonus Est.',
            style: TextStyle(
              color: Colors.white,
              fontSize: AppTypeScale.support,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _formatCompactRupiah(totalBonus),
            style: const TextStyle(
              color: Colors.white,
              fontSize: AppTypeScale.heading,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          const Text(
            'Projected this month',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppTypeScale.support,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          _buildMetricRowCompact(
            'Target',
            _formatCompactRupiah(personalTarget),
          ),
          const SizedBox(height: 8),
          _buildMetricRowCompact('Progress', '${bonusPct.toStringAsFixed(0)}%'),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.go('/promotor/bonus-detail'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFA6E3E9),
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(40),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Lihat Bonus',
                style: TextStyle(
                  fontSize: AppTypeScale.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _showSetPersonalTargetDialog,
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(40),
                side: BorderSide(color: Colors.white.withValues(alpha: 0.2)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                personalTarget > 0 ? 'Ubah Target' : 'Set Target',
                style: const TextStyle(
                  fontSize: AppTypeScale.body,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRowCompact(String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: AppTypeScale.support,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: AppTypeScale.support,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Map<String, dynamic>? _currentWeekData() {
    final weeklyData = List<Map<String, dynamic>>.from(
      (_targetData?['weekly_breakdown'] as List?) ?? const [],
    );
    if (weeklyData.isEmpty) return null;

    final now = DateTime.now();
    for (final row in weeklyData) {
      final start = DateTime.tryParse('${row['start_date']}');
      final end = DateTime.tryParse('${row['end_date']}');
      if (start == null || end == null) continue;
      if (!now.isBefore(start) && !now.isAfter(end)) {
        return row;
      }
    }
    return weeklyData.first;
  }

  String _formatCompactRupiah(num value) {
    return 'Rp ${NumberFormat.decimalPattern('id_ID').format(value)}';
  }

  double _targetAchievementPct() {
    if (_targetData == null) return 0.0;
    final value = _targetData?['achievement_omzet_pct'];
    return (value is num) ? value.toDouble() : 0.0;
  }

  num _getTotalBonus() {
    return _toNum(
      _bonusSummary?['total_bonus'] ?? _bonusSummary?['bonus_total'],
    );
  }

  num _getPersonalTarget() => _toNum(_userProfile?['personal_bonus_target']);

  void _showSetPersonalTargetDialog() {
    final currentTarget = _toNum(
      _userProfile?['personal_bonus_target'],
    ).toInt();

    // Helper to format number with thousand separator
    String formatWithSeparator(int value) {
      if (value == 0) return '';
      return value.toString().replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
        (Match m) => '${m[1]}.',
      );
    }

    final controller = TextEditingController(
      text: formatWithSeparator(currentTarget),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.flag, color: AppColors.info),
            SizedBox(width: 8),
            Text('Target Bonus Anda'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Berapa target bonus yang ingin Anda capai bulan ini?',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Target Bonus (Rp)',
                prefixText: 'Rp ',
                border: OutlineInputBorder(),
                hintText: 'Contoh: 500.000',
              ),
              autofocus: true,
              onChanged: (value) {
                // Remove non-digits and reformat
                final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                final number = int.tryParse(digitsOnly) ?? 0;
                final formatted = formatWithSeparator(number);
                if (formatted != value) {
                  controller.value = TextEditingValue(
                    text: formatted,
                    selection: TextSelection.collapsed(
                      offset: formatted.length,
                    ),
                  );
                }
              },
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _buildQuickAmountChip(controller, 300000),
                _buildQuickAmountChip(controller, 500000),
                _buildQuickAmountChip(controller, 1000000),
                _buildQuickAmountChip(controller, 2000000),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount =
                  int.tryParse(
                    controller.text.replaceAll(RegExp(r'[^0-9]'), ''),
                  ) ??
                  0;
              Navigator.pop(context);
              await _savePersonalBonusTarget(amount);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.info,
              foregroundColor: Colors.white,
            ),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAmountChip(TextEditingController controller, int amount) {
    // Format with thousand separator
    String formatted = amount.toString().replaceAllMapped(
      RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
      (Match m) => '${m[1]}.',
    );
    return ActionChip(
      label: Text(
        _formatRupiah(amount),
        style: const TextStyle(fontSize: AppTypeScale.support),
      ),
      onPressed: () => controller.text = formatted,
    );
  }

  Future<void> _savePersonalBonusTarget(int amount) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client.rpc(
        'update_personal_bonus_target',
        params: {'p_user_id': userId, 'p_target_amount': amount},
      );

      // Update local state
      if (mounted) {
        setState(() {
          _userProfile?['personal_bonus_target'] = amount;
        });
        await showSuccessDialog(
          context,
          title: amount > 0 ? 'Target Berhasil Disimpan!' : 'Target Dihapus',
          message: amount > 0
              ? 'Target bonus pribadi Anda telah tersimpan'
              : 'Target bonus pribadi telah dihapus',
        );
      }
    } catch (e) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Gagal Menyimpan',
          message: 'Terjadi kesalahan: $e',
        );
      }
    }
  }
}
