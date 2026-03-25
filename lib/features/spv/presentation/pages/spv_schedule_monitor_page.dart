import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/features/sator/presentation/pages/jadwal/schedule_detail_page.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class SpvScheduleMonitorPage extends StatefulWidget {
  const SpvScheduleMonitorPage({super.key});

  @override
  State<SpvScheduleMonitorPage> createState() => _SpvScheduleMonitorPageState();
}

class _SpvScheduleMonitorPageState extends State<SpvScheduleMonitorPage> {
  final _supabase = Supabase.instance.client;
  final _searchController = TextEditingController();

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  Map<String, String> _dailyShiftByPromotor = <String, String>{};
  String _statusFilter = 'all';
  String _searchQuery = '';

  FieldThemeTokens get t => context.fieldTokens;
  String get _monthYear => DateFormat('yyyy-MM').format(_selectedMonth);
  String get _monthLabel => DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth);

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

  Future<List<dynamic>> _safeList(Future<dynamic> Function() loader) async {
    try {
      final result = await loader();
      return result is List ? result : <dynamic>[];
    } catch (_) {
      return <dynamic>[];
    }
  }

  Future<List<Map<String, dynamic>>> _fetchRowsForMonth(
    List<String> satorIds,
    String monthYear,
  ) async {
    final satorUsers = await _safeList(
      () => _supabase
          .from('users')
          .select('id, full_name')
          .inFilter('id', satorIds),
    );
    final satorNameById = {
      for (final row in List<Map<String, dynamic>>.from(satorUsers))
        row['id'].toString(): (row['full_name'] ?? 'SATOR').toString(),
    };

    final allRows = <Map<String, dynamic>>[];
    for (final satorId in satorIds) {
      final response = await _supabase.rpc(
        'get_sator_schedule_summary',
        params: <String, dynamic>{
          'p_sator_id': satorId,
          'p_month_year': monthYear,
        },
      );
      final parsed = List<Map<String, dynamic>>.from(response ?? const []);
      for (final row in parsed) {
        allRows.add(<String, dynamic>{
          ...row,
          'sator_id': satorId,
          'sator_name': satorNameById[satorId] ?? 'SATOR',
        });
      }
    }
    return allRows;
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Session tidak ditemukan.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final satorLinks = await _safeList(
        () => _supabase
            .from('hierarchy_spv_sator')
            .select('sator_id')
            .eq('spv_id', userId)
            .eq('active', true),
      );
      final satorIds = satorLinks
          .map((row) => row['sator_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      if (satorIds.isEmpty) {
        setState(() {
          _rows = <Map<String, dynamic>>[];
          _isLoading = false;
        });
        return;
      }

      var targetMonth = DateTime(_selectedMonth.year, _selectedMonth.month);
      var allRows = await _fetchRowsForMonth(satorIds, _monthYear);
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);
      final isCurrentMonth = targetMonth.year == currentMonth.year &&
          targetMonth.month == currentMonth.month;
      final hasSubmitted =
          allRows.any((row) => '${row['status'] ?? ''}' == 'submitted');

      if (isCurrentMonth && !hasSubmitted) {
        final nextMonth = DateTime(targetMonth.year, targetMonth.month + 1);
        final nextMonthYear = DateFormat('yyyy-MM').format(nextMonth);
        final nextRows = await _fetchRowsForMonth(satorIds, nextMonthYear);
        final nextHasSubmitted =
            nextRows.any((row) => '${row['status'] ?? ''}' == 'submitted');
        if (nextHasSubmitted) {
          targetMonth = nextMonth;
          allRows = nextRows;
        }
      }

      final promotorIds = allRows
          .map((row) => row['promotor_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final nextDailyShiftByPromotor = <String, String>{};
      if (promotorIds.isNotEmpty) {
        final today = DateTime.now();
        final inspectDate = DateTime(
          _selectedMonth.year,
          _selectedMonth.month,
          today.day.clamp(1, DateUtils.getDaysInMonth(_selectedMonth.year, _selectedMonth.month)),
        );
        final scheduleRows = await _safeList(
          () => _supabase
              .from('schedules')
              .select('promotor_id, shift_type, status')
              .inFilter('promotor_id', promotorIds)
              .eq('schedule_date', DateFormat('yyyy-MM-dd').format(inspectDate)),
        );
        for (final row in List<Map<String, dynamic>>.from(scheduleRows)) {
          final promotorId = row['promotor_id']?.toString() ?? '';
          if (promotorId.isEmpty) continue;
          nextDailyShiftByPromotor[promotorId] =
              '${row['shift_type'] ?? ''}|${row['status'] ?? ''}';
        }
      }

      allRows.sort((a, b) {
        final statusCompare =
            _statusRank('${a['status'] ?? ''}').compareTo(_statusRank('${b['status'] ?? ''}'));
        if (statusCompare != 0) return statusCompare;
        return '${a['promotor_name'] ?? ''}'.compareTo('${b['promotor_name'] ?? ''}');
      });

      if (!mounted) return;
      setState(() {
        _selectedMonth = targetMonth;
        _rows = allRows;
        _dailyShiftByPromotor = nextDailyShiftByPromotor;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Gagal memuat monitor jadwal. $e';
      });
    }
  }

  int _statusRank(String status) {
    switch (status) {
      case 'submitted':
        return 0;
      case 'belum_kirim':
        return 1;
      case 'rejected':
        return 2;
      case 'approved':
        return 3;
      case 'draft':
        return 4;
      default:
        return 5;
    }
  }

  int _countStatus(String status) =>
      _rows.where((row) => '${row['status'] ?? ''}' == status).length;

  List<Map<String, dynamic>> _applyFilters(Iterable<Map<String, dynamic>> source) {
    final query = _searchQuery.trim().toLowerCase();
    return source.where((row) {
      final status = '${row['status'] ?? ''}';
      if (_statusFilter == 'today_working') {
        final shift = _todayShiftType('${row['promotor_id'] ?? ''}');
        if (shift.isEmpty || shift == 'libur') return false;
      } else if (_statusFilter == 'today_off') {
        final shift = _todayShiftType('${row['promotor_id'] ?? ''}');
        if (shift != 'libur') return false;
      } else if (_statusFilter != 'all' && status != _statusFilter) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        '${row['promotor_name'] ?? ''}',
        '${row['store_name'] ?? ''}',
        '${row['sator_name'] ?? ''}',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  String _todayShiftType(String promotorId) {
    final raw = _dailyShiftByPromotor[promotorId];
    if (raw == null || raw.isEmpty) return '';
    final parts = raw.split('|');
    return parts.isEmpty ? '' : parts.first;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'submitted':
        return t.warning;
      case 'approved':
        return t.success;
      case 'rejected':
        return t.danger;
      case 'draft':
        return t.info;
      default:
        return t.textMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'submitted':
        return 'Sudah kirim, menunggu SATOR';
      case 'approved':
        return 'Sudah diapprove SATOR';
      case 'rejected':
        return 'Ditolak SATOR';
      case 'draft':
        return 'Masih draft';
      default:
        return 'Belum kirim';
    }
  }

  Color _dailyShiftColor(String shift) {
    switch (shift) {
      case 'pagi':
        return t.warning;
      case 'siang':
        return t.info;
      case 'fullday':
        return t.primaryAccent;
      case 'libur':
        return t.textMuted;
      default:
        return t.textMuted;
    }
  }

  String _dailyShiftLabel(String promotorId) {
    final raw = _dailyShiftByPromotor[promotorId];
    if (raw == null || raw.isEmpty) {
      return 'Hari ini belum ada baris jadwal';
    }
    final parts = raw.split('|');
    final shift = parts.isNotEmpty ? parts.first : '';
    final status = parts.length > 1 ? parts[1] : '';
    final shiftText = switch (shift) {
      'pagi' => 'Hari ini masuk pagi',
      'siang' => 'Hari ini masuk siang',
      'fullday' => 'Hari ini masuk fullday',
      'libur' => 'Hari ini libur',
      _ => 'Hari ini belum ada jadwal',
    };
    if (status == 'approved') return shiftText;
    if (status == 'submitted') return '$shiftText, masih menunggu approve';
    if (status == 'rejected') return '$shiftText, tapi bulan ini ditolak';
    if (status == 'draft') return '$shiftText, belum dikirim';
    return shiftText;
  }

  Color _dailyShiftTone(String promotorId) {
    final raw = _dailyShiftByPromotor[promotorId];
    if (raw == null || raw.isEmpty) return t.textMuted;
    final parts = raw.split('|');
    final shift = parts.isNotEmpty ? parts.first : '';
    return _dailyShiftColor(shift);
  }

  void _changeMonth(int offset) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + offset);
    });
    _loadData();
  }

  Future<void> _openDetail(Map<String, dynamic> row) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScheduleDetailPage(
          promotorId: '${row['promotor_id']}',
          promotorName: '${row['promotor_name'] ?? ''}',
          storeName: '${row['store_name'] ?? ''}',
          monthYear: _monthYear,
          status: '${row['status'] ?? 'belum_kirim'}',
        ),
      ),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final watchRows = _applyFilters(
      _rows.where(
        (row) => <String>['belum_kirim', 'submitted', 'rejected']
            .contains('${row['status'] ?? ''}'),
      ),
    );
    final approvedRows = _applyFilters(
      _rows.where((row) => '${row['status'] ?? ''}' == 'approved'),
    );

    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(
        title: const Text('Monitor Jadwal SPV'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildMonthCard(),
                  const SizedBox(height: 12),
                  if (_errorMessage != null) _buildErrorCard() else ...[
                    _buildSummaryCard(),
                    const SizedBox(height: 12),
                    _buildFilterCard(),
                    const SizedBox(height: 12),
                    _buildSection(
                      title: 'Perlu dipantau',
                      rows: watchRows,
                    ),
                    const SizedBox(height: 12),
                    _buildSection(
                      title: 'Jadwal approved SATOR',
                      rows: approvedRows,
                      showOpenHint: true,
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildMonthCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _changeMonth(-1),
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            Expanded(
              child: Text(
                _monthLabel,
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _changeMonth(1),
              icon: const Icon(Icons.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(child: _buildMiniStat('${_countStatus('belum_kirim')}', 'Belum', t.textMuted)),
            const SizedBox(width: 8),
            Expanded(child: _buildMiniStat('${_countStatus('submitted')}', 'Kirim', t.warning)),
            const SizedBox(width: 8),
            Expanded(child: _buildMiniStat('${_countStatus('approved')}', 'OK', t.success)),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filter',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Cari nama promotor, toko, atau SATOR',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _buildFilterChip('Semua', 'all'),
                _buildFilterChip('Belum kirim', 'belum_kirim'),
                _buildFilterChip('Submitted', 'submitted'),
                _buildFilterChip('Approved', 'approved'),
                _buildFilterChip('Rejected', 'rejected'),
                _buildFilterChip('Hari ini masuk', 'today_working'),
                _buildFilterChip('Hari ini libur', 'today_off'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final active = _statusFilter == value;
    final color = active ? t.primaryAccent : t.textMuted;
    return InkWell(
      onTap: () => setState(() => _statusFilter = value),
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: color.withValues(alpha: active ? 0.14 : 0.08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.w700,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Map<String, dynamic>> rows,
    bool showOpenHint = false,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Text(
                'Tidak ada data di section ini.',
                style: TextStyle(color: t.textSecondary),
              )
            else
              ...rows.map((row) => _buildPromotorCard(row, showOpenHint: showOpenHint)),
          ],
        ),
      ),
    );
  }

  Widget _buildPromotorCard(Map<String, dynamic> row, {bool showOpenHint = false}) {
    final status = '${row['status'] ?? 'belum_kirim'}';
    final tone = _statusColor(status);
    final updatedAt = DateTime.tryParse('${row['last_updated'] ?? ''}');
    final promotorId = '${row['promotor_id'] ?? ''}';
    final dailyTone = _dailyShiftTone(promotorId);
    final dailyLabel = _dailyShiftLabel(promotorId);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
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
                      '${row['promotor_name'] ?? ''}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${row['store_name'] ?? '-'} • ${row['sator_name'] ?? 'SATOR'}',
                      style: TextStyle(color: t.textSecondary, fontSize: 12),
                    ),
                  ],
                ),
              ),
              _buildPill(_statusLabel(status), tone),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (updatedAt != null)
                _buildPill(
                  'Update ${DateFormat('dd MMM yyyy', 'id_ID').format(updatedAt)}',
                  t.textMuted,
                ),
              _buildPill(dailyLabel, dailyTone),
              if (showOpenHint) _buildPill('Bisa cek detail shift', t.primaryAccent),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: status == 'belum_kirim' ? null : () => _openDetail(row),
              icon: const Icon(Icons.visibility_outlined),
              label: Text(status == 'belum_kirim' ? 'Belum ada jadwal' : 'Buka detail jadwal'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(_errorMessage ?? 'Terjadi kesalahan.'),
      ),
    );
  }

  Widget _buildPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 11.5,
        ),
      ),
    );
  }
}
