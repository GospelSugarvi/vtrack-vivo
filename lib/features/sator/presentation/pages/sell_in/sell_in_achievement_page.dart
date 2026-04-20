import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class SellInAchievementPage extends StatefulWidget {
  const SellInAchievementPage({super.key});

  @override
  State<SellInAchievementPage> createState() => _SellInAchievementPageState();
}

class _SellInAchievementPageState extends State<SellInAchievementPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _isLoading = true;
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _rows = const [];
  List<Map<String, String>> _storeOptions = const [];
  String? _selectedStoreId;
  String _satorName = 'SATOR';
  late DateTime _rangeStart;
  late DateTime _rangeEnd;

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
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Sesi login tidak ditemukan');
      final userRow = await _supabase
          .from('users')
          .select('full_name, nickname')
          .eq('id', userId)
          .maybeSingle();
      final resolvedSatorName =
          '${userRow?['nickname'] ?? ''}'.trim().isNotEmpty
          ? '${userRow?['nickname'] ?? ''}'.trim()
          : ('${userRow?['full_name'] ?? ''}'.trim().isNotEmpty
                ? '${userRow?['full_name'] ?? ''}'.trim()
                : 'SATOR');

      final stores = await _loadStoreOptions();
      final response = await _supabase.rpc(
        'get_sellin_achievement',
        params: {
          'p_sator_id': userId,
          'p_view_mode': 'daily',
          'p_store_id': _selectedStoreId,
          'p_start_date': DateFormat('yyyy-MM-dd').format(_rangeStart),
          'p_end_date': DateFormat('yyyy-MM-dd').format(_rangeEnd),
        },
      );
      final payload = Map<String, dynamic>.from(response ?? const {});
      final summary = Map<String, dynamic>.from(
        payload['summary'] ?? const <String, dynamic>{},
      );
      final rows = List<Map<String, dynamic>>.from(
        payload['rows'] ?? const <Map<String, dynamic>>[],
      );

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _rows = rows;
        _storeOptions = stores;
        _satorName = resolvedSatorName;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _summary = const {};
        _rows = const [];
        _storeOptions = const [];
        _satorName = 'SATOR';
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, String>>> _loadStoreOptions() async {
    final snapshotRaw = await _supabase.rpc('get_sator_sellin_store_options');
    final snapshot = Map<String, dynamic>.from(
      (snapshotRaw as Map?) ?? const <String, dynamic>{},
    );
    final stores = <Map<String, String>>[];
    for (final raw in _parseMapList(snapshot['stores'])) {
      final storeId = raw['store_id']?.toString() ?? '';
      if (storeId.isEmpty) continue;
      stores.add({
        'store_id': storeId,
        'store_name': '${raw['store_name'] ?? 'Toko'}',
      });
    }
    return stores;
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _rowRangeLabel(Map<String, dynamic> row) {
    final start = _toDate(row['start_date']);
    if (start == null) return '-';
    return DateFormat('EEEE, d MMM yyyy', 'id_ID').format(start);
  }

  String get _pageTitle => 'Achievement Sell-In • $_satorName';
  String get _rangeLabel {
    final start = DateFormat('d MMM yy', 'id_ID').format(_rangeStart);
    final end = DateFormat('d MMM yy', 'id_ID').format(_rangeEnd);
    return '$start - $end';
  }

  String get _storeLabel {
    if ((_selectedStoreId ?? '').isEmpty) return 'Semua Toko';
    final match = _storeOptions.cast<Map<String, String>?>().firstWhere(
      (row) => row?['store_id'] == _selectedStoreId,
      orElse: () => null,
    );
    return match?['store_name'] ?? 'Toko';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(_pageTitle),
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
        surfaceTintColor: t.background,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildToolbar(),
                  const SizedBox(height: 8),
                  _buildFilterActions(),
                  const SizedBox(height: 10),
                  _buildSummaryStrip(),
                  const SizedBox(height: 12),
                  if (_rows.isEmpty)
                    _buildEmptyState()
                  else
                    ..._rows.map(_buildAchievementRow),
                ],
              ),
            ),
    );
  }

  Widget _buildToolbar() {
    return Row(
      children: [
        Expanded(
          child: _buildSelectorPill(
            icon: Icons.storefront_outlined,
            label: _storeLabel,
            onTap: _showStorePicker,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterActions() {
    return Row(
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
        const SizedBox(width: 8),
        Expanded(
          child: _buildActionChip(
            icon: Icons.calendar_month_outlined,
            label: 'Bulan Penuh',
            onTap: _showMonthPicker,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectorPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: t.textMutedStrong),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ),
            if (enabled)
              Icon(Icons.expand_more, size: 16, color: t.textMutedStrong),
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
          color: t.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: t.textMutedStrong),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _rangeLabel,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: t.textMutedStrong,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildInlineMetric(
                'Order',
                '${_toInt(_summary['total_orders'])}',
                t.primaryAccent,
              ),
              _buildDivider(),
              _buildInlineMetric(
                'Unit',
                '${_toInt(_summary['total_units'])}',
                t.success,
              ),
              _buildDivider(),
              Expanded(
                flex: 2,
                child: _buildInlineMetric(
                  'Nominal',
                  _currency.format(_toNum(_summary['total_value'])),
                  t.warning,
                  alignEnd: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInlineMetric(
    String label,
    String value,
    Color tone, {
    bool alignEnd = false,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: alignEnd
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Container(
      width: 1,
      height: 28,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: t.surface3,
    );
  }

  Future<void> _showStorePicker() async {
    final selected = await showModalBottomSheet<String?>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface1,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filter Toko',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  title: const Text('Semua Toko'),
                  trailing: (_selectedStoreId ?? '').isEmpty
                      ? Icon(
                          Icons.check_rounded,
                          size: 18,
                          color: t.primaryAccent,
                        )
                      : null,
                  onTap: () => Navigator.of(sheetContext).pop(''),
                ),
                ..._storeOptions.map(
                  (store) => ListTile(
                    dense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    title: Text(store['store_name'] ?? 'Toko'),
                    trailing: _selectedStoreId == store['store_id']
                        ? Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: t.primaryAccent,
                          )
                        : null,
                    onTap: () =>
                        Navigator.of(sheetContext).pop(store['store_id']),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    setState(() => _selectedStoreId = selected.isEmpty ? null : selected);
    await _loadData();
  }

  Future<void> _showMonthPicker() async {
    final now = DateTime.now();
    final months = List<DateTime>.generate(
      18,
      (index) => DateTime(now.year, now.month - index, 1),
    );
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface1,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pilih Bulan Penuh',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: months.length,
                    itemBuilder: (context, index) {
                      final month = months[index];
                      final selected =
                          _rangeStart.year == month.year &&
                          _rangeStart.month == month.month &&
                          _rangeStart.day == 1 &&
                          _rangeEnd.year == month.year &&
                          _rangeEnd.month == month.month;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        title: Text(
                          DateFormat('MMMM yyyy', 'id_ID').format(month),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: selected ? t.primaryAccent : t.textPrimary,
                          ),
                        ),
                        trailing: selected
                            ? Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: t.primaryAccent,
                              )
                            : null,
                        onTap: () => Navigator.of(sheetContext).pop(month),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      _rangeStart = DateTime(picked.year, picked.month, 1);
      _rangeEnd = DateTime(picked.year, picked.month + 1, 0);
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
      _rangeStart = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _rangeEnd = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _loadData();
  }

  Future<void> _setTodayRange() async {
    final today = DateTime.now();
    setState(() {
      _rangeStart = DateTime(today.year, today.month, today.day);
      _rangeEnd = DateTime(today.year, today.month, today.day);
    });
    await _loadData();
  }

  Future<void> _showAchievementDetail(Map<String, dynamic> row) async {
    final date = _toDate(row['start_date']);
    final userId = _supabase.auth.currentUser?.id;
    if (date == null || userId == null) return;

    final response = await _supabase.rpc(
      'get_sellin_achievement_day_detail',
      params: {
        'p_sator_id': userId,
        'p_period_date': DateFormat('yyyy-MM-dd').format(date),
        'p_store_id': _selectedStoreId,
      },
    );
    if (!mounted) return;
    final payload = Map<String, dynamic>.from(response ?? const {});
    final stores = List<Map<String, dynamic>>.from(
      payload['stores'] ?? const <Map<String, dynamic>>[],
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: t.surface1,
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
                    _rowRangeLabel(row),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_toInt(row['total_orders'])} order • ${_toInt(row['total_units'])} unit • ${_currency.format(_toNum(row['total_value']))}',
                    style: TextStyle(fontSize: 12, color: t.textMutedStrong),
                  ),
                  const SizedBox(height: 12),
                  if (stores.isEmpty)
                    _buildEmptyState()
                  else
                    ...stores.map(_buildDetailStoreSection),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildDetailStoreSection(Map<String, dynamic> store) {
    final items = List<Map<String, dynamic>>.from(
      store['items'] ?? const <Map<String, dynamic>>[],
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${store['store_name'] ?? 'Toko'}',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${_toInt(store['total_orders'])} order • ${_toInt(store['total_units'])} unit • ${_currency.format(_toNum(store['total_value']))}',
            style: TextStyle(fontSize: 11, color: t.textMutedStrong),
          ),
          const SizedBox(height: 8),
          ...items.map(_buildDetailItemRow),
        ],
      ),
    );
  }

  Widget _buildDetailItemRow(Map<String, dynamic> item) {
    final specs = [
      '${item['variant'] ?? ''}'.trim(),
      '${item['color'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).join(' • ');
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surface3)),
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
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                if (specs.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    specs,
                    style: TextStyle(fontSize: 11, color: t.textMutedStrong),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_toInt(item['total_qty'])} unit',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _currency.format(_toNum(item['total_value'])),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: t.primaryAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementRow(Map<String, dynamic> row) {
    return InkWell(
      onTap: () => _showAchievementDetail(row),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: t.primaryAccentSoft,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.today_outlined,
                color: t.primaryAccent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _rowRangeLabel(row),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    runSpacing: 2,
                    children: [
                      Text(
                        '${_toInt(row['total_orders'])} order',
                        style: TextStyle(
                          fontSize: 11,
                          color: t.textMutedStrong,
                        ),
                      ),
                      Text(
                        '${_toInt(row['total_units'])} unit',
                        style: TextStyle(
                          fontSize: 11,
                          color: t.textMutedStrong,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 96, maxWidth: 132),
              child: Text(
                _currency.format(_toNum(row['total_value'])),
                textAlign: TextAlign.right,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: t.primaryAccent,
                  height: 1.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          Icon(Icons.insights_outlined, size: 34, color: t.textMuted),
          const SizedBox(height: 10),
          Text(
            'Belum ada pencapaian pada periode ini.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Data akan muncul setelah order sell in difinalisasi.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: t.textMutedStrong),
          ),
        ],
      ),
    );
  }
}
