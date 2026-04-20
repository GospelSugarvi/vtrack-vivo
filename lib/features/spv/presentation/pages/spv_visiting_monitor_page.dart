import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../ui/promotor/promotor.dart';

class SpvVisitingMonitorPage extends StatefulWidget {
  final String initialTab;
  final String? initialSatorId;
  final String? highlightedStoreId;
  final DateTime? initialMonth;
  final DateTime? initialDay;

  const SpvVisitingMonitorPage({
    super.key,
    this.initialTab = 'scope',
    this.initialSatorId,
    this.highlightedStoreId,
    this.initialMonth,
    this.initialDay,
  });

  @override
  State<SpvVisitingMonitorPage> createState() => _SpvVisitingMonitorPageState();
}

class _SpvVisitingMonitorPageState extends State<SpvVisitingMonitorPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  late DateTime _selectedMonth;
  DateTime? _selectedDay;
  List<Map<String, dynamic>> _rows = const [];
  String? _selectedSatorId;
  String? _highlightedStoreId;
  String _query = '';
  String _activeTab = 'scope';

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final initialMonth = widget.initialMonth ?? now;
    _selectedMonth = DateTime(initialMonth.year, initialMonth.month);
    final initialDay = widget.initialDay;
    _selectedDay = initialDay == null
        ? DateTime(now.year, now.month, now.day)
        : DateTime(initialDay.year, initialDay.month, initialDay.day);
    _activeTab = widget.initialTab == 'visited' ? 'visited' : 'scope';
    _selectedSatorId = widget.initialSatorId?.trim();
    _highlightedStoreId = widget.highlightedStoreId?.trim();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final snapshotRaw = await _supabase.rpc(
        'get_spv_visiting_monitor_snapshot',
        params: {
          'p_date': DateFormat(
            'yyyy-MM-dd',
          ).format(_selectedDay ?? _selectedMonth),
        },
      );
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final rows = _parseMapList(snapshot['rows']);

      if (!mounted) return;
      setState(() {
        _rows = rows;
        final hasSelected = rows.any(
          (row) => '${row['sator_id']}' == _selectedSatorId,
        );
        _selectedSatorId = hasSelected
            ? _selectedSatorId
            : (rows.isNotEmpty ? '${rows.first['sator_id']}' : null);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _selectedSatorId = null;
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  List<Map<String, dynamic>> _storesOf(Map<String, dynamic> row) {
    return _parseMapList(row['stores']);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final normalized = DateTime(picked.year, picked.month);
    if (normalized == _selectedMonth) return;
    setState(() => _selectedMonth = normalized);
    final now = DateTime.now();
    _selectedDay = normalized.year == now.year && normalized.month == now.month
        ? DateTime(now.year, now.month, now.day)
        : null;
    await _load();
  }

  Future<void> _pickVisitedDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay ?? _selectedMonth,
      firstDate: DateTime(_selectedMonth.year, _selectedMonth.month, 1),
      lastDate: DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0),
    );
    if (picked == null) return;
    setState(() {
      _selectedDay = DateTime(picked.year, picked.month, picked.day);
    });
    await _load();
  }

  List<Map<String, dynamic>> _visibleStores(Map<String, dynamic> row) {
    final query = _query.trim().toLowerCase();
    final stores = _storesForActiveTab(row);
    if (query.isEmpty) return stores;
    return stores.where((store) {
      final text = [
        '${store['store_name'] ?? ''}',
        '${store['address'] ?? ''}',
        '${store['area'] ?? ''}',
      ].join(' ').toLowerCase();
      return text.contains(query);
    }).toList();
  }

  List<Map<String, dynamic>> _storesForActiveTab(Map<String, dynamic> row) {
    final stores = _storesOf(row);
    if (_activeTab == 'visited') {
      return stores.where((store) {
        final effectiveVisitCount = _selectedDay != null
            ? _toInt(store['day_visit_count'])
            : _toInt(store['visit_count']);
        return effectiveVisitCount > 0;
      }).toList();
    }
    return stores;
  }

  Map<String, dynamic>? _selectedRow() {
    if (_rows.isEmpty) return null;
    final targetId = _selectedSatorId;
    if (targetId == null) return _rows.first;
    for (final row in _rows) {
      if ('${row['sator_id']}' == targetId) return row;
    }
    return _rows.first;
  }

  DateTime? _parseDate(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  String _formatDate(dynamic value) {
    final date = _parseDate(value);
    if (date == null) return 'Belum pernah visit';
    return DateFormat('dd MMM yyyy', 'id_ID').format(date);
  }

  String _formatTime(dynamic value) {
    final date = _parseDate(value);
    if (date == null) return '-';
    return DateFormat('HH:mm', 'id_ID').format(date);
  }

  Color _storeTone(Map<String, dynamic> store) {
    final visitCount = _toInt(store['visit_count']);
    if (visitCount > 0) return t.success;
    if (_parseDate(store['last_visit_at']) == null) return t.warning;
    return t.danger;
  }

  String _storeStatus(Map<String, dynamic> store) {
    final visitCount = _toInt(store['visit_count']);
    if (visitCount > 0) {
      return '${visitCount}x visit bulan ini';
    }
    return '${store['status'] ?? 'Belum divisit bulan ini'}';
  }

  void _openVisitForm(String storeId, String satorId) {
    final selectedDate = _selectedDay ?? _selectedMonth;
    context.pushNamed(
      'spv-visit-form',
      pathParameters: {'storeId': storeId},
      queryParameters: {
        'satorId': satorId,
        'date': DateFormat('yyyy-MM-dd').format(selectedDate),
      },
    );
  }

  void _openVisitedDetail(Map<String, dynamic> store) {
    final visitRows = (store['visit_rows'] is List)
        ? (store['visit_rows'] as List)
              .whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList()
        : const <Map<String, dynamic>>[];

    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 720),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${store['store_name'] ?? 'Toko'}',
                          style: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w800,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth),
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w700,
                      color: t.textMutedStrong,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: visitRows.isEmpty
                        ? Center(
                            child: Text(
                              'Belum ada detail visit.',
                              style: PromotorText.outfit(
                                size: 11,
                                weight: FontWeight.w700,
                                color: t.textMutedStrong,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: visitRows.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final row = visitRows[index];
                              final photos = (row['photos'] is List)
                                  ? (row['photos'] as List)
                                        .map((item) => '$item')
                                        .where((item) => item.isNotEmpty)
                                        .toList()
                                  : const <String>[];
                              return Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: t.surface1,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: t.surface3),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Visit ${_formatTime(row['visit_time'])}',
                                      style: PromotorText.outfit(
                                        size: 10.5,
                                        weight: FontWeight.w800,
                                        color: t.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      '${row['notes'] ?? '-'}'.trim().isEmpty
                                          ? '-'
                                          : '${row['notes']}',
                                      style: PromotorText.outfit(
                                        size: 10,
                                        weight: FontWeight.w700,
                                        color: t.textMutedStrong,
                                      ),
                                    ),
                                    if (photos.isNotEmpty) ...[
                                      const SizedBox(height: 10),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: photos
                                            .map(
                                              (url) => InkWell(
                                                onTap: () =>
                                                    _openPhotoPreview(url),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  child: Image.network(
                                                    url,
                                                    width: 92,
                                                    height: 92,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    ],
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _openPhotoPreview(String url) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Image.network(url, fit: BoxFit.contain),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSatorVisitReport(Map<String, dynamic> row) {
    final stores = _storesOf(row);
    final visitedStores = stores
        .where((store) => _toInt(store['visit_count']) > 0)
        .toList();
    final unvisitedStores = stores
        .where((store) => _toInt(store['visit_count']) <= 0)
        .toList();
    final dayVisitedStores = stores
        .where((store) => _toInt(store['day_visit_count']) > 0)
        .toList();
    final visibleVisitedStores =
        _selectedDay != null ? dayVisitedStores : visitedStores;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Laporan Visit ${row['name'] ?? 'SATOR'}',
            style: PromotorText.outfit(
              size: 11.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _smallTag('Toko ${_toInt(row['total_stores'])}', t.primaryAccent),
              _smallTag(
                'Sudah visit ${_toInt(row['visited_stores'])}',
                t.success,
              ),
              _smallTag(
                'Belum visit ${unvisitedStores.length}',
                unvisitedStores.isEmpty ? t.surface3 : t.danger,
                foreground: unvisitedStores.isEmpty
                    ? t.textMutedStrong
                    : null,
              ),
              _smallTag(
                'Total kunjungan ${_toInt(row['total_visits'])}',
                t.warning,
              ),
              if (_selectedDay != null)
                _smallTag('Visit hari ini ${dayVisitedStores.length}', t.success),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _selectedDay != null ? 'Sudah divisit hari ini' : 'Sudah divisit',
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w800,
              color: t.success,
            ),
          ),
          const SizedBox(height: 6),
          if (visibleVisitedStores.isEmpty)
            Text(
              'Belum ada toko yang masuk laporan visit pada filter ini.',
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: visibleVisitedStores
                  .map(
                    (store) => _smallTag(
                      '${store['store_name'] ?? '-'} ${_selectedDay != null ? _toInt(store['day_visit_count']) : _toInt(store['visit_count'])}x',
                      t.success,
                    ),
                  )
                  .toList(),
            ),
          const SizedBox(height: 10),
          Text(
            'Belum divisit',
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w800,
              color: t.danger,
            ),
          ),
          const SizedBox(height: 6),
          if (unvisitedStores.isEmpty)
            Text(
              'Semua toko sudah divisit.',
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            )
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: unvisitedStores
                  .map(
                    (store) => _smallTag(
                      '${store['store_name'] ?? '-'}',
                      t.danger,
                    ),
                  )
                  .toList(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedRow = _selectedRow();
    var visibleStores = selectedRow == null
        ? const <Map<String, dynamic>>[]
        : _visibleStores(selectedRow);
    if ((_highlightedStoreId ?? '').isNotEmpty) {
      visibleStores = [...visibleStores]
        ..sort((a, b) {
          final aScore = '${a['store_id'] ?? ''}' == _highlightedStoreId ? 0 : 1;
          final bScore = '${b['store_id'] ?? ''}' == _highlightedStoreId ? 0 : 1;
          if (aScore != bScore) return aScore.compareTo(bScore);
          return 0;
        });
    }

    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: const Text('Visiting Monitoring SPV')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildTabBar(),
                  const SizedBox(height: 10),
                  _buildSearchAndSatorTabs(),
                  const SizedBox(height: 10),
                  if (selectedRow != null) ...[
                    _buildSatorVisitReport(selectedRow),
                    const SizedBox(height: 10),
                  ],
                  if (_activeTab == 'visited') ...[
                    _buildVisitedFilterBar(),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 2),
                  if (_rows.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Text(
                        'Belum ada data visiting SATOR pada hierarki SPV.',
                        style: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w700,
                          color: t.textMutedStrong,
                        ),
                      ),
                    )
                  else if (selectedRow == null)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Text(
                        'SATOR belum terpilih.',
                        style: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w700,
                          color: t.textMutedStrong,
                        ),
                      ),
                    )
                  else if (visibleStores.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Text(
                        _activeTab == 'visited'
                            ? 'Belum ada toko yang divisit pada filter ini.'
                            : 'Tidak ada toko yang cocok dengan pencarian.',
                        style: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w700,
                          color: t.textMutedStrong,
                        ),
                      ),
                    )
                  else
                    Column(
                      children: visibleStores
                          .map(
                            (store) => _buildStoreRow(
                              store,
                              '${selectedRow['sator_id'] ?? ''}',
                            ),
                          )
                          .toList(),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSearchAndSatorTabs() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          flex: 9,
          child: TextField(
            controller: _searchController,
            onChanged: (value) => setState(() => _query = value),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Cari toko',
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              filled: true,
              fillColor: t.surface1,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 10,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.surface3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.surface3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.primaryAccent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(flex: 12, child: _buildSatorTabs()),
      ],
    );
  }

  Widget _buildSatorTabs() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rowCount = _rows.length;
          final useFullWidthTabs = rowCount > 0 && rowCount <= 3;
          final spacing = useFullWidthTabs ? 6.0 : 4.0;
          final equalWidth = useFullWidthTabs
              ? (constraints.maxWidth - ((rowCount - 1) * spacing)) / rowCount
              : null;

          final children = _rows.map((row) {
            final satorId = '${row['sator_id'] ?? ''}';
            final isActive = satorId == _selectedSatorId;
            final tab = InkWell(
              onTap: () => setState(() => _selectedSatorId = satorId),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: equalWidth,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: isActive ? t.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  '${row['name'] ?? 'SATOR'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: isActive ? t.textOnAccent : t.textSecondary,
                  ),
                ),
              ),
            );

            return Padding(
              padding: EdgeInsets.only(right: satorId == '${_rows.last['sator_id'] ?? ''}' ? 0 : spacing),
              child: tab,
            );
          }).toList();

          if (useFullWidthTabs) {
            return Row(children: children);
          }

          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: Row(children: children),
            ),
          );
        },
      ),
    );
  }

  Widget _buildVisitedFilterBar() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _pickMonth,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.surface3),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 16,
                    color: t.primaryAccent,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 10.5,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: _pickVisitedDay,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.surface3),
              ),
              child: Row(
                children: [
                  Icon(Icons.event_rounded, size: 16, color: t.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedDay == null
                          ? 'Semua Tanggal'
                          : DateFormat(
                              'dd MMM yyyy',
                              'id_ID',
                            ).format(_selectedDay!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 10.5,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_selectedDay != null) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: () async {
              setState(() => _selectedDay = null);
              await _load();
            },
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.surface3),
              ),
              child: Icon(Icons.close_rounded, color: t.textMutedStrong),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTabBar() {
    final items = [('scope', 'Toko'), ('visited', 'Sudah Visit')];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: items.map((item) {
          final isActive = _activeTab == item.$1;
          return Expanded(
            child: InkWell(
              onTap: () => setState(() => _activeTab = item.$1),
              borderRadius: BorderRadius.circular(10),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 11),
                decoration: BoxDecoration(
                  color: isActive ? t.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  item.$2,
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: isActive ? t.textOnAccent : t.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildStoreRow(Map<String, dynamic> store, String satorId) {
    final tone = _storeTone(store);
    final area = '${store['area'] ?? ''}'.trim();
    final storeId = '${store['store_id'] ?? ''}'.trim();
    final canOpen = storeId.isNotEmpty && satorId.isNotEmpty;

    return InkWell(
      onTap: canOpen
          ? () {
              if (_activeTab == 'visited') {
                _openVisitedDetail(store);
              } else {
                _openVisitForm(storeId, satorId);
              }
            }
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${store['store_name'] ?? '-'}',
                    style: PromotorText.outfit(
                      size: 11.5,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  if (area.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      area,
                      style: PromotorText.outfit(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: t.textMutedStrong,
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _smallTag(_storeStatus(store), tone),
                      if (_selectedDay != null)
                        _smallTag(
                          '${_toInt(store['day_visit_count'])}x di tanggal ini',
                          t.warning,
                        ),
                      _smallTag(
                        'Terakhir ${_formatDate(store['last_visit_at'])}',
                        t.surface3,
                        foreground: t.textMutedStrong,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.chevron_right_rounded,
              color: canOpen ? t.textMutedStrong : t.surface3,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _smallTag(String label, Color tone, {Color? foreground}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 8.5,
          weight: FontWeight.w800,
          color: foreground ?? tone,
        ),
      ),
    );
  }
}
