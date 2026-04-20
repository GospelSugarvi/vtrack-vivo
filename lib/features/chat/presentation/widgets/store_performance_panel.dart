import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../repository/chat_repository.dart';
import '../../../allbrand/presentation/widgets/allbrand_report_detail_panel.dart';
import '../theme/chat_theme.dart';

class StorePerformancePanel extends StatefulWidget {
  final String storeId;
  final String storeName;

  const StorePerformancePanel({
    super.key,
    required this.storeId,
    required this.storeName,
  });

  @override
  State<StorePerformancePanel> createState() => _StorePerformancePanelState();
}

class _StorePerformancePanelState extends State<StorePerformancePanel>
    with SingleTickerProviderStateMixin {
  bool _isExpanded = false;
  late TabController _tabController;
  bool _isLoading = false;
  final _repository = ChatRepository();
  Map<String, dynamic>? _performanceData;
  RealtimeChannel? _allbrandChannel;
  ChatThemeTokens get _tokens => chatTokensOf(context);
  ChatUiPalette get _palette => chatPaletteOf(context);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
    _subscribeAllbrandRealtime();
  }

  @override
  void dispose() {
    if (_allbrandChannel != null) {
      Supabase.instance.client.removeChannel(_allbrandChannel!);
    }
    _tabController.dispose();
    super.dispose();
  }

  void _subscribeAllbrandRealtime() {
    _allbrandChannel = _repository.subscribeToAllbrandReports(
      storeId: widget.storeId,
      onChanged: () {
        if (!mounted) return;
        _loadData();
      },
    );
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final data = await _repository.getStorePerformanceData(
        storeId: widget.storeId,
      );
      if (mounted) setState(() => _performanceData = data);
    } catch (e) {
      // debugPrint('=== ERROR loading performance data: $e ===');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [_buildQuickStatsBar(), if (_isExpanded) _buildExpandedPanel()],
    );
  }

  Widget _buildQuickStatsBar() {
    final tokens = _tokens;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: tokens.surfaceAlt,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tokens.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Detail toko',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: tokens.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                if (_isLoading)
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.8,
                      valueColor: AlwaysStoppedAnimation<Color>(tokens.primary),
                    ),
                  )
                else
                  Icon(
                    _isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: tokens.textMuted,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedPanel() {
    final tokens = _tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            decoration: BoxDecoration(
              color: tokens.surface,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: Container(
              height: 38,
              decoration: BoxDecoration(
                color: tokens.surfaceAlt,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.border),
              ),
              child: TabBar(
                controller: _tabController,
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: tokens.border),
                ),
                labelColor: tokens.primary,
                unselectedLabelColor: tokens.textMuted,
                labelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                splashBorderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.all(3),
                tabs: const [
                  Tab(height: 30, text: 'AllBrand'),
                  Tab(height: 30, text: 'VAST'),
                  Tab(height: 30, text: 'Aktivitas'),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 300,
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(tokens.primary),
                    ),
                  )
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAllbrandTab(),
                      _buildVastFinanceTab(),
                      _buildActivityTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllbrandTab() {
    final tokens = _tokens;
    final allbrandData = _performanceData?['allbrand'] as Map<String, dynamic>?;
    if (allbrandData == null || allbrandData['has_data'] != true) {
      return Center(
        child: Text(
          'Belum ada laporan AllBrand untuk toko ini',
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }

    final reportDate = '${allbrandData['report_date'] ?? '-'}';
    final isToday = allbrandData['is_today'] == true;
    final reportLabel = isToday ? 'Laporan hari ini' : 'Laporan terakhir';
    final summaryRows = _buildAllbrandSummaryRows(allbrandData);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.surfaceAlt,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Text(
                      '$reportLabel: $reportDate',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: tokens.textMuted,
                      ),
                    ),
                  ),
                ),
                if (summaryRows.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: summaryRows.map((row) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: _buildAllbrandBrandTile(
                            label: '${row['label']}',
                            value: _toInt(row['units']),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                InkWell(
                  onTap: () {
                    showModalBottomSheet<void>(
                      context: context,
                      isScrollControlled: true,
                      backgroundColor: Colors.transparent,
                      builder: (context) => DraggableScrollableSheet(
                        expand: false,
                        initialChildSize: 0.9,
                        maxChildSize: 0.96,
                        minChildSize: 0.6,
                        builder: (context, controller) {
                          return Container(
                            decoration: BoxDecoration(
                              color: tokens.surface,
                              borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(28),
                              ),
                              border: Border.all(color: tokens.border),
                            ),
                            child: ListView(
                              controller: controller,
                              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Center(
                                        child: Container(
                                          width: 44,
                                          height: 4,
                                          decoration: BoxDecoration(
                                            color: tokens.border,
                                            borderRadius: BorderRadius.circular(999),
                                          ),
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      onPressed: () => Navigator.of(context).pop(),
                                      icon: Icon(
                                        Icons.close_rounded,
                                        size: 20,
                                        color: tokens.textMuted,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      tooltip: 'Tutup',
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                AllbrandReportDetailPanel(
                                  storeId: widget.storeId,
                                  initialStoreName: widget.storeName,
                                  showCopyAction: false,
                                ),
                              ],
                            ),
                          );
                        },
                    ),
                  );
                },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: tokens.border),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, size: 16, color: tokens.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Lihat detail AllBrand',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: tokens.textPrimary,
                            ),
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: tokens.textMuted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _buildAllbrandSummaryRows(
    Map<String, dynamic> allbrandData,
  ) {
    final brands = _mapFromValue(allbrandData['brands']);
    final rows = <Map<String, dynamic>>[];
    const orderedBrands = <String>[
      'VIVO',
      'OPPO',
      'Samsung',
      'Realme',
      'Xiaomi',
      'Tecno',
      'Infinix',
    ];

    for (final brand in orderedBrands) {
      final units = brand == 'VIVO'
          ? _toInt(allbrandData['vivo_units'])
          : _sumBrandUnits(brands[brand] ?? brands[brand.toUpperCase()]);
      rows.add({
        'label': brand,
        'units': units,
      });
    }

    return rows;
  }

  Widget _buildAllbrandBrandTile({
    required String label,
    required int value,
  }) {
    final tokens = _tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tokens.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tokens.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _mapFromValue(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return const <String, dynamic>{};
  }

  int _sumBrandUnits(dynamic raw) {
    final row = _mapFromValue(raw);
    return _toInt(row['under_2m']) +
        _toInt(row['2m_4m']) +
        _toInt(row['4m_6m']) +
        _toInt(row['above_6m']);
  }

  Widget _buildActivityTab() {
    final tokens = _tokens;
    final activityData = _performanceData?['activity'] as List?;
    if (activityData == null || activityData.isEmpty) {
      return Center(
        child: Text(
          'Belum ada aktivitas hari ini',
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: activityData.length,
      itemBuilder: (context, index) {
        final activity = activityData[index] as Map<String, dynamic>;
        return _buildActivityCard(activity);
      },
    );
  }

  Widget _buildActivityCard(Map<String, dynamic> activity) {
    final tokens = _tokens;
    final c = _palette;
    final name = activity['promotor_name'] ?? 'Unknown';
    final clockIn = activity['clock_in'];
    final clockOut = activity['clock_out'];
    final salesCount = activity['sales_count'] ?? 0;
    final stockCount = activity['stock_count'] ?? 0;
    final hasClockIn = clockIn != null;
    final hasClockOut = clockOut != null;

    return InkWell(
      onTap: () => _showActivityDetail(activity),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.surfaceAlt,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tokens.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: tokens.primary.withValues(alpha: 0.2),
                  child: Text(
                    name[0].toUpperCase(),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: tokens.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: hasClockIn
                        ? (hasClockOut
                              ? tokens.surface
                              : c.greenSoft)
                        : c.redSoft,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: tokens.border),
                  ),
                  child: Text(
                    hasClockIn
                        ? (hasClockOut ? 'Selesai' : 'Aktif')
                        : 'Belum Masuk',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: hasClockIn
                          ? (hasClockOut
                                ? tokens.textMuted
                                : c.green)
                          : c.red,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_right, size: 16, color: tokens.textMuted),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                _buildActivityStat(
                  Icons.schedule,
                  'Masuk ${hasClockIn ? _formatTime(clockIn) : '-'}',
                  c.blue,
                ),
                _buildActivityStat(
                  Icons.schedule_outlined,
                  'Keluar ${hasClockOut ? _formatTime(clockOut) : '-'}',
                  c.amber,
                ),
                _buildActivityStat(
                  Icons.shopping_cart,
                  'Jual $salesCount',
                  c.green,
                ),
                _buildActivityStat(
                  Icons.inventory,
                  'Stok $stockCount',
                  c.purple,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityStat(IconData icon, String value, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildVastFinanceTab() {
    final tokens = _tokens;
    final c = _palette;
    final vastData = _performanceData?['vast'] as Map<String, dynamic>?;
    if (vastData == null) {
      return Center(
        child: Text(
          'Belum ada data VAST Finance',
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }

    final rows = List<Map<String, dynamic>>.from(
      (vastData['rows'] as List?) ?? const [],
    );
    final targetTotal = _toInt(vastData['target_total']);
    final inputTotal = _toInt(vastData['input_total']);
    final closingTotal = _toInt(vastData['closing_total']);
    final pendingTotal = _toInt(vastData['pending_total']);
    final rejectTotal = _toInt(vastData['reject_total']);
    final achievement = targetTotal > 0
        ? ((inputTotal * 100) / targetTotal).clamp(0, 999).toDouble()
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.surfaceAlt,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.account_balance_wallet_rounded,
                      size: 16,
                      color: c.gold,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'VAST Finance',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      '${achievement.toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: achievement >= 100
                            ? c.green
                            : (achievement > 0 ? c.amber : tokens.textMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _buildVastHighlightTile(
                        'Target',
                        '$targetTotal',
                        c.gold,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildVastHighlightTile(
                        'Input',
                        '$inputTotal',
                        c.blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildVastMiniStat(
                        'Closing',
                        '$closingTotal',
                        c.green,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildVastMiniStat(
                        'Pending',
                        '$pendingTotal',
                        c.amber,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildVastMiniStat(
                        'Reject',
                        '$rejectTotal',
                        c.red,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Rekap per Promotor',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Text(
              'Belum ada input VAST dari promotor toko ini.',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            )
          else
            ...rows.map((row) {
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: tokens.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: tokens.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: Text(
                        '${row['promotor_name'] ?? 'Promotor'}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        '${_toInt(row['target_total'])}/${_toInt(row['input_total'])}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: c.blue,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        '${_toInt(row['pending_total'])}/${_toInt(row['closing_total'])}/${_toInt(row['reject_total'])}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        _buildVastAchievementLabel(
                          target: _toInt(row['target_total']),
                          input: _toInt(row['input_total']),
                        ),
                        textAlign: TextAlign.end,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: _toInt(row['input_total']) >= _toInt(row['target_total']) &&
                                  _toInt(row['target_total']) > 0
                              ? c.green
                              : (_toInt(row['input_total']) > 0
                                    ? c.amber
                                    : tokens.textMuted),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          if (rows.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Format: target/input • pending/closing/reject',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: tokens.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildVastHighlightTile(String label, String value, Color color) {
    final tokens = _tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVastMiniStat(String label, String value, Color color) {
    final tokens = _tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: tokens.textMuted,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  String _buildVastAchievementLabel({
    required int target,
    required int input,
  }) {
    if (target <= 0) return input > 0 ? 'ON' : '0%';
    return '${((input * 100) / target).round()}%';
  }

  void _showActivityDetail(Map<String, dynamic> activity) {
    final tokens = _tokens;
    final c = _palette;
    final name = activity['promotor_name'] ?? 'Unknown';
    final clockIn = activity['clock_in'];
    final clockOut = activity['clock_out'];
    final salesCount = activity['sales_count'] ?? 0;
    final stockCount = activity['stock_count'] ?? 0;
    final hasClockIn = clockIn != null;
    final hasClockOut = clockOut != null;

    String workDuration = '-';
    if (hasClockIn && hasClockOut) {
      try {
        final inTime = DateTime.parse(clockIn);
        final outTime = DateTime.parse(clockOut);
        final duration = outTime.difference(inTime);
        final hours = duration.inHours;
        final minutes = duration.inMinutes % 60;
        workDuration = '${hours}j ${minutes}m';
      } catch (e) {
        workDuration = '-';
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: tokens.surface,
        title: Row(
          children: [
            CircleAvatar(
              radius: 20,
              backgroundColor: tokens.primary.withValues(alpha: 0.2),
              child: Text(
                name[0].toUpperCase(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: tokens.primary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                name,
                style: TextStyle(fontSize: 16, color: tokens.textPrimary),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Kehadiran',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Jam Masuk',
                hasClockIn ? _formatTime(clockIn) : 'Belum masuk',
                hasClockIn ? c.green : c.red,
              ),
              const SizedBox(height: 6),
              _buildDetailRow(
                'Jam Keluar',
                hasClockOut ? _formatTime(clockOut) : 'Belum keluar',
                hasClockOut ? c.amber : tokens.textMuted,
              ),
              const SizedBox(height: 6),
              _buildDetailRow('Durasi Kerja', workDuration, c.blue),
              const Divider(height: 20),
              Text(
                'Rekap Aktivitas Hari Ini',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Lapor Jual',
                '$salesCount transaksi sellout',
                c.green,
              ),
              const SizedBox(height: 6),
              _buildDetailRow(
                'Aktivitas Stok',
                '$stockCount pergerakan stok',
                c.purpleDeep,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Tutup', style: TextStyle(color: tokens.primary)),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, Color valueColor) {
    final tokens = _tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: tokens.textMuted),
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  String _formatTime(String? timestamp) {
    if (timestamp == null) return '-';
    try {
      final dt = DateTime.parse(timestamp);
      return DateFormat('HH:mm').format(dt);
    } catch (e) {
      return '-';
    }
  }

}
