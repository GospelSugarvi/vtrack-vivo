import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../promotor/presentation/pages/stok_toko_page.dart';

class ListTokoPage extends StatefulWidget {
  const ListTokoPage({super.key});

  @override
  State<ListTokoPage> createState() => _ListTokoPageState();
}

class _ListTokoPageState extends State<ListTokoPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _stores = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final data = await _supabase.rpc(
        'get_store_stock_status',
        params: {'p_sator_id': userId},
      );
      if (mounted) {
        final stores = List<Map<String, dynamic>>.from(data ?? []);
        setState(() {
          _stores = stores;
          _stores.sort((a, b) {
            final groupCompare = _compareText(a['group_name'], b['group_name']);
            if (groupCompare != 0) return groupCompare;
            final emptyCompare =
                _toInt(b['empty_count']).compareTo(_toInt(a['empty_count']));
            if (emptyCompare != 0) return emptyCompare;
            return _compareText(a['store_name'], b['store_name']);
          });
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int _compareText(dynamic a, dynamic b) {
    return '${a ?? ''}'.toLowerCase().compareTo('${b ?? ''}'.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('List Toko'),
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
        surfaceTintColor: t.background,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: Column(
                children: [
                  _buildToolbar(),
                  Expanded(
                    child: _filteredStores.isEmpty
                        ? const Center(
                            child: Text('Tidak ada toko sesuai filter'),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                            itemCount: _filteredStores.length,
                            itemBuilder: (context, index) =>
                                _buildStoreRow(_filteredStores[index]),
                            separatorBuilder: (_, index) =>
                                const SizedBox(height: 6),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildToolbar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: t.surface1,
        border: Border(bottom: BorderSide(color: t.surface3)),
      ),
      child: Column(
        children: [
          TextField(
            onChanged: (v) =>
                setState(() => _searchQuery = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Cari nama toko...',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              filled: true,
              fillColor: t.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.primaryAccent, width: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> get _filteredStores {
    var list = _stores;

    if (_searchQuery.isNotEmpty) {
      list = list
          .where(
            (s) => [
              '${s['store_name'] ?? ''}',
              '${s['group_name'] ?? ''}',
              '${s['area'] ?? ''}',
            ].join(' ').toLowerCase().contains(_searchQuery),
          )
          .toList();
    }

    return list;
  }

  Widget _buildStoreRow(Map<String, dynamic> store) {
    return InkWell(
      onTap: () => _openStockSummary(store),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.surface3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    (store['store_name'] ?? '-').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: t.primaryAccentSoft.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Text(
                    'Kosong ${_toInt(store['empty_count'])}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: t.primaryAccent,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  color: t.textMuted,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMetaChip(
                  Icons.layers_outlined,
                  ('${store['group_name'] ?? ''}').trim().isEmpty
                      ? 'Tanpa grup'
                      : '${store['group_name']}',
                ),
                if ('${store['area'] ?? ''}'.trim().isNotEmpty)
                  _buildMetaChip(Icons.place_outlined, '${store['area']}'),
                _buildMetaChip(
                  Icons.warning_amber_rounded,
                  'Kurang ${_toInt(store['low_count'])}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetaChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: t.textMutedStrong),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: t.textMutedStrong,
            ),
          ),
        ],
      ),
    );
  }

  void _openStockSummary(Map<String, dynamic> store) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StokTokoPage(
          storeId: store['store_id'],
          mode: 'all',
          initialTab: 'stock',
          enableRecommendationAction: true,
        ),
      ),
    );
  }
}
