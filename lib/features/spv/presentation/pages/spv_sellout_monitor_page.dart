import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/foundation/field_theme_extensions.dart';
import '../../../../ui/promotor/promotor.dart';

class SpvSellOutMonitorPage extends StatefulWidget {
  const SpvSellOutMonitorPage({super.key});

  @override
  State<SpvSellOutMonitorPage> createState() => _SpvSellOutMonitorPageState();
}

class _SpvSellOutMonitorPageState extends State<SpvSellOutMonitorPage> {
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
  String? _expandedSatorId;
  String? _leftWeekKey;
  String? _rightWeekKey;

  List<_SpvPromotorOverview> _promotors = const [];
  Map<String, dynamic> _currentSpvTargetMeta = const {};
  Map<String, dynamic> _previousSpvTargetMeta = const {};
  String _headerFullName = '';

  FieldThemeTokens get t => context.fieldTokens;
  DateTime get _monthStart =>
      DateTime(_referenceDate.year, _referenceDate.month, 1);
  DateTime get _prevMonthStart =>
      DateTime(_referenceDate.year, _referenceDate.month - 1, 1);
  DateTime get _prevMonthEnd {
    final endOfPrevMonth = DateTime(
      _referenceDate.year,
      _referenceDate.month,
      0,
    );
    return DateTime(
      endOfPrevMonth.year,
      endOfPrevMonth.month,
      math.min(endOfPrevMonth.day, _referenceDate.day),
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final spvId = _supabase.auth.currentUser?.id;
    if (spvId == null) return;
    if (mounted) setState(() => _loading = true);

    try {
      final snapshotRaw = await _supabase.rpc(
        'get_spv_sellout_insight_snapshot',
        params: {
          'p_spv_id': spvId,
          'p_reference_date': _fmtDate(_referenceDate),
        },
      );
      if (snapshotRaw is! Map) {
        throw Exception('Snapshot payload invalid');
      }

      final snapshot = _asMap(snapshotRaw);
      final selfProfile = _asMap(snapshot['profile']);
      final promotorRows = _asList(snapshot['promotors']);
      final built = <_SpvPromotorOverview>[];
      for (final row in promotorRows) {
        final id = '${row['id'] ?? ''}'.trim();
        if (id.isEmpty) continue;
        built.add(
          _SpvPromotorOverview(
            id: id,
            name: '${row['name'] ?? 'Promotor'}',
            satorId: '${row['sator_id'] ?? ''}',
            satorName: '${row['sator_name'] ?? 'Sator'}',
            storeName: '${row['store_name'] ?? 'Belum ada toko'}',
            referenceDate: _referenceDate,
            currentInsight: _asMap(row['current_insight']),
            previousInsight: _asMap(row['previous_insight']),
            currentTargetMeta: _asMap(row['current_target_meta']),
            previousTargetMeta: _asMap(row['previous_target_meta']),
            salesRows: _asList(row['sales_rows']),
            vastRows: _asList(row['vast_rows']),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _promotors = built;
        _currentSpvTargetMeta = _asMap(snapshot['current_spv_target_meta']);
        _previousSpvTargetMeta = _asMap(snapshot['previous_spv_target_meta']);
        _headerFullName = _displayName(selfProfile, fallback: 'SPV');
        _expandedSatorId = _expandedSatorId ?? built.firstOrNull?.satorId;
        _loading = false;
      });
      _ensureWeekSelection();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _promotors = const [];
        _currentSpvTargetMeta = const {};
        _previousSpvTargetMeta = const {};
        _headerFullName = '';
        _expandedSatorId = null;
        _loading = false;
      });
    }
  }

  void _ensureWeekSelection() {
    final weeks = _areaWeeklyRows;
    if (weeks.isEmpty || !mounted) return;
    final last = weeks.last;
    final prev = weeks.length > 1 ? weeks[weeks.length - 2] : weeks.last;
    setState(() {
      _rightWeekKey ??= _weekKey(last);
      _leftWeekKey ??= _weekKey(prev);
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

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('$value') ?? 0;
  }

  String _displayName(Map<String, dynamic> row, {required String fallback}) {
    final nickname = '${row['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    final fullName = '${row['full_name'] ?? ''}'.trim();
    if (fullName.isNotEmpty) return fullName;
    return fallback;
  }

  String _formatMoney(num value) => _money.format(value);
  String _formatMoneyTight(num value) => _moneyCompact.format(value);
  String _formatPct(num value) => '${value.toStringAsFixed(1)}%';
  String _weekKey(Map<String, dynamic> row) =>
      '${row['week_number'] ?? ''}-${row['week_start'] ?? ''}';

  Color _toneForPct(num pct) {
    if (pct >= 100) return t.success;
    if (pct >= 70) return t.primaryAccent;
    return t.danger;
  }

  Color _compareTone({
    required num left,
    required num right,
    required bool rightSide,
  }) {
    if (left == right) return t.textSecondary;
    if (rightSide) return right > left ? t.success : t.danger;
    return left > right ? t.success : t.danger;
  }

  String _formatWeekTitle(Map<String, dynamic> row) =>
      'Minggu ${row['week_number'] ?? '-'}';
  String _formatWeekRange(Map<String, dynamic> row) {
    final start = DateTime.tryParse('${row['week_start'] ?? ''}');
    final end = DateTime.tryParse('${row['week_end'] ?? ''}');
    if (start == null || end == null) return '-';
    return '${DateFormat('d MMM', 'id_ID').format(start)} - ${DateFormat('d MMM', 'id_ID').format(end)}';
  }

  String _typeLabelFromSale(Map<String, dynamic> row) {
    final variantLabel = '${row['variant_label'] ?? ''}'.trim();
    if (variantLabel.isNotEmpty) return variantLabel;
    final variant = _asMap(row['product_variants']);
    final product = _asMap(variant['products']);
    final model = '${product['model_name'] ?? ''}'.trim();
    final ramRom = '${variant['ram_rom'] ?? ''}'.trim();
    final color = '${variant['color'] ?? ''}'.trim();
    return [model, ramRom, color].where((part) => part.isNotEmpty).join(' ');
  }

  List<Map<String, dynamic>> _buildTypeRows(List<Map<String, dynamic>> source) {
    final grouped = <String, Map<String, dynamic>>{};
    for (final row in source) {
      final typeLabel = _typeLabelFromSale(row);
      if (typeLabel.isEmpty) continue;
      final existing = grouped[typeLabel];
      if (existing == null) {
        grouped[typeLabel] = {
          'type_label': typeLabel,
          'units': 1,
          'omzet': _toNum(row['price_at_transaction']),
          'is_chip': row['is_chip_sale'] == true,
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

  num _resolveOmzetTarget(Map<String, dynamic> meta) {
    final targetOmzet = _toNum(meta['target_omzet']);
    if (targetOmzet > 0) return targetOmzet;
    return _toNum(meta['target_sell_out']);
  }

  num _resolveFocusTarget(Map<String, dynamic> meta) {
    final focusTotal = _toNum(meta['target_fokus_total']);
    if (focusTotal > 0) return focusTotal;
    return _sumDetailValues(meta['target_fokus_detail']) +
        _sumDetailValues(meta['target_special_detail']);
  }

  num _resolveSpecialTarget(Map<String, dynamic> meta) {
    final specialTotal = _toNum(meta['target_special']);
    if (specialTotal > 0) return specialTotal;
    return _sumDetailValues(meta['target_special_detail']);
  }

  num _sumDetailValues(dynamic detail) {
    final map = _asMap(detail);
    num total = 0;
    for (final value in map.values) {
      total += _toNum(value);
    }
    return total;
  }

  Map<String, dynamic> get _areaSummary {
    num target = 0;
    num actual = 0;
    num focusTarget = 0;
    num focusActual = 0;
    num specialTarget = 0;
    num specialActual = 0;
    num vastInput = 0;
    num vastClosing = 0;
    num chip = 0;
    for (final promotor in _promotors) {
      target += promotor.monthlyTarget;
      actual += promotor.actualCurrent;
      focusTarget += promotor.focusTargetCurrent;
      focusActual += promotor.focusActualCurrent;
      specialTarget += promotor.specialTargetCurrent;
      specialActual += promotor.specialActualCurrent;
      vastInput += promotor.vastInputCurrent;
      vastClosing += promotor.vastClosingCurrent;
      chip += promotor.chipCurrent;
    }

    final spvTarget = _resolveOmzetTarget(_currentSpvTargetMeta);
    final spvFocusTarget = _resolveFocusTarget(_currentSpvTargetMeta);
    final spvSpecialTarget = _resolveSpecialTarget(_currentSpvTargetMeta);
    final effectiveTarget = spvTarget > 0 ? spvTarget : target;
    final effectiveFocusTarget = spvFocusTarget > 0
        ? spvFocusTarget
        : focusTarget;
    final effectiveSpecialTarget = spvSpecialTarget > 0
        ? spvSpecialTarget
        : specialTarget;

    return {
      'target': effectiveTarget,
      'actual': actual,
      'achievement_pct': effectiveTarget > 0
          ? (actual / effectiveTarget) * 100
          : 0,
      'focus_target': effectiveFocusTarget,
      'focus_actual': focusActual,
      'special_target': effectiveSpecialTarget,
      'special_actual': specialActual,
      'vast_input': vastInput,
      'vast_closing': vastClosing,
      'chip': chip,
    };
  }

  List<Map<String, dynamic>> get _areaSoldTypes {
    final currentSales = _promotors
        .expand((promotor) => promotor.currentSalesRows)
        .toList();
    return _buildTypeRows(currentSales);
  }

  List<Map<String, dynamic>> get _areaDailyRows {
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      for (final row in promotor.dailyRows) {
        final key = '${row['date'] ?? ''}';
        final existing = grouped[key];
        if (existing == null) {
          grouped[key] = {
            'date': row['date'],
            'target_omzet': _toNum(row['target_omzet']),
            'actual_omzet': _toNum(row['actual_omzet']),
            'actual_focus': _toNum(row['actual_focus']),
            'actual_special': _toNum(row['actual_special']),
            'vast_input': _toNum(row['vast_input']),
            'vast_closing': _toNum(row['vast_closing']),
            'chip_units': _toNum(row['chip_units']),
          };
        } else {
          existing['target_omzet'] =
              _toNum(existing['target_omzet']) + _toNum(row['target_omzet']);
          existing['actual_omzet'] =
              _toNum(existing['actual_omzet']) + _toNum(row['actual_omzet']);
          existing['actual_focus'] =
              _toNum(existing['actual_focus']) + _toNum(row['actual_focus']);
          existing['actual_special'] =
              _toNum(existing['actual_special']) +
              _toNum(row['actual_special']);
          existing['vast_input'] =
              _toNum(existing['vast_input']) + _toNum(row['vast_input']);
          existing['vast_closing'] =
              _toNum(existing['vast_closing']) + _toNum(row['vast_closing']);
          existing['chip_units'] =
              _toNum(existing['chip_units']) + _toNum(row['chip_units']);
        }
      }
    }
    final rows = grouped.values.toList()
      ..sort((a, b) => '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}'));
    for (final row in rows) {
      final target = _toNum(row['target_omzet']);
      final actual = _toNum(row['actual_omzet']);
      row['achievement_pct'] = target > 0 ? (actual / target) * 100 : 0;
    }
    return rows;
  }

  List<Map<String, dynamic>> get _areaWeeklyRows {
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      for (final row in promotor.weeklyRows) {
        final key = _weekKey(row);
        final existing = grouped[key];
        if (existing == null) {
          grouped[key] = {
            'week_number': row['week_number'],
            'week_start': row['week_start'],
            'week_end': row['week_end'],
            'actual_omzet': _toNum(row['actual_omzet']),
            'target_omzet': _toNum(row['target_omzet']),
            'actual_focus': _toNum(row['actual_focus']),
            'actual_special': _toNum(row['actual_special']),
            'vast_input': _toNum(row['vast_input']),
            'vast_closing': _toNum(row['vast_closing']),
            'chip_units': _toNum(row['chip_units']),
          };
        } else {
          existing['actual_omzet'] =
              _toNum(existing['actual_omzet']) + _toNum(row['actual_omzet']);
          existing['target_omzet'] =
              _toNum(existing['target_omzet']) + _toNum(row['target_omzet']);
          existing['actual_focus'] =
              _toNum(existing['actual_focus']) + _toNum(row['actual_focus']);
          existing['actual_special'] =
              _toNum(existing['actual_special']) +
              _toNum(row['actual_special']);
          existing['vast_input'] =
              _toNum(existing['vast_input']) + _toNum(row['vast_input']);
          existing['vast_closing'] =
              _toNum(existing['vast_closing']) + _toNum(row['vast_closing']);
          existing['chip_units'] =
              _toNum(existing['chip_units']) + _toNum(row['chip_units']);
        }
      }
    }
    final rows = grouped.values.toList()
      ..sort(
        (a, b) =>
            '${a['week_start'] ?? ''}'.compareTo('${b['week_start'] ?? ''}'),
      );
    for (final row in rows) {
      final target = _toNum(row['target_omzet']);
      final actual = _toNum(row['actual_omzet']);
      row['achievement_pct'] = target > 0 ? (actual / target) * 100 : 0;
    }
    return rows;
  }

  Map<String, List<_SpvPromotorOverview>> get _promotorsBySator {
    final grouped = <String, List<_SpvPromotorOverview>>{};
    for (final promotor in _promotors) {
      grouped
          .putIfAbsent(promotor.satorId, () => <_SpvPromotorOverview>[])
          .add(promotor);
    }
    for (final rows in grouped.values) {
      rows.sort((a, b) {
        final storeCompare = a.storeName.compareTo(b.storeName);
        if (storeCompare != 0) return storeCompare;
        return a.name.compareTo(b.name);
      });
    }
    return grouped;
  }

  List<Map<String, dynamic>> get _satorSummaryRows {
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      final existing = grouped[promotor.satorId];
      if (existing == null) {
        grouped[promotor.satorId] = {
          'sator_id': promotor.satorId,
          'sator_name': promotor.satorName,
          'target': promotor.monthlyTarget,
          'actual': promotor.actualCurrent,
          'focus_target': promotor.focusTargetCurrent,
          'focus_actual': promotor.focusActualCurrent,
          'special_target': promotor.specialTargetCurrent,
          'special_actual': promotor.specialActualCurrent,
          'vast_input': promotor.vastInputCurrent,
          'vast_closing': promotor.vastClosingCurrent,
          'chip': promotor.chipCurrent,
        };
      } else {
        existing['target'] =
            _toNum(existing['target']) + promotor.monthlyTarget;
        existing['actual'] =
            _toNum(existing['actual']) + promotor.actualCurrent;
        existing['focus_target'] =
            _toNum(existing['focus_target']) + promotor.focusTargetCurrent;
        existing['focus_actual'] =
            _toNum(existing['focus_actual']) + promotor.focusActualCurrent;
        existing['special_target'] =
            _toNum(existing['special_target']) + promotor.specialTargetCurrent;
        existing['special_actual'] =
            _toNum(existing['special_actual']) + promotor.specialActualCurrent;
        existing['vast_input'] =
            _toNum(existing['vast_input']) + promotor.vastInputCurrent;
        existing['vast_closing'] =
            _toNum(existing['vast_closing']) + promotor.vastClosingCurrent;
        existing['chip'] = _toNum(existing['chip']) + promotor.chipCurrent;
      }
    }

    final rows = grouped.values.toList();
    for (final row in rows) {
      final target = _toNum(row['target']);
      row['achievement_pct'] = target > 0
          ? (_toNum(row['actual']) / target) * 100
          : 0;
    }
    rows.sort(
      (a, b) =>
          '${a['sator_name'] ?? ''}'.compareTo('${b['sator_name'] ?? ''}'),
    );
    return rows;
  }

  List<Map<String, dynamic>> get _satorDailyRows {
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      final row = promotor.dailyCurrent;
      final existing = grouped[promotor.satorId];
      if (existing == null) {
        grouped[promotor.satorId] = {
          'sator_id': promotor.satorId,
          'sator_name': promotor.satorName,
          'target_omzet': _toNum(row['target_omzet']),
          'actual_omzet': _toNum(row['actual_omzet']),
          'focus': _toNum(row['focus']),
          'special': _toNum(row['special']),
          'vast': _toNum(row['vast']),
          'chip': _toNum(row['chip']),
        };
      } else {
        existing['target_omzet'] =
            _toNum(existing['target_omzet']) + _toNum(row['target_omzet']);
        existing['actual_omzet'] =
            _toNum(existing['actual_omzet']) + _toNum(row['actual_omzet']);
        existing['focus'] = _toNum(existing['focus']) + _toNum(row['focus']);
        existing['special'] =
            _toNum(existing['special']) + _toNum(row['special']);
        existing['vast'] = _toNum(existing['vast']) + _toNum(row['vast']);
        existing['chip'] = _toNum(existing['chip']) + _toNum(row['chip']);
      }
    }
    final rows = grouped.values.toList();
    for (final row in rows) {
      final target = _toNum(row['target_omzet']);
      row['achievement_pct'] = target > 0
          ? (_toNum(row['actual_omzet']) / target) * 100
          : 0;
    }
    rows.sort(
      (a, b) =>
          '${a['sator_name'] ?? ''}'.compareTo('${b['sator_name'] ?? ''}'),
    );
    return rows;
  }

  List<Map<String, dynamic>> get _satorMonthlyRows {
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      final existing = grouped[promotor.satorId];
      if (existing == null) {
        grouped[promotor.satorId] = {
          'sator_id': promotor.satorId,
          'sator_name': promotor.satorName,
          'previous_actual': promotor.previousActual,
          'current_actual': promotor.actualCurrent,
          'previous_focus': promotor.previousFocusActual,
          'current_focus': promotor.focusActualCurrent,
          'previous_special': promotor.previousSpecialActual,
          'current_special': promotor.specialActualCurrent,
          'previous_vast': promotor.previousVastClosing,
          'current_vast': promotor.vastClosingCurrent,
          'previous_chip': promotor.previousChip,
          'current_chip': promotor.chipCurrent,
        };
      } else {
        existing['previous_actual'] =
            _toNum(existing['previous_actual']) + promotor.previousActual;
        existing['current_actual'] =
            _toNum(existing['current_actual']) + promotor.actualCurrent;
        existing['previous_focus'] =
            _toNum(existing['previous_focus']) + promotor.previousFocusActual;
        existing['current_focus'] =
            _toNum(existing['current_focus']) + promotor.focusActualCurrent;
        existing['previous_special'] =
            _toNum(existing['previous_special']) +
            promotor.previousSpecialActual;
        existing['current_special'] =
            _toNum(existing['current_special']) + promotor.specialActualCurrent;
        existing['previous_vast'] =
            _toNum(existing['previous_vast']) + promotor.previousVastClosing;
        existing['current_vast'] =
            _toNum(existing['current_vast']) + promotor.vastClosingCurrent;
        existing['previous_chip'] =
            _toNum(existing['previous_chip']) + promotor.previousChip;
        existing['current_chip'] =
            _toNum(existing['current_chip']) + promotor.chipCurrent;
      }
    }
    final rows = grouped.values.toList()
      ..sort(
        (a, b) =>
            '${a['sator_name'] ?? ''}'.compareTo('${b['sator_name'] ?? ''}'),
      );
    return rows;
  }

  List<Map<String, dynamic>> _satorWeeklyRows(
    Map<String, dynamic>? left,
    Map<String, dynamic>? right,
  ) {
    if (left == null || right == null) return const [];
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      final leftRow = promotor.weekByKey(_leftWeekKey);
      final rightRow = promotor.weekByKey(_rightWeekKey);
      final existing = grouped[promotor.satorId];
      if (existing == null) {
        grouped[promotor.satorId] = {
          'sator_id': promotor.satorId,
          'sator_name': promotor.satorName,
          'left_actual': _toNum(leftRow['actual_omzet']),
          'right_actual': _toNum(rightRow['actual_omzet']),
          'left_focus': _toNum(leftRow['actual_focus']),
          'right_focus': _toNum(rightRow['actual_focus']),
          'left_special': _toNum(leftRow['actual_special']),
          'right_special': _toNum(rightRow['actual_special']),
          'left_vast': _toNum(leftRow['vast_closing']),
          'right_vast': _toNum(rightRow['vast_closing']),
          'left_chip': _toNum(leftRow['chip_units']),
          'right_chip': _toNum(rightRow['chip_units']),
        };
      } else {
        existing['left_actual'] =
            _toNum(existing['left_actual']) + _toNum(leftRow['actual_omzet']);
        existing['right_actual'] =
            _toNum(existing['right_actual']) + _toNum(rightRow['actual_omzet']);
        existing['left_focus'] =
            _toNum(existing['left_focus']) + _toNum(leftRow['actual_focus']);
        existing['right_focus'] =
            _toNum(existing['right_focus']) + _toNum(rightRow['actual_focus']);
        existing['left_special'] =
            _toNum(existing['left_special']) +
            _toNum(leftRow['actual_special']);
        existing['right_special'] =
            _toNum(existing['right_special']) +
            _toNum(rightRow['actual_special']);
        existing['left_vast'] =
            _toNum(existing['left_vast']) + _toNum(leftRow['vast_closing']);
        existing['right_vast'] =
            _toNum(existing['right_vast']) + _toNum(rightRow['vast_closing']);
        existing['left_chip'] =
            _toNum(existing['left_chip']) + _toNum(leftRow['chip_units']);
        existing['right_chip'] =
            _toNum(existing['right_chip']) + _toNum(rightRow['chip_units']);
      }
    }
    final rows = grouped.values.toList()
      ..sort(
        (a, b) =>
            '${a['sator_name'] ?? ''}'.compareTo('${b['sator_name'] ?? ''}'),
      );
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.shellBackground,
      appBar: AppBar(
        backgroundColor: t.shellBackground,
        foregroundColor: t.textPrimary,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Sell Out Insight'),
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
              onRefresh: _loadData,
              color: t.primaryAccent,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 24),
                children: [
                  _buildDateBar(),
                  const SizedBox(height: 10),
                  _buildTabBar(),
                  const SizedBox(height: 10),
                  if (_promotors.isEmpty)
                    _buildEmptyState()
                  else if (_selectedTab == 0)
                    _buildSummaryTab()
                  else if (_selectedTab == 1)
                    _buildDailyTab()
                  else if (_selectedTab == 2)
                    _buildWeeklyTab()
                  else
                    _buildMonthlyTab(),
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
          FilledButton.tonalIcon(
            onPressed: _pickReferenceDate,
            icon: const Icon(Icons.event_rounded, size: 18),
            label: const Text('Tanggal'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    const labels = ['Ringkasan', 'Harian', 'Mingguan', 'Bulanan'];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = _selectedTab == index;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: index == labels.length - 1 ? 0 : 4,
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _selectedTab = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: selected ? t.primaryAccent : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    labels[index],
                    textAlign: TextAlign.center,
                    style: PromotorText.outfit(
                      size: 10.5,
                      weight: FontWeight.w800,
                      color: selected ? Colors.black : t.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Future<void> _pickReferenceDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _referenceDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now(),
      locale: const Locale('id', 'ID'),
    );
    if (selected == null) return;
    setState(() {
      _referenceDate = selected;
      _leftWeekKey = null;
      _rightWeekKey = null;
    });
    await _loadData();
  }

  Widget _buildSummaryTab() {
    final summary = _areaSummary;
    final soldTypes = _areaSoldTypes;
    final topType = soldTypes.isNotEmpty ? soldTypes.first : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeroSummary(summary),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _statTile(
                'Tipe Fokus',
                '${_toNum(summary['focus_actual']).toInt()} / ${_toNum(summary['focus_target']).toInt()}',
                _toneForPct(
                  _toNum(summary['focus_target']) > 0
                      ? (_toNum(summary['focus_actual']) /
                              _toNum(summary['focus_target'])) *
                          100
                      : 0,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statTile(
                'Tipe Khusus',
                '${_toNum(summary['special_actual']).toInt()} / ${_toNum(summary['special_target']).toInt()}',
                _toneForPct(
                  _toNum(summary['special_target']) > 0
                      ? (_toNum(summary['special_actual']) /
                              _toNum(summary['special_target'])) *
                          100
                      : 0,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _statTile(
                'VAST Input',
                '${_toNum(summary['vast_input']).toInt()}',
                t.info,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statTile(
                'VAST Closing',
                '${_toNum(summary['vast_closing']).toInt()}',
                t.success,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _statTile(
                'Chip',
                '${_toNum(summary['chip']).toInt()}',
                t.warning,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle('Semua Tipe Terjual Area'),
        const SizedBox(height: 8),
        if (soldTypes.isEmpty)
          _buildEmptyState(message: 'Belum ada tipe terjual pada periode ini.')
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.surface3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (topType != null)
                  Text(
                    'Tipe terlaris area: ${topType['type_label']} (${_toNum(topType['units']).toInt()} unit)',
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                if (soldTypes.isNotEmpty) ...[
                  if (topType != null) const SizedBox(height: 8),
                  Text(
                    'Semua Tipe Terjual',
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  ...soldTypes.map(_buildSoldTypeRow),
                ],
              ],
            ),
          ),
        const SizedBox(height: 12),
        _sectionTitle('Pencapaian Sator'),
        const SizedBox(height: 8),
        ..._satorSummaryRows.map(_buildSatorSummaryCard),
      ],
    );
  }

  Widget _buildDailyTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Harian Area'),
        const SizedBox(height: 8),
        _buildDailyBoard(_areaDailyRows),
        const SizedBox(height: 12),
        _sectionTitle('Harian per Sator'),
        const SizedBox(height: 8),
        ..._satorDailyRows.map(
          (row) => _buildSatorExpandableCard(
            satorId: '${row['sator_id'] ?? ''}',
            title: '${row['sator_name'] ?? 'Sator'}',
            subtitle:
                'Sell Out: ${_formatMoneyTight(_toNum(row['actual_omzet']))} • Tipe Fokus: ${_toNum(row['focus']).toInt()} • Tipe Khusus: ${_toNum(row['special']).toInt()} • VAST: ${_toNum(row['vast']).toInt()} • Chip: ${_toNum(row['chip']).toInt()}',
            tone: _toneForPct(_toNum(row['achievement_pct'])),
            child: _buildPromotorDailyTable(
              _promotorsBySator['${row['sator_id'] ?? ''}'] ?? const [],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyTab() {
    final weeks = _areaWeeklyRows;
    final left = weeks
        .where((row) => _weekKey(row) == _leftWeekKey)
        .firstOrNull;
    final right = weeks
        .where((row) => _weekKey(row) == _rightWeekKey)
        .firstOrNull;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (weeks.length > 1) _buildWeekPicker(weeks),
        if (weeks.length > 1) const SizedBox(height: 10),
        _sectionTitle('Perbandingan Mingguan Area'),
        const SizedBox(height: 8),
        _buildCompareMatrix(
          leftTitle: left == null ? 'Minggu X' : _formatWeekTitle(left),
          leftSubtitle: left == null ? '-' : _formatWeekRange(left),
          rightTitle: right == null ? 'Minggu Y' : _formatWeekTitle(right),
          rightSubtitle: right == null ? '-' : _formatWeekRange(right),
          rows: [
            _matrixRow(
              'Sell Out',
              _toNum(left?['actual_omzet']),
              _toNum(right?['actual_omzet']),
              currency: true,
            ),
            _matrixRow(
              'Tipe Fokus',
              _toNum(left?['actual_focus']),
              _toNum(right?['actual_focus']),
            ),
            _matrixRow(
              'Tipe Khusus',
              _toNum(left?['actual_special']),
              _toNum(right?['actual_special']),
            ),
            _matrixRow(
              'VAST Input',
              _toNum(left?['vast_input']),
              _toNum(right?['vast_input']),
            ),
            _matrixRow(
              'VAST Closing',
              _toNum(left?['vast_closing']),
              _toNum(right?['vast_closing']),
            ),
            _matrixRow(
              'Chip',
              _toNum(left?['chip_units']),
              _toNum(right?['chip_units']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle('Mingguan per Sator'),
        const SizedBox(height: 8),
        ..._satorWeeklyRows(left, right).map(
          (row) => _buildSatorExpandableCard(
            satorId: '${row['sator_id'] ?? ''}',
            title: '${row['sator_name'] ?? 'Sator'}',
            subtitle:
                'Sell Out: ${_formatMoneyTight(_toNum(row['left_actual']))} → ${_formatMoneyTight(_toNum(row['right_actual']))} • Tipe Fokus: ${_toNum(row['left_focus']).toInt()} → ${_toNum(row['right_focus']).toInt()} • Tipe Khusus: ${_toNum(row['left_special']).toInt()} → ${_toNum(row['right_special']).toInt()} • VAST: ${_toNum(row['left_vast']).toInt()} → ${_toNum(row['right_vast']).toInt()}',
            tone: _compareTone(
              left: _toNum(row['left_actual']),
              right: _toNum(row['right_actual']),
              rightSide: true,
            ),
            child: _buildPromotorWeeklyTable(
              _promotorsBySator['${row['sator_id'] ?? ''}'] ?? const [],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyTab() {
    final summary = _areaSummary;
    final previousTarget = _resolveOmzetTarget(_previousSpvTargetMeta);
    final previousFocusTarget = _resolveFocusTarget(_previousSpvTargetMeta);
    final previousSpecialTarget = _resolveSpecialTarget(_previousSpvTargetMeta);
    final currentTarget = _resolveOmzetTarget(_currentSpvTargetMeta);
    final currentFocusTarget = _resolveFocusTarget(_currentSpvTargetMeta);
    final currentSpecialTarget = _resolveSpecialTarget(_currentSpvTargetMeta);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Perbandingan Bulanan Area'),
        const SizedBox(height: 8),
        _buildCompareMatrix(
          leftTitle: DateFormat('MMMM yyyy', 'id_ID').format(_prevMonthStart),
          leftSubtitle:
              '${DateFormat('d MMM', 'id_ID').format(_prevMonthStart)} - ${DateFormat('d MMM yyyy', 'id_ID').format(_prevMonthEnd)}',
          rightTitle: DateFormat('MMMM yyyy', 'id_ID').format(_monthStart),
          rightSubtitle:
              '${DateFormat('d MMM', 'id_ID').format(_monthStart)} - ${DateFormat('d MMM yyyy', 'id_ID').format(_referenceDate)}',
          rows: [
            _matrixRow(
              'Sell Out',
              _toNum(previousTarget > 0 ? previousTarget : 0),
              _toNum(currentTarget > 0 ? currentTarget : summary['target']),
              currency: true,
              labelOverride: 'Target',
            ),
            _matrixRow(
              'Actual Sell Out',
              _promotors.fold<num>(0, (sum, row) => sum + row.previousActual),
              _toNum(summary['actual']),
              currency: true,
            ),
            _matrixRow(
              'Tipe Fokus',
              _toNum(previousFocusTarget),
              _toNum(
                currentFocusTarget > 0
                    ? currentFocusTarget
                    : summary['focus_target'],
              ),
              labelOverride: 'Target',
            ),
            _matrixRow(
              'Actual Fokus',
              _promotors.fold<num>(
                0,
                (sum, row) => sum + row.previousFocusActual,
              ),
              _toNum(summary['focus_actual']),
            ),
            _matrixRow(
              'Tipe Khusus',
              _toNum(previousSpecialTarget),
              _toNum(
                currentSpecialTarget > 0
                    ? currentSpecialTarget
                    : summary['special_target'],
              ),
              labelOverride: 'Target',
            ),
            _matrixRow(
              'Actual Khusus',
              _promotors.fold<num>(
                0,
                (sum, row) => sum + row.previousSpecialActual,
              ),
              _toNum(summary['special_actual']),
            ),
            _matrixRow(
              'VAST Closing',
              _promotors.fold<num>(
                0,
                (sum, row) => sum + row.previousVastClosing,
              ),
              _toNum(summary['vast_closing']),
            ),
            _matrixRow(
              'Chip',
              _promotors.fold<num>(0, (sum, row) => sum + row.previousChip),
              _toNum(summary['chip']),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _sectionTitle('Bulanan per Sator'),
        const SizedBox(height: 8),
        ..._satorMonthlyRows.map(
          (row) => _buildSatorExpandableCard(
            satorId: '${row['sator_id'] ?? ''}',
            title: '${row['sator_name'] ?? 'Sator'}',
            subtitle:
                'Sell Out: ${_formatMoneyTight(_toNum(row['previous_actual']))} → ${_formatMoneyTight(_toNum(row['current_actual']))} • Tipe Fokus: ${_toNum(row['previous_focus']).toInt()} → ${_toNum(row['current_focus']).toInt()} • Tipe Khusus: ${_toNum(row['previous_special']).toInt()} → ${_toNum(row['current_special']).toInt()} • VAST: ${_toNum(row['previous_vast']).toInt()} → ${_toNum(row['current_vast']).toInt()}',
            tone: _compareTone(
              left: _toNum(row['previous_actual']),
              right: _toNum(row['current_actual']),
              rightSide: true,
            ),
            child: _buildPromotorMonthlyTable(
              _promotorsBySator['${row['sator_id'] ?? ''}'] ?? const [],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroSummary(Map<String, dynamic> summary) {
    final target = _toNum(summary['target']);
    final actual = _toNum(summary['actual']);
    final pct = _toNum(summary['achievement_pct']);
    final gap = math.max(target - actual, 0);
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Sell Out Area',
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
                child: _miniMetric(
                  'Target',
                  _formatMoneyTight(target),
                  t.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniMetric('Gap', _formatMoneyTight(gap), t.warning),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _miniMetric(
                  'Pencapaian',
                  _formatPct(pct),
                  _toneForPct(pct),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSoldTypeRow(Map<String, dynamic> row) {
    final isChip = row['is_chip'] == true;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '${row['type_label'] ?? '-'}',
              style: PromotorText.outfit(
                size: 9.6,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_toNum(row['units']).toInt()}x',
            style: PromotorText.outfit(
              size: 9.6,
              weight: FontWeight.w800,
              color: t.textSecondary,
            ),
          ),
          if (isChip) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: t.warning.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'CHIP',
                style: PromotorText.outfit(
                  size: 7.6,
                  weight: FontWeight.w800,
                  color: t.warning,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _miniMetric(String label, String value, Color tone) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.surface2,
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

  Widget _statTile(String label, String value, Color tone) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: t.surface1,
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

  Widget _buildSatorSummaryCard(Map<String, dynamic> row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${row['sator_name'] ?? 'Sator'}',
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              Text(
                _formatPct(_toNum(row['achievement_pct'])),
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w800,
                  color: _toneForPct(_toNum(row['achievement_pct'])),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Sell Out: ${_formatMoneyTight(_toNum(row['actual']))} / ${_formatMoneyTight(_toNum(row['target']))}',
            style: PromotorText.outfit(
              size: 10.2,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tipe Fokus: ${_toNum(row['focus_actual']).toInt()} • Tipe Khusus: ${_toNum(row['special_actual']).toInt()} • VAST: ${_toNum(row['vast_closing']).toInt()} • Chip: ${_toNum(row['chip']).toInt()}',
            style: PromotorText.outfit(
              size: 9.8,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyBoard(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return _buildEmptyState(message: 'Belum ada data harian.');
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          _tableHeader(const [
            _FlexCol('Tanggal', 18),
            _FlexCol('Sell Out', 22),
            _FlexCol('Persen', 12),
            _FlexCol('Tipe Fokus', 12),
            _FlexCol('Tipe Khusus', 12),
            _FlexCol('VAST', 12),
            _FlexCol('Chip', 12),
          ]),
          const SizedBox(height: 6),
          ...rows.map((row) {
            final date = DateTime.tryParse('${row['date'] ?? ''}');
            return _tableRow(
              const [18, 22, 12, 12, 12, 12, 12],
              [
                Text(
                  date == null
                      ? '-'
                      : DateFormat('d MMM', 'id_ID').format(date),
                ),
                Text(_formatMoneyTight(_toNum(row['actual_omzet']))),
                Text(
                  _formatPct(_toNum(row['achievement_pct'])),
                  style: TextStyle(
                    color: _toneForPct(_toNum(row['achievement_pct'])),
                  ),
                ),
                Text('${_toNum(row['actual_focus']).toInt()}'),
                Text('${_toNum(row['actual_special']).toInt()}'),
                Text('${_toNum(row['vast_closing']).toInt()}'),
                Text('${_toNum(row['chip_units']).toInt()}'),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildWeekPicker(List<Map<String, dynamic>> weeks) {
    return Row(
      children: [
        Expanded(
          child: _weekDropdown(
            label: 'Pilih Minggu X',
            value: _leftWeekKey,
            items: weeks,
            onChanged: (value) => setState(() => _leftWeekKey = value),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _weekDropdown(
            label: 'Pilih Minggu Y',
            value: _rightWeekKey,
            items: weeks,
            onChanged: (value) => setState(() => _rightWeekKey = value),
          ),
        ),
      ],
    );
  }

  Widget _weekDropdown({
    required String label,
    required String? value,
    required List<Map<String, dynamic>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          dropdownColor: t.surface1,
          borderRadius: BorderRadius.circular(12),
          hint: Text(
            label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          items: items
              .map(
                (row) => DropdownMenuItem<String>(
                  value: _weekKey(row),
                  child: Text(
                    '${_formatWeekTitle(row)} • ${_formatWeekRange(row)}',
                    style: PromotorText.outfit(
                      size: 10.2,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildCompareMatrix({
    required String leftTitle,
    required String leftSubtitle,
    required String rightTitle,
    required String rightSubtitle,
    required List<Widget> rows,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          _tableHeader([
            const _FlexCol('Metrik', 28),
            _FlexCol(leftTitle, 24, subtitle: leftSubtitle),
            _FlexCol(rightTitle, 24, subtitle: rightSubtitle),
            const _FlexCol('Selisih', 24),
          ]),
          const SizedBox(height: 8),
          ...rows,
        ],
      ),
    );
  }

  Widget _matrixRow(
    String label,
    num left,
    num right, {
    bool currency = false,
    String? labelOverride,
  }) {
    final delta = right - left;
    final deltaTone = _compareTone(left: left, right: right, rightSide: true);
    String fmt(num value) =>
        currency ? _formatMoneyTight(value) : value.toInt().toString();

    return _tableRow(
      const [28, 24, 24, 24],
      [
        Text(labelOverride ?? label),
        Text(
          fmt(left),
          style: TextStyle(
            color: _compareTone(left: left, right: right, rightSide: false),
          ),
        ),
        Text(
          fmt(right),
          style: TextStyle(
            color: _compareTone(left: left, right: right, rightSide: true),
          ),
        ),
        Text(
          currency ? _formatMoneyTight(delta) : delta.toInt().toString(),
          style: TextStyle(color: deltaTone),
        ),
      ],
    );
  }

  Widget _buildSatorExpandableCard({
    required String satorId,
    required String title,
    required String subtitle,
    required Color tone,
    required Widget child,
  }) {
    final expanded = _expandedSatorId == satorId;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () =>
                setState(() => _expandedSatorId = expanded ? null : satorId),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
              child: Row(
                children: [
                  Expanded(
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
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: PromotorText.outfit(
                            size: 9.8,
                            weight: FontWeight.w700,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    expanded
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                    color: tone,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: child,
            ),
        ],
      ),
    );
  }

  Widget _buildPromotorDailyTable(List<_SpvPromotorOverview> rows) {
    if (rows.isEmpty) return _buildEmptyState(message: 'Belum ada promotor.');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          _tableHeader(const [
            _FlexCol('Promotor', 24),
            _FlexCol('Sell Out', 20),
            _FlexCol('Persen', 12),
            _FlexCol('Tipe Fokus', 12),
            _FlexCol('Tipe Khusus', 12),
            _FlexCol('VAST', 10),
            _FlexCol('Chip', 10),
          ]),
          const SizedBox(height: 6),
          ...rows.map((promotor) {
            final daily = promotor.dailyCurrent;
            return _tableRow(
              const [24, 20, 12, 12, 12, 10, 10],
              [
                Text(promotor.name),
                Text(_formatMoneyTight(_toNum(daily['actual_omzet']))),
                Text(
                  _formatPct(_toNum(daily['achievement_pct'])),
                  style: TextStyle(
                    color: _toneForPct(_toNum(daily['achievement_pct'])),
                  ),
                ),
                Text('${_toNum(daily['focus']).toInt()}'),
                Text('${_toNum(daily['special']).toInt()}'),
                Text('${_toNum(daily['vast']).toInt()}'),
                Text('${_toNum(daily['chip']).toInt()}'),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPromotorWeeklyTable(List<_SpvPromotorOverview> rows) {
    if (rows.isEmpty) return _buildEmptyState(message: 'Belum ada promotor.');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          _tableHeader(const [
            _FlexCol('Promotor', 24),
            _FlexCol('Sell Out', 22),
            _FlexCol('Tipe Fokus', 14),
            _FlexCol('Tipe Khusus', 14),
            _FlexCol('VAST', 14),
            _FlexCol('Chip', 12),
          ]),
          const SizedBox(height: 6),
          ...rows.map((promotor) {
            final left = promotor.weekByKey(_leftWeekKey);
            final right = promotor.weekByKey(_rightWeekKey);
            return _tableRow(
              const [24, 22, 14, 14, 14, 12],
              [
                Text(promotor.name),
                Text(
                  '${_formatMoneyTight(_toNum(left['actual_omzet']))} → ${_formatMoneyTight(_toNum(right['actual_omzet']))}',
                ),
                Text(
                  '${_toNum(left['actual_focus']).toInt()} → ${_toNum(right['actual_focus']).toInt()}',
                ),
                Text(
                  '${_toNum(left['actual_special']).toInt()} → ${_toNum(right['actual_special']).toInt()}',
                ),
                Text(
                  '${_toNum(left['vast_closing']).toInt()} → ${_toNum(right['vast_closing']).toInt()}',
                ),
                Text(
                  '${_toNum(left['chip_units']).toInt()} → ${_toNum(right['chip_units']).toInt()}',
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPromotorMonthlyTable(List<_SpvPromotorOverview> rows) {
    if (rows.isEmpty) return _buildEmptyState(message: 'Belum ada promotor.');
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          _tableHeader(const [
            _FlexCol('Promotor', 24),
            _FlexCol('Sell Out', 22),
            _FlexCol('Tipe Fokus', 14),
            _FlexCol('Tipe Khusus', 14),
            _FlexCol('VAST', 14),
            _FlexCol('Chip', 12),
          ]),
          const SizedBox(height: 6),
          ...rows.map((promotor) {
            return _tableRow(
              const [24, 22, 14, 14, 14, 12],
              [
                Text(promotor.name),
                Text(
                  '${_formatMoneyTight(promotor.previousActual)} → ${_formatMoneyTight(promotor.actualCurrent)}',
                ),
                Text(
                  '${promotor.previousFocusActual.toInt()} → ${promotor.focusActualCurrent.toInt()}',
                ),
                Text(
                  '${promotor.previousSpecialActual.toInt()} → ${promotor.specialActualCurrent.toInt()}',
                ),
                Text(
                  '${promotor.previousVastClosing} → ${promotor.vastClosingCurrent}',
                ),
                Text('${promotor.previousChip} → ${promotor.chipCurrent}'),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _tableHeader(List<_FlexCol> cols) {
    return Row(
      children: cols
          .map(
            (col) => Expanded(
              flex: col.flex,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      col.label,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 9.2,
                        weight: FontWeight.w800,
                        color: t.textMuted,
                      ),
                    ),
                    if (col.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        col.subtitle!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PromotorText.outfit(
                          size: 8.2,
                          weight: FontWeight.w700,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _tableRow(List<int> flexes, List<Widget> cells) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: t.surface3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(cells.length, (index) {
          return Expanded(
            flex: flexes[index],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: DefaultTextStyle(
                style: PromotorText.outfit(
                  size: 9.5,
                  weight: FontWeight.w700,
                  color: t.textPrimary,
                ),
                child: cells[index],
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _sectionTitle(String text) {
    return Text(
      text,
      style: PromotorText.outfit(
        size: 11,
        weight: FontWeight.w800,
        color: t.textPrimary,
      ),
    );
  }

  Widget _buildEmptyState({String? message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        message ?? 'Belum ada data achievement untuk periode ini.',
        style: PromotorText.outfit(
          size: 10,
          weight: FontWeight.w700,
          color: t.textMuted,
        ),
      ),
    );
  }
}

class _FlexCol {
  const _FlexCol(this.label, this.flex, {this.subtitle});

  final String label;
  final int flex;
  final String? subtitle;
}

class _SpvPromotorOverview {
  _SpvPromotorOverview({
    required this.id,
    required this.name,
    required this.satorId,
    required this.satorName,
    required this.storeName,
    required this.referenceDate,
    required this.currentInsight,
    required this.previousInsight,
    required this.currentTargetMeta,
    required this.previousTargetMeta,
    required this.salesRows,
    required this.vastRows,
  });

  final String id;
  final String name;
  final String satorId;
  final String satorName;
  final String storeName;
  final DateTime referenceDate;
  final Map<String, dynamic> currentInsight;
  final Map<String, dynamic> previousInsight;
  final Map<String, dynamic> currentTargetMeta;
  final Map<String, dynamic> previousTargetMeta;
  final List<Map<String, dynamic>> salesRows;
  final List<Map<String, dynamic>> vastRows;

  DateTime get monthStart =>
      DateTime(referenceDate.year, referenceDate.month, 1);
  DateTime get prevMonthStart =>
      DateTime(referenceDate.year, referenceDate.month - 1, 1);
  DateTime get prevMonthEnd {
    final endOfPrevMonth = DateTime(referenceDate.year, referenceDate.month, 0);
    return DateTime(
      endOfPrevMonth.year,
      endOfPrevMonth.month,
      math.min(endOfPrevMonth.day, referenceDate.day),
    );
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('$value') ?? 0;
  }

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

  num get monthlyTarget {
    final targetOmzet = _toNum(currentTargetMeta['target_omzet']);
    if (targetOmzet > 0) return targetOmzet;
    return _toNum(currentTargetMeta['target_sell_out']);
  }

  num get actualCurrent =>
      _toNum(_asMap(currentInsight['summary'])['actual_total']);
  num get previousActual =>
      _toNum(_asMap(previousInsight['summary'])['actual_total']);

  num get focusTargetCurrent {
    final focusTotal = _toNum(currentTargetMeta['target_fokus_total']);
    if (focusTotal > 0) return focusTotal;
    return _sumDetailValues(currentTargetMeta['target_fokus_detail']) +
        _sumDetailValues(currentTargetMeta['target_special_detail']);
  }

  num get specialTargetCurrent {
    final specialTotal = _toNum(currentTargetMeta['target_special']);
    if (specialTotal > 0) return specialTotal;
    return _sumDetailValues(currentTargetMeta['target_special_detail']);
  }

  num get focusActualCurrent =>
      _toNum(_asMap(currentInsight['summary'])['focus_units_total']);
  num get specialActualCurrent =>
      _toNum(_asMap(currentInsight['summary'])['special_units_total']);
  num get previousFocusActual =>
      _toNum(_asMap(previousInsight['summary'])['focus_units_total']);
  num get previousSpecialActual =>
      _toNum(_asMap(previousInsight['summary'])['special_units_total']);

  List<Map<String, dynamic>> get currentSalesRows => salesRows.where((row) {
    final date = DateTime.tryParse('${row['transaction_date'] ?? ''}');
    return date != null &&
        !date.isBefore(monthStart) &&
        !date.isAfter(referenceDate);
  }).toList();

  int get chipCurrent => salesRows.where((row) {
    final date = DateTime.tryParse('${row['transaction_date'] ?? ''}');
    return row['is_chip_sale'] == true &&
        date != null &&
        !date.isBefore(monthStart) &&
        !date.isAfter(referenceDate);
  }).length;

  int get previousChip => salesRows.where((row) {
    final date = DateTime.tryParse('${row['transaction_date'] ?? ''}');
    return row['is_chip_sale'] == true &&
        date != null &&
        !date.isBefore(prevMonthStart) &&
        !date.isAfter(prevMonthEnd);
  }).length;

  int get vastInputCurrent => vastRows.where((row) {
    final date = DateTime.tryParse('${row['application_date'] ?? ''}');
    return date != null &&
        !date.isBefore(monthStart) &&
        !date.isAfter(referenceDate);
  }).length;

  int get vastClosingCurrent => vastRows.where((row) {
    final date = DateTime.tryParse('${row['application_date'] ?? ''}');
    return date != null &&
        !date.isBefore(monthStart) &&
        !date.isAfter(referenceDate) &&
        _isClosingVast(row);
  }).length;

  int get previousVastClosing => vastRows.where((row) {
    final date = DateTime.tryParse('${row['application_date'] ?? ''}');
    return date != null &&
        !date.isBefore(prevMonthStart) &&
        !date.isAfter(prevMonthEnd) &&
        _isClosingVast(row);
  }).length;

  List<Map<String, dynamic>> get dailyRows {
    final daily = _asList(currentInsight['daily_trend']);
    return daily.map((row) {
      final dateKey = '${row['date'] ?? ''}';
      final chip = salesRows.where((sale) {
        final date = DateTime.tryParse('${sale['transaction_date'] ?? ''}');
        return sale['is_chip_sale'] == true &&
            date != null &&
            DateFormat('yyyy-MM-dd').format(date) == dateKey;
      }).length;
      final vastInput = vastRows.where((item) {
        final date = DateTime.tryParse('${item['application_date'] ?? ''}');
        return date != null && DateFormat('yyyy-MM-dd').format(date) == dateKey;
      }).length;
      final vastClosing = vastRows.where((item) {
        final date = DateTime.tryParse('${item['application_date'] ?? ''}');
        return date != null &&
            DateFormat('yyyy-MM-dd').format(date) == dateKey &&
            _isClosingVast(item);
      }).length;
      final target = _toNum(row['target_all']);
      final actual = _toNum(row['all_actual']);
      return {
        'date': dateKey,
        'target_omzet': target,
        'actual_omzet': actual,
        'achievement_pct': target > 0 ? (actual / target) * 100 : 0,
        'actual_focus': _toNum(row['focus_units']),
        'actual_special': _toNum(row['special_units']),
        'vast_input': vastInput,
        'vast_closing': vastClosing,
        'chip_units': chip,
      };
    }).toList();
  }

  Map<String, dynamic> get dailyCurrent {
    final dateKey = DateFormat('yyyy-MM-dd').format(referenceDate);
    Map<String, dynamic> row = const {};
    for (final item in dailyRows) {
      if ('${item['date'] ?? ''}' == dateKey) {
        row = item;
        break;
      }
    }
    return {
      'target_omzet': _toNum(row['target_omzet']),
      'actual_omzet': _toNum(row['actual_omzet']),
      'achievement_pct': _toNum(row['achievement_pct']),
      'focus': _toNum(row['actual_focus']),
      'special': _toNum(row['actual_special']),
      'vast': _toNum(row['vast_closing']),
      'chip': _toNum(row['chip_units']),
    };
  }

  List<Map<String, dynamic>> get weeklyRows {
    return _asList(currentInsight['weekly_details']).map((row) {
      final weekStart = DateTime.tryParse('${row['week_start'] ?? ''}');
      final weekEnd = DateTime.tryParse('${row['week_end'] ?? ''}');
      final chip = salesRows.where((sale) {
        final date = DateTime.tryParse('${sale['transaction_date'] ?? ''}');
        return sale['is_chip_sale'] == true &&
            date != null &&
            weekStart != null &&
            weekEnd != null &&
            !date.isBefore(weekStart) &&
            !date.isAfter(weekEnd);
      }).length;
      final vastInput = vastRows.where((item) {
        final date = DateTime.tryParse('${item['application_date'] ?? ''}');
        return date != null &&
            weekStart != null &&
            weekEnd != null &&
            !date.isBefore(weekStart) &&
            !date.isAfter(weekEnd);
      }).length;
      final vastClosing = vastRows.where((item) {
        final date = DateTime.tryParse('${item['application_date'] ?? ''}');
        return date != null &&
            weekStart != null &&
            weekEnd != null &&
            !date.isBefore(weekStart) &&
            !date.isAfter(weekEnd) &&
            _isClosingVast(item);
      }).length;
      return {
        ...row,
        'actual_omzet': _toNum(row['actual']),
        'target_omzet': _toNum(row['target']),
        'actual_focus': _toNum(row['focus_units']),
        'actual_special': _toNum(row['special_units']),
        'vast_input': vastInput,
        'vast_closing': vastClosing,
        'chip_units': chip,
      };
    }).toList();
  }

  Map<String, dynamic> weekByKey(String? key) {
    if (key == null) return const {};
    for (final row in weeklyRows) {
      if ('${row['week_number'] ?? ''}-${row['week_start'] ?? ''}' == key) {
        return row;
      }
    }
    return const {};
  }
}
