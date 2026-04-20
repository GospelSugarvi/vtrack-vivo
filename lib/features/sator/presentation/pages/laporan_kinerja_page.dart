// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/promotor/promotor.dart';

class LaporanKinerjaPage extends StatefulWidget {
  const LaporanKinerjaPage({super.key});

  @override
  State<LaporanKinerjaPage> createState() => _LaporanKinerjaPageState();
}

class _LaporanKinerjaPageState extends State<LaporanKinerjaPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _rupiah = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _isLoading = true;
  String? _error;
  Map<String, dynamic>? _summary;
  List<Map<String, dynamic>> _promotorRows = [];
  List<Map<String, dynamic>> _storeRows = [];
  List<Map<String, dynamic>> _alerts = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Sesi login tidak ditemukan.');
      }

      final snapshotRaw = await _supabase.rpc(
        'get_sator_laporan_kinerja_snapshot',
        params: {'p_sator_id': userId},
      );
      final snapshot = snapshotRaw is Map
          ? Map<String, dynamic>.from(snapshotRaw)
          : <String, dynamic>{};

      if (!mounted) return;
      setState(() {
        _summary = Map<String, dynamic>.from(
          snapshot['summary'] as Map? ?? const {},
        );
        _promotorRows = _parseMapList(snapshot['promotor_rows']);
        _storeRows = _parseMapList(snapshot['store_rows']);
        _alerts = _parseMapList(snapshot['alerts']);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  String _formatRupiah(num value) => _rupiah.format(value);

  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return 'Minggu aktif';
    return '${DateFormat('d MMM', 'id_ID').format(start)} - ${DateFormat('d MMM yyyy', 'id_ID').format(end)}';
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '-';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  Color _achievementColor(double pct) {
    if (pct >= 80) return t.success;
    if (pct >= 40) return t.warning;
    return t.danger;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: SafeArea(
        child: _isLoading
            ? Center(
                child: CircularProgressIndicator(color: t.primaryAccent),
              )
            : _error != null
            ? _buildErrorState()
            : RefreshIndicator(
                onRefresh: _loadData,
                color: t.primaryAccent,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 16),
                      _buildWeeklyHero(),
                      const SizedBox(height: 14),
                      _buildPromotorSection(),
                      const SizedBox(height: 14),
                      _buildStoreSection(),
                      const SizedBox(height: 14),
                      _buildAlertSection(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildErrorState() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildHeader(),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.surface3),
          ),
          child: Text(
            'Laporan mingguan belum bisa dimuat.\n$_error',
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    final week = _summary?['weekly'] as Map<String, dynamic>? ?? {};
    final weekStart = _parseDate(week['week_start']);
    final weekEnd = _parseDate(week['week_end']);
    return Row(
      children: [
        InkWell(
          onTap: () => context.canPop() ? context.pop() : context.go('/sator'),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.surface3),
            ),
            child: Icon(
              Icons.arrow_back,
              color: t.textSecondary,
              size: 18,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Laporan Mingguan Lengkap',
                style: PromotorText.display(
                  size: 24,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _formatDateRange(weekStart, weekEnd),
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w600,
                  color: t.primaryAccent,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklyHero() {
    final weekly = _summary?['weekly'] as Map<String, dynamic>? ?? {};
    final daily = _summary?['daily'] as Map<String, dynamic>? ?? {};
    final targetOmzet = _toDouble(weekly['target_omzet']);
    final actualOmzet = _toDouble(weekly['actual_omzet']);
    final targetFokus = _toDouble(weekly['target_fokus']);
    final actualFokus = _toDouble(weekly['actual_fokus']);
    final targetPct = targetOmzet > 0
        ? (actualOmzet * 100 / targetOmzet).toDouble()
        : 0.0;
    final attendanceTotal = _toInt(daily['attendance_total']);
    final reportsDone = _toInt(daily['reports_done']);
    final activeStores = _storeRows
        .where((row) => _toDouble(row['omzet']) > 0)
        .length;

    return Container(
      padding: EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: [t.surface1, t.surface2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ringkasan Minggu Ini',
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: t.primaryAccent,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildHeroStat(
                  'Sell Out',
                  _formatRupiah(actualOmzet),
                  'Target ${_formatRupiah(targetOmzet)}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _buildHeroStat(
                  'Produk Fokus',
                  '${actualFokus.toInt()} unit',
                  'Target ${targetFokus.ceil()} unit',
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ((targetPct / 100).clamp(0, 1)).toDouble(),
              minHeight: 8,
              backgroundColor: t.surface3,
              valueColor: AlwaysStoppedAnimation(_achievementColor(targetPct)),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '${targetPct.toStringAsFixed(0)}% menuju target minggu',
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w600,
                  color: t.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '$activeStores toko aktif · $reportsDone/$attendanceTotal laporan',
                style: PromotorText.outfit(
                  size: 8,
                  weight: FontWeight.w700,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeroStat(String label, String value, String hint) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.textOnAccent.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w600,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: PromotorText.display(size: 18, color: t.textSecondary),
          ),
          const SizedBox(height: 3),
          Text(
            hint,
            style: PromotorText.outfit(
              size: 8,
              weight: FontWeight.w700,
              color: t.primaryAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotorSection() {
    return _buildSectionShell(
      title: 'Breakdown per Promotor',
      subtitle: 'Siapa yang memimpin, siapa yang perlu didorong',
      child: _promotorRows.isEmpty
          ? _buildEmpty('Belum ada data promotor minggu ini.')
          : Column(children: _promotorRows.map(_buildPromotorRow).toList()),
    );
  }

  Widget _buildPromotorRow(Map<String, dynamic> row) {
    final pct = _toDouble(row['achievement_pct']);
    final color = _achievementColor(pct);
    final targetOmzet = _toDouble(row['target_weekly_omzet']);
    final actualOmzet = _toDouble(row['actual_weekly_omzet']);
    final targetFocus = _toDouble(row['target_weekly_focus']);
    final actualFocus = _toInt(row['actual_weekly_focus']);
    final status = pct >= 80
        ? 'On Track'
        : pct > 0
        ? 'Perlu Didorong'
        : 'Belum Bergerak';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surface3)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: color.withValues(alpha: 0.45),
                width: 1.3,
              ),
            ),
            child: Center(
              child: Text(
                _initials('${row['name'] ?? '-'}'),
                style: PromotorText.display(size: 15, color: color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['name'] ?? '-'}',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row['store_name'] ?? '-'}',
                  style: PromotorText.outfit(
                    size: 7,
                    weight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Produk Fokus ${targetFocus.ceil()}/$actualFocus unit',
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w700,
                    color: t.primaryAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatRupiah(targetOmzet),
                style: PromotorText.display(size: 13, color: color),
              ),
              Text(
                'target',
                style: PromotorText.outfit(
                  size: 7,
                  weight: FontWeight.w700,
                  color: t.textMuted,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'realisasi ${_formatRupiah(actualOmzet)}',
                style: PromotorText.outfit(
                  size: 7,
                  weight: FontWeight.w600,
                  color: t.textMuted,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$status · ${pct.toStringAsFixed(0)}%',
                style: PromotorText.outfit(
                  size: 7,
                  weight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStoreSection() {
    return _buildSectionShell(
      title: 'Breakdown per Toko',
      subtitle: 'Toko paling aktif dan toko yang masih sunyi minggu ini',
      child: _storeRows.isEmpty
          ? _buildEmpty('Belum ada data toko pada minggu aktif.')
          : Column(children: _storeRows.map(_buildStoreRow).toList()),
    );
  }

  Widget _buildStoreRow(Map<String, dynamic> row) {
    final omzet = _toDouble(row['omzet']);
    final focusUnits = _toInt(row['focus_units']);
    final promotorCount = _toInt(row['promotor_count']);
    final hasSales = omzet > 0;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surface3)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: t.surface3),
            ),
            child: Icon(
              Icons.storefront_rounded,
              size: 16,
              color: hasSales ? t.primaryAccent : t.textMuted,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['store_name'] ?? '-'}',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '$promotorCount promotor · Produk Fokus $focusUnits unit',
                  style: PromotorText.outfit(
                    size: 8,
                    weight: FontWeight.w600,
                    color: t.primaryAccent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatRupiah(omzet),
            style: PromotorText.display(
              size: 13,
              color: hasSales ? t.textSecondary : t.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertSection() {
    return _buildSectionShell(
      title: 'Alert Mingguan',
      subtitle: 'Poin yang perlu ditindak oleh Sator',
      child: _alerts.isEmpty
          ? _buildEmpty(
              'Tidak ada alert besar minggu ini. Ritme tim cukup aman.',
            )
          : Column(children: _alerts.map(_buildAlertRow).toList()),
    );
  }

  Widget _buildAlertRow(Map<String, dynamic> alert) {
    final color = switch ('${alert['tone'] ?? ''}') {
      'danger' => t.danger,
      'warning' => t.warning,
      'primary' => t.primaryAccent,
      _ => t.primaryAccent,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${alert['title'] ?? '-'}',
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${alert['note'] ?? '-'}',
                  style: PromotorText.outfit(
                    size: 8,
                    weight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${alert['count'] ?? 0}',
            style: PromotorText.display(size: 16, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionShell({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: PromotorText.outfit(
              size: 8,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildEmpty(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        message,
        style: PromotorText.outfit(
          size: 11,
          weight: FontWeight.w700,
          color: t.textMuted,
        ),
      ),
    );
  }
}
