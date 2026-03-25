import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/foundation/field_theme_extensions.dart';
import '../../../../ui/promotor/promotor.dart';

class SpvSellInMonitorPage extends StatefulWidget {
  const SpvSellInMonitorPage({super.key});

  @override
  State<SpvSellInMonitorPage> createState() => _SpvSellInMonitorPageState();
}

class _SpvSellInMonitorPageState extends State<SpvSellInMonitorPage> {
  final _supabase = Supabase.instance.client;
  final _compactCurrency = NumberFormat.compactCurrency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _isLoading = true;
  String _selectedFilter = 'today';
  String? _expandedSatorId;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  Map<String, dynamic> _range = const {};
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _sators = const [];

  FieldThemeTokens get t => context.fieldTokens;
  Color get _s1 => t.surface1;
  Color get _s3 => t.surface3;
  Color get _gold => t.primaryAccent;
  Color get _goldDim => t.primaryAccentSoft;
  Color get _cream => t.textPrimary;
  Color get _cream2 => t.textSecondary;
  Color get _muted => t.textMuted;
  Color get _green => t.success;
  Color get _greenDim => t.successSoft;
  Color get _red => t.danger;
  Color get _redDim => t.dangerSoft;
  Color get _blue => t.info;

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

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _rangeStart = DateTime(now.year, now.month, now.day);
    _rangeEnd = DateTime(now.year, now.month, now.day);
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final spvId = _supabase.auth.currentUser?.id;
      if (spvId == null) throw Exception('Sesi login tidak ditemukan');

      final response = await _supabase.rpc(
        'get_spv_sellin_monitor',
        params: {
          'p_spv_id': spvId,
          'p_filter': _selectedFilter,
          'p_start_date': DateFormat('yyyy-MM-dd').format(_rangeStart),
          'p_end_date': DateFormat('yyyy-MM-dd').format(_rangeEnd),
        },
      );

      final payload = Map<String, dynamic>.from(response ?? const {});
      final sators = List<Map<String, dynamic>>.from(
        payload['sators'] ?? const <Map<String, dynamic>>[],
      );

      if (!mounted) return;
      setState(() {
        _range = Map<String, dynamic>.from(
          payload['range'] ?? const <String, dynamic>{},
        );
        _summary = Map<String, dynamic>.from(
          payload['summary'] ?? const <String, dynamic>{},
        );
        _sators = sators;
        final activeIds = sators.map((row) => '${row['sator_id']}').toSet();
        if (_expandedSatorId == null && sators.isNotEmpty) {
          _expandedSatorId = '${sators.first['sator_id']}';
        } else if (!activeIds.contains(_expandedSatorId)) {
          _expandedSatorId = sators.isEmpty
              ? null
              : '${sators.first['sator_id']}';
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _range = const {};
        _summary = const {};
        _sators = const [];
        _expandedSatorId = null;
        _isLoading = false;
      });
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  String _formatMoney(num value) => _compactCurrency.format(value);

  String _formatPct(double value) => '${value.toStringAsFixed(1)}%';

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _filterLabel(String filter) {
    switch (filter) {
      case 'custom':
        return 'Rentang tanggal';
      case 'today':
      default:
        return 'Hari ini';
    }
  }

  Future<void> _setTodayRange() async {
    final now = DateTime.now();
    setState(() {
      _selectedFilter = 'today';
      _rangeStart = DateTime(now.year, now.month, now.day);
      _rangeEnd = DateTime(now.year, now.month, now.day);
    });
    await _loadData();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      helpText: 'Pilih Rentang Tanggal',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedFilter = 'custom';
      _rangeStart = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _rangeEnd = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _loadData();
  }

  Future<void> _showStoreOrders({
    required String satorId,
    required String satorName,
    required Map<String, dynamic> store,
  }) async {
    final storeId = '${store['store_id'] ?? ''}';
    if (storeId.isEmpty) return;

    final spvId = _supabase.auth.currentUser?.id;
    if (spvId == null) return;

    final response = await _supabase.rpc(
      'get_spv_sellin_store_orders',
      params: {
        'p_spv_id': spvId,
        'p_sator_id': satorId,
        'p_store_id': storeId,
        'p_start_date': DateFormat('yyyy-MM-dd').format(_rangeStart),
        'p_end_date': DateFormat('yyyy-MM-dd').format(_rangeEnd),
      },
    );
    if (!mounted) return;

    final payload = Map<String, dynamic>.from(response ?? const {});
    final orders = List<Map<String, dynamic>>.from(
      payload['orders'] ?? const <Map<String, dynamic>>[],
    );
    final storeMeta = Map<String, dynamic>.from(
      payload['store'] ?? const <String, dynamic>{},
    );
    final rangeMeta = Map<String, dynamic>.from(
      payload['range'] ?? const <String, dynamic>{},
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: _s1,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.72,
            minChildSize: 0.48,
            maxChildSize: 0.92,
            builder: (context, controller) {
              return ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  Text(
                    '${storeMeta['store_name'] ?? store['store_name'] ?? 'Toko'}',
                    style: _outfit(
                      size: 14,
                      weight: FontWeight.w800,
                      color: _cream,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$satorName · ${rangeMeta['label'] ?? _range['label'] ?? '-'}',
                    style: _outfit(size: 10, color: _muted),
                  ),
                  const SizedBox(height: 12),
                  if (orders.isEmpty)
                    _buildEmptyState(
                      message:
                          'Belum ada order toko ini pada periode tersebut.',
                    )
                  else
                    ...orders.map(_buildOrderCard),
                ],
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.shellBackground,
      appBar: AppBar(
        backgroundColor: t.shellBackground,
        foregroundColor: _cream,
        title: const Text('Monitor Sell-In'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gold))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _gold,
              backgroundColor: _s1,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionChip(
                          icon: Icons.today_outlined,
                          label: 'Hari Ini',
                          onTap: _setTodayRange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildActionChip(
                          icon: Icons.date_range_outlined,
                          label: 'Rentang Tanggal',
                          onTap: _pickDateRange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    decoration: BoxDecoration(
                      color: _s1,
                      border: Border.all(color: _s3),
                      borderRadius: BorderRadius.circular(16),
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
                                  Text(
                                    'Sell-in area',
                                    style: _outfit(
                                      size: 12,
                                      weight: FontWeight.w800,
                                      color: _cream,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${_filterLabel(_selectedFilter)} · ${_range['label'] ?? '-'}',
                                    style: _outfit(size: 9, color: _muted),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 7,
                              ),
                              decoration: BoxDecoration(
                                color: _greenDim,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _green.withValues(alpha: 0.18),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _formatPct(
                                      _toDouble(_summary['achievement_pct']),
                                    ),
                                    style: _display(
                                      size: 16,
                                      weight: FontWeight.w800,
                                      color: _green,
                                    ),
                                  ),
                                  Text(
                                    'achievement',
                                    style: _outfit(size: 7, color: _green),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTopStat(
                                label: 'Target',
                                value: _formatMoney(
                                  _toDouble(_summary['target_value']),
                                ),
                                color: _gold,
                                bg: _goldDim,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildTopStat(
                                label: 'Actual',
                                value: _formatMoney(
                                  _toDouble(_summary['actual_value']),
                                ),
                                color: _green,
                                bg: _greenDim,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Expanded(
                              child: _buildTopStat(
                                label: 'Sisa',
                                value: _formatMoney(
                                  _toDouble(_summary['gap_value']),
                                ),
                                color: _red,
                                bg: _redDim,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildTopStat(
                                label: 'Order',
                                value:
                                    '${_toInt(_summary['finalized_order_count'])} final · ${_toInt(_summary['pending_order_count'])} pending',
                                color: _blue,
                                bg: _blue.withValues(alpha: 0.10),
                                compact: true,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Ranking SATOR',
                    style: _outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: _cream2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_sators.isEmpty)
                    _buildEmptyState()
                  else
                    ..._sators.asMap().entries.map(
                      (entry) => _buildSatorCard(
                        rank: entry.key + 1,
                        row: entry.value,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _s1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _s3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: _muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _outfit(
                  size: 11.5,
                  weight: FontWeight.w700,
                  color: _cream,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopStat({
    required String label,
    required String value,
    required Color color,
    required Color bg,
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.fromLTRB(10, compact ? 8 : 9, 10, compact ? 8 : 9),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 7, color: color)),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: compact ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: _outfit(
              size: compact ? 8 : 10,
              weight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSatorCard({
    required int rank,
    required Map<String, dynamic> row,
  }) {
    final satorId = '${row['sator_id'] ?? ''}';
    final expanded = _expandedSatorId == satorId;
    final achievement = _toDouble(row['achievement_pct']);
    final stores = List<Map<String, dynamic>>.from(
      row['stores'] ?? const <Map<String, dynamic>>[],
    );
    final tone = achievement >= 100
        ? _green
        : (achievement >= 70 ? _gold : _red);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? tone.withValues(alpha: 0.28) : _s3,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () =>
                setState(() => _expandedSatorId = expanded ? null : satorId),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$rank',
                          style: _outfit(
                            size: 10,
                            weight: FontWeight.w800,
                            color: tone,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${row['sator_name'] ?? 'SATOR'}',
                              style: _outfit(
                                size: 11,
                                weight: FontWeight.w800,
                                color: _cream,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${_toInt(row['finalized_order_count'])} finalized · ${_toInt(row['pending_order_count'])} pending',
                              style: _outfit(size: 8, color: _muted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _formatPct(achievement),
                            style: _outfit(
                              size: 10,
                              weight: FontWeight.w800,
                              color: tone,
                            ),
                          ),
                          Text(
                            expanded ? 'Tutup' : 'Detail toko',
                            style: _outfit(size: 7, color: _muted),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricMini(
                          label: 'Target',
                          value: _formatMoney(_toDouble(row['target_value'])),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildMetricMini(
                          label: 'Actual',
                          value: _formatMoney(_toDouble(row['actual_value'])),
                          valueColor: _green,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildMetricMini(
                          label: 'Gap',
                          value: _formatMoney(_toDouble(row['gap_value'])),
                          valueColor: _red,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: _s3),
            if (stores.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Belum ada toko dengan activity sell-in pada periode ini.',
                    style: _outfit(size: 9, color: _muted),
                  ),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daftar toko',
                      style: _outfit(
                        size: 10,
                        weight: FontWeight.w800,
                        color: _cream2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...stores.map((store) => _buildStoreRow(row, store)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricMini({
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 7, 9, 7),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(10),
      ),
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
              size: 9,
              weight: FontWeight.w800,
              color: valueColor ?? _cream,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreRow(
    Map<String, dynamic> satorRow,
    Map<String, dynamic> storeRow,
  ) {
    final actualValue = _toDouble(storeRow['actual_value']);
    final contribution = _toDouble(storeRow['contribution_pct']);
    final pendingCount = _toInt(storeRow['pending_order_count']);
    final finalizedCount = _toInt(storeRow['finalized_order_count']);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => _showStoreOrders(
        satorId: '${satorRow['sator_id'] ?? ''}',
        satorName: '${satorRow['sator_name'] ?? 'SATOR'}',
        store: storeRow,
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _s3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${storeRow['store_name'] ?? 'Toko'}',
                    style: _outfit(
                      size: 10,
                      weight: FontWeight.w700,
                      color: _cream,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatMoney(actualValue)} · ${_formatPct(contribution)} kontribusi',
                    style: _outfit(size: 8, color: _muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$finalizedCount final',
                  style: _outfit(
                    size: 8,
                    color: _green,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$pendingCount pending',
                  style: _outfit(
                    size: 8,
                    color: pendingCount > 0 ? _gold : _muted,
                    weight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 16, color: _muted),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final items = List<Map<String, dynamic>>.from(
      order['items'] ?? const <Map<String, dynamic>>[],
    );
    final status = '${order['status'] ?? '-'}';
    final statusTone = switch (status) {
      'finalized' => _green,
      'pending' => _gold,
      'cancelled' => _red,
      _ => _muted,
    };
    final orderDate = _toDate(order['order_date']);
    final finalizedAt = _toDate(order['finalized_at']);
    final cancelledAt = _toDate(order['cancelled_at']);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
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
                    Text(
                      orderDate == null
                          ? 'Order'
                          : DateFormat('d MMM yyyy', 'id_ID').format(orderDate),
                      style: _outfit(
                        size: 11,
                        weight: FontWeight.w800,
                        color: _cream,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${order['source'] ?? '-'} · ${_toInt(order['total_qty'])} unit · ${_currency.format(_toDouble(order['total_value']))}',
                      style: _outfit(size: 8, color: _muted),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusTone.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusTone.withValues(alpha: 0.16)),
                ),
                child: Text(
                  status,
                  style: _outfit(
                    size: 7,
                    weight: FontWeight.w800,
                    color: statusTone,
                  ),
                ),
              ),
            ],
          ),
          if (finalizedAt != null ||
              cancelledAt != null ||
              '${order['notes'] ?? ''}'.trim().isNotEmpty ||
              '${order['cancellation_reason'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (finalizedAt != null)
                  'Final ${DateFormat('d MMM HH:mm', 'id_ID').format(finalizedAt)}',
                if (cancelledAt != null)
                  'Batal ${DateFormat('d MMM HH:mm', 'id_ID').format(cancelledAt)}',
                if ('${order['cancellation_reason'] ?? ''}'.trim().isNotEmpty)
                  '${order['cancellation_reason']}',
                if ('${order['notes'] ?? ''}'.trim().isNotEmpty)
                  '${order['notes']}',
              ].join(' · '),
              style: _outfit(size: 8, color: _muted),
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...items.map(_buildOrderItemRow),
          ],
        ],
      ),
    );
  }

  Widget _buildOrderItemRow(Map<String, dynamic> item) {
    final specs = [
      '${item['variant'] ?? ''}'.trim(),
      '${item['color'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).join(' · ');

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 7),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _s3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['product_name'] ?? 'Produk'}',
                  style: _outfit(
                    size: 9,
                    weight: FontWeight.w700,
                    color: _cream,
                  ),
                ),
                if (specs.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(specs, style: _outfit(size: 8, color: _muted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_toInt(item['qty'])} unit',
                style: _outfit(size: 8, weight: FontWeight.w800, color: _cream),
              ),
              const SizedBox(height: 2),
              Text(
                _currency.format(_toDouble(item['subtotal'])),
                style: _outfit(size: 8, weight: FontWeight.w700, color: _gold),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({String? message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Text(
        message ?? 'Belum ada data sell-in untuk periode ini.',
        style: _outfit(size: 10, color: _muted),
      ),
    );
  }
}
