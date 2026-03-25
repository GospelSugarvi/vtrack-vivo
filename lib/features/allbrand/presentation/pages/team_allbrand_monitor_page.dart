import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import 'allbrand_store_detail_page.dart';

class TeamAllbrandMonitorPage extends StatefulWidget {
  final String title;
  final String rpcName;
  final String principalParam;
  final bool showSatorName;

  const TeamAllbrandMonitorPage({
    super.key,
    required this.title,
    required this.rpcName,
    required this.principalParam,
    this.showSatorName = false,
  });

  @override
  State<TeamAllbrandMonitorPage> createState() =>
      _TeamAllbrandMonitorPageState();
}

class _TeamAllbrandMonitorPageState extends State<TeamAllbrandMonitorPage> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String? _errorMessage;
  String _statusFilter = 'all';
  String _searchQuery = '';
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

  FieldThemeTokens get t => context.fieldTokens;
  String get _dateKey => DateFormat('yyyy-MM-dd').format(_selectedDate);
  String get _dateLabel =>
      DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDate);

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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2025, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    await _loadData();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Sesi login tidak ditemukan.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await _supabase.rpc(
        widget.rpcName,
        params: <String, dynamic>{
          widget.principalParam: userId,
          'p_date': _dateKey,
        },
      );
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(response ?? const []);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _rows = <Map<String, dynamic>>[];
        _isLoading = false;
        _errorMessage = 'Gagal memuat monitor all brand. $e';
      });
    }
  }

  List<Map<String, dynamic>> _filteredRows() {
    final query = _searchQuery.trim().toLowerCase();
    return _rows.where((row) {
      final status = '${row['status'] ?? 'belum_kirim'}';
      if (_statusFilter != 'all' && status != _statusFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        '${row['store_name'] ?? ''}',
        '${row['submitted_by_name'] ?? ''}',
        '${row['latest_submitted_by_name'] ?? ''}',
        '${row['sator_name'] ?? ''}',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> _groupedRows(
    List<Map<String, dynamic>> rows,
  ) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final key = widget.showSatorName
          ? '${row['sator_name'] ?? 'SATOR'}'
          : 'TOKO';
      groups.putIfAbsent(key, () => <Map<String, dynamic>>[]);
      groups[key]!.add(row);
    }

    final entries = groups.entries.toList();
    for (final entry in entries) {
      entry.value.sort((a, b) {
        final aNoPromotor = (((a['promotor_count'] as num?)?.toInt() ?? 0) <= 0)
            ? 1
            : 0;
        final bNoPromotor = (((b['promotor_count'] as num?)?.toInt() ?? 0) <= 0)
            ? 1
            : 0;
        if (aNoPromotor != bNoPromotor) {
          return aNoPromotor.compareTo(bNoPromotor);
        }
        final aStatus = '${a['status'] ?? 'belum_kirim'}' == 'sudah_kirim'
            ? 0
            : 1;
        final bStatus = '${b['status'] ?? 'belum_kirim'}' == 'sudah_kirim'
            ? 0
            : 1;
        if (aStatus != bStatus) {
          return aStatus.compareTo(bStatus);
        }
        return '${a['store_name'] ?? ''}'.compareTo('${b['store_name'] ?? ''}');
      });
    }
    entries.sort((a, b) => a.key.compareTo(b.key));
    return entries;
  }

  int _countStatus(String status) =>
      _rows.where((row) => '${row['status'] ?? ''}' == status).length;

  Color _statusColor(String status) {
    switch (status) {
      case 'sudah_kirim':
        return t.success;
      default:
        return t.danger;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'sudah_kirim':
        return 'Sudah kirim';
      default:
        return 'Belum kirim';
    }
  }

  String _submittedMeta(Map<String, dynamic> row) {
    final rawAt = row['submitted_at']?.toString();
    final submittedAt = rawAt == null
        ? null
        : DateTime.tryParse(rawAt)?.toLocal();
    final sender = '${row['submitted_by_name'] ?? '-'}';
    if (submittedAt == null) {
      return 'Hari dipilih: belum kirim';
    }
    return 'Hari dipilih: $sender · ${DateFormat('HH:mm').format(submittedAt)}';
  }

  String _latestMeta(Map<String, dynamic> row) {
    final rawDate = row['latest_report_date']?.toString();
    if (rawDate == null || rawDate.isEmpty) {
      return 'Belum ada laporan tersimpan';
    }
    final reportDate = DateTime.tryParse(rawDate);
    final sender = '${row['latest_submitted_by_name'] ?? '-'}';
    final dailyUnits = '${row['latest_daily_total_units'] ?? 0}';
    final cumulativeUnits = '${row['latest_cumulative_total_units'] ?? 0}';
    final dateLabel = reportDate == null
        ? rawDate
        : DateFormat('dd MMM yyyy', 'id_ID').format(reportDate);
    return 'Terakhir: $dateLabel · $sender · $dailyUnits/$cumulativeUnits unit';
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    if (row['latest_report_id'] == null && row['report_id'] == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AllbrandStoreDetailPage(
          storeId: '${row['store_id']}',
          storeName: '${row['store_name'] ?? '-'}',
          targetDate: _selectedDate,
        ),
      ),
    );
    if (!mounted) return;
    await _loadData();
  }

  Widget _buildShell({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: child,
    );
  }

  Widget _buildMiniStat(String value, String label, Color tone) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tone.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final active = _statusFilter == value;
    return GestureDetector(
      onTap: () => setState(() => _statusFilter = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? t.primaryAccentSoft : t.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? t.primaryAccent : t.surface3),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: active ? t.primaryAccent : t.textMutedStrong,
          ),
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final status = '${row['status'] ?? 'belum_kirim'}';
    final statusColor = _statusColor(status);
    final canOpen = row['latest_report_id'] != null || row['report_id'] != null;
    final promotorCount = '${row['promotor_count'] ?? 0}';
    final sideMeta = '$promotorCount promotor';
    final hasLatest = row['latest_report_date'] != null;

    return InkWell(
      onTap: canOpen ? () => _openDetail(row) : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.surface3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: statusColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${row['store_name'] ?? '-'}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    sideMeta,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: t.textMutedStrong,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _submittedMeta(row),
                    style: TextStyle(fontSize: 10, color: t.textMuted),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _latestMeta(row),
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: hasLatest ? t.primaryAccent : t.textMutedStrong,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.18),
                    ),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: statusColor,
                    ),
                  ),
                ),
                if (canOpen) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Lihat',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: t.primaryAccent,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filteredRows();
    final groupedRows = _groupedRows(rows);
    final sentCount = _countStatus('sudah_kirim');
    final missingCount = _countStatus('belum_kirim');

    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: Text(widget.title)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildShell(
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
                                    'Monitor AllBrand',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: t.textMutedStrong,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    _dateLabel,
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w800,
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
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
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
                                      color: t.textPrimary,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Ubah',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: t.textPrimary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _buildMiniStat(
                              '${_rows.length}',
                              'Toko',
                              t.primaryAccent,
                            ),
                            const SizedBox(width: 8),
                            _buildMiniStat('$sentCount', 'Sudah', t.success),
                            const SizedBox(width: 8),
                            _buildMiniStat('$missingCount', 'Belum', t.danger),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildShell(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      children: [
                        TextField(
                          controller: _searchController,
                          onChanged: (value) =>
                              setState(() => _searchQuery = value),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: 'Cari toko, laporan terakhir, atau sator',
                            hintStyle: TextStyle(
                              fontSize: 11,
                              color: t.textMuted,
                            ),
                            prefixIcon: const Icon(
                              Icons.search_rounded,
                              size: 16,
                            ),
                            filled: true,
                            fillColor: t.surface2,
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
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _buildFilterChip('Semua', 'all'),
                            _buildFilterChip('Sudah kirim', 'sudah_kirim'),
                            _buildFilterChip('Belum kirim', 'belum_kirim'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color: t.danger,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  _buildShell(
                    padding: EdgeInsets.zero,
                    child: rows.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(
                              'Tidak ada data untuk filter ini.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: t.textMutedStrong,
                              ),
                            ),
                          )
                        : Column(
                            children: [
                              for (final group in groupedRows) ...[
                                if (widget.showSatorName)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.fromLTRB(
                                      12,
                                      10,
                                      12,
                                      8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: t.primaryAccentSoft.withValues(
                                        alpha: 0.22,
                                      ),
                                      border: Border(
                                        bottom: BorderSide(color: t.surface3),
                                      ),
                                    ),
                                    child: Text(
                                      group.key,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w900,
                                        color: t.textPrimary,
                                      ),
                                    ),
                                  ),
                                for (final row in group.value) _buildRow(row),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
