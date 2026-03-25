import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class ChipApprovalPage extends StatefulWidget {
  const ChipApprovalPage({super.key});

  @override
  State<ChipApprovalPage> createState() => _ChipApprovalPageState();
}

class _ChipApprovalPageState extends State<ChipApprovalPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _requests = const [];

  @override
  void initState() {
    super.initState();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Sesi login tidak ditemukan');
      final rows = await _supabase
          .from('stock_chip_requests')
          .select('id, reason, status, requested_at, promotor:promotor_id(full_name), stores(store_name)')
          .eq('sator_id', userId)
          .order('requested_at', ascending: false)
          .limit(100);

      if (!mounted) return;
      setState(() {
        _requests = List<Map<String, dynamic>>.from(rows);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _requests = const [];
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Persetujuan Chip')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: t.primaryAccent,
                      foregroundColor: t.textOnAccent,
                      child: Icon(Icons.sim_card_outlined),
                    ),
                    title: const Text('Permintaan Chip'),
                    subtitle: Text('${_requests.length} data'),
                  ),
                ),
                const SizedBox(height: 12),
                ..._requests.map(
                  (item) => Card(
                    child: ListTile(
                      title: Text('${item['promotor']?['full_name'] ?? 'Promotor'}'),
                      subtitle: Text('${item['stores']?['store_name'] ?? 'Toko'} • ${item['reason'] ?? '-'}'),
                      trailing: Text('${item['status'] ?? '-'}'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
