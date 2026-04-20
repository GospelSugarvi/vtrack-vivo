import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/promotor/promotor.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

class StokHariIniPage extends StatefulWidget {
  const StokHariIniPage({super.key});

  @override
  State<StokHariIniPage> createState() => _StokHariIniPageState();
}

class _StokHariIniPageState extends State<StokHariIniPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _hasValidationToday = false;
  int _emptyCount = 0;
  int _readyCount = 0;
  int _chipCount = 0;
  String? _storeName;
  void _handleBack() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    context.go('/promotor');
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      final assignmentRows = await _supabase
          .from('assignments_promotor_store')
          .select('store_id, stores(store_name, grade)')
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1);
      final assignments = List<Map<String, dynamic>>.from(assignmentRows);
      final assigned = assignments.isNotEmpty ? assignments.first : null;

      if (assigned == null) {
        throw Exception('Anda belum ditugaskan di toko manapun.');
      }

      final storeId = assigned['store_id']?.toString();
      if (storeId == null || storeId.isEmpty) {
        throw Exception('Store promotor tidak ditemukan.');
      }

      final scopeStoreIds = await _loadStockScopeStoreIds(storeId);

      final now = DateTime.now();
      final startOfDay = DateTime(
        now.year,
        now.month,
        now.day,
      ).toIso8601String();
      final endOfDay = DateTime(
        now.year,
        now.month,
        now.day,
        23,
        59,
        59,
      ).toIso8601String();

      final validations = await _supabase
          .from('stock_validations')
          .select('id')
          .eq('store_id', storeId)
          .eq('status', 'completed')
          .gte('validation_date', startOfDay)
          .lte('validation_date', endOfDay);

      final validationIds = (validations as List)
          .map((row) => row['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final groupedCounts = await _buildCounts(
        storeId: storeId,
        scopeStoreIds: scopeStoreIds,
        validationIds: validationIds,
      );

      if (!mounted) return;
      setState(() {
        _storeName = assigned['stores']?['store_name']?.toString();
        _hasValidationToday = validationIds.isNotEmpty;
        _emptyCount = groupedCounts['empty'] ?? 0;
        _readyCount = groupedCounts['ready'] ?? 0;
        _chipCount = groupedCounts['chip'] ?? 0;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Gagal memuat stok hari ini: $e',
      );
    }
  }

  Future<Map<String, int>> _buildCounts({
    required String storeId,
    required List<String> scopeStoreIds,
    required List<String> validationIds,
  }) async {
    final variantsRaw = await _supabase
        .from('product_variants')
        .select('id')
        .isFilter('deleted_at', null)
        .order('id');

    final counts = <String, int>{};
    for (final row in (variantsRaw as List)) {
      final variantId = row['id']?.toString() ?? '';
      if (variantId.isNotEmpty) counts[variantId] = 0;
    }

    if (validationIds.isNotEmpty) {
      final validatedRows = await _supabase
          .from('stock_validation_items')
          .select('stok:stok_id(variant_id, tipe_stok)')
          .filter(
            'validation_id',
            'in',
            '(${validationIds.map((id) => '"$id"').join(',')})',
          );

      var chipCount = 0;
      var readyCount = 0;
      for (final row in (validatedRows as List)) {
        final stok = row['stok'] as Map<String, dynamic>?;
        final variantId = stok?['variant_id']?.toString() ?? '';
        if (variantId.isNotEmpty) {
          counts[variantId] = (counts[variantId] ?? 0) + 1;
        }
        if ('${stok?['tipe_stok'] ?? ''}' == 'chip') {
          chipCount++;
        } else {
          readyCount++;
        }
      }

      final values = counts.values.toList();
      return {
        'empty': values.where((qty) => qty == 0).length,
        'ready': readyCount,
        'chip': chipCount,
      };
    }

    final stockRows = await _supabase
        .from('stok')
        .select('variant_id, tipe_stok')
        .inFilter(
          'store_id',
          scopeStoreIds.isNotEmpty ? scopeStoreIds : <String>[storeId],
        )
        .eq('is_sold', false);

    var chipCount = 0;
    var readyCount = 0;
    for (final row in (stockRows as List)) {
      final variantId = row['variant_id']?.toString() ?? '';
      if (variantId.isNotEmpty) {
        counts[variantId] = (counts[variantId] ?? 0) + 1;
      }
      if ('${row['tipe_stok'] ?? ''}' == 'chip') {
        chipCount++;
      } else {
        readyCount++;
      }
    }

    final values = counts.values.toList();
    return {
      'empty': values.where((qty) => qty == 0).length,
      'ready': readyCount,
      'chip': chipCount,
    };
  }

  Future<List<String>> _loadStockScopeStoreIds(String storeId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      try {
        final rpcResult = await _supabase.rpc(
          'get_promotor_stock_scope',
          params: {'p_promotor_id': userId},
        );
        final rpcMap = rpcResult is Map<String, dynamic>
            ? rpcResult
            : Map<String, dynamic>.from(rpcResult as Map);
        final rpcScope = (rpcMap['stock_scope_store_ids'] as List? ?? const [])
            .map((item) => '${item ?? ''}'.trim())
            .where((id) => id.isNotEmpty)
            .toList();
        if (rpcScope.isNotEmpty) {
          return rpcScope;
        }
      } catch (_) {}
    }

    final storeRow = await _supabase
        .from('stores')
        .select('group_id')
        .eq('id', storeId)
        .maybeSingle();
    final groupId = '${storeRow?['group_id'] ?? ''}'.trim();
    Map<String, dynamic> group = <String, dynamic>{};
    if (groupId.isNotEmpty) {
      final groupRow = await _supabase
          .from('store_groups')
          .select('stock_handling_mode')
          .eq('id', groupId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (groupRow != null) {
        group = Map<String, dynamic>.from(groupRow);
      }
    }
    final groupMode = '${group['stock_handling_mode'] ?? ''}'.trim();
    if (groupId.isEmpty || groupMode != 'shared_group') {
      return <String>[storeId];
    }

    final storeRows = await _supabase
        .from('stores')
        .select('id')
        .eq('group_id', groupId)
        .isFilter('deleted_at', null);
    final ids = List<Map<String, dynamic>>.from(storeRows)
        .map((row) => '${row['id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    return ids.isEmpty ? <String>[storeId] : ids;
  }

  Widget _buildMetric({
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: PromotorText.outfit(
              size: 18,
              weight: FontWeight.w900,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip() {
    final isDone = _hasValidationToday;
    final tone = isDone ? t.success : t.warning;
    final bg = isDone ? t.successSoft : t.warningSoft;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isDone ? Icons.verified_rounded : Icons.schedule_rounded,
            size: 14,
            color: tone,
          ),
          const SizedBox(width: 6),
          Text(
            isDone ? 'Sudah divalidasi' : 'Belum divalidasi',
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStockMenuIcon({
    required String label,
    required IconData icon,
    required Color iconTone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: iconTone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: iconTone.withValues(alpha: 0.18)),
              ),
              child: Icon(icon, color: iconTone, size: 26),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    if (_isLoading) {
      return Scaffold(
        backgroundColor: t.textOnAccent,
        body: Center(child: CircularProgressIndicator(color: t.primaryAccent)),
      );
    }

    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: Container(
        color: t.background,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _loadData,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: _handleBack,
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: t.textPrimary,
                      ),
                      tooltip: 'Kembali',
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stok Toko',
                            style: PromotorText.display(
                              size: 20,
                              color: t.textPrimary,
                            ),
                          ),
                          Text(
                            _storeName ?? '-',
                            style: PromotorText.outfit(
                              size: 13,
                              weight: FontWeight.w700,
                              color: t.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Stok Toko',
                              style: PromotorText.outfit(
                                size: 16,
                                weight: FontWeight.w800,
                                color: t.textPrimary,
                              ),
                            ),
                          ),
                          _buildStatusChip(),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _buildMetric(
                              label: 'Kosong',
                              value: '$_emptyCount',
                              tone: t.danger,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetric(
                              label: 'Ready',
                              value: '$_readyCount',
                              tone: t.success,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetric(
                              label: 'Chip',
                              value: '$_chipCount',
                              tone: t.primaryAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Menu Stok',
                  style: PromotorText.outfit(
                    size: 14,
                    weight: FontWeight.w800,
                    color: t.textMutedStrong,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Expanded(
                        child: _buildStockMenuIcon(
                          label: 'Validasi',
                          icon: Icons.fact_check_outlined,
                          iconTone: t.primaryAccent,
                          onTap: () =>
                              context.push('/promotor/stock-validation'),
                        ),
                      ),
                      Expanded(
                        child: _buildStockMenuIcon(
                          label: 'Management Stok',
                          icon: Icons.tune_rounded,
                          iconTone: t.success,
                          onTap: () => context.push('/promotor/stok-aksi'),
                        ),
                      ),
                      Expanded(
                        child: _buildStockMenuIcon(
                          label: 'Stok Toko',
                          icon: Icons.inventory_2_outlined,
                          iconTone: t.textPrimary,
                          onTap: () => context.push('/promotor/stok-ringkasan'),
                        ),
                      ),
                      Expanded(
                        child: _buildStockMenuIcon(
                          label: 'Cari Antar Toko',
                          icon: Icons.storefront_outlined,
                          iconTone: t.info,
                          onTap: () => context.push('/promotor/cari-stok'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Diperbarui ${DateFormat('dd MMM yyyy', 'id_ID').format(DateTime.now())}',
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.textMutedStrong,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
