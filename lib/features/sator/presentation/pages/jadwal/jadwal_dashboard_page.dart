import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../ui/promotor/promotor.dart';
import 'schedule_detail_page.dart';

class JadwalDashboardPage extends StatefulWidget {
  const JadwalDashboardPage({super.key});

  @override
  State<JadwalDashboardPage> createState() => _JadwalDashboardPageState();
}

class _JadwalDashboardPageState extends State<JadwalDashboardPage>
    with SingleTickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  late final TabController _tabController;
  DateTime _selectedMonth = DateTime.now();
  List<Map<String, dynamic>> _allSchedules = const [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  Future<List<Map<String, dynamic>>> _fetchSummaryForMonth(
    String userId,
    DateTime month,
  ) async {
    final monthYear = DateFormat('yyyy-MM').format(month);
    final response = await _supabase.rpc(
      'get_sator_schedule_summary',
      params: {'p_sator_id': userId, 'p_month_year': monthYear},
    );
    return List<Map<String, dynamic>>.from(response ?? const []);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (!mounted) return;

    if (userId == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Session tidak ditemukan. Silakan login ulang.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      var targetMonth = DateTime(_selectedMonth.year, _selectedMonth.month);
      var rows = await _fetchSummaryForMonth(userId, targetMonth);
      final now = DateTime.now();
      final currentMonth = DateTime(now.year, now.month);
      final isCurrentMonth = targetMonth.year == currentMonth.year &&
          targetMonth.month == currentMonth.month;
      final hasSubmitted = rows.any((row) => '${row['status'] ?? ''}' == 'submitted');

      if (isCurrentMonth && !hasSubmitted) {
        final nextMonth = DateTime(targetMonth.year, targetMonth.month + 1);
        final nextRows = await _fetchSummaryForMonth(userId, nextMonth);
        final nextHasSubmitted =
            nextRows.any((row) => '${row['status'] ?? ''}' == 'submitted');
        if (nextHasSubmitted) {
          targetMonth = nextMonth;
          rows = nextRows;
        }
      }

      if (!mounted) return;
      setState(() {
        _selectedMonth = targetMonth;
        _allSchedules = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Jadwal tim gagal dimuat. ${_humanizeError(e)}';
      });
    }
  }

  String _humanizeError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  List<Map<String, dynamic>> _statusRows(String status) {
    return _allSchedules.where((row) => row['status'] == status).toList();
  }

  int get _pendingCount => _statusRows('submitted').length;
  int get _approvedCount => _statusRows('approved').length;
  int get _notSubmittedCount => _statusRows('belum_kirim').length;

  bool get _canMoveForward {
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final selected = DateTime(_selectedMonth.year, _selectedMonth.month);
    return selected.isBefore(currentMonth);
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
        return 'Pending';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'draft':
        return 'Draft';
      default:
        return 'Belum Kirim';
    }
  }

  Future<void> _openDetail(Map<String, dynamic> schedule) async {
    final result = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ScheduleDetailPage(
          promotorId: '${schedule['promotor_id']}',
          promotorName: '${schedule['promotor_name'] ?? ''}',
          storeName: '${schedule['store_name'] ?? ''}',
          monthYear: DateFormat('yyyy-MM').format(_selectedMonth),
          status: '${schedule['status'] ?? 'belum_kirim'}',
        ),
      ),
    );

    if (result == true) {
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
            : RefreshIndicator(
                color: t.primaryAccent,
                backgroundColor: t.surface1,
                onRefresh: _loadData,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopBar(context),
                            const SizedBox(height: 10),
                            if (_errorMessage != null)
                              _buildErrorCard()
                            else ...[
                              _buildStatsRow(),
                              const SizedBox(height: 12),
                              _buildTabShell(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_errorMessage == null)
                      SliverFillRemaining(
                        hasScrollBody: true,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildApprovalTab(),
                              _buildOverviewTab(),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.pop(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.surface3),
            ),
            child: Icon(Icons.arrow_back_rounded, color: t.textPrimary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Jadwal Tim',
            style: PromotorText.outfit(
              size: 18,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        _buildMonthCompactSwitch(),
      ],
    );
  }

  Widget _buildMonthCompactSwitch() {
    final monthLabel = DateFormat('MMM yyyy', 'id_ID').format(_selectedMonth);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildMonthSwitch(
            icon: Icons.chevron_left_rounded,
            compact: true,
            onTap: () {
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month - 1,
                );
              });
              _loadData();
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              monthLabel,
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w800,
              ),
            ),
          ),
          _buildMonthSwitch(
            icon: Icons.chevron_right_rounded,
            enabled: _canMoveForward,
            compact: true,
            onTap: () {
              if (!_canMoveForward) return;
              setState(() {
                _selectedMonth = DateTime(
                  _selectedMonth.year,
                  _selectedMonth.month + 1,
                );
              });
              _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSwitch({
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
    bool compact = false,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: Container(
        width: compact ? 30 : 48,
        height: compact ? 30 : 48,
        decoration: BoxDecoration(
          color: enabled ? t.surface1 : t.surface1.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(compact ? 10 : 16),
          border: Border.all(color: t.surface3),
        ),
        child: Icon(
          icon,
          size: compact ? 18 : 24,
          color: enabled ? t.textPrimary : t.textMutedStrong,
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'Pending',
            value: '$_pendingCount',
            tone: t.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            title: 'Approved',
            value: '$_approvedCount',
            tone: t.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMetricCard(
            title: 'Belum Kirim',
            value: '$_notSubmittedCount',
            tone: t.textMuted,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required Color tone,
  }) {
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
            title.toUpperCase(),
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w700,
              color: t.textMuted,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: PromotorText.outfit(
              size: 17,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabShell() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: t.primaryAccentSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.primaryAccentGlow),
        ),
        dividerColor: t.surface1.withValues(alpha: 0),
        labelStyle: PromotorText.outfit(size: 13, weight: FontWeight.w800),
        unselectedLabelStyle: PromotorText.outfit(
          size: 13,
          weight: FontWeight.w700,
          color: t.textSecondary,
        ),
        labelColor: t.primaryAccentLight,
        unselectedLabelColor: t.textSecondary,
        tabs: [
          Tab(text: 'Approval ($_pendingCount)'),
          const Tab(text: 'Overview'),
        ],
      ),
    );
  }

  Widget _buildApprovalTab() {
    final pendingRows = _statusRows('submitted');
    final notSubmittedRows = _statusRows('belum_kirim');

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 12),
        _buildSectionTitle('Menunggu Review'),
        const SizedBox(height: 10),
        if (pendingRows.isEmpty)
          _buildEmptyCard('Tidak ada jadwal yang menunggu approval bulan ini.')
        else
          ...pendingRows.map(
            (row) => _buildScheduleCard(row, actionable: true),
          ),
        const SizedBox(height: 16),
        _buildSectionTitle('Belum Kirim'),
        const SizedBox(height: 10),
        if (notSubmittedRows.isEmpty)
          _buildEmptyCard('Semua promotor sudah punya draft atau jadwal aktif.')
        else
          ...notSubmittedRows.map(
            (row) => _buildScheduleCard(row, actionable: false),
          ),
      ],
    );
  }

  Widget _buildOverviewTab() {
    final sections = [
      ('Approved', 'approved'),
      ('Rejected', 'rejected'),
      ('Draft', 'draft'),
    ];

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 12),
        for (final section in sections) ...[
          _buildSectionTitle(
            section.$1,
          ),
          const SizedBox(height: 10),
          if (_statusRows(section.$2).isEmpty)
            _buildEmptyCard('Tidak ada jadwal ${section.$1.toLowerCase()}.')
          else
            ..._statusRows(
              section.$2,
            ).map((row) => _buildScheduleCard(row, actionable: true)),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: PromotorText.outfit(
        size: 15,
        weight: FontWeight.w800,
        color: t.textPrimary,
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return PromotorCard(
      child: Text(
        message,
        style: PromotorText.outfit(
          size: 13,
          weight: FontWeight.w600,
          color: t.textSecondary,
        ),
      ),
    );
  }

  Widget _buildScheduleCard(
    Map<String, dynamic> schedule, {
    required bool actionable,
  }) {
    final status = '${schedule['status'] ?? 'belum_kirim'}';
    final statusColor = _statusColor(status);
    final lastUpdated = DateTime.tryParse('${schedule['last_updated'] ?? ''}');

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: actionable ? () => _openDetail(schedule) : null,
      child: PromotorCard(
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: t.surface2,
                border: Border.all(color: t.surface3),
              ),
              alignment: Alignment.center,
              child: Text(
                ('${schedule['promotor_name'] ?? 'P'}')
                    .trim()
                    .substring(0, 1)
                    .toUpperCase(),
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w800,
                  color: t.primaryAccentLight,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${schedule['promotor_name'] ?? ''}',
                    style: PromotorText.outfit(
                      size: 15,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${schedule['store_name'] ?? '-'}',
                    style: PromotorText.outfit(
                      size: 12,
                      weight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _buildTonePill(_statusLabel(status), statusColor),
                      if (lastUpdated != null)
                        _buildTonePill(
                          DateFormat('dd MMM', 'id_ID').format(lastUpdated),
                          t.textMuted,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            if (actionable)
              Icon(Icons.arrow_forward_rounded, color: t.textSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildTonePill(String label, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 12,
          weight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return PromotorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PromotorSectionLabel('Gagal Memuat'),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'Terjadi kesalahan.',
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.primaryAccent,
                foregroundColor: t.textOnAccent,
              ),
              onPressed: _loadData,
              child: Text(
                'Coba Lagi',
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w800,
                  color: t.textOnAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
