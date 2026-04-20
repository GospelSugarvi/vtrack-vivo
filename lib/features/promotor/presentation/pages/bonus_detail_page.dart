import 'dart:async';

import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/success_dialog.dart';
import '../../../../ui/patterns/patterns.dart';
import '../../../../ui/promotor/promotor.dart';

class BonusDetailPage extends StatefulWidget {
  const BonusDetailPage({super.key});

  @override
  State<BonusDetailPage> createState() => _BonusDetailPageState();
}

class _BonusDetailPageState extends State<BonusDetailPage> {
  FieldThemeTokens get t => context.fieldTokens;
  bool _isLoading = true;
  Map<String, dynamic>? _bonusSummary;
  List<Map<String, dynamic>> _transactions = <Map<String, dynamic>>[];
  DateTime _selectedMonth = DateTime.now();
  DateTime? _selectedDate;
  num _previousMonthBonus = 0;
  num _personalBonusTarget = 0;
  num _baseSalary = 0;
  Set<String> _ratioProductNames = <String>{};
  final Set<String> _expandedRatioItems = <String>{};
  String _displayName = '';
  String _storeName = '-';
  String _areaName = '';
  String _satorName = '';

  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw SessionExpiredException();

      final startDate = _selectedDate != null
          ? DateTime(
              _selectedDate!.year,
              _selectedDate!.month,
              _selectedDate!.day,
            )
          : DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final endDate = _selectedDate != null
          ? DateTime(
              _selectedDate!.year,
              _selectedDate!.month,
              _selectedDate!.day,
            )
          : DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
      final startDateStr = DateFormat('yyyy-MM-dd').format(startDate);
      final endDateStr = DateFormat('yyyy-MM-dd').format(endDate);

      final previousMonth = DateTime(
        _selectedMonth.year,
        _selectedMonth.month - 1,
        1,
      );
      final previousStart = DateFormat('yyyy-MM-dd').format(previousMonth);
      final previousEnd = DateFormat(
        'yyyy-MM-dd',
      ).format(DateTime(previousMonth.year, previousMonth.month + 1, 0));

      final results = await Future.wait([
        Supabase.instance.client
            .rpc(
              'get_promotor_bonus_summary',
              params: {
                'p_promotor_id': userId,
                'p_start_date': startDateStr,
                'p_end_date': endDateStr,
              },
            )
            .timeout(const Duration(seconds: 15)),
        Supabase.instance.client
            .rpc(
              'get_promotor_bonus_details',
              params: {
                'p_promotor_id': userId,
                'p_start_date': startDateStr,
                'p_end_date': endDateStr,
                'p_limit': 300,
                'p_offset': 0,
              },
            )
            .timeout(const Duration(seconds: 15)),
        Supabase.instance.client
            .rpc(
              'get_promotor_bonus_details_from_events',
              params: {
                'p_promotor_id': userId,
                'p_start_date': startDateStr,
                'p_end_date': endDateStr,
                'p_limit': 300,
                'p_offset': 0,
              },
            )
            .timeout(const Duration(seconds: 15)),
        Supabase.instance.client.rpc(
          'get_promotor_bonus_summary',
          params: {
            'p_promotor_id': userId,
            'p_start_date': previousStart,
            'p_end_date': previousEnd,
          },
        ),
        Supabase.instance.client
            .from('users')
            .select(
              'personal_bonus_target, full_name, nickname, area, avatar_url, base_salary',
            )
            .eq('id', userId)
            .maybeSingle(),
        Supabase.instance.client
            .from('assignments_promotor_store')
            .select('stores(store_name)')
            .eq('promotor_id', userId)
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(1),
        Supabase.instance.client
            .from('hierarchy_sator_promotor')
            .select(
              'users!hierarchy_sator_promotor_sator_id_fkey(full_name, nickname)',
            )
            .eq('promotor_id', userId)
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(1),
        () async {
          try {
            final rows = await Supabase.instance.client
                .from('bonus_rules')
                .select('products(series, model_name)')
                .eq('bonus_type', 'ratio');
            return List<Map<String, dynamic>>.from(rows);
          } catch (_) {
            return <Map<String, dynamic>>[];
          }
        }(),
      ]);

      final summary = results[0];
      final details = results[1];
      final detailEvents = results[2];
      final prevSummary = results[3];
      final userRow = results[4] as Map<String, dynamic>?;
      final storeRows = List<Map<String, dynamic>>.from(results[5] as List);
      final hierarchyRows = List<Map<String, dynamic>>.from(results[6] as List);
      final ratioRuleRows = List<Map<String, dynamic>>.from(results[7] as List);
      final detailRows = details is List
          ? List<Map<String, dynamic>>.from(details)
          : <Map<String, dynamic>>[];
      final eventRows = detailEvents is List
          ? List<Map<String, dynamic>>.from(detailEvents)
          : <Map<String, dynamic>>[];
      final eventByTransactionId = {
        for (final row in eventRows)
          '${row['sales_sell_out_id'] ?? row['transaction_id'] ?? ''}': row,
      };
      final storeRow = storeRows.isNotEmpty ? storeRows.first : null;
      final hierarchyRow = hierarchyRows.isNotEmpty
          ? hierarchyRows.first
          : null;
      final nickname = (userRow?['nickname'] ?? '').toString().trim();
      final fullName = (userRow?['full_name'] ?? '').toString().trim();
      final metadata =
          Supabase.instance.client.auth.currentUser?.userMetadata ?? const {};
      final authFullName = (metadata['full_name'] ?? '').toString().trim();
      final authName = (metadata['name'] ?? '').toString().trim();
      final authDisplayName = (metadata['display_name'] ?? '')
          .toString()
          .trim();
      final authUsername = (metadata['username'] ?? '').toString().trim();
      final authEmail =
          Supabase.instance.client.auth.currentUser?.email
              ?.split('@')
              .first
              .toString()
              .trim() ??
          '';
      final satorUser = hierarchyRow?['users'] is Map
          ? Map<String, dynamic>.from(hierarchyRow!['users'] as Map)
          : null;
      final satorNickname = (satorUser?['nickname'] ?? '').toString().trim();
      final satorFullName = (satorUser?['full_name'] ?? '').toString().trim();
      final ratioProductNames = <String>{
        for (final row in ratioRuleRows)
          if (row['products'] is Map)
            ...{
              '${row['products']?['series'] ?? ''} ${row['products']?['model_name'] ?? ''}'
                  .trim(),
              '${row['products']?['model_name'] ?? ''}'.trim(),
            }.where((value) => value.isNotEmpty),
      };
      if (!mounted) return;
      setState(() {
        _bonusSummary = summary is Map<String, dynamic>
            ? Map<String, dynamic>.from(summary)
            : <String, dynamic>{};
        _transactions = detailRows.map((row) {
          final transactionId = '${row['transaction_id'] ?? ''}';
          final event = eventByTransactionId[transactionId];
          return <String, dynamic>{...row, if (event != null) ...event};
        }).toList();
        _previousMonthBonus = _toNum(
          prevSummary is Map<String, dynamic> ? prevSummary['total_bonus'] : 0,
        );
        _personalBonusTarget = _toNum(userRow?['personal_bonus_target']);
        _baseSalary = _toNum(userRow?['base_salary']);
        _ratioProductNames = ratioProductNames;
        _displayName =
            [
              nickname,
              fullName,
              authFullName,
              authName,
              authDisplayName,
              authUsername,
              authEmail,
            ].firstWhere(
              (value) =>
                  value.isNotEmpty && value.toLowerCase().trim() != 'promotor',
              orElse: () => authEmail,
            );
        _storeName = '${storeRow?['stores']?['store_name'] ?? '-'}';
        _areaName = '${userRow?['area'] ?? ''}'.trim();
        _satorName = satorNickname.isNotEmpty ? satorNickname : satorFullName;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      final exception = ErrorHandler.handleError(e);
      ErrorHandler.showErrorDialog(context, exception, onRetry: _loadData);
      setState(() => _isLoading = false);
    }
  }

  bool _isRatioTransaction(Map<String, dynamic> item) {
    final productName = '${item['product_name'] ?? item['model_name'] ?? ''}'
        .trim();
    final bonusType = '${item['bonus_type'] ?? ''}'.trim().toLowerCase();
    return bonusType == 'ratio' ||
        _ratioProductNames.contains(productName) ||
        _ratioProductNames.any(
          (ratioName) =>
              ratioName.isNotEmpty && productName.endsWith(ratioName),
        );
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              color: t.primaryAccent,
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  _buildHeader(),
                  _buildMonthRow(),
                  _buildHeroCard(),
                  const SizedBox(height: 12),
                  _buildTransactions(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final storeLine = _storeName.isNotEmpty && _storeName != '-'
        ? _storeName
        : '';
    final areaLine = _areaName.isNotEmpty && _areaName != 'null'
        ? _areaName
        : '';
    final satorLine = _satorName.isNotEmpty && _satorName != 'null'
        ? 'Sator: $_satorName'
        : '';

    return AppSafeHeader(
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: InkWell(
              onTap: () => Navigator.of(context).pop(),
              borderRadius: BorderRadius.circular(999),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: t.surface1,
                  shape: BoxShape.circle,
                  border: Border.all(color: t.surface3),
                ),
                child: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 14,
                  color: t.textSecondary,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 44),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  'Detail Bonus',
                  textAlign: TextAlign.center,
                  style: PromotorText.display(size: 24, color: t.textPrimary),
                ),
                if (_displayName.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    _displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                  ),
                ],
                if (storeLine.isNotEmpty || areaLine.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 4,
                    runSpacing: 2,
                    children: [
                      if (storeLine.isNotEmpty)
                        Text(
                          storeLine,
                          style: PromotorText.outfit(
                            size: 12,
                            weight: FontWeight.w700,
                            color: t.primaryAccent,
                          ),
                        ),
                      if (areaLine.isNotEmpty)
                        Text(
                          areaLine,
                          style: PromotorText.outfit(
                            size: 12,
                            weight: FontWeight.w700,
                            color: t.primaryAccent,
                          ),
                        ),
                    ],
                  ),
                ],
                if (satorLine.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.center,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: t.primaryAccentSoft,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: t.primaryAccent.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_pin_circle_rounded,
                            size: 14,
                            color: t.primaryAccent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            satorLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PromotorText.outfit(
                              size: 11,
                              weight: FontWeight.w700,
                              color: t.primaryAccent,
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildMonthRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.surface3),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                      1,
                    );
                    _selectedDate = null;
                  });
                  _loadData();
                },
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.chevron_left,
                  color: t.textSecondary,
                  size: 18,
                ),
              ),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth),
                      textAlign: TextAlign.center,
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: _pickDateFilter,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: t.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: t.surface3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              size: 14,
                              color: t.primaryAccent,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                _selectedDate == null
                                    ? 'Semua tanggal'
                                    : DateFormat(
                                        'd MMMM yyyy',
                                        'id_ID',
                                      ).format(_selectedDate!),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PromotorText.outfit(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: _selectedDate == null
                                      ? t.textSecondary
                                      : t.textPrimary,
                                ),
                              ),
                            ),
                            if (_selectedDate != null) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: () {
                                  setState(() => _selectedDate = null);
                                  _loadData();
                                },
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: t.textMuted,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                      1,
                    );
                    _selectedDate = null;
                  });
                  _loadData();
                },
                visualDensity: VisualDensity.compact,
                icon: Icon(
                  Icons.chevron_right,
                  color: t.textSecondary,
                  size: 18,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDateFilter() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? _selectedMonth,
      firstDate: DateTime(_selectedMonth.year, _selectedMonth.month, 1),
      lastDate: DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0),
      locale: const Locale('id', 'ID'),
    );

    if (picked == null || !mounted) return;
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
      _selectedMonth = DateTime(picked.year, picked.month, 1);
    });
    await _loadData();
  }

  Widget _buildHeroCard() {
    final summary = _bonusSummary ?? <String, dynamic>{};
    final totalBonus = _toNum(summary['total_bonus']);
    final totalIncome = _baseSalary + totalBonus;
    final totalUnits = _toNum(summary['total_sales']).toInt();
    final achievementPct = _personalBonusTarget > 0
        ? (totalBonus / _personalBonusTarget) * 100
        : 0.0;
    final remainingBonus = (_personalBonusTarget - totalBonus) > 0
        ? (_personalBonusTarget - totalBonus)
        : 0;
    final metaItems = <Map<String, String>>[
      {
        'label': 'Gaji Tetap',
        'value': _currencyFormat.format(_baseSalary),
      },
      {
        'label': 'Total Pendapatan',
        'value': _currencyFormat.format(totalIncome),
      },
      {
        'label': 'Persentase',
        'value': '${achievementPct.toStringAsFixed(1)}%',
      },
      {
        'label': 'Kekurangan',
        'value': _currencyFormat.format(remainingBonus),
      },
      {
        'label': 'Target Bonus',
        'value': _currencyFormat.format(_personalBonusTarget),
      },
      {
        'label': 'Unit Terjual',
        'value': NumberFormat.decimalPattern('id_ID').format(totalUnits),
      },
      {
        'label': 'Bulan Lalu',
        'value': _currencyFormat.format(_previousMonthBonus),
      },
    ];

    return PromotorCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _currencyFormat.format(totalBonus),
            style: PromotorText.display(size: 28, color: t.textPrimary),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.surface3),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const spacing = 8.0;
                final itemWidth = (constraints.maxWidth - spacing) / 2;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: metaItems.asMap().entries.map((entry) {
                    final index = entry.key;
                    final item = entry.value;
                    final isLastOddItem =
                        metaItems.length.isOdd && index == metaItems.length - 1;
                    return SizedBox(
                      width: isLastOddItem ? constraints.maxWidth : itemWidth,
                      child: _buildHeroMeta(
                        item['label'] ?? '-',
                        item['value'] ?? '-',
                      ),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              onPressed: _showBonusTargetDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primaryAccent,
                foregroundColor: t.textOnAccent,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Atur Target',
                  maxLines: 1,
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.textOnAccent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactions() {
    if (_transactions.isEmpty) {
      final emptyMessage = _selectedDate != null
          ? 'Tidak ada penjualan di hari ini.'
          : 'Belum ada transaksi bonus di bulan ini.';
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            emptyMessage,
            style: PromotorText.outfit(size: 12, color: t.textSecondary),
          ),
        ),
      );
    }
    final ratioPairs = _buildRatioPairItems();
    final regularTransactions = _transactions
        .where((item) => !_isRatioTransaction(item))
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (regularTransactions.isNotEmpty) ...[
            Text(
              ratioPairs.isNotEmpty ? 'Transaksi Lainnya' : 'Transaksi',
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: 10),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: regularTransactions.length,
              separatorBuilder: (context, index) =>
                  Divider(height: 1, color: t.surface3),
              itemBuilder: (context, index) {
                final item = regularTransactions[index];
                final title =
                    '${item['product_name'] ?? item['model_name'] ?? 'Transaksi'}';
                final subtitle = '${item['bonus_type'] ?? 'Bonus'}';
                final trxDate = item['transaction_date']?.toString();
                final dateLabel = trxDate == null || trxDate.isEmpty
                    ? ''
                    : DateFormat(
                        'd MMM yyyy',
                        'id_ID',
                      ).format(DateTime.parse(trxDate));
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
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
                                color: t.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              dateLabel.isEmpty
                                  ? subtitle
                                  : '$subtitle • $dateLabel',
                              style: PromotorText.outfit(
                                size: 11,
                                weight: FontWeight.w600,
                                color: t.textMuted,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'IMEI ${item['serial_imei'] ?? '-'}',
                              style: PromotorText.outfit(
                                size: 10,
                                weight: FontWeight.w600,
                                color: t.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        _currencyFormat.format(
                          _toNum(item['bonus_amount'] ?? item['bonus']),
                        ),
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.primaryAccent,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          if (ratioPairs.isNotEmpty) ...[
            if (regularTransactions.isNotEmpty) const SizedBox(height: 16),
            Text(
              'Rasio 2 Unit = 1 Bonus',
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...ratioPairs.map(_buildRatioPairCard),
          ],
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildRatioPairItems() {
    final groups = <String, List<Map<String, dynamic>>>{};
    final groupMeta = <String, Map<String, dynamic>>{};
    for (final item in _transactions) {
      if (!_isRatioTransaction(item)) continue;
      final title = '${item['product_name'] ?? item['model_name'] ?? 'Produk'}';
      final trxDate = DateTime.tryParse('${item['transaction_date'] ?? ''}');
      final monthKey = trxDate == null
          ? 'unknown'
          : '${trxDate.year}-${trxDate.month.toString().padLeft(2, '0')}';
      final key = '$title|$monthKey';
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(item);
      groupMeta.putIfAbsent(
        key,
        () => <String, dynamic>{
          'title': title,
          'month_label': trxDate == null
              ? ''
              : DateFormat(
                  'MMMM yyyy',
                  'id_ID',
                ).format(DateTime(trxDate.year, trxDate.month)),
        },
      );
    }

    final result = <Map<String, dynamic>>[];
    for (final entry in groups.entries) {
      final rows = entry.value.reversed.toList();
      final meta = groupMeta[entry.key] ?? const <String, dynamic>{};

      for (var i = 0; i < rows.length; i += 2) {
        final second = i + 1 < rows.length ? rows[i + 1] : null;
        final pairRows = rows.sublist(i, second == null ? i + 1 : i + 2);
        final latestDate = pairRows
            .map((row) => DateTime.tryParse('${row['transaction_date'] ?? ''}'))
            .whereType<DateTime>()
            .fold<DateTime?>(null, (latest, current) {
              if (latest == null) return current;
              return current.isAfter(latest) ? current : latest;
            });
        result.add(<String, dynamic>{
          'title': meta['title'] ?? entry.key,
          'month_label': meta['month_label'] ?? '',
          'rows': pairRows,
          'is_complete': second != null,
          'pair_id':
              '${meta['title'] ?? entry.key}-${meta['month_label'] ?? ''}-${pairRows.map((row) => row['transaction_id'] ?? row['sales_sell_out_id'] ?? '').join('-')}',
          'total_bonus': pairRows.fold<num>(
            0,
            (sum, row) => sum + _toNum(row['bonus_amount'] ?? row['bonus']),
          ),
          'latest_date': latestDate,
        });
      }
    }

    result.sort((a, b) {
      final aDate = a['latest_date'] as DateTime?;
      final bDate = b['latest_date'] as DateTime?;
      if (aDate == null || bDate == null) return 0;
      return bDate.compareTo(aDate);
    });
    return result;
  }

  Widget _buildRatioPairCard(Map<String, dynamic> pair) {
    final rows = List<Map<String, dynamic>>.from(pair['rows'] as List);
    final totalBonus = _toNum(pair['total_bonus']);
    final isComplete = pair['is_complete'] == true;
    final pairId = '${pair['pair_id'] ?? pair['title'] ?? ''}';
    final isExpanded = _expandedRatioItems.contains(pairId);
    final statusLabel = isComplete ? 'Sudah Jadi Bonus' : 'Menunggu Pasangan';
    final statusColor = isComplete ? t.success : t.warning;
    final summaryText = isComplete
        ? '2 unit ini sudah digabung menjadi 1 bonus'
        : 'Baru 1 unit, belum genap 2 unit';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedRatioItems.remove(pairId);
            } else {
              _expandedRatioItems.add(pairId);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(10),
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
                          '${pair['title'] ?? 'Produk Ratio'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PromotorText.outfit(
                            size: 12,
                            weight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          summaryText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PromotorText.outfit(
                            size: 10,
                            weight: FontWeight.w600,
                            color: t.textSecondary,
                          ),
                        ),
                        if ('${pair['month_label'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            '${pair['month_label']}',
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        isComplete && totalBonus > 0
                            ? _currencyFormat.format(totalBonus)
                            : '-',
                        style: PromotorText.outfit(
                          size: 12,
                          weight: FontWeight.w700,
                          color: isComplete && totalBonus > 0
                              ? t.primaryAccent
                              : t.textMuted,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: t.textMuted,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildRatioInfoChip(
                      isComplete ? '2 unit = 1 bonus' : '1 unit tersimpan',
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: statusColor.withValues(alpha: 0.24),
                        ),
                      ),
                      child: Text(
                        statusLabel,
                        textAlign: TextAlign.center,
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w700,
                          color: statusColor,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (isExpanded) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    children: rows.map((row) {
                      final trxDate = row['transaction_date']?.toString();
                      final imei = '${row['serial_imei'] ?? '-'}';
                      final dateLabel = trxDate == null || trxDate.isEmpty
                          ? '-'
                          : DateFormat(
                              'd MMM yyyy',
                              'id_ID',
                            ).format(DateTime.parse(trxDate));
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${row['product_name'] ?? row['model_name'] ?? '-'}',
                                    style: PromotorText.outfit(
                                      size: 10,
                                      weight: FontWeight.w700,
                                      color: t.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'IMEI $imei',
                                    style: PromotorText.outfit(
                                      size: 10,
                                      weight: FontWeight.w600,
                                      color: t.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    dateLabel,
                                    style: PromotorText.outfit(
                                      size: 10,
                                      weight: FontWeight.w600,
                                      color: t.textMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _currencyFormat.format(
                                _toNum(row['bonus_amount'] ?? row['bonus']),
                              ),
                              style: PromotorText.outfit(
                                size: 10,
                                weight: FontWeight.w700,
                                color:
                                    _toNum(
                                          row['bonus_amount'] ?? row['bonus'],
                                        ) >
                                        0
                                    ? t.primaryAccent
                                    : t.textMuted,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRatioInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 10,
          weight: FontWeight.w700,
          color: t.textSecondary,
        ),
      ),
    );
  }

  Widget _buildHeroMeta(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
              size: 9,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            height: 18,
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showBonusTargetDialog() {
    final currentTarget = _personalBonusTarget.toInt();
    final controller = TextEditingController(
      text: _formatDigitsWithSeparator(currentTarget),
    );

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'Target Bonus Anda',
          style: PromotorText.outfit(
            size: 14,
            weight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Berapa target bonus yang ingin Anda capai bulan ini?',
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w600,
                color: t.textMuted,
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: t.textPrimary,
              ),
              decoration: InputDecoration(
                labelText: 'Target Bonus',
                prefixText: 'Rp ',
                border: const OutlineInputBorder(),
                hintText: 'Contoh: 500.000',
                labelStyle: PromotorText.outfit(
                  size: 12,
                  weight: FontWeight.w600,
                  color: t.textMuted,
                ),
              ),
              onChanged: (value) {
                final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
                final number = int.tryParse(digitsOnly) ?? 0;
                final formatted = _formatDigitsWithSeparator(number);
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
              runSpacing: 8,
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
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Batal',
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w700,
                color: t.textMuted,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount =
                  int.tryParse(
                    controller.text.replaceAll(RegExp(r'[^0-9]'), ''),
                  ) ??
                  0;
              Navigator.of(dialogContext).pop();
              await _savePersonalBonusTarget(amount);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: t.primaryAccent,
              foregroundColor: t.textOnAccent,
            ),
            child: Text(
              'Simpan',
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w700,
                color: t.textOnAccent,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAmountChip(TextEditingController controller, int amount) {
    return ActionChip(
      label: Text(
        _currencyFormat.format(amount),
        style: PromotorText.outfit(
          size: 11,
          weight: FontWeight.w700,
          color: t.primaryAccent,
        ),
      ),
      onPressed: () => controller.text = _formatDigitsWithSeparator(amount),
    );
  }

  Future<void> _savePersonalBonusTarget(int amount) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw SessionExpiredException();

      await Supabase.instance.client.rpc(
        'update_personal_bonus_target',
        params: {'p_user_id': userId, 'p_target_amount': amount},
      );

      if (!mounted) return;
      setState(() => _personalBonusTarget = amount);
      await showSuccessDialog(
        context,
        title: amount > 0 ? 'Target Berhasil Disimpan' : 'Target Dihapus',
        message: amount > 0
            ? 'Target bonus pribadi Anda telah diperbarui'
            : 'Target bonus pribadi telah dihapus',
      );
    } catch (e) {
      if (!mounted) return;
      final exception = ErrorHandler.handleError(e);
      ErrorHandler.showErrorDialog(context, exception);
    }
  }

  String _formatDigitsWithSeparator(int value) {
    return NumberFormat.decimalPattern('id_ID').format(value);
  }
}
