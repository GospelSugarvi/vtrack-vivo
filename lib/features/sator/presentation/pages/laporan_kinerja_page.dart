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

      final summaryRaw = await _supabase.rpc(
        'get_sator_home_summary',
        params: {'p_sator_id': userId},
      );
      final summary = summaryRaw is Map
          ? Map<String, dynamic>.from(summaryRaw)
          : <String, dynamic>{};
      final weekly = summary['weekly'] as Map<String, dynamic>? ?? {};
      final weekStart = _parseDate(weekly['week_start']);
      final weekEnd = _parseDate(weekly['week_end']);
      if (weekStart == null || weekEnd == null) {
        throw Exception('Rentang minggu aktif tidak ditemukan.');
      }

      final promotorRows = await _loadPromotorWeeklyRows(
        userId: userId,
        weekStart: weekStart,
        weekEnd: weekEnd,
      );
      final storeRows = await _loadStoreWeeklyRows(
        userId: userId,
        weekStart: weekStart,
        weekEnd: weekEnd,
      );
      final alerts = _buildAlerts(
        promotorRows: promotorRows,
        storeRows: storeRows,
      );

      if (!mounted) return;
      setState(() {
        _summary = summary;
        _promotorRows = promotorRows;
        _storeRows = storeRows;
        _alerts = alerts;
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

  Future<List<Map<String, dynamic>>> _loadPromotorWeeklyRows({
    required String userId,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) async {
    final linkRows = await _supabase
        .from('hierarchy_sator_promotor')
        .select('promotor_id')
        .eq('sator_id', userId)
        .eq('active', true);
    final promotorIds = List<Map<String, dynamic>>.from(linkRows)
        .map((row) => row['promotor_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (promotorIds.isEmpty) return [];

    final profileRows = await _supabase
        .from('users')
        .select('id, full_name')
        .inFilter('id', promotorIds);
    final nameById = {
      for (final row in List<Map<String, dynamic>>.from(profileRows))
        row['id'].toString(): row['full_name']?.toString() ?? '-',
    };

    final storeRows = await _supabase
        .from('assignments_promotor_store')
        .select('promotor_id, created_at, stores(store_name)')
        .inFilter('promotor_id', promotorIds)
        .eq('active', true)
        .order('created_at', ascending: false);
    final storeByPromotor = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(storeRows)) {
      final promotorId = row['promotor_id']?.toString() ?? '';
      if (promotorId.isEmpty || storeByPromotor.containsKey(promotorId)) {
        continue;
      }
      storeByPromotor[promotorId] =
          row['stores']?['store_name']?.toString() ?? '-';
    }

    final start = DateFormat('yyyy-MM-dd').format(weekStart);
    final end = DateFormat('yyyy-MM-dd').format(weekEnd);
    final dailyDashboardByPromotor = <String, Map<String, dynamic>>{};
    for (final promotorId in promotorIds) {
      final result = await _supabase.rpc(
        'get_daily_target_dashboard',
        params: {'p_user_id': promotorId, 'p_date': start},
      );
      if (result is List && result.isNotEmpty && result.first is Map) {
        dailyDashboardByPromotor[promotorId] = Map<String, dynamic>.from(
          result.first as Map,
        );
      } else if (result is Map && result.isNotEmpty) {
        dailyDashboardByPromotor[promotorId] = Map<String, dynamic>.from(
          result,
        );
      }
    }

    final salesRows = await _supabase
        .from('sales_sell_out')
        .select(
          'promotor_id, store_id, price_at_transaction, variant_id, transaction_date, '
          'product_variants(product_id, products(is_focus)), stores(store_name)',
        )
        .inFilter('promotor_id', promotorIds)
        .gte('transaction_date', start)
        .lte('transaction_date', end)
        .eq('is_chip_sale', false)
        .isFilter('deleted_at', null);

    final omzetByPromotor = <String, double>{};
    final focusByPromotor = <String, int>{};
    for (final row in List<Map<String, dynamic>>.from(salesRows)) {
      final promotorId = row['promotor_id']?.toString() ?? '';
      if (promotorId.isEmpty) continue;
      omzetByPromotor[promotorId] =
          (omzetByPromotor[promotorId] ?? 0) +
          _toDouble(row['price_at_transaction']);
      final isFocus = row['product_variants']?['products']?['is_focus'] == true;
      if (isFocus) {
        focusByPromotor[promotorId] = (focusByPromotor[promotorId] ?? 0) + 1;
      }
    }

    final rows = <Map<String, dynamic>>[];
    for (final promotorId in promotorIds) {
      final dashboard = dailyDashboardByPromotor[promotorId] ?? {};
      final targetOmzet = _toDouble(dashboard['target_weekly_all_type']);
      final actualOmzet = omzetByPromotor[promotorId] ?? 0;
      final targetFocus = _toDouble(dashboard['target_weekly_focus']);
      final actualFocus = _toInt(dashboard['actual_weekly_focus']) > 0
          ? _toInt(dashboard['actual_weekly_focus'])
          : (focusByPromotor[promotorId] ?? 0);
      final achievement = targetOmzet > 0
          ? (actualOmzet * 100 / targetOmzet)
          : 0;

      rows.add({
        'promotor_id': promotorId,
        'name': nameById[promotorId] ?? '-',
        'store_name': storeByPromotor[promotorId] ?? '-',
        'target_weekly_omzet': targetOmzet,
        'actual_weekly_omzet': actualOmzet,
        'target_weekly_focus': targetFocus,
        'actual_weekly_focus': actualFocus,
        'achievement_pct': achievement,
      });
    }

    rows.sort(
      (a, b) => _toDouble(
        b['actual_weekly_omzet'],
      ).compareTo(_toDouble(a['actual_weekly_omzet'])),
    );
    return rows;
  }

  Future<List<Map<String, dynamic>>> _loadStoreWeeklyRows({
    required String userId,
    required DateTime weekStart,
    required DateTime weekEnd,
  }) async {
    final linkRows = await _supabase
        .from('hierarchy_sator_promotor')
        .select('promotor_id')
        .eq('sator_id', userId)
        .eq('active', true);
    final promotorIds = List<Map<String, dynamic>>.from(linkRows)
        .map((row) => row['promotor_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    if (promotorIds.isEmpty) return [];

    final storeRows = await _supabase
        .from('assignments_promotor_store')
        .select('promotor_id, store_id, created_at, stores(store_name)')
        .inFilter('promotor_id', promotorIds)
        .eq('active', true)
        .order('created_at', ascending: false);

    final storeInfoByPromotor = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(storeRows)) {
      final promotorId = row['promotor_id']?.toString() ?? '';
      if (promotorId.isEmpty || storeInfoByPromotor.containsKey(promotorId)) {
        continue;
      }
      storeInfoByPromotor[promotorId] = {
        'store_id': row['store_id']?.toString() ?? '',
        'store_name': row['stores']?['store_name']?.toString() ?? '-',
      };
    }

    final start = DateFormat('yyyy-MM-dd').format(weekStart);
    final end = DateFormat('yyyy-MM-dd').format(weekEnd);
    final salesRows = await _supabase
        .from('sales_sell_out')
        .select(
          'promotor_id, price_at_transaction, variant_id, transaction_date, '
          'product_variants(product_id, products(is_focus))',
        )
        .inFilter('promotor_id', promotorIds)
        .gte('transaction_date', start)
        .lte('transaction_date', end)
        .eq('is_chip_sale', false)
        .isFilter('deleted_at', null);

    final storeAggregate = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(salesRows)) {
      final promotorId = row['promotor_id']?.toString() ?? '';
      final storeInfo = storeInfoByPromotor[promotorId];
      if (storeInfo == null) continue;
      final storeId = storeInfo['store_id']?.toString() ?? '';
      if (storeId.isEmpty) continue;
      final current = storeAggregate.putIfAbsent(
        storeId,
        () => {
          'store_id': storeId,
          'store_name': storeInfo['store_name'] ?? '-',
          'omzet': 0.0,
          'focus_units': 0,
          'promotor_count': 0,
        },
      );
      current['omzet'] =
          _toDouble(current['omzet']) + _toDouble(row['price_at_transaction']);
      final isFocus = row['product_variants']?['products']?['is_focus'] == true;
      if (isFocus) {
        current['focus_units'] = _toInt(current['focus_units']) + 1;
      }
    }

    final uniquePromotorCountByStore = <String, int>{};
    for (final storeInfo in storeInfoByPromotor.values) {
      final storeId = storeInfo['store_id']?.toString() ?? '';
      if (storeId.isEmpty) continue;
      uniquePromotorCountByStore[storeId] =
          (uniquePromotorCountByStore[storeId] ?? 0) + 1;
      storeAggregate.putIfAbsent(
        storeId,
        () => {
          'store_id': storeId,
          'store_name': storeInfo['store_name'] ?? '-',
          'omzet': 0.0,
          'focus_units': 0,
          'promotor_count': 0,
        },
      );
    }

    for (final entry in storeAggregate.entries) {
      entry.value['promotor_count'] =
          uniquePromotorCountByStore[entry.key] ?? 0;
    }

    final rows = storeAggregate.values.toList()
      ..sort((a, b) => _toDouble(b['omzet']).compareTo(_toDouble(a['omzet'])));
    return rows;
  }

  List<Map<String, dynamic>> _buildAlerts({
    required List<Map<String, dynamic>> promotorRows,
    required List<Map<String, dynamic>> storeRows,
  }) {
    final alerts = <Map<String, dynamic>>[];

    final noSales = promotorRows
        .where((row) => _toDouble(row['actual_weekly_omzet']) <= 0)
        .toList();
    if (noSales.isNotEmpty) {
      alerts.add({
        'title': 'Promotor Belum Bergerak',
        'count': noSales.length,
        'note':
            '${noSales.first['name']} dan lainnya belum ada sell out minggu ini',
        'color': t.danger,
      });
    }

    final lowAchievement = promotorRows
        .where((row) => _toDouble(row['achievement_pct']) > 0)
        .where((row) => _toDouble(row['achievement_pct']) < 40)
        .toList();
    if (lowAchievement.isNotEmpty) {
      alerts.add({
        'title': 'Promotor Tertinggal',
        'count': lowAchievement.length,
        'note':
            '${lowAchievement.first['name']} masih jauh di bawah target minggu ini',
        'color': t.warning,
      });
    }

    final quietStores = storeRows
        .where((row) => _toDouble(row['omzet']) <= 0)
        .toList();
    if (quietStores.isNotEmpty) {
      alerts.add({
        'title': 'Toko Perlu Atensi',
        'count': quietStores.length,
        'note':
            '${quietStores.first['store_name']} belum ada penjualan pada minggu aktif',
        'color': t.primaryAccent,
      });
    }

    return alerts;
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
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
    final color = alert['color'] as Color? ?? t.primaryAccent;
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
