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
  String _currentUserName = '';
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
      await Future.wait([
        _loadCurrentUser(),
        _loadScheduleDetail(),
        _loadComments(),
      ]);
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

  Future<void> _loadCurrentUser() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _currentUserRole = '';
      _currentUserName = '';
      return;
    }

    final profile = await _supabase
        .from('users')
        .select('full_name, role')
        .eq('id', userId)
        .single();

    _currentUserName = '${profile['full_name'] ?? ''}';
    _currentUserRole = '${profile['role'] ?? ''}';
  }

  Future<void> _loadScheduleDetail() async {
    final response = await _supabase.rpc(
      'get_promotor_schedule_detail',
      params: {
        'p_promotor_id': widget.promotorId,
        'p_month_year': widget.monthYear,
      },
    );

    _schedules = List<Map<String, dynamic>>.from(response ?? const []);
    if (_schedules.isNotEmpty) {
      _rejectionReason = _schedules.first['rejection_reason']?.toString();
      _currentStatus = '${_schedules.first['status'] ?? _currentStatus}';
    }
  }

  Future<void> _loadComments() async {
    final response = await _supabase
        .from('schedule_review_comments')
        .select('id, author_id, author_name, author_role, message, created_at')
        .eq('promotor_id', widget.promotorId)
        .eq('month_year', widget.monthYear)
        .order('created_at');

    _comments = List<Map<String, dynamic>>.from(response);
  }

  Future<void> _sendComment() async {
    final message = _commentController.text.trim();
    final userId = _supabase.auth.currentUser?.id;
    if (message.isEmpty || userId == null) return;

    setState(() => _isSendingComment = true);
    try {
      await _supabase.from('schedule_review_comments').insert({
        'promotor_id': widget.promotorId,
        'month_year': widget.monthYear,
        'author_id': userId,
        'author_name': _currentUserName.isEmpty ? 'User' : _currentUserName,
        'author_role': _currentUserRole.isEmpty ? 'user' : _currentUserRole,
        'message': message,
      });

      _commentController.clear();
      await _loadComments();
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

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _showNotice(
        'Session tidak ditemukan. Silakan login ulang.',
        isError: true,
      );
      return;
    }

    setState(() => _isReviewing = true);
    try {
      final result = await _supabase.rpc(
        'review_monthly_schedule',
        params: {
          'p_sator_id': userId,
          'p_promotor_id': widget.promotorId,
          'p_month_year': widget.monthYear,
          'p_action': action,
          'p_rejection_reason': reason,
        },
      );

      final rows = List<Map<String, dynamic>>.from(result ?? const []);
      final first = rows.isNotEmpty ? rows.first : const <String, dynamic>{};
      final success = first['success'] == true;
      final message = '${first['message'] ?? 'Proses review selesai.'}';

      if (!success) {
        _showNotice(message, isError: true);
        if (mounted) setState(() => _isReviewing = false);
        return;
      }

      if (reason != null && reason.trim().isNotEmpty) {
        await _supabase.from('schedule_review_comments').insert({
          'promotor_id': widget.promotorId,
          'month_year': widget.monthYear,
          'author_id': userId,
          'author_name': _currentUserName.isEmpty ? 'SATOR' : _currentUserName,
          'author_role': _currentUserRole.isEmpty ? 'sator' : _currentUserRole,
          'message': reason.trim(),
        });
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

  DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);

  List<DateTime> _monthCellsForCalendar() {
    final month = DateTime.parse('${widget.monthYear}-01');
    final firstDay = DateTime(month.year, month.month, 1);
    final startOffset = firstDay.weekday - 1;
    final gridStart = firstDay.subtract(Duration(days: startOffset));
    return List<DateTime>.generate(
      42,
      (index) => gridStart.add(Duration(days: index)),
    );
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
          DateFormat('MMMM yyyy', 'id_ID').format(DateTime.parse('${widget.monthYear}-01')),
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
            _buildTonePill(_statusLabel(_currentStatus), _statusTone(_currentStatus)),
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
    final cells = _monthCellsForCalendar();
    const weekdays = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];
    final month = DateTime.parse('${widget.monthYear}-01');
    final workingDays = _schedules
        .where((row) => '${row['shift_type'] ?? ''}' != 'libur')
        .length;
    final offDays = _schedules.length - workingDays;
    final scheduleByDate = <DateTime, Map<String, dynamic>>{
      for (final row in _schedules)
        _normalizeDate(DateTime.parse('${row['schedule_date']}')): row,
    };

    return PromotorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kalender',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 12),
          if (_schedules.isEmpty)
            Text(
              'Belum ada jadwal untuk bulan ini.',
              style: PromotorText.outfit(
                size: 15,
                weight: FontWeight.w600,
                color: t.textSecondary,
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final textScale = MediaQuery.textScalerOf(context).scale(1);
                final contentWidth = constraints.maxWidth;
                final spacing = contentWidth < 340 ? 6.0 : 8.0;
                final cellWidth = (contentWidth - (spacing * 6)) / 7;
                final compact = cellWidth < 52 || textScale > 1.05;
                final veryCompact = cellWidth < 44 || textScale > 1.15;
                final weekdayFont = compact ? 11.0 : 13.0;
                final cellPadding = compact ? 6.0 : 8.0;
                final aspectRatio = veryCompact ? 0.74 : (compact ? 0.82 : 0.9);
                final labelFont = compact ? 6.5 : 7.4;

                return Column(
                  children: [
                    Row(
                      children: weekdays
                          .map(
                            (label) => Expanded(
                              child: Center(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    label,
                                    maxLines: 1,
                                    style: PromotorText.outfit(
                                      size: weekdayFont,
                                      weight: FontWeight.w700,
                                      color: t.textSecondary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 10),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: cells.length,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        childAspectRatio: aspectRatio,
                        crossAxisSpacing: spacing,
                        mainAxisSpacing: spacing,
                      ),
                      itemBuilder: (context, index) {
                        final day = cells[index];
                        final inMonth = day.month == month.month;
                        final schedule = scheduleByDate[_normalizeDate(day)];
                        final shift = '${schedule?['shift_type'] ?? 'libur'}';
                        final tone = _shiftColor(shift);

                        if (!inMonth) {
                          return IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.transparent,
                                borderRadius: BorderRadius.circular(compact ? 14 : 18),
                              ),
                            ),
                          );
                        }

                        return Container(
                          padding: EdgeInsets.all(cellPadding),
                          decoration: BoxDecoration(
                            color: schedule == null
                                ? t.surface2
                                : tone.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(compact ? 14 : 18),
                            border: Border.all(
                              color: schedule == null
                                  ? t.surface3
                                  : tone.withValues(alpha: 0.35),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: compact ? 24 : 28,
                                height: compact ? 24 : 28,
                                decoration: BoxDecoration(
                                  color: t.textOnAccent,
                                  shape: BoxShape.circle,
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${day.day}',
                                  maxLines: 1,
                                  style: PromotorText.outfit(
                                    size: compact ? 11 : 13,
                                    weight: FontWeight.w800,
                                    color: t.textPrimary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 1),
                              if (schedule != null)
                                Expanded(
                                  child: Transform.translate(
                                    offset: const Offset(0, -3),
                                    child: Align(
                                      alignment: Alignment.topCenter,
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 1),
                                        child: FittedBox(
                                          fit: BoxFit.scaleDown,
                                          child: Text(
                                            _shiftShortLabel(shift),
                                            textAlign: TextAlign.center,
                                            style: PromotorText.outfit(
                                              size: labelFont,
                                              weight: FontWeight.w700,
                                              color: tone,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _buildStatItem('$workingDays', 'hari kerja', t.info, compact: true),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _buildStatItem('$offDays', 'libur', t.textMuted, compact: true),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String value, String label, Color tone, {bool compact = false}) {
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
