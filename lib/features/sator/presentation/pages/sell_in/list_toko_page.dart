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
        setState(() {
          _stores = List<Map<String, dynamic>>.from(data ?? []);
          _stores.sort(
            (a, b) => (b['empty_count'] ?? 0).compareTo(a['empty_count'] ?? 0),
          );
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
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
            (s) => (s['store_name'] ?? '').toString().toLowerCase().contains(
              _searchQuery,
            ),
          )
          .toList();
    }

    return list;
  }

  Widget _buildStoreRow(Map<String, dynamic> store) {
    return InkWell(
      onTap: () => _openStock(store),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: t.surface3)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
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
          ],
        ),
      ),
    );
  }

  void _openStock(Map<String, dynamic> store) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StokTokoPage(
          storeId: store['store_id'],
          enableRecommendationAction: true,
        ),
      ),
    );
  }
}
