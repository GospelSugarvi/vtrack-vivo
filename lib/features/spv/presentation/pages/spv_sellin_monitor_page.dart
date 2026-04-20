import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/foundation/field_theme_extensions.dart';
import '../../../../ui/patterns/app_target_hero_card.dart';
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
  Color get _cream => t.textPrimary;
  Color get _cream2 => t.textSecondary;
  Color get _muted => t.textMuted;
  Color get _green => t.success;
  Color get _greenDim => t.successSoft;
  Color get _red => t.danger;
  Color get _blue => t.info;

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
    _syncCurrentMonthRange();
    _loadData();
  }

  void _syncCurrentMonthRange() {
    final now = DateTime.now();
    _rangeStart = DateTime(now.year, now.month, 1);
    _rangeEnd = DateTime(now.year, now.month + 1, 0);
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      _syncCurrentMonthRange();
      final spvId = _supabase.auth.currentUser?.id;
      if (spvId == null) throw Exception('Sesi login tidak ditemukan');

      final response = await _supabase.rpc(
        'get_spv_sellin_monitor',
        params: {
          'p_spv_id': spvId,
          'p_filter': 'custom',
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
                  AppTargetHeroCard(
                    title: 'Sell-in Area',
                    nominal: _toDouble(_summary['target_value']),
                    realisasi: _toDouble(_summary['actual_value']),
                    percentage: _toDouble(_summary['achievement_pct']),
                    sisa: _toDouble(_summary['gap_value']),
                    ringLabel: 'Achieve',
                    metaLeftText:
                        'Bulan berjalan · ${DateFormat('MMMM yyyy', 'id_ID').format(_rangeStart)}',
                    progressColor: _gold,
                    ringColor: _green,
                    useMetricCards: true,
                    bottomContent: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildTopStat(
                              label: 'Finalized',
                              value:
                                  '${_toInt(_summary['finalized_order_count'])} order',
                              color: _green,
                              bg: _greenDim,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildTopStat(
                              label: 'Pending',
                              value:
                                  '${_toInt(_summary['pending_order_count'])} order',
                              color: _blue,
                              bg: _blue.withValues(alpha: 0.10),
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildTopStat({
    required String label,
    required String value,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
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
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _outfit(
              size: 10,
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
    final progressValue = (achievement / 100).clamp(0.0, 1.0);
    final stores = List<Map<String, dynamic>>.from(
      row['stores'] ?? const <Map<String, dynamic>>[],
    );
    final tone = achievement >= 100
        ? _green
        : (achievement >= 70 ? _gold : _red);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_s1, t.surface2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: expanded ? tone.withValues(alpha: 0.30) : _s3,
        ),
        boxShadow: expanded
            ? [
                BoxShadow(
                  color: tone.withValues(alpha: 0.08),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: Column(
        children: [
          Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  t.background.withValues(alpha: 0),
                  tone.withValues(alpha: 0.65),
                  t.background.withValues(alpha: 0),
                ],
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () =>
                setState(() => _expandedSatorId = expanded ? null : satorId),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: tone.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '#$rank',
                              style: _outfit(
                                size: 10,
                                weight: FontWeight.w800,
                                color: tone,
                              ),
                            ),
                            Text(
                              'rank',
                              style: _outfit(size: 6.5, color: tone),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${row['sator_name'] ?? 'SATOR'}',
                                    style: _outfit(
                                      size: 12,
                                      weight: FontWeight.w800,
                                      color: _cream,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tone.withValues(alpha: 0.11),
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: tone.withValues(alpha: 0.18),
                                    ),
                                  ),
                                  child: Text(
                                    _formatPct(achievement),
                                    style: _outfit(
                                      size: 8,
                                      weight: FontWeight.w800,
                                      color: tone,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Target ${_formatMoney(_toDouble(row['target_value']))}',
                              style: _outfit(size: 8.5, color: _muted),
                            ),
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(999),
                              child: LinearProgressIndicator(
                                value: progressValue,
                                minHeight: 6,
                                backgroundColor: _s3,
                                valueColor: AlwaysStoppedAnimation<Color>(tone),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: _buildMetricMini(
                                    label: 'Actual',
                                    value: _formatMoney(
                                      _toDouble(row['actual_value']),
                                    ),
                                    valueColor: _green,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _buildMetricMini(
                                    label: 'Gap',
                                    value: _formatMoney(
                                      _toDouble(row['gap_value']),
                                    ),
                                    valueColor: _red,
                                    alignEnd: true,
                                  ),
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
                        child: _buildStatusChip(
                          label: '${_toInt(row['finalized_order_count'])} finalized',
                          color: _green,
                          background: _greenDim,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildStatusChip(
                          label: '${_toInt(row['pending_order_count'])} pending',
                          color: _blue,
                          background: _blue.withValues(alpha: 0.10),
                          alignEnd: true,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Text(
                        expanded ? 'Tutup detail toko' : 'Lihat detail toko',
                        style: _outfit(
                          size: 8.5,
                          weight: FontWeight.w700,
                          color: _muted,
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        expanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: _muted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Divider(height: 1, color: tone.withValues(alpha: 0.18)),
            ),
            if (stores.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
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
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
                  decoration: BoxDecoration(
                    color: t.surface2.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _s3),
                  ),
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
    bool alignEnd = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: t.surface2.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Column(
        crossAxisAlignment:
            alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: _outfit(
              size: 7.5,
              color: _muted,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: alignEnd ? TextAlign.right : TextAlign.left,
            style: _outfit(
              size: 9.5,
              weight: FontWeight.w800,
              color: valueColor ?? _cream,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip({
    required String label,
    required Color color,
    required Color background,
    bool alignEnd = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: alignEnd ? TextAlign.right : TextAlign.left,
        style: _outfit(
          size: 8.5,
          weight: FontWeight.w800,
          color: color,
        ),
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
