import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../repository/chat_repository.dart';
import 'dart:convert';
import '../../../allbrand/presentation/pages/allbrand_store_detail_page.dart';
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

  Map<String, dynamic> _safeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [_buildQuickStatsBar(), if (_isExpanded) _buildExpandedPanel()],
    );
  }

  Widget _buildQuickStatsBar() {
    final tokens = _tokens;
    final c = _palette;
    final targetData = _performanceData?['target'] as Map<String, dynamic>?;
    final allbrandData = _performanceData?['allbrand'] as Map<String, dynamic>?;
    final activityData = _performanceData?['activity'] as List?;
    final selloutRows =
        List<Map<String, dynamic>>.from(
          (targetData?['sellout_by_promotor'] as List?) ?? const [],
        );
    final dailyAchievement = targetData?['daily_achievement'] ?? 0;
    final dailyTarget = targetData?['daily_target'] ?? 0;
    final achievementPercent = dailyTarget > 0
        ? ((dailyAchievement / dailyTarget) * 100).round()
        : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.store, size: 18, color: tokens.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.storeName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: tokens.textPrimary,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: tokens.textMuted,
                ),
                onPressed: () => setState(() => _isExpanded = !_isExpanded),
              ),
              IconButton(
                icon: Icon(Icons.refresh, size: 20, color: tokens.textMuted),
                onPressed: _isLoading ? null : _loadData,
              ),
            ],
          ),
          if (!_isExpanded) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                _buildQuickStat(
                  'Sellout',
                  '$achievementPercent%',
                  '${_formatCurrency(dailyAchievement)}/${_formatCurrency(dailyTarget)}',
                  _getAchievementColor(achievementPercent.toDouble()),
                ),
                const SizedBox(width: 12),
                _buildQuickStat(
                  'AllBrand',
                  '${allbrandData?['total_store_units'] ?? allbrandData?['total_units'] ?? 0}',
                  'MS ${((allbrandData?['vivo_market_share'] as num?) ?? 0).toStringAsFixed(1)}%',
                  c.amber,
                ),
                const SizedBox(width: 12),
                _buildQuickStat(
                  'Promotor',
                  '${selloutRows.length}',
                  '${activityData?.length ?? 0} aktivitas',
                  c.purple,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickStat(
    String label,
    String value,
    String subtitle,
    Color color,
  ) {
    final tokens = _tokens;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: tokens.surfaceAlt,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 11, color: tokens.textMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
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
            decoration: BoxDecoration(
              color: tokens.surfaceAlt,
              border: Border(bottom: BorderSide(color: tokens.border)),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: tokens.primary,
              unselectedLabelColor: tokens.textMuted,
              indicatorColor: tokens.primary,
              tabs: const [
                Tab(text: 'AllBrand'),
                Tab(text: 'Sellout'),
                Tab(text: 'Aktivitas'),
              ],
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
                      _buildSelloutTab(),
                      _buildActivityTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelloutTab() {
    final tokens = _tokens;
    final c = _palette;
    final targetData = _performanceData?['target'] as Map<String, dynamic>?;
    if (targetData == null) {
      return Center(
        child: Text(
          'Belum ada data sellout',
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }

    final selloutRows = List<Map<String, dynamic>>.from(
      (targetData['sellout_by_promotor'] as List?) ?? const [],
    );
    final dailyAchievement = targetData['daily_achievement'] ?? 0;
    final dailyTarget = targetData['daily_target'] ?? 0;
    final promotorCount = targetData['promotor_count'] ?? 0;
    final dailyPercent = dailyTarget > 0
        ? (dailyAchievement / dailyTarget * 100)
        : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.people, size: 16, color: tokens.primary),
              const SizedBox(width: 6),
              Text(
                '$promotorCount Promotor Aktif',
                style: TextStyle(
                  fontSize: 12,
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildTargetCard(
            'Sellout Toko Hari Ini',
            dailyAchievement,
            dailyTarget,
            dailyPercent,
            c.green,
          ),
          const SizedBox(height: 14),
          Text(
            'Sellout Per Promotor',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: tokens.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          if (selloutRows.isEmpty)
            Text(
              'Belum ada sellout promotor hari ini',
              style: TextStyle(fontSize: 12, color: tokens.textMuted),
            )
          else
            Column(
              children: selloutRows
                  .map((row) => _buildSelloutPromotorRow(row))
                  .toList(),
            ),
        ],
      ),
    );
  }

  Widget _buildSelloutPromotorRow(Map<String, dynamic> row) {
    final tokens = _tokens;
    final c = _palette;
    final name = '${row['promotor_name'] ?? 'Promotor'}';
    final units = _toInt(row['units']);
    final omzet = _toInt(row['omzet']);
    final focusUnits = _toInt(row['focus_units']);
    final variants = List<String>.from((row['variants'] as List?) ?? const []);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
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
              Text(
                '$units unit',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _formatCurrency(omzet),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: c.gold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Produk Fokus $focusUnits',
            style: TextStyle(fontSize: 11, color: c.purple),
          ),
          if (variants.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              variants.take(3).join(' • '),
              style: TextStyle(fontSize: 11, color: tokens.textMuted),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetCard(
    String title,
    int achievement,
    int target,
    double percent,
    Color color,
  ) {
    final tokens = _tokens;
    return InkWell(
      onTap: () =>
          _showTargetDetail(title, achievement, target, percent, color),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: tokens.textPrimary,
                    ),
                  ),
                ),
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: color.withValues(alpha: 0.7),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: percent / 100,
                minHeight: 8,
                backgroundColor: tokens.border,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${percent.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  '${_formatCurrency(achievement)} / ${_formatCurrency(target)}',
                  style: TextStyle(fontSize: 12, color: tokens.textSecondary),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showTargetDetail(
    String title,
    int achievement,
    int target,
    double percent,
    Color color,
  ) {
    final tokens = _tokens;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: tokens.surface,
        title: Text(
          title,
          style: TextStyle(fontSize: 16, color: tokens.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow(
                'Achievement',
                _formatCurrencyFull(achievement),
                color,
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Target',
                _formatCurrencyFull(target),
                tokens.textSecondary,
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Persentase',
                '${percent.toStringAsFixed(1)}%',
                color,
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 12,
                  backgroundColor: tokens.border,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
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

  Widget _buildAllbrandTab() {
    final tokens = _tokens;
    final c = _palette;
    final allbrandData = _performanceData?['allbrand'] as Map<String, dynamic>?;
    if (allbrandData == null || allbrandData['has_data'] != true) {
      return Center(
        child: Text(
          'Belum ada laporan AllBrand untuk toko ini',
          style: TextStyle(color: tokens.textMuted),
        ),
      );
    }

    final totalUnits = _toInt(allbrandData['total_units']);
    final totalStoreUnits = _toInt(allbrandData['total_store_units']);
    final vivoUnits = _toInt(allbrandData['vivo_units']);
    final marketShare = ((allbrandData['vivo_market_share'] as num?) ?? 0)
        .toDouble();
    final leasingTotalUnits = _toInt(allbrandData['leasing_total_units']);
    final promotorTotal = _toInt(allbrandData['promotor_total']);
    final focusStoreDaily = _toInt(allbrandData['focus_store_daily']);
    final focusStoreCumulative = _toInt(allbrandData['focus_store_cumulative']);
    final reportDate = '${allbrandData['report_date'] ?? '-'}';
    final isToday = allbrandData['is_today'] == true;
    final history = List<Map<String, dynamic>>.from(
      (allbrandData['history'] as List?) ?? const [],
    );
    final brandsRaw = allbrandData['brands'];
    final leasingRaw = allbrandData['leasing_sales'];
    final vivoAuto = allbrandData['vivo_auto'];
    final focusByPromotor = List<Map<String, dynamic>>.from(
      (allbrandData['focus_by_promotor'] as List?) ?? const [],
    );
    final brandShare = List<Map<String, dynamic>>.from(
      (allbrandData['brand_share'] as List?) ?? const [],
    );
    final brands = _safeMap(brandsRaw);
    final leasing = _safeMap(leasingRaw);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.surfaceAlt,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: tokens.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Snapshot AllBrand',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: tokens.textPrimary,
                      ),
                    ),
                    Text(
                      isToday ? 'Hari ini' : 'Terakhir: $reportDate',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isToday ? c.green : tokens.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _buildMetricChip(
                      'Total Toko',
                      '$totalStoreUnits unit',
                      c.amber,
                    ),
                    _buildMetricChip(
                      'Competitor',
                      '$totalUnits unit',
                      tokens.textSecondary,
                    ),
                    _buildMetricChip('VIVO', '$vivoUnits unit', c.blue),
                    _buildMetricChip(
                      'MS VIVO',
                      '${marketShare.toStringAsFixed(1)}%',
                      c.green,
                    ),
                    _buildMetricChip(
                      'Leasing',
                      '$leasingTotalUnits unit',
                      c.gold,
                    ),
                    _buildMetricChip(
                      'Promotor',
                      '$promotorTotal org',
                      c.purpleDeep,
                    ),
                    _buildMetricChip(
                      'Fokus',
                      '$focusStoreDaily / $focusStoreCumulative',
                      c.purple,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AllbrandStoreDetailPage(
                            storeId: widget.storeId,
                            storeName: widget.storeName,
                          ),
                        ),
                      );
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: tokens.primary,
                      side: BorderSide(
                        color: tokens.primary.withValues(alpha: 0.4),
                      ),
                    ),
                    child: const Text('Lihat detail lengkap'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (focusByPromotor.isNotEmpty) ...[
            Text(
              'Produk Fokus per Promotor',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...focusByPromotor.map(
              (item) => _buildLeasingRow(
                '${item['name']}',
                _toInt(item['today']),
                c.purple,
                trailing:
                    '${_toInt(item['today'])} / ${_toInt(item['cumulative'])}',
              ),
            ),
            const Divider(height: 24),
          ],
          if (brandShare.isNotEmpty) ...[
            Text(
              'Market Share Brand',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...brandShare.map(
              (item) => _buildLeasingRow(
                '${item['label']}',
                _toInt(item['units']),
                c.amber,
                trailing:
                    '${_toInt(item['units'])} unit • ${((item['share'] as num?) ?? 0).toStringAsFixed(1)}%',
              ),
            ),
            const Divider(height: 24),
          ],
          if (vivoAuto != null) ...[
            Text(
              'VIVO (Auto)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            _buildBrandRow(
              'VIVO',
              _toInt(_safeMap(vivoAuto)['total']),
              c.blue,
              _safeMap(vivoAuto),
            ),
            const Divider(height: 24),
          ],
          if (brands.isNotEmpty) ...[
            Text(
              'Brand Lain',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...brands.entries.map((entry) {
              final brandData = _safeMap(entry.value);
              final total =
                  _toInt(brandData['under_2m']) +
                  _toInt(brandData['2m_4m']) +
                  _toInt(brandData['4m_6m']) +
                  _toInt(brandData['above_6m']);
              return _buildBrandRow(
                entry.key,
                total,
                tokens.textSecondary,
                brandData,
              );
            }),
          ],
          if (leasing.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              'Penjualan per Leasing',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...leasing.entries.map(
              (entry) => _buildLeasingRow(
                entry.key,
                _toInt(entry.value),
                c.green,
              ),
            ),
          ],
          if (history.isNotEmpty) ...[
            const Divider(height: 24),
            Text(
              'Riwayat 7 Hari',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: tokens.textSecondary,
              ),
            ),
            const SizedBox(height: 8),
            ...history.take(7).map((row) {
              final dateText = '${row['report_date'] ?? '-'}';
              final rowTotalStore = _toInt(row['total_store_units']);
              final rowVivo = _toInt(row['vivo_units']);
              final rowMs = ((row['vivo_market_share'] as num?) ?? 0)
                  .toDouble();
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: tokens.surfaceAlt,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: tokens.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        dateText,
                        style: TextStyle(
                          fontSize: 12,
                          color: tokens.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      'Toko $rowTotalStore | VIVO $rowVivo | MS ${rowMs.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 13,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricChip(String label, String value, Color color) {
    final tokens = _tokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.chipBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.chipBorder),
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 13,
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildBrandRow(
    String name,
    int units,
    Color color,
    Map<String, dynamic>? detailData,
  ) {
    final tokens = _tokens;
    return InkWell(
      onTap: detailData != null
          ? () => _showBrandDetail(name, detailData)
          : null,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: tokens.surfaceAlt,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: tokens.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                name,
                style: TextStyle(fontSize: 13, color: tokens.textSecondary),
              ),
              Row(
                children: [
                  Text(
                    '$units unit',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  if (detailData != null) ...[
                    const SizedBox(width: 4),
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: tokens.textMuted,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeasingRow(
    String name,
    int units,
    Color color, {
    String? trailing,
  }) {
    final tokens = _tokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.surfaceAlt,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tokens.border),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              name,
              style: TextStyle(fontSize: 13, color: tokens.textSecondary),
            ),
            Text(
              trailing ?? '$units unit',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBrandDetail(String brandName, Map<String, dynamic> data) {
    final tokens = _tokens;
    final c = _palette;
    final under2m = _toInt(data['under_2m']);
    final m2to4 = _toInt(data['2m_4m']);
    final m4to6 = _toInt(data['4m_6m']);
    final above6m = _toInt(data['above_6m']);
    final total = _toInt(data['total']) > 0
        ? _toInt(data['total'])
        : (under2m + m2to4 + m4to6 + above6m);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        scrollable: true,
        backgroundColor: tokens.surface,
        title: Text(
          'Detail $brandName',
          style: TextStyle(fontSize: 16, color: tokens.textPrimary),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDetailRow('Total', '$total unit', c.amber),
              const Divider(height: 20),
              Text(
                'Breakdown per Harga:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow('< 2 Juta', '$under2m unit', tokens.textSecondary),
              const SizedBox(height: 6),
              _buildDetailRow('2-4 Juta', '$m2to4 unit', tokens.textSecondary),
              const SizedBox(height: 6),
              _buildDetailRow('4-6 Juta', '$m4to6 unit', tokens.textSecondary),
              const SizedBox(height: 6),
              _buildDetailRow('> 6 Juta', '$above6m unit', tokens.textSecondary),
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
            Row(
              children: [
                _buildActivityStat(
                  Icons.schedule,
                  hasClockIn ? _formatTime(clockIn) : '-',
                  c.blue,
                ),
                const SizedBox(width: 16),
                _buildActivityStat(
                  Icons.schedule_outlined,
                  hasClockOut ? _formatTime(clockOut) : '-',
                  c.amber,
                ),
                const SizedBox(width: 16),
                _buildActivityStat(
                  Icons.shopping_cart,
                  '$salesCount',
                  c.green,
                ),
                const SizedBox(width: 16),
                _buildActivityStat(
                  Icons.inventory,
                  '$stockCount',
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
                'Clock In',
                hasClockIn ? _formatTime(clockIn) : 'Belum masuk',
                hasClockIn ? c.green : c.red,
              ),
              const SizedBox(height: 6),
              _buildDetailRow(
                'Clock Out',
                hasClockOut ? _formatTime(clockOut) : 'Belum keluar',
                hasClockOut ? c.amber : tokens.textMuted,
              ),
              const SizedBox(height: 6),
              _buildDetailRow('Durasi Kerja', workDuration, c.blue),
              const Divider(height: 20),
              Text(
                'Aktivitas',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: tokens.textSecondary,
                ),
              ),
              const SizedBox(height: 8),
              _buildDetailRow(
                'Penjualan',
                '$salesCount transaksi',
                c.green,
              ),
              const SizedBox(height: 6),
              _buildDetailRow(
                'Stock Movement',
                '$stockCount pergerakan',
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

  String _formatCurrency(int value) {
    final formatter = NumberFormat('#,###', 'id_ID');
    return formatter.format(value);
  }

  String _formatCurrencyFull(int value) {
    final formatter = NumberFormat('#,###', 'id_ID');
    return 'Rp ${formatter.format(value)}';
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

  Color _getAchievementColor(double percent) {
    final c = _palette;
    if (percent >= 100) return c.green;
    if (percent >= 75) return c.amber;
    return c.red;
  }
}
