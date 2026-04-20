import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../ui/promotor/promotor.dart';

class ScheduleDetailPage extends StatefulWidget {
  final String promotorId;
  final String promotorName;
  final String storeName;
  final String monthYear;
  final String status;

  const ScheduleDetailPage({
    super.key,
    required this.promotorId,
    required this.promotorName,
    required this.storeName,
    required this.monthYear,
    required this.status,
  });

  @override
  State<ScheduleDetailPage> createState() => _ScheduleDetailPageState();
}

class _ScheduleDetailPageState extends State<ScheduleDetailPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _commentController = TextEditingController();

  List<Map<String, dynamic>> _schedules = const [];
  List<Map<String, dynamic>> _comments = const [];
  bool _isLoading = true;
  bool _isSendingComment = false;
  bool _isReviewing = false;
  String? _errorMessage;
  String? _rejectionReason;
  String _currentUserRole = '';
  String _currentStatus = '';

  @override
  void initState() {
    super.initState();
    _currentStatus = widget.status;
    _loadPageData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadPageData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('Session user tidak ditemukan.');
      }

      final monthDate = DateTime.parse('${widget.monthYear}-01');
      final monthStart = DateTime(monthDate.year, monthDate.month, 1);
      final nextMonth = DateTime(monthDate.year, monthDate.month + 1, 1);

      final results = await Future.wait([
        _supabase.from('users').select('role').eq('id', currentUserId).single(),
        _supabase
            .from('schedules')
            .select(
              'schedule_date, shift_type, status, rejection_reason, '
              'break_start, break_end, peak_start, peak_end, shift_start, shift_end, month_year',
            )
            .eq('promotor_id', widget.promotorId)
            .eq('month_year', widget.monthYear)
            .order('schedule_date'),
        _supabase
            .from('schedule_review_comments')
            .select(
              'id, author_id, author_name, author_role, message, created_at, month_year',
            )
            .eq('promotor_id', widget.promotorId)
            .eq('month_year', widget.monthYear)
            .order('created_at'),
      ]);

      final currentUser = Map<String, dynamic>.from(
        (results[0] as Map?) ?? const <String, dynamic>{},
      );
      final schedules = List<Map<String, dynamic>>.from(results[1] as List)
          .where((row) {
            final rowMonthYear = '${row['month_year'] ?? ''}'.trim();
            final rowDate = DateTime.tryParse('${row['schedule_date'] ?? ''}');
            if (rowMonthYear == widget.monthYear) return true;
            if (rowDate == null) return false;
            return !rowDate.isBefore(monthStart) && rowDate.isBefore(nextMonth);
          })
          .toList();
      final comments = List<Map<String, dynamic>>.from(results[2] as List)
          .where((row) {
            final monthYear = '${row['month_year'] ?? ''}'.trim();
            return monthYear == widget.monthYear;
          })
          .toList();

      _currentUserRole = '${currentUser['role'] ?? ''}';
      _schedules = schedules;
      _comments = comments;
      if (_schedules.isNotEmpty) {
        _rejectionReason = _schedules.first['rejection_reason']?.toString();
        _currentStatus = '${_schedules.first['status'] ?? _currentStatus}';
      }
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Detail jadwal gagal dimuat. ${_humanizeError(e)}';
      });
    }
  }

  Future<void> _sendComment() async {
    final message = _commentController.text.trim();
    if (message.isEmpty) return;

    setState(() => _isSendingComment = true);
    try {
      final result = await _supabase.rpc(
        'add_schedule_review_comment',
        params: {
          'p_promotor_id': widget.promotorId,
          'p_month_year': widget.monthYear,
          'p_message': message,
        },
      );
      final payload = Map<String, dynamic>.from(
        (result as Map?) ?? const <String, dynamic>{},
      );
      if (payload['success'] != true) {
        throw Exception('${payload['message'] ?? 'Gagal kirim komentar.'}');
      }

      _commentController.clear();
      await _loadPageData();
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showNotice('Gagal kirim komentar. ${_humanizeError(e)}', isError: true);
    } finally {
      if (mounted) setState(() => _isSendingComment = false);
    }
  }

  Future<String?> _promptRejectReason() async {
    return showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Alasan Penolakan'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(
              hintText: 'Contoh: distribusi shift belum seimbang',
            ),
            maxLines: 4,
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Tolak'),
            ),
          ],
        );
      },
    );
  }

  Future<bool> _confirmApprove() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Konfirmasi Approval'),
            content: Text(
              'Approve jadwal ${widget.promotorName} untuk bulan ${widget.monthYear}?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Approve'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _reviewSchedule(String action) async {
    String? reason;
    if (action == 'reject') {
      reason = await _promptRejectReason();
      if (reason == null || reason.trim().isEmpty) return;
    } else {
      final confirmed = await _confirmApprove();
      if (!confirmed) return;
    }

    setState(() => _isReviewing = true);
    try {
      final result = await _supabase.rpc(
        'review_monthly_schedule_with_comment',
        params: {
          'p_promotor_id': widget.promotorId,
          'p_month_year': widget.monthYear,
          'p_action': action,
          'p_rejection_reason': reason,
        },
      );
      final payload = Map<String, dynamic>.from(
        (result as Map?) ?? const <String, dynamic>{},
      );
      final success = payload['success'] == true;
      final message = '${payload['message'] ?? 'Proses review selesai.'}';

      if (!success) {
        _showNotice(message, isError: true);
        if (mounted) setState(() => _isReviewing = false);
        return;
      }

      await _loadPageData();
      if (!mounted) return;
      _showNotice(message);
      context.pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isReviewing = false);
      _showNotice('Review gagal. ${_humanizeError(e)}', isError: true);
    }
  }

  void _showNotice(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? t.danger : t.success,
      ),
    );
  }

  String _humanizeError(Object error) {
    return error.toString().replaceFirst('Exception: ', '').trim();
  }

  Color _shiftColor(String shiftType) {
    switch (shiftType.toLowerCase()) {
      case 'pagi':
        return t.warning;
      case 'siang':
        return t.info;
      case 'fullday':
        return t.primaryAccent;
      case 'malam':
        return Color.lerp(t.info, t.primaryAccentLight, 0.55)!;
      case 'libur':
        return t.textMuted;
      default:
        return t.textMuted;
    }
  }

  String _shiftShortLabel(String shiftType) {
    switch (shiftType.toLowerCase()) {
      case 'pagi':
        return 'Pagi';
      case 'siang':
        return 'Siang';
      case 'fullday':
        return 'Full';
      case 'malam':
        return 'Malam';
      case 'libur':
        return 'Libur';
      default:
        return '-';
    }
  }

  String _shiftTimeText(Map<String, dynamic> row) {
    final shiftType = '${row['shift_type'] ?? ''}'.toLowerCase();
    if (shiftType == 'libur') return '-';
    final start = '${row['shift_start'] ?? ''}'.trim();
    final end = '${row['shift_end'] ?? ''}'.trim();
    if (start.isNotEmpty && end.isNotEmpty) {
      return '${start.substring(0, 5)}-${end.substring(0, 5)}';
    }
    return '-';
  }

  String _breakTimeText(Map<String, dynamic> row) {
    final shiftType = '${row['shift_type'] ?? ''}'.toLowerCase();
    if (shiftType == 'libur') return '-';
    final start = '${row['break_start'] ?? ''}'.trim();
    final end = '${row['break_end'] ?? ''}'.trim();
    if (start.isNotEmpty && end.isNotEmpty) {
      return '${start.substring(0, 5)}-${end.substring(0, 5)}';
    }
    return '-';
  }

  String _peakTimeText(Map<String, dynamic> row) {
    final start = '${row['peak_start'] ?? ''}'.trim();
    final end = '${row['peak_end'] ?? ''}'.trim();
    if (start.isNotEmpty && end.isNotEmpty) {
      return '${start.substring(0, 5)}-${end.substring(0, 5)}';
    }
    return '-';
  }

  bool get _canReview =>
      _currentUserRole == 'sator' && _currentStatus == 'submitted';

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;

    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
            : Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      color: t.primaryAccent,
                      backgroundColor: t.surface1,
                      onRefresh: _loadPageData,
                      child: CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(
                                18,
                                18,
                                18,
                                12,
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildTopBar(context),
                                  const SizedBox(height: 12),
                                  if (_errorMessage != null)
                                    _buildErrorCard()
                                  else ...[
                                    _buildHeaderCard(),
                                    const SizedBox(height: 12),
                                    _buildCalendarSection(),
                                    const SizedBox(height: 12),
                                    _buildCommentsSection(),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_errorMessage == null && _canReview) _buildActionBar(),
                ],
              ),
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final t = context.fieldTokens;
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.pop(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.surface3),
            ),
            child: Icon(Icons.arrow_back_rounded, color: t.textPrimary),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.promotorName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PromotorText.outfit(
                  size: 18,
                  weight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                widget.storeName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _buildTonePill(
          DateFormat(
            'MMMM yyyy',
            'id_ID',
          ).format(DateTime.parse('${widget.monthYear}-01')),
          t.primaryAccent,
        ),
      ],
    );
  }

  Widget _buildHeaderCard() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: t.surface1,
        border: Border.all(color: t.surface3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTonePill(
              _statusLabel(_currentStatus),
              _statusTone(_currentStatus),
            ),
            if (_rejectionReason != null &&
                _rejectionReason!.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.danger.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.danger.withValues(alpha: 0.24)),
                ),
                child: Text(
                  'Alasan terakhir: $_rejectionReason',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w600,
                    color: t.textSecondary,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _statusTone(String status) {
    switch (status) {
      case 'submitted':
        return t.warning;
      case 'approved':
        return t.success;
      case 'rejected':
        return t.danger;
      case 'draft':
        return t.info;
      default:
        return t.textMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'submitted':
        return 'Pending Review';
      case 'approved':
        return 'Approved';
      case 'rejected':
        return 'Rejected';
      case 'draft':
        return 'Draft';
      default:
        return 'Belum Kirim';
    }
  }

  Widget _buildTonePill(String label, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.24)),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 13,
          weight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }

  Widget _buildCalendarSection() {
    final rows = List<Map<String, dynamic>>.from(_schedules)
      ..sort(
        (a, b) => '${a['schedule_date']}'.compareTo('${b['schedule_date']}'),
      );
    final workingDays = rows
        .where((row) => '${row['shift_type'] ?? ''}'.toLowerCase() != 'libur')
        .length;
    final offDays = rows.length - workingDays;
    const dateColumnWidth = 124.0;
    const shiftColumnWidth = 78.0;
    const shiftTimeColumnWidth = 88.0;
    const breakColumnWidth = 88.0;
    const peakColumnWidth = 88.0;

    Widget buildCell(
      String text, {
      required double width,
      bool header = false,
      Color? color,
    }) {
      return Container(
        width: width,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            right: BorderSide(color: t.surface3),
            bottom: BorderSide(color: t.surface3),
          ),
          color: header ? t.surface2 : null,
        ),
        child: Text(
          text,
          style: PromotorText.outfit(
            size: 12,
            weight: header ? FontWeight.w800 : FontWeight.w700,
            color: color ?? (header ? t.textPrimary : t.textSecondary),
          ),
        ),
      );
    }

    return PromotorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Preview Jadwal',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              Text(
                '${rows.length} hari',
                style: PromotorText.outfit(
                  size: 12,
                  weight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            Text(
              'Belum ada jadwal untuk bulan ini.',
              style: PromotorText.outfit(
                size: 15,
                weight: FontWeight.w600,
                color: t.textSecondary,
              ),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.surface3),
              ),
              clipBehavior: Clip.antiAlias,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        buildCell(
                          'Tanggal',
                          width: dateColumnWidth,
                          header: true,
                        ),
                        buildCell(
                          'Shift',
                          width: shiftColumnWidth,
                          header: true,
                        ),
                        buildCell(
                          'Jam Shift',
                          width: shiftTimeColumnWidth,
                          header: true,
                        ),
                        buildCell(
                          'Jam Break',
                          width: breakColumnWidth,
                          header: true,
                        ),
                        buildCell(
                          'Jam Ramai',
                          width: peakColumnWidth,
                          header: true,
                        ),
                      ],
                    ),
                    ...rows.map((row) {
                      final date = DateTime.tryParse('${row['schedule_date']}');
                      final shift = '${row['shift_type'] ?? ''}';
                      final tone = _shiftColor(shift);
                      return Row(
                        children: [
                          buildCell(
                            date == null
                                ? '-'
                                : DateFormat(
                                    'dd MMM, EEE',
                                    'id_ID',
                                  ).format(date),
                            width: dateColumnWidth,
                            color: t.textPrimary,
                          ),
                          buildCell(
                            _shiftShortLabel(shift),
                            width: shiftColumnWidth,
                            color: tone,
                          ),
                          buildCell(
                            _shiftTimeText(row),
                            width: shiftTimeColumnWidth,
                            color: t.textPrimary,
                          ),
                          buildCell(
                            _breakTimeText(row),
                            width: breakColumnWidth,
                            color: t.textPrimary,
                          ),
                          buildCell(
                            _peakTimeText(row),
                            width: peakColumnWidth,
                            color: t.textPrimary,
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  '$workingDays',
                  'hari kerja',
                  t.info,
                  compact: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatItem(
                  '$offDays',
                  'libur',
                  t.textMuted,
                  compact: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
    String value,
    String label,
    Color tone, {
    bool compact = false,
  }) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 10 : 12,
        vertical: compact ? 9 : 10,
      ),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            value,
            style: PromotorText.outfit(
              size: compact ? 15 : 18,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PromotorText.outfit(
                size: compact ? 10.5 : 12,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentsSection() {
    return PromotorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Komentar',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (_comments.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._comments.map(_buildCommentBubble),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            minLines: 1,
            maxLines: 3,
            cursorColor: t.primaryAccent,
            style: PromotorText.outfit(
              size: 14,
              weight: FontWeight.w600,
              color: t.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Tulis komentar',
              hintStyle: PromotorText.outfit(
                size: 14,
                weight: FontWeight.w700,
                color: t.textMuted,
              ),
              filled: true,
              fillColor: t.surface2,
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
                borderSide: BorderSide(color: t.primaryAccent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: t.primaryAccent,
                foregroundColor: t.textOnAccent,
              ),
              onPressed: _isSendingComment ? null : _sendComment,
              icon: _isSendingComment
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, size: 16),
              label: Text(
                'Kirim',
                style: PromotorText.outfit(
                  size: 14,
                  weight: FontWeight.w800,
                  color: t.textOnAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentBubble(Map<String, dynamic> comment) {
    final author = '${comment['author_name'] ?? 'User'}';
    final createdAt = DateTime.tryParse('${comment['created_at'] ?? ''}');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(12),
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
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 14,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              if (createdAt != null) ...[
                const SizedBox(width: 8),
                Text(
                  DateFormat('dd MMM HH:mm', 'id_ID').format(createdAt),
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w600,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${comment['message'] ?? ''}',
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
      decoration: BoxDecoration(
        color: t.textOnAccent,
        border: Border(
          top: BorderSide(color: t.surface3.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: t.danger,
                side: BorderSide(color: t.danger),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isReviewing ? null : () => _reviewSchedule('reject'),
              icon: const Icon(Icons.close_rounded),
              label: const Text('Tolak'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: t.success,
                foregroundColor: t.textOnAccent,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: _isReviewing ? null : () => _reviewSchedule('approve'),
              icon: _isReviewing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_rounded),
              label: const Text('Approve'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard() {
    return PromotorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PromotorSectionLabel('Gagal Memuat'),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'Terjadi kesalahan.',
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.primaryAccent,
                foregroundColor: t.textOnAccent,
              ),
              onPressed: _loadPageData,
              child: Text(
                'Coba Lagi',
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w800,
                  color: t.textOnAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
