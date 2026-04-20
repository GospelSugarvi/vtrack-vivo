import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';


class SpvChipMonitorPage extends StatefulWidget {
  const SpvChipMonitorPage({super.key});

  @override
  State<SpvChipMonitorPage> createState() => _SpvChipMonitorPageState();
}

class _SpvChipMonitorPageState extends State<SpvChipMonitorPage> {
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
      final snapshotRaw = await Supabase.instance.client.rpc(
        'get_spv_chip_monitor_snapshot',
      );
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final rows = _parseMapList(snapshot['rows']);

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

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Chip Monitor')),
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
                    subtitle: Text('${_rows.length} data'),
                  ),
                ),
                const SizedBox(height: 12),
                ..._rows.map(
                  (row) => Card(
                    child: ListTile(
                      title: Text('${row['promotor_name'] ?? '-'}'),
                      subtitle: Text('${row['store_name'] ?? '-'}'),
                      trailing: Text('${row['status'] ?? '-'}'),
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
