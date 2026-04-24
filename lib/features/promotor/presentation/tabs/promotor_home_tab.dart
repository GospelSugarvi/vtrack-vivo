// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

import 'package:intl/intl.dart';
import '../../../../core/router/app_route_names.dart';
import '../../../../core/utils/avatar_refresh_bus.dart';
import '../../../../core/utils/promotor_home_refresh_bus.dart';
import '../../../../core/utils/success_dialog.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../features/notifications/presentation/widgets/app_notification_bell_button.dart';
import '../../../../ui/ui.dart';
import '../../../../ui/patterns/app_target_hero_card.dart';
import '../../../../ui/promotor/promotor.dart';

final Map<String, Map<String, dynamic>> _promotorHomeProfileMemoryCache =
    <String, Map<String, dynamic>>{};

class PromotorHomeTab extends StatefulWidget {
  const PromotorHomeTab({super.key});

  @override
  State<PromotorHomeTab> createState() => _PromotorHomeTabState();
}

class _PromotorHomeTabState extends State<PromotorHomeTab> {
  FieldThemeTokens get t => context.fieldTokens;
  Map<String, dynamic>? _userProfile;
  bool _headerIdentityReady = false;
  bool _headerAvatarReady = false;
  bool _hasClockInToday = false;
  String? _clockInTimeLabel;
  Map<String, dynamic>? _targetData;
  Map<String, dynamic>? _dailyTargetData;
  Map<String, dynamic>? _yesterdayAchievementData;
  Map<String, dynamic>? _todayActivityData;
  Map<String, dynamic>? _dailyBonusData;
  Map<String, dynamic>? _weeklyBonusData;
  Map<String, dynamic>? _vastDailyData;
  Map<String, dynamic>? _vastWeeklyData;
  Map<String, dynamic>? _vastMonthlyData;
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

  Map<String, dynamic> _sessionProfileSeed() {
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final nickname = '${metadata['nickname'] ?? ''}'.trim();
    final fullName =
        '${metadata['full_name'] ?? metadata['name'] ?? 'Promotor'}'.trim();
    return {
      'nickname': nickname,
      'full_name': fullName.isEmpty ? 'Promotor' : fullName,
      'avatar_url': '${metadata['avatar_url'] ?? ''}'.trim(),
    };
  }

  Map<String, dynamic> _initialProfileSeed() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final sessionSeed = _sessionProfileSeed();
    if (userId == null) return sessionSeed;
    final cached = _promotorHomeProfileMemoryCache[userId];
    if (cached == null) return sessionSeed;
    return {...sessionSeed, ...cached};
  }

  bool _hasResolvedIdentity(Map<String, dynamic>? profile) {
    if (profile == null) return false;
    final fullName = '${profile['full_name'] ?? ''}'.trim();
    final nickname = '${profile['nickname'] ?? ''}'.trim();
    final avatarUrl = '${profile['avatar_url'] ?? ''}'.trim();
    return nickname.isNotEmpty ||
        (fullName.isNotEmpty && fullName.toLowerCase() != 'promotor') ||
        avatarUrl.isNotEmpty;
  }

  Future<void> _refreshHeaderVisualState() async {
    final avatarUrl = '${_userProfile?['avatar_url'] ?? ''}'.trim();
    final identityReady = _hasResolvedIdentity(_userProfile);
    if (!mounted) return;
    setState(() {
      _headerIdentityReady = identityReady;
      _headerAvatarReady = !identityReady || avatarUrl.isEmpty;
    });
    if (!identityReady || avatarUrl.isEmpty || !mounted) return;
    try {
      await precacheImage(CachedNetworkImageProvider(avatarUrl), context);
    } catch (_) {
      // Keep showing the header even if pre-cache fails.
    }
    if (!mounted) return;
    setState(() {
      _headerAvatarReady = true;
    });
  }

  TextStyle _sectionTitleStyle({Color? color}) {
    return PromotorText.outfit(
      size: 14,
      weight: FontWeight.w700,
      color: color ?? t.textSecondary,
    );
  }

  Widget _buildSectionHeading(
    String title, {
    IconData? icon,
    Color? accent,
    Widget? trailing,
  }) {
    final resolvedAccent = accent ?? t.primaryAccent;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null) ...[
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: resolvedAccent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: resolvedAccent.withValues(alpha: 0.14)),
            ),
            child: Icon(icon, size: 15, color: resolvedAccent),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: _sectionTitleStyle(color: t.textPrimary)),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing],
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _activeUserId = Supabase.instance.client.auth.currentUser?.id;
    _userProfile = _initialProfileSeed();
    _headerIdentityReady = _hasResolvedIdentity(_userProfile);
    _headerAvatarReady =
        !_headerIdentityReady ||
        '${_userProfile?['avatar_url'] ?? ''}'.trim().isEmpty;
    unawaited(_restoreCachedProfile());
    unawaited(_restoreCachedTargetCards());
    unawaited(_restoreCachedHomeSnapshot());
    unawaited(_refreshHomeData(waitForSnapshot: false));
    unawaited(_refreshHeaderVisualState());
    avatarRefreshTick.addListener(_handleAvatarRefresh);
    promotorHomeRefreshTick.addListener(_handleHomeRefresh);
    _authSub = Supabase.instance.client.auth.onAuthStateChange.listen((event) {
      final newUserId = event.session?.user.id;
      if (newUserId == null || newUserId == _activeUserId) return;
      _activeUserId = newUserId;
      if (!mounted) return;
      setState(() {
        _userProfile = _initialProfileSeed();
        _headerIdentityReady = _hasResolvedIdentity(_userProfile);
        _headerAvatarReady =
            !_headerIdentityReady ||
            '${_userProfile?['avatar_url'] ?? ''}'.trim().isEmpty;
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
      unawaited(_refreshHeaderVisualState());
      unawaited(_restoreCachedProfile());
      unawaited(_restoreCachedTargetCards());
      unawaited(_restoreCachedHomeSnapshot());
      unawaited(_refreshHomeData(waitForSnapshot: false));
    });
  }

  void _handleAvatarRefresh() {
    if (!mounted) return;
    unawaited(_loadData());
  }

  void _handleHomeRefresh() {
    if (!mounted) return;
    unawaited(_refreshHomeData(waitForSnapshot: false));
  }

  @override
  void dispose() {
    avatarRefreshTick.removeListener(_handleAvatarRefresh);
    promotorHomeRefreshTick.removeListener(_handleHomeRefresh);
    _authSub?.cancel();
    super.dispose();
  }

  Future<void> _refreshHomeData({required bool waitForSnapshot}) async {
    await _loadQuickTargetCards();
    await _loadData();
    if (waitForSnapshot) {
      await _loadHomeSnapshot();
      return;
    }
    unawaited(_loadHomeSnapshot());
  }

  String _dailyTargetCacheKey(String userId) =>
      'promotor_home.daily_target.$userId';

  String _monthlyTargetCacheKey(String userId) =>
      'promotor_home.monthly_target.$userId';

  String _profileCacheKey(String userId) => 'promotor_home.profile.$userId';

  String _homeSnapshotCacheKey(String userId) =>
      'promotor_home.snapshot.$userId';

  Future<void> _restoreCachedProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profileCacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final cachedProfile = Map<String, dynamic>.from(decoded);
      _promotorHomeProfileMemoryCache[userId] = cachedProfile;
      if (!mounted) return;
      setState(() {
        _userProfile = {...?_userProfile, ...cachedProfile};
        _headerIdentityReady = _hasResolvedIdentity(_userProfile);
      });
      unawaited(_refreshHeaderVisualState());
    } catch (e) {
      debugPrint('Error restoring cached profile: $e');
    }
  }

  Future<void> _restoreCachedTargetCards() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final dailyRaw = prefs.getString(_dailyTargetCacheKey(userId));
      final monthlyRaw = prefs.getString(_monthlyTargetCacheKey(userId));
      Map<String, dynamic>? decodeMap(String? raw) {
        if (raw == null || raw.trim().isEmpty) return null;
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
        return null;
      }

      final cachedDaily = decodeMap(dailyRaw);
      final cachedMonthly = decodeMap(monthlyRaw);
      if (!mounted) return;
      if (cachedDaily == null && cachedMonthly == null) return;
      setState(() {
        _dailyTargetData ??= cachedDaily;
        _targetData ??= cachedMonthly;
        _monthlySellOutTarget = _toNum(
          cachedMonthly?['target_omzet'] ?? _targetData?['target_omzet'],
        );
      });
    } catch (e) {
      debugPrint('Error restoring cached target cards: $e');
    }
  }

  Future<void> _persistTargetCards({
    Map<String, dynamic>? dailyTarget,
    Map<String, dynamic>? monthlyTarget,
  }) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      if (dailyTarget != null) {
        await prefs.setString(
          _dailyTargetCacheKey(userId),
          jsonEncode(dailyTarget),
        );
      }
      if (monthlyTarget != null) {
        await prefs.setString(
          _monthlyTargetCacheKey(userId),
          jsonEncode(monthlyTarget),
        );
      }
    } catch (e) {
      debugPrint('Error persisting target cards: $e');
    }
  }

  Future<void> _restoreCachedHomeSnapshot() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_homeSnapshotCacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final payload = Map<String, dynamic>.from(decoded);

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
        if (value is! List) return <Map<String, dynamic>>[];
        return value
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }

      final cachedDailyTarget = asMap(payload['daily_target']);
      final cachedMonthlyTarget = asMap(payload['monthly_target']);
      final cachedWeeklySnapshots = asList(payload['weekly_snapshots']);
      final resolvedSelectedWeeklyKey = _resolveSelectedWeeklyKey(
        cachedWeeklySnapshots,
        preferredKey: _selectedWeeklyKey,
        activeWeekNumber: _toNum(
          payload['active_week_number'] ??
              cachedDailyTarget?['active_week_number'],
        ).toInt(),
      );

      if (!mounted) return;
      setState(() {
        _dailyTargetData ??= cachedDailyTarget;
        _targetData ??= cachedMonthlyTarget;
        _dailyBonusData ??= asMap(payload['daily_bonus']);
        _weeklyBonusData ??= asMap(payload['weekly_bonus']);
        _vastDailyData ??= asMap(payload['vast_daily']);
        _vastWeeklyData ??= asMap(payload['vast_weekly']);
        _vastMonthlyData ??= asMap(payload['vast_monthly']);
        if (_weeklySnapshots.isEmpty) {
          _weeklySnapshots = cachedWeeklySnapshots;
        }
        _bonusSummary ??= asMap(payload['monthly_bonus']);
        if (_dailySpecialRows.isEmpty) {
          _dailySpecialRows = asList(payload['daily_special_rows']);
        }
        if (_weeklySpecialRows.isEmpty) {
          _weeklySpecialRows = asList(payload['weekly_special_rows']);
        }
        if (_monthlySpecialRows.isEmpty) {
          _monthlySpecialRows = asList(payload['monthly_special_rows']);
        }
        _yesterdayAchievementData ??= asMap(payload['yesterday_achievement']);
        _todayActivityData ??= asMap(payload['today_activity']);
        _previousMonthOmzet = _previousMonthOmzet == 0
            ? _toNum(payload['previous_month_omzet'])
            : _previousMonthOmzet;
        if (!_hasClockInToday) {
          _hasClockInToday = payload['clock_in_today'] == true;
        }
        _clockInTimeLabel ??= payload['clock_in_time']?.toString();
        _monthlySellOutTarget = _monthlySellOutTarget == 0
            ? _toNum(
                cachedMonthlyTarget?['target_omzet'] ??
                    payload['monthly_sell_out_target'],
              )
            : _monthlySellOutTarget;
        _selectedWeeklyKey ??= resolvedSelectedWeeklyKey;
      });
    } catch (e) {
      debugPrint('Error restoring cached home snapshot: $e');
    }
  }

  Future<void> _persistHomeSnapshotCache({
    Map<String, dynamic>? dailyTarget,
    Map<String, dynamic>? monthlyTarget,
    Map<String, dynamic>? dailyBonus,
    Map<String, dynamic>? weeklyBonus,
    Map<String, dynamic>? vastDaily,
    Map<String, dynamic>? vastWeekly,
    Map<String, dynamic>? vastMonthly,
    required List<Map<String, dynamic>> weeklySnapshots,
    Map<String, dynamic>? monthlyBonus,
    required List<Map<String, dynamic>> dailySpecialRows,
    required List<Map<String, dynamic>> weeklySpecialRows,
    required List<Map<String, dynamic>> monthlySpecialRows,
    Map<String, dynamic>? yesterdayAchievement,
    Map<String, dynamic>? todayActivity,
    required num previousMonthOmzet,
    required bool hasClockInToday,
    String? clockInTimeLabel,
    required num monthlySellOutTarget,
    required int activeWeekNumber,
  }) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'daily_target': dailyTarget,
        'monthly_target': monthlyTarget,
        'daily_bonus': dailyBonus,
        'weekly_bonus': weeklyBonus,
        'vast_daily': vastDaily,
        'vast_weekly': vastWeekly,
        'vast_monthly': vastMonthly,
        'weekly_snapshots': weeklySnapshots,
        'monthly_bonus': monthlyBonus,
        'daily_special_rows': dailySpecialRows,
        'weekly_special_rows': weeklySpecialRows,
        'monthly_special_rows': monthlySpecialRows,
        'yesterday_achievement': yesterdayAchievement,
        'today_activity': todayActivity,
        'previous_month_omzet': previousMonthOmzet,
        'clock_in_today': hasClockInToday,
        'clock_in_time': clockInTimeLabel,
        'monthly_sell_out_target': monthlySellOutTarget,
        'active_week_number': activeWeekNumber,
      };
      await prefs.setString(_homeSnapshotCacheKey(userId), jsonEncode(payload));
    } catch (e) {
      debugPrint('Error persisting cached home snapshot: $e');
    }
  }

  Future<void> _persistProfileCache(Map<String, dynamic> profile) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      _promotorHomeProfileMemoryCache[userId] = Map<String, dynamic>.from(
        profile,
      );
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileCacheKey(userId), jsonEncode(profile));
    } catch (e) {
      debugPrint('Error persisting profile cache: $e');
    }
  }

  Future<void> _syncAuthMetadataFromProfile(
    Map<String, dynamic> profile,
  ) async {
    try {
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser == null) return;
      final currentMetadata =
          currentUser.userMetadata ?? const <String, dynamic>{};
      final nextMetadata = <String, dynamic>{
        ...currentMetadata,
        'full_name': '${profile['full_name'] ?? ''}'.trim(),
        'nickname': '${profile['nickname'] ?? ''}'.trim(),
        'avatar_url': '${profile['avatar_url'] ?? ''}'.trim(),
        'area': '${profile['area'] ?? ''}'.trim(),
        'role': '${profile['role'] ?? ''}'.trim(),
      };

      bool changed(String key) =>
          '${currentMetadata[key] ?? ''}'.trim() !=
          '${nextMetadata[key] ?? ''}'.trim();

      if (!(changed('full_name') ||
          changed('nickname') ||
          changed('avatar_url') ||
          changed('area') ||
          changed('role'))) {
        return;
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: nextMetadata),
      );
    } catch (e) {
      debugPrint('Error syncing auth metadata: $e');
    }
  }

  Future<void> _loadQuickTargetCards() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final today = DateTime.now().toIso8601String().split('T')[0];
      final results = await Future.wait<dynamic>([
        Supabase.instance.client.rpc(
          'get_daily_target_dashboard',
          params: {'p_user_id': userId, 'p_date': today},
        ),
        Supabase.instance.client.rpc(
          'get_target_dashboard',
          params: {'p_user_id': userId, 'p_period_id': null},
        ),
      ]);

      Map<String, dynamic>? asMap(dynamic value) {
        if (value is Map<String, dynamic>) {
          return Map<String, dynamic>.from(value);
        }
        if (value is Map) {
          return Map<String, dynamic>.from(value);
        }
        if (value is List && value.isNotEmpty && value.first is Map) {
          return Map<String, dynamic>.from(value.first as Map);
        }
        return null;
      }

      final dailyTarget = asMap(results[0]);
      final monthlyTarget = asMap(results[1]);
      if (!mounted) return;
      setState(() {
        _dailyTargetData = dailyTarget ?? _dailyTargetData;
        _targetData = monthlyTarget ?? _targetData;
        _monthlySellOutTarget = _toNum(
          monthlyTarget?['target_omzet'] ?? _targetData?['target_omzet'],
        );
      });
      unawaited(
        _persistTargetCards(
          dailyTarget: dailyTarget,
          monthlyTarget: monthlyTarget,
        ),
      );
    } catch (e) {
      debugPrint('Error loading quick target cards: $e');
    }
  }

  Future<void> _loadHomeSnapshot() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final today = DateTime.now().toIso8601String().split('T')[0];
      final results = await Future.wait<dynamic>([
        Supabase.instance.client.rpc(
          'get_promotor_home_snapshot',
          params: {'p_user_id': userId, 'p_date': today},
        ),
        Supabase.instance.client.rpc(
          'get_promotor_vast_page_snapshot',
          params: {'p_date': today},
        ),
      ]);

      Map<String, dynamic> snapshot = <String, dynamic>{};
      final response = results[0];
      final vastResponse = results[1];
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
      final vastSnapshot = vastResponse is Map<String, dynamic>
          ? Map<String, dynamic>.from(vastResponse)
          : vastResponse is Map
          ? Map<String, dynamic>.from(vastResponse)
          : <String, dynamic>{};
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
        _vastDailyData = asMap(vastSnapshot['daily_period_stats']);
        _vastWeeklyData = asMap(vastSnapshot['weekly_period_stats']);
        _vastMonthlyData = asMap(vastSnapshot['monthly_period_stats']);
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
      unawaited(
        _persistTargetCards(
          dailyTarget: dailyTarget,
          monthlyTarget: monthlyTarget,
        ),
      );
      unawaited(
        _persistHomeSnapshotCache(
          dailyTarget: dailyTarget,
          monthlyTarget: monthlyTarget,
          dailyBonus: asMap(snapshot['daily_bonus']),
          weeklyBonus: asMap(snapshot['weekly_bonus']),
          vastDaily: asMap(vastSnapshot['daily_period_stats']),
          vastWeekly: asMap(vastSnapshot['weekly_period_stats']),
          vastMonthly: asMap(vastSnapshot['monthly_period_stats']),
          weeklySnapshots: weeklySnapshots,
          monthlyBonus: asMap(snapshot['monthly_bonus']),
          dailySpecialRows: asList(snapshot['daily_special_rows']),
          weeklySpecialRows: asList(snapshot['weekly_special_rows']),
          monthlySpecialRows: asList(snapshot['monthly_special_rows']),
          yesterdayAchievement: asMap(snapshot['yesterday_achievement']),
          todayActivity: asMap(snapshot['today_activity']),
          previousMonthOmzet: _toNum(snapshot['previous_month_omzet']),
          hasClockInToday: snapshot['clock_in_today'] == true,
          clockInTimeLabel: snapshot['clock_in_time']?.toString(),
          monthlySellOutTarget: _toNum(monthlyTarget?['target_omzet']),
          activeWeekNumber: activeWeekNumber,
        ),
      );
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
        _vastDailyData = null;
        _vastWeeklyData = null;
        _vastMonthlyData = null;
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
      final userResult = await Supabase.instance.client
          .from('users')
          .select(
            'full_name, nickname, area, role, personal_bonus_target, avatar_url',
          )
          .eq('id', userId)
          .single();
      final userData = Map<String, dynamic>.from(userResult);
      if (mounted) {
        setState(() {
          _userProfile = {...?_userProfile, ...userData};
          _headerIdentityReady = _hasResolvedIdentity(_userProfile);
        });
      }
      unawaited(_refreshHeaderVisualState());
      unawaited(_persistProfileCache({...?_userProfile, ...userData}));
      unawaited(_syncAuthMetadataFromProfile(userData));

      final results = await Future.wait<dynamic>([
        Supabase.instance.client
            .from('assignments_promotor_store')
            .select('store_id, stores(store_name)')
            .eq('promotor_id', userId)
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(1)
            .catchError((error) {
              debugPrint('Error loading store: $error');
              return null;
            }),
        Supabase.instance.client
            .from('hierarchy_sator_promotor')
            .select(
              'sator_id, users!hierarchy_sator_promotor_sator_id_fkey(full_name, nickname)',
            )
            .eq('promotor_id', userId)
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(1)
            .catchError((error) {
              debugPrint('Error loading sator: $error');
              return null;
            }),
      ]);

      String? storeName;
      final storeRows = results[0];
      if (storeRows is List) {
        final assignments = List<Map<String, dynamic>>.from(storeRows);
        final storeData = assignments.isNotEmpty ? assignments.first : null;
        storeName = storeData?['stores']?['store_name'];
      }

      String? satorName;
      final hierarchyRows = results[1];
      if (hierarchyRows is List) {
        final hierarchy = List<Map<String, dynamic>>.from(hierarchyRows);
        final satorData = hierarchy.isNotEmpty
            ? Map<String, dynamic>.from(hierarchy.first)
            : null;
        final satorUser = satorData?['users'] is Map
            ? Map<String, dynamic>.from(satorData!['users'] as Map)
            : null;
        final satorFullName = (satorUser?['full_name'] ?? '').toString().trim();
        satorName = satorFullName;
      }

      final combinedData = {
        ...userData,
        'store_name': storeName,
        'sator_name': satorName,
      };
      if (mounted) {
        setState(() {
          _userProfile = combinedData;
          _headerIdentityReady = _hasResolvedIdentity(_userProfile);
        });
      }
      unawaited(_refreshHeaderVisualState());
      unawaited(_persistProfileCache(Map<String, dynamic>.from(combinedData)));
      unawaited(_syncAuthMetadataFromProfile(combinedData));
    } catch (e, stackTrace) {
      debugPrint('Error: $e');
      debugPrint('StackTrace: $stackTrace');
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

  num _getPersonalTarget() => _toNum(_userProfile?['personal_bonus_target']);

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return RefreshIndicator(
      onRefresh: () async {
        await _refreshHomeData(waitForSnapshot: true);
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
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildHeaderControls(),
              ),
              const SizedBox(height: 20),
              if (_selectedTab == 'harian') ...[
                _buildAbsenRow(),
                const SizedBox(height: 16),
                _buildHarianTab(),
                const SizedBox(height: 20),
                _buildActivityCard(),
              ] else if (_selectedTab == 'mingguan') ...[
                _buildMingguanTab(),
              ] else ...[
                _buildBulananTab(),
              ],
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _buildBonusCard(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    if (!_headerIdentityReady || !_headerAvatarReady) {
      return _buildHeaderSkeleton();
    }
    final nickname = (_userProfile?['nickname'] ?? '').toString().trim();
    final fullName = (_userProfile?['full_name'] ?? 'Promotor')
        .toString()
        .trim();
    final name = fullName.isNotEmpty ? fullName : nickname;
    final area = (_userProfile?['area'] ?? '').toString().trim();
    final store = (_userProfile?['store_name'] ?? 'No Store').toString();
    final sator = (_userProfile?['sator_name'] ?? '').toString().trim();
    final avatarUrl = (_userProfile?['avatar_url'] ?? '').toString().trim();
    final storeLabel = store.isNotEmpty && store != 'null' ? store : 'No Store';
    final satorLabel = sator.isNotEmpty && sator != 'null' ? sator : '-';
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 390;
        final veryCompact = width < 360;
        final horizontal = veryCompact ? 10.0 : 12.0;
        final headerPadding = veryCompact
            ? const EdgeInsets.fromLTRB(10, 10, 10, 8)
            : compact
            ? const EdgeInsets.fromLTRB(12, 12, 12, 10)
            : const EdgeInsets.fromLTRB(14, 14, 14, 12);
        final avatarRadius = veryCompact
            ? 16.0
            : compact
            ? 18.0
            : 20.0;
        final avatarRing = veryCompact ? 1.0 : 1.5;
        final titleSize = veryCompact
            ? 18.0
            : compact
            ? 20.0
            : 22.0;
        final metaSize = veryCompact ? 9.0 : 10.0;
        final contentGap = veryCompact ? 8.0 : 10.0;
        final nameGap = veryCompact ? 3.0 : 5.0;

        Widget buildMetaChip({
          required String label,
          required Color color,
          required IconData icon,
        }) {
          final tint = color.withValues(alpha: isDark ? 0.16 : 0.10);
          final border = color.withValues(alpha: isDark ? 0.28 : 0.18);
          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: veryCompact ? 8 : 9,
              vertical: veryCompact ? 4 : 5,
            ),
            decoration: BoxDecoration(
              color: tint,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: veryCompact ? 10 : 11, color: color),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PromotorText.outfit(
                      size: metaSize,
                      weight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              margin: EdgeInsets.fromLTRB(horizontal, 6, horizontal, 4),
              padding: headerPadding,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDark
                      ? [t.surface1, t.surface2]
                      : [t.surface1, t.background],
                ),
                borderRadius: BorderRadius.circular(veryCompact ? 16 : 20),
                border: Border.all(color: t.surface3),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? t.background.withValues(alpha: 0.16)
                        : const Color(0xFF000000).withValues(alpha: 0.04),
                    blurRadius: veryCompact ? 14 : 18,
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
                          'Home',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PromotorText.display(
                            size: compact ? 18 : 20,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      AppNotificationBellButton(
                        backgroundColor: t.surface1,
                        borderColor: t.surface3,
                        iconColor: t.textMuted,
                        badgeColor: t.danger,
                        badgeTextColor: t.textOnAccent,
                        routePath: '/promotor/notifications',
                      ),
                    ],
                  ),
                  SizedBox(height: compact ? 8 : 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: EdgeInsets.all(avatarRing),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: t.primaryAccentGlow),
                        ),
                        child: UserAvatar(
                          avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
                          fullName: name,
                          radius: avatarRadius,
                          showBorder: false,
                        ),
                      ),
                      SizedBox(width: contentGap),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: PromotorText.display(
                                size: compact ? titleSize - 1 : titleSize,
                                weight: FontWeight.w800,
                                color: t.textPrimary,
                              ),
                            ),
                            SizedBox(height: nameGap),
                            Wrap(
                              spacing: 6,
                              runSpacing: 3,
                              children: [
                                if (storeLabel.isNotEmpty &&
                                    storeLabel.toLowerCase() !=
                                        'belum ada toko')
                                  buildMetaChip(
                                    label: storeLabel,
                                    color: t.primaryAccent,
                                    icon: Icons.storefront_rounded,
                                  ),
                                if (area.isNotEmpty && area != 'null')
                                  buildMetaChip(
                                    label: area,
                                    color: t.primaryAccent,
                                    icon: Icons.place_rounded,
                                  ),
                                if (satorLabel.isNotEmpty &&
                                    satorLabel.toLowerCase() !=
                                        'belum ada sator')
                                  buildMetaChip(
                                    label: satorLabel,
                                    color: t.textSecondary,
                                    icon: Icons.badge_rounded,
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
            ),
          ],
        );
      },
    );
  }

  Widget _buildDateBadge(String label, {double fontSize = 11}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          Icon(Icons.calendar_today_rounded, size: 11, color: t.primaryAccent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
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

  Widget _buildHeaderControls() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 360;
        final dateLabel = compact
            ? DateFormat('d MMM yyyy', 'id_ID').format(DateTime.now())
            : width < 390
            ? DateFormat('EEE, d MMM yyyy', 'id_ID').format(DateTime.now())
            : DateFormat('EEEE, d MMM yyyy', 'id_ID').format(DateTime.now());
        final segmentedWidth = compact ? 232.0 : 248.0;
        final dateMaxWidth = (width - segmentedWidth - 12).clamp(110.0, 220.0);
        final segmented = ConstrainedBox(
          constraints: BoxConstraints(maxWidth: compact ? 232 : 248),
          child: _buildTabBar(),
        );

        return Row(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: dateMaxWidth),
              child: _buildDateBadge(dateLabel, fontSize: compact ? 10 : 11),
            ),
            const Spacer(),
            segmented,
          ],
        );
      },
    );
  }

  Widget _buildHeaderSkeleton() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
      child: Container(
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
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Container(
                    height: 24,
                    decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: t.surface2,
                    shape: BoxShape.circle,
                    border: Border.all(color: t.primaryAccentGlow),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        height: 22,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: t.surface2,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: List<Widget>.generate(
                          3,
                          (_) => Container(
                            width: 82,
                            height: 12,
                            decoration: BoxDecoration(
                              color: t.surface2,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = [
      {'key': 'harian', 'label': 'Harian'},
      {'key': 'mingguan', 'label': 'Mingguan'},
      {'key': 'bulanan', 'label': 'Bulanan'},
    ];
    return IntrinsicWidth(
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: tabs.map((tab) {
            final isSelected = _selectedTab == tab['key'];
            return GestureDetector(
              onTap: () => setState(() => _selectedTab = tab['key'] as String),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                decoration: BoxDecoration(
                  color: isSelected ? t.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tab['label'] as String,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w700,
                    color: isSelected ? t.textOnAccent : t.textMuted,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAbsenRow() {
    final statusColor = _hasClockInToday ? t.success : t.warning;
    final statusText = _hasClockInToday ? 'Sudah Absen' : 'Belum Absen';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _hasClockInToday ? 'Absen Hari Ini' : 'Status Absen',
                style: PromotorText.outfit(
                  size: 12,
                  weight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: statusColor.withValues(alpha: 0.16)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _hasClockInToday
                        ? (_clockInTimeLabel ?? 'Sudah Absen')
                        : statusText,
                    style: PromotorText.outfit(
                      size: 11,
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
    );
  }

  Widget _buildHarianTab() {
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildNewTargetHero(
            label: 'TARGET HARIAN',
            target: safeDailyTarget,
            actual: dailyActual,
            percentage: dailyPct,
            sisa: dailySisa,
          ),
          const SizedBox(height: 16),
          _buildNewFocusSection(
            focusTarget: focusTarget,
            focusActual: focusActual,
            focusPct: focusPct,
            focusSisa: focusSisa,
            specialRows: _dailySpecialRows,
          ),
          const SizedBox(height: 16),
          _buildVastFinanceCard(),
          const SizedBox(height: 20),
          _buildPencapaianKemarin(),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  NEW DESIGN COMPONENTS
  // ═══════════════════════════════════════════════════════════════════════════

  /// Komponen hero target baru — design editorial, big ring centered
  Widget _buildNewTargetHero({
    required String label,
    required num target,
    required num actual,
    required double percentage,
    required num sisa,
    Color? accentColor,
    VoidCallback? onTap,
  }) {
    final accent = accentColor ?? t.primaryAccent;
    final safePct = percentage.isNaN ? 0.0 : percentage.clamp(0, 100);
    final pct = safePct / 100;
    final accentSoft = accent.withValues(alpha: 0.04);
    final accentSoftStrong = accent.withValues(alpha: 0.06);
    final accentLine = accent.withValues(alpha: 0.10);

    final card = Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color.lerp(accentSoftStrong, t.surface1, 0.35)!, t.surface1],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        boxShadow: [
          BoxShadow(
            color: accentSoft,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(color: accentLine),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          // Label
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: accent.withValues(alpha: 0.10)),
            ),
            child: Text(
              label,
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w800,
                color: accent,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Big ring
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 100,
                  height: 100,
                  child: CircularProgressIndicator(
                    value: pct,
                    strokeWidth: 6.5,
                    strokeCap: StrokeCap.round,
                    backgroundColor: accent.withValues(alpha: 0.05),
                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                  ),
                ),
                Text(
                  '${safePct.toStringAsFixed(0)}%',
                  style: PromotorText.display(size: 28, color: accent),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Target amount
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              children: [
                TextSpan(
                  text: 'Rp ',
                  style: PromotorText.outfit(
                    size: 14,
                    weight: FontWeight.w600,
                    color: t.textMuted,
                  ),
                ),
                TextSpan(
                  text: _formatCompactNumber(target),
                  style: PromotorText.display(size: 28, color: t.textPrimary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Realisasi + Sisa row
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Tercapai',
                        style: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w600,
                          color: t.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatCompactRupiah(actual),
                        style: PromotorText.outfit(
                          size: 14,
                          weight: FontWeight.w800,
                          color: t.success,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, height: 32, color: t.surface3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        'Sisa',
                        style: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w600,
                          color: t.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatCompactRupiah(sisa),
                        style: PromotorText.outfit(
                          size: 14,
                          weight: FontWeight.w800,
                          color: t.primaryAccentLight,
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
    );

    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }

  /// Focus section baru — clean grid
  Widget _buildNewFocusSection({
    required num focusTarget,
    required num focusActual,
    required double focusPct,
    required num focusSisa,
    required List<Map<String, dynamic>> specialRows,
  }) {
    final safePct = focusPct.isNaN ? 0.0 : focusPct.clamp(0, 100).toDouble();
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            'Produk Fokus',
            icon: Icons.local_fire_department_rounded,
            trailing: Text(
              '${safePct.toStringAsFixed(0)}%',
              style: PromotorText.display(size: 20, color: t.primaryAccent),
            ),
          ),
          const SizedBox(height: 14),
          // Progress bar
          Container(
            height: 6,
            decoration: BoxDecoration(
              color: t.surface3,
              borderRadius: BorderRadius.circular(100),
            ),
            child: FractionallySizedBox(
              widthFactor: (safePct / 100).clamp(0, 1),
              alignment: Alignment.centerLeft,
              child: Container(
                decoration: BoxDecoration(
                  color: t.primaryAccent,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Stats row
          Row(
            children: [
              _buildNewStatChip(
                'Target',
                _formatUnitTarget(focusTarget),
                t.textPrimary,
              ),
              const SizedBox(width: 8),
              _buildNewStatChip(
                'Terjual',
                focusActual.toInt().toString(),
                t.success,
              ),
              const SizedBox(width: 8),
              _buildNewStatChip(
                'Sisa',
                focusSisa.toInt().toString(),
                t.warning,
              ),
            ],
          ),
          if (specialRows.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(height: 1, color: t.surface3),
            const SizedBox(height: 14),
            Text('Tipe Khusus', style: _sectionTitleStyle()),
            ...specialRows.asMap().entries.map(
              (entry) => _buildNewSpecialItem(
                detail: entry.value,
                index: entry.key + 1,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNewStatChip(String label, String value, Color valueColor) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              label,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w600,
                color: t.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: PromotorText.outfit(
                size: 15,
                weight: FontWeight.w800,
                color: valueColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNewSpecialItem({
    required Map<String, dynamic> detail,
    required int index,
  }) {
    final bundleName = (detail['bundle_name'] ?? 'Tipe Khusus').toString();
    final targetQty = _toNum(detail['target_qty']).toInt();
    final actualQty = _toNum(detail['actual_qty']).toInt();
    final pct = _toNum(detail['pct']).toDouble();
    final safePct = pct.isNaN ? 0.0 : pct.clamp(0, 100).toDouble();

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$index',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: t.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              bundleName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w600,
                color: t.textPrimary,
              ),
            ),
          ),
          Text(
            '$actualQty/$targetQty',
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 40,
            child: Text(
              '${safePct.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: safePct >= 100 ? t.success : t.primaryAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusProductItem({
    required Map<String, dynamic> row,
    required int index,
  }) {
    final modelName = (row['model_name'] ?? '-').toString();
    final actualUnits = _toNum(row['actual_units']).toInt();
    final tags = <String>[
      if (row['is_detail_target'] == true) 'Detail',
      if (row['is_special'] == true) 'Khusus',
    ];

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$index',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: t.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  modelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w600,
                    color: t.textPrimary,
                  ),
                ),
                if (tags.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    tags.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w600,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${actualUnits}u',
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: actualUnits > 0 ? t.primaryAccent : t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildDailyFocusContent({
    required num focusTarget,
    required num focusActual,
    required double focusPct,
    required num focusSisa,
    required List<Map<String, dynamic>> specialRows,
    required List<Map<String, dynamic>> focusRows,
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
          _buildFocusInsightCard(
            title: 'Produk Fokus',
            targetValue: _formatUnitTarget(focusTarget),
            actualValue: focusActual.toInt().toString(),
            remainingValue: _nonNegative(focusSisa).toInt().toString(),
            progressText: '${focusPct.toStringAsFixed(0)}%',
            progressValue: focusPct,
            leftLabel: 'Progress fokus hari ini',
          ),
          if (focusRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(height: 1, color: t.surface3),
            const SizedBox(height: 14),
            Text(
              'Pencapaian per Tipe',
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
            ...focusRows
                .take(3)
                .toList()
                .asMap()
                .entries
                .map(
                  (entry) => _buildFocusProductItem(
                    row: entry.value,
                    index: entry.key + 1,
                  ),
                ),
          ],
          if (specialRows.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSpecialInsightCard(rows: specialRows),
          ],
        ],
      ),
    );
  }

  Widget _buildMingguanTab() {
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildNewTargetHero(
            label: 'TARGET MINGGUAN',
            target: weeklyTarget,
            actual: weeklyActual,
            percentage: weeklyPct,
            sisa: weeklySisa,
            accentColor: t.warning,
          ),
          const SizedBox(height: 16),
          _buildMingguanFocusContent(),
          const SizedBox(height: 16),
          _buildWeeklyHeroProgressContent(),
          const SizedBox(height: 16),
          _buildVastFinanceCard(),
          const SizedBox(height: 20),
          _buildMingguanAnalysisContent(),
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

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Pilih Minggu',
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                const Spacer(),
                Text(
                  selectedRangeLabel,
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w600,
                    color: t.textMuted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            _buildWeeklySelectorStrip(),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(12),
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
                    '$selectedElapsedDays/$selectedWorkingDays hari',
                    style: PromotorText.outfit(
                      size: 12,
                      weight: FontWeight.w700,
                      color: t.primaryAccent,
                    ),
                  ),
                ],
              ),
            ),
          ],
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

  Widget _buildMingguanFocusContent() {
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
    final weeklySpecialRows = selectedSnapshot?['special_rows'] is List
        ? _asMapList(selectedSnapshot?['special_rows'])
        : _weeklySpecialRows;

    return _buildNewFocusSection(
      focusTarget: roundedWeeklyFocusTarget,
      focusActual: weeklyFocusActual,
      focusPct: weeklyFocusPct,
      focusSisa: weeklyFocusSisa,
      specialRows: weeklySpecialRows,
    );
  }

  Widget _buildMingguanAnalysisContent() {
    if (_dailyTargetData == null) {
      return const SizedBox.shrink();
    }

    final selectedSnapshot = _selectedWeeklySnapshot();
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
    final fallbackWeekStart = _parseDate(_dailyTargetData?['active_week_start']);
    final fallbackWeekEnd = _parseDate(_dailyTargetData?['active_week_end']);
    final elapsedDays = selectedSnapshot != null
        ? _toNum(selectedSnapshot['elapsed_working_days']).toInt()
        : fallbackWeekStart == null || fallbackWeekEnd == null
        ? 0
        : _elapsedWorkingDays(fallbackWeekStart, fallbackWeekEnd, DateTime.now());
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
    final safeWeeklyGap = weeklyGap.clamp(0, double.infinity);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Analisa Mingguan',
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _buildNewStatChip('Avg/Hari', _formatCompactNumber(avgPerDay), t.info),
              const SizedBox(width: 8),
              _buildNewStatChip(
                'Proyeksi',
                _formatCompactNumber(projectedWeekly),
                projectedWeekly >= weeklyTargetAll ? t.success : t.warning,
              ),
              const SizedBox(width: 8),
              _buildNewStatChip(
                'Gap',
                _formatCompactNumber(safeWeeklyGap),
                t.primaryAccent,
              ),
            ],
          ),
        ],
      ),
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

  // ignore: unused_element
  Widget _buildWeeklySectionCard({
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
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
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w600,
                color: t.textMuted,
              ),
            ),
          ],
          const SizedBox(height: 14),
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
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        children: [
          _buildNewTargetHero(
            label: 'TARGET BULANAN',
            target: targetOmzet,
            actual: actualOmzet,
            percentage: achievement,
            sisa: sisaTarget,
          ),
          const SizedBox(height: 16),
          _buildBulananFocusContent(),
          const SizedBox(height: 16),
          _buildVastFinanceCard(),
          const SizedBox(height: 16),
          _buildBulananStatsContent(),
        ],
      ),
    );
  }

  Widget _buildBulananFocusContent() {
    final focusTarget = _toNum(_targetData?['target_fokus_total']);
    final focusActual = _toNum(_targetData?['actual_fokus_total']);
    final focusPct = _toNum(_targetData?['achievement_fokus_pct']).toDouble();
    final focusRemaining = _nonNegative(
      _roundUpUnitTarget(focusTarget) - focusActual.toInt(),
    );

    return _buildNewFocusSection(
      focusTarget: focusTarget,
      focusActual: focusActual,
      focusPct: focusPct,
      focusSisa: focusRemaining,
      specialRows: _monthlySpecialRows,
    );
  }

  Widget _buildBulananStatsContent() {
    final now = DateTime.now();
    final previousMonth = DateTime(now.year, now.month - 1, 1);
    final periodStart = _parseDate(_targetData?['start_date']);
    final periodEnd = _parseDate(_targetData?['end_date']);
    final actualOmzet = _toNum(_targetData?['actual_omzet']);
    final targetOmzet = _toNum(_targetData?['target_omzet']);
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
    final prevLabel = DateFormat(
      'MMM',
      'id_ID',
    ).format(previousMonth).toUpperCase();

    return Column(
      children: [
        // Hari Kerja + Target/Hari + VS bulan lalu
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            children: [
              _buildNewStatChip(
                'Hari Kerja',
                '$elapsedWorkingDays/$totalWorkingDays',
                t.textPrimary,
              ),
              const SizedBox(width: 8),
              _buildNewStatChip(
                'Need/Hari',
                _formatCompactNumber(targetPerRemainingDay),
                t.primaryAccent,
              ),
              const SizedBox(width: 8),
              _buildNewStatChip(
                'VS $prevLabel',
                '${isVsPositive ? '↑' : '↓'}${vsPrevPct.abs().toStringAsFixed(0)}%',
                isVsPositive ? t.success : t.danger,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Analisa bulanan
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Analisa Bulanan',
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  _buildNewStatChip(
                    'Avg/Hari',
                    _formatCompactNumber(avgPerWorkingDay),
                    t.info,
                  ),
                  const SizedBox(width: 8),
                  _buildNewStatChip(
                    'Proyeksi',
                    _formatCompactNumber(projectedMonth),
                    projectedMonth >= targetOmzet ? t.success : t.warning,
                  ),
                  const SizedBox(width: 8),
                  _buildNewStatChip(
                    'Sisa Hari',
                    '$remainingWorkingDays',
                    t.primaryAccentLight,
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ignore: unused_element
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

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeading(
            'Pencapaian Kemarin',
            icon: Icons.history_rounded,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCompareArea(
                name: 'All Type',
                value: _formatCompactNumber(allTypeActual),
                target: _formatRupiah(allTypeTarget),
                percentage: _calculatePercentage(allTypeActual, allTypeTarget),
                color: t.success,
                isCurrency: true,
              ),
              Container(width: 1, height: 60, color: t.surface3),
              _buildCompareArea(
                name: 'Fokus',
                value: focusActual.toInt().toString(),
                target: '${_formatUnitTarget(focusTarget)} unit',
                percentage: _calculatePercentage(focusActual, focusTarget),
                color: t.primaryAccent,
                isCurrency: false,
              ),
              Container(width: 1, height: 60, color: t.surface3),
              _buildCompareArea(
                name: 'VAST',
                value: vastActual.toInt().toString(),
                target: '${_formatUnitTarget(vastTarget)} unit',
                percentage: _calculatePercentage(vastActual, vastTarget),
                color: t.warning,
                isCurrency: false,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> get _activeVastData {
    switch (_selectedTab) {
      case 'mingguan':
        return Map<String, dynamic>.from(
          _vastWeeklyData ?? const <String, dynamic>{},
        );
      case 'bulanan':
        return Map<String, dynamic>.from(
          _vastMonthlyData ?? const <String, dynamic>{},
        );
      default:
        return Map<String, dynamic>.from(
          _vastDailyData ?? const <String, dynamic>{},
        );
    }
  }

  String get _vastTargetLabel {
    switch (_selectedTab) {
      case 'mingguan':
        return 'Target Mingguan';
      case 'bulanan':
        return 'Target Bulanan';
      default:
        return 'Target Harian';
    }
  }

  String get _vastPeriodNote {
    switch (_selectedTab) {
      case 'mingguan':
        final selectedSnapshot = _selectedWeeklySnapshot();
        final weekNumber = _toNum(
          selectedSnapshot?['week_number'] ??
              _dailyTargetData?['active_week_number'],
        ).toInt();
        return weekNumber > 0 ? 'minggu $weekNumber' : 'mingguan';
      case 'bulanan':
        return 'bulan ini';
      default:
        return 'hari ini';
    }
  }

  Widget _buildVastFinanceCard() {
    final vast = _activeVastData;
    final target = _toNum(vast['target']).toInt();
    final input = _toNum(vast['submissions']).toInt();
    final pending = _toNum(vast['pending']).toInt();
    final reject = _toNum(vast['reject']).toInt();
    final closing = _toNum(vast['acc']).toInt();
    final pct = target > 0
        ? ((input / target) * 100).clamp(0, 999).toDouble()
        : 0.0;

    return GestureDetector(
      onTap: () => context.pushNamed('promotor-vast'),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeading(
              'VAST Finance',
              icon: Icons.account_balance_wallet_rounded,
              trailing: Text(
                '${pct.toStringAsFixed(0)}%',
                style: PromotorText.display(size: 20, color: t.warning),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$_vastTargetLabel: ${target.toString()} input',
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$input input • $_vastPeriodNote',
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w600,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 6,
              decoration: BoxDecoration(
                color: t.surface3,
                borderRadius: BorderRadius.circular(100),
              ),
              child: FractionallySizedBox(
                widthFactor: (pct / 100).clamp(0, 1),
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: t.warning,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                _buildNewStatChip('Input', '$input', t.warning),
                const SizedBox(width: 8),
                _buildNewStatChip('Closing', '$closing', t.success),
                const SizedBox(width: 8),
                _buildNewStatChip('Pending', '$pending', t.primaryAccent),
                const SizedBox(width: 8),
                _buildNewStatChip('Reject', '$reject', t.danger),
              ],
            ),
          ],
        ),
      ),
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
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              name,
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w600,
                color: t.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: PromotorText.display(
                size: isCurrency ? 16 : 24,
                color: color,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              '${percentage.toStringAsFixed(0)}%',
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w700,
                color: percentage >= 100 ? t.success : t.textMuted,
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
        margin: const EdgeInsets.symmetric(horizontal: 20),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title row
            Row(
              children: [
                Expanded(
                  child: _buildSectionHeading(
                    'Aktivitas Hari Ini',
                    icon: Icons.checklist_rounded,
                    trailing: Text(
                      '$completedCount/$totalCount',
                      style: PromotorText.display(
                        size: 20,
                        color: t.primaryAccent,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Icon(
                  Icons.arrow_forward_ios,
                  color: t.textMutedStrong,
                  size: 14,
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Progress bar
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: t.surface3,
                borderRadius: BorderRadius.circular(100),
              ),
              child: FractionallySizedBox(
                widthFactor: progress.clamp(0, 1),
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: t.primaryAccent,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // Activity pills
            Wrap(
              spacing: 6,
              runSpacing: 6,
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
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '$index',
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              bundleName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$actualQty/$targetQty',
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${safePct.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w800,
                color: tone,
              ),
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
    final accent = t.primaryAccent;
    final border = t.primaryAccent.withValues(alpha: 0.14);
    final bg = t.textOnAccent;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: t.primaryAccentSoft,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.primaryAccentGlow),
                ),
                child: Text(
                  title,
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  progressText,
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              _buildFocusMetricPill('Target', targetValue, t.textPrimary),
              _buildFocusMetricPill('Terjual', actualValue, t.success),
              _buildFocusMetricPill('Sisa', remainingValue, t.warning),
            ],
          ),
          const SizedBox(height: 8),
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
    final specialBg = Color.lerp(t.warningSoft, t.surface1, 0.35)!;
    final specialBorder = Color.lerp(t.warning, t.primaryAccent, 0.18)!;
    final specialHeader = Color.lerp(t.warning, t.primaryAccent, 0.15)!;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: specialBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: specialBorder.withValues(alpha: 0.32)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: specialHeader),
              const SizedBox(width: 6),
              Text(
                title,
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w800,
                  color: specialHeader,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
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

  Widget _buildFocusMetricPill(String label, String value, Color valueColor) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 9,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w800,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusCard() {
    Map<String, dynamic>? selectedBonusData;
    String title;
    if (_selectedTab == 'harian') {
      title = 'Bonus Harian';
      selectedBonusData = _dailyBonusData;
    } else if (_selectedTab == 'mingguan') {
      title = 'Bonus Mingguan';
      final selectedSnapshot = _selectedWeeklySnapshot();
      selectedBonusData = selectedSnapshot?['bonus'] is Map
          ? Map<String, dynamic>.from(selectedSnapshot!['bonus'] as Map)
          : _weeklyBonusData;
    } else {
      title = 'Bonus Bulanan';
      selectedBonusData = _bonusSummary;
    }

    return _buildBonusSummaryCard(
      title: title,
      subtitle: '',
      data: selectedBonusData,
    );
  }

  Widget _buildBonusSummaryCard({
    required String title,
    required String subtitle,
    required Map<String, dynamic>? data,
  }) {
    final totalBonus = _toNum(data?['total_bonus'] ?? data?['bonus_total']);
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
                                      style: _sectionTitleStyle(
                                        color: t.textPrimary,
                                      ).copyWith(fontWeight: FontWeight.w800),
                                    ),
                                    if (subtitle.isNotEmpty)
                                      Text(
                                        subtitle,
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
                                  style: _sectionTitleStyle(
                                    color: t.textPrimary,
                                  ).copyWith(fontWeight: FontWeight.w800),
                                ),
                                if (subtitle.isNotEmpty)
                                  Text(
                                    subtitle,
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
                            child: _buildBonusMiniStat(
                              label: 'Target',
                              value: '${bonusPct.toStringAsFixed(0)}%',
                              hint: _formatCompactRupiah(personalTarget),
                              tone: statusColor,
                              background: t.textOnAccent,
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
                            child: _buildBonusMiniStat(
                              label: 'Target',
                              value: '${bonusPct.toStringAsFixed(0)}%',
                              hint: _formatCompactRupiah(personalTarget),
                              tone: statusColor,
                              background: t.textOnAccent,
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

  // ignore: unused_element
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

  // ignore: unused_element
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
