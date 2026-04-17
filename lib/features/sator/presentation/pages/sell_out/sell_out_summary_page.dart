import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../promotor/presentation/pages/sellout_insight_page.dart';
import '../../../../../ui/foundation/field_theme_extensions.dart';
import '../../../../../ui/promotor/promotor.dart';

class SellOutSummaryPage extends StatefulWidget {
  const SellOutSummaryPage({super.key});

  @override
  State<SellOutSummaryPage> createState() => _SellOutSummaryPageState();
}

class _SellOutSummaryPageState extends State<SellOutSummaryPage> {
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
  List<_SatorPromotorOverview> _promotors = const [];
  Map<String, String> _variantLabelById = const <String, String>{};
  String? _leftWeekKey;
  String? _rightWeekKey;
  String _headerFullName = '';

  FieldThemeTokens get t => context.fieldTokens;
  DateTime get _monthStart =>
      DateTime(_referenceDate.year, _referenceDate.month, 1);
  DateTime get _prevMonthStart =>
      DateTime(_referenceDate.year, _referenceDate.month - 1, 1);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final satorId = _supabase.auth.currentUser?.id;
    if (satorId == null) return;
    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      await _loadDataServerSnapshot(satorId);
    } catch (e) {
      debugPrint('SellOutSummary: load failed. $e');
      if (!mounted) return;
      setState(() {
        _promotors = const [];
        _variantLabelById = const <String, String>{};
        _headerFullName = '';
        _loading = false;
      });
    }
  }

  Future<Map<String, String>> _fetchVariantLabels(
    List<Map<String, dynamic>> salesRows,
  ) async {
    final variantIds = salesRows
        .map((row) => '${row['variant_id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (variantIds.isEmpty) return const <String, String>{};

    final variantRows = _asList(
      await _supabase
          .from('product_variants')
          .select('id, ram_rom, color, products!left(model_name)')
          .inFilter('id', variantIds),
    );
    final variantLabelById = <String, String>{};
    for (final row in variantRows) {
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final product = _asMap(row['products']);
      final model = '${product['model_name'] ?? ''}'.trim();
      final ramRom = '${row['ram_rom'] ?? ''}'.trim();
      final color = '${row['color'] ?? ''}'.trim();
      final label = [model, ramRom, color].where((part) => part.isNotEmpty).join(' ');
      if (label.isNotEmpty) {
        variantLabelById[id] = label;
      }
    }
    return variantLabelById;
  }

  Future<void> _loadDataServerSnapshot(String satorId) async {
    final snapshotRaw = await _supabase.rpc(
      'get_sator_sellout_insight_snapshot',
      params: {
        'p_sator_id': satorId,
        'p_reference_date': _fmtDate(_referenceDate),
      },
    );
    if (snapshotRaw is! Map) {
      throw Exception('Snapshot payload invalid');
    }
    final snapshot = _asMap(snapshotRaw);
    final selfProfile = _asMap(snapshot['profile']);
    final promotorRows = _asList(snapshot['promotors']);

    final built = <_SatorPromotorOverview>[];
    final allSales = <Map<String, dynamic>>[];
    for (final row in promotorRows) {
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      final salesRows = _asList(row['sales_rows']);
      final vastRows = _asList(row['vast_rows']);
      allSales.addAll(salesRows);
      built.add(
        _SatorPromotorOverview(
          id: id,
          name: '${row['name'] ?? 'Promotor'}',
          storeName: '${row['store_name'] ?? 'Belum ada toko'}',
          referenceDate: _referenceDate,
          currentInsight: _asMap(row['current_insight']),
          previousInsight: _asMap(row['previous_insight']),
          currentTargetMeta: _asMap(row['current_target_meta']),
          previousTargetMeta: _asMap(row['previous_target_meta']),
          salesRows: salesRows,
          vastRows: vastRows,
        ),
      );
    }
    final variantLabelById = await _fetchVariantLabels(allSales);

    if (!mounted) return;
    setState(() {
      _promotors = built;
      _variantLabelById = variantLabelById;
      _headerFullName = _displayName(selfProfile, fallback: 'Sator');
      _loading = false;
    });
    _ensureWeekSelection();
  }

  String _displayName(Map<String, dynamic> row, {required String fallback}) {
    final fullName = '${row['full_name'] ?? ''}'.trim();
    if (fullName.isNotEmpty) return fullName;
    final nickname = '${row['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    return fallback;
  }

  void _ensureWeekSelection() {
    final weeks = _teamWeeklyRows;
    if (weeks.isEmpty) return;
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

  String _formatMoney(num value) => _money.format(value);
  String _formatMoneyTight(num value) => _moneyCompact.format(value);
  String _formatPct(num value) => '${value.toStringAsFixed(1)}%';
  String _formatWeekTitle(Map<String, dynamic> row) =>
      'Minggu ${row['week_number'] ?? '-'}';
  String _formatWeekRange(Map<String, dynamic> row) {
    final start = DateTime.tryParse('${row['week_start'] ?? ''}');
    final end = DateTime.tryParse('${row['week_end'] ?? ''}');
    if (start == null || end == null) return '${row['week_label'] ?? '-'}';
    return '${DateFormat('d MMM', 'id_ID').format(start)} - ${DateFormat('d MMM', 'id_ID').format(end)}';
  }

  String _typeLabelFromSale(Map<String, dynamic> row) {
    final variantId = '${row['variant_id'] ?? ''}'.trim();
    if (variantId.isNotEmpty) {
      final mappedLabel = _variantLabelById[variantId];
      if (mappedLabel != null && mappedLabel.isNotEmpty) {
        return mappedLabel;
      }
    }
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
    if (rightSide) {
      return right > left ? t.success : t.danger;
    }
    return left > right ? t.success : t.danger;
  }

  String _weekKey(Map<String, dynamic> row) =>
      '${row['week_number'] ?? ''}-${row['week_start'] ?? ''}';

  List<Map<String, dynamic>> get _teamWeeklyRows {
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      for (final row in promotor.weeklyRows) {
        final key = _weekKey(row);
        final existing = grouped[key];
        if (existing == null) {
          grouped[key] = {
            'week_number': row['week_number'],
            'week_label': row['week_label'],
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
              _toNum(existing['actual_special']) + _toNum(row['actual_special']);
          existing['vast_input'] =
              _toNum(existing['vast_input']) + _toNum(row['vast_input']);
          existing['vast_closing'] =
              _toNum(existing['vast_closing']) + _toNum(row['vast_closing']);
          existing['chip_units'] =
              _toNum(existing['chip_units']) + _toNum(row['chip_units']);
        }
      }
    }
    final rows = grouped.values.toList();
    rows.sort((a, b) => '${a['week_start'] ?? ''}'.compareTo('${b['week_start'] ?? ''}'));
    for (final row in rows) {
      final target = _toNum(row['target_omzet']);
      final actual = _toNum(row['actual_omzet']);
      row['achievement_pct'] = target > 0 ? (actual / target) * 100 : 0;
    }
    return rows;
  }

  Map<String, dynamic> get _teamSummary {
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
    return {
      'target': target,
      'actual': actual,
      'achievement_pct': target > 0 ? (actual / target) * 100 : 0,
      'focus_target': focusTarget,
      'focus_actual': focusActual,
      'special_target': specialTarget,
      'special_actual': specialActual,
      'vast_input': vastInput,
      'vast_closing': vastClosing,
      'chip': chip,
    };
  }

  List<Map<String, dynamic>> get _teamSoldTypes {
    final currentSales = _promotors
        .expand((promotor) => promotor.currentSalesRows)
        .toList();
    return _buildTypeRows(currentSales);
  }

  List<Map<String, dynamic>> get _teamDailyRows {
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
              _toNum(existing['actual_special']) + _toNum(row['actual_special']);
          existing['vast_input'] =
              _toNum(existing['vast_input']) + _toNum(row['vast_input']);
          existing['vast_closing'] =
              _toNum(existing['vast_closing']) + _toNum(row['vast_closing']);
          existing['chip_units'] =
              _toNum(existing['chip_units']) + _toNum(row['chip_units']);
        }
      }
    }
    final rows = grouped.values.toList();
    rows.sort(
      (a, b) => '${a['date'] ?? ''}'.compareTo('${b['date'] ?? ''}'),
    );
    for (final row in rows) {
      final target = _toNum(row['target_omzet']);
      final actual = _toNum(row['actual_omzet']);
      row['achievement_pct'] = target > 0 ? (actual / target) * 100 : 0;
    }
    return rows;
  }

  List<Map<String, dynamic>> get _storeRows {
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      final existing = grouped[promotor.storeName];
      if (existing == null) {
        grouped[promotor.storeName] = {
          'store_name': promotor.storeName,
          'promotor_count': 1,
          'target': promotor.monthlyTarget,
          'actual': promotor.actualCurrent,
          'focus': promotor.focusActualCurrent,
          'special': promotor.specialActualCurrent,
          'vast': promotor.vastClosingCurrent,
          'chip': promotor.chipCurrent,
          'achievement_pct': promotor.monthlyPct,
        };
      } else {
        existing['promotor_count'] = _toNum(existing['promotor_count']).toInt() + 1;
        existing['target'] = _toNum(existing['target']) + promotor.monthlyTarget;
        existing['actual'] = _toNum(existing['actual']) + promotor.actualCurrent;
        existing['focus'] = _toNum(existing['focus']) + promotor.focusActualCurrent;
        existing['special'] =
            _toNum(existing['special']) + promotor.specialActualCurrent;
        existing['vast'] = _toNum(existing['vast']) + promotor.vastClosingCurrent;
        existing['chip'] = _toNum(existing['chip']) + promotor.chipCurrent;
        final target = _toNum(existing['target']);
        final actual = _toNum(existing['actual']);
        existing['achievement_pct'] = target > 0 ? (actual / target) * 100 : 0;
      }
    }
    final rows = grouped.values.toList();
    rows.sort((a, b) {
      final storeCompare = '${a['store_name'] ?? ''}'.compareTo(
        '${b['store_name'] ?? ''}',
      );
      if (storeCompare != 0) return storeCompare;
      return _toNum(b['actual']).compareTo(_toNum(a['actual']));
    });
    return rows;
  }

  List<Map<String, dynamic>> get _storeDailyRows {
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      final row = promotor.dailyCurrent;
      final existing = grouped[promotor.storeName];
      if (existing == null) {
        grouped[promotor.storeName] = {
          'store_name': promotor.storeName,
          'promotor_count': 1,
          'target_omzet': _toNum(row['target_omzet']),
          'actual_omzet': _toNum(row['actual_omzet']),
          'focus': _toNum(row['focus']),
          'vast': _toNum(row['vast']),
          'chip': _toNum(row['chip']),
        };
      } else {
        existing['promotor_count'] = _toNum(existing['promotor_count']).toInt() + 1;
        existing['target_omzet'] =
            _toNum(existing['target_omzet']) + _toNum(row['target_omzet']);
        existing['actual_omzet'] =
            _toNum(existing['actual_omzet']) + _toNum(row['actual_omzet']);
        existing['focus'] = _toNum(existing['focus']) + _toNum(row['focus']);
        existing['vast'] = _toNum(existing['vast']) + _toNum(row['vast']);
        existing['chip'] = _toNum(existing['chip']) + _toNum(row['chip']);
      }
    }
    final rows = grouped.values.toList();
    for (final row in rows) {
      final target = _toNum(row['target_omzet']);
      final actual = _toNum(row['actual_omzet']);
      row['achievement_pct'] = target > 0 ? (actual / target) * 100 : 0;
    }
    rows.sort((a, b) => '${a['store_name'] ?? ''}'.compareTo('${b['store_name'] ?? ''}'));
    return rows;
  }

  List<Map<String, dynamic>> _storeWeeklyRows(
    Map<String, dynamic>? left,
    Map<String, dynamic>? right,
  ) {
    if (left == null || right == null) return const [];
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      final leftRow = promotor.weekByKey(_leftWeekKey);
      final rightRow = promotor.weekByKey(_rightWeekKey);
      final existing = grouped[promotor.storeName];
      if (existing == null) {
        grouped[promotor.storeName] = {
          'store_name': promotor.storeName,
          'left_actual': _toNum(leftRow['actual_omzet']),
          'right_actual': _toNum(rightRow['actual_omzet']),
          'left_focus': _toNum(leftRow['actual_focus']),
          'right_focus': _toNum(rightRow['actual_focus']),
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
    final rows = grouped.values.toList();
    rows.sort((a, b) => '${a['store_name'] ?? ''}'.compareTo('${b['store_name'] ?? ''}'));
    return rows;
  }

  List<Map<String, dynamic>> get _storeMonthlyRows {
    final grouped = <String, Map<String, dynamic>>{};
    for (final promotor in _promotors) {
      final existing = grouped[promotor.storeName];
      if (existing == null) {
        grouped[promotor.storeName] = {
          'store_name': promotor.storeName,
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
            _toNum(existing['previous_special']) + promotor.previousSpecialActual;
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
    final rows = grouped.values.toList();
    rows.sort((a, b) => '${a['store_name'] ?? ''}'.compareTo('${b['store_name'] ?? ''}'));
    return rows;
  }

  Map<String, List<_SatorPromotorOverview>> get _promotorsByStore {
    final grouped = <String, List<_SatorPromotorOverview>>{};
    for (final promotor in _promotors) {
      grouped.putIfAbsent(
        promotor.storeName,
        () => <_SatorPromotorOverview>[],
      ).add(promotor);
    }
    for (final rows in grouped.values) {
      rows.sort((a, b) => a.name.compareTo(b.name));
    }
    return grouped;
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
                  if (_selectedTab == 0) ...[
                    _buildSummaryTab(),
                  ] else if (_selectedTab == 1) ...[
                    _buildDailyTab(),
                  ] else if (_selectedTab == 2) ...[
                    _buildWeeklyTab(),
                  ] else ...[
                    _buildMonthlyTab(),
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
            onTap: _pickDate,
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

  Widget _buildTabBar() {
    final labels = const ['Ringkasan', 'Harian', 'Mingguan', 'Bulanan'];
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _referenceDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() => _referenceDate = picked);
    await _loadData();
  }

  Widget _buildSummaryTab() {
    final summary = _teamSummary;
    final soldTypes = _teamSoldTypes;
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
        if (topType != null || soldTypes.isNotEmpty) ...[
          const SizedBox(height: 10),
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
                    'Tipe terlaris tim: ${topType['type_label']} (${_toNum(topType['units']).toInt()} unit)',
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
        ],
      ],
    );
  }

  Widget _buildDailyTab() {
    final teamRows = _teamDailyRows.reversed.toList();
    final groupedPromotors = _promotorsByStore;
    final dailyMap = {
      for (final row in _storeDailyRows) '${row['store_name'] ?? ''}': row,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Harian Tim'),
        const SizedBox(height: 8),
        if (teamRows.isEmpty)
          _emptyCard('Belum ada data harian.')
        else ...[
          _teamDailyHeader(),
          const SizedBox(height: 4),
          ...teamRows.map(_buildTeamDailyRow),
        ],
        const SizedBox(height: 10),
        _sectionTitle(
          'Per Toko',
          subtitle: 'Klik toko untuk lihat pencapaian harian promotor di dalamnya.',
        ),
        const SizedBox(height: 8),
        ..._storeRows.map(
          (row) => _buildStoreAccordionRow(
            title: '${row['store_name'] ?? '-'}',
            summaryText:
                'Sell Out: ${_formatMoneyTight(_toNum((dailyMap['${row['store_name'] ?? ''}'] ?? const {})['actual_omzet']))}',
            achievementPct:
                _toNum((dailyMap['${row['store_name'] ?? ''}'] ?? const {})['achievement_pct']),
            detailLines: [
              'Sell Out: ${_formatMoneyTight(_toNum((dailyMap['${row['store_name'] ?? ''}'] ?? const {})['actual_omzet']))} • Pencapaian: ${_formatPct(_toNum((dailyMap['${row['store_name'] ?? ''}'] ?? const {})['achievement_pct']))}',
              'Tipe Fokus: ${_toNum((dailyMap['${row['store_name'] ?? ''}'] ?? const {})['focus']).toInt()} • VAST: ${_toNum((dailyMap['${row['store_name'] ?? ''}'] ?? const {})['vast']).toInt()} • Chip: ${_toNum((dailyMap['${row['store_name'] ?? ''}'] ?? const {})['chip']).toInt()}',
            ],
            promotors:
                groupedPromotors['${row['store_name'] ?? ''}'] ?? const [],
            promotorMode: _PromotorRowMode.daily,
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyTab() {
    final weeks = _teamWeeklyRows;
    final left = weeks.where((row) => _weekKey(row) == _leftWeekKey).firstOrNull;
    final right = weeks.where((row) => _weekKey(row) == _rightWeekKey).firstOrNull;
    final groupedPromotors = _promotorsByStore;
    final weeklyMap = {
      for (final row in _storeWeeklyRows(left, right)) '${row['store_name'] ?? ''}': row,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (weeks.isEmpty)
          _emptyCard('Belum ada data mingguan.')
        else ...[
          Row(
            children: [
              Expanded(
                child: _weekSelector(
                  value: _leftWeekKey,
                  label: 'Pilih Minggu X',
                  rows: weeks,
                  onChanged: (value) => setState(() => _leftWeekKey = value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _weekSelector(
                  value: _rightWeekKey,
                  label: 'Pilih Minggu Y',
                  rows: weeks,
                  onChanged: (value) => setState(() => _rightWeekKey = value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildWeeklyMatrix(left, right),
          const SizedBox(height: 10),
          _sectionTitle(
            'Per Toko',
            subtitle: 'Klik toko untuk lihat perbandingan mingguan promotor di dalamnya.',
          ),
          const SizedBox(height: 8),
          ..._storeRows.map((row) {
            final weekly = weeklyMap['${row['store_name'] ?? ''}'] ?? const <String, dynamic>{};
            return _buildStoreAccordionRow(
              title: '${row['store_name'] ?? '-'}',
              summaryText:
                  'Sell Out: ${_formatMoneyTight(_toNum(weekly['left_actual']))} → ${_formatMoneyTight(_toNum(weekly['right_actual']))}',
              achievementPct: _toNum(row['achievement_pct']),
              detailLines: [
                'Sell Out: ${_formatMoneyTight(_toNum(weekly['left_actual']))} → ${_formatMoneyTight(_toNum(weekly['right_actual']))}',
                'Tipe Fokus: ${_toNum(weekly['left_focus']).toInt()} → ${_toNum(weekly['right_focus']).toInt()} • VAST: ${_toNum(weekly['left_vast']).toInt()} → ${_toNum(weekly['right_vast']).toInt()} • Chip: ${_toNum(weekly['left_chip']).toInt()} → ${_toNum(weekly['right_chip']).toInt()}',
              ],
              promotors: groupedPromotors['${row['store_name'] ?? ''}'] ?? const [],
              promotorMode: _PromotorRowMode.weekly,
            );
          }),
        ],
      ],
    );
  }

  Widget _buildMonthlyTab() {
    final teamCurrent = _teamSummary;
    final groupedPromotors = _promotorsByStore;
    final monthlyMap = {
      for (final row in _storeMonthlyRows) '${row['store_name'] ?? ''}': row,
    };
    num prevTarget = 0;
    num prevActual = 0;
    num prevFocus = 0;
    num prevSpecial = 0;
    num prevVast = 0;
    num prevChip = 0;
    for (final promotor in _promotors) {
      prevTarget += promotor.previousMonthlyTarget;
      prevActual += promotor.previousActual;
      prevFocus += promotor.previousFocusActual;
      prevSpecial += promotor.previousSpecialActual;
      prevVast += promotor.previousVastClosing;
      prevChip += promotor.previousChip;
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildMonthlyMatrix(
          previousLabel: DateFormat('MMMM yyyy', 'id_ID').format(_prevMonthStart),
          currentLabel: DateFormat('MMMM yyyy', 'id_ID').format(_monthStart),
          previous: {
            'target': prevTarget,
            'actual': prevActual,
            'focus': prevFocus,
            'special': prevSpecial,
            'vast': prevVast,
            'chip': prevChip,
          },
          current: {
            'target': _toNum(teamCurrent['target']),
            'actual': _toNum(teamCurrent['actual']),
            'focus': _toNum(teamCurrent['focus_actual']),
            'special': _toNum(teamCurrent['special_actual']),
            'vast': _toNum(teamCurrent['vast_closing']),
            'chip': _toNum(teamCurrent['chip']),
          },
        ),
        const SizedBox(height: 10),
        _sectionTitle(
          'Per Toko',
          subtitle: 'Klik toko untuk lihat perbandingan bulanan promotor di dalamnya.',
        ),
        const SizedBox(height: 8),
        ..._storeRows.map((row) {
          final monthly = monthlyMap['${row['store_name'] ?? ''}'] ?? const <String, dynamic>{};
          return _buildStoreAccordionRow(
            title: '${row['store_name'] ?? '-'}',
            summaryText:
                'Sell Out: ${_formatMoneyTight(_toNum(monthly['previous_actual']))} → ${_formatMoneyTight(_toNum(monthly['current_actual']))}',
            achievementPct: _toNum(row['achievement_pct']),
            detailLines: [
              'Sell Out: ${_formatMoneyTight(_toNum(monthly['previous_actual']))} → ${_formatMoneyTight(_toNum(monthly['current_actual']))}',
              'Tipe Fokus: ${_toNum(monthly['previous_focus']).toInt()} → ${_toNum(monthly['current_focus']).toInt()} • VAST: ${_toNum(monthly['previous_vast']).toInt()} → ${_toNum(monthly['current_vast']).toInt()} • Chip: ${_toNum(monthly['previous_chip']).toInt()} → ${_toNum(monthly['current_chip']).toInt()}',
            ],
            promotors: groupedPromotors['${row['store_name'] ?? ''}'] ?? const [],
            promotorMode: _PromotorRowMode.monthly,
          );
        }),
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
            'Sell Out Tim',
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
              Expanded(child: _miniMetric('Target', _formatMoneyTight(target), t.textSecondary)),
              const SizedBox(width: 8),
              Expanded(child: _miniMetric('Gap', _formatMoneyTight(gap), t.warning)),
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

  Widget _buildStoreAccordionRow({
    required String title,
    required String summaryText,
    required num achievementPct,
    required List<String> detailLines,
    required List<_SatorPromotorOverview> promotors,
    required _PromotorRowMode promotorMode,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          childrenPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          collapsedIconColor: t.textMuted,
          iconColor: t.primaryAccent,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      summaryText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w700,
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Pencapaian ${_formatPct(achievementPct)}',
                    style: PromotorText.outfit(
                      size: 9.5,
                      weight: FontWeight.w800,
                      color: _toneForPct(achievementPct),
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.surface3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < detailLines.length; index++) ...[
                    if (index > 0) const SizedBox(height: 6),
                    Text(
                      detailLines[index],
                      style: PromotorText.outfit(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Promotor di toko ini',
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            _buildPromotorHeaderForMode(promotorMode),
            const SizedBox(height: 4),
            ...promotors.map(
              (row) => _buildPromotorOverviewRow(
                row,
                mode: promotorMode,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSoldTypeRow(Map<String, dynamic> row) {
    final isChip = row['is_chip'] == true;
    final qty = _toNum(row['units']).toInt();
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
              color: isChip ? t.warning : t.primaryAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _teamDailyHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          _dailyHeaderCell('Tanggal', 46, TextAlign.left),
          _dailyHeaderCell('Sell Out', 74, TextAlign.right),
          _dailyHeaderCell('Pencapaian', 54, TextAlign.right),
          _dailyHeaderCell('Tipe Fokus', 54, TextAlign.center),
          _dailyHeaderCell('VAST', 40, TextAlign.center),
          _dailyHeaderCell('Chip', 34, TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildPromotorHeaderForMode(_PromotorRowMode mode) {
    return switch (mode) {
      _PromotorRowMode.daily => Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Promotor',
                style: PromotorText.outfit(
                  size: 8.5,
                  weight: FontWeight.w800,
                  color: t.textMuted,
                ),
              ),
            ),
            _dailyHeaderCell('Sell Out', 50, TextAlign.left),
            _dailyHeaderCell('Pencapaian', 54, TextAlign.right),
            _dailyHeaderCell('Fokus', 40, TextAlign.center),
            _dailyHeaderCell('VAST', 40, TextAlign.center),
            _dailyHeaderCell('Chip', 34, TextAlign.center),
          ],
        ),
      ),
      _PromotorRowMode.weekly => Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Promotor',
                style: PromotorText.outfit(
                  size: 8.5,
                  weight: FontWeight.w800,
                  color: t.textMuted,
                ),
              ),
            ),
            _dailyHeaderCell('Sell Out', 76, TextAlign.left),
            _dailyHeaderCell('Tipe Fokus', 54, TextAlign.center),
            _dailyHeaderCell('VAST', 46, TextAlign.center),
            _dailyHeaderCell('Selisih', 70, TextAlign.right),
          ],
        ),
      ),
      _PromotorRowMode.monthly => Container(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Promotor',
                style: PromotorText.outfit(
                  size: 8.5,
                  weight: FontWeight.w800,
                  color: t.textMuted,
                ),
              ),
            ),
            _dailyHeaderCell('Sell Out', 92, TextAlign.left),
            _dailyHeaderCell('Tipe Fokus', 46, TextAlign.center),
            _dailyHeaderCell('VAST', 38, TextAlign.center),
            _dailyHeaderCell('Selisih', 62, TextAlign.right),
          ],
        ),
      ),
      _PromotorRowMode.summary => const SizedBox.shrink(),
    };
  }

  Widget _compareValueCell(
    String text, {
    required double width,
    TextAlign align = TextAlign.center,
    Color? color,
  }) {
    final alignment = switch (align) {
      TextAlign.left || TextAlign.start => Alignment.centerLeft,
      TextAlign.right || TextAlign.end => Alignment.centerRight,
      _ => Alignment.center,
    };
    return SizedBox(
      width: width,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: alignment,
        child: Text(
          text,
          textAlign: align,
          maxLines: 1,
          style: PromotorText.outfit(
            size: 9,
            weight: FontWeight.w700,
            color: color ?? t.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _deltaMoneyCell(num delta) {
    return SizedBox(
      width: 70,
      child: Text(
        delta >= 0 ? '+${_formatMoneyTight(delta)}' : _formatMoneyTight(delta),
        textAlign: TextAlign.right,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: PromotorText.outfit(
          size: 9.5,
          weight: FontWeight.w800,
          color: delta >= 0 ? t.success : t.danger,
        ),
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

  Widget _buildTeamDailyRow(Map<String, dynamic> row) {
    final date = DateTime.tryParse('${row['date'] ?? ''}');
    final pct = _toNum(row['achievement_pct']);
    final tone = _toneForPct(pct);
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
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
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              _formatPct(pct),
              textAlign: TextAlign.right,
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
          SizedBox(
            width: 54,
            child: Text(
              '${_toNum(row['actual_focus']).toInt()}',
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
              '${_toNum(row['vast_closing']).toInt()}',
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
              '${_toNum(row['chip_units']).toInt()}',
              textAlign: TextAlign.center,
              style: PromotorText.outfit(
                size: 9,
                weight: FontWeight.w700,
                color: _toNum(row['chip_units']) > 0 ? t.warning : t.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotorOverviewRow(
    _SatorPromotorOverview row, {
    required _PromotorRowMode mode,
    Map<String, dynamic>? leftWeek,
    Map<String, dynamic>? rightWeek,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SelloutInsightPage(
              userIdOverride: row.id,
              titleOverride: row.name,
            ),
          ),
        ),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          margin: const EdgeInsets.only(bottom: 6),
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.surface3),
          ),
          child: switch (mode) {
            _PromotorRowMode.summary => _buildSummaryRowContent(row),
            _PromotorRowMode.daily => _buildDailyRowContent(row),
            _PromotorRowMode.weekly => _buildWeeklyRowContent(row, leftWeek, rightWeek),
            _PromotorRowMode.monthly => _buildMonthlyRowContent(row),
          },
        ),
      ),
    );
  }

  Widget _buildSummaryRowContent(_SatorPromotorOverview row) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                row.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Sell Out: ${_formatMoneyTight(row.actualCurrent)} • Tipe Fokus: ${row.focusActualCurrent.toInt()} • Tipe Khusus: ${row.specialActualCurrent.toInt()} • VAST: ${row.vastClosingCurrent.toInt()}',
                style: PromotorText.outfit(
                  size: 9.5,
                  weight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Text(
          _formatPct(row.monthlyPct),
          style: PromotorText.outfit(
            size: 10,
            weight: FontWeight.w800,
            color: _toneForPct(row.monthlyPct),
          ),
        ),
      ],
    );
  }

  Widget _buildDailyRowContent(_SatorPromotorOverview row) {
    final daily = row.dailyCurrent;
    final pct = _toNum(daily['achievement_pct']);
    return Row(
      children: [
        Expanded(
          child: Text(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 10.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 50,
          child: Text(
            _formatMoneyTight(_toNum(daily['actual_omzet'])),
            textAlign: TextAlign.right,
            style: PromotorText.outfit(
              size: 9.5,
              weight: FontWeight.w800,
              color: _toneForPct(pct),
            ),
          ),
        ),
        SizedBox(
          width: 46,
          child: Text(
            _formatPct(pct),
            textAlign: TextAlign.right,
            style: PromotorText.outfit(
              size: 9.5,
              weight: FontWeight.w800,
              color: _toneForPct(pct),
            ),
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 36,
          child: Text(
            '${_toNum(daily['focus']).toInt()}',
            textAlign: TextAlign.center,
            style: PromotorText.outfit(
              size: 9,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ),
        SizedBox(
          width: 36,
          child: Text(
            '${_toNum(daily['vast']).toInt()}',
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
            '${_toNum(daily['chip']).toInt()}',
            textAlign: TextAlign.center,
            style: PromotorText.outfit(
              size: 9,
              weight: FontWeight.w700,
              color: _toNum(daily['chip']) > 0 ? t.warning : t.textMuted,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyRowContent(
    _SatorPromotorOverview row,
    Map<String, dynamic>? leftWeek,
    Map<String, dynamic>? rightWeek,
  ) {
    final left = row.weekByKey(_leftWeekKey);
    final right = row.weekByKey(_rightWeekKey);
    final leftActual = _toNum(left['actual_omzet']);
    final rightActual = _toNum(right['actual_omzet']);
    final delta = rightActual - leftActual;
    return Row(
      children: [
        Expanded(
          child: Text(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 10.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ),
        _compareValueCell(
          '${_formatMoneyTight(leftActual)} → ${_formatMoneyTight(rightActual)}',
          width: 76,
          align: TextAlign.right,
        ),
        const SizedBox(width: 4),
        _compareValueCell(
          '${_toNum(left['actual_focus']).toInt()} → ${_toNum(right['actual_focus']).toInt()}',
          width: 50,
        ),
        _compareValueCell(
          '${_toNum(left['vast_closing']).toInt()} → ${_toNum(right['vast_closing']).toInt()}',
          width: 42,
          color: t.info,
        ),
        _deltaMoneyCell(delta),
      ],
    );
  }

  Widget _buildMonthlyRowContent(_SatorPromotorOverview row) {
    final delta = row.actualCurrent - row.previousActual;
    return Row(
      children: [
        Expanded(
          child: Text(
            row.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 10.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ),
        _compareValueCell(
          '${_formatMoneyTight(row.previousActual)} → ${_formatMoneyTight(row.actualCurrent)}',
          width: 92,
          align: TextAlign.right,
        ),
        const SizedBox(width: 4),
        _compareValueCell(
          '${row.previousFocusActual.toInt()} → ${row.focusActualCurrent.toInt()}',
          width: 46,
        ),
        _compareValueCell(
          '${row.previousVastClosing} → ${row.vastClosingCurrent}',
          width: 38,
          color: t.info,
        ),
        SizedBox(
          width: 62,
          child: Text(
            delta >= 0 ? '+${_formatMoneyTight(delta)}' : _formatMoneyTight(delta),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 9.5,
              weight: FontWeight.w800,
              color: delta >= 0 ? t.success : t.danger,
            ),
          ),
        ),
      ],
    );
  }

  Widget _weekSelector({
    required String? value,
    required String label,
    required List<Map<String, dynamic>> rows,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
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
          selectedItemBuilder: (_) {
            return rows.map((row) {
              return Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatWeekTitle(row),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 10.5,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                    Text(
                      _formatWeekRange(row),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 9,
                        weight: FontWeight.w700,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
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
          items: rows.map((row) {
            final key = _weekKey(row);
            return DropdownMenuItem<String>(
              value: key,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatWeekTitle(row),
                    style: PromotorText.outfit(
                      size: 10.5,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  Text(
                    _formatWeekRange(row),
                    style: PromotorText.outfit(
                      size: 9,
                      weight: FontWeight.w700,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildWeeklyMatrix(
    Map<String, dynamic>? left,
    Map<String, dynamic>? right,
  ) {
    if (left == null || right == null) return _emptyCard('Pilih minggu dulu.');
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          _weeklyMatrixHeader(left, right),
          _matrixRow('Sell Out', _toNum(left['actual_omzet']), _toNum(right['actual_omzet']), money: true),
          _matrixRow('Tipe Fokus', _toNum(left['actual_focus']), _toNum(right['actual_focus'])),
          _matrixRow('Tipe Khusus', _toNum(left['actual_special']), _toNum(right['actual_special'])),
          _matrixRow('VAST Input', _toNum(left['vast_input']), _toNum(right['vast_input'])),
          _matrixRow('VAST Closing', _toNum(left['vast_closing']), _toNum(right['vast_closing'])),
          _matrixRow('Chip', _toNum(left['chip_units']), _toNum(right['chip_units']), isLast: true),
        ],
      ),
    );
  }

  Widget _weeklyMatrixHeader(
    Map<String, dynamic> left,
    Map<String, dynamic> right,
  ) {
    Widget weekColumn(Map<String, dynamic> row) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _formatWeekTitle(row),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 9,
              weight: FontWeight.w800,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            _formatWeekRange(row),
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 8.5,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.surface2,
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
          Expanded(flex: 2, child: weekColumn(left)),
          Expanded(flex: 2, child: weekColumn(right)),
          Expanded(
            flex: 2,
            child: Text(
              'Selisih',
              textAlign: TextAlign.right,
              style: PromotorText.outfit(
                size: 9,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthlyMatrix({
    required String previousLabel,
    required String currentLabel,
    required Map<String, dynamic> previous,
    required Map<String, dynamic> current,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          _matrixHeader(previousLabel, currentLabel),
          _matrixRow('Sell Out', _toNum(previous['actual']), _toNum(current['actual']), money: true),
          _matrixRow('Tipe Fokus', _toNum(previous['focus']), _toNum(current['focus'])),
          _matrixRow('Tipe Khusus', _toNum(previous['special']), _toNum(current['special'])),
          _matrixRow('VAST Closing', _toNum(previous['vast']), _toNum(current['vast'])),
          _matrixRow('Chip', _toNum(previous['chip']), _toNum(current['chip']), isLast: true),
        ],
      ),
    );
  }

  Widget _matrixHeader(String left, String right) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: t.surface2,
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
              left,
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
              right,
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
                size: 9,
                weight: FontWeight.w800,
                color: t.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _matrixRow(
    String label,
    num left,
    num right, {
    bool money = false,
    bool isLast = false,
  }) {
    final delta = right - left;
    final tone = delta > 0 ? t.success : (delta < 0 ? t.danger : t.textMuted);
    final leftTone = _compareTone(left: left, right: right, rightSide: false);
    final rightTone = _compareTone(left: left, right: right, rightSide: true);
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
              money ? _formatMoneyTight(left) : '${left.toInt()}',
              textAlign: TextAlign.right,
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w800,
                color: leftTone,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              money ? _formatMoneyTight(right) : '${right.toInt()}',
              textAlign: TextAlign.right,
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w800,
                color: rightTone,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              delta >= 0
                  ? money
                      ? '+${_formatMoneyTight(delta)}'
                      : '+${delta.toInt()}'
                  : money
                      ? _formatMoneyTight(delta)
                      : '${delta.toInt()}',
              textAlign: TextAlign.right,
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w800,
                color: tone,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {String? subtitle}) {
    return Column(
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
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Widget _emptyCard(String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 10.5,
          weight: FontWeight.w700,
          color: t.textSecondary,
        ),
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
}

enum _PromotorRowMode { summary, daily, weekly, monthly }

class _SatorPromotorOverview {
  _SatorPromotorOverview({
    required this.id,
    required this.name,
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
  final String storeName;
  final DateTime referenceDate;
  final Map<String, dynamic> currentInsight;
  final Map<String, dynamic> previousInsight;
  final Map<String, dynamic> currentTargetMeta;
  final Map<String, dynamic> previousTargetMeta;
  final List<Map<String, dynamic>> salesRows;
  final List<Map<String, dynamic>> vastRows;

  DateTime get monthStart => DateTime(referenceDate.year, referenceDate.month, 1);
  DateTime get prevMonthStart => DateTime(referenceDate.year, referenceDate.month - 1, 1);
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

  num get previousMonthlyTarget {
    final targetOmzet = _toNum(previousTargetMeta['target_omzet']);
    if (targetOmzet > 0) return targetOmzet;
    return _toNum(previousTargetMeta['target_sell_out']);
  }

  num get actualCurrent => _toNum(_asMap(currentInsight['summary'])['actual_total']);
  num get previousActual => _toNum(_asMap(previousInsight['summary'])['actual_total']);
  num get monthlyPct => monthlyTarget > 0 ? (actualCurrent / monthlyTarget) * 100 : 0;

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

  num get focusActualCurrent => _toNum(_asMap(currentInsight['summary'])['focus_units_total']);
  num get specialActualCurrent => _toNum(_asMap(currentInsight['summary'])['special_units_total']);
  num get previousFocusActual => _toNum(_asMap(previousInsight['summary'])['focus_units_total']);
  num get previousSpecialActual => _toNum(_asMap(previousInsight['summary'])['special_units_total']);

  List<Map<String, dynamic>> get currentSalesRows => salesRows.where((row) {
        final date = DateTime.tryParse('${row['transaction_date'] ?? ''}');
        return date != null &&
            !date.isBefore(monthStart) &&
            !date.isAfter(referenceDate);
      }).toList();

  List<Map<String, dynamic>> get previousSalesRows => salesRows.where((row) {
        final date = DateTime.tryParse('${row['transaction_date'] ?? ''}');
        return date != null &&
            !date.isBefore(prevMonthStart) &&
            !date.isAfter(prevMonthEnd);
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
        return date != null &&
            DateFormat('yyyy-MM-dd').format(date) == dateKey;
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
    Map<String, dynamic> row = const <String, dynamic>{};
    final dateKey = DateFormat('yyyy-MM-dd').format(referenceDate);
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
      final rowKey = '${row['week_number'] ?? ''}-${row['week_start'] ?? ''}';
      if (rowKey == key) return row;
    }
    return const {};
  }
}
