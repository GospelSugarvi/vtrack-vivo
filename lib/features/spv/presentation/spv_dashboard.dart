import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/router/app_route_names.dart';
import '../../../core/utils/avatar_refresh_bus.dart';
import '../../../core/utils/chat_nav_badge_counter.dart';
import '../../../core/utils/chat_unread_refresh_bus.dart';
import '../../../core/utils/test_account_switcher.dart';
import '../../../core/widgets/user_avatar.dart';
import '../../../ui/components/app_dashboard_shell.dart';
import '../../../ui/components/field_segmented_control.dart';
import '../../../ui/foundation/field_theme_extensions.dart';
import '../../../ui/promotor/promotor.dart';
import '../../chat/presentation/pages/chat_list_page.dart';
import '../../notifications/presentation/widgets/app_notification_bell_button.dart';
import 'pages/spv_leaderboard_page.dart';
import 'pages/spv_profile_page.dart';

part 'widgets/spv_dashboard_data_part.dart';
part 'widgets/spv_dashboard_layout_part.dart';
part 'widgets/spv_dashboard_components_part.dart';

class SpvDashboard extends StatefulWidget {
  const SpvDashboard({super.key});

  @override
  State<SpvDashboard> createState() => _SpvDashboardState();
}

final Map<String, Map<String, dynamic>> _spvHomeProfileMemoryCache =
    <String, Map<String, dynamic>>{};

class _SpvDashboardState extends State<SpvDashboard> {
  FieldThemeTokens get t => context.fieldTokens;
  int _currentIndex = 0;
  int _homeFrameIndex = 0;
  int _unreadCount = 0;
  final Set<int> _loadedTabSlots = <int>{0};

  bool _headerIdentityReady = false;
  String _spvName = 'SPV';
  String _spvArea = '-';
  String _spvAvatarUrl = '';
  bool _headerAvatarReady = false;

  Map<String, dynamic>? _teamTargetData;
  Map<String, dynamic>? _scheduleSummary;
  Map<String, dynamic>? _spvKpiSummary;
  Map<String, dynamic>? _vastDaily;
  Map<String, dynamic>? _vastWeekly;
  Map<String, dynamic>? _vastMonthly;
  List<Map<String, dynamic>> _satorTargetBreakdown = [];
  List<Map<String, dynamic>> _dailyFocusRows = [];
  List<Map<String, dynamic>> _monthlyFocusRows = [];
  List<Map<String, dynamic>> _dailySpecialRows = [];
  List<Map<String, dynamic>> _monthlySpecialRows = [];
  Map<String, List<Map<String, dynamic>>> _weeklyFocusRowsByKey = {};
  Map<String, List<Map<String, dynamic>>> _weeklySpecialRowsByKey = {};
  List<Map<String, dynamic>> _weeklySnapshots = [];
  String? _selectedWeeklyKey;
  bool _homeSnapshotReady = false;
  bool _weeklySnapshotReady = false;

  int _todayOmzet = 0;
  int _weekOmzet = 0;
  int _monthOmzet = 0;
  int _weekFocusUnits = 0;
  int _permissionPendingCount = 0;

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
  Color get _red => _t.danger;
  Color get _amber => _t.warning;
  Color get _shellBg => _t.shellBackground;
  Color get _heroStart => _t.heroGradientStart;
  Color get _heroEnd => _t.heroGradientEnd;
  Color get _bottomBarBg => _t.bottomBarBackground;

  @override
  void initState() {
    super.initState();
    final seed = _initialProfileSeed();
    _applyHeaderProfile(seed);
    _headerIdentityReady = _hasResolvedHeaderIdentity(seed);
    _headerAvatarReady = !_headerIdentityReady || _spvAvatarUrl.isEmpty;
    unawaited(_restoreCachedProfile());
    unawaited(_refreshHeaderVisualState());
    _refreshAll();
    avatarRefreshTick.addListener(_handleAvatarRefresh);
    chatUnreadRefreshTick.addListener(_handleUnreadRefresh);
    unawaited(_loadUnreadCount());
  }

  void _handleAvatarRefresh() {
    if (!mounted) return;
    _loadHeaderProfile();
    _loadHomeSnapshot();
  }

  void _handleUnreadRefresh() {
    if (!mounted) return;
    unawaited(_loadUnreadCount());
  }

  void _updateState(VoidCallback fn) {
    setState(fn);
  }

  @override
  void dispose() {
    avatarRefreshTick.removeListener(_handleAvatarRefresh);
    chatUnreadRefreshTick.removeListener(_handleUnreadRefresh);
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final total = await loadChatNavBadgeCount(Supabase.instance.client);
      if (!mounted) return;
      _updateState(() => _unreadCount = total);
    } catch (e) {
      debugPrint('SPV unread count failed: $e');
    }
  }

  Map<String, dynamic> _sessionProfileSeed() {
    final user = Supabase.instance.client.auth.currentUser;
    final metadata = user?.userMetadata ?? const <String, dynamic>{};
    final fullName = '${metadata['full_name'] ?? metadata['name'] ?? 'SPV'}'
        .trim();
    return <String, dynamic>{
      'full_name': fullName.isEmpty ? 'SPV' : fullName,
      'area': '${metadata['area'] ?? ''}'.trim(),
      'role': '${metadata['role'] ?? 'spv'}'.trim(),
      'avatar_url': '${metadata['avatar_url'] ?? ''}'.trim(),
    };
  }

  Map<String, dynamic> _initialProfileSeed() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    final sessionSeed = _sessionProfileSeed();
    if (userId == null) return sessionSeed;
    final cached = _spvHomeProfileMemoryCache[userId];
    if (cached == null) return sessionSeed;
    return <String, dynamic>{...sessionSeed, ...cached};
  }

  String _profileCacheKey(String userId) => 'spv_home.profile.$userId';

  void _applyHeaderProfile(Map<String, dynamic> profile) {
    _spvName = '${profile['full_name'] ?? 'SPV'}'.trim().isEmpty
        ? 'SPV'
        : '${profile['full_name'] ?? 'SPV'}'.trim();
    _spvArea = '${profile['area'] ?? '-'}'.trim().isEmpty
        ? '-'
        : '${profile['area'] ?? '-'}'.trim();
    _spvAvatarUrl = '${profile['avatar_url'] ?? ''}'.trim();
  }

  bool _hasResolvedHeaderIdentity(Map<String, dynamic> profile) {
    final fullName = '${profile['full_name'] ?? ''}'.trim();
    final area = '${profile['area'] ?? ''}'.trim();
    final avatarUrl = '${profile['avatar_url'] ?? ''}'.trim();
    return (fullName.isNotEmpty && fullName.toLowerCase() != 'spv') ||
        area.isNotEmpty ||
        avatarUrl.isNotEmpty ||
        profile.isNotEmpty;
  }

  Map<String, dynamic> _currentHeaderProfile() => <String, dynamic>{
    'full_name': _spvName,
    'area': _spvArea,
    'role': _spvRole.toLowerCase(),
    'avatar_url': _spvAvatarUrl,
  };

  String _homeSnapshotCacheKey(String userId) => 'spv_home.snapshot.$userId';

  Future<void> _restoreCachedProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_profileCacheKey(userId));
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final cached = Map<String, dynamic>.from(decoded);
      _spvHomeProfileMemoryCache[userId] = cached;
      if (!mounted) return;
      _updateState(() {
        _applyHeaderProfile(cached);
        _headerIdentityReady = _hasResolvedHeaderIdentity(cached);
      });
      unawaited(_refreshHeaderVisualState());
    } catch (e) {
      debugPrint('SPV restore cached profile failed: $e');
    }
  }

  Future<void> _persistProfileCache(Map<String, dynamic> profile) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final normalized = Map<String, dynamic>.from(profile);
      _spvHomeProfileMemoryCache[userId] = normalized;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_profileCacheKey(userId), jsonEncode(normalized));
    } catch (e) {
      debugPrint('SPV persist profile cache failed: $e');
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
        'avatar_url': '${profile['avatar_url'] ?? ''}'.trim(),
        'area': '${profile['area'] ?? ''}'.trim(),
        'role': '${profile['role'] ?? ''}'.trim(),
      };

      bool changed(String key) =>
          '${currentMetadata[key] ?? ''}'.trim() !=
          '${nextMetadata[key] ?? ''}'.trim();

      if (!(changed('full_name') ||
          changed('avatar_url') ||
          changed('area') ||
          changed('role'))) {
        return;
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(data: nextMetadata),
      );
    } catch (e) {
      debugPrint('SPV sync auth metadata failed: $e');
    }
  }

  Future<void> _refreshHeaderVisualState() async {
    final avatarUrl = _spvAvatarUrl;
    final identityReady = _hasResolvedHeaderIdentity(_currentHeaderProfile());
    if (!mounted) return;
    _updateState(() {
      _headerIdentityReady = identityReady;
      _headerAvatarReady = !identityReady || avatarUrl.isEmpty;
    });
    if (!identityReady || avatarUrl.isEmpty || !mounted) return;
    try {
      await precacheImage(CachedNetworkImageProvider(avatarUrl), context);
    } catch (_) {}
    if (!mounted) return;
    _updateState(() {
      _headerAvatarReady = true;
    });
  }

  Map<String, dynamic> _mapFromValue(dynamic value) {
    if (value is Map<String, dynamic>) return Map<String, dynamic>.from(value);
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    final visibleIndex = _currentIndex <= 1 ? 0 : _currentIndex - 1;
    final body = Padding(
      padding: const EdgeInsets.only(bottom: 92),
      child: IndexedStack(
        index: visibleIndex.clamp(0, 3),
        children: [
          _buildDashboardBody(),
          _loadedTabSlots.contains(1)
              ? const SpvLeaderboardPage()
              : const SizedBox.shrink(),
          _loadedTabSlots.contains(2)
              ? const ChatListPage()
              : const SizedBox.shrink(),
          _loadedTabSlots.contains(3)
              ? const SpvProfilePage()
              : const SizedBox.shrink(),
        ],
      ),
    );

    return Scaffold(
      backgroundColor: _shellBg,
      body: Stack(
        children: [
          Positioned.fill(child: body),
          if (kDebugMode) const TestAccountSwitcherFab(),
          Positioned(bottom: 0, left: 0, right: 0, child: _buildBottomNav()),
        ],
      ),
    );
  }
}

String get _spvRole => 'SPV';
