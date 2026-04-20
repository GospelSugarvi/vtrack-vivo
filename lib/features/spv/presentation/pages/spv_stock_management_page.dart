import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/features/promotor/presentation/pages/stok_toko_page.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class SpvStockManagementPage extends StatefulWidget {
  const SpvStockManagementPage({super.key});

  @override
  State<SpvStockManagementPage> createState() =>
      _SpvStockManagementPageState();
}

class _SpvStockManagementPageState extends State<SpvStockManagementPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _searchQuery = '';
  String _areaName = '-';
  List<Map<String, dynamic>> _stores = const [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final snapshotRaw = await _supabase.rpc(
        'get_spv_stock_management_snapshot',
      );
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final area = '${snapshot['area_name'] ?? '-'}'.trim();
      final enriched = _parseMapList(snapshot['stores']);

      if (!mounted) return;
      setState(() {
        _areaName = area.isEmpty ? '-' : area;
        _stores = enriched;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stores = const [];
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  List<Map<String, dynamic>> get _filteredStores {
    if (_searchQuery.isEmpty) return _stores;
    return _stores.where((row) {
      final storeName = '${row['store_name'] ?? ''}'.toLowerCase();
      return storeName.contains(_searchQuery);
    }).toList();
  }

  int get _totalStores => _stores.length;

  int get _storeWithChipCount => _stores
      .where((row) => ((row['chip_count'] ?? 0) as int) > 0)
      .length;

  int get _pendingChipCount => _stores.fold<int>(
    0,
    (sum, row) => sum + ((row['pending_chip_count'] ?? 0) as int),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.shellBackground,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                children: [
                  _buildPageHeader(),
                  const SizedBox(height: 12),
                  _buildSummaryCard(),
                  const SizedBox(height: 12),
                  _buildSearchField(),
                  const SizedBox(height: 12),
                  if (_filteredStores.isEmpty)
                    _buildEmptyState()
                  else
                    ..._filteredStores.map(_buildStoreCard),
                ],
              ),
            ),
    );
  }

  Widget _buildPageHeader() {
    return Row(
      children: [
        InkWell(
          onTap: () => context.pop(),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.surface3),
            ),
            child: Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: t.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'SPV • MONITOR STOK TOKO',
                style: TextStyle(
                  fontSize: AppTypeScale.caption,
                  fontWeight: FontWeight.w800,
                  color: t.primaryAccent,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Stok Toko Area',
                style: TextStyle(
                  fontSize: AppTypeScale.title,
                  fontWeight: FontWeight.bold,
                  color: t.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Area $_areaName',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _summaryStat('Total toko', '$_totalStores', t.primaryAccent),
              const SizedBox(width: 8),
              _summaryStat('Toko dengan chip', '$_storeWithChipCount', t.warning),
              const SizedBox(width: 8),
              _summaryStat('Pending request', '$_pendingChipCount', t.success),
            ],
          ),
        ],
      ),
    );
  }

  Widget _summaryStat(String label, String value, Color tone) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tone.withValues(alpha: 0.18)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: tone,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: t.textMutedStrong,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      onChanged: (value) =>
          setState(() => _searchQuery = value.trim().toLowerCase()),
      decoration: InputDecoration(
        hintText: 'Cari toko...',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: t.surface1,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.surface3),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.surface3),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.primaryAccent, width: 1.2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _buildStoreCard(Map<String, dynamic> row) {
    return InkWell(
      onTap: () => _openStore(row),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: t.surface3),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '${row['store_name'] ?? '-'}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: t.textMuted,
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          Icon(Icons.inventory_2_outlined, size: 40, color: t.textMuted),
          const SizedBox(height: 10),
          Text(
            'Tidak ada toko sesuai filter',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _openStore(Map<String, dynamic> row) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StokTokoPage(
          storeId: row['store_id']?.toString(),
          mode: 'all',
          initialTab: 'stock',
        ),
      ),
    );
  }

}
