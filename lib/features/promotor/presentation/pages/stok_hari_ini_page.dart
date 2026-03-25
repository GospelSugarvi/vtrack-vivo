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
  int _lowCount = 0;
  int _chipCount = 0;
  String? _storeName;
  String? _storeGrade;

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
        validationIds: validationIds,
      );

      if (!mounted) return;
      setState(() {
        _storeName = assigned['stores']?['store_name']?.toString();
        _storeGrade = assigned['stores']?['grade']?.toString();
        _hasValidationToday = validationIds.isNotEmpty;
        _emptyCount = groupedCounts['empty'] ?? 0;
        _lowCount = groupedCounts['low'] ?? 0;
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
    required List<String> validationIds,
  }) async {
    final variantsRaw = await _supabase
        .from('product_variants')
        .select('id')
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
      for (final row in (validatedRows as List)) {
        final stok = row['stok'] as Map<String, dynamic>?;
        final variantId = stok?['variant_id']?.toString() ?? '';
        if (variantId.isNotEmpty) {
          counts[variantId] = (counts[variantId] ?? 0) + 1;
        }
        if ('${stok?['tipe_stok'] ?? ''}' == 'chip') {
          chipCount++;
        }
      }

      final values = counts.values.toList();
      return {
        'empty': values.where((qty) => qty == 0).length,
        'low': values.where((qty) => qty > 0 && qty <= 2).length,
        'chip': chipCount,
      };
    }

    final stockRows = await _supabase
        .from('stok')
        .select('variant_id, tipe_stok')
        .eq('store_id', storeId)
        .eq('is_sold', false);

    var chipCount = 0;
    for (final row in (stockRows as List)) {
      final variantId = row['variant_id']?.toString() ?? '';
      if (variantId.isNotEmpty) {
        counts[variantId] = (counts[variantId] ?? 0) + 1;
      }
      if ('${row['tipe_stok'] ?? ''}' == 'chip') {
        chipCount++;
      }
    }

    final values = counts.values.toList();
    return {
      'empty': values.where((qty) => qty == 0).length,
      'low': values.where((qty) => qty > 0 && qty <= 2).length,
      'chip': chipCount,
    };
  }

  Widget _buildMetric({
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tone.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w600,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: PromotorText.outfit(
              size: 20,
              weight: FontWeight.w800,
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

  Widget _buildActionTile({
    required String title,
    required String shortLabel,
    required IconData icon,
    required Color iconTone,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.surface3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: iconTone.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconTone, size: 20),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: PromotorText.outfit(
                size: 15,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              shortLabel,
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
            const SizedBox(height: 10),
            Icon(Icons.arrow_forward_rounded, color: t.textMuted, size: 18),
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
                            'Stok Hari Ini',
                            style: PromotorText.display(
                              size: 20,
                              color: t.textPrimary,
                            ),
                          ),
                          Text(
                            '${_storeName ?? '-'} • Grade ${_storeGrade ?? '-'}',
                            style: PromotorText.outfit(
                              size: 13,
                              weight: FontWeight.w700,
                              color: t.textMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _loadData,
                      icon: Icon(Icons.refresh, color: t.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(16),
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
                              'Ringkasan Stok',
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
                      const SizedBox(height: 14),
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
                              label: 'Tipis',
                              value: '$_lowCount',
                              tone: t.warning,
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
                Row(
                  children: [
                    Expanded(
                      child: _buildActionTile(
                        title: 'Validasi',
                        shortLabel: 'Cek fisik',
                        icon: Icons.fact_check_outlined,
                        iconTone: t.primaryAccent,
                        onTap: () => context.push('/promotor/stok-validasi'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionTile(
                        title: 'Order',
                        shortLabel: 'Rekomendasi',
                        icon: Icons.assignment_outlined,
                        iconTone: t.warning,
                        onTap: () => context.push('/promotor/rekomendasi-order'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildActionTile(
                        title: 'Aksi',
                        shortLabel: 'Chip & klaim',
                        icon: Icons.tune_rounded,
                        iconTone: t.success,
                        onTap: () => context.push('/promotor/stok-aksi'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildActionTile(
                        title: 'Ringkasan',
                        shortLabel: 'Lihat stok',
                        icon: Icons.inventory_2_outlined,
                        iconTone: t.textPrimary,
                        onTap: () => context.push('/promotor/stok-ringkasan'),
                      ),
                    ),
                  ],
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
