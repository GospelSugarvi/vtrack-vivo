import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../ui/promotor/promotor.dart';

class SpvPermissionApprovalPage extends StatefulWidget {
  const SpvPermissionApprovalPage({super.key});

  @override
  State<SpvPermissionApprovalPage> createState() =>
      _SpvPermissionApprovalPageState();
}

class _SpvPermissionApprovalPageState extends State<SpvPermissionApprovalPage> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  String _tab = 'pending';
  List<Map<String, dynamic>> _rows = <Map<String, dynamic>>[];

  FieldThemeTokens get t => context.fieldTokens;

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
        'get_spv_permission_approval_snapshot',
      );
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final rows = _parseMapList(snapshot['requests']);
      if (!mounted) return;
      setState(() {
        _rows = rows;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading spv permission approvals: $e');
      if (!mounted) return;
      setState(() {
        _rows = <Map<String, dynamic>>[];
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

  Future<void> _processRequest(String requestId, String action) async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: t.surface1,
          title: Text(
            action == 'approve' ? 'Approve Final SPV' : 'Tolak Final SPV',
            style: PromotorText.display(size: 18, color: t.textPrimary),
          ),
          content: TextField(
            controller: controller,
            maxLines: 3,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Catatan untuk promotor',
              hintStyle: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: t.textMuted,
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(
                'Batal',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w800,
                  color: t.textMuted,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(action == 'approve' ? 'Approve' : 'Tolak'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      controller.dispose();
      return;
    }

    try {
      final result = await _supabase.rpc(
        'process_permission_request_by_spv',
        params: {
          'p_request_id': requestId,
          'p_action': action,
          'p_comment': controller.text.trim(),
        },
      );
      controller.dispose();
      final payload = result is Map<String, dynamic>
          ? result
          : Map<String, dynamic>.from(result as Map);
      if (payload['success'] != true) {
        throw Exception('${payload['message'] ?? 'Gagal memproses izin.'}');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${payload['message']}')));
      await _loadData();
    } catch (e) {
      controller.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memproses izin: $e')));
    }
  }

  List<Map<String, dynamic>> get _filteredRows {
    if (_tab == 'pending') {
      return _rows
          .where((row) => '${row['status']}' == 'approved_sator')
          .toList();
    }
    return _rows
        .where((row) => '${row['status']}' != 'approved_sator')
        .toList();
  }

  String _typeLabel(String value) {
    switch (value) {
      case 'sick':
        return 'Sakit';
      case 'personal':
        return 'Izin Pribadi';
      case 'other':
        return 'Izin Lainnya';
      default:
        return value;
    }
  }

  String _statusLabel(String value) {
    switch (value) {
      case 'approved_sator':
        return 'Menunggu SPV';
      case 'approved_spv':
        return 'Disetujui SPV';
      case 'rejected_spv':
        return 'Ditolak SPV';
      case 'rejected_sator':
        return 'Ditolak SATOR';
      default:
        return value;
    }
  }

  Color _statusColor(String value) {
    switch (value) {
      case 'approved_spv':
        return t.success;
      case 'rejected_spv':
      case 'rejected_sator':
        return t.danger;
      default:
        return t.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        backgroundColor: t.background,
        elevation: 0,
        title: Text(
          'Approval Perijinan SPV',
          style: PromotorText.display(size: 18, color: t.textPrimary),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        color: t.primaryAccent,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            _buildTabs(),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 32),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_filteredRows.isEmpty)
              _buildEmpty()
            else
              ..._filteredRows.map(_buildCard),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs() {
    final tabs = [('pending', 'Pending'), ('history', 'Riwayat')];
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: tabs.map((item) {
          final selected = _tab == item.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = item.$1),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? t.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  item.$2,
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: selected ? t.textOnAccent : t.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmpty() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        _tab == 'pending'
            ? 'Belum ada izin yang menunggu final approval SPV.'
            : 'Belum ada riwayat final approval perijinan.',
        style: PromotorText.outfit(
          size: 14,
          weight: FontWeight.w700,
          color: t.textSecondary,
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> row) {
    final status = '${row['status'] ?? ''}';
    final statusColor = _statusColor(status);
    final photoUrl = '${row['photo_url'] ?? ''}'.trim();
    final promotorName = '${row['promotor_name'] ?? 'Promotor'}';
    final satorName = '${row['sator_name'] ?? 'SATOR'}';
    final satorDecisionText = switch (status) {
      'rejected_sator' => 'Ditolak SATOR: $satorName',
      'approved_sator' || 'approved_spv' || 'rejected_spv' =>
        'Disetujui SATOR: $satorName',
      _ => 'Review SATOR: $satorName',
    };
    final satorDecisionColor = switch (status) {
      'rejected_sator' => t.danger,
      'approved_sator' || 'approved_spv' || 'rejected_spv' => t.info,
      _ => t.textMuted,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  promotorName,
                  style: PromotorText.display(size: 15, color: t.textPrimary),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _statusLabel(status),
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${_typeLabel('${row['request_type'] ?? ''}')} • ${DateFormat('dd MMM yyyy', 'id_ID').format(DateTime.parse('${row['request_date']}'))}',
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${row['reason'] ?? '-'}',
            style: PromotorText.outfit(
              size: 12.5,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            satorDecisionText,
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: satorDecisionColor,
            ),
          ),
          if ('${row['sator_comment'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Catatan SATOR: ${row['sator_comment']}',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ],
          if ('${row['note'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              '${row['note']}',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ],
          if (photoUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            InkWell(
              onTap: () => showDialog<void>(
                context: context,
                builder: (dialogContext) => Dialog(
                  backgroundColor: Colors.transparent,
                  insetPadding: const EdgeInsets.all(16),
                  child: Stack(
                    children: [
                      InteractiveViewer(
                        minScale: 0.8,
                        maxScale: 4,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.network(
                            photoUrl,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Positioned(
                        top: 8,
                        right: 8,
                        child: IconButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.black.withValues(alpha: 0.45),
                            foregroundColor: Colors.white,
                          ),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              borderRadius: BorderRadius.circular(14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.network(
                  photoUrl,
                  height: 132,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ],
          if ('${row['spv_comment'] ?? ''}'.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Catatan SPV: ${row['spv_comment']}',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ],
          if (status == 'approved_sator') ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _processRequest('${row['id']}', 'reject'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.danger,
                      side: BorderSide(color: t.danger),
                    ),
                    child: const Text('Tolak'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _processRequest('${row['id']}', 'approve'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: t.success,
                      foregroundColor: t.textOnAccent,
                    ),
                    child: const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
