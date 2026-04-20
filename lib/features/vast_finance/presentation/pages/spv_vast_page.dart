import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/promotor/promotor.dart';
import '../vast_finance_export.dart';
import '../widgets/vast_promotor_input_viewer.dart';

class SpvVastPage extends StatefulWidget {
  const SpvVastPage({super.key});

  @override
  State<SpvVastPage> createState() => _SpvVastPageState();
}

class _SpvVastPageState extends State<SpvVastPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  FieldThemeTokens get t => context.fieldTokens;
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy', 'id_ID');
  final NumberFormat _currencyFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _isLoading = true;
  String _activeSection = 'performance';
  String _selectedPeriod = 'daily';
  String _profileName = 'SPV';
  String _profileArea = '-';
  String _alertFilter = 'all';
  int _activeWeekPercentage = 25;
  DateTime? _activeWeekStart;
  DateTime? _activeWeekEnd;
  DateTime _snapshotDate = DateTime.now();

  Map<String, dynamic>? _daily;
  Map<String, dynamic>? _weekly;
  Map<String, dynamic>? _monthly;
  List<Map<String, dynamic>> _dailyPromotorRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _weeklyPromotorRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _monthlyPromotorRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _alerts = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>>? _snapshotFuture;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<Map<String, dynamic>> _fetchSnapshot() {
    final existing = _snapshotFuture;
    if (existing != null) return existing;
    final future = () async {
      final raw = await _supabase.rpc(
        'get_spv_vast_page_snapshot',
        params: {'p_date': DateFormat('yyyy-MM-dd').format(_snapshotDate)},
      );
      if (raw is Map<String, dynamic>) return raw;
      if (raw is Map) return Map<String, dynamic>.from(raw);
      return <String, dynamic>{};
    }();
    _snapshotFuture = future;
    return future;
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

  int _closingCount(Map<String, dynamic> summary) {
    return _toInt(summary['total_closed_direct']) +
        _toInt(summary['total_closed_follow_up']);
  }

  List<Map<String, dynamic>> get _selectedPromotorRows {
    switch (_selectedPeriod) {
      case 'weekly':
        return _weeklyPromotorRows;
      case 'monthly':
        return _monthlyPromotorRows;
      default:
        return _dailyPromotorRows;
    }
  }

  bool _hasMeaningfulSummary(Map<String, dynamic>? summary) {
    if (summary == null || summary.isEmpty) return false;
    return _toInt(summary['target_submissions']) > 0 ||
        _toInt(summary['total_submissions']) > 0 ||
        _toInt(summary['total_active_pending']) > 0 ||
        _toInt(summary['total_acc']) > 0 ||
        _toInt(summary['total_reject']) > 0 ||
        _toInt(summary['total_duplicate_alerts']) > 0 ||
        _toInt(summary['promotor_with_input']) > 0;
  }

  Map<String, dynamic> _fallbackSummaryFromRows(
    List<Map<String, dynamic>> rows,
  ) {
    final target = rows.fold<int>(0, (sum, row) => sum + _rowTarget(row));
    final submissions = rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['period_submissions']),
    );
    final pending = rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['pending']),
    );
    final totalAcc = rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['total_acc']),
    );
    final totalReject = rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['total_reject']),
    );
    final duplicates = rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['duplicates']),
    );
    final promotorWithInput = rows
        .where((row) => _toInt(row['period_submissions']) > 0)
        .length;

    return <String, dynamic>{
      'target_submissions': target,
      'total_submissions': submissions,
      'total_active_pending': pending,
      'total_pending': pending,
      'total_acc': totalAcc,
      'total_reject': totalReject,
      'total_duplicate_alerts': duplicates,
      'promotor_with_input': promotorWithInput,
      'achievement_pct': target > 0 ? (submissions * 100.0 / target) : 0,
      'total_closed_direct': totalAcc,
      'total_closed_follow_up': 0,
      'closing_omzet': 0,
    };
  }

  DateTime _periodStart() {
    final now = _snapshotDate;
    if (_selectedPeriod == 'weekly') {
      return _activeWeekStart ?? now;
    }
    if (_selectedPeriod == 'monthly') {
      return DateTime(now.year, now.month, 1);
    }
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _periodEnd() {
    final now = _snapshotDate;
    if (_selectedPeriod == 'weekly') {
      return _activeWeekEnd ?? _periodStart();
    }
    if (_selectedPeriod == 'monthly') {
      return DateTime(now.year, now.month + 1, 0);
    }
    return DateTime(now.year, now.month, now.day);
  }

  Future<void> _openPromotorInputs(Map<String, dynamic> row) async {
    final promotorId = '${row['id'] ?? ''}'.trim();
    if (promotorId.isEmpty) return;
    await VastPromotorInputViewer.show(
      context: context,
      supabase: _supabase,
      promotorId: promotorId,
      promotorName: '${row['name'] ?? 'Promotor'}',
      startDate: _periodStart(),
      endDate: _periodEnd(),
    );
  }

  int _weeklyTargetFromMonthly(int monthlyTarget) {
    if (monthlyTarget <= 0) return 0;
    return ((monthlyTarget * _activeWeekPercentage) / 100).round();
  }

  int _rowTarget(Map<String, dynamic> row) {
    if (_selectedPeriod == 'monthly') {
      return _toInt(row['target']);
    }
    if (_selectedPeriod == 'daily') {
      return _toInt(row['target']);
    }
    final monthlyTarget = _toInt(row['monthly_target']);
    if (_selectedPeriod == 'weekly') {
      return _weeklyTargetFromMonthly(monthlyTarget);
    }
    return _toInt(row['target']);
  }

  int _selectedSummaryTarget() {
    final rows = _selectedPromotorRows;
    if (rows.isNotEmpty) {
      return rows.fold<int>(0, (sum, row) => sum + _rowTarget(row));
    }
    return _toInt(_selectedSummary['target_submissions']);
  }

  double _selectedSummaryAchievementPct() {
    final target = _selectedSummaryTarget();
    final submissions = _toInt(_selectedSummary['total_submissions']);
    if (target > 0) {
      return (submissions * 100) / target;
    }
    return _toNum(_selectedSummary['achievement_pct']).toDouble();
  }

  double get _selectedClosingOmzet {
    return _toNum(_selectedSummary['closing_omzet']).toDouble();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    _snapshotFuture = null;
    try {
      await Future.wait([
        _loadProfile(),
        _loadSummary(),
        _loadSatorRows(),
        _loadAlerts(),
        _loadWeeklyTargetConfig(),
      ]);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadWeeklyTargetConfig() async {
    final today = _snapshotDate;
    final todayIso = DateFormat('yyyy-MM-dd').format(today);
    var percentage = 25;
    DateTime? activeWeekStart;
    DateTime? activeWeekEnd;

    final period = await _supabase
        .from('target_periods')
        .select('id, start_date, end_date')
        .lte('start_date', todayIso)
        .gte('end_date', todayIso)
        .isFilter('deleted_at', null)
        .order('start_date', ascending: false)
        .limit(1)
        .maybeSingle();

    final periodId = period?['id']?.toString();
    final periodStart = DateTime.tryParse('${period?['start_date'] ?? ''}');
    final periodEnd = DateTime.tryParse('${period?['end_date'] ?? ''}');
    if (periodId != null && periodId.isNotEmpty) {
      final rows = await _supabase
          .from('weekly_targets')
          .select('week_number, start_day, end_day, percentage')
          .eq('period_id', periodId)
          .order('week_number');
      for (final item in rows) {
        final row = Map<String, dynamic>.from(item);
        final startDay = _toInt(row['start_day']);
        final endDay = _toInt(row['end_day']);
        if (today.day >= startDay && today.day <= endDay) {
          percentage = _toInt(row['percentage']);
          if (periodStart != null && periodEnd != null) {
            activeWeekStart = DateTime(
              periodStart.year,
              periodStart.month,
              startDay,
            );
            activeWeekEnd = DateTime(
              periodStart.year,
              periodStart.month,
              endDay,
            );
            if (activeWeekStart.isBefore(periodStart)) {
              activeWeekStart = periodStart;
            }
            if (activeWeekEnd.isAfter(periodEnd)) {
              activeWeekEnd = periodEnd;
            }
          }
          break;
        }
      }
    }

    _activeWeekPercentage = percentage <= 0 ? 25 : percentage;
    _activeWeekStart = activeWeekStart;
    _activeWeekEnd = activeWeekEnd;
  }

  Future<void> _pickSnapshotDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _snapshotDate,
      firstDate: DateTime(2024, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      locale: const Locale('id', 'ID'),
    );
    if (picked == null || !mounted) return;
    final normalized = DateTime(picked.year, picked.month, picked.day);
    if (normalized == DateTime(
      _snapshotDate.year,
      _snapshotDate.month,
      _snapshotDate.day,
    )) {
      return;
    }
    setState(() => _snapshotDate = normalized);
    await _refresh();
  }

  Future<void> _loadProfile() async {
    final snapshot = await _fetchSnapshot();
    final profile = Map<String, dynamic>.from(
      (snapshot['profile'] as Map?) ?? const <String, dynamic>{},
    );
    _profileName = '${profile['full_name'] ?? 'SPV'}';
    _profileArea = '${profile['area'] ?? '-'}';
  }

  Future<void> _loadSummary() async {
    final snapshot = await _fetchSnapshot();
    _daily = Map<String, dynamic>.from(
      (snapshot['daily'] as Map?) ?? const <String, dynamic>{},
    );
    _weekly = Map<String, dynamic>.from(
      (snapshot['weekly'] as Map?) ?? const <String, dynamic>{},
    );
    _monthly = Map<String, dynamic>.from(
      (snapshot['monthly'] as Map?) ?? const <String, dynamic>{},
    );
  }

  Future<void> _loadSatorRows() async {
    final snapshot = await _fetchSnapshot();
    _dailyPromotorRows = List<Map<String, dynamic>>.from(
      (snapshot['rows_daily'] as List? ?? const []).whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );
    _weeklyPromotorRows = List<Map<String, dynamic>>.from(
      (snapshot['rows_weekly'] as List? ?? const []).whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );
    _monthlyPromotorRows = List<Map<String, dynamic>>.from(
      (snapshot['rows_monthly'] as List? ?? const []).whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );
  }

  Future<void> _loadAlerts() async {
    final snapshot = await _fetchSnapshot();
    var alerts = List<Map<String, dynamic>>.from(
      (snapshot['alerts'] as List? ?? const []).whereType<Map>().map(
        (item) => Map<String, dynamic>.from(item),
      ),
    );
    if (_alertFilter == 'unread') {
      alerts = alerts.where((row) => row['is_read'] != true).toList();
    } else if (_alertFilter == 'today') {
      final today = DateTime.now();
      alerts = alerts.where((row) {
        final createdAt = DateTime.tryParse('${row['created_at']}');
        return createdAt != null &&
            createdAt.year == today.year &&
            createdAt.month == today.month &&
            createdAt.day == today.day;
      }).toList();
    }
    _alerts = alerts;
  }

  Future<void> _markAlertRead(String alertId) async {
    await _supabase
        .from('vast_alerts')
        .update({'is_read': true, 'read_at': DateTime.now().toIso8601String()})
        .eq('id', alertId);
    await _loadAlerts();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _dismissFraudSignal({
    required String signalId,
    required String alertId,
    required BuildContext sheetContext,
  }) async {
    await _supabase
        .from('vast_fraud_signals')
        .update({
          'status': 'dismissed',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', signalId);
    await _supabase
        .from('vast_alerts')
        .update({'is_read': true, 'read_at': DateTime.now().toIso8601String()})
        .eq('id', alertId);
    if (sheetContext.mounted) {
      Navigator.of(sheetContext).pop();
    }
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Alert duplikasi di-dismiss.')),
      );
    }
  }

  Future<void> _confirmFraudAndCancel({
    required String signalId,
    required String applicationId,
    required String alertId,
    required BuildContext sheetContext,
  }) async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;

    await _supabase
        .from('vast_applications')
        .update({
          'deleted_at': DateTime.now().toIso8601String(),
          'deleted_by_user_id': currentUserId,
          'deleted_reason':
              'Dibatalkan SPV karena fraud duplikasi bukti terverifikasi.',
          'lifecycle_status': 'cancelled',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', applicationId)
        .isFilter('deleted_at', null);

    await _supabase
        .from('vast_fraud_signals')
        .update({
          'status': 'reviewed_valid',
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('id', signalId);

    await _supabase
        .from('vast_alerts')
        .update({'is_read': true, 'read_at': DateTime.now().toIso8601String()})
        .eq('id', alertId);

    if (sheetContext.mounted) {
      Navigator.of(sheetContext).pop();
    }
    await _refresh();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fraud divalidasi. Pengajuan terbaru dibatalkan.'),
        ),
      );
    }
  }

  Future<void> _showAlertDetail(Map<String, dynamic> alert) async {
    final signalId = alert['signal_id']?.toString();
    final applicationId = alert['application_id']?.toString();
    if (signalId == null || applicationId == null) return;

    final signal = await _supabase
        .from('vast_fraud_signals')
        .select(
          'id, matched_application_id, signal_type, severity, summary, '
          'status, detection_payload',
        )
        .eq('id', signalId)
        .maybeSingle();
    if (signal == null || !mounted) return;

    final signalMap = Map<String, dynamic>.from(signal);
    final matchedApplicationId = signalMap['matched_application_id']
        ?.toString();

    final currentApplication = await _supabase
        .from('vast_applications')
        .select(
          'id, customer_name, customer_phone, product_label, pekerjaan, '
          'monthly_income, limit_amount, dp_amount, tenor_months, '
          'application_date, outcome_status, lifecycle_status, notes, deleted_at',
        )
        .eq('id', applicationId)
        .maybeSingle();

    final matchedApplication = matchedApplicationId == null
        ? null
        : await _supabase
              .from('vast_applications')
              .select(
                'id, customer_name, customer_phone, product_label, pekerjaan, '
                'monthly_income, limit_amount, dp_amount, tenor_months, '
                'application_date, outcome_status, lifecycle_status, notes, deleted_at',
              )
              .eq('id', matchedApplicationId)
              .maybeSingle();

    final signalItems = await _supabase
        .from('vast_fraud_signal_items')
        .select(
          'current_evidence_id, matched_evidence_id, match_type, '
          'confidence_score, details',
        )
        .eq('signal_id', signalId);
    final signalItemRows = List<Map<String, dynamic>>.from(signalItems);

    final currentEvidences = await _supabase
        .from('vast_application_evidences')
        .select('id, file_url, evidence_type, created_at')
        .eq('application_id', applicationId)
        .order('created_at', ascending: true);

    final matchedEvidences = matchedApplicationId == null
        ? <dynamic>[]
        : await _supabase
              .from('vast_application_evidences')
              .select('id, file_url, evidence_type, created_at')
              .eq('application_id', matchedApplicationId)
              .order('created_at', ascending: true);

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) {
        final status = signalMap['status']?.toString() ?? 'open';
        final isResolved = status == 'reviewed_valid' || status == 'dismissed';
        final currentDeleted =
            (currentApplication?['deleted_at']?.toString() ?? '').isNotEmpty;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          maxChildSize: 0.96,
          minChildSize: 0.55,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.surface3,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Review Duplikasi',
                    style: PromotorText.display(size: 22, color: t.textPrimary),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _reviewPill(
                        'Tipe ${(signalMap['signal_type']?.toString() ?? '-').replaceAll('_', ' ')}',
                      ),
                      _reviewPill(
                        'Severity ${(signalMap['severity']?.toString() ?? '-').toUpperCase()}',
                      ),
                      _reviewPill('Status ${status.toUpperCase()}'),
                      if (signalItemRows.isNotEmpty)
                        _reviewPill(
                          'Confidence ${((_toNum(signalItemRows.first['confidence_score']) * 100)).toStringAsFixed(0)}%',
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    signalMap['summary']?.toString() ??
                        alert['body'].toString(),
                    style: PromotorText.outfit(
                      size: 13,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (currentApplication != null)
                    _buildApplicationReviewCard(
                      title: 'Pengajuan Baru',
                      item: Map<String, dynamic>.from(currentApplication),
                      evidences: List<Map<String, dynamic>>.from(
                        currentEvidences,
                      ),
                    ),
                  if (matchedApplication != null) ...[
                    const SizedBox(height: 16),
                    _buildApplicationReviewCard(
                      title: 'Pengajuan Pembanding',
                      item: Map<String, dynamic>.from(matchedApplication),
                      evidences: List<Map<String, dynamic>>.from(
                        matchedEvidences,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  if (!isResolved && !currentDeleted)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _dismissFraudSignal(
                              signalId: signalId,
                              alertId: alert['id'] as String,
                              sheetContext: context,
                            ),
                            child: const Text('Dismiss'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: t.danger,
                              foregroundColor: t.shellBackground,
                            ),
                            onPressed: () => _confirmFraudAndCancel(
                              signalId: signalId,
                              applicationId: applicationId,
                              alertId: alert['id'] as String,
                              sheetContext: context,
                            ),
                            child: const Text('Valid Fraud'),
                          ),
                        ),
                      ],
                    )
                  else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Text(
                        currentDeleted
                            ? 'Pengajuan terbaru sudah dibatalkan oleh SPV.'
                            : 'Alert ini sudah ditindaklanjuti.',
                        style: PromotorText.outfit(
                          size: 12,
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _export() async {
    final rowsForExport = _selectedPromotorRows;
    final path = await VastFinanceExport.exportXlsx(
      fileName:
          'VAST_SPV_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx',
      headers: const <String>[
        'Promotor',
        'Toko',
        'Input Periode',
        'Target',
        'Pending',
        'Closing',
        'Nominal Closing',
        'Reject',
        'Persentase',
      ],
      rows: rowsForExport
          .map(
            (row) => <Object?>[
              row['name'],
              row['store_name'],
              row['period_submissions'],
              _rowTarget(row),
              row['pending'],
              row['total_acc'],
              _toNum(row['closing_omzet']),
              row['total_reject'],
              (_rowTarget(row) > 0
                      ? (_toInt(row['period_submissions']) * 100) /
                            _rowTarget(row)
                      : _toNum(row['achievement_pct']))
                  .toStringAsFixed(1),
            ],
          )
          .toList(),
      sheetName: 'VAST SPV',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Export tersimpan di $path')));
  }

  Map<String, dynamic> get _selectedSummary {
    final rows = _selectedPromotorRows;
    switch (_selectedPeriod) {
      case 'weekly':
        if (_hasMeaningfulSummary(_weekly)) {
          return _weekly ?? <String, dynamic>{};
        }
        return _fallbackSummaryFromRows(rows);
      case 'monthly':
        if (_hasMeaningfulSummary(_monthly)) {
          return _monthly ?? <String, dynamic>{};
        }
        return _fallbackSummaryFromRows(rows);
      default:
        if (_hasMeaningfulSummary(_daily)) {
          return _daily ?? <String, dynamic>{};
        }
        return _fallbackSummaryFromRows(rows);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.shellBackground,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
          : RefreshIndicator(
              onRefresh: _refresh,
              color: t.primaryAccent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _buildHeader(),
                    _buildHero(),
                    const SizedBox(height: 12),
                    _buildSummaryBand(),
                    const SizedBox(height: 12),
                    _buildQuickActions(),
                    const SizedBox(height: 12),
                    _buildSectionCard(_sectionTitle, _buildSectionBody()),
                  ],
                ),
              ),
            ),
    );
  }

  String get _sectionTitle {
    switch (_activeSection) {
      case 'performance':
        return 'Rekap Tim';
      case 'alert':
        return 'Duplikasi Data Alert';
      case 'export':
        return 'Export';
      default:
        return 'Rekap Tim';
    }
  }

  Widget _buildSectionBody() {
    switch (_activeSection) {
      case 'performance':
        return _buildPerformanceSection();
      case 'alert':
        return _buildAlertSection();
      case 'export':
        return _buildExportSection();
      default:
        return _buildPerformanceSection();
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.surface3),
              ),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 18,
                color: t.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _profileName,
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: t.primaryAccent,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'VAST Finance',
                  style: PromotorText.display(size: 20, color: t.textPrimary),
                ),
                Text(
                  _profileArea,
                  style: PromotorText.outfit(size: 11, color: t.textMuted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              InkWell(
                onTap: _pickSnapshotDate,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.calendar_month_rounded,
                        size: 14,
                        color: t.primaryAccent,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _dateFormat.format(_snapshotDate),
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w800,
                          color: t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHero() {
    final summary = _selectedSummary;
    final target = _selectedSummaryTarget();
    final achievement = _selectedSummaryAchievementPct();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [t.surface1, t.surface2],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.primaryAccentGlow),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Spacer(),
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 0.42,
                      child: _buildPeriodTabs(),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  'Nominal Closing',
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: t.textMutedStrong,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _currencyFormat.format(_selectedClosingOmzet),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.display(size: 28, color: t.textPrimary),
                ),
                const SizedBox(height: 12),
                _buildHeroInfoStrip(summary, target, achievement),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeroInfoStrip(
    Map<String, dynamic> summary,
    int target,
    double achievement,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = math.max(0.0, (constraints.maxWidth - 12) / 2);
        final cards = [
          _heroDualMiniCard(
            leftLabel: 'Target',
            leftValue: '$target',
            rightLabel: 'Achv',
            rightValue: '${achievement.toStringAsFixed(1)}%',
          ),
          _heroMiniCard(
            'Promotor',
            '${_toInt(summary['promotor_with_input'])}',
          ),
        ];
        return Wrap(
          spacing: 12,
          runSpacing: 8,
          children: cards
              .map((child) => SizedBox(width: itemWidth, child: child))
              .toList(),
        );
      },
    );
  }

  Widget _heroDualMiniCard({
    required String leftLabel,
    required String leftValue,
    required String rightLabel,
    required String rightValue,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  leftLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 8.5,
                    weight: FontWeight.w700,
                    color: t.textMutedStrong,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  leftValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.display(size: 14, color: t.textPrimary),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 26, color: t.surface3),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rightLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 8.5,
                    weight: FontWeight.w700,
                    color: t.textMutedStrong,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  rightValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.display(size: 14, color: t.textPrimary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroMiniCard(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 8.5,
              weight: FontWeight.w700,
              color: t.textMutedStrong,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.display(size: 14, color: t.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _summaryMetricTile({
    required String label,
    required int value,
    required int target,
    required Color accent,
  }) {
    final percent = target <= 0 ? 0 : ((value / target) * 100).round();
    return _buildKpiCard(
      label: label,
      value: '$value',
      percentLabel: '$percent%',
      accent: accent,
    );
  }

  Widget _buildKpiCard({
    required String label,
    required String value,
    required String percentLabel,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const Spacer(),
              Text(
                percentLabel,
                style: PromotorText.outfit(
                  size: 12,
                  weight: FontWeight.w800,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: PromotorText.display(size: 14, color: t.textPrimary),
          ),
          const SizedBox(height: 1),
          Text(
            label,
            style: PromotorText.outfit(
              size: 8.5,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBand() {
    final summary = _selectedSummary;
    final target = _selectedSummaryTarget();
    final items = [
      _summaryMetricTile(
        label: 'Input',
        value: _toInt(summary['total_submissions']),
        target: target,
        accent: t.primaryAccent,
      ),
      _summaryMetricTile(
        label: 'Closing',
        value: _closingCount(summary),
        target: target,
        accent: const Color(0xFF0F8A6C),
      ),
      _summaryMetricTile(
        label: 'Pending',
        value: _toInt(summary['total_active_pending']),
        target: target,
        accent: const Color(0xFFC98210),
      ),
      _summaryMetricTile(
        label: 'Reject',
        value: _toInt(summary['total_reject']),
        target: target,
        accent: const Color(0xFFC14444),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          children: List<Widget>.generate(items.length, (index) {
            return Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: index == items.length - 1
                      ? null
                      : Border(right: BorderSide(color: t.surface3)),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: items[index],
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildPeriodTabs() {
    final tabs = const [
      ('daily', 'Harian'),
      ('weekly', 'Mingguan'),
      ('monthly', 'Bulanan'),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: tabs.map((tab) {
          final active = _selectedPeriod == tab.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriod = tab.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? t.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tab.$2,
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: active ? t.textOnAccent : t.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = <_ActionItem>[
      const _ActionItem('performance', Icons.groups_2_outlined, 'Tim'),
      const _ActionItem('alert', Icons.warning_amber_rounded, 'Duplikasi'),
      const _ActionItem('export', Icons.file_download_outlined, 'Export'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          children: actions.map((item) {
            final active = item.keyName == _activeSection;
            return Expanded(
              child: InkWell(
                onTap: () => setState(() => _activeSection = item.keyName),
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: active ? t.primaryAccent : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active ? t.primaryAccent : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        item.icon,
                        size: 16,
                        color: active ? t.textOnAccent : t.textSecondary,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          style: PromotorText.outfit(
                            size: 10,
                            weight: FontWeight.w800,
                            color: active ? t.textOnAccent : t.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSectionCard(String title, Widget child) {
    return PromotorCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: PromotorText.outfit(
                  size: 14,
                  weight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ),
          ),
          Divider(height: 1, color: t.surface3),
          child,
        ],
      ),
    );
  }

  Widget _buildPerformanceSection() {
    final promotorRows = _selectedPromotorRows;
    if (promotorRows.isEmpty) {
      return _empty('Belum ada data promotor.');
    }
    final totalTarget = promotorRows.fold<int>(
      0,
      (sum, row) => sum + _rowTarget(row),
    );
    final totalInput = promotorRows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['period_submissions']),
    );
    final totalPending = promotorRows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['pending']),
    );
    final totalClosing = promotorRows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['total_acc']),
    );
    final totalReject = promotorRows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['total_reject']),
    );
    final totalClosingOmzet = promotorRows.fold<num>(
      0,
      (sum, row) => sum + _toNum(row['closing_omzet']),
    );
    final totalPct = totalTarget > 0 ? (totalInput * 100 / totalTarget) : 0.0;

    Widget headerCell(
      String text, {
      required int flex,
      TextAlign align = TextAlign.left,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: align == TextAlign.right
                ? Alignment.centerRight
                : align == TextAlign.center
                ? Alignment.center
                : Alignment.centerLeft,
            child: Text(
              text,
              textAlign: align,
              style: PromotorText.outfit(
                size: 8.5,
                weight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ),
        ),
      );
    }

    Widget bodyCell(
      String text, {
      required int flex,
      TextAlign align = TextAlign.left,
      Color? color,
      FontWeight weight = FontWeight.w700,
      bool scaleDown = false,
    }) {
      return Expanded(
        flex: flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: scaleDown
              ? FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: align == TextAlign.right
                      ? Alignment.centerRight
                      : align == TextAlign.center
                      ? Alignment.center
                      : Alignment.centerLeft,
                  child: Text(
                    text,
                    textAlign: align,
                    maxLines: 1,
                    style: PromotorText.outfit(
                      size: 8.5,
                      weight: weight,
                      color: color ?? t.textPrimary,
                    ),
                  ),
                )
              : Text(
                  text,
                  textAlign: align,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 8.5,
                    weight: weight,
                    color: color ?? t.textPrimary,
                  ),
                ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.surface3),
          ),
          child: Column(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13),
                  ),
                ),
                child: Row(
                  children: [
                    headerCell('Promotor', flex: 3),
                    headerCell('Toko', flex: 2),
                    headerCell('Tgt/In', flex: 2, align: TextAlign.center),
                    headerCell('P/C/R', flex: 2, align: TextAlign.center),
                    headerCell('Nom', flex: 2, align: TextAlign.right),
                    headerCell('Achv', flex: 1, align: TextAlign.right),
                  ],
                ),
              ),
              ...List<Widget>.generate(promotorRows.length, (index) {
                final row = promotorRows[index];
                final rowTarget = _rowTarget(row);
                final rowInput = _toInt(row['period_submissions']);
                final underperform = rowTarget > 0 && rowInput < rowTarget;
                return InkWell(
                  onTap: () => _openPromotorInputs(row),
                  child: Container(
                    decoration: BoxDecoration(
                      color: underperform ? t.dangerSoft : Colors.transparent,
                      border: index == promotorRows.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: t.surface3)),
                    ),
                    child: Row(
                      children: [
                        bodyCell(
                          '${row['name']}',
                          flex: 3,
                          weight: FontWeight.w800,
                        ),
                        bodyCell(
                          '${row['store_name']}',
                          flex: 2,
                          color: t.textSecondary,
                        ),
                        bodyCell(
                          '$rowTarget/${row['period_submissions']}',
                          flex: 2,
                          align: TextAlign.center,
                          color: t.primaryAccent,
                        ),
                        bodyCell(
                          '${row['pending']}/${row['total_acc']}/${row['total_reject']}',
                          flex: 2,
                          align: TextAlign.center,
                          scaleDown: true,
                        ),
                        bodyCell(
                          _currencyFormat.format(_toNum(row['closing_omzet'])),
                          flex: 2,
                          align: TextAlign.right,
                          color: const Color(0xFF0F8A6C),
                          scaleDown: true,
                        ),
                        bodyCell(
                          rowTarget > 0
                              ? '${((rowInput * 100) / rowTarget).toStringAsFixed(1)}%'
                              : '${_toNum(row['achievement_pct']).toStringAsFixed(1)}%',
                          flex: 1,
                          align: TextAlign.right,
                          color: underperform ? t.danger : t.primaryAccent,
                          weight: FontWeight.w800,
                        ),
                      ],
                    ),
                  ),
                );
              }),
              Container(
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(13),
                  ),
                  border: Border(top: BorderSide(color: t.surface3)),
                ),
                child: Row(
                  children: [
                    bodyCell(
                      'TOTAL',
                      flex: 5,
                      color: t.primaryAccent,
                      weight: FontWeight.w800,
                    ),
                    bodyCell(
                      '$totalTarget/$totalInput',
                      flex: 2,
                      align: TextAlign.center,
                      color: t.primaryAccent,
                      weight: FontWeight.w800,
                    ),
                    bodyCell(
                      '$totalPending/$totalClosing/$totalReject',
                      flex: 2,
                      align: TextAlign.center,
                      weight: FontWeight.w800,
                      scaleDown: true,
                    ),
                    bodyCell(
                      _currencyFormat.format(totalClosingOmzet),
                      flex: 2,
                      align: TextAlign.right,
                      color: const Color(0xFF0F8A6C),
                      weight: FontWeight.w800,
                      scaleDown: true,
                    ),
                    bodyCell(
                      '${totalPct.toStringAsFixed(1)}%',
                      flex: 1,
                      align: TextAlign.right,
                      color: t.primaryAccent,
                      weight: FontWeight.w800,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.surface3),
          ),
          child: Wrap(
            spacing: 10,
            runSpacing: 6,
            children: [
              _tinyTotal('Total Target', '$totalTarget', t.textPrimary),
              _tinyTotal('Total Input', '$totalInput', t.primaryAccent),
              _tinyTotal('Pending', '$totalPending', const Color(0xFFC98210)),
              _tinyTotal('Closing', '$totalClosing', const Color(0xFF0F8A6C)),
              _tinyTotal(
                'Nominal Closing',
                _currencyFormat.format(totalClosingOmzet),
                const Color(0xFF0F8A6C),
              ),
              _tinyTotal('Reject', '$totalReject', const Color(0xFFC14444)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAlertSection() {
    final filters = <String, String>{
      'all': 'Semua',
      'unread': 'Unread',
      'today': 'Hari Ini',
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.surface3),
            ),
            child: Row(
              children: filters.entries.map((entry) {
                final active = _alertFilter == entry.key;
                return Expanded(
                  child: InkWell(
                    onTap: () async {
                      setState(() => _alertFilter = entry.key);
                      await _loadAlerts();
                      if (mounted) setState(() {});
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: active ? t.primaryAccent : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        entry.value,
                        textAlign: TextAlign.center,
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w800,
                          color: active ? t.textOnAccent : t.textSecondary,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 12),
          if (_alerts.isEmpty)
            _empty('Belum ada alert.')
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _alerts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final item = _alerts[index];
                final isRead = item['is_read'] == true;
                return InkWell(
                  onTap: () => _showAlertDetail(item),
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isRead ? t.surface3 : t.warning,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: isRead ? t.surface2 : t.warningSoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.warning_amber_rounded,
                                size: 18,
                                color: isRead ? t.textSecondary : t.warning,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${item['title']}',
                                    style: PromotorText.outfit(
                                      size: 12.5,
                                      weight: FontWeight.w800,
                                      color: t.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isRead
                                          ? t.surface2
                                          : t.warningSoft,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      isRead ? 'Sudah dibaca' : 'Perlu review',
                                      style: PromotorText.outfit(
                                        size: 9,
                                        weight: FontWeight.w800,
                                        color: isRead
                                            ? t.textSecondary
                                            : t.warning,
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(
                                      10,
                                      0,
                                      10,
                                      10,
                                    ),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: Text(
                                        'Tap baris promotor untuk lihat input VAST yang sudah dikirim.',
                                        style: PromotorText.outfit(
                                          size: 9.5,
                                          weight: FontWeight.w700,
                                          color: t.textMuted,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (!isRead) ...[
                              const SizedBox(width: 8),
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: t.primaryAccent,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 6,
                                  ),
                                ),
                                onPressed: () =>
                                    _markAlertRead(item['id'] as String),
                                child: const Text('Tandai'),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '${item['body']}',
                          style: PromotorText.outfit(
                            size: 12,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _dateFormat.format(
                            DateTime.tryParse('${item['created_at']}') ??
                                DateTime.now(),
                          ),
                          style: PromotorText.outfit(
                            size: 11,
                            weight: FontWeight.w700,
                            color: t.primaryAccent,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Icon(
                              Icons.open_in_new_rounded,
                              size: 14,
                              color: t.primaryAccent,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Buka detail',
                              style: PromotorText.outfit(
                                size: 10,
                                weight: FontWeight.w800,
                                color: t.primaryAccent,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Keterangan lengkap ada di bagian bawah halaman.',
                          style: PromotorText.outfit(
                            size: 9.5,
                            weight: FontWeight.w700,
                            color: t.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildExportSection() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _selectedPromotorRows.isEmpty ? null : _export,
              style: FilledButton.styleFrom(
                backgroundColor: t.primaryAccent,
                foregroundColor: t.shellBackground,
              ),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Export XLSX'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _pill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Text(text, style: PromotorText.outfit(size: 10)),
    );
  }

  Widget _tinyTotal(String label, String value, Color tone) {
    return RichText(
      text: TextSpan(
        style: PromotorText.outfit(
          size: 9,
          weight: FontWeight.w700,
          color: t.textSecondary,
        ),
        children: [
          TextSpan(text: '$label: '),
          TextSpan(
            text: value,
            style: PromotorText.outfit(
              size: 9.5,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _reviewPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 10,
          weight: FontWeight.w700,
          color: t.textPrimary,
        ),
      ),
    );
  }

  Widget _empty(String text) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: PromotorText.outfit(size: 12, color: t.textSecondary),
        ),
      ),
    );
  }

  Widget _buildApplicationReviewCard({
    required String title,
    required Map<String, dynamic> item,
    required List<Map<String, dynamic>> evidences,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(item['customer_name']?.toString() ?? '-'),
              _pill(item['product_label']?.toString() ?? '-'),
              _pill(item['customer_phone']?.toString() ?? '-'),
              _pill('${_toInt(item['tenor_months'])} bulan'),
              _pill((item['outcome_status']?.toString() ?? '-').toUpperCase()),
              _pill(item['lifecycle_status']?.toString() ?? '-'),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Pekerjaan: ${item['pekerjaan'] ?? '-'}\n'
            'Penghasilan: ${_toNum(item['monthly_income'])}\n'
            'Limit: ${_toNum(item['limit_amount'])}\n'
            'DP: ${_toNum(item['dp_amount'])}\n'
            'Tanggal: ${_dateFormat.format(DateTime.tryParse('${item['application_date']}') ?? DateTime.now())}\n'
            'Catatan: ${item['notes'] ?? '-'}',
            style: PromotorText.outfit(size: 12, color: t.textPrimary),
          ),
          const SizedBox(height: 12),
          if (evidences.isEmpty)
            Text(
              'Tidak ada bukti foto.',
              style: PromotorText.outfit(size: 12, color: t.textSecondary),
            )
          else
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: evidences.map((evidence) {
                final imageUrl = evidence['file_url']?.toString() ?? '';
                return SizedBox(
                  width: 132,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: imageUrl.isEmpty
                              ? Container(
                                  color: t.surface1,
                                  alignment: Alignment.center,
                                  child: Icon(
                                    Icons.broken_image_outlined,
                                    color: t.textSecondary,
                                  ),
                                )
                              : Image.network(
                                  imageUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: t.surface1,
                                      alignment: Alignment.center,
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: t.textSecondary,
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        evidence['evidence_type']?.toString() ?? '-',
                        style: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _ActionItem {
  const _ActionItem(this.keyName, this.icon, this.label);

  final String keyName;
  final IconData icon;
  final String label;
}
