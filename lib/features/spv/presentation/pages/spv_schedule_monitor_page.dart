import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/features/sator/presentation/pages/jadwal/schedule_detail_page.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';

class SpvScheduleMonitorPage extends StatefulWidget {
  const SpvScheduleMonitorPage({super.key});

  @override
  State<SpvScheduleMonitorPage> createState() => _SpvScheduleMonitorPageState();
}

class _SpvScheduleMonitorPageState extends State<SpvScheduleMonitorPage> {
  final _supabase = Supabase.instance.client;

  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];
  String _activeTab = 'watch';

  FieldThemeTokens get t => context.fieldTokens;
  String get _monthYear => DateFormat('yyyy-MM').format(_selectedMonth);
  String get _monthLabel => DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final requestedMonth = _monthYear;
    if (_supabase.auth.currentUser?.id == null) {
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
      final snapshotRaw = await _supabase.rpc(
        'get_spv_schedule_monitor_snapshot',
        params: <String, dynamic>{'p_month_year': requestedMonth},
      );
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final resolvedMonthYear = '${snapshot['month_year'] ?? requestedMonth}';
      final resolvedMonth = _parseMonthYear(resolvedMonthYear);
      final allRows = _parseMapList(snapshot['rows']);

      allRows.sort((a, b) {
        final statusCompare =
            _statusRank('${a['status'] ?? ''}').compareTo(_statusRank('${b['status'] ?? ''}'));
        if (statusCompare != 0) return statusCompare;
        return '${a['promotor_name'] ?? ''}'.compareTo('${b['promotor_name'] ?? ''}');
      });

      if (!mounted) return;
      setState(() {
        _selectedMonth = resolvedMonth;
        _rows = allRows;
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

  DateTime _parseMonthYear(String value) {
    final parsed = DateFormat('yyyy-MM').tryParseStrict(value);
    return parsed == null
        ? DateTime(DateTime.now().year, DateTime.now().month)
        : DateTime(parsed.year, parsed.month);
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
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

  String _dailyShiftLabel(Map<String, dynamic> row) {
    final shift = '${row['today_shift_type'] ?? ''}';
    if (shift.isEmpty) {
      return 'Hari ini belum ada baris jadwal';
    }
    final status = '${row['today_shift_status'] ?? ''}';
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

  Color _dailyShiftTone(Map<String, dynamic> row) {
    final shift = '${row['today_shift_type'] ?? ''}';
    return shift.isEmpty ? t.textMuted : _dailyShiftColor(shift);
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
    final watchRows = _rows.where(
      (row) => <String>['belum_kirim', 'submitted', 'rejected']
          .contains('${row['status'] ?? ''}'),
    ).toList();
    final approvedRows = _rows.where(
      (row) => '${row['status'] ?? ''}' == 'approved',
    ).toList();

    return Scaffold(
      backgroundColor: t.shellBackground,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 12),
                  _buildMonthCard(),
                  const SizedBox(height: 12),
                  if (_errorMessage != null) _buildErrorCard() else ...[
                    _buildSummaryCard(),
                    const SizedBox(height: 12),
                    _buildTabBar(watchRows.length, approvedRows.length),
                    const SizedBox(height: 12),
                    _buildSection(
                      title: _activeTab == 'watch'
                          ? 'Perlu dipantau'
                          : 'Jadwal approved SATOR',
                      rows: _activeTab == 'watch' ? watchRows : approvedRows,
                      showOpenHint: _activeTab == 'approved',
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildPageHeader() {
    return Row(
      children: [
        InkWell(
          onTap: () => context.pop(),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.surface3),
            ),
            child: Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: t.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SPV • MONITOR JADWAL',
                style: TextStyle(
                  fontSize: AppTypeScale.caption,
                  fontWeight: FontWeight.w800,
                  color: t.primaryAccent,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Jadwal Bulanan',
                style: TextStyle(
                  fontSize: AppTypeScale.title,
                  fontWeight: FontWeight.bold,
                  color: t.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMonthCard() {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
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
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: t.textPrimary,
                ),
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Expanded(child: _buildMiniStat('${_countStatus('belum_kirim')}', 'Belum', t.textMuted)),
          const SizedBox(width: 8),
          Expanded(child: _buildMiniStat('${_countStatus('submitted')}', 'Kirim', t.warning)),
          const SizedBox(width: 8),
          Expanded(child: _buildMiniStat('${_countStatus('approved')}', 'OK', t.success)),
        ],
      ),
    );
  }

  Widget _buildTabBar(int watchCount, int approvedCount) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildTabButton(
              label: 'Perlu dipantau',
              value: 'watch',
              count: watchCount,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildTabButton(
              label: 'Approved',
              value: 'approved',
              count: approvedCount,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String label,
    required String value,
    required int count,
  }) {
    final active = _activeTab == value;
    return InkWell(
      onTap: () => setState(() => _activeTab = value),
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: active ? t.primaryAccentSoft : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? t.primaryAccent.withValues(alpha: 0.22) : Colors.transparent,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: active ? t.primaryAccent : t.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: active
                    ? t.primaryAccent.withValues(alpha: 0.14)
                    : t.surface2,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: active ? t.primaryAccent : t.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMiniStat(String value, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
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
              fontSize: 14,
              height: 1.0,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: TextStyle(
              color: t.textSecondary,
              fontWeight: FontWeight.w700,
              fontSize: 10,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Map<String, dynamic>> rows,
    bool showOpenHint = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: AppTypeScale.bodyStrong,
            ),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Tidak ada data di section ini.',
                style: TextStyle(color: t.textSecondary),
              ),
            )
          else
            ...rows.map((row) => _buildPromotorCard(row, showOpenHint: showOpenHint)),
        ],
      ),
    );
  }

  Widget _buildPromotorCard(Map<String, dynamic> row, {bool showOpenHint = false}) {
    final status = '${row['status'] ?? 'belum_kirim'}';
    final tone = _statusColor(status);
    final updatedAt = DateTime.tryParse('${row['last_updated'] ?? ''}');
    final dailyTone = _dailyShiftTone(row);
    final dailyLabel = _dailyShiftLabel(row);
    final showDailyLabel =
        !(status == 'belum_kirim' && dailyLabel == 'Hari ini belum ada baris jadwal');

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.surface3),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(9, 8, 9, 8),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${row['promotor_name'] ?? ''}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 11.5,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${row['store_name'] ?? '-'}',
                    style: TextStyle(
                      color: t.textSecondary,
                      fontSize: 9.5,
                      fontWeight: FontWeight.w600,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showDailyLabel) ...[
                    const SizedBox(height: 2),
                    Text(
                      dailyLabel,
                      style: TextStyle(
                        fontSize: 9.5,
                        color: dailyTone,
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildPill(_statusLabel(status), tone),
                if (updatedAt != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('dd MMM', 'id_ID').format(updatedAt),
                    style: TextStyle(
                      fontSize: 8.5,
                      color: t.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                if (status != 'belum_kirim') ...[
                  const SizedBox(height: 4),
                  InkWell(
                    onTap: () => _openDetail(row),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
                      decoration: BoxDecoration(
                        color: t.primaryAccentSoft,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: t.primaryAccent.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        'Detail',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          color: t.primaryAccent,
                        ),
                      ),
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

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Text(_errorMessage ?? 'Terjadi kesalahan.'),
    );
  }

  Widget _buildPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
          fontSize: 10,
        ),
      ),
    );
  }
}
