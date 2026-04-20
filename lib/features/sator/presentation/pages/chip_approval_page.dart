import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class ChipApprovalPage extends StatefulWidget {
  const ChipApprovalPage({super.key});

  @override
  State<ChipApprovalPage> createState() => _ChipApprovalPageState();
}

class _ChipApprovalPageState extends State<ChipApprovalPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String _filter = 'pending';
  final Set<String> _processingIds = <String>{};
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
      final snapshotRaw = await _supabase.rpc('get_sator_chip_approval_snapshot');
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final rows = _parseMapList(snapshot['requests']);

      if (!mounted) return;
      setState(() {
        _requests = rows;
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

  List<Map<String, dynamic>> get _filteredRequests {
    switch (_filter) {
      case 'history':
        return _requests
            .where((row) => '${row['status'] ?? ''}' != 'pending')
            .toList();
      default:
        return _requests
            .where((row) => '${row['status'] ?? ''}' == 'pending')
            .toList();
    }
  }

  Future<void> _reviewRequest(
    String requestId,
    String action, {
    String? rejectionNote,
  }) async {
    if (!mounted) return;
    setState(() => _processingIds.add(requestId));
    try {
      await _supabase.rpc(
        'review_chip_request',
        params: {
          'p_request_id': requestId,
          'p_action': action,
          'p_rejection_note': rejectionNote,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'approved'
                ? 'Request chip disetujui'
                : 'Request chip ditolak',
          ),
          backgroundColor: action == 'approved' ? t.success : t.danger,
        ),
      );
      setState(() => _processingIds.remove(requestId));
      await _loadRequests();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memproses request: $e'),
          backgroundColor: t.danger,
        ),
      );
      setState(() => _processingIds.remove(requestId));
    }
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  Future<void> _showRejectDialog(String requestId) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tolak Request Chip'),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Masukkan alasan penolakan',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Tolak'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _reviewRequest(
      requestId,
      'rejected',
      rejectionNote: controller.text.trim().isEmpty
          ? null
          : controller.text.trim(),
    );
  }

  int _countByStatus(String status) {
    return _requests.where((row) => '${row['status'] ?? ''}' == status).length;
  }

  Widget _summaryStat(String label, String value, Color tone) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tone.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip({
    required String value,
    required String label,
    required int count,
    required Color tone,
  }) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text('$label $count'),
      selected: selected,
      onSelected: (_) => setState(() => _filter = value),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: selected ? tone : t.textMutedStrong,
      ),
      backgroundColor: t.surface1,
      selectedColor: tone.withValues(alpha: 0.12),
      side: BorderSide(
        color: selected ? tone.withValues(alpha: 0.28) : t.surface3,
      ),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: t.textMutedStrong,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCount = _countByStatus('pending');
    final approvedCount = _countByStatus('approved');
    final rejectedCount = _countByStatus('rejected');
    final historyCount = _requests.length - pendingCount;

    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: const Text('Persetujuan Chip')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRequests,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Row(
                    children: [
                      _summaryStat('Pending', '$pendingCount', t.primaryAccent),
                      const SizedBox(width: 8),
                      _summaryStat('Approve', '$approvedCount', t.success),
                      const SizedBox(width: 8),
                      _summaryStat('Reject', '$rejectedCount', t.danger),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterChip(
                        value: 'pending',
                        label: 'Pending',
                        count: pendingCount,
                        tone: t.primaryAccent,
                      ),
                      _filterChip(
                        value: 'history',
                        label: 'Riwayat',
                        count: historyCount,
                        tone: t.textPrimary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_filteredRequests.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Text(
                        _filter == 'pending'
                            ? 'Belum ada request pending.'
                            : 'Belum ada riwayat request.',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: t.textMuted,
                        ),
                      ),
                    )
                  else
                    ..._filteredRequests.map(_buildRequestCard),
                ],
              ),
            ),
    );
  }

  Widget _buildRequestCard(Map<String, dynamic> item) {
    final requestId = '${item['id'] ?? ''}';
    final isPending = '${item['status'] ?? ''}' == 'pending';
    final isProcessing = _processingIds.contains(requestId);
    final requestType = '${item['request_type'] ?? 'fresh_to_chip'}';
    final requestedAt = item['requested_at'] == null
        ? '-'
        : DateFormat(
            'dd MMM yyyy, HH:mm',
            'id_ID',
          ).format(DateTime.parse('${item['requested_at']}').toLocal());

    final typeLabel = requestType == 'sold_to_chip'
        ? 'Barang terjual -> chip'
        : 'Stok aktif -> chip';
    final productName = [
      '${item['product_name'] ?? 'Produk'}'.trim(),
      '${item['network_type'] ?? ''}'.trim(),
      '${item['variant'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).join(' • ');
    final storeName = '${item['store_name'] ?? 'Toko'}';
    final promotorName = '${item['promotor_name'] ?? 'Promotor'}';
    final note = '${item['rejection_note'] ?? ''}'.trim();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  productName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _statusPill('${item['status'] ?? '-'}'),
            ],
          ),
          const SizedBox(height: 8),
          _detailLine('IMEI', '${item['imei'] ?? '-'}'),
          _detailLine('Toko', storeName),
          _detailLine('Promotor', promotorName),
          _detailLine('Jalur', typeLabel),
          _detailLine('Alasan', '${item['reason'] ?? '-'}'),
          _detailLine('Waktu', requestedAt),
          if (!isPending && note.isNotEmpty) _detailLine('Catatan', note),
          if (isPending) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: isProcessing
                        ? null
                        : () => _showRejectDialog(requestId),
                    child: Text(isProcessing ? 'Proses...' : 'Tolak'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: isProcessing
                        ? null
                        : () => _reviewRequest(requestId, 'approved'),
                    child: Text(isProcessing ? 'Proses...' : 'Setujui'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusPill(String status) {
    final normalized = status.toLowerCase();
    final tone = switch (normalized) {
      'approved' => t.success,
      'rejected' => t.danger,
      _ => t.primaryAccent,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: tone,
        ),
      ),
    );
  }
}
