import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SpvStockManagementPage extends StatefulWidget {
  const SpvStockManagementPage({super.key});

  @override
  State<SpvStockManagementPage> createState() =>
      _SpvStockManagementPageState();
}

class _SpvStockManagementPageState extends State<SpvStockManagementPage> {
  FieldThemeTokens get t => context.fieldTokens;
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
      final rows = await Supabase.instance.client
          .from('stok')
          .select('id, imei, tipe_stok, is_sold, promotor:promotor_id(full_name), stores(store_name)')
          .order('created_at', ascending: false)
          .limit(200);

      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(rows);
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
      appBar: AppBar(title: const Text('Stock Management Area')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.inventory_2_outlined)),
                    title: const Text('Stok Area'),
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
