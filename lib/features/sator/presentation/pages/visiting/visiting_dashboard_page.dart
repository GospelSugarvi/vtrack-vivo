import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../../ui/promotor/promotor.dart';
import 'pre_visit_page.dart';

class VisitingDashboardPage extends StatefulWidget {
  const VisitingDashboardPage({super.key});

  @override
  State<VisitingDashboardPage> createState() => _VisitingDashboardPageState();
}

class _VisitingDashboardPageState extends State<VisitingDashboardPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  bool _isLoading = true;
  String _query = '';
  List<Map<String, dynamic>> _stores = const [];

  @override
  void initState() {
    super.initState();
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
      var stores = List<Map<String, dynamic>>.from(response ?? const []);

      if (stores.isEmpty) {
        final fallbackRows = await _supabase
            .from('assignments_sator_store')
            .select('store_id, stores(id, store_name, address, area)')
            .eq('sator_id', userId)
            .eq('active', true);
        stores = List<Map<String, dynamic>>.from(fallbackRows)
            .map((row) {
              final store = Map<String, dynamic>.from(
                row['stores'] as Map? ?? {},
              );
              return {
                'store_id': store['id'],
                'store_name': store['store_name'],
                'address': store['address'],
                'area': store['area'],
                'last_visit': null,
                'issue_count': 0,
                'priority': 2,
              };
            })
            .where((row) => '${row['store_id'] ?? ''}'.isNotEmpty)
            .toList();
      }

      if (!mounted) return;
      setState(() {
        _stores = stores;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stores = const [];
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _filteredStores() {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _stores;
    return _stores.where((store) {
      final text = [
        '${store['store_name'] ?? ''}',
        '${store['address'] ?? ''}',
      ].join(' ').toLowerCase();
      return text.contains(query);
    }).toList();
  }

  int _priorityScore(Map<String, dynamic> store) =>
      int.tryParse('${store['priority_score'] ?? ''}') ??
      int.tryParse('${store['priority'] ?? ''}') ??
      0;

  int _issueCount(Map<String, dynamic> store) =>
      int.tryParse('${store['issue_count'] ?? ''}') ?? 0;

  List<String> _priorityReasons(Map<String, dynamic> store) {
    final raw = store['priority_reasons'];
    if (raw is List) {
      return raw
          .map((item) => '$item')
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return const [];
  }

  DateTime? _lastVisit(Map<String, dynamic> store) {
    final raw = '${store['last_visit'] ?? ''}'.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  String _lastVisitLabel(Map<String, dynamic> store) {
    final date = _lastVisit(store);
    if (date == null) return 'Belum pernah visit';
    return DateFormat('dd MMM yyyy', 'id_ID').format(date);
  }

  Color _priorityColor(Map<String, dynamic> store) {
    final score = _priorityScore(store);
    if (score >= 35) return t.danger;
    if (score >= 20) return t.warning;
    if (score > 0) return t.primaryAccent;
    return t.success;
  }

  String _priorityLabel(Map<String, dynamic> store) {
    final score = _priorityScore(store);
    if (score >= 35) return 'Prioritas';
    if (_lastVisit(store) == null) return 'Belum Visit';
    if (score >= 20) return 'Perlu Visit';
    return 'Normal';
  }

  void _openStore(String storeId) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => PreVisitPage(storeId: storeId)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredStores();
    final priorityCount = _stores
        .where((row) => _priorityScore(row) >= 35)
        .length;
    final neverVisitedCount = _stores
        .where((row) => _lastVisit(row) == null)
        .length;

    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: const Text('Visiting')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _summaryPill(
                        '${_stores.length}',
                        'Toko',
                        t.primaryAccent,
                      ),
                      _summaryPill('$priorityCount', 'Prioritas', t.danger),
                      _summaryPill(
                        '$neverVisitedCount',
                        'Belum Visit',
                        t.warning,
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
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
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.surface3),
                    ),
                    child: rows.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Tidak ada toko untuk ditampilkan.',
                              style: PromotorText.outfit(
                                size: 12,
                                weight: FontWeight.w700,
                                color: t.textMutedStrong,
                              ),
                            ),
                          )
                        : Column(
                            children: rows.asMap().entries.map((entry) {
                              final store = entry.value;
                              final tone = _priorityColor(store);
                              final issues = _issueCount(store);
                              final reasons = _priorityReasons(store);
                              final storeId =
                                  '${store['store_id'] ?? store['id'] ?? ''}';

                              return InkWell(
                                onTap: storeId.isEmpty
                                    ? null
                                    : () => _openStore(storeId),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 9,
                                  ),
                                  decoration: BoxDecoration(
                                    border: entry.key == rows.length - 1
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
                                        width: 10,
                                        height: 10,
                                        margin: const EdgeInsets.only(top: 4),
                                        decoration: BoxDecoration(
                                          color: tone,
                                          shape: BoxShape.circle,
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
                                                    style: PromotorText.outfit(
                                                      size: 12.5,
                                                      weight: FontWeight.w800,
                                                      color: t.textPrimary,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  _lastVisitLabel(store),
                                                  style: PromotorText.outfit(
                                                    size: 9.5,
                                                    weight: FontWeight.w700,
                                                    color: t.textMutedStrong,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 3),
                                            Wrap(
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                _tag(
                                                  _priorityLabel(store),
                                                  tone,
                                                ),
                                                if (issues > 0)
                                                  _tag(
                                                    '$issues issue',
                                                    t.danger,
                                                  ),
                                                ...reasons
                                                    .take(2)
                                                    .map(
                                                      (reason) => _tag(
                                                        _compactReason(reason),
                                                        t.surface3,
                                                        foreground:
                                                            t.textMutedStrong,
                                                      ),
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
                            }).toList(),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  String _compactReason(String value) {
    if (value == 'Ada issue toko yang belum selesai') return 'Issue';
    if (value == 'Toko belum pernah divisit') return 'Baru';
    if (value == 'Sudah lama tidak divisit') return 'Ulang';
    if (value == 'Sell out di bawah target harian') return 'Sell Out';
    if (value == 'Produk fokus belum bergerak') return 'Fokus';
    if (value == 'Ada promotor dengan aktivitas rendah') return 'Aktivitas';
    return value;
  }

  Widget _summaryPill(String value, String label, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            value,
            style: PromotorText.outfit(
              size: 11.5,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: PromotorText.outfit(
              size: 9,
              weight: FontWeight.w700,
              color: tone,
            ),
          ),
        ],
      ),
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
