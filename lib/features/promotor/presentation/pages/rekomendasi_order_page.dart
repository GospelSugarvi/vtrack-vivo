import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class RekomendasiOrderPage extends StatefulWidget {
  const RekomendasiOrderPage({super.key});

  @override
  State<RekomendasiOrderPage> createState() => _RekomendasiOrderPageState();
}

class _RekomendasiOrderPageState extends State<RekomendasiOrderPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _currency = NumberFormat.decimalPattern('id_ID');

  bool _isLoading = true;
  String _storeName = '-';
  String? _storeGrade;
  List<Map<String, dynamic>> _rows = const [];
  String _stockFilter = 'all';

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
          .select('store_id, stores(store_name, grade)')
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1);
      final assignments = List<Map<String, dynamic>>.from(assignmentRows);
      final assignment = assignments.isNotEmpty ? assignments.first : null;
      final storeId = assignment?['store_id']?.toString();

      if (storeId == null || storeId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _rows = const [];
          _isLoading = false;
        });
        return;
      }

      final storeName = '${assignment?['stores']?['store_name'] ?? '-'}';
      final storeGrade = assignment?['stores']?['grade']?.toString();

      final rows = await _loadRecommendationRows(
        storeId: storeId,
        storeGrade: storeGrade,
      );

      if (!mounted) return;
      setState(() {
        _storeName = storeName;
        _storeGrade = storeGrade;
        _rows = rows;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _isLoading = false;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _loadRecommendationRows({
    required String storeId,
    required String? storeGrade,
  }) async {
    final response = await _supabase.rpc(
      'get_store_recommendations',
      params: {'p_store_id': storeId},
    );
    final rows = List<Map<String, dynamic>>.from(response ?? []);

    rows.sort((a, b) {
      final stockCompare = _toInt(
        a['current_stock'],
      ).compareTo(_toInt(b['current_stock']));
      if (stockCompare != 0) return stockCompare;
      return '${a['product_name']}'.compareTo('${b['product_name']}');
    });
    return rows;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'HABIS':
        return t.danger;
      case 'KURANG':
        return t.warning;
      case 'READY':
        return t.success;
      default:
        return t.success;
    }
  }

  List<Map<String, dynamic>> _filteredRows() {
    switch (_stockFilter) {
      case 'empty':
        return _rows.where((row) => _toInt(row['current_stock']) <= 0).toList();
      case 'ready':
        return _rows
            .where((row) => '${row['status'] ?? ''}' == 'READY')
            .toList();
      default:
        return _rows;
    }
  }

  Widget _buildFilterChip({required String value, required String label}) {
    final selected = _stockFilter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _stockFilter = value),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: selected ? t.primaryAccent : t.textMutedStrong,
      ),
      backgroundColor: t.surface1,
      selectedColor: t.primaryAccentSoft,
      side: BorderSide(
        color: selected ? t.primaryAccent.withValues(alpha: 0.28) : t.surface3,
      ),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _terminalCell(
    String value, {
    required int flex,
    Color? color,
    FontWeight weight = FontWeight.w700,
    TextAlign textAlign = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: TextStyle(
          fontFamily: 'monospace',
          fontWeight: weight,
          fontSize: 11,
          color: color ?? t.textPrimary,
        ),
      ),
    );
  }

  Widget _buildCompactOrderRow(Map<String, dynamic> row) {
    final status = '${row['status'] ?? 'KURANG'}';
    final tone = _statusColor(status);
    final product = '${row['product_name'] ?? '-'} ${row['network_type'] ?? ''}'
        .trim();
    final variant = '${row['variant'] ?? '-'}';
    final color = '${row['color'] ?? '-'}';

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surface3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            product,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              _terminalCell(status, flex: 2, color: tone),
              _terminalCell(color, flex: 2, color: tone),
              _terminalCell(variant, flex: 2, color: tone),
              _terminalCell(
                '${_toInt(row['current_stock'])}',
                flex: 2,
                color: tone,
              ),
              _terminalCell(
                '${_toInt(row['min_stock'])}',
                flex: 2,
                color: tone,
              ),
              _terminalCell(
                '${_toInt(row['order_qty'])}',
                flex: 2,
                color: tone,
                weight: FontWeight.w800,
                textAlign: TextAlign.right,
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final filteredRows = _filteredRows();
    final totalOrderQty = _rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['order_qty']),
    );
    final emptyCount = _rows
        .where((row) => _toInt(row['current_stock']) <= 0)
        .length;
    final readyCount = _rows
        .where((row) => '${row['status'] ?? ''}' == 'READY')
        .length;

    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: const Text('Laporan Order')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.store)),
                      title: const Text('Toko Aktif'),
                      subtitle: Text(
                        _storeGrade == null || _storeGrade!.isEmpty
                            ? _storeName
                            : '$_storeName • Grade $_storeGrade',
                      ),
                      trailing: Text('${_currency.format(totalOrderQty)} unit'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_rows.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'Tidak ada data varian aktif untuk toko ini.',
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildFilterChip(
                                value: 'all',
                                label: 'Semua ${_rows.length}',
                              ),
                              _buildFilterChip(
                                value: 'empty',
                                label: 'Kosong $emptyCount',
                              ),
                              _buildFilterChip(
                                value: 'ready',
                                label: 'Ready $readyCount',
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'PRODUK',
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                          ),
                          Row(
                            children: [
                              _terminalCell(
                                'STATUS',
                                flex: 2,
                                color: t.primaryAccent,
                                weight: FontWeight.w800,
                              ),
                              _terminalCell(
                                'WARNA',
                                flex: 2,
                                color: t.primaryAccent,
                                weight: FontWeight.w800,
                              ),
                              _terminalCell(
                                'RAM',
                                flex: 2,
                                color: t.primaryAccent,
                                weight: FontWeight.w800,
                              ),
                              _terminalCell(
                                'STOK',
                                flex: 2,
                                color: t.primaryAccent,
                                weight: FontWeight.w800,
                              ),
                              _terminalCell(
                                'MIN',
                                flex: 2,
                                color: t.primaryAccent,
                                weight: FontWeight.w800,
                              ),
                              _terminalCell(
                                'ORDER',
                                flex: 2,
                                color: t.primaryAccent,
                                weight: FontWeight.w800,
                                textAlign: TextAlign.right,
                              ),
                            ],
                          ),
                          Text(
                            '-' * 44,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: t.surface4,
                            ),
                          ),
                          if (filteredRows.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Text(
                                'Tidak ada data untuk filter ini.',
                                style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: t.textMuted,
                                ),
                              ),
                            )
                          else
                            ...filteredRows.map(_buildCompactOrderRow),
                        ],
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
