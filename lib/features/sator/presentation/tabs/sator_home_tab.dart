import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/features/notifications/presentation/widgets/app_notification_bell_button.dart';

import '../../../../core/router/app_route_names.dart';
import '../../../../core/utils/avatar_refresh_bus.dart';
import '../../../../core/utils/success_dialog.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../chat/repository/chat_repository.dart';
import '../../../../ui/components/field_segmented_control.dart';
import '../../../../ui/foundation/field_theme_extensions.dart';
import '../../../../ui/promotor/promotor.dart';

class SatorHomeTab extends StatefulWidget {
  final VoidCallback? onOpenLaporan;

  const SatorHomeTab({super.key, this.onOpenLaporan});

  @override
  State<SatorHomeTab> createState() => _SatorHomeTabState();
}

final Map<String, Map<String, dynamic>> _satorHomeProfileMemoryCache =
    <String, Map<String, dynamic>>{};

class _SatorHomeTabState extends State<SatorHomeTab> {
  FieldThemeTokens get t => context.fieldTokens;
  final SupabaseClient _supabase = Supabase.instance.client;
  final ChatRepository _chatRepository = ChatRepository();
  final NumberFormat _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  int _frameIndex = 0;
  int _homeSnapshotRequestId = 0;
  bool _headerIdentityReady = false;
  bool _headerAvatarReady = false;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _dailySummary;
  Map<String, dynamic>? _weeklySummary;
  Map<String, dynamic>? _monthlySummary;
  Map<String, dynamic>? _vastDaily;
  Map<String, dynamic>? _vastWeekly;
  Map<String, dynamic>? _vastMonthly;
  List<Map<String, dynamic>> _dailyPromotors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _weeklyPromotors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _monthlyPromotors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _weeklySnapshots = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _dailyFocusRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _dailySpecialRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _monthlyFocusRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _monthlySpecialRows = <Map<String, dynamic>>[];
  Map<String, List<Map<String, dynamic>>> _weeklyFocusRowsByKey =
      <String, List<Map<String, dynamic>>>{};
  Map<String, List<Map<String, dynamic>>> _weeklySpecialRowsByKey =
      <String, List<Map<String, dynamic>>>{};
  String? _selectedWeeklyKey;

  @override
  void initState() {
    super.initState();
    _profile = _initialProfileSeed();
    _headerIdentityReady = _hasResolvedIdentity(_profile ?? const {});
    _headerAvatarReady = !_headerIdentityReady || _profileAvatarUrl.isEmpty;
    unawaited(_restoreCachedProfile());
    unawaited(_restoreCachedHomeSummary());
    unawaited(_refreshHeaderVisualState());
    _refresh();
    avatarRefreshTick.addListener(_handleAvatarRefresh);
  }

  void _handleAvatarRefresh() {
    if (!mounted) return;
    _refresh();
  }

  @override
  void dispose() {
    avatarRefreshTick.removeListener(_handleAvatarRefresh);
    super.dispose();
  }

  Future<void> _loadWeeklySnapshots() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final weeklyRaw = await _supabase.rpc(
      'get_sator_home_weekly_snapshots',
      params: <String, dynamic>{
        'p_sator_id': userId,
        'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
      },
    );
    final weeklyPayload = weeklyRaw is Map
        ? Map<String, dynamic>.from(weeklyRaw)
        : <String, dynamic>{};
    final weeklySnapshots = _parseMapList(weeklyPayload['weekly_snapshots']);
    final resolvedSelectedWeeklyKey = _resolveInitialWeeklyKey(
      weeklySnapshots,
      preferredKey: _selectedWeeklyKey,
      activeWeekNumber: _toInt(weeklyPayload['active_week_number']),
    );
    final focusRowsByKey = <String, List<Map<String, dynamic>>>{};
    final specialRowsByKey = <String, List<Map<String, dynamic>>>{};
    await Future.wait(
      weeklySnapshots.map((snapshot) async {
        final startDate = _parseDate(snapshot['start_date']);
        final endDate = _parseDate(snapshot['end_date']);
        if (startDate == null || endDate == null) return;
        final key = _weeklySnapshotKey(snapshot);
        final results = await Future.wait([
          _fetchDashboardFocusRows(
            scopeRole: 'sator',
            userId: userId,
            startDate: startDate,
            endDate: endDate,
          ),
          _fetchDashboardSpecialRows(
            scopeRole: 'sator',
            userId: userId,
            startDate: startDate,
            endDate: endDate,
            rangeMode: 'weekly',
            weekPercentage: _toDouble(snapshot['percentage_of_total']),
          ),
        ]);
        focusRowsByKey[key] = results[0];
        specialRowsByKey[key] = results[1];
      }),
    );

    if (!mounted) return;
    setState(() {
      _weeklySnapshots = weeklySnapshots;
      _weeklyFocusRowsByKey = focusRowsByKey;
      _weeklySpecialRowsByKey = specialRowsByKey;
      _selectedWeeklyKey = resolvedSelectedWeeklyKey;
    });
  }

  FieldThemeTokens get _t => context.fieldTokens;
  Color get _bg => _t.background;
  Color get _s1 => _t.surface1;
  Color get _s2 => _t.surface2;
  Color get _s3 => _t.surface3;
  Color get _gold => _t.primaryAccent;
  Color get _goldSoft => _t.primaryAccentSoft;
  Color get _goldGlow => _t.primaryAccentGlow;
  Color get _goldLt => _t.primaryAccentLight;
  Color get _cream => _t.textPrimary;
  Color get _cream2 => _t.textSecondary;
  Color get _muted => _t.textMuted;
  Color get _green => _t.success;
  Color get _amber => _t.warning;
  Color get _red => _t.danger;
  Color get _redSoft => _t.dangerSoft;
  Color get _heroStart => _t.heroGradientStart;
  Color get _heroEnd => _t.heroGradientEnd;

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

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return 0;
    return int.tryParse(raw) ?? num.tryParse(raw)?.toInt() ?? 0;
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  String _formatRupiahInput(dynamic value) {
    final amount = value is num
        ? value.toInt()
        : int.tryParse('${value ?? ''}'.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    if (amount <= 0) return '';
    return _currency.format(amount);
  }

  int _parseCurrencyInput(String raw) {
    return int.tryParse(raw.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
  }

  void _applyRupiahFormat(TextEditingController controller) {
    final formatted = _formatRupiahInput(controller.text);
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _initialOf(dynamic value, {String fallback = 'P'}) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return fallback;
    return text.characters.first.toUpperCase();
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _fetchDashboardFocusRows({
    required String scopeRole,
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await _supabase.rpc(
      'get_dashboard_focus_product_rows',
      params: <String, dynamic>{
        'p_scope_role': scopeRole,
        'p_user_id': userId,
        'p_start_date': DateFormat('yyyy-MM-dd').format(startDate),
        'p_end_date': DateFormat('yyyy-MM-dd').format(endDate),
      },
    );
    return _parseMapList(response);
  }

  Future<List<Map<String, dynamic>>> _fetchDashboardSpecialRows({
    required String scopeRole,
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required String rangeMode,
    required num weekPercentage,
  }) async {
    final response = await _supabase.rpc(
      'get_dashboard_special_rows',
      params: <String, dynamic>{
        'p_scope_role': scopeRole,
        'p_user_id': userId,
        'p_start_date': DateFormat('yyyy-MM-dd').format(startDate),
        'p_end_date': DateFormat('yyyy-MM-dd').format(endDate),
        'p_range_mode': rangeMode,
        'p_week_percentage': weekPercentage,
      },
    );
    return _parseMapList(response);
  }

  Future<void> _refresh() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final requestId = ++_homeSnapshotRequestId;
    if (mounted) {
      setState(() {
        _headerIdentityReady = _hasResolvedIdentity(_profile ?? const {});
        _headerAvatarReady = !_headerIdentityReady || _profileAvatarUrl.isEmpty;
      });
    }
    unawaited(_refreshHeaderVisualState());

    try {
      final now = DateTime.now();
      final results = await Future.wait<dynamic>([
        _supabase.rpc(
          'get_sator_home_snapshot',
          params: <String, dynamic>{'p_sator_id': userId},
        ),
        _supabase.rpc('get_my_profile_snapshot'),
        _fetchDashboardFocusRows(
          scopeRole: 'sator',
          userId: userId,
          startDate: now,
          endDate: now,
        ),
        _fetchDashboardFocusRows(
          scopeRole: 'sator',
          userId: userId,
          startDate: DateTime(now.year, now.month, 1),
          endDate: now,
        ),
        _fetchDashboardSpecialRows(
          scopeRole: 'sator',
          userId: userId,
          startDate: now,
          endDate: now,
          rangeMode: 'daily',
          weekPercentage: 0,
        ),
        _fetchDashboardSpecialRows(
          scopeRole: 'sator',
          userId: userId,
          startDate: DateTime(now.year, now.month, 1),
          endDate: now,
          rangeMode: 'monthly',
          weekPercentage: 0,
        ),
      ]);
      final snapshotRaw = results[0];
      final liveProfileRaw = results[1];
      final dailyFocusRows = List<Map<String, dynamic>>.from(
        results[2] as List<Map<String, dynamic>>,
      );
      final monthlyFocusRows = List<Map<String, dynamic>>.from(
        results[3] as List<Map<String, dynamic>>,
      );
      final dailySpecialRows = List<Map<String, dynamic>>.from(
        results[4] as List<Map<String, dynamic>>,
      );
      final monthlySpecialRows = List<Map<String, dynamic>>.from(
        results[5] as List<Map<String, dynamic>>,
      );
      final snapshot = snapshotRaw is Map
          ? Map<String, dynamic>.from(snapshotRaw)
          : <String, dynamic>{};
      final liveProfile = liveProfileRaw is Map
          ? Map<String, dynamic>.from(liveProfileRaw)
          : <String, dynamic>{};
      final vastDaily = Map<String, dynamic>.from(
        snapshot['vast_daily'] as Map? ?? const <String, dynamic>{},
      );
      final vastWeekly = Map<String, dynamic>.from(
        snapshot['vast_weekly'] as Map? ?? const <String, dynamic>{},
      );
      final vastMonthly = Map<String, dynamic>.from(
        snapshot['vast_monthly'] as Map? ?? const <String, dynamic>{},
      );
      final profile = <String, dynamic>{
        ...?_profile,
        ...Map<String, dynamic>.from(
          snapshot['profile'] as Map? ?? const <String, dynamic>{},
        ),
        ...liveProfile,
      };
      final dailySummary = Map<String, dynamic>.from(
        snapshot['daily'] as Map? ?? const <String, dynamic>{},
      );
      final weeklySummary = Map<String, dynamic>.from(
        snapshot['weekly'] as Map? ?? const <String, dynamic>{},
      );
      final monthlySummary = Map<String, dynamic>.from(
        snapshot['monthly'] as Map? ?? const <String, dynamic>{},
      );
      final dailyPromotors = _parseMapList(snapshot['daily_promotors']);
      final weeklyPromotors = _parseMapList(snapshot['weekly_promotors']);
      final monthlyPromotors = _parseMapList(snapshot['monthly_promotors']);

      if (!mounted || requestId != _homeSnapshotRequestId) return;
      unawaited(_persistProfileCache(profile));
      unawaited(
        _persistHomeSummaryCache(
          dailySummary: dailySummary,
          weeklySummary: weeklySummary,
          monthlySummary: monthlySummary,
          vastDaily: vastDaily,
          vastWeekly: vastWeekly,
          vastMonthly: vastMonthly,
        ),
      );
      unawaited(_syncAuthMetadataFromProfile(profile));
      setState(() {
        _profile = profile;
        _dailySummary = dailySummary;
        _weeklySummary = weeklySummary;
        _monthlySummary = monthlySummary;
        _dailyPromotors = dailyPromotors;
        _weeklyPromotors = weeklyPromotors;
        _monthlyPromotors = monthlyPromotors;
        _dailyFocusRows = dailyFocusRows;
        _monthlyFocusRows = monthlyFocusRows;
        _dailySpecialRows = dailySpecialRows;
        _monthlySpecialRows = monthlySpecialRows;
        _vastDaily = vastDaily;
        _vastWeekly = vastWeekly;
        _vastMonthly = vastMonthly;
      });
      unawaited(_refreshHeaderVisualState());
    } catch (e) {
      debugPrint('SATOR home refresh failed: $e');
    }
  }

  Map<String, dynamic> get _summary {
    switch (_frameIndex) {
      case 1:
        final selectedSnapshot = _selectedWeeklySnapshot();
        if (selectedSnapshot != null) {
          return Map<String, dynamic>.from(
            selectedSnapshot['summary'] ?? const <String, dynamic>{},
          );
        }
        return Map<String, dynamic>.from(
          _weeklySummary ?? const <String, dynamic>{},
        );
      case 2:
        return Map<String, dynamic>.from(
          _monthlySummary ?? const <String, dynamic>{},
        );
      default:
        return Map<String, dynamic>.from(
          _dailySummary ?? const <String, dynamic>{},
        );
    }
  }

  List<Map<String, dynamic>> get _promotorRows {
    switch (_frameIndex) {
      case 1:
        final selectedSnapshot = _selectedWeeklySnapshot();
        if (selectedSnapshot != null) {
          return _parseMapList(selectedSnapshot['promotors']);
        }
        return _weeklyPromotors;
      case 2:
        return _monthlyPromotors;
      default:
        return _sortedDailyPromotors;
    }
  }

  List<Map<String, dynamic>> get _sortedDailyPromotors {
    final rows = _dailyPromotors
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    rows.sort((a, b) {
      final storeCompare = '${a['store_name'] ?? ''}'.toLowerCase().compareTo(
        '${b['store_name'] ?? ''}'.toLowerCase(),
      );
      if (storeCompare != 0) return storeCompare;
      return '${a['name'] ?? ''}'.toLowerCase().compareTo(
        '${b['name'] ?? ''}'.toLowerCase(),
      );
    });
    return rows;
  }

  String get _profileName {
    final fullName = '${_profile?['full_name'] ?? ''}'.trim();
    if (fullName.isNotEmpty) return fullName;
    final nickname = '${_profile?['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    return 'SATOR';
  }

  String get _profileArea => '${_profile?['area'] ?? '-'}';
  String get _profileRole => '${_profile?['role'] ?? 'SATOR'}';
  String get _profileAvatarUrl => '${_profile?['avatar_url'] ?? ''}'.trim();

  Map<String, dynamic> _sessionProfileSeed() {
    final user = _supabase.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final nickname = '${metadata['nickname'] ?? metadata['display_name'] ?? ''}'
        .trim();
    final fullName = '${metadata['full_name'] ?? metadata['name'] ?? 'SATOR'}'
        .trim();
    return <String, dynamic>{
      'nickname': nickname,
      'full_name': fullName.isEmpty ? 'SATOR' : fullName,
      'area': '${metadata['area'] ?? ''}'.trim(),
      'role': '${metadata['role'] ?? 'sator'}'.trim(),
      'avatar_url': '${metadata['avatar_url'] ?? ''}'.trim(),
    };
  }

  Map<String, dynamic> _initialProfileSeed() {
    final userId = _supabase.auth.currentUser?.id;
    final sessionSeed = _sessionProfileSeed();
    if (userId == null) return sessionSeed;
    final cached = _satorHomeProfileMemoryCache[userId];
    if (cached == null) return sessionSeed;
    return <String, dynamic>{...sessionSeed, ...cached};
  }

  String _profileCacheKey(String userId) => 'sator_home.profile.$userId';

  bool _hasResolvedIdentity(Map<String, dynamic> profile) {
    final fullName = '${profile['full_name'] ?? ''}'.trim();
    final nickname = '${profile['nickname'] ?? ''}'.trim();
    final area = '${profile['area'] ?? ''}'.trim();
    final avatarUrl = '${profile['avatar_url'] ?? ''}'.trim();
    return fullName.isNotEmpty ||
        nickname.isNotEmpty ||
        area.isNotEmpty ||
        avatarUrl.isNotEmpty ||
        profile.isNotEmpty;
  }

  Future<void> _restoreCachedProfile() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profileCacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final cached = Map<String, dynamic>.from(decoded);
      _satorHomeProfileMemoryCache[userId] = cached;
      if (!mounted) return;
      setState(() {
        _profile = <String, dynamic>{...?_profile, ...cached};
        _headerIdentityReady = _hasResolvedIdentity(_profile ?? const {});
      });
      unawaited(_refreshHeaderVisualState());
    } catch (e) {
      debugPrint('SATOR restore cached profile failed: $e');
    }
  }

  Future<void> _persistProfileCache(Map<String, dynamic> profile) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final normalized = Map<String, dynamic>.from(profile);
      _satorHomeProfileMemoryCache[userId] = normalized;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileCacheKey(userId), jsonEncode(normalized));
    } catch (e) {
      debugPrint('SATOR persist profile cache failed: $e');
    }
  }

  Future<void> _syncAuthMetadataFromProfile(
    Map<String, dynamic> profile,
  ) async {
    try {
      final currentUser = _supabase.auth.currentUser;
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

      await _supabase.auth.updateUser(UserAttributes(data: nextMetadata));
    } catch (e) {
      debugPrint('SATOR sync auth metadata failed: $e');
    }
  }

  Future<void> _refreshHeaderVisualState() async {
    final avatarUrl = _profileAvatarUrl;
    final identityReady = _hasResolvedIdentity(_profile ?? const {});
    if (!mounted) return;
    setState(() {
      _headerIdentityReady = identityReady;
      _headerAvatarReady = !identityReady || avatarUrl.isEmpty;
    });
    if (!identityReady || avatarUrl.isEmpty || !mounted) return;
    try {
      await precacheImage(CachedNetworkImageProvider(avatarUrl), context);
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _headerAvatarReady = true;
    });
  }

  String _homeSummaryCacheKey(String userId) => 'sator_home.summary.$userId';

  Future<void> _restoreCachedHomeSummary() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_homeSummaryCacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final payload = Map<String, dynamic>.from(decoded);
      if (!mounted) return;
      setState(() {
        _dailySummary ??= _mapFromValue(payload['daily_summary']);
        _weeklySummary ??= _mapFromValue(payload['weekly_summary']);
        _monthlySummary ??= _mapFromValue(payload['monthly_summary']);
        _vastDaily ??= _mapFromValue(payload['vast_daily']);
        _vastWeekly ??= _mapFromValue(payload['vast_weekly']);
        _vastMonthly ??= _mapFromValue(payload['vast_monthly']);
      });
    } catch (e) {
      debugPrint('SATOR restore home summary cache failed: $e');
    }
  }

  Future<void> _persistHomeSummaryCache({
    required Map<String, dynamic> dailySummary,
    required Map<String, dynamic> weeklySummary,
    required Map<String, dynamic> monthlySummary,
    required Map<String, dynamic> vastDaily,
    required Map<String, dynamic> vastWeekly,
    required Map<String, dynamic> vastMonthly,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'daily_summary': dailySummary,
        'weekly_summary': weeklySummary,
        'monthly_summary': monthlySummary,
        'vast_daily': vastDaily,
        'vast_weekly': vastWeekly,
        'vast_monthly': vastMonthly,
      };
      await prefs.setString(_homeSummaryCacheKey(userId), jsonEncode(payload));
    } catch (e) {
      debugPrint('SATOR persist home summary cache failed: $e');
    }
  }

  Map<String, dynamic> _mapFromValue(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

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

  List<Map<String, dynamic>> get _activeFocusRows {
    switch (_frameIndex) {
      case 1:
        final selectedSnapshot = _selectedWeeklySnapshot();
        if (selectedSnapshot == null) return const <Map<String, dynamic>>[];
        return (_weeklyFocusRowsByKey[_weeklySnapshotKey(selectedSnapshot)] ??
                const <Map<String, dynamic>>[])
            .where((row) => row['is_special'] != true)
            .toList();
      case 2:
        return _monthlyFocusRows
            .where((row) => row['is_special'] != true)
            .toList();
      default:
        return _dailyFocusRows
            .where((row) => row['is_special'] != true)
            .toList();
    }
  }

  List<Map<String, dynamic>> get _activeSpecialRows {
    switch (_frameIndex) {
      case 1:
        final selectedSnapshot = _selectedWeeklySnapshot();
        if (selectedSnapshot == null) return const <Map<String, dynamic>>[];
        return _weeklySpecialRowsByKey[_weeklySnapshotKey(selectedSnapshot)] ??
            const <Map<String, dynamic>>[];
      case 2:
        return _monthlySpecialRows;
      default:
        return _dailySpecialRows;
    }
  }

  num _sumPromotorField(List<Map<String, dynamic>> rows, String key) {
    num total = 0;
    for (final row in rows) {
      total += _toNum(row[key]);
    }
    return total;
  }

  String _formatCompactCurrency(num value) {
    return _currency.format(value).replaceAll(',00', '');
  }

  EdgeInsets get _sectionCardMargin => const EdgeInsets.fromLTRB(16, 0, 16, 14);
  bool get _isLightMode => Theme.of(context).brightness == Brightness.light;

  BoxDecoration _surfaceCardDecoration({Color? accent}) {
    final tone = accent ?? _gold;
    if (_isLightMode) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _s1,
            Color.lerp(_s1, tone, 0.055) ?? _s1,
            Color.lerp(_bg, tone, 0.025) ?? _bg,
          ],
          stops: const [0, 0.6, 1],
        ),
        borderRadius: BorderRadius.circular(_t.radiusMd),
        border: Border.all(color: Color.lerp(_s3, tone, 0.16) ?? _s3),
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
      color: _s1,
      borderRadius: BorderRadius.circular(_t.radiusMd),
      border: Border.all(color: _s3),
    );
  }

  BoxDecoration _innerCardDecoration({Color? accent}) {
    final tone = accent ?? _gold;
    if (_isLightMode) {
      return BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(_s2, Colors.white, 0.35) ?? _s2,
            Color.lerp(_s1, tone, 0.03) ?? _s1,
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Color.lerp(_s3, tone, 0.12) ?? _s3),
      );
    }

    return BoxDecoration(
      color: _s2,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: _s3),
    );
  }

  Widget _buildHeroAmount(num value, {double size = 22}) {
    final formatted = _formatCompactCurrency(value);
    final raw = formatted.replaceFirst('Rp ', '').trim();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'Rp ',
              style: _outfit(
                size: size * 0.52,
                weight: FontWeight.w800,
                color: _cream2,
              ),
            ),
            TextSpan(
              text: raw,
              style: _display(size: size, weight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusTitleBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _goldSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _goldGlow),
      ),
      child: Text(
        label,
        style: _outfit(size: 11, weight: FontWeight.w800, color: _gold),
      ),
    );
  }

  Widget _buildFocusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: _s2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _s3),
      ),
      child: Text(
        label,
        style: _outfit(size: 7, weight: FontWeight.w700, color: _cream2),
      ),
    );
  }

  Widget _buildFocusSummaryMetric(
    String label,
    String value,
    Color? valueColor,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: _innerCardDecoration(accent: valueColor ?? _gold),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 7, color: _muted)),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _outfit(
              size: 10,
              weight: FontWeight.w800,
              color: valueColor ?? _cream,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroMetaCard({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: _innerCardDecoration(accent: valueColor ?? _gold),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 8, color: _muted)),
          const SizedBox(height: 3),
          SizedBox(
            height: 18,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: _display(
                  size: 12,
                  weight: FontWeight.w800,
                  color: valueColor ?? _cream,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFocusProductRow(Map<String, dynamic> product) {
    final tags = <Widget>[
      if (product['is_detail_target'] == true) _buildFocusChip('Detail'),
      if (product['is_special'] == true) _buildFocusChip('Khusus'),
    ];
    final actualUnits = _toInt(product['actual_units']);

    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _goldSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.flag_rounded, size: 12, color: _gold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${product['model_name'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _outfit(size: 11, weight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${product['series'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _outfit(size: 8, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
            decoration: BoxDecoration(
              color: _goldSoft,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: _goldGlow),
            ),
            child: Text(
              '${actualUnits}u',
              style: _outfit(size: 8, weight: FontWeight.w800, color: _gold),
            ),
          ),
          if (tags.isNotEmpty) const SizedBox(width: 8),
          if (tags.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: tags
                  .map(
                    (tag) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: tag,
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildFocusInsightBlock({
    required String title,
    required num target,
    required num actual,
    required String progressNote,
    bool embedded = false,
  }) {
    final targetUnits = target.ceil();
    final actualUnits = actual.toInt();
    final remaining = math.max(0, targetUnits - actualUnits);
    final progress = target > 0 ? (actual * 100 / target) : 0.0;

    return Container(
      margin: embedded ? EdgeInsets.zero : _sectionCardMargin,
      decoration: embedded ? null : _surfaceCardDecoration(accent: _gold),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final metricWidth = math.max(
            0.0,
            math.min(88.0, (constraints.maxWidth - 48) / 3),
          );
          return Padding(
            padding: embedded
                ? const EdgeInsets.fromLTRB(0, 12, 0, 0)
                : const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: _buildFocusTitleBadge(title)),
                    const SizedBox(width: 10),
                    Text(
                      '${progress.toStringAsFixed(0)}%',
                      style: _display(
                        size: embedded ? 15 : 16,
                        weight: FontWeight.w800,
                        color: _gold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Center(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      SizedBox(
                        width: metricWidth,
                        child: _buildFocusSummaryMetric(
                          'Target',
                          '$targetUnits',
                          null,
                        ),
                      ),
                      SizedBox(
                        width: metricWidth,
                        child: _buildFocusSummaryMetric(
                          'Terjual',
                          '$actualUnits',
                          _green,
                        ),
                      ),
                      SizedBox(
                        width: metricWidth,
                        child: _buildFocusSummaryMetric(
                          'Sisa',
                          '$remaining',
                          _amber,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!embedded) ...[
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: (progress / 100).clamp(0, 1),
                      minHeight: 4,
                      backgroundColor: _s3,
                      valueColor: AlwaysStoppedAnimation<Color>(_gold),
                    ),
                  ),
                ],
                if (_activeFocusRows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ..._activeFocusRows.take(3).map(_buildFocusProductRow),
                ],
                if (_activeSpecialRows.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildSpecialInsightCard(rows: _activeSpecialRows),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSpecialInsightCard({
    required List<Map<String, dynamic>> rows,
    String title = 'Tipe Khusus',
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: _goldSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _goldGlow.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 14, color: _gold),
              const SizedBox(width: 6),
              Text(
                title,
                style: _outfit(size: 11, weight: FontWeight.w800, color: _gold),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...rows.asMap().entries.map(
            (entry) => _buildSpecialBundleRow(
              detail: entry.value,
              index: entry.key + 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialBundleRow({
    required Map<String, dynamic> detail,
    required int index,
  }) {
    final bundleName = '${detail['bundle_name'] ?? 'Tipe Khusus'}';
    final targetQty = _toDouble(detail['target_qty']);
    final actualQty = _toDouble(detail['actual_qty']);
    final pct = _toDouble(detail['pct']);
    final tone = pct >= 100 ? _green : (pct >= 70 ? _gold : _red);

    String fmt(double value) => value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
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
              style: _outfit(size: 10, weight: FontWeight.w800, color: tone),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              bundleName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: _outfit(size: 12, weight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${fmt(actualQty)}/${fmt(targetQty)}',
            style: _outfit(size: 11, weight: FontWeight.w700, color: _cream2),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 36,
            child: Text(
              '${pct.toStringAsFixed(0)}%',
              textAlign: TextAlign.right,
              style: _outfit(size: 11, weight: FontWeight.w800, color: tone),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    final summary = _summary;
    final selectedWeeklySnapshot = _selectedWeeklySnapshot();
    final target = switch (_frameIndex) {
      1 => _toInt(summary['target_omzet']),
      2 => _toInt(summary['target_omzet']),
      _ => _toInt(summary['target_sellout']),
    };
    final actual = switch (_frameIndex) {
      1 => _toInt(summary['actual_omzet']),
      2 => _toInt(summary['actual_omzet']),
      _ => _toInt(summary['actual_sellout']),
    };
    final pct = target > 0 ? actual / target : 0.0;
    final title = switch (_frameIndex) {
      1 => 'Target Mingguan',
      2 => 'Target Bulanan',
      _ => 'Target Harian',
    };
    final progressLabel = switch (_frameIndex) {
      1 =>
        selectedWeeklySnapshot != null
            ? 'Minggu ke-${_toInt(selectedWeeklySnapshot['week_number'])} • ${selectedWeeklySnapshot['status_label'] ?? 'Minggu aktif'}'
            : 'Minggu aktif',
      2 => 'Progress bulan ini',
      _ => 'Progress hari ini',
    };

    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 360;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [_heroStart, _heroEnd],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(_t.radiusLg),
            border: Border.all(color: _goldGlow),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _bg.withValues(alpha: 0),
                      _gold.withValues(alpha: 0.65),
                      _bg.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
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
                              _buildFocusTitleBadge(title),
                              const SizedBox(height: 10),
                              _buildHeroAmount(target, size: narrow ? 18 : 19),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: narrow ? 52 : 54,
                          height: narrow ? 52 : 54,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: narrow ? 52 : 54,
                                height: narrow ? 52 : 54,
                                child: CircularProgressIndicator(
                                  value: pct.clamp(0, 1),
                                  strokeWidth: 4.5,
                                  backgroundColor: _s3,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    pct < 0.6
                                        ? _red
                                        : (pct < 0.85 ? _amber : _gold),
                                  ),
                                ),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${(pct * 100).toStringAsFixed(0)}%',
                                    style: _display(
                                      size: 11,
                                      weight: FontWeight.w800,
                                    ),
                                  ),
                                  Text(
                                    _frameIndex == 1 ? 'mingguan' : 'bulanan',
                                    style: _outfit(size: 8, color: _cream2),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _buildHeroMetaCard(
                            label: 'Pencapaian',
                            value: _formatCompactCurrency(actual),
                            valueColor: _green,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildHeroMetaCard(
                            label: progressLabel,
                            value:
                                'Sisa ${_formatCompactCurrency(math.max(0, target - actual))}',
                            valueColor: _goldLt,
                          ),
                        ),
                      ],
                    ),
                    if (_frameIndex == 1) ...[
                      _buildFocusInsightBlock(
                        title: 'Produk Fokus',
                        target: _toNum(summary['target_fokus']),
                        actual: _toNum(summary['actual_fokus']),
                        progressNote:
                            'Progress produk fokus ${_weeklySectionNote(lowercase: true)}',
                        embedded: true,
                      ),
                    ] else if (_frameIndex == 2) ...[
                      _buildFocusInsightBlock(
                        title: 'Produk Fokus',
                        target: _toNum(summary['target_fokus']),
                        actual: _toNum(summary['actual_fokus']),
                        progressNote: 'Progress produk fokus bulan ini',
                        embedded: true,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDailyHeroCard() {
    final target = _toNum(_dailySummary?['target_sellout']);
    final actual = _toNum(_dailySummary?['actual_sellout']);
    final pct = target > 0 ? ((actual / target) * 100).clamp(0, 100) : 0.0;
    final remaining = math.max(0, target - actual);

    return GestureDetector(
      onTap: () => context.pushNamed(AppRouteNames.targetDetail),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 360;
          return Container(
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_heroStart, _heroEnd],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(_t.radiusLg),
              border: Border.all(color: _goldGlow),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        _bg.withValues(alpha: 0),
                        _gold.withValues(alpha: 0.65),
                        _bg.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildFocusTitleBadge('Target Harian Tim'),
                            const SizedBox(height: 10),
                            _buildHeroAmount(target, size: narrow ? 18 : 19),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: narrow ? 52 : 54,
                        height: narrow ? 52 : 54,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            SizedBox(
                              width: narrow ? 52 : 54,
                              height: narrow ? 52 : 54,
                              child: CircularProgressIndicator(
                                value: (pct / 100).clamp(0, 1),
                                strokeWidth: 4.5,
                                backgroundColor: _s3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _gold,
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${pct.toStringAsFixed(0)}%',
                                  style: _display(
                                    size: 11,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                Text(
                                  'hari ini',
                                  style: _outfit(size: 8, color: _cream2),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _buildHeroMetaCard(
                              label: 'Pencapaian',
                              value: _formatCompactCurrency(actual),
                              valueColor: _green,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildHeroMetaCard(
                              label: 'Progress',
                              value:
                                  'Sisa ${_formatCompactCurrency(remaining)}',
                              valueColor: _goldLt,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildDailyFocusContent(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionHead(String title, String note) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 10),
      child: Row(
        children: [
          // Accent dot + garis
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
          Expanded(
            child: Text(
              title,
              style: _outfit(size: 13, weight: FontWeight.w700, color: _cream2),
            ),
          ),
          Text(note, style: _outfit(size: 11, color: _muted)),
        ],
      ),
    );
  }

  String _weeklySectionNote({bool lowercase = false}) {
    final selectedSnapshot = _selectedWeeklySnapshot();
    final weekNumber = _toInt(selectedSnapshot?['week_number']);
    final label = weekNumber > 0 ? 'Minggu $weekNumber' : 'Mingguan';
    return lowercase ? label.toLowerCase() : label;
  }

  Widget _buildWeeklySelectorCard() {
    if (_weeklySnapshots.isEmpty) return const SizedBox(height: 8);
    final selectedSnapshot = _selectedWeeklySnapshot();
    final rangeLabel = _formatWeekRange(
      _parseDate(selectedSnapshot?['start_date']),
      _parseDate(selectedSnapshot?['end_date']),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isLightMode ? Color.lerp(_s1, _gold, 0.03) : _s1,
        borderRadius: BorderRadius.circular(_t.radiusMd),
        border: Border.all(
          color: _isLightMode ? Color.lerp(_s3, _gold, 0.12) ?? _s3 : _s3,
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = math.max(0.0, (constraints.maxWidth - 24) / 4);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    'Pilih Minggu',
                    style: _outfit(size: 11, weight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(rangeLabel, style: _outfit(size: 8, color: _muted)),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List<Widget>.generate(_weeklySnapshots.length, (
                  index,
                ) {
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

                  return SizedBox(
                    width: itemWidth,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () => setState(() => _selectedWeeklyKey = weekKey),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: isSelected
                                ? [
                                    _goldSoft,
                                    _isLightMode
                                        ? Color.lerp(
                                                _goldSoft,
                                                Colors.white,
                                                0.22,
                                              ) ??
                                              _goldSoft
                                        : _goldSoft,
                                  ]
                                : [
                                    _isLightMode
                                        ? Color.lerp(_s2, Colors.white, 0.24) ??
                                              _s2
                                        : _s2,
                                    _s2,
                                  ],
                          ),
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
                                    'Minggu $weekNumber',
                                    style: _outfit(
                                      size: 8,
                                      weight: FontWeight.w800,
                                      color: chipTone,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: chipTone,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _formatWeekRange(
                                _parseDate(snapshot['start_date']),
                                _parseDate(snapshot['end_date']),
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _outfit(size: 7, color: _muted),
                            ),
                            if (isFuture) ...[
                              const SizedBox(height: 3),
                              Text(
                                'Belum berjalan',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _outfit(
                                  size: 7,
                                  weight: FontWeight.w700,
                                  color: _cream2,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPromotorCard(Map<String, dynamic> row) {
    final targetNominal = _toNum(row['target_nominal']);
    final actualNominal = _toNum(row['actual_nominal']);
    final targetFocus = _toNum(row['target_focus_units']);
    final actualFocus = _toNum(row['actual_focus_units']);
    final pct = _toDouble(row['achievement_pct']) / 100;
    final tone = row['underperform'] == true
        ? _red
        : (pct < 0.6 ? _red : (pct < 0.85 ? _amber : _gold));

    return Container(
      margin: _sectionCardMargin,
      decoration: _surfaceCardDecoration(accent: tone),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: _s2,
                    shape: BoxShape.circle,
                    border: Border.all(color: _s3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initialOf(row['name']),
                    style: _display(
                      size: 8,
                      weight: FontWeight.w800,
                      color: _cream2,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _outfit(size: 10, weight: FontWeight.w700),
                      ),
                      Text(
                        '${row['store_name']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _outfit(size: 6, color: _muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  _frameIndex == 2
                      ? '${_toDouble(row['achievement_pct']).toStringAsFixed(0)}%'
                      : _formatCompactCurrency(actualNominal),
                  style: _outfit(size: 9, weight: FontWeight.w800, color: tone),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0, 1),
                      minHeight: 2,
                      backgroundColor: _s3,
                      valueColor: AlwaysStoppedAnimation<Color>(tone),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                SizedBox(
                  width: 40,
                  child: Text(
                    '${_toDouble(row['achievement_pct']).toStringAsFixed(0)}%',
                    style: _outfit(
                      size: 8,
                      weight: FontWeight.w700,
                      color: tone,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Target ${_formatCompactCurrency(targetNominal)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: _outfit(size: 6, color: _muted),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${actualFocus.toInt()}/${targetFocus.ceil()} unit',
                  style: _outfit(size: 6, color: _muted),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyPromotorDetailCard(Map<String, dynamic> row) {
    final targetNominal = _toNum(row['target_nominal']);
    final actualNominal = _toNum(row['actual_nominal']);
    final targetFocus = _toNum(row['target_focus_units']);
    final actualFocus = _toNum(row['actual_focus_units']);
    final achievementPct = _toDouble(row['achievement_pct']);
    final progress = (achievementPct / 100).clamp(0, 1).toDouble();
    final tone = achievementPct >= 100
        ? _green
        : (achievementPct > 0 ? _amber : _red);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: _surfaceCardDecoration(accent: tone),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${row['name']} • ${row['store_name'] ?? '-'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _outfit(size: 9, weight: FontWeight.w900),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: _innerCardDecoration(accent: tone),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Target', style: _outfit(size: 6, color: _muted)),
                      const SizedBox(height: 1),
                      Text(
                        _formatCompactCurrency(targetNominal),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _outfit(
                          size: 8,
                          weight: FontWeight.w900,
                          color: tone,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  decoration: _innerCardDecoration(accent: _amber),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Fokus', style: _outfit(size: 6, color: _muted)),
                      const SizedBox(height: 1),
                      Text(
                        '${targetFocus.ceil()}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _outfit(size: 7, weight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 6,
                  ),
                  decoration: _innerCardDecoration(accent: _green),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Real', style: _outfit(size: 6, color: _muted)),
                      const SizedBox(height: 1),
                      Text(
                        _formatCompactCurrency(actualNominal),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _outfit(size: 7, weight: FontWeight.w900),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 2,
                    backgroundColor: _s3,
                    valueColor: AlwaysStoppedAnimation<Color>(tone),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 38,
                child: Text(
                  '${achievementPct.toStringAsFixed(0)}%',
                  style: _outfit(size: 8, weight: FontWeight.w700, color: tone),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            'Fokus terjual ${actualFocus.toInt()} unit',
            style: _outfit(size: 6, color: _muted),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyPromotorPreviewCard() {
    final totalTarget = _sumPromotorField(_dailyPromotors, 'target_nominal');
    final totalActual = _sumPromotorField(_dailyPromotors, 'actual_nominal');
    final previewRows = _sortedDailyPromotors.take(2).toList();

    return GestureDetector(
      onTap: _dailyPromotorRowsAvailable ? _openDailyPromotorDetail : null,
      child: Container(
        margin: _sectionCardMargin,
        decoration: _surfaceCardDecoration(accent: _gold),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target Harian Promotor',
                          style: _outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: _cream2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_dailyPromotors.length} promotor',
                          style: _outfit(size: 9, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  if (_dailyPromotors.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(999),
                        child: InkWell(
                          onTap: _sendDailyTargetsToTeamGroup,
                          borderRadius: BorderRadius.circular(999),
                          splashColor: _gold.withValues(alpha: 0.14),
                          highlightColor: _gold.withValues(alpha: 0.08),
                          child: Ink(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _goldSoft,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: _gold.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Text(
                              'Kirim ke Grup',
                              style: _outfit(
                                size: 9,
                                weight: FontWeight.w800,
                                color: _gold,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  Icon(Icons.chevron_right_rounded, color: _gold, size: 18),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _buildPreviewMetric(
                      'Target',
                      _formatCompactCurrency(totalTarget),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildPreviewMetric(
                      'Realisasi',
                      _formatCompactCurrency(totalActual),
                    ),
                  ),
                ],
              ),
              if (previewRows.isNotEmpty) ...[
                const SizedBox(height: 14),
                ...previewRows.map((row) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _outfit(
                                  size: 10,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${row['store_name'] ?? '-'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _outfit(size: 7, color: _muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatCompactCurrency(_toNum(row['target_nominal'])),
                          style: _outfit(
                            size: 9,
                            weight: FontWeight.w700,
                            color: _gold,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSellInAchievementCard() {
    final monthly = _monthlySummary ?? const <String, dynamic>{};
    final target = _toNum(monthly['target_sellin']);
    final actual = _toNum(monthly['actual_sellin']);
    final pct = target > 0 ? ((actual / target) * 100).clamp(0, 100) : 0.0;
    final remaining = math.max(0, target - actual);

    return GestureDetector(
      onTap: () => context.push('/sator/sell-in'),
      child: Container(
        margin: _sectionCardMargin,
        padding: const EdgeInsets.all(16),
        decoration: _surfaceCardDecoration(accent: _amber),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _goldSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _goldGlow),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.inventory_2_rounded,
                    size: 12,
                    color: _gold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Sell In',
                    style: _outfit(size: 12, weight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: _outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: pct >= 100 ? _green : _amber,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_formatCompactCurrency(actual)} / ${_formatCompactCurrency(target)}',
                    style: _outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: _cream2,
                    ),
                  ),
                ),
                Text('bulan ini', style: _outfit(size: 8, color: _muted)),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: target > 0 ? (actual / target).clamp(0, 1) : 0,
                minHeight: 4,
                backgroundColor: _s3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  pct >= 100 ? _green : _gold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildPreviewMetric(
                    'Target',
                    _formatCompactCurrency(target),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildPreviewMetric(
                    'Sisa',
                    _formatCompactCurrency(remaining),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: _innerCardDecoration(accent: _gold),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 8, color: _muted)),
          const SizedBox(height: 3),
          Text(
            value,
            style: _outfit(size: 11, weight: FontWeight.w800, color: _cream),
          ),
        ],
      ),
    );
  }

  void _openDailyPromotorDetail() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg.withValues(alpha: 0),
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.88,
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _s3),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: _s3,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatCompactCurrency(
                              _sumPromotorField(
                                _sortedDailyPromotors,
                                'target_nominal',
                              ),
                            ),
                            style: _display(
                              size: 24,
                              weight: FontWeight.w800,
                              color: _cream,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Semua Target Harian Promotor',
                            style: _outfit(
                              size: 14,
                              weight: FontWeight.w700,
                              color: _cream,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_dailyPromotors.length} promotor',
                            style: _outfit(size: 10, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: Icon(Icons.close, color: _cream2, size: 18),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: _dailyPromotors.length,
                  itemBuilder: (context, index) {
                    return _buildDailyPromotorDetailCard(
                      _sortedDailyPromotors[index],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendDailyTargetsToTeamGroup() async {
    if (_dailyPromotors.isEmpty) return;
    final satorId = _supabase.auth.currentUser?.id;
    if (satorId == null) return;

    try {
      final room = await _chatRepository.getTeamChatRoom(satorId: satorId);
      if (room == null) {
        throw Exception('Grup utama tim belum tersedia');
      }

      final vastSnapshot = await _supabase.rpc(
        'get_sator_vast_page_snapshot',
        params: <String, dynamic>{
          'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        },
      );
      final vastMap = <String, Map<String, dynamic>>{};
      final vastRows = _parseMapList(
        (vastSnapshot is Map)
            ? Map<String, dynamic>.from(vastSnapshot)['rows_daily']
            : null,
      );
      for (final row in vastRows) {
        final id = '${row['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        vastMap[id] = row;
      }

      final draftRows =
          _dailyPromotors.map((row) {
            final id = '${row['id'] ?? ''}'.trim();
            final vastRow = vastMap[id] ?? const <String, dynamic>{};
            final displayName = '${row['nickname'] ?? ''}'.trim().isNotEmpty
                ? '${row['nickname']}'
                : '${row['name'] ?? 'Promotor'}';
            return <String, dynamic>{
              'id': id,
              'name': displayName,
              'store_name': '${row['store_name'] ?? '-'}',
              'target_nominal': _toNum(row['target_nominal']).toInt(),
              'target_vast': _toNum(vastRow['target_vast']).toInt(),
              'target_focus_units': _toNum(row['target_focus_units']).ceil(),
            };
          }).toList()..sort((a, b) {
            final storeCompare = '${a['store_name'] ?? ''}'
                .toLowerCase()
                .compareTo('${b['store_name'] ?? ''}'.toLowerCase());
            if (storeCompare != 0) return storeCompare;
            return '${a['name'] ?? ''}'.toLowerCase().compareTo(
              '${b['name'] ?? ''}'.toLowerCase(),
            );
          });

      final editedRows = await _showDailyTargetPreviewDialog(draftRows);
      if (editedRows == null || editedRows.isEmpty) return;

      final payload = <String, dynamic>{
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'sator_name': _profileName,
        'rows': editedRows,
      };

      await _chatRepository.sendTextMessage(
        roomId: room.id,
        content: 'target_card::${jsonEncode(payload)}',
      );

      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: 'Target harian berhasil dikirim ke grup tim.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal kirim target harian: $e')));
    }
  }

  Future<List<Map<String, dynamic>>?> _showDailyTargetPreviewDialog(
    List<Map<String, dynamic>> draftRows,
  ) async {
    return showDialog<List<Map<String, dynamic>>>(
      context: context,
      builder: (dialogContext) {
        final nominalControllers = <String, TextEditingController>{};
        final vastControllers = <String, TextEditingController>{};
        final focusControllers = <String, TextEditingController>{};

        for (final row in draftRows) {
          final id = '${row['id'] ?? ''}'.trim();
          nominalControllers[id] = TextEditingController(
            text: _formatRupiahInput(row['target_nominal']),
          );
          vastControllers[id] = TextEditingController(
            text: _toNum(row['target_vast']).toInt().toString(),
          );
          focusControllers[id] = TextEditingController(
            text: _toNum(row['target_focus_units']).ceil().toString(),
          );
        }

        return StatefulBuilder(
          builder: (context, setInnerState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 24,
              ),
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: 520,
                  maxHeight: MediaQuery.of(context).size.height * 0.84,
                ),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: _s3),
                ),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Preview Target Harian',
                                  style: _outfit(
                                    size: 15,
                                    weight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Review dan edit sebelum kirim ke grup tim.',
                                  style: _outfit(size: 11, color: _muted),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            icon: Icon(Icons.close, color: _cream2),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                        itemCount: draftRows.length,
                        itemBuilder: (context, index) {
                          final row = draftRows[index];
                          final id = '${row['id'] ?? ''}'.trim();
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: _s1,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: _s3),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${row['name'] ?? 'Promotor'} • ${row['store_name'] ?? '-'}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _outfit(
                                    size: 10,
                                    weight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Row(
                                  children: [
                                    Expanded(
                                      flex: 3,
                                      child: TextField(
                                        controller: nominalControllers[id],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        onChanged: (_) => setInnerState(
                                          () => _applyRupiahFormat(
                                            nominalControllers[id]!,
                                          ),
                                        ),
                                        style: _outfit(
                                          size: 9,
                                          weight: FontWeight.w800,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'Target',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      flex: 1,
                                      child: TextField(
                                        controller: vastControllers[id],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        style: _outfit(
                                          size: 8,
                                          weight: FontWeight.w800,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'Vast',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      flex: 1,
                                      child: TextField(
                                        controller: focusControllers[id],
                                        keyboardType: TextInputType.number,
                                        inputFormatters: [
                                          FilteringTextInputFormatter
                                              .digitsOnly,
                                        ],
                                        style: _outfit(
                                          size: 8,
                                          weight: FontWeight.w800,
                                        ),
                                        decoration: const InputDecoration(
                                          labelText: 'Fokus',
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () =>
                                  Navigator.of(dialogContext).pop(),
                              child: const Text('Batal'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () {
                                final rows = draftRows.map((row) {
                                  final id = '${row['id'] ?? ''}'.trim();
                                  return <String, dynamic>{
                                    ...row,
                                    'target_nominal': _parseCurrencyInput(
                                      nominalControllers[id]!.text.trim(),
                                    ),
                                    'target_vast':
                                        int.tryParse(
                                          vastControllers[id]!.text.trim(),
                                        ) ??
                                        0,
                                    'target_focus_units':
                                        int.tryParse(
                                          focusControllers[id]!.text.trim(),
                                        ) ??
                                        0,
                                  };
                                }).toList();
                                Navigator.of(dialogContext).pop(rows);
                              },
                              child: const Text('Ya, Kirim'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildMonthlyKpiCard(Map<String, dynamic> monthly, double monthlyPct) {
    Widget metric(String label, String value, Color color) {
      return SizedBox(
        height: 64,
        width: double.infinity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          decoration: _innerCardDecoration(accent: color),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: _outfit(size: 8, color: _muted)),
              const SizedBox(height: 4),
              Text(
                value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: _outfit(size: 10, weight: FontWeight.w800, color: color),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => context.pushNamed('sator-kpi-bonus'),
      child: Container(
        margin: _sectionCardMargin,
        padding: const EdgeInsets.all(16),
        decoration: _surfaceCardDecoration(accent: _gold),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'KPI Bulanan',
                    style: _outfit(size: 12, weight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${monthlyPct.toStringAsFixed(1)}%',
                  style: _outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: _gold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                metric(
                  'Sell Out',
                  '${_formatCompactCurrency(_toNum(monthly['actual_omzet']))} / ${_formatCompactCurrency(_toNum(monthly['target_omzet']))}',
                  _gold,
                ),
                const SizedBox(height: 8),
                metric(
                  'Produk Fokus',
                  '${_toInt(monthly['actual_fokus'])}/${_toInt(monthly['target_fokus'])} unit',
                  _amber,
                ),
                const SizedBox(height: 8),
                metric(
                  'Sell In',
                  '${_formatCompactCurrency(_toNum(monthly['actual_sellin']))} / ${_formatCompactCurrency(_toNum(monthly['target_sellin']))}',
                  _green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> get _vastSnapshot {
    switch (_frameIndex) {
      case 1:
        return Map<String, dynamic>.from(
          _vastWeekly ?? const <String, dynamic>{},
        );
      case 2:
        return Map<String, dynamic>.from(
          _vastMonthly ?? const <String, dynamic>{},
        );
      default:
        return Map<String, dynamic>.from(
          _vastDaily ?? const <String, dynamic>{},
        );
    }
  }

  String get _vastPeriodLabel {
    switch (_frameIndex) {
      case 1:
        return _weeklySectionNote(lowercase: true);
      case 2:
        return 'bulan ini';
      default:
        return 'hari ini';
    }
  }

  Widget _buildVastCompactCard() {
    final vast = _vastSnapshot;
    final target = _toInt(vast['target_submissions']);
    final input = _toInt(vast['total_submissions']);
    final reject = _toInt(vast['total_reject']);
    final pending = _toInt(vast['total_active_pending']);
    final closing =
        _toInt(vast['total_closed_direct']) +
        _toInt(vast['total_closed_follow_up']);
    final duplicateAlerts = _toInt(vast['total_duplicate_alerts']);
    final pct = target > 0
        ? ((input * 100) / target)
        : _toDouble(vast['achievement_pct']);
    final tone = pct >= 100 ? _green : (pct > 0 ? _amber : _muted);
    final targetLabel = _frameIndex == 1
        ? 'Target Mingguan'
        : _frameIndex == 2
        ? 'Target Bulanan'
        : 'Target Harian';

    Widget metric(String label, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
          decoration: _innerCardDecoration(
            accent: color,
          ).copyWith(borderRadius: BorderRadius.circular(10)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: _outfit(size: 8, color: _muted)),
              const SizedBox(height: 2),
              Text(
                value,
                style: _outfit(size: 11, weight: FontWeight.w800, color: color),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => context.pushNamed('sator-vast'),
      child: Container(
        margin: _sectionCardMargin,
        padding: const EdgeInsets.all(16),
        decoration: _surfaceCardDecoration(accent: _amber),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _goldSoft,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _goldGlow),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 12,
                    color: _gold,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'VAST Finance',
                    style: _outfit(size: 12, weight: FontWeight.w800),
                  ),
                ),
                Text(
                  '${pct.toStringAsFixed(0)}%',
                  style: _outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$targetLabel: $target input',
                    style: _outfit(size: 9, color: _cream2),
                  ),
                ),
                if (duplicateAlerts > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _redSoft,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$duplicateAlerts alert',
                      style: _outfit(
                        size: 8,
                        weight: FontWeight.w700,
                        color: _red,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '$input input • $_vastPeriodLabel',
              style: _outfit(size: 9, color: _muted),
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: target > 0 ? (input / target).clamp(0, 1) : 0,
                minHeight: 4,
                backgroundColor: _s3,
                valueColor: AlwaysStoppedAnimation<Color>(tone),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                metric('Input', '$input', _gold),
                const SizedBox(width: 8),
                metric('Reject', '$reject', _red),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                metric('Pending', '$pending', _amber),
                const SizedBox(width: 8),
                metric('Closing', '$closing', _green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankingState() {
    if (_monthlyPromotors.isEmpty) {
      return Container(
        margin: _sectionCardMargin,
        padding: const EdgeInsets.all(16),
        decoration: _surfaceCardDecoration(accent: _gold),
        child: Text(
          'Belum ada data ranking',
          style: _outfit(size: 11, color: _muted),
        ),
      );
    }

    return Column(
      children: _monthlyPromotors.take(3).map((row) {
        final index = _monthlyPromotors.indexOf(row) + 1;
        return Container(
          margin: _sectionCardMargin,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: _surfaceCardDecoration(
            accent: index == 1 ? _gold : _amber,
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _goldSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: _outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: _gold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${row['name']}',
                  style: _outfit(size: 12, weight: FontWeight.w700),
                ),
              ),
              Text(
                _formatCompactCurrency(_toNum(row['actual_nominal'])),
                style: _outfit(size: 10, color: _cream2),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBody() {
    final note = DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now());
    if (_frameIndex == 1) {
      return Column(
        children: [
          _buildHeroCard(),
          _buildWeeklySelectorCard(),
          const SizedBox(height: 4),
          _buildSectionHead('VAST Finance', _weeklySectionNote()),
          _buildVastCompactCard(),
          const SizedBox(height: 2),
          _buildSectionHead('Performa Promotor', _weeklySectionNote()),
          ..._promotorRows.take(5).map(_buildPromotorCard),
          const SizedBox(height: 20),
        ],
      );
    }

    if (_frameIndex == 2) {
      final monthly = _monthlySummary ?? <String, dynamic>{};
      final monthlyPct = _toNum(monthly['target_omzet']) > 0
          ? (_toNum(monthly['actual_omzet']) *
                100 /
                _toNum(monthly['target_omzet']))
          : 0.0;
      return Column(
        children: [
          _buildHeroCard(),
          const SizedBox(height: 4),
          _buildMonthlyKpiCard(monthly, monthlyPct),
          const SizedBox(height: 2),
          _buildSectionHead('VAST Finance', note),
          _buildVastCompactCard(),
          const SizedBox(height: 2),
          _buildSectionHead('Ranking Promotor', note),
          _buildRankingState(),
          const SizedBox(height: 24),
        ],
      );
    }

    return Column(
      children: [
        _buildDailyHeroCard(),
        const SizedBox(height: 2),
        _buildSectionHead('VAST Finance', 'hari ini'),
        _buildVastCompactCard(),
        const SizedBox(height: 2),
        _buildSectionHead('Sell In', 'bulan ini'),
        _buildSellInAchievementCard(),
        const SizedBox(height: 18),
        _buildDailyPromotorPreviewCard(),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildDailyFocusContent() {
    final focusTarget = _toNum(_dailySummary?['target_fokus']);
    final focusActual = _toNum(
      _dailySummary?['actual_fokus'] ??
          _dailySummary?['actual_focus'] ??
          _dailySummary?['actual_daily_focus'],
    );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _s3)),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: _buildFocusInsightBlock(
          title: 'Produk Fokus',
          target: focusTarget,
          actual: focusActual,
          progressNote: 'Progress produk fokus hari ini',
        ),
      ),
    );
  }

  String _formatWeekRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '-';
    final formatter = DateFormat('d MMM', 'id_ID');
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  Widget _buildDateBadge(String label, {double fontSize = 11}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.calendar_today_rounded, size: 11, color: _gold),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.fade,
              style: _outfit(size: fontSize, color: _muted),
            ),
          ),
        ],
      ),
    );
  }

  bool get _dailyPromotorRowsAvailable => _dailyPromotors.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final compact = width < 390;
        final veryCompact = width < 360;
        final headerHorizontal = veryCompact ? 10.0 : 12.0;
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
        final areaSize = veryCompact ? 10.0 : 11.0;
        final contentGap = veryCompact ? 8.0 : 10.0;
        final nameGap = veryCompact ? 3.0 : 5.0;
        final dateSectionBottom = veryCompact ? 4.0 : 6.0;

        Widget buildMetaChip({
          required String label,
          required Color color,
          required IconData icon,
        }) {
          final tint = color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.10,
          );
          final border = color.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.28
                : 0.18,
          );
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
                    style: _outfit(
                      size: areaSize,
                      weight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: _refresh,
          color: _gold,
          backgroundColor: _s1,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Container(
                margin: EdgeInsets.fromLTRB(
                  headerHorizontal,
                  6,
                  headerHorizontal,
                  4,
                ),
                padding: headerPadding,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: Theme.of(context).brightness == Brightness.dark
                        ? [_s1, _s2]
                        : [_s1, _bg],
                  ),
                  borderRadius: BorderRadius.circular(veryCompact ? 16 : 20),
                  border: Border.all(color: _s3),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? _bg.withValues(alpha: 0.16)
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
                            style: _display(
                              size: compact ? 18 : 20,
                              color: _cream,
                            ),
                          ),
                        ),
                        AppNotificationBellButton(
                          backgroundColor: _s1,
                          borderColor: _s3,
                          iconColor: _muted,
                          badgeColor: _red,
                          badgeTextColor: _bg,
                          routePath: '/sator/notifications',
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => context.push('/sator/home-search'),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: _s1,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: _s3),
                            ),
                            child: Icon(
                              Icons.search_rounded,
                              color: _muted,
                              size: 16,
                            ),
                          ),
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
                            border: Border.all(color: _goldGlow),
                          ),
                          child: _headerAvatarReady
                              ? UserAvatar(
                                  key: ValueKey(_profileAvatarUrl),
                                  avatarUrl: _profileAvatarUrl.isEmpty
                                      ? null
                                      : _profileAvatarUrl,
                                  fullName: _profileName,
                                  radius: avatarRadius,
                                  showBorder: false,
                                )
                              : Container(
                                  width: avatarRadius * 2,
                                  height: avatarRadius * 2,
                                  decoration: BoxDecoration(
                                    color: _s2,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                        ),
                        SizedBox(width: contentGap),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (_headerIdentityReady) ...[
                                Text(
                                  _profileName,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: _display(
                                    size: compact ? titleSize - 1 : titleSize,
                                    weight: FontWeight.w800,
                                  ),
                                ),
                                SizedBox(height: nameGap),
                                Wrap(
                                  spacing: 6,
                                  runSpacing: 3,
                                  children: [
                                    buildMetaChip(
                                      label:
                                          _profileArea.isNotEmpty &&
                                              _profileArea != '-'
                                          ? _profileArea
                                          : 'Area: -',
                                      color: _gold,
                                      icon: Icons.place_rounded,
                                    ),
                                    buildMetaChip(
                                      label: _profileRole.toUpperCase(),
                                      color: _cream2,
                                      icon: Icons.badge_rounded,
                                    ),
                                  ],
                                ),
                              ] else ...[
                                Container(
                                  height: compact ? 18 : 20,
                                  width: veryCompact ? 132 : 168,
                                  decoration: BoxDecoration(
                                    color: _s2,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                                SizedBox(height: nameGap),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: [
                                    Container(
                                      height: compact ? 10 : 11,
                                      width: 76,
                                      decoration: BoxDecoration(
                                        color: _s2,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      height: compact ? 10 : 11,
                                      width: 84,
                                      decoration: BoxDecoration(
                                        color: _s2,
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  headerHorizontal,
                  0,
                  headerHorizontal,
                  dateSectionBottom,
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final dateLabel = DateFormat(
                      constraints.maxWidth < 360
                          ? 'd MMM yyyy'
                          : constraints.maxWidth < 430
                          ? 'EEE, d MMM'
                          : 'EEEE, d MMM yyyy',
                      'id_ID',
                    ).format(DateTime.now());
                    final segmented = ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth < 360 ? 184 : 212,
                      ),
                      child: FieldSegmentedControl(
                        labels: const ['Harian', 'Mingguan', 'Bulanan'],
                        selectedIndex: _frameIndex,
                        onSelected: (index) async {
                          setState(() => _frameIndex = index);
                          if (index == 1 && _weeklySnapshots.isEmpty) {
                            try {
                              await _loadWeeklySnapshots();
                            } catch (e) {
                              debugPrint('SATOR weekly snapshots failed: $e');
                            }
                          }
                        },
                      ),
                    );

                    final dateBadge = Align(
                      alignment: Alignment.centerLeft,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: _buildDateBadge(
                          dateLabel,
                          fontSize: constraints.maxWidth < 360 ? 8.5 : 9.5,
                        ),
                      ),
                    );

                    if (constraints.maxWidth < 350) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          dateBadge,
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: segmented,
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: dateBadge),
                        const SizedBox(width: 8),
                        segmented,
                      ],
                    );
                  },
                ),
              ),
              _buildBody(),
            ],
          ),
        );
      },
    );
  }
}
