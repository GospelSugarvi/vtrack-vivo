import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/foundation/app_colors.dart';

class TeamStockFlowPage extends StatefulWidget {
  final String scope;

  const TeamStockFlowPage({
    super.key,
    required this.scope,
  });

  bool get isSpv => scope == 'spv';

  @override
  State<TeamStockFlowPage> createState() => _TeamStockFlowPageState();
}

class _TeamStockFlowPageState extends State<TeamStockFlowPage> {
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
      final rows = await _supabase
          .from('stock_validations')
          .select('id, validation_date, stores(store_name), validator:validator_id(full_name)')
          .order('validation_date', ascending: false)
          .limit(100);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isSpv ? 'Stock Flow SPV' : 'Stock Flow Tim'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: const CircleAvatar(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      child: Icon(Icons.swap_horiz),
                    ),
                    title: const Text('Riwayat Validasi'),
                    subtitle: Text('${_rows.length} data'),
                  ),
                ),
                const SizedBox(height: 12),
                ..._rows.map(
                  (row) => Card(
                    child: ListTile(
                      title: Text('${row['stores']?['store_name'] ?? '-'}'),
                      subtitle: Text('${row['validator']?['full_name'] ?? '-'}'),
                      trailing: Text('${row['validation_date'] ?? '-'}'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
