part of '../spv_dashboard.dart';

extension _SpvDashboardDataPart on _SpvDashboardState {
  Future<void> _refreshAll() async {
    if (!mounted) return;
    _updateState(() {
      _headerIdentityReady = _hasResolvedHeaderIdentity(
        _currentHeaderProfile(),
      );
      _headerAvatarReady = !_headerIdentityReady || _spvAvatarUrl.isEmpty;
    });
    await _restoreCachedHomeSnapshot();
    unawaited(_refreshHeaderVisualState());
    await _loadHeaderProfile();
    await Future.wait([
      _loadHomeSnapshot(),
      _loadSpvKpiSummary(),
      _loadWeeklySnapshots(),
    ]);
    if (mounted) _updateState(() {});
  }

  Future<void> _loadHeaderProfile() async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_my_profile_snapshot',
      );
      if (!mounted || response == null) return;
      final profile = <String, dynamic>{
        ..._currentHeaderProfile(),
        ...Map<String, dynamic>.from(response as Map),
      };
      unawaited(_persistProfileCache(profile));
      unawaited(_syncAuthMetadataFromProfile(profile));
      _updateState(() {
        _applyHeaderProfile(profile);
      });
      unawaited(_refreshHeaderVisualState());
    } catch (_) {}
  }

  Future<void> _loadPermissionPendingCount() async {
    try {
      final response = await Supabase.instance.client.rpc(
        'get_spv_permission_pending_count',
      );
      final payload = Map<String, dynamic>.from(
        (response as Map?) ?? const <String, dynamic>{},
      );
      _permissionPendingCount = _toInt(payload['pending_count']);
    } catch (_) {
      _permissionPendingCount = 0;
    }
  }

  Future<void> _loadHomeSnapshot() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final now = DateTime.now();
      final results = await Future.wait<dynamic>([
        Supabase.instance.client.rpc(
          'get_spv_home_snapshot',
          params: <String, dynamic>{
            'p_spv_id': userId,
            'p_date': DateFormat('yyyy-MM-dd').format(now),
          },
        ),
        _fetchDashboardFocusRows(
          scopeRole: 'spv',
          userId: userId,
          startDate: now,
          endDate: now,
        ),
        _fetchDashboardSpecialRows(
          scopeRole: 'spv',
          userId: userId,
          startDate: now,
          endDate: now,
          rangeMode: 'daily',
          weekPercentage: 0,
        ),
        _fetchDashboardFocusRows(
          scopeRole: 'spv',
          userId: userId,
          startDate: DateTime(now.year, now.month, 1),
          endDate: now,
        ),
        _fetchDashboardSpecialRows(
          scopeRole: 'spv',
          userId: userId,
          startDate: DateTime(now.year, now.month, 1),
          endDate: now,
          rangeMode: 'monthly',
          weekPercentage: 0,
        ),
      ]);
      final response = results[0];
      if (!mounted || response == null) return;

      final snapshot = Map<String, dynamic>.from(response as Map);
      final profile = Map<String, dynamic>.from(
        snapshot['profile'] ?? const <String, dynamic>{},
      );
      final mergedProfile = <String, dynamic>{
        ..._currentHeaderProfile(),
        ...profile,
      };
      final teamTargetData = Map<String, dynamic>.from(
        snapshot['team_target_data'] ?? const <String, dynamic>{},
      );
      final metrics = Map<String, dynamic>.from(
        snapshot['metrics'] ?? const <String, dynamic>{},
      );
      final scheduleSummary = Map<String, dynamic>.from(
        snapshot['schedule_summary'] ?? const <String, dynamic>{},
      );
      final vastDaily = Map<String, dynamic>.from(
        snapshot['vast_daily'] ?? const <String, dynamic>{},
      );
      final vastWeekly = Map<String, dynamic>.from(
        snapshot['vast_weekly'] ?? const <String, dynamic>{},
      );
      final vastMonthly = Map<String, dynamic>.from(
        snapshot['vast_monthly'] ?? const <String, dynamic>{},
      );
      final satorCards = List<Map<String, dynamic>>.from(
        (snapshot['sator_cards'] as List? ?? const <Map<String, dynamic>>[])
            .map((item) => Map<String, dynamic>.from(item as Map)),
      );
      final dailyFocusRows = List<Map<String, dynamic>>.from(
        results[1] as List<Map<String, dynamic>>,
      );
      final dailySpecialRows = List<Map<String, dynamic>>.from(
        results[2] as List<Map<String, dynamic>>,
      );
      final monthlyFocusRows = List<Map<String, dynamic>>.from(
        results[3] as List<Map<String, dynamic>>,
      );
      final monthlySpecialRows = List<Map<String, dynamic>>.from(
        results[4] as List<Map<String, dynamic>>,
      );
      unawaited(
        _persistHomeSnapshotCache(
          profile: mergedProfile,
          teamTargetData: teamTargetData,
          scheduleSummary: scheduleSummary,
          vastDaily: vastDaily,
          vastWeekly: vastWeekly,
          vastMonthly: vastMonthly,
          satorTargetBreakdown: satorCards,
          todayOmzet: _toInt(metrics['today_omzet']),
          weekOmzet: _toInt(metrics['week_omzet']),
          monthOmzet: _toInt(metrics['month_omzet']),
          weekFocusUnits: _toInt(metrics['week_focus_units']),
        ),
      );
      unawaited(_persistProfileCache(mergedProfile));
      unawaited(_syncAuthMetadataFromProfile(mergedProfile));

      _updateState(() {
        _applyHeaderProfile(mergedProfile);
        _teamTargetData = teamTargetData;
        _scheduleSummary = scheduleSummary;
        _vastDaily = vastDaily;
        _vastWeekly = vastWeekly;
        _vastMonthly = vastMonthly;
        _satorTargetBreakdown = satorCards;
        _dailyFocusRows = dailyFocusRows;
        _monthlyFocusRows = monthlyFocusRows;
        _dailySpecialRows = dailySpecialRows;
        _monthlySpecialRows = monthlySpecialRows;
        _todayOmzet = _toInt(metrics['today_omzet']);
        _weekOmzet = _toInt(metrics['week_omzet']);
        _monthOmzet = _toInt(metrics['month_omzet']);
        _weekFocusUnits = _toInt(metrics['week_focus_units']);
        _homeSnapshotReady = true;
      });
      unawaited(_refreshHeaderVisualState());
    } catch (_) {
      if (mounted) {
        _updateState(() {
          _homeSnapshotReady = true;
        });
      }
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
      final profile = _mapFromValue(payload['profile']);
      if (!mounted) return;
      _updateState(() {
        if (profile.isNotEmpty) {
          _applyHeaderProfile(profile);
          _headerIdentityReady = _hasResolvedHeaderIdentity(profile);
        }
        _teamTargetData ??= _mapFromValue(payload['team_target_data']);
        _scheduleSummary ??= _mapFromValue(payload['schedule_summary']);
        _vastDaily ??= _mapFromValue(payload['vast_daily']);
        _vastWeekly ??= _mapFromValue(payload['vast_weekly']);
        _vastMonthly ??= _mapFromValue(payload['vast_monthly']);
        final cachedRows = payload['sator_target_breakdown'];
        if (_satorTargetBreakdown.isEmpty && cachedRows is List) {
          _satorTargetBreakdown = cachedRows
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
        _todayOmzet = _todayOmzet == 0
            ? _toInt(payload['today_omzet'])
            : _todayOmzet;
        _weekOmzet = _weekOmzet == 0
            ? _toInt(payload['week_omzet'])
            : _weekOmzet;
        _monthOmzet = _monthOmzet == 0
            ? _toInt(payload['month_omzet'])
            : _monthOmzet;
        _weekFocusUnits = _weekFocusUnits == 0
            ? _toInt(payload['week_focus_units'])
            : _weekFocusUnits;
        _homeSnapshotReady =
            _teamTargetData != null ||
            _scheduleSummary != null ||
            _satorTargetBreakdown.isNotEmpty;
      });
      unawaited(_refreshHeaderVisualState());
    } catch (e) {
      debugPrint('SPV restore home snapshot cache failed: $e');
    }
  }

  Future<void> _persistHomeSnapshotCache({
    required Map<String, dynamic> profile,
    required Map<String, dynamic> teamTargetData,
    required Map<String, dynamic> scheduleSummary,
    required Map<String, dynamic> vastDaily,
    required Map<String, dynamic> vastWeekly,
    required Map<String, dynamic> vastMonthly,
    required List<Map<String, dynamic>> satorTargetBreakdown,
    required int todayOmzet,
    required int weekOmzet,
    required int monthOmzet,
    required int weekFocusUnits,
  }) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final prefs = await SharedPreferences.getInstance();
      final payload = <String, dynamic>{
        'profile': profile,
        'team_target_data': teamTargetData,
        'schedule_summary': scheduleSummary,
        'vast_daily': vastDaily,
        'vast_weekly': vastWeekly,
        'vast_monthly': vastMonthly,
        'sator_target_breakdown': satorTargetBreakdown,
        'today_omzet': todayOmzet,
        'week_omzet': weekOmzet,
        'month_omzet': monthOmzet,
        'week_focus_units': weekFocusUnits,
      };
      await prefs.setString(_homeSnapshotCacheKey(userId), jsonEncode(payload));
    } catch (e) {
      debugPrint('SPV persist home snapshot cache failed: $e');
    }
  }

  Future<void> _loadSpvKpiSummary() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final response = await Supabase.instance.client.rpc(
        'get_spv_kpi_summary',
        params: <String, dynamic>{'p_spv_id': userId},
      );
      if (!mounted || response == null) return;
      final payload = response is Map<String, dynamic>
          ? Map<String, dynamic>.from(response)
          : Map<String, dynamic>.from(response as Map);
      _updateState(() {
        _spvKpiSummary = payload;
      });
    } catch (_) {}
  }

  Future<void> _loadWeeklySnapshots() async {
    if (mounted) {
      _updateState(() {
        _weeklySnapshotReady = false;
      });
    }
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      final response = await Supabase.instance.client.rpc(
        'get_spv_home_weekly_snapshots',
        params: <String, dynamic>{
          'p_spv_id': userId,
          'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        },
      );
      if (!mounted || response == null) return;

      final payload = Map<String, dynamic>.from(response as Map);
      final snapshots = List<Map<String, dynamic>>.from(
        (payload['weekly_snapshots'] as List? ?? const <Map<String, dynamic>>[])
            .map((item) => Map<String, dynamic>.from(item as Map)),
      );
      final resolvedSelectedWeeklyKey = _resolveInitialWeeklyKey(
        snapshots,
        preferredKey: _selectedWeeklyKey,
        activeWeekNumber: _toInt(payload['active_week_number']),
      );
      final focusRowsByKey = <String, List<Map<String, dynamic>>>{};
      final specialRowsByKey = <String, List<Map<String, dynamic>>>{};
      for (final snapshot in snapshots) {
        final startDate = _parseDate(snapshot['start_date']);
        final endDate = _parseDate(snapshot['end_date']);
        if (startDate == null || endDate == null) continue;
        final key = _weeklySnapshotKey(snapshot);
        focusRowsByKey[key] = await _fetchDashboardFocusRows(
          scopeRole: 'spv',
          userId: userId,
          startDate: startDate,
          endDate: endDate.isAfter(DateTime.now()) ? DateTime.now() : endDate,
        );
        specialRowsByKey[key] = await _fetchDashboardSpecialRows(
          scopeRole: 'spv',
          userId: userId,
          startDate: startDate,
          endDate: endDate,
          rangeMode: 'weekly',
          weekPercentage: _toDouble(snapshot['percentage_of_total']),
        );
      }

      _updateState(() {
        _weeklySnapshots = snapshots;
        _weeklyFocusRowsByKey = focusRowsByKey;
        _weeklySpecialRowsByKey = specialRowsByKey;
        _selectedWeeklyKey = resolvedSelectedWeeklyKey;
        _weeklySnapshotReady = true;
      });
    } catch (_) {
      if (mounted) {
        _updateState(() {
          _weeklySnapshotReady = true;
        });
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchDashboardFocusRows({
    required String scopeRole,
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final response = await Supabase.instance.client.rpc(
      'get_dashboard_focus_product_rows',
      params: <String, dynamic>{
        'p_scope_role': scopeRole,
        'p_user_id': userId,
        'p_start_date': DateFormat('yyyy-MM-dd').format(startDate),
        'p_end_date': DateFormat('yyyy-MM-dd').format(endDate),
      },
    );
    return List<Map<String, dynamic>>.from(
      (response as List? ?? const <Map<String, dynamic>>[]).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchDashboardSpecialRows({
    required String scopeRole,
    required String userId,
    required DateTime startDate,
    required DateTime endDate,
    required String rangeMode,
    required num weekPercentage,
  }) async {
    final response = await Supabase.instance.client.rpc(
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
    return List<Map<String, dynamic>>.from(
      (response as List? ?? const <Map<String, dynamic>>[]).map(
        (item) => Map<String, dynamic>.from(item as Map),
      ),
    );
  }

  int _toInt(dynamic value) => value is int
      ? value
      : (value is num ? value.toInt() : (int.tryParse('${value ?? ''}') ?? 0));

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  bool _isTruthy(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final normalized = '${value ?? ''}'.trim().toLowerCase();
    return normalized == 'true' || normalized == '1' || normalized == 'yes';
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
    if (_homeFrameIndex == 1) {
      final selectedSnapshot = _selectedWeeklySnapshot();
      if (selectedSnapshot == null) return const <Map<String, dynamic>>[];
      return (_weeklyFocusRowsByKey[_weeklySnapshotKey(selectedSnapshot)] ??
              const <Map<String, dynamic>>[])
          .where((row) => !_isTruthy(row['is_special']))
          .toList();
    }
    if (_homeFrameIndex == 2) {
      return _monthlyFocusRows
          .where((row) => !_isTruthy(row['is_special']))
          .toList();
    }
    return _dailyFocusRows
        .where((row) => !_isTruthy(row['is_special']))
        .toList();
  }

  List<Map<String, dynamic>> get _activeSpecialRows {
    if (_homeFrameIndex == 1) {
      final selectedSnapshot = _selectedWeeklySnapshot();
      if (selectedSnapshot == null) return const <Map<String, dynamic>>[];
      return _weeklySpecialRowsByKey[_weeklySnapshotKey(selectedSnapshot)] ??
          const <Map<String, dynamic>>[];
    }
    if (_homeFrameIndex == 2) return _monthlySpecialRows;
    return _dailySpecialRows;
  }

  Map<String, dynamic> get _vastSnapshot {
    if (_homeFrameIndex == 1) {
      return Map<String, dynamic>.from(
        _vastWeekly ?? const <String, dynamic>{},
      );
    }
    if (_homeFrameIndex == 2) {
      return Map<String, dynamic>.from(
        _vastMonthly ?? const <String, dynamic>{},
      );
    }
    return Map<String, dynamic>.from(_vastDaily ?? const <String, dynamic>{});
  }

  String get _vastPeriodLabel {
    if (_homeFrameIndex == 1) {
      final selectedSnapshot = _selectedWeeklySnapshot();
      final weekNumber = _toInt(selectedSnapshot?['week_number']);
      return weekNumber > 0 ? 'minggu $weekNumber' : 'mingguan';
    }
    if (_homeFrameIndex == 2) return 'bulan ini';
    return 'hari ini';
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
}
