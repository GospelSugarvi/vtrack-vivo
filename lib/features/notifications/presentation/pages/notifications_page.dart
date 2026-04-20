import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isMarkingAllRead = false;
  String _filter = 'all';
  List<Map<String, dynamic>> _rows = const [];
  final Set<String> _processingIds = <String>{};

  @override
  void initState() {
    super.initState();
    _loadRows();
  }

  Future<void> _loadRows() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Sesi login tidak ditemukan');

      var query = _supabase
          .from('app_notifications')
          .select(
            'id, title, body, category, type, status, action_route, action_params, payload, created_at, read_at',
          )
          .eq('recipient_user_id', userId)
          .isFilter('archived_at', null);

      if (_filter == 'unread') {
        query = query.eq('status', 'unread');
      }

      final rows = await query.order('created_at', ascending: false).limit(100);

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

  Future<void> _markAsRead(String id) async {
    await _supabase
        .from('app_notifications')
        .update({'status': 'read', 'read_at': DateTime.now().toIso8601String()})
        .eq('id', id)
        .eq('status', 'unread');
  }

  Future<void> _markAllRead() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isMarkingAllRead = true);
    try {
      await _supabase
          .from('app_notifications')
          .update({
            'status': 'read',
            'read_at': DateTime.now().toIso8601String(),
          })
          .eq('recipient_user_id', userId)
          .eq('status', 'unread');
      await _loadRows();
    } finally {
      if (mounted) setState(() => _isMarkingAllRead = false);
    }
  }

  Future<void> _deleteNotification(Map<String, dynamic> row) async {
    final id = '${row['id'] ?? ''}'.trim();
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: t.surface1,
        title: Text(
          'Hapus notifikasi?',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
        content: Text(
          'Notifikasi ini akan dihapus dari daftar.',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: t.textMutedStrong,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: t.danger,
              foregroundColor: t.textOnAccent,
            ),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      setState(() => _processingIds.add(id));
    }
    try {
      await _supabase
          .from('app_notifications')
          .update({
            'status': 'archived',
            'archived_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
      if (!mounted) return;
      setState(() {
        _rows = _rows.where((item) => '${item['id'] ?? ''}' != id).toList();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Notifikasi dihapus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal menghapus notifikasi: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(id));
      }
    }
  }

  Future<void> _openNotification(Map<String, dynamic> row) async {
    final id = '${row['id'] ?? ''}'.trim();
    final route = '${row['action_route'] ?? ''}'.trim();
    final isUnread = '${row['status'] ?? ''}' == 'unread';
    final actionParams = row['action_params'];
    final isPermissionResult = _isPromotorPermissionResultNotification(row);
    if (id.isNotEmpty && isUnread) {
      await _markAsRead(id);
    }
    if (!mounted) return;
    if (isPermissionResult) {
      await _loadRows();
    } else if (route.isNotEmpty) {
      final extra = actionParams is Map
          ? Map<String, dynamic>.from(actionParams)
          : <String, dynamic>{};
      extra['__notification_type'] = '${row['type'] ?? ''}';
      await context.push(route, extra: extra);
      if (!mounted) return;
      await _loadRows();
    } else {
      await _loadRows();
    }
  }

  String _requestStatus(Map<String, dynamic> row) {
    final payload = row['payload'];
    if (payload is Map) {
      return '${payload['status'] ?? ''}'.trim().toLowerCase();
    }
    return '';
  }

  bool _isSatorVoidApprovalNotification(Map<String, dynamic> row) {
    final location = GoRouterState.of(context).uri.toString();
    final requestStatus = _requestStatus(row);
    return location.startsWith('/sator') &&
        '${row['type'] ?? ''}' == 'sell_out_void_requested' &&
        (requestStatus.isEmpty || requestStatus == 'pending');
  }

  bool _isSatorChipApprovalNotification(Map<String, dynamic> row) {
    final location = GoRouterState.of(context).uri.toString();
    return location.startsWith('/sator') &&
        '${row['type'] ?? ''}' == 'chip_request_submitted';
  }

  bool _isPromotorPermissionResultNotification(Map<String, dynamic> row) {
    final location = GoRouterState.of(context).uri.toString();
    if (!location.startsWith('/promotor')) return false;
    final type = '${row['type'] ?? ''}';
    return type == 'permission_request_approved_sator' ||
        type == 'permission_request_rejected_sator' ||
        type == 'permission_request_approved_spv' ||
        type == 'permission_request_rejected_spv';
  }

  String _permissionRequestTypeLabel(String value) {
    switch (value) {
      case 'sick':
        return 'Izin sakit';
      case 'personal':
        return 'Izin pribadi';
      case 'other':
        return 'Izin lainnya';
      default:
        return 'Perijinan';
    }
  }

  bool _isPermissionApprovedStatus(String value) {
    return value == 'approved_sator' || value == 'approved_spv';
  }

  Widget _buildPermissionResultCard(Map<String, dynamic> row) {
    final payload = row['payload'] is Map
        ? Map<String, dynamic>.from(row['payload'] as Map)
        : <String, dynamic>{};
    final status = '${payload['status'] ?? ''}'.trim();
    final approved = _isPermissionApprovedStatus(status);
    final tone = approved ? t.success : t.danger;
    final requestDate = payload['request_date']?.toString() ?? '';
    final requestType = _permissionRequestTypeLabel(
      '${payload['request_type'] ?? ''}'.trim(),
    );
    final reviewerNote = '${payload['spv_comment'] ?? payload['sator_comment'] ?? ''}'
        .trim();
    final resultLabel = approved ? 'Disetujui' : 'Ditolak';
    final resultSubtitle = status == 'approved_sator'
        ? 'Sudah disetujui SATOR dan diteruskan ke SPV.'
        : status == 'approved_spv'
            ? 'Sudah disetujui SPV.'
            : status == 'rejected_sator'
                ? 'Ditolak oleh SATOR.'
                : 'Ditolak oleh SPV.';

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  approved
                      ? Icons.verified_rounded
                      : Icons.cancel_rounded,
                  size: 18,
                  color: tone,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$requestType · $resultLabel',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: tone,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      resultSubtitle,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: t.textMutedStrong,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (requestDate.isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildPermissionResultMeta('Tanggal izin', requestDate),
          ],
          if (reviewerNote.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildPermissionResultMeta(
              approved ? 'Catatan approval' : 'Alasan penolakan',
              reviewerNote,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPermissionResultMeta(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: t.textMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: t.textPrimary,
          ),
        ),
      ],
    );
  }

  Future<void> _reviewVoidRequest(
    Map<String, dynamic> row,
    String action,
  ) async {
    final notificationId = '${row['id'] ?? ''}';
    final actionParams = row['action_params'];
    final requestId = actionParams is Map
        ? '${actionParams['request_id'] ?? ''}'.trim()
        : '';
    if (requestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request ID tidak ditemukan.')),
      );
      return;
    }

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: t.surface1,
          title: Text(
            action == 'approved' ? 'Approve Void' : 'Tolak Void',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: action == 'approved'
                  ? 'Catatan approval'
                  : 'Catatan penolakan',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(action == 'approved' ? 'Approve' : 'Tolak'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      controller.dispose();
      return;
    }

    if (mounted) {
      setState(() => _processingIds.add(notificationId));
    }
    try {
      await _supabase.rpc(
        'review_sell_out_void_request',
        params: {
          'p_request_id': requestId,
          'p_action': action,
          'p_review_note': controller.text.trim(),
        },
      );
      controller.dispose();
      if ('${row['status'] ?? ''}' == 'unread' && notificationId.isNotEmpty) {
        await _markAsRead(notificationId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'approved'
                ? 'Void penjualan berhasil di-approve.'
                : 'Void penjualan berhasil ditolak.',
          ),
        ),
      );
      await _loadRows();
    } on PostgrestException catch (e, stackTrace) {
      debugPrint(
        '[SatorVoidApproval][RPC] request_id=$requestId action=$action message=${e.message} code=${e.code} details=${e.details} hint=${e.hint}',
      );
      debugPrintStack(
        label: '[SatorVoidApproval][RPC][STACK]',
        stackTrace: stackTrace,
      );
      controller.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memproses void: $e')));
    } catch (e, stackTrace) {
      debugPrint(
        '[SatorVoidApproval][UI] request_id=$requestId action=$action error=$e',
      );
      debugPrintStack(
        label: '[SatorVoidApproval][UI][STACK]',
        stackTrace: stackTrace,
      );
      controller.dispose();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memproses void: $e')));
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(notificationId));
      }
    }
  }

  Future<void> _reviewChipRequest(
    Map<String, dynamic> row,
    String action,
  ) async {
    final notificationId = '${row['id'] ?? ''}';
    final actionParams = row['action_params'];
    final requestId = actionParams is Map
        ? '${actionParams['request_id'] ?? ''}'.trim()
        : '';
    if (requestId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Request chip tidak ditemukan.')),
      );
      return;
    }

    String? rejectionNote;
    if (action == 'rejected') {
      final controller = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: t.surface1,
            title: Text(
              'Tolak Request Chip',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            content: TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(hintText: 'Catatan penolakan'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Tolak'),
              ),
            ],
          );
        },
      );
      if (confirmed != true) {
        controller.dispose();
        return;
      }
      rejectionNote = controller.text.trim().isEmpty
          ? null
          : controller.text.trim();
      controller.dispose();
    }

    if (mounted) {
      setState(() => _processingIds.add(notificationId));
    }
    try {
      await _supabase.rpc(
        'review_chip_request',
        params: {
          'p_request_id': requestId,
          'p_action': action,
          'p_rejection_note': rejectionNote,
        },
      );
      if ('${row['status'] ?? ''}' == 'unread') {
        await _markAsRead(notificationId);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'approved'
                ? 'Request chip berhasil di-approve.'
                : 'Request chip berhasil ditolak.',
          ),
        ),
      );
      await _loadRows();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal memproses request chip: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(notificationId));
      }
    }
  }

  String _formatTime(dynamic value) {
    if (value == null) return '-';
    try {
      return DateFormat(
        'dd MMM yyyy, HH:mm',
        'id_ID',
      ).format(DateTime.parse('$value').toLocal());
    } catch (_) {
      return '$value';
    }
  }

  Color _categoryTone(String category) {
    switch (category) {
      case 'approval':
        return t.primaryAccent;
      case 'stock':
        return t.warning;
      case 'sales':
        return t.success;
      case 'schedule':
        return t.info;
      default:
        return t.textMutedStrong;
    }
  }

  int get _unreadCount =>
      _rows.where((row) => '${row['status'] ?? ''}' == 'unread').length;

  String _categoryLabel(String category) {
    switch (category) {
      case 'approval':
        return 'Approval';
      case 'stock':
        return 'Stok';
      case 'sales':
        return 'Penjualan';
      case 'schedule':
        return 'Jadwal';
      case 'system':
        return 'Sistem';
      default:
        return 'Semua';
    }
  }

  String _settingsRoute() {
    final location = GoRouterState.of(context).uri.toString();
    if (location.startsWith('/sator')) {
      return '/sator/notifications/settings';
    }
    if (location.startsWith('/spv')) {
      return '/spv/notifications/settings';
    }
    return '/promotor/notifications/settings';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(
        title: const Text('Notifikasi'),
        actions: [
          IconButton(
            onPressed: () => context.push(_settingsRoute()),
            icon: const Icon(Icons.tune_rounded),
            tooltip: 'Pengaturan Notifikasi',
          ),
          TextButton(
            onPressed: _isMarkingAllRead || _unreadCount == 0
                ? null
                : _markAllRead,
            child: Text(_isMarkingAllRead ? 'Proses...' : 'Tandai Dibaca'),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRows,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _filterChip('unread', 'Belum dibaca $_unreadCount'),
                      _filterChip('all', 'Semua ${_rows.length}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_rows.isEmpty) _emptyState() else ..._rows.map(_buildRow),
                ],
              ),
            ),
    );
  }

  Widget _filterChip(String value, String label) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() => _filter = value);
        _loadRows();
      },
      visualDensity: VisualDensity.compact,
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: selected ? t.primaryAccent : t.textMutedStrong,
      ),
      backgroundColor: t.surface1,
      selectedColor: t.primaryAccentSoft,
      side: BorderSide(
        color: selected ? t.primaryAccent.withValues(alpha: 0.24) : t.surface3,
      ),
    );
  }

  Widget _emptyState() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        _filter == 'unread'
            ? 'Tidak ada notifikasi yang belum dibaca.'
            : 'Belum ada notifikasi.',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: t.textMuted,
        ),
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> row) {
    final category = '${row['category'] ?? 'system'}';
    final tone = _categoryTone(category);
    final isUnread = '${row['status'] ?? ''}' == 'unread';
    final notificationId = '${row['id'] ?? ''}';
    final isProcessing = _processingIds.contains(notificationId);
    final canReviewVoid = _isSatorVoidApprovalNotification(row);
    final canReviewChip = _isSatorChipApprovalNotification(row);
    final isPermissionResult = _isPromotorPermissionResultNotification(row);
    final hasInlineActions = canReviewVoid || canReviewChip;
    final requestStatus = _requestStatus(row);
    final showProcessedBadge =
        '${row['type'] ?? ''}' == 'sell_out_void_requested' &&
        requestStatus.isNotEmpty &&
        requestStatus != 'pending';

    return Dismissible(
      key: ValueKey(notificationId),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _deleteNotification(row);
        return false;
      },
      background: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: t.danger.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.danger.withValues(alpha: 0.2)),
        ),
        alignment: Alignment.centerRight,
        child: Icon(Icons.delete_outline_rounded, color: t.danger),
      ),
      child: InkWell(
        onTap: hasInlineActions || isProcessing ? null : () => _openNotification(row),
        borderRadius: BorderRadius.circular(16),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isUnread ? tone.withValues(alpha: 0.28) : t.surface3,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: BoxDecoration(
                  color: isUnread ? tone : t.surface4,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: tone.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        _categoryLabel(category),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: tone,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${row['title'] ?? '-'}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${row['body'] ?? '-'}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: t.textMutedStrong,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _formatTime(row['created_at']),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: t.textMuted,
                      ),
                    ),
                    if (isPermissionResult) _buildPermissionResultCard(row),
                    if (showProcessedBadge) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: requestStatus == 'approved'
                              ? t.success.withValues(alpha: 0.12)
                              : t.danger.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          requestStatus == 'approved'
                              ? 'Sudah di-approve'
                              : 'Sudah ditolak',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: requestStatus == 'approved'
                                ? t.success
                                : t.danger,
                          ),
                        ),
                      ),
                    ],
                    if (canReviewVoid || canReviewChip) ...[
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isProcessing
                                  ? null
                                  : () => canReviewVoid
                                        ? _reviewVoidRequest(row, 'rejected')
                                        : _reviewChipRequest(row, 'rejected'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: t.danger,
                                side: BorderSide(color: t.danger),
                              ),
                              child: Text(isProcessing ? 'Proses...' : 'Tolak'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: isProcessing
                                  ? null
                                  : () => canReviewVoid
                                        ? _reviewVoidRequest(row, 'approved')
                                        : _reviewChipRequest(row, 'approved'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: t.success,
                                foregroundColor: t.textOnAccent,
                              ),
                              child: Text(isProcessing ? 'Proses...' : 'Approve'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              if (isProcessing)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: t.textMuted,
                  ),
                )
              else if (!hasInlineActions && !isPermissionResult)
                Icon(Icons.chevron_right_rounded, color: t.textMuted, size: 18),
              if (!hasInlineActions && !isProcessing)
                const SizedBox.shrink(),
            ],
          ),
        ),
      ),
    );
  }
}
