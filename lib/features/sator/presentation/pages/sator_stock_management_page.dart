import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SatorStockManagementPage extends StatefulWidget {
  const SatorStockManagementPage({super.key});

  @override
  State<SatorStockManagementPage> createState() =>
      _SatorStockManagementPageState();
}

class _SatorStockManagementPageState extends State<SatorStockManagementPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _rows = const [];

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
      if (userId == null) throw Exception('Sesi login tidak ditemukan');
      final hierarchy = await _supabase
          .from('hierarchy_sator_promotor')
          .select('promotor_id')
          .eq('sator_id', userId)
          .eq('active', true);
      final promotorIds = List<Map<String, dynamic>>.from(hierarchy)
          .map((row) => row['promotor_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      final rows = promotorIds.isEmpty
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _supabase
                  .from('stok')
                  .select('id, imei, tipe_stok, is_sold, promotor:promotor_id(full_name), stores(store_name)')
                  .inFilter('promotor_id', promotorIds)
                  .order('created_at', ascending: false)
                  .limit(200),
            );

      if (!mounted) return;
      setState(() {
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

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: const Text('Stock Management')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                    title: const Text('Stok Tim'),
                  ),
                ),
                const SizedBox(height: 12),
                ..._rows.map(
                  (row) => Card(
                    child: ListTile(
                      title: Text('${row['imei'] ?? '-'}'),
                      trailing: Text('${row['tipe_stok'] ?? '-'}'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
