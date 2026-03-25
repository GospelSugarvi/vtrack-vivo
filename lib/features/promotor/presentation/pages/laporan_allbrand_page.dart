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

  bool _isLoading = true;
  String? _storeId;
  String _storeName = '-';
  List<Map<String, dynamic>> _rows = const [];
  bool _hasTodayReport = false;

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

      final reportRows = await _supabase
          .from('allbrand_reports')
          .select('id, report_date, daily_total_units, cumulative_total_units, notes, updated_at')
          .eq('store_id', storeId)
          .order('report_date', ascending: false)
          .limit(30);

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
      setState(() {
        _storeId = storeId;
        _storeName = '${assignment['stores']?['store_name'] ?? '-'}';
        _rows = List<Map<String, dynamic>>.from(reportRows);
        _hasTodayReport = todayReport != null;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _hasTodayReport = false;
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

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 14),
                  _HeaderCard(
                    storeName: _storeName,
                    count: _rows.length,
                    hasTodayReport: _hasTodayReport,
                  ),
                  const SizedBox(height: 14),
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
                    const _EmptyState(
                      title: 'Belum ada laporan',
                    )
                  else
                    ..._rows.map(
                      (row) => Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: BorderRadius.circular(22),
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
                            horizontal: 18,
                            vertical: 10,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
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
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: t.primaryAccentSoft,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(
              Icons.hub_outlined,
              color: t.primaryAccent,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Laporan All Brand',
                  style: PromotorText.display(size: 20, color: t.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  'Pantau input harian toko dan buka detail laporan dengan tampilan yang seragam dengan tema promotor.',
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
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

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.storeName,
    required this.count,
    required this.hasTodayReport,
  });

  final String storeName;
  final int count;
  final bool hasTodayReport;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: t.primaryAccentSoft,
            foregroundColor: t.primaryAccent,
            child: const Icon(Icons.storefront_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Workplace All Brand',
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w700,
                    color: t.primaryAccent,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  storeName,
                  style: PromotorText.display(size: 18, color: t.textPrimary),
                ),
                const SizedBox(height: 6),
                Text(
                  hasTodayReport ? 'Laporan hari ini sudah ada' : 'Belum ada laporan hari ini',
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w700,
                    color: hasTodayReport ? t.success : t.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                Text(
                  '$count',
                  style: PromotorText.display(size: 18, color: t.textPrimary),
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
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.title});

  final String title;

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
            'Input pertama akan muncul di halaman ini.',
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
