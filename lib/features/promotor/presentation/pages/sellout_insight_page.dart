import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/foundation/field_theme_extensions.dart';
import '../../../../ui/promotor/promotor.dart';

class SelloutInsightPage extends StatefulWidget {
  const SelloutInsightPage({
    super.key,
    this.userIdOverride,
    this.titleOverride,
  });

  final String? userIdOverride;
  final String? titleOverride;

  @override
  State<SelloutInsightPage> createState() => _SelloutInsightPageState();
}

class _SelloutInsightPageState extends State<SelloutInsightPage> {
  final _supabase = Supabase.instance.client;
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final _moneyCompact = NumberFormat.compactCurrency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _loading = true;
  DateTime _referenceDate = DateTime.now();
  int _selectedTab = 0;

  Map<String, dynamic> _currentInsight = const {};
  Map<String, dynamic> _previousInsight = const {};
  List<Map<String, dynamic>> _salesRows = const [];
  List<Map<String, dynamic>> _vastRows = const [];

  Map<String, dynamic> _currentTargetMeta = const {};
  Map<String, dynamic> _previousTargetMeta = const {};
  Set<String> _currentFocusProductIds = const <String>{};
  Set<String> _currentSpecialProductIds = const <String>{};
  String? _leftWeekKey;
  String? _rightWeekKey;
  String _headerFullName = '';

  FieldThemeTokens get t => context.fieldTokens;

  DateTime get _monthStart =>
      DateTime(_referenceDate.year, _referenceDate.month, 1);
  DateTime get _prevMonthStart =>
      DateTime(_referenceDate.year, _referenceDate.month - 1, 1);

  DateTime get _prevMonthEnd {
    final endOfPrevMonth = DateTime(_referenceDate.year, _referenceDate.month, 0);
    return DateTime(
      endOfPrevMonth.year,
      endOfPrevMonth.month,
      math.min(endOfPrevMonth.day, _referenceDate.day),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadInsight();
  }

  Future<void> _loadInsight() async {
    final userId = widget.userIdOverride ?? _supabase.auth.currentUser?.id;
    if (userId == null) return;
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final currentStart = _fmtDate(_monthStart);
      final currentEnd = _fmtDate(_referenceDate);
      final prevStart = _fmtDate(_prevMonthStart);
      final prevEnd = _fmtDate(_prevMonthEnd);

      final results = await Future.wait<dynamic>([
        _supabase
            .from('users')
            .select('full_name, nickname')
            .eq('id', userId)
            .maybeSingle(),
        _supabase.rpc(
          'get_promotor_sellout_insight',
          params: {
            'p_user_id': userId,
            'p_start_date': currentStart,
            'p_end_date': currentEnd,
          },
        ),
        _supabase.rpc(
          'get_promotor_sellout_insight',
          params: {
            'p_user_id': userId,
            'p_start_date': prevStart,
            'p_end_date': prevEnd,
          },
        ),
        _supabase
            .from('sales_sell_out')
            .select(
              'transaction_date, is_chip_sale, price_at_transaction, '
              'product_variants!inner(ram_rom, color, products!inner(id, model_name))',
            )
            .eq('promotor_id', userId)
            .isFilter('deleted_at', null)
            .gte('transaction_date', prevStart)
            .lte('transaction_date', currentEnd),
        _supabase
            .from('vast_applications')
            .select(
              'application_date, outcome_status, lifecycle_status, product_label',
            )
            .eq('promotor_id', userId)
            .isFilter('deleted_at', null)
            .gte('application_date', prevStart)
            .lte('application_date', currentEnd),
        _supabase.rpc(
          'get_daily_target_dashboard',
          params: {
            'p_user_id': userId,
            'p_date': currentEnd,
          },
        ),
        _supabase.rpc(
          'get_daily_target_dashboard',
          params: {
            'p_user_id': userId,
            'p_date': prevEnd,
          },
        ),
      ]);

      final userProfile = _asMap(results[0]);
      final currentInsight = _asMap(results[1]);
      final previousInsight = _asMap(results[2]);
      final salesRows = _asList(results[3]);
      final vastRows = _asList(results[4]);
      final currentDtd = _firstOf(results[5]);
      final prevDtd = _firstOf(results[6]);

      final targetPeriodIds = <String>{
        if (currentDtd['period_id'] != null) '${currentDtd['period_id']}',
        if (prevDtd['period_id'] != null) '${prevDtd['period_id']}',
      }.toList();

      final targetRows = targetPeriodIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : _asList(
              await _supabase
                  .from('user_targets')
                  .select(
                    'period_id, target_omzet, target_sell_out, '
                    'target_fokus_total, target_special, '
                    'target_fokus_detail, target_special_detail',
                  )
                  .eq('user_id', userId)
                  .inFilter('period_id', targetPeriodIds),
            );

      final currentTargetMeta = _matchTargetMeta(
        targetRows,
        currentDtd['period_id']?.toString(),
      );
      final previousTargetMeta = _matchTargetMeta(
        targetRows,
        prevDtd['period_id']?.toString(),
      );

      final currentFocusProductIds = await _loadFocusProductIds(
        currentDtd['period_id']?.toString(),
        currentTargetMeta,
      );
      final currentSpecialProductIds = await _loadSpecialProductIds(
        currentTargetMeta,
      );
      if (!mounted) return;
      setState(() {
        _currentInsight = currentInsight;
        _previousInsight = previousInsight;
        _salesRows = salesRows;
        _vastRows = vastRows;
        _currentTargetMeta = currentTargetMeta;
        _previousTargetMeta = previousTargetMeta;
        _currentFocusProductIds = currentFocusProductIds;
        _currentSpecialProductIds = currentSpecialProductIds;
        _headerFullName = _displayName(userProfile, fallback: 'Promotor');
        _loading = false;
      });
      _ensureWeekSelection();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _currentInsight = const {};
        _previousInsight = const {};
        _salesRows = const [];
        _vastRows = const [];
        _currentTargetMeta = const {};
        _previousTargetMeta = const {};
        _currentFocusProductIds = const <String>{};
        _currentSpecialProductIds = const <String>{};
        _headerFullName = '';
        _loading = false;
      });
    }
  }

  String _displayName(Map<String, dynamic> row, {required String fallback}) {
    final fullName = '${row['full_name'] ?? ''}'.trim();
    if (fullName.isNotEmpty) return fullName;
    final nickname = '${row['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    return fallback;
  }

  Future<Set<String>> _loadFocusProductIds(
    String? periodId,
    Map<String, dynamic> meta,
  ) async {
    if (periodId == null || periodId.isEmpty) return const <String>{};
    try {
      final rows = _asList(
        await _supabase.rpc(
          'get_target_focus_product_ids',
          params: {
            'p_period_id': periodId,
            'p_target_fokus_detail':
                _asMap(meta['target_fokus_detail']).isEmpty
                    ? {}
                    : _asMap(meta['target_fokus_detail']),
            'p_target_special_detail':
                _asMap(meta['target_special_detail']).isEmpty
                    ? {}
                    : _asMap(meta['target_special_detail']),
          },
        ),
      );
      return rows
          .map((row) => '${row['product_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  Future<Set<String>> _loadSpecialProductIds(Map<String, dynamic> meta) async {
    final specialDetail = _asMap(meta['target_special_detail']);
    final bundleIds = specialDetail.keys.toList();
    if (bundleIds.isEmpty) return const <String>{};
    try {
      final rows = _asList(
        await _supabase
            .from('special_focus_bundle_products')
            .select('product_id')
            .inFilter('bundle_id', bundleIds),
      );
      return rows
          .map((row) => '${row['product_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet();
    } catch (_) {
      return const <String>{};
    }
  }

  Map<String, dynamic> _matchTargetMeta(
    List<Map<String, dynamic>> rows,
    String? periodId,
  ) {
    if (periodId == null || periodId.isEmpty) return const {};
    return rows.firstWhere(
      (row) => '${row['period_id'] ?? ''}' == periodId,
      orElse: () => <String, dynamic>{},
    );
  }

  void _ensureWeekSelection() {
    final weeks = _weeklyRows;
    if (weeks.isEmpty) {
      _leftWeekKey = null;
      _rightWeekKey = null;
      return;
    }
    final last = weeks.last;
    final prev = weeks.length > 1 ? weeks[weeks.length - 2] : weeks.last;
    setState(() {
      _rightWeekKey ??= _weekKey(last);
      _leftWeekKey ??= _weekKey(prev);
      if (!weeks.any((row) => _weekKey(row) == _rightWeekKey)) {
        _rightWeekKey = _weekKey(last);
      }
      if (!weeks.any((row) => _weekKey(row) == _leftWeekKey)) {
        _leftWeekKey = _weekKey(prev);
      }
    });
  }

  String _fmtDate(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return <Map<String, dynamic>>[];
  }

  Map<String, dynamic> _firstOf(dynamic value) {
    final rows = _asList(value);
    return rows.isNotEmpty ? rows.first : <String, dynamic>{};
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('$value') ?? 0;
  }

  String _weekKey(Map<String, dynamic> row) =>
      '${row['week_number'] ?? ''}-${row['week_start'] ?? ''}';

  String _formatMoney(num value) => _money.format(value);

  String _formatMoneyTight(num value) => _moneyCompact.format(value);

  String _formatPct(num value) => '${value.toStringAsFixed(1)}%';

  Color _toneForPct(num pct) {
    if (pct >= 100) return t.success;
    if (pct >= 70) return t.primaryAccent;
    return t.danger;
  }

  num _sumDetailValues(dynamic detail) {
    final map = _asMap(detail);
    num total = 0;
    for (final value in map.values) {
      total += _toNum(value);
    }
    return total;
  }

  bool _isClosingVast(Map<String, dynamic> row) {
    final outcome = '${row['outcome_status'] ?? ''}'.toLowerCase();
    final lifecycle = '${row['lifecycle_status'] ?? ''}'.toLowerCase();
    return outcome == 'acc' ||
        lifecycle == 'closed_direct' ||
        lifecycle == 'closed_follow_up';
  }

  String _typeLabelFromSale(Map<String, dynamic> row) {
    final variant = _asMap(row['product_variants']);
    final product = _asMap(variant['products']);
    final model = '${product['model_name'] ?? ''}'.trim();
    final ramRom = '${variant['ram_rom'] ?? ''}'.trim();
    final color = '${variant['color'] ?? ''}'.trim();
    return [model, ramRom, color].where((part) => part.isNotEmpty).join(' ');
  }

  String _productIdFromSale(Map<String, dynamic> row) {
    final variant = _asMap(row['product_variants']);
    final product = _asMap(variant['products']);
    return '${product['id'] ?? ''}';
  }

  List<Map<String, dynamic>> get _currentSalesRows => _salesRows.where((row) {
        final date = DateTime.tryParse('${row['transaction_date'] ?? ''}');
        if (date == null) return false;
        return !date.isBefore(_monthStart) && !date.isAfter(_referenceDate);
      }).toList();

  List<Map<String, dynamic>> get _previousSalesRows => _salesRows.where((row) {
        final date = DateTime.tryParse('${row['transaction_date'] ?? ''}');
        if (date == null) return false;
        return !date.isBefore(_prevMonthStart) && !date.isAfter(_prevMonthEnd);
      }).toList();

  List<Map<String, dynamic>> get _currentVastRows => _vastRows.where((row) {
        final date = DateTime.tryParse('${row['application_date'] ?? ''}');
        if (date == null) return false;
        return !date.isBefore(_monthStart) && !date.isAfter(_referenceDate);
      }).toList();

  List<Map<String, dynamic>> get _previousVastRows => _vastRows.where((row) {
        final date = DateTime.tryParse('${row['application_date'] ?? ''}');
        if (date == null) return false;
        return !date.isBefore(_prevMonthStart) && !date.isAfter(_prevMonthEnd);
      }).toList();

  List<Map<String, dynamic>> get _dailyRows {
    final dailyTrend = _asList(_currentInsight['daily_trend']);
    final summary = _asMap(_currentInsight['summary']);
    final specialMonthlyTarget = _sumDetailValues(
      _currentTargetMeta['target_special_detail'],
    );
    final totalTarget = _toNum(summary['target_total']);

    final freshByDate = <String, List<Map<String, dynamic>>>{};
    final chipByDate = <String, List<Map<String, dynamic>>>{};
    for (final row in _currentSalesRows) {
      final dateKey = '${row['transaction_date'] ?? ''}';
      final isChip = row['is_chip_sale'] == true;
      (isChip ? chipByDate : freshByDate)
          .putIfAbsent(dateKey, () => <Map<String, dynamic>>[])
          .add(row);
    }

    final vastByDate = <String, List<Map<String, dynamic>>>{};
    for (final row in _currentVastRows) {
      final dateKey = '${row['application_date'] ?? ''}';
      vastByDate.putIfAbsent(dateKey, () => <Map<String, dynamic>>[]).add(row);
    }

    num previousActual = 0;
    final rows = <Map<String, dynamic>>[];
    for (final row in dailyTrend) {
      final dateKey = '${row['date'] ?? ''}';
      final freshRows = freshByDate[dateKey] ?? const <Map<String, dynamic>>[];
      final chipRows = chipByDate[dateKey] ?? const <Map<String, dynamic>>[];
      final vastRows = vastByDate[dateKey] ?? const <Map<String, dynamic>>[];
      final targetOmzet = _toNum(row['target_all']);
      final actualOmzet = _toNum(row['all_actual']);
      final focusTarget = _toNum(row['target_focus']);
      final focusActual = _toNum(row['focus_units']);
      final specialActual = _toNum(row['special_units']);
      final specialTarget = totalTarget > 0
          ? (specialMonthlyTarget * targetOmzet / totalTarget)
          : 0;

      final freshTypes = _buildTypeRows(
        freshRows,
        _currentFocusProductIds,
        _currentSpecialProductIds,
      );
      final chipTypes = _buildTypeRows(chipRows, const <String>{}, const <String>{});
      final specialTypes = freshTypes.where((e) => e['is_special'] == true).toList();
      final vastInput = vastRows.length;
      final vastClosing = vastRows.where(_isClosingVast).length;

      final trendDelta = actualOmzet - previousActual;
      rows.add({
        'date': dateKey,
        'target_omzet': targetOmzet,
        'actual_omzet': actualOmzet,
        'achievement_pct': targetOmzet > 0 ? (actualOmzet / targetOmzet) * 100 : 0,
        'target_focus': focusTarget,
        'actual_focus': focusActual,
        'focus_achievement_pct':
            focusTarget > 0 ? (focusActual / focusTarget) * 100 : 0,
        'target_special': specialTarget,
        'actual_special': specialActual,
        'special_achievement_pct':
            specialTarget > 0 ? (specialActual / specialTarget) * 100 : 0,
        'fresh_units': _toNum(row['all_units']).toInt(),
        'chip_units': chipRows.length,
        'fresh_types': freshTypes,
        'chip_types': chipTypes,
        'special_types': specialTypes,
        'vast_input': vastInput,
        'vast_closing': vastClosing,
        'trend_delta': trendDelta,
        'trend_direction':
            trendDelta > 0 ? 'up' : (trendDelta < 0 ? 'down' : 'flat'),
      });
      previousActual = actualOmzet;
    }
    return rows;
  }

  List<Map<String, dynamic>> _buildTypeRows(
    List<Map<String, dynamic>> source,
    Set<String> focusIds,
    Set<String> specialIds,
  ) {
    final grouped = <String, Map<String, dynamic>>{};
    for (final row in source) {
      final typeLabel = _typeLabelFromSale(row);
      if (typeLabel.isEmpty) continue;
      final productId = _productIdFromSale(row);
      final existing = grouped[typeLabel];
      if (existing == null) {
        grouped[typeLabel] = {
          'type_label': typeLabel,
          'units': 1,
          'omzet': _toNum(row['price_at_transaction']),
          'is_chip': row['is_chip_sale'] == true,
          'is_focus': focusIds.contains(productId),
          'is_special': specialIds.contains(productId),
        };
      } else {
        existing['units'] = _toNum(existing['units']).toInt() + 1;
        existing['omzet'] =
            _toNum(existing['omzet']) + _toNum(row['price_at_transaction']);
      }
    }

    final rows = grouped.values.toList();
    rows.sort((a, b) {
      final unitCompare = _toNum(b['units']).compareTo(_toNum(a['units']));
      if (unitCompare != 0) return unitCompare;
      return _toNum(b['omzet']).compareTo(_toNum(a['omzet']));
    });
    return rows;
  }

  List<Map<String, dynamic>> get _weeklyRows {
    final weekly = _asList(_currentInsight['weekly_details']);
    final summary = _asMap(_currentInsight['summary']);
    final totalTarget = _toNum(summary['target_total']);
    final specialMonthlyTarget = _sumDetailValues(
      _currentTargetMeta['target_special_detail'],
    );

    return weekly.map((row) {
      final weekStart = DateTime.tryParse('${row['week_start'] ?? ''}');
      final weekEnd = DateTime.tryParse('${row['week_end'] ?? ''}');
      final targetOmzet = _toNum(row['target']);
      final actualOmzet = _toNum(row['actual']);
      final focusTarget = _dailyRows
          .where((daily) => _isDateBetween(daily['date'], weekStart, weekEnd))
          .fold<num>(0, (sum, daily) => sum + _toNum(daily['target_focus']));
      final focusActual = _toNum(row['focus_units']);
      final specialTarget = totalTarget > 0
          ? (specialMonthlyTarget * targetOmzet / totalTarget)
          : 0;
      final specialActual = _toNum(row['special_units']);
      final freshRows = _currentSalesRows.where((sale) {
        final txDate = DateTime.tryParse('${sale['transaction_date'] ?? ''}');
        return sale['is_chip_sale'] != true &&
            txDate != null &&
            !txDate.isBefore(weekStart ?? _monthStart) &&
            !txDate.isAfter(weekEnd ?? _referenceDate);
      }).toList();
      final chipRows = _currentSalesRows.where((sale) {
        final txDate = DateTime.tryParse('${sale['transaction_date'] ?? ''}');
        return sale['is_chip_sale'] == true &&
            txDate != null &&
            !txDate.isBefore(weekStart ?? _monthStart) &&
            !txDate.isAfter(weekEnd ?? _referenceDate);
      }).toList();
      final weekVast = _currentVastRows.where((item) {
        final appDate = DateTime.tryParse('${item['application_date'] ?? ''}');
        return appDate != null &&
            !appDate.isBefore(weekStart ?? _monthStart) &&
            !appDate.isAfter(weekEnd ?? _referenceDate);
      }).toList();
      final weekTypes = _buildTypeRows(
        freshRows,
        _currentFocusProductIds,
        _currentSpecialProductIds,
      );
      final topType = weekTypes.isEmpty ? null : weekTypes.first;
      final topSpecialType =
          weekTypes.where((item) => item['is_special'] == true).cast<Map<String, dynamic>>().toList();

      return {
        ...row,
        'target_omzet': targetOmzet,
        'actual_omzet': actualOmzet,
        'achievement_pct':
            targetOmzet > 0 ? (actualOmzet / targetOmzet) * 100 : 0,
        'target_focus': focusTarget,
        'actual_focus': focusActual,
        'focus_achievement_pct':
            focusTarget > 0 ? (focusActual / focusTarget) * 100 : 0,
        'target_special': specialTarget,
        'actual_special': specialActual,
        'special_achievement_pct':
            specialTarget > 0 ? (specialActual / specialTarget) * 100 : 0,
        'chip_units': chipRows.length,
        'vast_input': weekVast.length,
        'vast_closing': weekVast.where(_isClosingVast).length,
        'best_type': topType,
        'best_special_type': topSpecialType.isEmpty ? null : topSpecialType.first,
      };
    }).toList();
  }

  bool _isDateBetween(dynamic dateValue, DateTime? start, DateTime? end) {
    final date = DateTime.tryParse('$dateValue');
    if (date == null) return false;
    if (start != null && date.isBefore(start)) return false;
    if (end != null && date.isAfter(end)) return false;
    return true;
  }

  Map<String, dynamic> get _summaryData {
    final summary = _asMap(_currentInsight['summary']);
    final monthlyTarget = _monthlySelloutTarget(_currentTargetMeta);
    final chipUnits = _currentSalesRows.where((row) => row['is_chip_sale'] == true).length;
    final vastInput = _currentVastRows.length;
    final vastClosing = _currentVastRows.where(_isClosingVast).length;
    final focusTarget = _monthlyFocusTarget(_currentTargetMeta);
    final focusActual = _dailyRows.fold<num>(
      0,
      (sum, row) => sum + _toNum(row['actual_focus']),
    );
    final specialTarget = _monthlySpecialTarget(_currentTargetMeta);
    final specialActual = _dailyRows.fold<num>(
      0,
      (sum, row) => sum + _toNum(row['actual_special']),
    );
    final freshTypes = _buildTypeRows(
      _currentSalesRows.where((row) => row['is_chip_sale'] != true).toList(),
      _currentFocusProductIds,
      _currentSpecialProductIds,
    );
    final soldTypes = _buildTypeRows(
      _currentSalesRows,
      _currentFocusProductIds,
      _currentSpecialProductIds,
    );
    final bestType = freshTypes.isEmpty ? null : freshTypes.first;
    final bestSpecial = freshTypes
        .where((row) => row['is_special'] == true)
        .cast<Map<String, dynamic>>()
        .toList();

    return {
      ...summary,
      'target_total': monthlyTarget,
      'gap_total': math.max(monthlyTarget - _toNum(summary['actual_total']), 0),
      'achievement_pct': monthlyTarget > 0
          ? (_toNum(summary['actual_total']) / monthlyTarget) * 100
          : 0,
      'chip_units': chipUnits,
      'focus_target_total': focusTarget,
      'focus_actual_total': focusActual,
      'focus_achievement_pct': focusTarget > 0 ? (focusActual / focusTarget) * 100 : 0,
      'special_target_total': specialTarget,
      'special_actual_total': specialActual,
      'special_achievement_pct':
          specialTarget > 0 ? (specialActual / specialTarget) * 100 : 0,
      'vast_input_total': vastInput,
      'vast_closing_total': vastClosing,
      'sold_types': soldTypes,
      'best_type': bestType,
      'best_special_type': bestSpecial.isEmpty ? null : bestSpecial.first,
    };
  }

  Map<String, dynamic> get _monthCompare {
    final currentSummary = _summaryData;
    final previousSummaryBase = _asMap(_previousInsight['summary']);
    final previousDaily = _asList(_previousInsight['daily_trend']);
    final previousMonthlyTarget = _monthlySelloutTarget(_previousTargetMeta);
    final previousFocusTarget = _monthlyFocusTarget(_previousTargetMeta);
    final previousSpecialTarget = _monthlySpecialTarget(_previousTargetMeta);
    final previousSpecialActual = previousDaily.fold<num>(
      0,
      (sum, row) => sum + _toNum(row['special_units']),
    );
    final previousData = {
      ...previousSummaryBase,
      'target_total': previousMonthlyTarget,
      'gap_total':
          math.max(previousMonthlyTarget - _toNum(previousSummaryBase['actual_total']), 0),
      'achievement_pct': previousMonthlyTarget > 0
          ? (_toNum(previousSummaryBase['actual_total']) / previousMonthlyTarget) * 100
          : 0,
      'chip_units': _previousSalesRows.where((row) => row['is_chip_sale'] == true).length,
      'focus_target_total': previousFocusTarget,
      'focus_actual_total': _toNum(previousSummaryBase['focus_units_total']),
      'focus_achievement_pct': previousFocusTarget > 0
          ? (_toNum(previousSummaryBase['focus_units_total']) / previousFocusTarget) * 100
          : 0,
      'special_target_total': previousSpecialTarget,
      'special_actual_total': previousSpecialActual,
      'special_achievement_pct': previousSpecialTarget > 0
          ? (previousSpecialActual / previousSpecialTarget) * 100
          : 0,
      'vast_input_total': _previousVastRows.length,
      'vast_closing_total': _previousVastRows.where(_isClosingVast).length,
    };
    final hasPrevious = _toNum(previousData['target_total']) > 0 ||
        _toNum(previousData['actual_total']) > 0 ||
        _toNum(previousData['vast_input_total']) > 0 ||
        _toNum(previousData['chip_units']) > 0;

    return {
      'current': currentSummary,
      'previous': previousData,
      'has_previous': hasPrevious,
      'actual_delta':
          _toNum(currentSummary['actual_total']) - _toNum(previousData['actual_total']),
      'focus_delta': _toNum(currentSummary['focus_actual_total']) -
          _toNum(previousData['focus_actual_total']),
      'special_delta': _toNum(currentSummary['special_actual_total']) -
          _toNum(previousData['special_actual_total']),
      'vast_delta': _toNum(currentSummary['vast_closing_total']) -
          _toNum(previousData['vast_closing_total']),
    };
  }

  num _monthlySelloutTarget(Map<String, dynamic> meta) {
    final targetOmzet = _toNum(meta['target_omzet']);
    if (targetOmzet > 0) return targetOmzet;
    return _toNum(meta['target_sell_out']);
  }

  num _monthlyFocusTarget(Map<String, dynamic> meta) {
    final focusTotal = _toNum(meta['target_fokus_total']);
    if (focusTotal > 0) return focusTotal;
    return _sumDetailValues(meta['target_fokus_detail']) +
        _sumDetailValues(meta['target_special_detail']);
  }

  num _monthlySpecialTarget(Map<String, dynamic> meta) {
    final specialTotal = _toNum(meta['target_special']);
    if (specialTotal > 0) return specialTotal;
    return _sumDetailValues(meta['target_special_detail']);
  }

  Map<String, dynamic>? _selectedWeek(String? key) {
    if (key == null) return null;
    for (final row in _weeklyRows) {
      if (_weekKey(row) == key) return row;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.shellBackground,
      appBar: AppBar(
        backgroundColor: t.shellBackground,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.titleOverride ?? 'Sell Out Insight'),
            if (_headerFullName.isNotEmpty)
              Text(
                _headerFullName,
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
          : RefreshIndicator(
              onRefresh: _loadInsight,
              color: t.primaryAccent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                children: [
                  _buildDateBar(),
                  const SizedBox(height: 10),
                  _buildTabBar(),
                  const SizedBox(height: 10),
                  if (_selectedTab == 0) ...[
                    _buildSummaryCard(),
                  ] else if (_selectedTab == 1) ...[
                    _buildDailyAchievementCard(),
                  ] else if (_selectedTab == 2) ...[
                    _buildWeeklyCompareCard(),
                    const SizedBox(height: 10),
                    _buildWeeklyTypeCompareCard(),
                  ] else ...[
                    _buildMonthCompareCard(),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildDateBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Periode aktif',
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat('d MMM', 'id_ID').format(_monthStart)} - ${DateFormat('d MMM yyyy', 'id_ID').format(_referenceDate)}',
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          InkWell(
            onTap: _pickReferenceDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.surface3),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 16,
                    color: t.primaryAccent,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    DateFormat('d MMM', 'id_ID').format(_referenceDate),
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
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

  Future<void> _pickReferenceDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _referenceDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _referenceDate = picked);
    await _loadInsight();
  }

  Widget _buildTabBar() {
    final labels = const ['Summary', 'Harian', 'Mingguan', 'Bulanan'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = index == _selectedTab;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _selectedTab = index),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? t.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  labels[index],
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: active ? t.textOnAccent : t.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildSummaryCard() {
    final summary = _summaryData;
    final target = _toNum(summary['target_total']);
    final actual = _toNum(summary['actual_total']);
    final pct = _toNum(summary['achievement_pct']);
    final gap = math.max(target - actual, 0);
    final bestType = _asMap(summary['best_type']);
    final bestSpecial = _asMap(summary['best_special_type']);
    final soldTypes = _asList(summary['sold_types']);

    return _card(
      'Ringkasan Pencapaian',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.surface3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sell Out bulan berjalan',
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _formatMoney(actual),
                  style: PromotorText.display(
                    size: 26,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _miniMetric('Target', _formatMoneyTight(target), t.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniMetric('Gap', _formatMoneyTight(gap), t.warning),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniMetric('Achv', _formatPct(pct), _toneForPct(pct)),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _summaryStatTile(
                  'Produk Fokus',
                  '${_toNum(summary['focus_actual_total']).toInt()} / ${_toNum(summary['focus_target_total']).toInt()}',
                  _toneForPct(_toNum(summary['focus_achievement_pct'])),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryStatTile(
                  'Tipe Khusus',
                  '${_toNum(summary['special_actual_total']).toInt()} / ${_toNum(summary['special_target_total']).toInt()}',
                  _toneForPct(_toNum(summary['special_achievement_pct'])),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _summaryStatTile(
                  'VAST Input',
                  '${_toNum(summary['vast_input_total']).toInt()}',
                  t.info,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryStatTile(
                  'VAST Closing',
                  '${_toNum(summary['vast_closing_total']).toInt()}',
                  t.success,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryStatTile(
                  'Chip',
                  '${_toNum(summary['chip_units']).toInt()}',
                  t.warning,
                ),
              ),
            ],
          ),
          if (bestType.isNotEmpty || bestSpecial.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.surface3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bestType.isNotEmpty)
                    Text(
                      'Tipe terlaris: ${bestType['type_label']} (${bestType['units']} unit)',
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                  if (bestType.isNotEmpty && bestSpecial.isNotEmpty)
                    const SizedBox(height: 4),
                  if (bestSpecial.isNotEmpty)
                    Text(
                      'Tipe khusus terlaris: ${bestSpecial['type_label']} (${bestSpecial['units']} unit)',
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                ],
              ),
            ),
          ],
          if (soldTypes.isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.surface3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Semua Tipe Terjual',
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...soldTypes.map(_buildSummarySoldTypeRow),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummarySoldTypeRow(Map<String, dynamic> row) {
    final isChip = row['is_chip'] == true;
    final qty = _toNum(row['units']).toInt();
    final tone = isChip ? t.warning : t.primaryAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          if (isChip) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: t.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'CHIP',
                style: PromotorText.outfit(
                  size: 8.5,
                  weight: FontWeight.w800,
                  color: t.warning,
                ),
              ),
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: Text(
              '${row['type_label'] ?? '-'}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${qty}x',
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyAchievementCard() {
    final rows = _dailyRows.reversed.toList();
    if (rows.isEmpty) {
      return _card(
        'Achievement Harian',
        child: _noteCard('Belum ada data harian pada periode ini.'),
      );
    }

    return _card(
      'Achievement Harian',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _noteCard(
            'Tap baris untuk lihat detail tipe fresh, chip, tipe khusus, dan vast hari itu.',
          ),
          const SizedBox(height: 6),
          _buildDailyTableHeader(),
          const SizedBox(height: 4),
          ...rows.map(_buildDailyCompactRow),
        ],
      ),
    );
  }

  Widget _buildDailyTableHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          _dailyHeaderCell('Tanggal', 44, TextAlign.left),
          _dailyHeaderCell('Sell Out', 78, TextAlign.right),
          _dailyHeaderCell('Persen', 44, TextAlign.right),
          _dailyHeaderCell('Tipe Fokus', 58, TextAlign.center),
          _dailyHeaderCell('Vast', 40, TextAlign.center),
          _dailyHeaderCell('Chip', 34, TextAlign.center),
        ],
      ),
    );
  }

  Widget _dailyHeaderCell(String label, double width, TextAlign align) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PromotorText.outfit(
          size: 8,
          weight: FontWeight.w800,
          color: t.textMuted,
        ),
      ),
    );
  }

  Widget _buildDailyCompactRow(Map<String, dynamic> row) {
    final date = DateTime.tryParse('${row['date'] ?? ''}');
    final achv = _toNum(row['achievement_pct']);
    final tone = _toneForPct(achv);
    final focusCount = _toNum(row['actual_focus']).toInt();
    final vastClosing = _toNum(row['vast_closing']).toInt();
    final chipCount = _toNum(row['chip_units']).toInt();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _showDailyDetail(row),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.only(bottom: 4),
          padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.surface3),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 44,
                child: Text(
                  date == null ? '-' : DateFormat('d MMM', 'id_ID').format(date),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              SizedBox(
                width: 78,
                child: Text(
                  _formatMoneyTight(_toNum(row['actual_omzet'])),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 9.5,
                    weight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  '${achv.toStringAsFixed(0)}%',
                  textAlign: TextAlign.right,
                  style: PromotorText.outfit(
                    size: 9.5,
                    weight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ),
              SizedBox(
                width: 58,
                child: Text(
                  '$focusCount',
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
              ),
              SizedBox(
                width: 40,
                child: Text(
                  '$vastClosing',
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w700,
                    color: t.info,
                  ),
                ),
              ),
              SizedBox(
                width: 34,
                child: Text(
                  '$chipCount',
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w700,
                    color: chipCount > 0 ? t.warning : t.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showDailyDetail(Map<String, dynamic> row) async {
    final date = DateTime.tryParse('${row['date'] ?? ''}');
    final achv = _toNum(row['achievement_pct']);
    final specialTypes = _asList(row['special_types']);
    final trendDirection = '${row['trend_direction'] ?? 'flat'}';
    final trendDelta = _toNum(row['trend_delta']);
    final trendColor = trendDirection == 'up'
        ? t.success
        : (trendDirection == 'down' ? t.danger : t.textMuted);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.surface3,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        date == null
                            ? 'Detail Harian'
                            : DateFormat('EEEE, d MMMM yyyy', 'id_ID').format(date),
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: _toneForPct(achv).withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _formatPct(achv),
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w800,
                          color: _toneForPct(achv),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _miniMetric(
                        'Target',
                        _formatMoneyTight(_toNum(row['target_omzet'])),
                        t.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniMetric(
                        'Actual',
                        _formatMoneyTight(_toNum(row['actual_omzet'])),
                        _toneForPct(achv),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _miniMetric(
                        'Fokus',
                        '${_toNum(row['actual_focus']).toInt()} / ${_toNum(row['target_focus']).toInt()}',
                        _toneForPct(_toNum(row['focus_achievement_pct'])),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniMetric(
                        'Khusus',
                        '${_toNum(row['actual_special']).toInt()} / ${_toNum(row['target_special']).toStringAsFixed(1)}',
                        _toneForPct(_toNum(row['special_achievement_pct'])),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _smallTag('Fresh ${_toNum(row['fresh_units']).toInt()}'),
                    _smallTag('Chip ${_toNum(row['chip_units']).toInt()}'),
                    _smallTag('VAST In ${_toNum(row['vast_input']).toInt()}'),
                    _smallTag('VAST Closing ${_toNum(row['vast_closing']).toInt()}'),
                    _smallTag(
                      trendDirection == 'up'
                          ? 'Naik ${_formatMoneyTight(trendDelta)}'
                          : trendDirection == 'down'
                              ? 'Turun ${_formatMoneyTight(trendDelta.abs())}'
                              : 'Flat',
                      color: trendColor,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _typeWrap('Fresh', _asList(row['fresh_types']), maxItems: 6),
                const SizedBox(height: 8),
                _typeWrap(
                  'Chip',
                  _asList(row['chip_types']),
                  maxItems: 6,
                  emptyLabel: 'Tidak ada chip',
                ),
                if (specialTypes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _typeWrap('Tipe Khusus', specialTypes, maxItems: 6),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _typeWrap(
    String label,
    List<Map<String, dynamic>> rows, {
    int maxItems = 3,
    String emptyLabel = 'Belum ada tipe terjual',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PromotorText.outfit(
            size: 10,
            weight: FontWeight.w700,
            color: t.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        if (rows.isEmpty)
          Text(
            emptyLabel,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: rows.take(maxItems).map((row) {
              final label = '${row['type_label'] ?? '-'}';
              final units = _toNum(row['units']).toInt();
              final isSpecial = row['is_special'] == true;
              final color = isSpecial ? t.warning : t.primaryAccent;
              return _smallTag('$label ($units)', color: color);
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildWeeklyCompareCard() {
    final weeks = _weeklyRows;
    if (weeks.isEmpty) {
      return _card(
        'Compare Week to Week',
        child: _noteCard('Belum ada data mingguan.'),
      );
    }
    final left = _selectedWeek(_leftWeekKey) ?? weeks.first;
    final right = _selectedWeek(_rightWeekKey) ?? weeks.last;

    return _card(
      'Compare Week to Week',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _weekSelector(
                  value: _leftWeekKey,
                  label: 'Pilih Minggu X',
                  onChanged: (value) => setState(() => _leftWeekKey = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _weekSelector(
                  value: _rightWeekKey,
                  label: 'Pilih Minggu Y',
                  onChanged: (value) => setState(() => _rightWeekKey = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.surface3),
            ),
            child: Column(
              children: [
                _buildWeeklyCompareHeader(left, right),
                _buildWeeklyCompareMetricRow(
                  'Sell Out',
                  _toNum(left['actual_omzet']),
                  _toNum(right['actual_omzet']),
                  money: true,
                ),
                _buildWeeklyCompareMetricRow(
                  'Produk Fokus',
                  _toNum(left['actual_focus']),
                  _toNum(right['actual_focus']),
                ),
                _buildWeeklyCompareMetricRow(
                  'Tipe Khusus',
                  _toNum(left['actual_special']),
                  _toNum(right['actual_special']),
                ),
                _buildWeeklyCompareMetricRow(
                  'VAST Input',
                  _toNum(left['vast_input']),
                  _toNum(right['vast_input']),
                ),
                _buildWeeklyCompareMetricRow(
                  'VAST Closing',
                  _toNum(left['vast_closing']),
                  _toNum(right['vast_closing']),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyCompareHeader(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    final leftLabel = '${left['week_label'] ?? 'Minggu X'}'
        .replaceFirst('·', '\n·')
        .trim();
    final rightLabel = '${right['week_label'] ?? 'Minggu Y'}'
        .replaceFirst('·', '\n·')
        .trim();
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: t.surface3)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Metrik',
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              leftLabel,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 9,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              rightLabel,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 9,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Selisih',
              textAlign: TextAlign.right,
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyCompareMetricRow(
    String label,
    num left,
    num right, {
    bool money = false,
  }) {
    final delta = right - left;
    final tone = delta > 0 ? t.success : (delta < 0 ? t.danger : t.textMuted);
    final leftLabel = money ? _formatMoneyTight(left) : '${left.toInt()}';
    final rightLabel = money ? _formatMoneyTight(right) : '${right.toInt()}';
    final deltaLabel = money ? _formatMoneyTight(delta) : '${delta.toInt()}';

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surface3)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: PromotorText.outfit(
                size: 10.5,
                weight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              leftLabel,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              rightLabel,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              delta > 0 ? '+$deltaLabel' : deltaLabel,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekSelector({
    required String? value,
    required String label,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: t.surface1,
          iconEnabledColor: t.textSecondary,
          style: PromotorText.outfit(
            size: 11,
            weight: FontWeight.w700,
            color: t.textPrimary,
          ),
          hint: Text(
            label,
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          items: _weeklyRows.map((row) {
            final key = _weekKey(row);
            return DropdownMenuItem<String>(
              value: key,
              child: Text('${row['week_label'] ?? 'Week'}'),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildWeeklyTypeCompareCard() {
    final weeks = _weeklyRows;
    if (weeks.isEmpty) {
      return _card(
        'Perbandingan Tipe Mingguan',
        child: _noteCard('Belum ada data tipe mingguan.'),
      );
    }
    final left = _selectedWeek(_leftWeekKey) ?? weeks.first;
    final right = _selectedWeek(_rightWeekKey) ?? weeks.last;
    final leftBestType = _asMap(left['best_type']);
    final rightBestType = _asMap(right['best_type']);
    final leftBestSpecial = _asMap(left['best_special_type']);
    final rightBestSpecial = _asMap(right['best_special_type']);

    return _card(
      'Perbandingan Tipe Mingguan',
      child: Container(
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.surface3),
        ),
        child: Column(
          children: [
            _buildWeeklyCompareHeader(left, right),
            _buildWeeklyTextCompareRow(
              'Tipe Terlaris',
              _typeSummaryLabel(leftBestType, empty: 'Belum ada'),
              _typeSummaryLabel(rightBestType, empty: 'Belum ada'),
            ),
            _buildWeeklyTextCompareRow(
              'Tipe Khusus',
              _typeSummaryLabel(leftBestSpecial, empty: 'Belum ada'),
              _typeSummaryLabel(rightBestSpecial, empty: 'Belum ada'),
            ),
            _buildWeeklyTextCompareRow(
              'Achv Sell Out',
              _formatPct(_toNum(left['achievement_pct'])),
              _formatPct(_toNum(right['achievement_pct'])),
            ),
            _buildWeeklyTextCompareRow(
              'Achv Fokus',
              _formatPct(_toNum(left['focus_achievement_pct'])),
              _formatPct(_toNum(right['focus_achievement_pct'])),
            ),
            _buildWeeklyTextCompareRow(
              'Achv Khusus',
              _formatPct(_toNum(left['special_achievement_pct'])),
              _formatPct(_toNum(right['special_achievement_pct'])),
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  String _typeSummaryLabel(
    Map<String, dynamic> row, {
    required String empty,
  }) {
    if (row.isEmpty) return empty;
    final label = '${row['type_label'] ?? '-'}';
    final units = _toNum(row['units']).toInt();
    return '$label ($units)';
  }

  Widget _buildWeeklyTextCompareRow(
    String label,
    String left,
    String right, {
    bool isLast = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        border: isLast ? null : Border(bottom: BorderSide(color: t.surface3)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: PromotorText.outfit(
                size: 10.5,
                weight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              left,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              right,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
          ),
          const Expanded(
            flex: 2,
            child: SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCompareCard() {
    final compare = _monthCompare;
    final current = _asMap(compare['current']);
    final previous = _asMap(compare['previous']);
    final hasPrevious = compare['has_previous'] == true;
    final currentLabel = DateFormat('MMMM yyyy', 'id_ID').format(_monthStart);
    final previousLabel = DateFormat('MMMM yyyy', 'id_ID').format(_prevMonthStart);

    return _card(
      'Banding Bulan Lalu',
      child: Column(
        children: [
          if (!hasPrevious) _noteCard('Tidak ada data bulan lalu.'),
          Container(
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.surface3),
            ),
            child: Column(
              children: [
                _buildMonthCompareHeader(previousLabel, currentLabel),
                _buildWeeklyCompareMetricRow(
                  'Sell Out',
                  _toNum(previous['actual_total']),
                  _toNum(current['actual_total']),
                  money: true,
                ),
                _buildWeeklyTextCompareRow(
                  'Achv Sell Out',
                  hasPrevious ? _formatPct(_toNum(previous['achievement_pct'])) : '-',
                  _formatPct(_toNum(current['achievement_pct'])),
                ),
                _buildWeeklyCompareMetricRow(
                  'Produk Fokus',
                  _toNum(previous['focus_actual_total']),
                  _toNum(current['focus_actual_total']),
                ),
                _buildWeeklyTextCompareRow(
                  'Achv Fokus',
                  hasPrevious
                      ? _formatPct(_toNum(previous['focus_achievement_pct']))
                      : '-',
                  _formatPct(_toNum(current['focus_achievement_pct'])),
                ),
                _buildWeeklyCompareMetricRow(
                  'Tipe Khusus',
                  _toNum(previous['special_actual_total']),
                  _toNum(current['special_actual_total']),
                ),
                _buildWeeklyTextCompareRow(
                  'Achv Khusus',
                  hasPrevious
                      ? _formatPct(_toNum(previous['special_achievement_pct']))
                      : '-',
                  _formatPct(_toNum(current['special_achievement_pct'])),
                ),
                _buildWeeklyCompareMetricRow(
                  'VAST Closing',
                  _toNum(previous['vast_closing_total']),
                  _toNum(current['vast_closing_total']),
                ),
                _buildWeeklyCompareMetricRow(
                  'Chip',
                  _toNum(previous['chip_units']),
                  _toNum(current['chip_units']),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthCompareHeader(String previousLabel, String currentLabel) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
        border: Border(bottom: BorderSide(color: t.surface3)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Metrik',
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              previousLabel,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 9,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              currentLabel,
              textAlign: TextAlign.right,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: 9,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Selisih',
              textAlign: TextAlign.right,
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(String title, {required Widget child}) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
              size: 12,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String value, Color tone) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
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
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
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

  Widget _summaryStatTile(String label, String value, Color tone) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 9.5,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 10.5,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallTag(String text, {Color? color}) {
    final tone = color ?? t.primaryAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.22)),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 10,
          weight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }

  Widget _noteCard(String text) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 10,
          weight: FontWeight.w700,
          color: t.textSecondary,
        ),
      ),
    );
  }
}
