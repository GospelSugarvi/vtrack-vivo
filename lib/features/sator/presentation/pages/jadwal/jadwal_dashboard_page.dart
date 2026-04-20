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
    _tabController.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
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
      backgroundColor: t.background,
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
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopBar(context),
                            const SizedBox(height: 8),
                            if (_errorMessage != null)
                              _buildErrorCard()
                            else ...[
                              _buildTabShell(),
                              const SizedBox(height: 8),
                              _buildStatsRow(),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_errorMessage == null)
                      SliverFillRemaining(
                        hasScrollBody: true,
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
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
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.pop(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(12),
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
              size: 17,
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
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
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
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Text(
              monthLabel,
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w800,
                color: t.textPrimary,
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
        width: compact ? 28 : 44,
        height: compact ? 28 : 44,
        decoration: BoxDecoration(
          color: enabled ? t.surface1 : t.surface1.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(compact ? 9 : 14),
          border: Border.all(color: t.surface3),
        ),
        child: Icon(
          icon,
          size: compact ? 16 : 22,
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
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w700,
                color: t.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: PromotorText.outfit(
              size: 13.5,
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
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: TabBar(
        controller: _tabController,
        indicatorSize: TabBarIndicatorSize.tab,
        splashBorderRadius: BorderRadius.circular(9),
        indicator: BoxDecoration(
          color: t.primaryAccent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: t.primaryAccent.withValues(alpha: 0.22),
          ),
        ),
        dividerColor: t.surface1.withValues(alpha: 0),
        padding: EdgeInsets.zero,
        labelPadding: EdgeInsets.zero,
        indicatorPadding: EdgeInsets.zero,
        tabAlignment: TabAlignment.fill,
        labelStyle: PromotorText.outfit(size: 10, weight: FontWeight.w800),
        unselectedLabelStyle: PromotorText.outfit(
          size: 10,
          weight: FontWeight.w700,
          color: t.textSecondary,
        ),
        labelColor: t.primaryAccent,
        unselectedLabelColor: t.textSecondary,
        tabs: [
          _buildCompactTab(
            label: 'Approval',
            count: _pendingCount,
            selectedTone: t.primaryAccent,
            idleTone: t.textMutedStrong,
          ),
          _buildCompactTab(
            label: 'Overview',
            count: null,
            selectedTone: t.primaryAccent,
            idleTone: t.textMutedStrong,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactTab({
    required String label,
    required int? count,
    required Color selectedTone,
    required Color idleTone,
  }) {
    final hasCount = count != null;
    final isApproval = label == 'Approval';
    final selected = _tabController.index == (isApproval ? 0 : 1);

    return Tab(
      height: 28,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.max,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (hasCount) ...[
              const SizedBox(width: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: (selected ? selectedTone : idleTone).withValues(
                    alpha: selected ? 0.14 : 0.1,
                  ),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: PromotorText.outfit(
                    size: 8.5,
                    weight: FontWeight.w800,
                    color: selected ? selectedTone : idleTone,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildApprovalTab() {
    final pendingRows = _statusRows('submitted');
    final notSubmittedRows = _statusRows('belum_kirim');

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        const SizedBox(height: 10),
        _buildSectionTitle('Pending Review', pendingRows.length),
        const SizedBox(height: 8),
        if (pendingRows.isEmpty)
          _buildEmptyCard('Belum ada jadwal yang menunggu review.')
        else
          ...pendingRows.map(
            (row) => _buildScheduleCard(row, actionable: true),
          ),
        const SizedBox(height: 12),
        _buildSectionTitle('Belum Kirim', notSubmittedRows.length),
        const SizedBox(height: 8),
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
        const SizedBox(height: 10),
        for (final section in sections) ...[
          _buildSectionTitle(
            section.$1,
            _statusRows(section.$2).length,
          ),
          const SizedBox(height: 8),
          if (_statusRows(section.$2).isEmpty)
            _buildEmptyCard('Tidak ada jadwal ${section.$1.toLowerCase()}.')
          else
            ..._statusRows(
              section.$2,
            ).map((row) => _buildScheduleCard(row, actionable: true)),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  Widget _buildSectionTitle(String title, int count) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: PromotorText.outfit(
              size: 14,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: t.surface3),
          ),
          child: Text(
            '$count',
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w800,
              color: t.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyCard(String message) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        message,
        style: PromotorText.outfit(
          size: 12,
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
    final promotorName = '${schedule['promotor_name'] ?? ''}'.trim();
    final storeName = '${schedule['store_name'] ?? '-'}';
    final initial = promotorName.isEmpty ? 'P' : promotorName.substring(0, 1).toUpperCase();

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: actionable ? () => _openDetail(schedule) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.surface3),
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w800,
                  color: t.primaryAccentLight,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            children: [
                              TextSpan(
                                text: promotorName,
                                style: PromotorText.outfit(
                                  size: 11,
                                  weight: FontWeight.w800,
                                  color: t.textPrimary,
                                ),
                              ),
                              TextSpan(
                                text: storeName.isEmpty ? '' : '  •  $storeName',
                                style: PromotorText.outfit(
                                  size: 9,
                                  weight: FontWeight.w700,
                                  color: t.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildTonePill(_statusLabel(status), statusColor),
                    ],
                  ),
                  if (lastUpdated != null) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          size: 10,
                          color: t.textMutedStrong,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          'Update ${DateFormat('dd MMM', 'id_ID').format(lastUpdated)}',
                          style: PromotorText.outfit(
                            size: 8.8,
                            weight: FontWeight.w700,
                            color: t.textMutedStrong,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (actionable)
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 11,
                  color: t.textMutedStrong,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTonePill(String label, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 9,
          weight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PromotorSectionLabel('Gagal Memuat'),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'Terjadi kesalahan.',
            style: PromotorText.outfit(
              size: 13,
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
