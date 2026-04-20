import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../../ui/promotor/promotor.dart';

class VisitingDashboardPage extends StatefulWidget {
  final String initialTab;
  final String? highlightedStoreId;
  final DateTime? initialVisitedMonth;
  final DateTime? initialVisitedDate;

  const VisitingDashboardPage({
    super.key,
    this.initialTab = 'scope',
    this.highlightedStoreId,
    this.initialVisitedMonth,
    this.initialVisitedDate,
  });

  @override
  State<VisitingDashboardPage> createState() => _VisitingDashboardPageState();
}

class _VisitingDashboardPageState extends State<VisitingDashboardPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isVisitedLoading = false;
  String _query = '';
  String _activeTab = 'scope';
  List<Map<String, dynamic>> _stores = const [];
  List<Map<String, dynamic>> _visitedStores = const [];
  late DateTime _visitedMonth;
  DateTime? _visitedDate;
  String? _highlightedStoreId;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab == 'visited' ? 'visited' : 'scope';
    final initialMonth = widget.initialVisitedMonth ?? DateTime.now();
    _visitedMonth = DateTime(initialMonth.year, initialMonth.month);
    final initialDate = widget.initialVisitedDate;
    _visitedDate = initialDate == null
        ? null
        : DateTime(initialDate.year, initialDate.month, initialDate.day);
    _highlightedStoreId = widget.highlightedStoreId?.trim();
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Sesi login tidak ditemukan');

      final response = await _supabase.rpc(
        'get_sator_visiting_stores',
        params: {'p_sator_id': userId},
      );
      final visitedResponse = await _supabase.rpc(
        'get_sator_visited_stores',
        params: {
          'p_sator_id': userId,
          'p_month': DateFormat('yyyy-MM-dd').format(_visitedMonth),
          'p_date': _visitedDate == null
              ? null
              : DateFormat('yyyy-MM-dd').format(_visitedDate!),
        },
      );
      final stores = List<Map<String, dynamic>>.from(response ?? const []);
      final visitedStores = List<Map<String, dynamic>>.from(
        visitedResponse ?? const [],
      );

      if (!mounted) return;
      setState(() {
        _stores = stores;
        _visitedStores = visitedStores;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stores = const [];
        _visitedStores = const [];
        _isLoading = false;
      });
    }
  }

  Future<void> _loadVisitedStores() async {
    if (!mounted) return;
    setState(() => _isVisitedLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Sesi login tidak ditemukan');
      final response = await _supabase.rpc(
        'get_sator_visited_stores',
        params: {
          'p_sator_id': userId,
          'p_month': DateFormat('yyyy-MM-dd').format(_visitedMonth),
          'p_date': _visitedDate == null
              ? null
              : DateFormat('yyyy-MM-dd').format(_visitedDate!),
        },
      );
      final visitedStores = List<Map<String, dynamic>>.from(
        response ?? const [],
      );
      if (!mounted) return;
      setState(() {
        _visitedStores = visitedStores;
        _isVisitedLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _visitedStores = const [];
        _isVisitedLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _filteredStores(
    List<Map<String, dynamic>> source,
  ) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return source;
    return source.where((store) {
      final text = [
        '${store['store_name'] ?? ''}',
        '${store['address'] ?? ''}',
      ].join(' ').toLowerCase();
      return text.contains(query);
    }).toList();
  }

  int _issueCount(Map<String, dynamic> store) =>
      int.tryParse('${store['issue_count'] ?? ''}') ?? 0;

  DateTime? _lastVisit(Map<String, dynamic> store) {
    final raw = '${store['last_visit'] ?? store['last_visit_at'] ?? ''}'.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  String _lastVisitLabel(Map<String, dynamic> store) {
    final date = _lastVisit(store);
    if (date == null) return 'Belum pernah visit';
    return DateFormat('dd MMM yyyy', 'id_ID').format(date);
  }

  void _openStore(String storeId) {
    context.push('/sator/visiting/form/$storeId');
  }

  String _visitTimeLabel(dynamic value) {
    final date = _lastVisit({'last_visit_at': value});
    if (date == null) return '-';
    return DateFormat('HH:mm', 'id_ID').format(date);
  }

  int _monthVisitCount(Map<String, dynamic> store) =>
      int.tryParse(
        '${store['month_visit_count'] ?? store['visit_count'] ?? ''}',
      ) ??
      0;

  int _dayVisitCount(Map<String, dynamic> store) =>
      int.tryParse('${store['day_visit_count'] ?? ''}') ?? 0;

  Future<void> _pickVisitedMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitedMonth,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 2)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final normalized = DateTime(picked.year, picked.month);
    if (normalized == _visitedMonth) return;
    final now = DateTime.now();
    setState(() {
      _visitedMonth = normalized;
      _visitedDate =
          normalized.year == now.year && normalized.month == now.month
          ? DateTime(now.year, now.month, now.day)
          : null;
    });
    await _loadVisitedStores();
  }

  Future<void> _pickVisitedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _visitedDate ?? _visitedMonth,
      firstDate: DateTime(_visitedMonth.year, _visitedMonth.month, 1),
      lastDate: DateTime(_visitedMonth.year, _visitedMonth.month + 1, 0),
    );
    if (picked == null) return;
    setState(() {
      _visitedDate = DateTime(picked.year, picked.month, picked.day);
    });
    await _loadVisitedStores();
  }

  @override
  Widget build(BuildContext context) {
    final scopeRows = _filteredStores(_stores);
    var visitedRows = _filteredStores(_visitedStores);
    if (_highlightedStoreId != null && _highlightedStoreId!.isNotEmpty) {
      visitedRows = [...visitedRows]
        ..sort((a, b) {
          final aScore = ('${a['store_id'] ?? ''}' == _highlightedStoreId)
              ? 0
              : 1;
          final bScore = ('${b['store_id'] ?? ''}' == _highlightedStoreId)
              ? 0
              : 1;
          if (aScore != bScore) return aScore.compareTo(bScore);
          return 0;
        });
    }
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('Visiting')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                children: [
                  _buildTabBar(),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: _activeTab == 'scope'
                          ? 'Cari toko'
                          : 'Cari toko hasil visit',
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
                  const SizedBox(height: 10),
                  if (_activeTab == 'visited') ...[
                    _buildVisitedFilterBar(),
                    const SizedBox(height: 10),
                  ],
                  Container(
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.surface3),
                    ),
                    child: (_activeTab == 'visited' && _isVisitedLoading)
                        ? const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        : (_activeTab == 'scope' ? scopeRows : visitedRows)
                              .isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _activeTab == 'scope'
                                  ? 'Tidak ada toko untuk ditampilkan.'
                                  : 'Belum ada hasil visit pada filter ini.',
                              style: PromotorText.outfit(
                                size: 12,
                                weight: FontWeight.w700,
                                color: t.textMutedStrong,
                              ),
                            ),
                          )
                        : Column(
                            children: (_activeTab == 'scope' ? scopeRows : visitedRows)
                                .asMap()
                                .entries
                                .map((entry) {
                                  final currentRows = _activeTab == 'scope'
                                      ? scopeRows
                                      : visitedRows;
                                  final store = entry.value;
                                  final issues = _issueCount(store);
                                  final storeId =
                                      '${store['store_id'] ?? store['id'] ?? ''}';
                                  final isVisitedTab = _activeTab == 'visited';
                                  final isHighlighted =
                                      '${store['store_id'] ?? ''}' ==
                                      _highlightedStoreId;
                                  final visitTone = isHighlighted
                                      ? t.primaryAccent
                                      : t.success;

                                  return InkWell(
                                    onTap: storeId.isEmpty
                                        ? null
                                        : () {
                                            if (isVisitedTab) {
                                              _openVisitedDetail(store);
                                            } else {
                                              _openStore(storeId);
                                            }
                                          },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 9,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isHighlighted
                                            ? t.primaryAccentSoft.withValues(
                                                alpha: 0.5,
                                              )
                                            : null,
                                        border:
                                            entry.key == currentRows.length - 1
                                            ? null
                                            : Border(
                                                bottom: BorderSide(
                                                  color: t.surface3,
                                                ),
                                              ),
                                      ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        width: 22,
                                        height: 22,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: (isVisitedTab
                                                  ? visitTone
                                                  : t.surface2)
                                              .withValues(alpha: 0.16),
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${entry.key + 1}',
                                          style: PromotorText.outfit(
                                            size: 8.5,
                                            weight: FontWeight.w800,
                                            color: isVisitedTab
                                                ? visitTone
                                                : t.textMutedStrong,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: Text(
                                                        '${store['store_name'] ?? '-'}',
                                                        style:
                                                            PromotorText.outfit(
                                                              size: 12.5,
                                                              weight: FontWeight
                                                                  .w800,
                                                              color:
                                                                  t.textPrimary,
                                                            ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Text(
                                                      isVisitedTab
                                                          ? _visitTimeLabel(
                                                              store['last_visit_at'],
                                                            )
                                                          : _lastVisitLabel(
                                                              store,
                                                            ),
                                                      style: PromotorText.outfit(
                                                        size: 9.5,
                                                        weight: FontWeight.w700,
                                                        color:
                                                            t.textMutedStrong,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                const SizedBox(height: 3),
                                                if (isVisitedTab)
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children: [
                                                      _tag(
                                                        '${_monthVisitCount(store)}x bulan ini',
                                                        visitTone,
                                                      ),
                                                      _tag(
                                                        'Jam ${_visitTimeLabel(store['last_visit_at'])}',
                                                        t.info,
                                                      ),
                                                      if (_visitedDate != null)
                                                        _tag(
                                                          '${_dayVisitCount(store)}x di tanggal ini',
                                                          t.warning,
                                                        ),
                                                    ],
                                                  )
                                                else
                                                  Wrap(
                                                    spacing: 6,
                                                    runSpacing: 4,
                                                    children: [
                                                      if (issues > 0)
                                                        _tag(
                                                          '$issues issue',
                                                          t.danger,
                                                        ),
                                                    ],
                                                  ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: t.textMuted,
                                            size: 18,
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                })
                                .toList(),
                          ),
                  ),
                ],
              ),
            ),
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

  Widget _buildVisitedFilterBar() {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: _pickVisitedMonth,
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
                      DateFormat('MMMM yyyy', 'id_ID').format(_visitedMonth),
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
            onTap: _pickVisitedDate,
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
                      _visitedDate == null
                          ? 'Semua Tanggal'
                          : DateFormat(
                              'dd MMM yyyy',
                              'id_ID',
                            ).format(_visitedDate!),
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
        if (_visitedDate != null) ...[
          const SizedBox(width: 8),
          InkWell(
            onTap: () async {
              setState(() => _visitedDate = null);
              await _loadVisitedStores();
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
                    _visitedDate == null
                        ? DateFormat('MMMM yyyy', 'id_ID').format(_visitedMonth)
                        : DateFormat(
                            'dd MMMM yyyy',
                            'id_ID',
                          ).format(_visitedDate!),
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
                                      'Visit ${_visitTimeLabel(row['visit_time'])}',
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

  Widget _tag(String label, Color tone, {Color? foreground}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 8,
          weight: FontWeight.w800,
          color: foreground ?? tone,
        ),
      ),
    );
  }
}
