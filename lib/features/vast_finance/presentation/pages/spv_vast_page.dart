import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/promotor/promotor.dart';
import '../vast_finance_export.dart';

class SpvVastPage extends StatefulWidget {
  const SpvVastPage({super.key});

  @override
  State<SpvVastPage> createState() => _SpvVastPageState();
}

class _SpvVastPageState extends State<SpvVastPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  FieldThemeTokens get t => context.fieldTokens;
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy', 'id_ID');

  bool _isLoading = true;
  String _activeSection = 'home';
  String _selectedPeriod = 'daily';
  String _profileName = 'SPV';
  String _profileArea = '-';
  String _alertFilter = 'all';

  Map<String, dynamic>? _daily;
  Map<String, dynamic>? _weekly;
  Map<String, dynamic>? _monthly;
  List<Map<String, dynamic>> _dailyPromotorRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _weeklyPromotorRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _monthlyPromotorRows = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _alerts = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _refresh();
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

  int _resolvePeriodTarget({
    required int monthlyTarget,
    required Map<String, dynamic> source,
    required String periodKey,
  }) {
    final aggregateTarget = _toInt(source['target_submissions']);
    if (periodKey == 'monthly' && aggregateTarget > 0) {
      return aggregateTarget;
    }
    if (monthlyTarget <= 0) {
      return 0;
    }
    if (periodKey == 'weekly') {
      final weeklyTargets = _buildWeeklyTargets(monthlyTarget);
      return weeklyTargets[_currentWeekIndex()];
    }
    if (periodKey == 'daily') {
      final now = DateTime.now();
      final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
      return (monthlyTarget / daysInMonth).ceil();
    }
    return monthlyTarget;
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

  int get _monthlyTeamTarget {
    final total = _monthlyPromotorRows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['monthly_target']),
    );
    if (total > 0) {
      return total;
    }
    return _toInt(_monthly?['target_submissions']);
  }

  String get _periodLabel {
    switch (_selectedPeriod) {
      case 'weekly':
        return 'Minggu Ini';
      case 'monthly':
        return 'Bulan Ini';
      default:
        return 'Hari Ini';
    }
  }

  String get _periodColumnLabel {
    switch (_selectedPeriod) {
      case 'weekly':
        return 'Pengajuan Minggu';
      case 'monthly':
        return 'Pengajuan Bulan';
      default:
        return 'Pengajuan Hari';
    }
  }

  String _periodRangeLabel() {
    final now = DateTime.now();
    if (_selectedPeriod == 'weekly') {
      final start = now.subtract(Duration(days: now.weekday - 1));
      final end = start.add(const Duration(days: 6));
      return '${_dateFormat.format(start)} - ${_dateFormat.format(end)}';
    }
    if (_selectedPeriod == 'monthly') {
      return DateFormat('MMMM yyyy', 'id_ID').format(now);
    }
    return _dateFormat.format(now);
  }

  int _currentWeekIndex() {
    final day = DateTime.now().day;
    if (day <= 7) return 0;
    if (day <= 14) return 1;
    if (day <= 21) return 2;
    return 3;
  }

  List<int> _buildWeeklyTargets(int monthlyTarget) {
    if (monthlyTarget <= 0) {
      return const <int>[0, 0, 0, 0];
    }
    final base = monthlyTarget ~/ 4;
    final remainder = monthlyTarget % 4;
    return List<int>.generate(
      4,
      (index) => base + (index < remainder ? 1 : 0),
    );
  }

  int _selectedSummaryTarget() {
    final monthlyTarget = _monthlyTeamTarget;
    if (monthlyTarget <= 0) {
      return _toInt(_selectedSummary['target_submissions']);
    }
    if (_selectedPeriod == 'daily') {
      final now = DateTime.now();
      final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
      return (monthlyTarget / daysInMonth).ceil();
    }
    if (_selectedPeriod == 'weekly') {
      return _buildWeeklyTargets(monthlyTarget)[_currentWeekIndex()];
    }
    return monthlyTarget;
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      await Future.wait([
        _loadProfile(),
        _loadSummary(),
        _loadSatorRows(),
        _loadAlerts(),
      ]);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final profile = await _supabase
        .from('users')
        .select('full_name, area')
        .eq('id', userId)
        .maybeSingle();
    if (profile == null) return;
    _profileName = '${profile['full_name'] ?? 'SPV'}';
    _profileArea = '${profile['area'] ?? '-'}';
  }

  Future<void> _loadSummary() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);

    final daily = await _supabase
        .from('vast_agg_daily_spv')
        .select()
        .eq('spv_id', userId)
        .eq('metric_date', today)
        .maybeSingle();
    final weekly = await _supabase
        .from('vast_agg_weekly_spv')
        .select()
        .eq('spv_id', userId)
        .eq('week_start_date', weekStartStr)
        .maybeSingle();
    final monthly = await _supabase
        .from('vast_agg_monthly_spv')
        .select()
        .eq('spv_id', userId)
        .eq('month_key', monthKey)
        .maybeSingle();

    _daily = daily == null ? null : Map<String, dynamic>.from(daily);
    _weekly = weekly == null ? null : Map<String, dynamic>.from(weekly);
    _monthly = monthly == null ? null : Map<String, dynamic>.from(monthly);
  }

  Future<void> _loadSatorRows() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    final weekStartStr = DateFormat('yyyy-MM-dd').format(weekStart);
    final activePeriodRows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('target_periods')
          .select('id')
          .eq('status', 'active')
          .isFilter('deleted_at', null)
          .order('target_year', ascending: false)
          .order('target_month', ascending: false)
          .order('created_at', ascending: false)
          .limit(1),
    );
    final periodId = activePeriodRows.isEmpty
        ? null
        : activePeriodRows.first['id']?.toString();
    List<Map<String, dynamic>> hierarchyRows = <Map<String, dynamic>>[];
    if (periodId != null && periodId.isNotEmpty) {
      hierarchyRows = List<Map<String, dynamic>>.from(
        await _supabase.rpc(
              'get_users_with_hierarchy',
              params: <String, dynamic>{
                'p_period_id': periodId,
                'p_role': 'promotor',
              },
            ) as List? ??
            const [],
      );
    }

    var promotors = hierarchyRows
        .where((row) => '${row['spv_id'] ?? ''}' == userId)
        .toList();
    if (promotors.isEmpty) {
      final satorRows = List<Map<String, dynamic>>.from(
        await _supabase
            .from('hierarchy_spv_sator')
            .select('sator_id')
            .eq('spv_id', userId)
            .eq('active', true),
      );
      final satorIds = satorRows
          .map((row) => '${row['sator_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toList();
      if (satorIds.isNotEmpty) {
        final promotorRelations = List<Map<String, dynamic>>.from(
          await _supabase
              .from('hierarchy_sator_promotor')
              .select('sator_id, promotor_id')
              .eq('active', true)
              .inFilter('sator_id', satorIds),
        );
        final fallbackPromotorIds = promotorRelations
            .map((row) => '${row['promotor_id'] ?? ''}')
            .where((id) => id.isNotEmpty)
            .toList();
        if (fallbackPromotorIds.isNotEmpty) {
          final userRows = List<Map<String, dynamic>>.from(
            await _supabase
                .from('users')
                .select('id, full_name, nickname')
                .eq('role', 'promotor')
                .isFilter('deleted_at', null)
                .inFilter('id', fallbackPromotorIds),
          );
          final assignmentRows = List<Map<String, dynamic>>.from(
            await _supabase
                .from('assignments_promotor_store')
                .select('promotor_id, stores(store_name)')
                .eq('active', true)
                .inFilter('promotor_id', fallbackPromotorIds),
          );
          final targetRows =
              periodId == null || periodId.isEmpty
                  ? <Map<String, dynamic>>[]
                  : List<Map<String, dynamic>>.from(
                      await _supabase
                          .from('user_targets')
                          .select('user_id, target_vast')
                          .eq('period_id', periodId)
                          .inFilter('user_id', fallbackPromotorIds),
                    );
          final relationByPromotor = <String, Map<String, dynamic>>{
            for (final row in promotorRelations) '${row['promotor_id']}': row,
          };
          final assignmentByPromotor = <String, Map<String, dynamic>>{
            for (final row in assignmentRows) '${row['promotor_id']}': row,
          };
          final targetByPromotor = <String, Map<String, dynamic>>{
            for (final row in targetRows) '${row['user_id']}': row,
          };
          promotors = userRows.map((row) {
            final promotorId = '${row['id']}';
            final relation = relationByPromotor[promotorId];
            final assignment = assignmentByPromotor[promotorId];
            final store = assignment?['stores'];
            final target = targetByPromotor[promotorId];
            return <String, dynamic>{
              'user_id': promotorId,
              'full_name': row['full_name'],
              'nickname': row['nickname'],
              'sator_id': relation?['sator_id'],
              'spv_id': userId,
              'store_name':
                  store is Map<String, dynamic> ? store['store_name'] : '-',
              'target_vast': target?['target_vast'] ?? 0,
            };
          }).toList();
        }
      }
    }
    final promotorIds = promotors
        .map((row) => '${row['user_id'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toList();
    final nicknameRows = promotorIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _supabase
                .from('users')
                .select('id, nickname')
                .inFilter('id', promotorIds),
          );
    final nicknameById = <String, String>{
      for (final row in nicknameRows) '${row['id']}': '${row['nickname'] ?? ''}'.trim(),
    };

    final dailyRows = promotorIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _supabase
                .from('vast_agg_daily_promotor')
                .select()
                .eq('spv_id', userId)
                .inFilter('promotor_id', promotorIds)
                .eq('metric_date', today),
          );
    final monthlyRows = promotorIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _supabase
                .from('vast_agg_monthly_promotor')
                .select()
                .eq('spv_id', userId)
                .inFilter('promotor_id', promotorIds)
                .eq('month_key', monthKey),
          );
    final weeklyRows = promotorIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await _supabase
                .from('vast_agg_weekly_promotor')
                .select()
                .eq('spv_id', userId)
                .inFilter('promotor_id', promotorIds)
                .eq('week_start_date', weekStartStr),
          );

    final dailyById = <String, Map<String, dynamic>>{
      for (final row in dailyRows) '${row['promotor_id']}': row,
    };
    final weeklyById = <String, Map<String, dynamic>>{
      for (final row in weeklyRows) '${row['promotor_id']}': row,
    };
    final monthlyById = <String, Map<String, dynamic>>{
      for (final row in monthlyRows) '${row['promotor_id']}': row,
    };

    List<Map<String, dynamic>> buildRows(
      Map<String, Map<String, dynamic>> sourceById,
      String periodKey,
    ) {
      final rows = promotors.map((row) {
        final id = '${row['user_id']}';
        final source = sourceById[id] ?? const <String, dynamic>{};
        final monthlyTarget = _toInt(row['target_vast']);
        final target = _resolvePeriodTarget(
          monthlyTarget: monthlyTarget,
          source: source,
          periodKey: periodKey,
        );
        final submissions = _toInt(source['total_submissions']);
        final achievement = target > 0
            ? (submissions / target) * 100
            : _toNum(source['achievement_pct']);
        final nickname =
            '${row['nickname'] ?? nicknameById[id] ?? ''}'.trim();
        final fullName = '${row['full_name'] ?? '-'}'.trim();
        return <String, dynamic>{
          'id': id,
          'name': nickname.isNotEmpty ? nickname : fullName,
          'store_name': row['store_name'] ?? '-',
          'monthly_target': monthlyTarget,
          'period_submissions': submissions,
          'target': target,
          'pending': _toInt(source['total_active_pending']),
          'duplicates': _toInt(source['total_duplicate_alerts']),
          'total_acc': _toInt(source['total_acc']),
          'total_reject': _toInt(source['total_reject']),
          'achievement_pct': achievement,
          'underperform': periodKey == 'monthly'
              ? source['underperform'] == true
              : achievement < 100 && submissions < target,
        };
      }).toList();
      rows.sort(
        (a, b) => _toInt(b['period_submissions']).compareTo(
          _toInt(a['period_submissions']),
        ),
      );
      return rows;
    }

    _dailyPromotorRows = buildRows(dailyById, 'daily');
    _weeklyPromotorRows = buildRows(weeklyById, 'weekly');
    _monthlyPromotorRows = buildRows(monthlyById, 'monthly');
  }

  Future<void> _loadAlerts() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final rows = await _supabase
        .from('vast_alerts')
        .select('id, signal_id, application_id, title, body, created_at, is_read')
        .eq('recipient_user_id', userId)
        .order('created_at', ascending: false)
        .limit(50);
    var alerts = List<Map<String, dynamic>>.from(rows);
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
        .update({
          'is_read': true,
          'read_at': DateTime.now().toIso8601String(),
        })
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
        .update({
          'is_read': true,
          'read_at': DateTime.now().toIso8601String(),
        })
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
        .update({
          'is_read': true,
          'read_at': DateTime.now().toIso8601String(),
        })
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
    final matchedApplicationId = signalMap['matched_application_id']?.toString();

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
                    signalMap['summary']?.toString() ?? alert['body'].toString(),
                    style: PromotorText.outfit(size: 13, color: t.textSecondary),
                  ),
                  const SizedBox(height: 18),
                  if (currentApplication != null)
                    _buildApplicationReviewCard(
                      title: 'Pengajuan Baru',
                      item: Map<String, dynamic>.from(currentApplication),
                      evidences: List<Map<String, dynamic>>.from(currentEvidences),
                    ),
                  if (matchedApplication != null) ...[
                    const SizedBox(height: 16),
                    _buildApplicationReviewCard(
                      title: 'Pengajuan Pembanding',
                      item: Map<String, dynamic>.from(matchedApplication),
                      evidences: List<Map<String, dynamic>>.from(matchedEvidences),
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
        'ACC',
        'Reject',
        'Persentase',
      ],
      rows: rowsForExport
          .map(
            (row) => <Object?>[
              row['name'],
              row['store_name'],
              row['period_submissions'],
              row['target'],
              row['pending'],
              row['total_acc'],
              row['total_reject'],
              _toNum(row['achievement_pct']).toStringAsFixed(1),
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
    switch (_selectedPeriod) {
      case 'weekly':
        return _weekly ?? <String, dynamic>{};
      case 'monthly':
        return _monthly ?? <String, dynamic>{};
      default:
        return _daily ?? <String, dynamic>{};
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
        return 'Performance';
      case 'alert':
        return 'Duplikasi Data Alert';
      case 'export':
        return 'Export';
      default:
        return 'Dashboard Area';
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
        return _buildHomeSection();
    }
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
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
        ],
      ),
    );
  }

  Widget _buildHero() {
    final summary = _selectedSummary;
    final target = _selectedSummaryTarget();
    final weeklyTargets = _buildWeeklyTargets(_monthlyTeamTarget);
    final activeWeekIndex = _currentWeekIndex();
    return PromotorCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ringkasan Area',
            style: PromotorText.display(size: 22, color: t.textPrimary),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  _periodRangeLabel(),
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: MediaQuery.of(context).size.width * 0.48,
                child: _buildPeriodTabs(),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildMetricStrip(<Widget>[
            _metricTile(
              label: 'Input',
              value: _toInt(summary['total_submissions']),
              target: target,
              accent: t.primaryAccent,
            ),
            _metricTile(
              label: 'Closing',
              value: _closingCount(summary),
              target: target,
              accent: const Color(0xFF0F8A6C),
            ),
            _metricTile(
              label: 'Pending',
              value: _toInt(summary['total_active_pending']),
              target: target,
              accent: const Color(0xFFC98210),
            ),
            _metricTile(
              label: 'Reject',
              value: _toInt(summary['total_reject']),
              target: target,
              accent: const Color(0xFFC14444),
            ),
          ]),
          if (_selectedPeriod == 'weekly') ...[
            const SizedBox(height: 12),
            Center(
              child: _buildMetricStrip(
                List<Widget>.generate(
                  4,
                  (index) => _buildWeekTile(
                    index: index,
                    target: weeklyTargets[index],
                    active: index == activeWeekIndex,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricStrip(List<Widget> children) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(children.length, (index) {
          return Padding(
            padding: EdgeInsets.only(right: index == children.length - 1 ? 0 : 10),
            child: children[index],
          );
        }),
      ),
    );
  }

  Widget _metricTile({
    required String label,
    required int value,
    required int target,
    required Color accent,
  }) {
    final percent = target <= 0 ? 0 : ((value / target) * 100).round();
    return SizedBox(
      width: 122,
      child: _buildKpiCard(
        label: label,
        value: '$value',
        percentLabel: '$percent%',
        accent: accent,
      ),
    );
  }

  Widget _buildWeekTile({
    required int index,
    required int target,
    required bool active,
  }) {
    final monthlyTarget = _monthlyTeamTarget;
    final percent = monthlyTarget <= 0 ? 0 : ((target / monthlyTarget) * 100).round();
    return SizedBox(
      width: 90,
      child: _buildWeekBubble(
        label: 'Week ${index + 1}',
        value: '$target',
        percentLabel: '$percent%',
        accent: active ? t.primaryAccent : t.textMuted,
        active: active,
      ),
    );
  }

  Widget _buildKpiCard({
    required String label,
    required String value,
    required String percentLabel,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
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
                  size: 10,
                  weight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: PromotorText.display(size: 22, color: t.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekBubble({
    required String label,
    required String value,
    required String percentLabel,
    required Color accent,
    required bool active,
  }) {
    return Container(
      width: 90,
      height: 90,
      decoration: BoxDecoration(
        color: active ? accent.withValues(alpha: 0.12) : t.surface2,
        shape: BoxShape.circle,
        border: Border.all(color: active ? accent : t.surface3, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: active ? 0.16 : 0.06),
            blurRadius: active ? 16 : 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: active ? accent : t.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: PromotorText.display(size: 18, color: t.textPrimary),
          ),
          Text(
            percentLabel,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: active ? accent : t.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
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
            style: PromotorText.outfit(size: 11, color: t.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: PromotorText.display(size: 18, color: t.textPrimary),
          ),
        ],
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
      const _ActionItem('home', Icons.space_dashboard_outlined, 'Home'),
      const _ActionItem('performance', Icons.leaderboard_outlined, 'Ranking'),
      const _ActionItem('alert', Icons.warning_amber_rounded, 'Duplikasi'),
      const _ActionItem('export', Icons.file_download_outlined, 'Export'),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Row(
        children: actions.map((item) {
          final active = item.keyName == _activeSection;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: InkWell(
                onTap: () => setState(() => _activeSection = item.keyName),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: active ? t.primaryAccent : t.surface1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: active ? t.primaryAccent : t.surface3,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        item.icon,
                        size: 18,
                        color: active ? t.textOnAccent : t.primaryAccent,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        item.label,
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w700,
                          color: active ? t.textOnAccent : t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }).toList(),
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

  Widget _buildHomeSection() {
    final summary = _selectedSummary;
    final target = _selectedSummaryTarget();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Target',
                  '$target',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metric(
                  'Achievement',
                  '${_toNum(summary['achievement_pct']).toStringAsFixed(1)}%',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _metric(
                  'Duplikasi',
                  '${_toInt(summary['total_duplicate_alerts'])}',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metric(
                  'Promotor Aktif',
                  '${_toInt(summary['promotor_with_input'])}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _metric('ACC', '${_toInt(summary['total_acc'])}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metric('Reject', '${_toInt(summary['total_reject'])}'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceSection() {
    final promotorRows = _selectedPromotorRows;
    if (promotorRows.isEmpty) {
      return _empty('Belum ada data promotor.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Pencapaian promotor $_periodLabel',
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Container(
            width: _tableWidth,
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.surface3),
            ),
            child: Column(
              children: [
                _buildTableHeader(<String>[
                  'Promotor',
                  'Toko',
                  'Target',
                  _periodColumnLabel,
                  'Pending',
                  'ACC',
                  'Reject',
                  '%',
                ]),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 360),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: promotorRows.length,
                    separatorBuilder: (context, index) =>
                        Divider(height: 1, color: t.surface3),
                    itemBuilder: (context, index) =>
                        _buildPromotorTableRow(promotorRows[index]),
                  ),
                ),
              ],
            ),
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
        children: [
          Wrap(
            spacing: 8,
            children: filters.entries.map((entry) {
              final active = _alertFilter == entry.key;
              return ChoiceChip(
                label: Text(entry.value),
                selected: active,
                onSelected: (_) async {
                  setState(() => _alertFilter = entry.key);
                  await _loadAlerts();
                  if (mounted) setState(() {});
                },
              );
            }).toList(),
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
                    padding: const EdgeInsets.all(14),
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
                          children: [
                            Expanded(
                              child: Text(
                                '${item['title']}',
                                style: PromotorText.outfit(
                                  size: 13,
                                  weight: FontWeight.w700,
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                            if (!isRead)
                              TextButton(
                                style: TextButton.styleFrom(
                                  foregroundColor: t.primaryAccent,
                                ),
                                onPressed: () => _markAlertRead(
                                  item['id'] as String,
                                ),
                                child: const Text('Tandai Dibaca'),
                              ),
                          ],
                        ),
                        Text(
                          isRead ? 'Sudah dibaca' : 'Belum dibaca',
                          style: PromotorText.outfit(
                            size: 11,
                            weight: FontWeight.w700,
                            color: isRead ? t.textSecondary : t.warning,
                          ),
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
                        const SizedBox(height: 8),
                        Text(
                          'Tap untuk review manual',
                          style: PromotorText.outfit(
                            size: 11,
                            weight: FontWeight.w700,
                            color: t.primaryAccent,
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

  Widget _buildTableHeader(List<String> labels) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(17)),
      ),
      child: Row(
        children: List<Widget>.generate(labels.length, (index) {
          return SizedBox(
            width: _tableColumnWidths[index],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Text(
                labels[index],
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  List<double> get _tableColumnWidths =>
      const <double>[140, 136, 78, 108, 78, 64, 72, 84];

  double get _tableWidth =>
      _tableColumnWidths.fold<double>(0, (total, width) => total + width) + 4;

  Widget _buildPromotorTableRow(Map<String, dynamic> row) {
    final underperform = row['underperform'] == true;
    final cells = <String>[
      '${row['name']}',
      '${row['store_name']}',
      '${row['target']}',
      '${row['period_submissions']}',
      '${row['pending']}',
      '${row['total_acc']}',
      '${row['total_reject']}',
      '${_toNum(row['achievement_pct']).toStringAsFixed(1)}%',
    ];
    return Container(
      decoration: BoxDecoration(
        color: underperform ? t.dangerSoft : Colors.transparent,
      ),
      child: Row(
        children: List<Widget>.generate(cells.length, (index) {
          return SizedBox(
            width: _tableColumnWidths[index],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              child: Text(
                cells[index],
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ),
          );
        }),
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
