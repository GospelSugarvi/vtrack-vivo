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
  DateTime _nextMonthStart(DateTime month) => DateTime(month.year, month.month + 1, 1);

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

    final statuses = rows
        .map((row) => '${row['status'] ?? 'draft'}')
        .toSet();

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
        .select('month_year, schedule_date, status, updated_at, rejection_reason')
        .eq('promotor_id', userId)
        .order('schedule_date', ascending: false)
        .order('updated_at', ascending: false);

    final monthly = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final scheduleDate = DateTime.tryParse('${row['schedule_date'] ?? ''}');
      final monthYear = '${row['month_year'] ?? ''}'.trim().isNotEmpty
          ? '${row['month_year']}'
          : (scheduleDate == null ? '' : DateFormat('yyyy-MM').format(scheduleDate));
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
      (monthly[monthYear]!['statuses'] as Set<String>)
          .add('${row['status'] ?? 'draft'}');
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

    _history = monthly.values.map((item) {
      final statuses = item['statuses'] as Set<String>;
      return <String, dynamic>{
        'month_year': item['month_year'],
        'status': deriveStatus(statuses),
        'updated_at': item['updated_at'],
        'total_days': item['total_days'],
        'rejection_reason': item['rejection_reason'],
      };
    }).toList()
      ..sort((a, b) => '${b['month_year']}'.compareTo('${a['month_year']}'));
  }

  Future<void> _pickNewMonth() async {
    final month = await _showMonthPickerSheet();
    if (month == null || !mounted) return;

    final monthYear = DateFormat('yyyy-MM').format(month);
    final historyItem = _history.where((row) => '${row['month_year']}' == monthYear).firstOrNull;
    final status = historyItem == null ? 'draft' : '${historyItem['status'] ?? 'draft'}';

    final shouldReload = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => JadwalBulananComposerPage(
          month: month,
          initialStatus: status,
        ),
      ),
    );

    if (shouldReload == true) {
      _activeMonth = month;
      await _loadPage();
    }
  }

  Future<DateTime?> _showMonthPickerSheet() async {
    final years = List<int>.generate(4, (index) => DateTime.now().year - 1 + index);
    final monthNames = const <String>[
      'Januari',
      'Februari',
      'Maret',
      'April',
      'Mei',
      'Juni',
      'Juli',
      'Agustus',
      'September',
      'Oktober',
      'November',
      'Desember',
    ];
    var selectedYear = _activeMonth.year;

    return showModalBottomSheet<DateTime>(
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
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: t.surface3,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Pilih bulan',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 12),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: years.map((year) {
                          final active = year == selectedYear;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              label: Text('$year'),
                              selected: active,
                              onSelected: (_) => setSheetState(() => selectedYear = year),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 14),
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 12,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 2.4,
                      ),
                      itemBuilder: (context, index) {
                        return OutlinedButton(
                          onPressed: () => Navigator.of(context).pop(
                            DateTime(selectedYear, index + 1),
                          ),
                          child: Text(monthNames[index]),
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
        .select('schedule_date, shift_type, status, rejection_reason, month_year')
        .eq('promotor_id', userId)
        .order('schedule_date');
    final scheduleRows = List<Map<String, dynamic>>.from(allScheduleRows).where((row) {
      final rowMonthYear = '${row['month_year'] ?? ''}';
      final rowDate = DateTime.tryParse('${row['schedule_date'] ?? ''}');
      if (rowMonthYear == DateFormat('yyyy-MM').format(month)) return true;
      if (rowDate == null) return false;
      return !rowDate.isBefore(monthStart) && rowDate.isBefore(nextMonth);
    }).toList();
    final commentRows = await _supabase
        .from('schedule_review_comments')
        .select('author_name, author_role, message, created_at')
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
      appBar: AppBar(
        title: Text(_promotorName),
        actions: [
          IconButton(
            onPressed: _loadPage,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
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
              final updatedAt = DateTime.tryParse('${item['updated_at'] ?? ''}');
              final rejectionReason = item['rejection_reason']?.toString();

              return InkWell(
                onTap: () => _openHistory(item),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                              DateFormat('MMMM yyyy', 'id_ID').format(monthDate),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                            if (updatedAt != null) ...[
                              const SizedBox(height: 2),
                              Text(
                                DateFormat('dd MMM yyyy', 'id_ID').format(updatedAt),
                                style: TextStyle(color: t.textSecondary, fontSize: 12),
                              ),
                            ],
                            if (rejectionReason != null && rejectionReason.trim().isNotEmpty) ...[
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
                      const SizedBox(width: 8),
                      _buildPill(_statusLabel(status), tone),
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
  final _commentController = TextEditingController();

  final Map<DateTime, ShiftType> _schedules = <DateTime, ShiftType>{};
  final Set<DateTime> _selectedDates = <DateTime>{};
  final List<Map<String, dynamic>> _comments = <Map<String, dynamic>>[];
  final Map<String, String> _shiftTimeByType = <String, String>{
    'pagi': '08:00-16:00',
    'siang': '13:00-21:00',
    'fullday': '08:00-22:00',
    'libur': 'Libur',
  };

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSendingComment = false;
  bool _hasLoadedScheduleData = false;
  bool _selectionMode = false;
  late DateTime _month;
  late String _status;
  String? _rejectionReason;
  String _currentUserName = '';
  String _currentUserArea = 'default';

  FieldThemeTokens get t => context.fieldTokens;
  String get _monthYear => DateFormat('yyyy-MM').format(_month);
  String get _monthLabel => DateFormat('MMMM yyyy', 'id_ID').format(_month);
  int get _daysInMonth => DateTime(_month.year, _month.month + 1, 0).day;
  int get _filledDays => _schedules.length;
  bool get _isComplete => _filledDays == _daysInMonth;
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
    _commentController.dispose();
    super.dispose();
  }

  DateTime _normalize(DateTime date) => DateTime(date.year, date.month, date.day);
  DateTime _monthStart(DateTime month) => DateTime(month.year, month.month, 1);
  DateTime _nextMonthStart(DateTime month) => DateTime(month.year, month.month + 1, 1);

  Future<void> _loadPage() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      await _loadCurrentUser();
      _applyScheduleRows(widget.prefetchedScheduleRows, allowEmpty: true);
      _applyCommentRows(widget.prefetchedComments);
      await Future.wait([
        _loadShiftSettings(),
        _loadSchedule(),
        _loadComments(),
      ]);
    } catch (e) {
      _showMessage('Gagal memuat kalender jadwal. $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCurrentUser() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Session user tidak ditemukan.');

    final profile = await _supabase
        .from('users')
        .select('full_name, area')
        .eq('id', userId)
        .single();

    _currentUserName = '${profile['full_name'] ?? 'Promotor'}';
    final area = '${profile['area'] ?? ''}'.trim();
    _currentUserArea = area.isEmpty ? 'default' : area;
  }

  Future<void> _loadShiftSettings() async {
    final rows = await _supabase
        .from('shift_settings')
        .select('shift_type, start_time, end_time, area')
        .inFilter('area', <String>[_currentUserArea, 'default'])
        .eq('active', true);

    String formatTime(dynamic value) {
      final raw = '$value';
      if (!raw.contains(':')) return raw;
      final parts = raw.split(':');
      if (parts.length < 2) return raw;
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }

    final localRows = <String, Map<String, dynamic>>{};
    final defaultRows = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      final shiftType = '${row['shift_type'] ?? ''}';
      final area = '${row['area'] ?? ''}';
      if (shiftType.isEmpty) continue;
      if (area == _currentUserArea) {
        localRows[shiftType] = row;
      } else if (area == 'default') {
        defaultRows[shiftType] = row;
      }
    }

    for (final shift in <String>['pagi', 'siang', 'fullday']) {
      final row = localRows[shift] ?? defaultRows[shift];
      if (row == null) continue;
      _shiftTimeByType[shift] =
          '${formatTime(row['start_time'])}-${formatTime(row['end_time'])}';
    }
  }

  Future<void> _loadSchedule() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final monthStart = _monthStart(_month);
    final nextMonth = _nextMonthStart(_month);

    final rows = await _supabase
        .from('schedules')
        .select('schedule_date, shift_type, status, rejection_reason, month_year')
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
        .select('author_name, author_role, message, created_at')
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
      _status = 'draft';
      _rejectionReason = null;
      _selectedDates.clear();
      _hasLoadedScheduleData = false;
      return;
    }

    if (rows.isEmpty && allowEmpty) {
      return;
    }

    _schedules.clear();
    var nextStatus = widget.initialStatus;
    String? nextReason;

    for (final row in rows) {
      final date = DateTime.tryParse('${row['schedule_date'] ?? ''}');
      final shiftName = '${row['shift_type'] ?? ''}';
      if (date == null || shiftName.isEmpty) continue;
      final shift = ShiftType.values.where((e) => e.name == shiftName).firstOrNull;
      if (shift == null) continue;
      _schedules[_normalize(date)] = shift;
      nextStatus = '${row['status'] ?? nextStatus}';
      nextReason = row['rejection_reason']?.toString();
    }

    if (rows.isNotEmpty) {
      _status = nextStatus;
      _rejectionReason = nextReason;
      _hasLoadedScheduleData = true;
    }
    _selectedDates.clear();
    _selectionMode = false;
  }

  void _applyCommentRows(List<Map<String, dynamic>> rows) {
    _comments
      ..clear()
      ..addAll(rows);
  }

  void _applyShiftToSelected(ShiftType shift) {
    if (!_isEditable || _selectedDates.isEmpty) return;
    final dates = _selectedDates.toList()..sort();
    setState(() {
      for (final date in dates) {
        _schedules[date] = shift;
      }
      _status = 'draft';
      _rejectionReason = null;
      _selectedDates.clear();
      _selectionMode = false;
    });
  }

  Future<void> _submitSchedule() async {
    if (!_isEditable || !_isComplete) return;

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    setState(() => _isSaving = true);
    try {
      final payload = _schedules.entries
          .map((entry) => <String, dynamic>{
                'promotor_id': userId,
                'schedule_date': DateFormat('yyyy-MM-dd').format(entry.key),
                'shift_type': entry.value.name,
                'status': 'draft',
                'month_year': _monthYear,
                'rejection_reason': null,
              })
          .toList()
        ..sort(
          (a, b) => '${a['schedule_date']}'.compareTo('${b['schedule_date']}'),
        );

      await _supabase.from('schedules').upsert(
        payload,
        onConflict: 'promotor_id,schedule_date',
      );

      final result = await _supabase.rpc(
        'submit_monthly_schedule',
        params: {
          'p_promotor_id': userId,
          'p_month_year': _monthYear,
        },
      );

      final rows = List<Map<String, dynamic>>.from(result ?? const []);
      final first = rows.isNotEmpty ? rows.first : const <String, dynamic>{};
      if (first['success'] != true) {
        _showMessage('${first['message'] ?? 'Gagal kirim jadwal.'}', isError: true);
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

  Future<void> _sendComment() async {
    final userId = _supabase.auth.currentUser?.id;
    final message = _commentController.text.trim();
    if (userId == null || message.isEmpty) return;

    setState(() => _isSendingComment = true);
    try {
      await _supabase.from('schedule_review_comments').insert({
        'promotor_id': userId,
        'month_year': _monthYear,
        'author_id': userId,
        'author_name': _currentUserName,
        'author_role': 'promotor',
        'message': message,
      });
      _commentController.clear();
      await _loadComments();
      if (mounted) setState(() {});
    } catch (e) {
      _showMessage('Gagal kirim komentar. $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSendingComment = false);
    }
  }

  void _toggleDate(DateTime date) {
    if (!_isEditable) return;
    final normalized = _normalize(date);
    setState(() {
      _selectionMode = true;
      if (_selectedDates.contains(normalized)) {
        _selectedDates.remove(normalized);
      } else {
        _selectedDates.add(normalized);
      }
      if (_selectedDates.isEmpty) {
        _selectionMode = false;
      }
    });
  }

  void _startSelection(DateTime date) {
    if (!_isEditable) return;
    final normalized = _normalize(date);
    setState(() {
      _selectionMode = true;
      _selectedDates
        ..clear()
        ..add(normalized);
    });
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
          final time = shift == ShiftType.libur ? null : _shiftTimeByType[shift.name];
          return Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: tone.withValues(alpha: 0.2)),
            ),
            child: Text(
              time == null ? _shiftLabel(shift) : '${_shiftLabel(shift)} • $time',
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(
        title: Text(_monthLabel),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              children: [
                _buildStatusHeader(),
                const SizedBox(height: 12),
                if (_isEditable) _buildShiftToolbar(),
                if (_isEditable) const SizedBox(height: 12),
                _buildCalendarCard(),
                if (_isEditable) ...[
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
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _pill(_statusLabel(_status), tone),
            ],
          ),
          if (_rejectionReason != null && _rejectionReason!.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              'Catatan penolakan: $_rejectionReason',
              style: TextStyle(
                color: t.danger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShiftToolbar() {
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
                child: Text(
                  _selectedDates.isEmpty
                      ? 'Pilih tanggal dulu'
                      : '${_selectedDates.length} tanggal dipilih',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (_selectedDates.isNotEmpty)
                TextButton(
                  onPressed: () => setState(() {
                    _selectedDates.clear();
                    _selectionMode = false;
                  }),
                  child: const Text('Bersihkan'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ShiftType.values.map((shift) {
                final tone = _shiftColor(shift);
                final enabled = _selectedDates.isNotEmpty;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: enabled ? () => _applyShiftToSelected(shift) : null,
                    borderRadius: BorderRadius.circular(14),
                    child: Opacity(
                      opacity: enabled ? 1 : 0.45,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: tone.withValues(alpha: 0.22)),
                        ),
                        child: Text(
                          _shiftLabel(shift),
                          style: TextStyle(
                            color: tone,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCard() {
    final cells = _monthCells();
    const weekdays = ['Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu'];

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
          Row(
            children: [
              const Text(
                'Kalender',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
              ),
              const Spacer(),
              if (_isEditable && !_selectionMode)
                Text(
                  'Tahan tanggal',
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
                      final selected = _selectedDates.contains(_normalize(day));
                      final tone = shift == null ? t.surface3 : _shiftColor(shift);
                      final isToday = DateUtils.isSameDay(day, DateTime.now());
                      final canInteract = inMonth && _isEditable;

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

                      return GestureDetector(
                        onLongPress: canInteract ? () => _startSelection(day) : null,
                        onTap: canInteract
                            ? () {
                                if (_selectionMode) {
                                  _toggleDate(day);
                                }
                              }
                            : null,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: EdgeInsets.all(cellPadding),
                          decoration: BoxDecoration(
                            color: !inMonth
                                ? t.surface2.withValues(alpha: 0.35)
                                : shift == null
                                    ? t.surface2
                                    : tone.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(compact ? 14 : 18),
                            border: Border.all(
                              color: selected
                                  ? t.primaryAccent
                                  : isToday
                                      ? t.info
                                      : shift == null
                                          ? t.surface3
                                          : tone.withValues(alpha: 0.35),
                              width: selected ? 1.8 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
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
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: compact ? 11 : 13,
                                        color: t.textPrimary,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  if (selected && inMonth)
                                    Container(
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
                                ],
                              ),
                              const SizedBox(height: 1),
                              if (inMonth && shift != null)
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
                                            style: TextStyle(
                                              color: tone,
                                              fontSize: labelFont,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
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
            'Catatan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          if (_comments.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._comments.map((comment) {
              final role = '${comment['author_role'] ?? ''}';
              final isPromotor = role == 'promotor';
              final createdAt = DateTime.tryParse('${comment['created_at'] ?? ''}');
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
                        _pill(role.toUpperCase(), isPromotor ? t.info : t.primaryAccent),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text('${comment['message'] ?? ''}'),
                    if (createdAt != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        DateFormat('dd MMM yyyy HH:mm', 'id_ID').format(createdAt),
                        style: TextStyle(color: t.textSecondary, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              );
            }),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: _commentController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              hintText: 'Tulis komentar untuk SATOR',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isSendingComment ? null : _sendComment,
              icon: _isSendingComment
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
              label: const Text('Kirim komentar'),
            ),
          ),
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
        child: FilledButton.icon(
          onPressed: _isSaving || !_isComplete ? null : _submitSchedule,
          icon: _isSaving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send_rounded),
          label: const FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('Kirim ke SATOR'),
          ),
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
