import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../ui/promotor/promotor.dart';

class LaporanAllbrandPage extends StatefulWidget {
  const LaporanAllbrandPage({super.key});

  @override
  State<LaporanAllbrandPage> createState() => _LaporanAllbrandPageState();
}

class _LaporanAllbrandPageState extends State<LaporanAllbrandPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _dateFormat = DateFormat('dd MMM yyyy');
  late DateTime _selectedMonth;

  bool _isLoading = true;
  String? _storeId;
  String _storeName = '-';
  List<Map<String, dynamic>> _rows = const [];
  bool _hasTodayReport = false;
  num _targetOmzetMonth = 0;
  int _targetFokusMonth = 0;
  int _targetSpecialMonth = 0;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User tidak ditemukan');

      final assignmentRows = await _supabase
          .from('assignments_promotor_store')
          .select('store_id, stores(store_name)')
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1);

      final assignments = List<Map<String, dynamic>>.from(assignmentRows);
      if (assignments.isEmpty) {
        if (!mounted) return;
        setState(() {
          _storeId = null;
          _storeName = '-';
          _rows = const [];
          _isLoading = false;
        });
        return;
      }

      final assignment = assignments.first;
      final storeId = '${assignment['store_id'] ?? ''}';
      final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
      final nextMonthStart = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
      final targetPeriodRows = await _supabase
          .from('target_periods')
          .select('id')
          .eq('target_month', _selectedMonth.month)
          .eq('target_year', _selectedMonth.year)
          .isFilter('deleted_at', null)
          .order('start_date', ascending: false)
          .limit(1);
      final periodId = targetPeriodRows.isEmpty
          ? null
          : '${targetPeriodRows.first['id'] ?? ''}'.trim();
      Map<String, dynamic>? targetRow;
      if (periodId != null && periodId.isNotEmpty) {
        targetRow = await _supabase
            .from('user_targets')
            .select(
              'target_omzet, target_fokus_total, target_special, '
              'target_special_detail',
            )
            .eq('user_id', userId)
            .eq('period_id', periodId)
            .maybeSingle();
      }

      final reportRows = await _supabase
          .from('allbrand_reports')
          .select('id, report_date, daily_total_units, cumulative_total_units, notes, updated_at')
          .eq('store_id', storeId)
          .gte('report_date', monthStart.toIso8601String().split('T').first)
          .lt('report_date', nextMonthStart.toIso8601String().split('T').first)
          .order('report_date', ascending: false)
          .limit(60);

      final today = DateTime.now().toIso8601String().split('T').first;
      final todayReport = await _supabase
          .from('allbrand_reports')
          .select('id')
          .eq('store_id', storeId)
          .eq('report_date', today)
          .order('updated_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      final targetMap = targetRow == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(targetRow);
      final specialDetail = _safeMap(targetMap['target_special_detail']);
      final targetSpecialMonth = specialDetail.isNotEmpty
          ? specialDetail.values.fold<int>(
              0,
              (sum, value) => sum + _asInt(value),
            )
          : _asInt(targetMap['target_special']);
      setState(() {
        _storeId = storeId;
        _storeName = '${assignment['stores']?['store_name'] ?? '-'}';
        _rows = List<Map<String, dynamic>>.from(reportRows);
        _hasTodayReport = todayReport != null;
        _targetOmzetMonth = targetMap['target_omzet'] as num? ?? 0;
        _targetFokusMonth = _asInt(targetMap['target_fokus_total']);
        _targetSpecialMonth = targetSpecialMonth;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _hasTodayReport = false;
        _targetOmzetMonth = 0;
        _targetFokusMonth = 0;
        _targetSpecialMonth = 0;
        _isLoading = false;
      });
    }
  }

  String _formatDate(dynamic value) {
    final parsed = DateTime.tryParse('${value ?? ''}');
    if (parsed == null) return '-';
    return _dateFormat.format(parsed.toLocal());
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Map<String, dynamic> _safeMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const <String, dynamic>{};
  }

  String _formatCompactCurrency(num value) {
    if (value <= 0) return 'Rp 0';
    final abs = value.abs().toDouble();
    if (abs >= 1000000000) {
      return 'Rp ${(value / 1000000000).toStringAsFixed(abs >= 10000000000 ? 0 : 1)} M';
    }
    if (abs >= 1000000) {
      return 'Rp ${(value / 1000000).toStringAsFixed(abs >= 10000000 ? 0 : 1)} Jt';
    }
    if (abs >= 1000) {
      return 'Rp ${(value / 1000).toStringAsFixed(abs >= 10000 ? 0 : 1)} Rb';
    }
    return 'Rp ${value.toStringAsFixed(0)}';
  }

  String _formatMonthLabel(DateTime value) {
    const months = [
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    return '${months[value.month - 1]} ${value.year}';
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(now.year - 2, 1),
      lastDate: DateTime(now.year + 1, 12, 31),
      helpText: 'Pilih bulan laporan',
      fieldHintText: 'MM/YYYY',
      initialEntryMode: DatePickerEntryMode.calendarOnly,
    );

    if (picked == null || !mounted) return;

    final nextValue = DateTime(picked.year, picked.month);
    if (nextValue.year == _selectedMonth.year &&
        nextValue.month == _selectedMonth.month) {
      return;
    }

    setState(() {
      _selectedMonth = nextValue;
    });
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return Scaffold(
      backgroundColor: t.background,
      floatingActionButton: _storeId == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.pushNamed('laporan-allbrand-input'),
              backgroundColor: t.primaryAccent,
              foregroundColor: t.textOnAccent,
              icon: Icon(_hasTodayReport ? Icons.edit_rounded : Icons.add),
              label: Text(_hasTodayReport ? 'Ubah Hari Ini' : 'Input'),
            ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: EdgeInsets.fromLTRB(16, topInset + 12, 16, 90),
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 12),
                  _HeaderCard(
                    storeName: _storeName,
                    count: _rows.length,
                    hasTodayReport: _hasTodayReport,
                    monthLabel: _formatMonthLabel(_selectedMonth),
                    targetOmzetMonth: _formatCompactCurrency(_targetOmzetMonth),
                    targetFokusMonth: _targetFokusMonth,
                    targetSpecialMonth: _targetSpecialMonth,
                  ),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Text(
                      'Riwayat laporan',
                      style: PromotorText.outfit(
                        size: 12,
                        weight: FontWeight.w700,
                        color: t.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_rows.isEmpty)
                    _EmptyState(
                      title: 'Belum ada laporan',
                      monthLabel: _formatMonthLabel(_selectedMonth),
                    )
                  else
                    ..._rows.map(
                      (row) => Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: t.surface3),
                        ),
                        child: ListTile(
                          onTap: () => context.pushNamed(
                            'laporan-allbrand-detail',
                            pathParameters: {
                              'reportId': '${row['id']}',
                            },
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 6,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          title: Text(
                            _formatDate(row['report_date']),
                            style: PromotorText.outfit(
                              size: 14,
                              weight: FontWeight.w800,
                              color: t.textPrimary,
                            ),
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _buildMetricPill(
                                  'Harian ${_asInt(row['daily_total_units'])}',
                                ),
                                _buildMetricPill(
                                  'Total ${_asInt(row['cumulative_total_units'])}',
                                  isAccent: true,
                                ),
                              ],
                            ),
                          ),
                          trailing: Icon(
                            Icons.chevron_right_rounded,
                            color: t.textMutedStrong,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildPageHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.surface1, t.background],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          _HeaderIconButton(
            icon: Icons.arrow_back_rounded,
            onTap: () => context.pop(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Laporan All Brand',
              style: PromotorText.display(size: 20, color: t.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          _MonthFilterChip(
            label: _formatMonthLabel(_selectedMonth),
            onTap: _pickMonth,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricPill(String label, {bool isAccent = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isAccent ? t.primaryAccentSoft : t.surface2,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 11,
          weight: FontWeight.w700,
          color: isAccent ? t.primaryAccent : t.textSecondary,
        ),
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    required this.icon,
    required this.onTap,
  });

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Material(
      color: t.surface2,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(icon, color: t.textPrimary, size: 22),
        ),
      ),
    );
  }
}

class _MonthFilterChip extends StatelessWidget {
  const _MonthFilterChip({
    required this.label,
    required this.onTap,
  });

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Material(
      color: t.primaryAccentSoft,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.calendar_month_rounded,
                size: 16,
                color: t.primaryAccent,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w800,
                  color: t.primaryAccent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.storeName,
    required this.count,
    required this.hasTodayReport,
    required this.monthLabel,
    required this.targetOmzetMonth,
    required this.targetFokusMonth,
    required this.targetSpecialMonth,
  });

  final String storeName;
  final int count;
  final bool hasTodayReport;
  final String monthLabel;
  final String targetOmzetMonth;
  final int targetFokusMonth;
  final int targetSpecialMonth;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: t.primaryAccentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.storefront_rounded,
                  color: t.primaryAccent,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      monthLabel,
                      style: PromotorText.outfit(
                        size: 11,
                        weight: FontWeight.w700,
                        color: t.primaryAccent,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      storeName,
                      style: PromotorText.display(size: 17, color: t.textPrimary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hasTodayReport
                          ? 'Laporan hari ini sudah ada'
                          : 'Belum ada laporan hari ini',
                      style: PromotorText.outfit(
                        size: 12,
                        weight: FontWeight.w700,
                        color: hasTodayReport ? t.success : t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Text(
                      '$count',
                      style: PromotorText.display(size: 16, color: t.textPrimary),
                    ),
                    Text(
                      'Data',
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w700,
                        color: t.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _TargetPill(label: 'Target Bulanan', value: targetOmzetMonth),
              _TargetPill(label: 'Fokus', value: '$targetFokusMonth unit'),
              _TargetPill(
                label: 'Tipe Khusus',
                value: '$targetSpecialMonth unit',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TargetPill extends StatelessWidget {
  const _TargetPill({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({
    required this.title,
    required this.monthLabel,
  });

  final String title;
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: t.textMutedStrong),
          const SizedBox(height: 12),
          Text(
            title,
            style: PromotorText.outfit(
              size: 14,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Belum ada data untuk $monthLabel.',
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
