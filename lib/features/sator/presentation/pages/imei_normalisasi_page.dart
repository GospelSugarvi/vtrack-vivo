import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ImeiNormalisasiPage extends StatefulWidget {
  const ImeiNormalisasiPage({super.key});

  @override
  State<ImeiNormalisasiPage> createState() => _ImeiNormalisasiPageState();
}

class _ImeiNormalisasiPageState extends State<ImeiNormalisasiPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _items = const [];
  final Set<String> _selectedPendingIds = <String>{};

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

      final rows = await _supabase.rpc(
        'get_sator_imei_list',
        params: {'p_sator_id': userId},
      );

      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows ?? const []);
        _selectedPendingIds.removeWhere(
          (id) => !_items.any((item) => '${item['id']}' == id),
        );
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _itemsForStatuses(Set<String> statuses) {
    return _items.where((item) => statuses.contains('${item['status'] ?? ''}')).toList();
  }

  bool get _canDismissPage {
    return _itemsForStatuses({'reported', 'processing', 'sent', 'pending'}).isEmpty;
  }

  Future<void> _markSelectedAsReady() async {
    final userId = _supabase.auth.currentUser?.id;
    if (_selectedPendingIds.isEmpty || userId == null || _isSubmitting) return;

    if (!mounted) return;
    setState(() => _isSubmitting = true);
    try {
      for (final id in _selectedPendingIds) {
        await _supabase.rpc(
          'mark_imei_normalized',
          params: {
            'p_normalization_id': id,
            'p_sator_id': userId,
            'p_notes': 'Selesai diproses dan siap scan',
          },
        );
      }
      final processed = _selectedPendingIds.length;
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$processed IMEI ditandai siap scan'),
          backgroundColor: t.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal update IMEI: $e'),
          backgroundColor: t.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _copySelectedPendingImeis() async {
    final items = _items
        .where((item) => _selectedPendingIds.contains('${item['id']}'))
        .toList();
    final text = items.map((item) => '${item['imei'] ?? ''}'.trim()).where((v) => v.isNotEmpty).join('\n');
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${items.length} IMEI disalin'),
        backgroundColor: t.info,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'reported':
        return t.warning;
      case 'processing':
        return t.info;
      case 'ready_to_scan':
        return t.success;
      case 'scanned':
        return t.textMutedStrong;
      default:
        return t.textMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'reported':
        return 'Dikirim';
      case 'processing':
        return 'Diproses';
      case 'ready_to_scan':
        return 'Siap Scan';
      case 'scanned':
        return 'Selesai';
      default:
        return status;
    }
  }

  Widget _buildStatusBadge(String status) {
    final tone = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: tone,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemList(List<Map<String, dynamic>> items, {required bool selectable}) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.surface3),
        ),
        child: Text(
          'Belum ada data.',
          style: TextStyle(
            color: t.textMuted,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
      children: items.asMap().entries.map((entry) {
        final item = entry.value;
        final isLast = entry.key == items.length - 1;
        final status = '${item['status'] ?? '-'}';
        final subtitle = [
          '${item['promotor_name'] ?? '-'}',
          '${item['store_name'] ?? '-'}',
        ].where((part) => part.trim().isNotEmpty).join(' • ');
        final selected = _selectedPendingIds.contains('${item['id']}');

        final rowContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    '${item['product_name'] ?? '-'}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'IMEI ${item['imei'] ?? '-'}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: t.textMuted,
              ),
            ),
          ],
        );

        return Container(
          decoration: BoxDecoration(
            color: selectable && selected
                ? t.primaryAccentSoft.withValues(alpha: 0.4)
                : Colors.transparent,
            border: Border(
              bottom: isLast ? BorderSide.none : BorderSide(color: t.surface3),
            ),
          ),
          child: selectable
              ? CheckboxListTile(
                  value: selected,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  controlAffinity: ListTileControlAffinity.leading,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  checkboxShape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        _selectedPendingIds.add('${item['id']}');
                      } else {
                        _selectedPendingIds.remove('${item['id']}');
                      }
                    });
                  },
                  title: rowContent,
                )
              : ListTile(
                  dense: true,
                  visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  title: rowContent,
                ),
        );
      }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingItems = _itemsForStatuses({'reported', 'processing', 'sent', 'pending'});
    final readyItems = _itemsForStatuses({'ready_to_scan', 'normalized', 'normal'});
    final scannedItems = _itemsForStatuses({'scanned'});

    return Scaffold(
      appBar: AppBar(
        title: const Text('IMEI Normalisasi'),
        actions: [
          if (_canDismissPage)
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Tutup'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: t.surface3),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: t.primaryAccentSoft,
                          child: Icon(Icons.qr_code_2, color: t.primaryAccent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Monitoring IMEI',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: t.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                pendingItems.isEmpty
                                    ? 'Semua IMEI sudah normal'
                                    : 'Pending ${pendingItems.length} • Siap scan ${readyItems.length} • Selesai ${scannedItems.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pendingItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    if (_selectedPendingIds.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: t.surface3),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _copySelectedPendingImeis,
                                child: const Text('Copy IMEI'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _isSubmitting ? null : _markSelectedAsReady,
                                child: const Text('Siap Scan'),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: t.surface3),
                      ),
                      child: const Text('Belum ada data normalisasi IMEI.'),
                    )
                  else
                    ...[
                      _buildSectionTitle(
                        'Perlu Diproses',
                      ),
                      _buildItemList(pendingItems, selectable: true),
                      const SizedBox(height: 12),
                      _buildSectionTitle(
                        'Siap Scan',
                      ),
                      _buildItemList(readyItems, selectable: false),
                      const SizedBox(height: 12),
                      _buildSectionTitle(
                        'Selesai',
                      ),
                      _buildItemList(scannedItems, selectable: false),
                    ],
                ],
              ),
            ),
    );
  }
}
