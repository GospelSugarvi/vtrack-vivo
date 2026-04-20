import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

enum ShiftType { pagi, siang, fullday, libur }

class JadwalBulananPageNew extends StatefulWidget {
  const JadwalBulananPageNew({super.key});

  @override
  State<JadwalBulananPageNew> createState() => _JadwalBulananPageNewState();
}

class _JadwalBulananPageNewState extends State<JadwalBulananPageNew> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  DateTime _activeMonth = DateTime(DateTime.now().year, DateTime.now().month);
  String _activeStatus = 'draft';
  String _promotorName = 'Promotor';
  List<Map<String, dynamic>> _history = <Map<String, dynamic>>[];

  FieldThemeTokens get t => context.fieldTokens;
  String get _activeMonthLabel =>
      DateFormat('MMMM yyyy', 'id_ID').format(_activeMonth);

  @override
  void initState() {
    super.initState();
    _loadPage();
  }

  DateTime _monthStart(DateTime month) => DateTime(month.year, month.month, 1);
  DateTime _nextMonthStart(DateTime month) =>
      DateTime(month.year, month.month + 1, 1);

  Future<void> _loadPromotorName() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final row = await _supabase
        .from('users')
        .select('full_name, nickname')
        .eq('id', userId)
        .maybeSingle();
    final nickname = '${row?['nickname'] ?? ''}'.trim();
    final fullName = '${row?['full_name'] ?? ''}'.trim();
    _promotorName = nickname.isNotEmpty
        ? nickname
        : (fullName.isNotEmpty ? fullName : 'Promotor');
  }

  Future<void> _loadPage() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadPromotorName(),
        _loadActiveMonthSummary(),
        _loadHistory(),
      ]);
    } catch (e) {
      _showMessage('Gagal memuat jadwal. $e', isError: true);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadActiveMonthSummary() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('Session user tidak ditemukan.');
    }
    final monthStart = _monthStart(_activeMonth);
    final nextMonth = _nextMonthStart(_activeMonth);
    final rows = await _supabase
        .from('schedules')
        .select('status, rejection_reason, schedule_date')
        .eq('promotor_id', userId)
        .gte('schedule_date', DateFormat('yyyy-MM-dd').format(monthStart))
        .lt('schedule_date', DateFormat('yyyy-MM-dd').format(nextMonth))
        .order('schedule_date');

    if (rows.isEmpty) {
      _activeStatus = 'draft';
      return;
    }

    final statuses = rows.map((row) => '${row['status'] ?? 'draft'}').toSet();

    String deriveStatus() {
      if (statuses.contains('submitted')) return 'submitted';
      if (statuses.contains('rejected')) return 'rejected';
      if (statuses.contains('approved')) return 'approved';
      return 'draft';
    }

    _activeStatus = deriveStatus();
  }

  Future<void> _loadHistory() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final rows = await _supabase
        .from('schedules')
        .select(
          'month_year, schedule_date, status, updated_at, rejection_reason',
        )
        .eq('promotor_id', userId)
        .order('schedule_date', ascending: false)
        .order('updated_at', ascending: false);

    final monthly = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final scheduleDate = DateTime.tryParse('${row['schedule_date'] ?? ''}');
      final monthYear = '${row['month_year'] ?? ''}'.trim().isNotEmpty
          ? '${row['month_year']}'
          : (scheduleDate == null
                ? ''
                : DateFormat('yyyy-MM').format(scheduleDate));
      if (monthYear.isEmpty) continue;
      monthly.putIfAbsent(monthYear, () {
        return <String, dynamic>{
          'month_year': monthYear,
          'statuses': <String>{},
          'updated_at': row['updated_at'],
          'total_days': 0,
          'rejection_reason': row['rejection_reason'],
        };
      });
      (monthly[monthYear]!['statuses'] as Set<String>).add(
        '${row['status'] ?? 'draft'}',
      );
      monthly[monthYear]!['total_days'] =
          (monthly[monthYear]!['total_days'] as int) + 1;
      if ((row['rejection_reason']?.toString().trim().isNotEmpty ?? false)) {
        monthly[monthYear]!['rejection_reason'] = row['rejection_reason'];
      }
    }

    String deriveStatus(Set<String> statuses) {
      if (statuses.contains('submitted')) return 'submitted';
      if (statuses.contains('rejected')) return 'rejected';
      if (statuses.contains('approved')) return 'approved';
      return 'draft';
    }

    _history =
        monthly.values.map((item) {
          final statuses = item['statuses'] as Set<String>;
          return <String, dynamic>{
            'month_year': item['month_year'],
            'status': deriveStatus(statuses),
            'updated_at': item['updated_at'],
            'total_days': item['total_days'],
            'rejection_reason': item['rejection_reason'],
          };
        }).toList()..sort(
          (a, b) => '${b['month_year']}'.compareTo('${a['month_year']}'),
        );
  }

  Future<void> _pickNewMonth() async {
    final month = await _showMonthPickerSheet();
    if (month == null || !mounted) return;

    final monthYear = DateFormat('yyyy-MM').format(month);
    final historyItem = _history
        .where((row) => '${row['month_year']}' == monthYear)
        .firstOrNull;
    final status = historyItem == null
        ? 'draft'
        : '${historyItem['status'] ?? 'draft'}';

    final shouldReload = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) =>
            JadwalBulananComposerPage(month: month, initialStatus: status),
      ),
    );

    if (shouldReload == true) {
      _activeMonth = month;
      await _loadPage();
    }
  }

  Future<DateTime?> _showMonthPickerSheet() async {
    final now = DateTime.now();
    final availableYears = List<int>.generate(
      4,
      (index) => now.year - 1 + index,
    );
    final monthLabels = const <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'Mei',
      'Jun',
      'Jul',
      'Agu',
      'Sep',
      'Okt',
      'Nov',
      'Des',
    ];
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: t.textOnAccent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        var selectedYear = _activeMonth.year;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pilih Bulan Jadwal',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.surface3),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          value: selectedYear,
                          isExpanded: true,
                          items: availableYears
                              .map(
                                (year) => DropdownMenuItem<int>(
                                  value: year,
                                  child: Text('$year'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setSheetState(() => selectedYear = value);
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 12,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            childAspectRatio: 2.2,
                          ),
                      itemBuilder: (context, index) {
                        final month = index + 1;
                        final isActive =
                            selectedYear == _activeMonth.year &&
                            month == _activeMonth.month;
                        return InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            Navigator.of(
                              context,
                            ).pop(DateTime(selectedYear, month));
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              color: isActive
                                  ? t.primaryAccent.withValues(alpha: 0.14)
                                  : t.surface1,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isActive ? t.primaryAccent : t.surface3,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              monthLabels[index],
                              style: TextStyle(
                                color: isActive
                                    ? t.primaryAccent
                                    : t.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return picked == null ? null : DateTime(picked.year, picked.month);
  }

  Future<void> _openHistory(Map<String, dynamic> item) async {
    final month = DateTime.parse('${item['month_year']}-01');
    final status = '${item['status'] ?? 'draft'}';
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final monthStart = _monthStart(month);
    final nextMonth = _nextMonthStart(month);

    final allScheduleRows = await _supabase
        .from('schedules')
        .select(
          'schedule_date, shift_type, status, rejection_reason, month_year, break_start, break_end, peak_start, peak_end, shift_start, shift_end',
        )
        .eq('promotor_id', userId)
        .order('schedule_date');
    final scheduleRows = List<Map<String, dynamic>>.from(allScheduleRows).where(
      (row) {
        final rowMonthYear = '${row['month_year'] ?? ''}';
        final rowDate = DateTime.tryParse('${row['schedule_date'] ?? ''}');
        if (rowMonthYear == DateFormat('yyyy-MM').format(month)) return true;
        if (rowDate == null) return false;
        return !rowDate.isBefore(monthStart) && rowDate.isBefore(nextMonth);
      },
    ).toList();
    final commentRows = await _supabase
        .from('schedule_review_comments')
        .select('author_name, author_role, message, created_at, month_year')
        .eq('promotor_id', userId)
        .eq('month_year', DateFormat('yyyy-MM').format(month))
        .order('created_at');
    if (!mounted) return;

    final shouldReload = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JadwalBulananComposerPage(
          month: month,
          initialStatus: status,
          forceReadOnly: status == 'approved' || status == 'submitted',
          prefetchedScheduleRows: List<Map<String, dynamic>>.from(scheduleRows),
          prefetchedComments: List<Map<String, dynamic>>.from(commentRows),
        ),
      ),
    );

    if (shouldReload == true) {
      _activeMonth = month;
      await _loadPage();
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'submitted':
        return 'Menunggu review';
      case 'approved':
        return 'Sudah disetujui';
      case 'rejected':
        return 'Ditolak';
      default:
        return 'Belum dikirim';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'submitted':
        return t.warning;
      case 'approved':
        return t.success;
      case 'rejected':
        return t.danger;
      default:
        return t.info;
    }
  }

  bool _showStatusPill(String status) => status != 'draft';

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? t.danger : t.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: Text(_promotorName)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadPage,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
                children: [
                  _buildActiveSummary(),
                  const SizedBox(height: 12),
                  _buildHistoryCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildActiveSummary() {
    final tone = _statusColor(_activeStatus);
    return Container(
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
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Periode aktif',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _activeMonthLabel,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              if (_showStatusPill(_activeStatus))
                _buildPill(_statusLabel(_activeStatus), tone),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _pickNewMonth,
              icon: const Icon(Icons.add_circle_outline_rounded),
              label: const Text('Buat jadwal baru'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Riwayat Jadwal',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 8),
          if (_history.isEmpty)
            Text(
              'Belum ada jadwal yang pernah dibuat.',
              style: TextStyle(color: t.textSecondary),
            )
          else
            ..._history.take(8).map((item) {
              final status = '${item['status'] ?? 'draft'}';
              final tone = _statusColor(status);
              final monthDate = DateTime.parse('${item['month_year']}-01');
              final updatedAt = DateTime.tryParse(
                '${item['updated_at'] ?? ''}',
              );
              final rejectionReason = item['rejection_reason']?.toString();

              return InkWell(
                onTap: () => _openHistory(item),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              DateFormat(
                                'MMMM yyyy',
                                'id_ID',
                              ).format(monthDate),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            if (updatedAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                DateFormat(
                                  'dd MMM yyyy',
                                  'id_ID',
                                ).format(updatedAt),
                                style: TextStyle(
                                  color: t.textSecondary,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                            if (rejectionReason != null &&
                                rejectionReason.trim().isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                rejectionReason,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: t.danger,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (_showStatusPill(status)) ...[
                        const SizedBox(width: 8),
                        _buildPill(_statusLabel(status), tone),
                      ],
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class JadwalBulananComposerPage extends StatefulWidget {
  const JadwalBulananComposerPage({
    super.key,
    required this.month,
    required this.initialStatus,
    this.forceReadOnly = false,
    this.prefetchedScheduleRows = const [],
    this.prefetchedComments = const [],
  });

  final DateTime month;
  final String initialStatus;
  final bool forceReadOnly;
  final List<Map<String, dynamic>> prefetchedScheduleRows;
  final List<Map<String, dynamic>> prefetchedComments;

  @override
  State<JadwalBulananComposerPage> createState() =>
      _JadwalBulananComposerPageState();
}

class _JadwalBulananComposerPageState extends State<JadwalBulananComposerPage> {
  final _supabase = Supabase.instance.client;
  final ScrollController _pageScrollController = ScrollController();
  final GlobalKey _peakHoursCardKey = GlobalKey();
  final GlobalKey _calendarCardKey = GlobalKey();

  final Map<DateTime, ShiftType> _schedules = <DateTime, ShiftType>{};
  final Map<DateTime, String> _breakStartByDate = <DateTime, String>{};
  final Map<DateTime, String> _breakEndByDate = <DateTime, String>{};
  final Map<String, String> _shiftStartByType = <String, String>{};
  final Map<String, String> _shiftEndByType = <String, String>{};
  final Set<DateTime> _selectedDates = <DateTime>{};
  final List<Map<String, dynamic>> _comments = <Map<String, dynamic>>[];

  bool _isLoading = true;
  bool _isSaving = false;
  bool _hasLoadedScheduleData = false;
  late DateTime _month;
  late String _status;
  String? _rejectionReason;
  String? _peakStart;
  String? _peakEnd;

  FieldThemeTokens get t => context.fieldTokens;
  String get _monthYear => DateFormat('yyyy-MM').format(_month);
  String get _monthLabel => DateFormat('MMMM yyyy', 'id_ID').format(_month);
  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;
  int get _filledDays => _schedules.length;
  Set<String> get _usedShiftTypes => _schedules.values
      .where((shift) => shift != ShiftType.libur)
      .map((shift) => shift.name)
      .toSet();
  bool get _hasPeakHours =>
      (_peakStart?.isNotEmpty ?? false) && (_peakEnd?.isNotEmpty ?? false);
  List<String> get _missingShiftTemplateTypes => _usedShiftTypes
      .where((shiftType) => !_hasShiftWindow(shiftType))
      .toList()
    ..sort();
  int get _missingBreakCount => _schedules.entries
      .where(
        (entry) =>
            entry.value != ShiftType.libur && !_hasBreakWindow(entry.key),
      )
      .length;
  bool get _hasAllRequiredShiftTemplates => _missingShiftTemplateTypes.isEmpty;
  bool get _hasBreakForAllWorkingDays => _missingBreakCount == 0;
  bool get _isComplete =>
      _filledDays == _daysInMonth &&
      _hasPeakHours &&
      _hasAllRequiredShiftTemplates &&
      _hasBreakForAllWorkingDays;
  bool get _isEditable =>
      !widget.forceReadOnly && (_status == 'draft' || _status == 'rejected');

  @override
  void initState() {
    super.initState();
    _month = DateTime(widget.month.year, widget.month.month);
    _status = widget.initialStatus;
    _loadPage();
  }

  @override
  void dispose() {
    _pageScrollController.dispose();
    super.dispose();
  }

  DateTime _normalize(DateTime date) =>
      DateTime(date.year, date.month, date.day);
  DateTime _monthStart(DateTime month) => DateTime(month.year, month.month, 1);
  DateTime _nextMonthStart(DateTime month) =>
      DateTime(month.year, month.month + 1, 1);

  Future<void> _loadPage() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      _applyScheduleRows(widget.prefetchedScheduleRows, allowEmpty: true);
      _applyCommentRows(widget.prefetchedComments);
      await Future.wait([_loadSchedule(), _loadComments()]);
    } catch (e) {
      _showMessage('Gagal memuat kalender jadwal. $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadSchedule() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final monthStart = _monthStart(_month);
    final nextMonth = _nextMonthStart(_month);

    final rows = await _supabase
        .from('schedules')
        .select(
          'schedule_date, shift_type, status, rejection_reason, month_year, break_start, break_end, peak_start, peak_end, shift_start, shift_end',
        )
        .eq('promotor_id', userId)
        .order('schedule_date');

    final parsedRows = List<Map<String, dynamic>>.from(rows).where((row) {
      final rowMonthYear = '${row['month_year'] ?? ''}';
      final rowDate = DateTime.tryParse('${row['schedule_date'] ?? ''}');
      if (rowMonthYear == _monthYear) return true;
      if (rowDate == null) return false;
      return !rowDate.isBefore(monthStart) && rowDate.isBefore(nextMonth);
    }).toList();
    if (parsedRows.isEmpty && _hasLoadedScheduleData) {
      return;
    }
    _applyScheduleRows(parsedRows);
  }

  Future<void> _loadComments() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final rows = await _supabase
        .from('schedule_review_comments')
        .select('author_name, author_role, message, created_at, month_year')
        .eq('promotor_id', userId)
        .eq('month_year', _monthYear)
        .order('created_at');

    _applyCommentRows(List<Map<String, dynamic>>.from(rows));
  }

  void _applyScheduleRows(
    List<Map<String, dynamic>> rows, {
    bool allowEmpty = false,
  }) {
    if (rows.isEmpty && !allowEmpty) {
      _schedules.clear();
      _breakStartByDate.clear();
      _breakEndByDate.clear();
      _shiftStartByType.clear();
      _shiftEndByType.clear();
      _status = 'draft';
      _rejectionReason = null;
      _peakStart = null;
      _peakEnd = null;
      _selectedDates.clear();
      _hasLoadedScheduleData = false;
      return;
    }

    if (rows.isEmpty && allowEmpty) {
      return;
    }

    _schedules.clear();
    _breakStartByDate.clear();
    _breakEndByDate.clear();
    _shiftStartByType.clear();
    _shiftEndByType.clear();
    var nextStatus = widget.initialStatus;
    String? nextReason;

    for (final row in rows) {
      final date = DateTime.tryParse('${row['schedule_date'] ?? ''}');
      final shiftName = '${row['shift_type'] ?? ''}';
      if (date == null || shiftName.isEmpty) continue;
      final shift = ShiftType.values
          .where((e) => e.name == shiftName)
          .firstOrNull;
      if (shift == null) continue;
      final normalizedDate = _normalize(date);
      _schedules[normalizedDate] = shift;
      final breakStart = _normalizeTimeValue(row['break_start']);
      final breakEnd = _normalizeTimeValue(row['break_end']);
      if (breakStart != null && breakStart.isNotEmpty) {
        _breakStartByDate[normalizedDate] = breakStart;
      }
      if (breakEnd != null && breakEnd.isNotEmpty) {
        _breakEndByDate[normalizedDate] = breakEnd;
      }
      _peakStart ??= _normalizeTimeValue(row['peak_start']);
      _peakEnd ??= _normalizeTimeValue(row['peak_end']);
      final shiftStart = _normalizeTimeValue(row['shift_start']);
      final shiftEnd = _normalizeTimeValue(row['shift_end']);
      if (shiftName != 'libur' &&
          shiftStart != null &&
          shiftStart.isNotEmpty &&
          !_shiftStartByType.containsKey(shiftName)) {
        _shiftStartByType[shiftName] = shiftStart;
      }
      if (shiftName != 'libur' &&
          shiftEnd != null &&
          shiftEnd.isNotEmpty &&
          !_shiftEndByType.containsKey(shiftName)) {
        _shiftEndByType[shiftName] = shiftEnd;
      }
      nextStatus = '${row['status'] ?? nextStatus}';
      nextReason = row['rejection_reason']?.toString();
    }

    if (rows.isNotEmpty) {
      _status = nextStatus;
      _rejectionReason = nextReason;
      _hasLoadedScheduleData = true;
    }
    _selectedDates.clear();
  }

  void _applyCommentRows(List<Map<String, dynamic>> rows) {
    _comments
      ..clear()
      ..addAll(
        rows.where((row) {
          final monthYear = '${row['month_year'] ?? ''}'.trim();
          return monthYear.isEmpty || monthYear == _monthYear;
        }),
      );
  }

  String? _normalizeTimeValue(dynamic raw) {
    final value = '${raw ?? ''}'.trim();
    if (value.isEmpty) return null;
    if (value.length >= 5) return value.substring(0, 5);
    return value;
  }

  TimeOfDay? _parseTimeOfDay(String? value) {
    final raw = value?.trim() ?? '';
    if (raw.isEmpty || !raw.contains(':')) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  bool _hasShiftWindow(String shiftType) {
    return (_shiftStartByType[shiftType]?.isNotEmpty ?? false) &&
        (_shiftEndByType[shiftType]?.isNotEmpty ?? false);
  }

  bool _hasBreakWindow(DateTime date) {
    return (_breakStartByDate[date]?.isNotEmpty ?? false) &&
        (_breakEndByDate[date]?.isNotEmpty ?? false);
  }

  List<String> _collectValidationIssues({
    required bool includeDayCompleteness,
    Set<String>? targetShiftTypes,
  }) {
    final issues = <String>[];

    if (!_hasPeakHours) {
      issues.add('Jam ramai toko belum diatur.');
    }

    if (includeDayCompleteness && _filledDays != _daysInMonth) {
      issues.add(
        'Jadwal belum lengkap: baru $_filledDays dari $_daysInMonth hari.',
      );
    }

    final requiredShiftTypes = targetShiftTypes ?? _usedShiftTypes;
    final missingShiftTypes = requiredShiftTypes
        .where((shiftType) => !_hasShiftWindow(shiftType))
        .map(_shiftLabelByName)
        .toList()
      ..sort();

    if (missingShiftTypes.isNotEmpty) {
      issues.add('Jam shift belum diatur untuk: ${missingShiftTypes.join(', ')}.');
    }

    if (includeDayCompleteness && _missingBreakCount > 0) {
      issues.add('Jam break belum lengkap di $_missingBreakCount hari kerja.');
    }

    return issues;
  }

  Future<void> _showValidationIssues(
    List<String> issues, {
    String title = 'Lengkapi Jadwal Dulu',
  }) async {
    if (issues.isEmpty || !mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: t.textOnAccent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                ...issues.map(
                  (issue) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(top: 5),
                          child: Icon(
                            Icons.error_outline_rounded,
                            size: 16,
                            color: t.warning,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            issue,
                            style: TextStyle(
                              color: t.textSecondary,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Mengerti'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop();
                          _jumpToFirstIssue();
                        },
                        child: const Text('Perbaiki Sekarang'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _jumpToSection(GlobalKey key) async {
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      alignment: 0.08,
    );
  }

  Future<void> _jumpToFirstIssue() async {
    await Future<void>.delayed(const Duration(milliseconds: 90));
    if (!mounted) return;

    if (!_hasPeakHours) {
      await _jumpToSection(_peakHoursCardKey);
      return;
    }

    if (!_hasAllRequiredShiftTemplates) {
      await _jumpToSection(_calendarCardKey);
      return;
    }

    if (_filledDays != _daysInMonth || !_hasBreakForAllWorkingDays) {
      await _jumpToSection(_calendarCardKey);
    }
  }

  String _shiftTimeText(String shiftType) {
    if (shiftType == 'libur') return 'Libur';
    final start = _shiftStartByType[shiftType];
    final end = _shiftEndByType[shiftType];
    if ((start?.isNotEmpty ?? false) && (end?.isNotEmpty ?? false)) {
      return '$start-$end';
    }
    return 'Belum diatur';
  }

  Future<void> _editShiftWindow(String shiftType) async {
    String? start = _shiftStartByType[shiftType];
    String? end = _shiftEndByType[shiftType];
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.textOnAccent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Shift ${_shiftLabel(ShiftType.values.firstWhere((e) => e.name == shiftType))}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Isi satu kali untuk periode bulan ini.',
                      style: TextStyle(color: t.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final value = await _pickClockTime(
                                initialValue: start,
                              );
                              if (value != null) {
                                setSheetState(() => start = value);
                              }
                            },
                            child: Text(start ?? 'Mulai'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final value = await _pickClockTime(
                                initialValue: end,
                              );
                              if (value != null) {
                                setSheetState(() => end = value);
                              }
                            },
                            child: Text(end ?? 'Selesai'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (start == null || end == null)
                            ? null
                            : () => Navigator.of(context).pop((start!, end!)),
                        child: const Text('Simpan Shift'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (result == null) return;
    setState(() {
      _shiftStartByType[shiftType] = result.$1;
      _shiftEndByType[shiftType] = result.$2;
      _status = 'draft';
      _rejectionReason = null;
    });
  }

  Future<String?> _pickClockTime({String? initialValue}) async {
    final initialTime =
        _parseTimeOfDay(initialValue) ?? const TimeOfDay(hour: 12, minute: 0);
    final saved = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.textOnAccent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        var selectedHour = initialTime.hour;
        var selectedMinute = initialTime.minute;
        final hourController = FixedExtentScrollController(
          initialItem: selectedHour,
        );
        final minuteController = FixedExtentScrollController(
          initialItem: selectedMinute,
        );

        Widget buildWheel({
          required FixedExtentScrollController controller,
          required int itemCount,
          required ValueChanged<int> onSelectedItemChanged,
        }) {
          return CupertinoPicker(
            scrollController: controller,
            itemExtent: 40,
            selectionOverlay: Container(
              decoration: BoxDecoration(
                border: Border.symmetric(
                  horizontal: BorderSide(color: t.surface3),
                ),
              ),
            ),
            onSelectedItemChanged: onSelectedItemChanged,
            children: List<Widget>.generate(
              itemCount,
              (index) => Center(
                child: Text(
                  index.toString().padLeft(2, '0'),
                  style: TextStyle(
                    color: t.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }

        return StatefulBuilder(
          builder: (context, setSheetState) {
            final preview =
                '${selectedHour.toString().padLeft(2, '0')}:${selectedMinute.toString().padLeft(2, '0')}';
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'Pilih Jam',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: t.surface2,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: t.surface3),
                          ),
                          child: Text(
                            preview,
                            style: TextStyle(
                              color: t.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      height: 180,
                      child: Row(
                        children: [
                          Expanded(
                            child: buildWheel(
                              controller: hourController,
                              itemCount: 24,
                              onSelectedItemChanged: (value) {
                                setSheetState(() => selectedHour = value);
                              },
                            ),
                          ),
                          Text(
                            ':',
                            style: TextStyle(
                              color: t.textPrimary,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Expanded(
                            child: buildWheel(
                              controller: minuteController,
                              itemCount: 60,
                              onSelectedItemChanged: (value) {
                                setSheetState(() => selectedMinute = value);
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Batal'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton(
                            onPressed: () => Navigator.of(context).pop(preview),
                            child: const Text('Simpan'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    return saved;
  }

  Future<(String, String)?> _showBreakTimeSheet(ShiftType shift) async {
    String? breakStart;
    String? breakEnd;
    return showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.textOnAccent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Break ${_shiftLabel(shift)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Pilih jam break untuk semua tanggal yang dipilih.',
                      style: TextStyle(color: t.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final value = await _pickClockTime(
                                initialValue: breakStart,
                              );
                              if (value != null) {
                                setSheetState(() => breakStart = value);
                              }
                            },
                            child: Text(breakStart ?? 'Mulai Break'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final value = await _pickClockTime(
                                initialValue: breakEnd,
                              );
                              if (value != null) {
                                setSheetState(() => breakEnd = value);
                              }
                            },
                            child: Text(breakEnd ?? 'Selesai Break'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (breakStart == null || breakEnd == null)
                            ? null
                            : () => Navigator.of(
                                context,
                              ).pop((breakStart!, breakEnd!)),
                        child: const Text('Terapkan'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<ShiftType?> _showShiftPickerSheet() {
    final dates = _selectedDates.toList()..sort();
    final firstDate = dates.isEmpty ? null : dates.first;
    final currentShift = dates.length == 1 ? _schedules[firstDate] : null;

    Widget buildShiftTile({required ShiftType shift, required IconData icon}) {
      final tone = _shiftColor(shift);
      final selected = currentShift == shift;
      final time = shift == ShiftType.libur ? null : _shiftTimeText(shift.name);

      return InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.of(context).pop(shift),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: tone.withValues(alpha: selected ? 0.16 : 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? tone : tone.withValues(alpha: 0.2),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: tone.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: tone),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _shiftLabel(shift),
                      style: TextStyle(
                        color: tone,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      time ?? 'Tidak masuk kerja',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, color: tone, size: 20),
            ],
          ),
        ),
      );
    }

    return showModalBottomSheet<ShiftType>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.textOnAccent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pilih Shift',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  dates.length <= 1
                      ? DateFormat(
                          'EEEE, dd MMMM yyyy',
                          'id_ID',
                        ).format(firstDate ?? DateTime.now())
                      : '${dates.length} tanggal dipilih',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 14),
                buildShiftTile(
                  shift: ShiftType.pagi,
                  icon: Icons.wb_sunny_outlined,
                ),
                buildShiftTile(
                  shift: ShiftType.siang,
                  icon: Icons.wb_twilight_outlined,
                ),
                buildShiftTile(
                  shift: ShiftType.fullday,
                  icon: Icons.schedule_rounded,
                ),
                buildShiftTile(
                  shift: ShiftType.libur,
                  icon: Icons.hotel_rounded,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _editPeakHours() async {
    String? start = _peakStart;
    String? end = _peakEnd;
    final result = await showModalBottomSheet<(String, String)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.textOnAccent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Jam Ramai Toko',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Isi satu kali untuk periode bulan ini.',
                      style: TextStyle(color: t.textSecondary),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final value = await _pickClockTime(
                                initialValue: start,
                              );
                              if (value != null) {
                                setSheetState(() => start = value);
                              }
                            },
                            child: Text(start ?? 'Mulai'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final value = await _pickClockTime(
                                initialValue: end,
                              );
                              if (value != null) {
                                setSheetState(() => end = value);
                              }
                            },
                            child: Text(end ?? 'Selesai'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: (start == null || end == null)
                            ? null
                            : () => Navigator.of(context).pop((start!, end!)),
                        child: const Text('Simpan Jam Ramai'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
    if (result == null) return;
    setState(() {
      _peakStart = result.$1;
      _peakEnd = result.$2;
      _status = 'draft';
      _rejectionReason = null;
    });
  }

  Future<void> _applyShiftToSelected(ShiftType shift) async {
    if (!_isEditable || _selectedDates.isEmpty) return;

    // Potong step: jika shift dipilih belum punya jam, langsung arahkan
    // ke pengaturan jam shift yang relevan, lalu lanjutkan proses apply.
    if (shift != ShiftType.libur && !_hasShiftWindow(shift.name)) {
      await _editShiftWindow(shift.name);
      if (!_hasShiftWindow(shift.name)) {
        return;
      }
    }

    final issues = _collectValidationIssues(
      includeDayCompleteness: false,
      targetShiftTypes: shift == ShiftType.libur ? <String>{} : {shift.name},
    );
    if (issues.isNotEmpty) {
      await _showValidationIssues(issues, title: 'Belum Bisa Terapkan Shift');
      return;
    }

    String? breakStart;
    String? breakEnd;
    if (shift != ShiftType.libur) {
      final result = await _showBreakTimeSheet(shift);
      if (result == null) return;
      breakStart = result.$1;
      breakEnd = result.$2;
    }

    final dates = _selectedDates.toList()..sort();
    setState(() {
      for (final date in dates) {
        _schedules[date] = shift;
        if (shift == ShiftType.libur) {
          _breakStartByDate.remove(date);
          _breakEndByDate.remove(date);
        } else {
          _breakStartByDate[date] = breakStart!;
          _breakEndByDate[date] = breakEnd!;
        }
      }
      _status = 'draft';
      _rejectionReason = null;
      _selectedDates.clear();
    });
  }

  void _toggleDateSelection(DateTime date) {
    if (!_isEditable) return;
    final normalized = _normalize(date);
    setState(() {
      if (_selectedDates.contains(normalized)) {
        _selectedDates.remove(normalized);
      } else {
        _selectedDates.add(normalized);
      }
    });
  }

  Future<void> _openBulkShiftPicker() async {
    if (!_isEditable || _selectedDates.isEmpty) return;

    final issues = _collectValidationIssues(
      includeDayCompleteness: false,
      targetShiftTypes: const <String>{},
    );
    if (issues.isNotEmpty) {
      await _showValidationIssues(issues, title: 'Belum Bisa Pilih Shift');
      return;
    }

    final shift = await _showShiftPickerSheet();
    if (!mounted) return;

    if (shift == null) {
      return;
    }

    await _applyShiftToSelected(shift);
  }

  String _breakTimeText(DateTime date) {
    final start = _breakStartByDate[date];
    final end = _breakEndByDate[date];
    if ((start?.isNotEmpty ?? false) && (end?.isNotEmpty ?? false)) {
      return '$start - $end';
    }
    return '-';
  }

  Future<void> _openSubmitPreview() async {
    if (!_isEditable) return;
    final issues = _collectValidationIssues(includeDayCompleteness: true);
    if (issues.isNotEmpty) {
      await _showValidationIssues(issues, title: 'Preview Belum Bisa Dibuka');
      return;
    }

    final dates = _schedules.keys.toList()..sort();
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
      TextAlign textAlign = TextAlign.left,
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
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 12,
            fontWeight: header ? FontWeight.w800 : FontWeight.w700,
            color: color ?? (header ? t.textPrimary : t.textSecondary),
          ),
        ),
      );
    }

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.textOnAccent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.88,
            minChildSize: 0.6,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Preview Jadwal',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Periksa lagi semua isi jadwal sebelum dikirim ke SATOR.',
                      style: TextStyle(color: t.textSecondary),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Jam ramai toko: ${_peakStart ?? '-'} - ${_peakEnd ?? '-'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total hari terisi: ${dates.length} / $_daysInMonth',
                            style: TextStyle(
                              color: t.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: t.surface3),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Scrollbar(
                          controller: scrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: scrollController,
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
                                  ...dates.map((date) {
                                    final shift = _schedules[date]!;
                                    final tone = _shiftColor(shift);
                                    final shiftWindow = shift == ShiftType.libur
                                        ? '-'
                                        : _shiftTimeText(shift.name);
                                    final breakWindow = shift == ShiftType.libur
                                        ? '-'
                                        : _breakTimeText(date);
                                    final dateText = DateFormat(
                                      'dd MMM, EEE',
                                      'id_ID',
                                    ).format(date);
                                    return Row(
                                      children: [
                                        buildCell(
                                          dateText,
                                          width: dateColumnWidth,
                                          color: t.textPrimary,
                                        ),
                                        buildCell(
                                          _shiftLabel(shift),
                                          width: shiftColumnWidth,
                                          color: tone,
                                        ),
                                        buildCell(
                                          shiftWindow,
                                          width: shiftTimeColumnWidth,
                                          color: t.textPrimary,
                                        ),
                                        buildCell(
                                          breakWindow,
                                          width: breakColumnWidth,
                                          color: t.textPrimary,
                                        ),
                                        buildCell(
                                          '${_peakStart ?? '-'}-${_peakEnd ?? '-'}',
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
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.of(context).pop(false),
                            child: const Text('Kembali Edit'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: () => Navigator.of(context).pop(true),
                            icon: const Icon(Icons.send_rounded),
                            label: const Text('Kirim ke SATOR'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    if (confirmed == true) {
      await _submitSchedule();
    }
  }

  Future<void> _submitSchedule() async {
    if (!_isEditable) return;
    final issues = _collectValidationIssues(includeDayCompleteness: true);
    if (issues.isNotEmpty) {
      await _showValidationIssues(issues, title: 'Pengiriman Ditolak');
      return;
    }

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _isSaving = true);
    try {
      final payload =
          _schedules.entries
              .map(
                (entry) => <String, dynamic>{
                  'schedule_date': DateFormat('yyyy-MM-dd').format(entry.key),
                  'shift_type': entry.value.name,
                  'break_start': _breakStartByDate[entry.key],
                  'break_end': _breakEndByDate[entry.key],
                  'peak_start': _peakStart,
                  'peak_end': _peakEnd,
                  'shift_start': entry.value == ShiftType.libur
                      ? null
                      : _shiftStartByType[entry.value.name],
                  'shift_end': entry.value == ShiftType.libur
                      ? null
                      : _shiftEndByType[entry.value.name],
                },
              )
              .toList()
            ..sort(
              (a, b) =>
                  '${a['schedule_date']}'.compareTo('${b['schedule_date']}'),
            );

      await _supabase.rpc(
        'save_monthly_schedule_draft_bulk',
        params: {'p_month_year': _monthYear, 'p_items': payload},
      );

      final result = await _supabase.rpc(
        'submit_monthly_schedule',
        params: {'p_promotor_id': userId, 'p_month_year': _monthYear},
      );

      final rows = List<Map<String, dynamic>>.from(result ?? const []);
      final first = rows.isNotEmpty ? rows.first : const <String, dynamic>{};
      if (first['success'] != true) {
        _showMessage(
          '${first['message'] ?? 'Gagal kirim jadwal.'}',
          isError: true,
        );
        return;
      }

      await _loadSchedule();
      if (mounted) setState(() {});
      _showMessage('${first['message'] ?? 'Jadwal berhasil dikirim.'}');
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      _showMessage('Gagal kirim jadwal. $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'submitted':
        return 'Menunggu review';
      case 'approved':
        return 'Sudah disetujui';
      case 'rejected':
        return 'Ditolak';
      default:
        return 'Draft';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'submitted':
        return t.warning;
      case 'approved':
        return t.success;
      case 'rejected':
        return t.danger;
      default:
        return t.info;
    }
  }

  Color _shiftColor(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return t.warning;
      case ShiftType.siang:
        return t.info;
      case ShiftType.fullday:
        return t.primaryAccent;
      case ShiftType.libur:
        return t.textMuted;
    }
  }

  String _shiftLabel(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi';
      case ShiftType.siang:
        return 'Siang';
      case ShiftType.fullday:
        return 'Fullday';
      case ShiftType.libur:
        return 'Libur';
    }
  }

  String _shiftLabelByName(String shiftType) {
    final shift = ShiftType.values.firstWhere(
      (item) => item.name == shiftType,
      orElse: () => ShiftType.fullday,
    );
    return _shiftLabel(shift);
  }

  String _shiftShortLabel(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'Pagi';
      case ShiftType.siang:
        return 'Siang';
      case ShiftType.fullday:
        return 'Full';
      case ShiftType.libur:
        return 'Libur';
    }
  }

  List<DateTime> _monthCells() {
    final firstDay = DateTime(_month.year, _month.month, 1);
    final startOffset = firstDay.weekday - 1;
    final gridStart = firstDay.subtract(Duration(days: startOffset));
    return List<DateTime>.generate(
      42,
      (index) => gridStart.add(Duration(days: index)),
    );
  }

  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? t.danger : t.success,
      ),
    );
  }

  Widget _buildShiftLegend() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: ShiftType.values.map((shift) {
          final tone = _shiftColor(shift);
          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tone.withValues(alpha: 0.2)),
            ),
            child: Text(
              _shiftLabel(shift),
              style: TextStyle(
                color: tone,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSchedulePreviewTable({
    bool includeTitle = true,
    ScrollController? verticalController,
  }) {
    final dates = _schedules.keys.toList()..sort();
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
      TextAlign textAlign = TextAlign.left,
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
          textAlign: textAlign,
          style: TextStyle(
            fontSize: 12,
            fontWeight: header ? FontWeight.w800 : FontWeight.w700,
            color: color ?? (header ? t.textPrimary : t.textSecondary),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (includeTitle) ...[
            Row(
              children: [
                const Text(
                  'Preview Jadwal',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const Spacer(),
                Text(
                  '${dates.length} / $_daysInMonth hari',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Jam ramai toko: ${_peakStart ?? '-'} - ${_peakEnd ?? '-'}',
              style: TextStyle(
                color: t.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (dates.isEmpty)
            Text(
              'Belum ada jadwal untuk bulan ini.',
              style: TextStyle(color: t.textSecondary),
            )
          else
            Container(
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.surface3),
              ),
              clipBehavior: Clip.antiAlias,
              child: Scrollbar(
                controller: verticalController,
                thumbVisibility: verticalController != null,
                child: SingleChildScrollView(
                  controller: verticalController,
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
                        ...dates.map((date) {
                          final shift = _schedules[date]!;
                          final tone = _shiftColor(shift);
                          final shiftWindow = shift == ShiftType.libur
                              ? '-'
                              : _shiftTimeText(shift.name);
                          final breakWindow = shift == ShiftType.libur
                              ? '-'
                              : _breakTimeText(date);
                          return Row(
                            children: [
                              buildCell(
                                DateFormat('dd MMM, EEE', 'id_ID').format(date),
                                width: dateColumnWidth,
                                color: t.textPrimary,
                              ),
                              buildCell(
                                _shiftLabel(shift),
                                width: shiftColumnWidth,
                                color: tone,
                              ),
                              buildCell(
                                shiftWindow,
                                width: shiftTimeColumnWidth,
                                color: t.textPrimary,
                              ),
                              buildCell(
                                breakWindow,
                                width: breakColumnWidth,
                                color: t.textPrimary,
                              ),
                              buildCell(
                                '${_peakStart ?? '-'}-${_peakEnd ?? '-'}',
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
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: Text(_monthLabel)),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              controller: _pageScrollController,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                if (_status != 'draft' ||
                    (_rejectionReason != null &&
                        _rejectionReason!.trim().isNotEmpty)) ...[
                  _buildStatusHeader(),
                  const SizedBox(height: 12),
                ],
                if (_isEditable) _buildPeakHoursCard(),
                if (_isEditable) const SizedBox(height: 12),
                if (_isEditable)
                  _buildCalendarCard()
                else
                  _buildSchedulePreviewTable(),
                if (_isEditable || _comments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _buildCommentsCard(),
                ],
              ],
            ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildStatusHeader() {
    final tone = _statusColor(_status);
    final showPill = _status != 'draft';
    final showRejection =
        _rejectionReason != null && _rejectionReason!.trim().isNotEmpty;

    if (!showPill && !showRejection) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showPill)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [_pill(_statusLabel(_status), tone)],
            ),
          if (showRejection) ...[
            const SizedBox(height: 10),
            Text(
              'Catatan penolakan: $_rejectionReason',
              style: TextStyle(color: t.danger, fontWeight: FontWeight.w700),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPeakHoursCard() {
    final label = _hasPeakHours ? '$_peakStart - $_peakEnd' : 'Belum diatur';
    return Container(
      key: _peakHoursCardKey,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Jam Ramai Toko',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: _hasPeakHours ? t.textPrimary : t.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          FilledButton(
            onPressed: _editPeakHours,
            child: Text(_hasPeakHours ? 'Ubah' : 'Atur'),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCard() {
    final cells = _monthCells();
    const weekdays = [
      'Senin',
      'Selasa',
      'Rabu',
      'Kamis',
      'Jumat',
      'Sabtu',
      'Minggu',
    ];

    return Container(
      key: _calendarCardKey,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Kalender',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              if (_isEditable)
                Text(
                  _selectedDates.isEmpty
                      ? 'Pilih beberapa tanggal'
                      : '${_selectedDates.length} tanggal dipilih',
                  style: TextStyle(
                    color: t.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(1);
              final contentWidth = constraints.maxWidth;
              final spacing = contentWidth < 340 ? 6.0 : 8.0;
              final cellWidth = (contentWidth - (spacing * 6)) / 7;
              final compact = cellWidth < 52 || textScale > 1.05;
              final veryCompact = cellWidth < 44 || textScale > 1.15;
              final badgeSize = compact ? 16.0 : 18.0;
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
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontWeight: FontWeight.w700,
                                    fontSize: weekdayFont,
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
                      mainAxisSpacing: spacing,
                      crossAxisSpacing: spacing,
                      childAspectRatio: aspectRatio,
                    ),
                    itemBuilder: (context, index) {
                      final day = cells[index];
                      final inMonth = day.month == _month.month;
                      final shift = _schedules[_normalize(day)];
                      final isOffday = shift == ShiftType.libur;
                      final selected = _selectedDates.contains(_normalize(day));
                      final tone = shift == null
                          ? t.surface3
                          : _shiftColor(shift);
                      final offdayBg = t.dangerSoft.withValues(alpha: 0.42);
                      final offdayBorder = t.danger.withValues(alpha: 0.55);
                      final offdayLabelTone = t.danger;
                      final isToday = DateUtils.isSameDay(day, DateTime.now());
                      final canInteract = inMonth && _isEditable;

                      if (!inMonth) {
                        return IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                compact ? 14 : 18,
                              ),
                            ),
                          ),
                        );
                      }

                      return GestureDetector(
                        onLongPress: canInteract
                            ? () => _toggleDateSelection(day)
                            : null,
                        onTap: canInteract
                            ? () => _toggleDateSelection(day)
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: EdgeInsets.all(cellPadding),
                          decoration: BoxDecoration(
                            color: !inMonth
                                ? t.surface2.withValues(alpha: 0.35)
                                : isOffday
                                ? offdayBg
                                : shift == null
                                ? t.surface2
                                : tone.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(
                              compact ? 14 : 18,
                            ),
                            border: Border.all(
                              color: selected
                                  ? t.primaryAccent
                                  : isToday
                                  ? t.info
                                  : isOffday
                                  ? offdayBorder
                                  : shift == null
                                  ? t.surface3
                                  : tone.withValues(alpha: 0.35),
                              width: selected ? 1.8 : 1,
                            ),
                          ),
                          child: Stack(
                            children: [
                              Align(
                                alignment: Alignment.topLeft,
                                child: Container(
                                  width: compact ? 24 : 28,
                                  height: compact ? 24 : 28,
                                  decoration: BoxDecoration(
                                    color: isOffday
                                        ? t.danger.withValues(alpha: 0.12)
                                        : t.textOnAccent,
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    '${day.day}',
                                    maxLines: 1,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: compact ? 11 : 13,
                                      color: t.textPrimary,
                                    ),
                                  ),
                                ),
                              ),
                              if (selected && inMonth)
                                Align(
                                  alignment: Alignment.topRight,
                                  child: Container(
                                    width: badgeSize,
                                    height: badgeSize,
                                    decoration: BoxDecoration(
                                      color: t.primaryAccent,
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    alignment: Alignment.center,
                                    child: Icon(
                                      Icons.check_rounded,
                                      size: compact ? 10 : 12,
                                      color: t.textOnAccent,
                                    ),
                                  ),
                                ),
                              if (inMonth && shift != null)
                                Align(
                                  alignment: Alignment.bottomCenter,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 1,
                                    ),
                                    child: FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        _shiftShortLabel(shift),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: isOffday
                                              ? offdayLabelTone
                                              : tone,
                                          fontSize: labelFont,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          _buildShiftLegend(),
        ],
      ),
    );
  }

  Widget _buildCommentsCard() {
    if (_comments.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Catatan Review',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 10),
          ..._comments.map((comment) {
            final role = '${comment['author_role'] ?? ''}';
            final isPromotor = role == 'promotor';
            final createdAt = DateTime.tryParse(
              '${comment['created_at'] ?? ''}',
            );
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isPromotor ? t.infoSoft : t.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.surface3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${comment['author_name'] ?? 'User'}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      _pill(
                        role.toUpperCase(),
                        isPromotor ? t.info : t.primaryAccent,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text('${comment['message'] ?? ''}'),
                  if (createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      DateFormat(
                        'dd MMM yyyy HH:mm',
                        'id_ID',
                      ).format(createdAt),
                      style: TextStyle(color: t.textSecondary, fontSize: 12),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    if (!_isEditable) {
      return SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          decoration: BoxDecoration(
            color: t.textOnAccent,
            border: Border(top: BorderSide(color: t.surface3)),
          ),
          child: FilledButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Kembali'),
          ),
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: t.textOnAccent,
          border: Border(top: BorderSide(color: t.surface3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_selectedDates.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => setState(() => _selectedDates.clear()),
                        child: const Text('Bersihkan Tanggal'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: _openBulkShiftPicker,
                        child: const Text('Pilih Shift'),
                      ),
                    ),
                  ],
                ),
              ),
            if (!_isComplete)
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: t.warningSoft.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.warning.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Perlu dilengkapi:',
                          style: TextStyle(
                            color: t.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        ..._collectValidationIssues(
                          includeDayCompleteness: true,
                        ).map(
                          (issue) => Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              '• $issue',
                              style: TextStyle(
                                color: t.textSecondary,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            FilledButton.icon(
              onPressed: _isSaving ? null : _openSubmitPreview,
              icon: _isSaving
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Preview Sebelum Kirim'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}
