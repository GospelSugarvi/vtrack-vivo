import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class AllbrandReportDetailPanel extends StatefulWidget {
  final String? reportId;
  final String? storeId;
  final String? initialStoreName;
  final DateTime? targetDate;
  final EdgeInsetsGeometry padding;

  const AllbrandReportDetailPanel({
    super.key,
    this.reportId,
    this.storeId,
    this.initialStoreName,
    this.targetDate,
    this.padding = EdgeInsets.zero,
  }) : assert(reportId != null || storeId != null);

  @override
  State<AllbrandReportDetailPanel> createState() =>
      _AllbrandReportDetailPanelState();
}

class _AllbrandReportDetailPanelState extends State<AllbrandReportDetailPanel> {
  static const List<String> _brands = <String>[
    'Samsung',
    'OPPO',
    'Realme',
    'Xiaomi',
    'Infinix',
    'Tecno',
  ];

  static const List<String> _priceRanges = <String>[
    'under_2m',
    '2m_4m',
    '4m_6m',
    'above_6m',
  ];

  static const List<String> _leasingProviders = <String>[
    'HCI',
    'Kredivo',
    'FIF',
    'Indodana',
    'Kredit Plus',
    'Home Credit',
    'VAST Finance',
  ];

  final _supabase = Supabase.instance.client;
  final _dateFormat = DateFormat('dd/MM/yyyy');
  bool _isLoading = true;
  Map<String, dynamic>? _report;
  String _messageText = '';

  @override
  void initState() {
    super.initState();
    _loadReport();
  }

  Future<void> _loadReport() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      Map<String, dynamic>? row;
      if (widget.reportId != null && widget.reportId!.isNotEmpty) {
        row = await _supabase
            .from('allbrand_reports')
            .select(
              'id, promotor_id, store_id, report_date, '
              'brand_data, brand_data_daily, leasing_sales, leasing_sales_daily, '
              'daily_total_units, cumulative_total_units, vivo_auto_data, '
              'vivo_promotor_count, notes, stores(store_name), users(full_name, nickname)',
            )
            .eq('id', widget.reportId!)
            .maybeSingle();
      } else if (widget.storeId != null && widget.storeId!.isNotEmpty) {
        final dateKey = (widget.targetDate ?? DateTime.now())
            .toIso8601String()
            .split('T')
            .first;
        row = await _supabase
            .from('allbrand_reports')
            .select(
              'id, promotor_id, store_id, report_date, '
              'brand_data, brand_data_daily, leasing_sales, leasing_sales_daily, '
              'daily_total_units, cumulative_total_units, vivo_auto_data, '
              'vivo_promotor_count, notes, stores(store_name), users(full_name, nickname)',
            )
            .eq('store_id', widget.storeId!)
            .lte('report_date', dateKey)
            .order('report_date', ascending: false)
            .order('updated_at', ascending: false)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
      }

      if (row == null) {
        if (!mounted) return;
        setState(() {
          _report = null;
          _messageText = '';
          _isLoading = false;
        });
        return;
      }

      final report = Map<String, dynamic>.from(row);
      final vivoSummary = await _loadVivoSalesSummary(report);
      final promotorSummaries = await _loadPromotorSummaries(report);
      final message = _buildTerminalMessage(report, promotorSummaries, vivoSummary);

      if (!mounted) return;
      setState(() {
        _report = report;
        _messageText = message;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _report = null;
        _messageText = '';
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadPromotorSummaries(
    Map<String, dynamic> report,
  ) async {
    final storeId = report['store_id']?.toString();
    final reportDate = DateTime.tryParse('${report['report_date'] ?? ''}');
    if (storeId == null || storeId.isEmpty || reportDate == null) {
      return const [];
    }

    final reportDateKey = reportDate.toIso8601String().split('T').first;
    final assignmentRows = await _supabase
        .from('assignments_promotor_store')
        .select('promotor_id, users(full_name, nickname)')
        .eq('store_id', storeId)
        .eq('active', true)
        .order('created_at', ascending: false);

    final latestByPromotor = <String, Map<String, dynamic>>{};
    for (final raw in List<Map<String, dynamic>>.from(assignmentRows)) {
      final promotorId = raw['promotor_id']?.toString() ?? '';
      if (promotorId.isEmpty || latestByPromotor.containsKey(promotorId)) {
        continue;
      }
      latestByPromotor[promotorId] = raw;
    }
    if (latestByPromotor.isEmpty) return const [];

    final promotorIds = latestByPromotor.keys.toList();
    final periodRows = await _supabase
        .from('target_periods')
        .select('id, start_date, end_date')
        .lte('start_date', reportDateKey)
        .gte('end_date', reportDateKey)
        .isFilter('deleted_at', null)
        .order('start_date', ascending: false)
        .limit(1);

    String? periodId;
    DateTime periodStart = reportDate;
    if (periodRows.isNotEmpty) {
      final period = Map<String, dynamic>.from(periodRows.first);
      periodId = period['id']?.toString();
      periodStart =
          DateTime.tryParse('${period['start_date'] ?? ''}') ?? reportDate;
    }

    final targetRows = periodId == null
        ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _supabase
                .from('user_targets')
                .select(
                  'user_id, target_sell_out, target_fokus_total, '
                  'target_fokus_detail, target_special, target_special_detail',
                )
                .eq('period_id', periodId)
                .inFilter('user_id', promotorIds)
                .order('updated_at', ascending: false),
          );

    final latestTargetByUser = <String, Map<String, dynamic>>{};
    for (final row in targetRows) {
      final userId = row['user_id']?.toString() ?? '';
      if (userId.isEmpty || latestTargetByUser.containsKey(userId)) continue;
      latestTargetByUser[userId] = row;
    }

    final dashboardByUser = <String, Map<String, dynamic>>{};
    for (final promotorId in promotorIds) {
      final raw = await _supabase.rpc(
        'get_daily_target_dashboard',
        params: {
          'p_user_id': promotorId,
          'p_date': reportDateKey,
        },
      );
      if (raw is List && raw.isNotEmpty && raw.first is Map) {
        dashboardByUser[promotorId] = Map<String, dynamic>.from(raw.first);
      } else if (raw is Map) {
        dashboardByUser[promotorId] = Map<String, dynamic>.from(raw);
      }
    }

    final salesRows = await _supabase
        .from('sales_sell_out')
        .select(
          'promotor_id, transaction_date, price_at_transaction, variant_id, '
          'product_variants(product_id, products(is_focus))',
        )
        .eq('store_id', storeId)
        .inFilter('promotor_id', promotorIds)
        .gte('transaction_date', periodStart.toIso8601String().split('T').first)
        .lte('transaction_date', reportDateKey)
        .eq('is_chip_sale', false)
        .isFilter('deleted_at', null);

    final specialBundleIds = <String>{};
    for (final row in latestTargetByUser.values) {
      final detail = _safeMap(row['target_special_detail']);
      specialBundleIds.addAll(detail.keys);
    }

    final specialProductIdsByBundle = <String, Set<String>>{};
    final specialBundleNames = <String, String>{};
    if (specialBundleIds.isNotEmpty) {
      final bundleRows = await _supabase
          .from('special_focus_bundles')
          .select('id, bundle_name')
          .inFilter('id', specialBundleIds.toList());
      for (final raw in List<Map<String, dynamic>>.from(bundleRows)) {
        final bundleId = raw['id']?.toString() ?? '';
        if (bundleId.isEmpty) continue;
        specialBundleNames[bundleId] = '${raw['bundle_name'] ?? 'Tipe Khusus'}';
      }

      final specialRows = await _supabase
          .from('special_focus_bundle_products')
          .select('bundle_id, product_id')
          .inFilter('bundle_id', specialBundleIds.toList());
      for (final raw in List<Map<String, dynamic>>.from(specialRows)) {
        final bundleId = raw['bundle_id']?.toString() ?? '';
        final productId = raw['product_id']?.toString() ?? '';
        if (bundleId.isEmpty || productId.isEmpty) continue;
        specialProductIdsByBundle.putIfAbsent(bundleId, () => <String>{});
        specialProductIdsByBundle[bundleId]!.add(productId);
      }
    }

    final summaries = <String, Map<String, dynamic>>{};
    for (final promotorId in promotorIds) {
      final assignment = latestByPromotor[promotorId] ?? const <String, dynamic>{};
      final target = latestTargetByUser[promotorId] ?? const <String, dynamic>{};
      final dashboard = dashboardByUser[promotorId] ?? const <String, dynamic>{};
      final focusDetail = _safeMap(target['target_fokus_detail']);
      final specialDetail = _safeMap(target['target_special_detail']);

      summaries[promotorId] = {
        'promotor_id': promotorId,
        'name': _displayName(assignment['users']),
        'target_all_month': _toNum(target['target_sell_out']),
        'target_all_day': _toNum(dashboard['target_daily_all_type']),
        'actual_all_day': _toNum(dashboard['actual_daily_all_type']),
        'actual_all_month': 0.0,
        'target_focus_month': _sumJsonValues(focusDetail).toDouble(),
        'target_focus_day':
            _computeDailyDetailTarget(
              monthlyTotal: _sumJsonValues(focusDetail).toDouble(),
              monthlyFallback: _toNum(target['target_fokus_total']),
              weeklyTarget: _toNum(dashboard['target_weekly_focus']),
            ),
        'actual_focus_day': 0,
        'actual_focus_month': 0,
        'target_special_month': _sumJsonValues(specialDetail).toDouble(),
        'target_special_day': _computeDailyDetailTarget(
          monthlyTotal: _sumJsonValues(specialDetail).toDouble(),
          monthlyFallback: _toNum(target['target_special']),
          weeklyTarget: null,
        ),
        'actual_special_day': 0,
        'actual_special_month': 0,
        'special_rows': specialDetail.entries.map((entry) {
          final bundleId = entry.key;
          final targetMonth = _toNum(entry.value);
          return <String, dynamic>{
            'bundle_id': bundleId,
            'label': specialBundleNames[bundleId] ?? 'Tipe Khusus',
            'target_day': _computeDailyDetailTarget(
              monthlyTotal: targetMonth,
              monthlyFallback: targetMonth,
              weeklyTarget: null,
            ),
            'target_month': targetMonth,
            'actual_day': 0,
            'actual_month': 0,
            'product_ids':
                specialProductIdsByBundle[bundleId] ?? const <String>{},
          };
        }).toList(),
        'special_product_ids': _resolveSpecialProductIds(
          specialDetail.keys,
          specialProductIdsByBundle,
        ),
      };
    }

    for (final raw in List<Map<String, dynamic>>.from(salesRows)) {
      final promotorId = raw['promotor_id']?.toString() ?? '';
      final summary = summaries[promotorId];
      if (summary == null) continue;
      final rowDate = '${raw['transaction_date'] ?? ''}';
      final isToday = rowDate == reportDateKey;
      final price = _toNum(raw['price_at_transaction']);
      final variant = raw['product_variants'] is Map
          ? Map<String, dynamic>.from(raw['product_variants'] as Map)
          : const <String, dynamic>{};
      final productRaw = variant['products'] is Map
          ? Map<String, dynamic>.from(variant['products'] as Map)
          : const <String, dynamic>{};
      final productId = variant['product_id']?.toString() ?? '';
      final isFocus = productRaw['is_focus'] == true;
      final specialIds =
          (summary['special_product_ids'] as Set<String>? ?? const <String>{});
      final specialRows =
          List<Map<String, dynamic>>.from(summary['special_rows'] as List? ?? const []);

      summary['actual_all_month'] = _toNum(summary['actual_all_month']) + price;
      if (isToday) {
        summary['actual_all_day'] = _toNum(summary['actual_all_day']) + price;
      }

      if (isFocus) {
        summary['actual_focus_month'] = _toInt(summary['actual_focus_month']) + 1;
        if (isToday) {
          summary['actual_focus_day'] = _toInt(summary['actual_focus_day']) + 1;
        }
      }

      if (productId.isNotEmpty && specialIds.contains(productId)) {
        summary['actual_special_month'] =
            _toInt(summary['actual_special_month']) + 1;
        if (isToday) {
          summary['actual_special_day'] =
              _toInt(summary['actual_special_day']) + 1;
        }
      }

      if (productId.isNotEmpty && specialRows.isNotEmpty) {
        for (final specialRow in specialRows) {
          final productIds =
              specialRow['product_ids'] as Set<String>? ?? const <String>{};
          if (!productIds.contains(productId)) continue;
          specialRow['actual_month'] = _toInt(specialRow['actual_month']) + 1;
          if (isToday) {
            specialRow['actual_day'] = _toInt(specialRow['actual_day']) + 1;
          }
        }
      }
    }

    final result = summaries.values.map((row) {
      row.remove('special_product_ids');
      final specialRows =
          List<Map<String, dynamic>>.from(row['special_rows'] as List? ?? const []);
      for (final specialRow in specialRows) {
        specialRow.remove('product_ids');
      }
      specialRows.sort(
        (a, b) => _toNum(b['target_month']).compareTo(_toNum(a['target_month'])),
      );
      row['special_rows'] = specialRows;
      return row;
    }).toList();

    result.sort(
      (a, b) =>
          _toNum(b['actual_all_day']).compareTo(_toNum(a['actual_all_day'])),
    );
    return result;
  }

  Future<Map<String, dynamic>> _loadVivoSalesSummary(
    Map<String, dynamic> report,
  ) async {
    final storeId = report['store_id']?.toString();
    final reportDate = DateTime.tryParse('${report['report_date'] ?? ''}');
    if (storeId == null || storeId.isEmpty || reportDate == null) {
      return const {
        'daily_total': 0,
        'monthly_total': 0,
        'daily_rows': <Map<String, dynamic>>[],
        'monthly_rows': <Map<String, dynamic>>[],
      };
    }

    final reportDateKey = reportDate.toIso8601String().split('T').first;
    var periodStart = DateTime(reportDate.year, reportDate.month, 1);
    final periodRows = await _supabase
        .from('target_periods')
        .select('start_date, end_date')
        .lte('start_date', reportDateKey)
        .gte('end_date', reportDateKey)
        .isFilter('deleted_at', null)
        .order('start_date', ascending: false)
        .limit(1);
    if (periodRows.isNotEmpty) {
      final period = Map<String, dynamic>.from(periodRows.first);
      periodStart = DateTime.tryParse('${period['start_date'] ?? ''}') ?? periodStart;
    }

    final salesRows = await _supabase
        .from('sales_sell_out')
        .select(
          'transaction_date, product_variants(ram_rom, ram, storage, color, products(model_name))',
        )
        .eq('store_id', storeId)
        .gte('transaction_date', periodStart.toIso8601String().split('T').first)
        .lte('transaction_date', reportDateKey)
        .eq('is_chip_sale', false)
        .isFilter('deleted_at', null);

    final dailyCounts = <String, int>{};
    final monthlyCounts = <String, int>{};
    for (final raw in List<Map<String, dynamic>>.from(salesRows)) {
      final dateKey = '${raw['transaction_date'] ?? ''}';
      final variant = raw['product_variants'] is Map
          ? Map<String, dynamic>.from(raw['product_variants'] as Map)
          : const <String, dynamic>{};
      final label = _buildVivoTypeLabel(variant);
      if (label.isEmpty) continue;
      monthlyCounts[label] = (monthlyCounts[label] ?? 0) + 1;
      if (dateKey == reportDateKey) {
        dailyCounts[label] = (dailyCounts[label] ?? 0) + 1;
      }
    }

    final monthlyRows = monthlyCounts.entries
        .map((entry) => <String, dynamic>{
              'label': entry.key,
              'qty': entry.value,
            })
        .toList()
      ..sort((a, b) => _toInt(b['qty']).compareTo(_toInt(a['qty'])));

    final dailyRows = dailyCounts.entries
        .map((entry) => <String, dynamic>{
              'label': entry.key,
              'qty': entry.value,
            })
        .toList()
      ..sort((a, b) => _toInt(b['qty']).compareTo(_toInt(a['qty'])));

    return {
      'daily_total': dailyCounts.values.fold<int>(0, (sum, value) => sum + value),
      'monthly_total':
          monthlyCounts.values.fold<int>(0, (sum, value) => sum + value),
      'daily_rows': dailyRows,
      'monthly_rows': monthlyRows,
    };
  }

  Set<String> _resolveSpecialProductIds(
    Iterable<String> bundleIds,
    Map<String, Set<String>> bundleMap,
  ) {
    final ids = <String>{};
    for (final bundleId in bundleIds) {
      ids.addAll(bundleMap[bundleId] ?? const <String>{});
    }
    return ids;
  }

  double _computeDailyDetailTarget({
    required double monthlyTotal,
    double? monthlyFallback,
    double? weeklyTarget,
  }) {
    final source = monthlyTotal > 0 ? monthlyTotal : (monthlyFallback ?? 0);
    if (source <= 0) return 0;
    if (weeklyTarget != null && weeklyTarget > 0) {
      final ratio = (weeklyTarget / source).clamp(0, 1.5);
      return double.parse((source * ratio / 6).toStringAsFixed(2));
    }
    return double.parse((source / 24).toStringAsFixed(2));
  }

  String _buildTerminalMessage(
    Map<String, dynamic> report,
    List<Map<String, dynamic>> promotorSummaries,
    Map<String, dynamic> vivoSummary,
  ) {
    final storeName =
        '${report['stores']?['store_name'] ?? widget.initialStoreName ?? '-'}';
    final inputBy = _displayName(report['users']);
    final reportDate = _formatDate(report['report_date']);
    final brandDaily = _safeMap(report['brand_data_daily'] ?? report['brand_data']);
    final brandTotal = _safeMap(report['brand_data']);
    final leasingDaily = _safeMap(
      report['leasing_sales_daily'] ?? report['leasing_sales'],
    );
    final leasingTotal = _safeMap(report['leasing_sales']);
    final vivo = _safeMap(report['vivo_auto_data']);
    final notes = '${report['notes'] ?? ''}'.trim();
    final dailyVivoTotal = _toInt(vivoSummary['daily_total']);
    final monthlyVivoTotal = _toInt(vivoSummary['monthly_total']);
    final dailyAllBrand = _toInt(report['daily_total_units']) + dailyVivoTotal;
    final monthlyAllBrand =
        _toInt(report['cumulative_total_units']) + monthlyVivoTotal;
    final marketRows = _buildMarketShareRows(
      brandDaily: brandDaily,
      brandTotal: brandTotal,
      dailyVivoTotal: dailyVivoTotal,
      monthlyVivoTotal: monthlyVivoTotal,
      dailyAllBrand: dailyAllBrand,
      monthlyAllBrand: monthlyAllBrand,
    );
    final dailyVivoRows = List<Map<String, dynamic>>.from(
      (vivoSummary['daily_rows'] as List?) ?? const [],
    );
    final monthlyVivoRows = List<Map<String, dynamic>>.from(
      (vivoSummary['monthly_rows'] as List?) ?? const [],
    );
    const sectionDivider = '========================================';

    final lines = <String>[
      'LAPORAN ALL BRAND',
      'TOKO    : $storeName',
      'TANGGAL : $reportDate',
      'INPUT   : $inputBy',
      '',
      sectionDivider,
      'BRAND STORE',
      sectionDivider,
      '${_padRight('BRAND', 9)} ${_center('<2', 5)} ${_center('2-4', 5)} ${_center('4-6', 5)} ${_center('>6', 5)} ${_center('PROM', 6)}',
      '----------------------------------------',
    ];

    for (final brand in _brands) {
      final a = _safeMap(brandDaily[brand]);
      final b = _safeMap(brandTotal[brand]);
      if (_sumBrandRow(a) == 0 && _sumBrandRow(b) == 0) continue;
      lines.add(
        '${_padRight(brand, 9)} '
        '${_abCell(a['under_2m'], b['under_2m'], width: 5)} '
        '${_abCell(a['2m_4m'], b['2m_4m'], width: 5)} '
        '${_abCell(a['4m_6m'], b['4m_6m'], width: 5)} '
        '${_abCell(a['above_6m'], b['above_6m'], width: 5)} '
        '${_padLeft('${_toInt(a['promotor_count'])}', 6)}',
      );
    }

    lines.add(
      '${_padRight('VIVO', 9)} '
      '${_abCell(vivo['under_2m'], monthlyVivoTotal == 0 ? vivo['under_2m'] : vivo['under_2m'], width: 5)} '
      '${_abCell(vivo['2m_4m'], monthlyVivoTotal == 0 ? vivo['2m_4m'] : vivo['2m_4m'], width: 5)} '
      '${_abCell(vivo['4m_6m'], monthlyVivoTotal == 0 ? vivo['4m_6m'] : vivo['4m_6m'], width: 5)} '
      '${_abCell(vivo['above_6m'], monthlyVivoTotal == 0 ? vivo['above_6m'] : vivo['above_6m'], width: 5)} '
      '${_padLeft('${_toInt(report['vivo_promotor_count'])}', 6)}',
    );

    lines.add('----------------------------------------');
    lines.add(
      'ALL BRAND  ${_padLeft('$dailyAllBrand', 2)} / $monthlyAllBrand',
    );
    lines.add('');
    lines.add(sectionDivider);
    lines.add('MARKET SHARE');
    lines.add(sectionDivider);
    lines.add(
      '${_padRight('BRAND', 10)} ${_center('HARIAN', 10)} ${_center('BULANAN', 10)}',
    );
    lines.add('----------------------------------------');
    for (final row in marketRows) {
      lines.add(
        '${_padRight('${row['brand']}', 10)} '
        '${_center('${row['daily_units']}u ${row['daily_share']}%', 10)} '
        '${_center('${row['monthly_units']}u ${row['monthly_share']}%', 10)}',
      );
    }
    lines.add('');
    lines.add(sectionDivider);
    lines.add('LEASING');
    lines.add(sectionDivider);
    for (final provider in _leasingProviders) {
      final a = _toInt(leasingDaily[provider]);
      final b = _toInt(leasingTotal[provider]);
      if (a == 0 && b == 0) continue;
      lines.add('${_padRight(provider, 12)} ${_abCell(a, b)}');
    }
    lines.add('');
    lines.add(sectionDivider);
    lines.add('VIVO PER TIPE');
    lines.add(sectionDivider);
    lines.add(
      '${_padRight('TIPE', 16)} ${_center('HARIAN', 7)} ${_center('BULAN', 7)}',
    );
    lines.add('----------------------------------------');
    final vivoLabels = <String>{
      ...dailyVivoRows.map((row) => '${row['label']}'),
      ...monthlyVivoRows.map((row) => '${row['label']}'),
    }.toList()
      ..sort((a, b) {
        final aMonthly = _findQty(monthlyVivoRows, a);
        final bMonthly = _findQty(monthlyVivoRows, b);
        return bMonthly.compareTo(aMonthly);
      });
    for (final label in vivoLabels) {
      final dailyQty = _findQty(dailyVivoRows, label);
      final monthlyQty = _findQty(monthlyVivoRows, label);
      lines.add(
        '${_padRight(label, 16)} ${_center('$dailyQty', 7)} ${_center('$monthlyQty', 7)}',
      );
    }

    if (promotorSummaries.isNotEmpty) {
      lines.add('');
      lines.add(sectionDivider);
      lines.add('PENCAPAIAN PROMOTOR VIVO');
      lines.add(sectionDivider);
      for (final row in promotorSummaries) {
        lines.add(_displayPromotorAchievement(row));
        lines.add('----------------------------------------');
      }
    }

    if (notes.isNotEmpty) {
      lines.add('');
      lines.add(sectionDivider);
      lines.add('CATATAN');
      lines.add(sectionDivider);
      lines.add(notes);
    }

    return lines.join('\n').trimRight();
  }

  String _displayPromotorAchievement(Map<String, dynamic> row) {
    final lines = <String>['${row['name'] ?? '-'}'];

    lines.add(
      '${_padRight('ITEM', 12)} ${_center('HARIAN', 14)} ${_center('BULANAN', 14)}',
    );
    lines.add('----------------------------------------');
    lines.add(
      '${_padRight('All Type', 12)} ${_formatMoneyAbRow(
        dayActual: _toNum(row['actual_all_day']),
        dayTarget: _toNum(row['target_all_day']),
        monthActual: _toNum(row['actual_all_month']),
        monthTarget: _toNum(row['target_all_month']),
      )}',
    );
    lines.add(
      '${_padRight('Produk Fokus', 12)} ${_formatUnitAbRow(
        dayActual: _toNum(row['actual_focus_day']),
        dayTarget: _roundedUnitTarget(row['target_focus_day']),
        monthActual: _toNum(row['actual_focus_month']),
        monthTarget: _toNum(row['target_focus_month']),
      )}',
    );
    final specialRows =
        List<Map<String, dynamic>>.from(row['special_rows'] as List? ?? const []);
    if (specialRows.isEmpty) {
      lines.add(
        '${_padRight('Tipe Khusus', 12)} ${_formatUnitAbRow(
          dayActual: _toNum(row['actual_special_day']),
          dayTarget: _roundedUnitTarget(row['target_special_day']),
          monthActual: _toNum(row['actual_special_month']),
          monthTarget: _toNum(row['target_special_month']),
        )}',
      );
    } else {
      for (final specialRow in specialRows) {
        lines.add(
          '${_padRight(_compactSpecialLabel('${specialRow['label'] ?? 'Tipe Khusus'}'), 12)} '
          '${_formatUnitAbRow(
            dayActual: _toNum(specialRow['actual_day']),
            dayTarget: _roundedUnitTarget(specialRow['target_day']),
            monthActual: _toNum(specialRow['actual_month']),
            monthTarget: _toNum(specialRow['target_month']),
          )}',
        );
      }
    }
    return lines.join('\n');
  }

  String _formatMoneyAbRow({
    required double dayActual,
    required double dayTarget,
    required double monthActual,
    required double monthTarget,
  }) {
    return '${_center('${_formatMoneyCompact(dayActual)}/${_formatMoneyCompact(dayTarget)} ${_formatPct(dayActual, dayTarget)}', 14)} '
        '${_center('${_formatMoneyCompact(monthActual)}/${_formatMoneyCompact(monthTarget)} ${_formatPct(monthActual, monthTarget)}', 14)}';
  }

  String _formatUnitAbRow({
    required double dayActual,
    required double dayTarget,
    required double monthActual,
    required double monthTarget,
  }) {
    return '${_center('${_formatUnit(dayActual)}/${_formatUnit(dayTarget)} ${_formatPct(dayActual, dayTarget)}', 14)} '
        '${_center('${_formatUnit(monthActual)}/${_formatUnit(monthTarget)} ${_formatPct(monthActual, monthTarget)}', 14)}';
  }

  double _roundedUnitTarget(dynamic raw) {
    final value = _toNum(raw);
    if (value <= 0) return 0;
    return value < 1 ? 1 : value.ceilToDouble();
  }

  List<Map<String, dynamic>> _buildMarketShareRows({
    required Map<String, dynamic> brandDaily,
    required Map<String, dynamic> brandTotal,
    required int dailyVivoTotal,
    required int monthlyVivoTotal,
    required int dailyAllBrand,
    required int monthlyAllBrand,
  }) {
    final rows = <Map<String, dynamic>>[];
    for (final brand in _brands) {
      final dailyUnits = _sumBrandRow(_safeMap(brandDaily[brand]));
      final monthlyUnits = _sumBrandRow(_safeMap(brandTotal[brand]));
      rows.add({
        'brand': brand,
        'daily_units': dailyUnits,
        'monthly_units': monthlyUnits,
        'daily_share': _sharePct(dailyUnits, dailyAllBrand),
        'monthly_share': _sharePct(monthlyUnits, monthlyAllBrand),
      });
    }
    rows.add({
      'brand': 'VIVO',
      'daily_units': dailyVivoTotal,
      'monthly_units': monthlyVivoTotal,
      'daily_share': _sharePct(dailyVivoTotal, dailyAllBrand),
      'monthly_share': _sharePct(monthlyVivoTotal, monthlyAllBrand),
    });
    rows.sort(
      (a, b) => _toInt(b['monthly_units']).compareTo(_toInt(a['monthly_units'])),
    );
    return rows;
  }

  int _sharePct(int numerator, int denominator) {
    if (denominator <= 0) return 0;
    return ((numerator / denominator) * 100).round();
  }

  int _findQty(List<Map<String, dynamic>> rows, String label) {
    for (final row in rows) {
      if ('${row['label']}' == label) return _toInt(row['qty']);
    }
    return 0;
  }

  String _buildVivoTypeLabel(Map<String, dynamic> variant) {
    final product =
        variant['products'] is Map
            ? Map<String, dynamic>.from(variant['products'] as Map)
            : const <String, dynamic>{};
    final model = '${product['model_name'] ?? ''}'.trim();
    final ramRom = '${variant['ram_rom'] ?? ''}'.trim();
    final ram = '${variant['ram'] ?? ''}'.trim();
    final storage = '${variant['storage'] ?? ''}'.trim();
    final spec = ramRom.isNotEmpty
        ? ramRom
        : (ram.isNotEmpty && storage.isNotEmpty ? '$ram/$storage' : '');
    if (model.isEmpty && spec.isEmpty) return '';
    if (model.isEmpty) return spec;
    if (spec.isEmpty) return model;
    return '$model $spec';
  }

  String _compactSpecialLabel(String label) {
    final value = label.trim();
    if (value.length <= 12) return value;
    return value.substring(0, 12);
  }

  String _formatMoneyCompact(double value) {
    final abs = value.abs();
    if (abs >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(value % 1000000 == 0 ? 0 : 1)}jt';
    }
    if (abs >= 1000) {
      return '${(value / 1000).toStringAsFixed(value % 1000 == 0 ? 0 : 1)}rb';
    }
    return value.toStringAsFixed(0);
  }

  String _formatUnit(double value) => value.toStringAsFixed(value % 1 == 0 ? 0 : 1);

  String _formatPct(double actual, double target) {
    if (target <= 0) return '0%';
    return '${((actual / target) * 100).toStringAsFixed(0)}%';
  }

  String _abCell(dynamic a, dynamic b, {int width = 6}) {
    final left = _toInt(a);
    final right = _toInt(b);
    return _padRight('$left/$right', width);
  }

  int _sumBrandRow(Map<String, dynamic> row) {
    var total = 0;
    for (final key in _priceRanges) {
      total += _toInt(row[key]);
    }
    return total;
  }

  String _padRight(String text, int width) {
    final value = text.length > width ? text.substring(0, width) : text;
    return value.padRight(width);
  }

  String _padLeft(String text, int width) {
    final value = text.length > width ? text.substring(text.length - width) : text;
    return value.padLeft(width);
  }

  String _center(String text, int width) {
    final value = text.length > width ? text.substring(0, width) : text;
    final left = ((width - value.length) / 2).floor();
    final right = width - value.length - left;
    return '${' ' * left}$value${' ' * right}';
  }

  String _displayName(dynamic userRaw) {
    final user = _safeMap(userRaw);
    final nickname = '${user['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    final fullName = '${user['full_name'] ?? ''}'.trim();
    return fullName.isNotEmpty ? fullName : '-';
  }

  Map<String, dynamic> _safeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  int _sumJsonValues(Map<String, dynamic> raw) {
    return raw.values.fold<int>(0, (sum, value) => sum + _toInt(value));
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  double _toNum(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '-';
    return _dateFormat.format(parsed.toLocal());
  }

  Future<void> _copyText() async {
    if (_messageText.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: _messageText));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Format kiriman berhasil disalin')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_report == null) {
      return Padding(
        padding: widget.padding,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: t.surface3),
          ),
          child: Text(
            'Detail laporan all brand belum tersedia.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: t.textMutedStrong,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Spacer(),
              Container(
                decoration: BoxDecoration(
                  color: t.primaryAccentSoft.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.surface3),
                ),
                child: OutlinedButton.icon(
                  onPressed: _copyText,
                  icon: const Icon(Icons.copy_all_rounded, size: 16),
                  label: const Text('Copy'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: t.textPrimary,
                    side: BorderSide.none,
                    backgroundColor: Colors.transparent,
                    textStyle: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  t.surface1,
                  t.surface2.withValues(alpha: 0.9),
                ],
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.surface3),
              boxShadow: [
                BoxShadow(
                  color: t.primaryAccentSoft.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: t.textOnAccent.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: t.primaryAccent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Terminal View',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: t.textMutedStrong,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  _messageText,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 12.5,
                    height: 1.42,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
