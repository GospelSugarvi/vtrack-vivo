import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/foundation/field_theme_extensions.dart';
import '../../../../ui/promotor/promotor.dart';

class SpvAttendanceMonitorPage extends StatefulWidget {
  const SpvAttendanceMonitorPage({super.key});

  @override
  State<SpvAttendanceMonitorPage> createState() =>
      _SpvAttendanceMonitorPageState();
}

class _SpvAttendanceMonitorPageState extends State<SpvAttendanceMonitorPage> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  List<Map<String, dynamic>> _tabs = [];
  List<Map<String, dynamic>> _rows = [];
  int _selectedTabIndex = 0;

  FieldThemeTokens get t => context.fieldTokens;
  Color get _s1 => t.surface1;
  Color get _s3 => t.surface3;
  Color get _gold => t.primaryAccent;
  Color get _goldDim => t.primaryAccentSoft;
  Color get _cream => t.textPrimary;
  Color get _cream2 => t.textSecondary;
  Color get _muted => t.textMuted;
  Color get _green => t.success;
  Color get _greenDim => t.successSoft;
  Color get _red => t.danger;
  Color get _redDim => t.dangerSoft;
  Color get _amber => t.warning;
  Color get _blue => t.info;

  TextStyle _display({
    double size = 28,
    FontWeight weight = FontWeight.w800,
    Color? color,
  }) =>
      PromotorText.display(size: size, weight: weight, color: color ?? _cream);

  TextStyle _outfit({
    double size = 12,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = 0,
  }) => PromotorText.outfit(
    size: size,
    weight: weight,
    color: color ?? _cream,
    letterSpacing: letterSpacing,
  );

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final spvId = _supabase.auth.currentUser?.id;
      if (spvId == null) return;
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);

      final satorLinks = await _supabase
          .from('hierarchy_spv_sator')
          .select('sator_id')
          .eq('spv_id', spvId)
          .eq('active', true);
      final satorIds = List<Map<String, dynamic>>.from(satorLinks)
          .map((row) => '${row['sator_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toList();
      final satorUsers = satorIds.isEmpty
          ? const []
          : await _supabase
                .from('users')
                .select('id, full_name')
                .inFilter('id', satorIds);
      final satorNameById = {
        for (final row in List<Map<String, dynamic>>.from(satorUsers))
          '${row['id'] ?? ''}': '${row['full_name'] ?? 'SATOR'}'.trim().isEmpty
              ? 'SATOR'
              : '${row['full_name'] ?? 'SATOR'}',
      };
      final sators = satorIds
          .map((id) => {'id': id, 'name': satorNameById[id] ?? 'SATOR'})
          .toList();

      if (satorIds.isEmpty) {
        _setTabsAndRows([], []);
        return;
      }

      final promotorLinks = await _supabase
          .from('hierarchy_sator_promotor')
          .select('sator_id, promotor_id')
          .inFilter('sator_id', satorIds)
          .eq('active', true);
      final promotorLinkRows = List<Map<String, dynamic>>.from(promotorLinks);
      final promotorIds = promotorLinkRows
          .map((row) => '${row['promotor_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      if (promotorIds.isEmpty) {
        _setTabsAndRows(sators, []);
        return;
      }

      final userRows = await _supabase
          .from('users')
          .select('id, full_name, area, deleted_at')
          .inFilter('id', promotorIds);
      final users = {
        for (final row in List<Map<String, dynamic>>.from(userRows))
          '${row['id'] ?? ''}': Map<String, dynamic>.from(row),
      };

      final assignmentRows = await _supabase
          .from('assignments_promotor_store')
          .select('promotor_id, created_at, stores(store_name)')
          .inFilter('promotor_id', promotorIds)
          .eq('active', true)
          .order('created_at', ascending: false);
      final latestStoreByPromotor = <String, String>{};
      for (final row in List<Map<String, dynamic>>.from(assignmentRows)) {
        final promotorId = '${row['promotor_id'] ?? ''}';
        if (promotorId.isEmpty ||
            latestStoreByPromotor.containsKey(promotorId)) {
          continue;
        }
        latestStoreByPromotor[promotorId] =
            '${row['stores']?['store_name'] ?? '-'}';
      }

      final scheduleRows = await _supabase
          .from('schedules')
          .select('promotor_id, shift_type, status, updated_at, created_at')
          .inFilter('promotor_id', promotorIds)
          .eq('schedule_date', today)
          .order('updated_at', ascending: false);
      final latestScheduleByPromotor = <String, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(scheduleRows)) {
        final promotorId = '${row['promotor_id'] ?? ''}';
        if (promotorId.isEmpty ||
            latestScheduleByPromotor.containsKey(promotorId)) {
          continue;
        }
        latestScheduleByPromotor[promotorId] = row;
      }

      final attendanceRows = await _supabase
          .from('attendance')
          .select('*')
          .inFilter('user_id', promotorIds)
          .eq('attendance_date', today)
          .order('created_at', ascending: false);
      final latestAttendanceByPromotor = <String, Map<String, dynamic>>{};
      for (final row in List<Map<String, dynamic>>.from(attendanceRows)) {
        final promotorId = '${row['user_id'] ?? ''}';
        if (promotorId.isEmpty ||
            latestAttendanceByPromotor.containsKey(promotorId)) {
          continue;
        }
        latestAttendanceByPromotor[promotorId] = row;
      }

      final shiftRows = await _supabase
          .from('shift_settings')
          .select('shift_type, start_time, end_time, area')
          .eq('active', true);
      final shiftSettings = List<Map<String, dynamic>>.from(shiftRows);

      final builtRows = <Map<String, dynamic>>[];
      for (final link in promotorLinkRows) {
        final satorId = '${link['sator_id'] ?? ''}';
        final promotorId = '${link['promotor_id'] ?? ''}';
        final user = users[promotorId];
        if (satorId.isEmpty || promotorId.isEmpty || user == null) continue;
        if (user['deleted_at'] != null) continue;

        final area = '${user['area'] ?? 'default'}';
        final schedule = latestScheduleByPromotor[promotorId];
        final attendance = latestAttendanceByPromotor[promotorId];
        final shiftType = '${schedule?['shift_type'] ?? ''}';
        final scheduleStatus = '${schedule?['status'] ?? ''}';
        final shift = _resolveShiftSetting(
          shiftSettings: shiftSettings,
          shiftType: shiftType,
          area: area,
        );
        final shiftStart = _parseTime(shift?['start_time']);
        final clockIn = DateTime.tryParse('${attendance?['clock_in'] ?? ''}');
        final mainAttendanceStatus =
            '${attendance?['main_attendance_status'] ?? ''}';
        final reportCategory = '${attendance?['report_category'] ?? ''}';
        final attendanceCategory = reportCategory.isNotEmpty
            ? reportCategory
            : (mainAttendanceStatus == 'late'
                  ? 'late'
                  : (clockIn != null ? 'normal' : ''));
        final statusKey = _statusKey(
          clockIn: clockIn,
          attendanceCategory: attendanceCategory,
          shiftType: shiftType,
          scheduleExists: schedule != null,
          scheduleStatus: scheduleStatus,
          shiftStart: shiftStart,
          now: now,
        );

        builtRows.add({
          'sator_id': satorId,
          'sator_name': satorNameById[satorId] ?? 'SATOR',
          'promotor_id': promotorId,
          'promotor_name': '${user['full_name'] ?? 'Promotor'}',
          'store_name': latestStoreByPromotor[promotorId] ?? '-',
          'shift_label': _shiftLabel(shiftType, shift, schedule != null),
          'status_key': statusKey,
          'status_reason': _statusReason(
            statusKey: statusKey,
            attendanceCategory: attendanceCategory,
            shiftStart: shiftStart,
          ),
          'attendance_category': attendanceCategory,
          'clock_in_time': clockIn == null
              ? ''
              : DateFormat('HH:mm').format(clockIn.toLocal()),
          'schedule_status': scheduleStatus,
          'sort_order': _statusOrder(statusKey, attendanceCategory),
        });
      }

      builtRows.sort((a, b) {
        final orderCompare = (a['sort_order'] as int).compareTo(
          b['sort_order'] as int,
        );
        if (orderCompare != 0) return orderCompare;
        return '${a['promotor_name']}'.compareTo('${b['promotor_name']}');
      });

      _setTabsAndRows(sators, builtRows);
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _setTabsAndRows(
    List<Map<String, dynamic>> tabs,
    List<Map<String, dynamic>> rows,
  ) {
    if (!mounted) return;
    setState(() {
      _tabs = tabs;
      _rows = rows;
      _selectedTabIndex = tabs.isEmpty
          ? 0
          : _selectedTabIndex.clamp(0, tabs.length - 1);
      _isLoading = false;
    });
  }

  Map<String, dynamic>? _resolveShiftSetting({
    required List<Map<String, dynamic>> shiftSettings,
    required String shiftType,
    required String area,
  }) {
    if (shiftType.isEmpty || shiftType == 'libur') return null;
    for (final row in shiftSettings) {
      if ('${row['shift_type']}' == shiftType && '${row['area']}' == area) {
        return row;
      }
    }
    for (final row in shiftSettings) {
      if ('${row['shift_type']}' == shiftType &&
          '${row['area']}' == 'default') {
        return row;
      }
    }
    return null;
  }

  TimeOfDay? _parseTime(dynamic value) {
    final raw = '${value ?? ''}';
    if (raw.isEmpty) return null;
    final parts = raw.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String _statusKey({
    required DateTime? clockIn,
    required String attendanceCategory,
    required String shiftType,
    required bool scheduleExists,
    required String scheduleStatus,
    required TimeOfDay? shiftStart,
    required DateTime now,
  }) {
    if (clockIn != null) return 'checked_in';
    if ({
      'travel',
      'special_permission',
      'system_issue',
      'sick',
      'leave',
      'management_holiday',
    }.contains(attendanceCategory)) {
      return 'exception';
    }
    if (shiftType == 'libur') return 'off';
    if (!scheduleExists) return 'no_schedule';
    if (scheduleStatus != 'approved') return 'schedule_pending';
    if (shiftStart != null) {
      final shiftDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        shiftStart.hour,
        shiftStart.minute,
      );
      if (now.isBefore(shiftDateTime)) return 'waiting_shift';
    }
    return 'no_report';
  }

  String _shiftLabel(
    String shiftType,
    Map<String, dynamic>? shift,
    bool hasSchedule,
  ) {
    if (!hasSchedule) return 'Belum ada jadwal';
    if (shiftType == 'libur') return 'Libur';
    if (shift == null) {
      return shiftType.isEmpty ? 'Belum ada jadwal' : shiftType;
    }
    final start = _formatTime('${shift['start_time'] ?? ''}');
    final end = _formatTime('${shift['end_time'] ?? ''}');
    return '${_cap(shiftType)} $start-$end';
  }

  String _statusReason({
    required String statusKey,
    required String attendanceCategory,
    required TimeOfDay? shiftStart,
  }) {
    switch (statusKey) {
      case 'checked_in':
        return attendanceCategory == 'late'
            ? 'Sudah masuk · terlambat'
            : 'Sudah masuk kerja';
      case 'exception':
        return _attendanceCategoryLabel(attendanceCategory);
      case 'off':
        return 'Libur hari ini';
      case 'no_schedule':
        return 'Jadwal hari ini belum ada';
      case 'schedule_pending':
        return 'Jadwal belum approved';
      case 'waiting_shift':
        if (shiftStart == null) return 'Menunggu shift';
        return 'Masuk ${shiftStart.hour.toString().padLeft(2, '0')}:${shiftStart.minute.toString().padLeft(2, '0')}';
      case 'no_report':
      default:
        return 'Belum ada laporan masuk kerja';
    }
  }

  int _statusOrder(String statusKey, String attendanceCategory) {
    if (statusKey == 'checked_in' && attendanceCategory != 'late') return 0;
    if (statusKey == 'checked_in' && attendanceCategory == 'late') return 1;
    if (statusKey == 'waiting_shift') return 2;
    if (statusKey == 'exception') return 3;
    if (statusKey == 'off') return 4;
    if (statusKey == 'no_report') return 5;
    if (statusKey == 'schedule_pending') return 6;
    if (statusKey == 'no_schedule') return 7;
    return 8;
  }

  String _formatTime(String raw) {
    final parts = raw.split(':');
    if (parts.length < 2) return '--:--';
    return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
  }

  String _cap(String raw) {
    if (raw.isEmpty) return raw;
    return raw[0].toUpperCase() + raw.substring(1);
  }

  List<Map<String, dynamic>> _rowsForActiveTab() {
    if (_tabs.isEmpty) return const [];
    final satorId = '${_tabs[_selectedTabIndex]['id']}';
    return _rows.where((row) => '${row['sator_id']}' == satorId).toList();
  }

  int _countByStatus(List<Map<String, dynamic>> rows, String key) =>
      rows.where((row) => '${row['status_key']}' == key).length;

  @override
  Widget build(BuildContext context) {
    final rows = _rowsForActiveTab();
    final checkedIn = _countByStatus(rows, 'checked_in');
    final late = rows
        .where((row) => '${row['status_key']}' == 'checked_in')
        .where((row) => '${row['attendance_category']}' == 'late')
        .length;
    final noReport = _countByStatus(rows, 'no_report');
    final waitingShift = _countByStatus(rows, 'waiting_shift');
    final exceptions = _countByStatus(rows, 'exception');
    final working = rows
        .where(
          (row) => !{
            'off',
            'no_schedule',
            'schedule_pending',
          }.contains('${row['status_key']}'),
        )
        .length;
    final progress = working > 0 ? checkedIn / working : 0.0;

    return Scaffold(
      backgroundColor: t.shellBackground,
      appBar: AppBar(
        backgroundColor: t.shellBackground,
        foregroundColor: _cream,
        title: const Text('Monitor Masuk Kerja'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gold))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _gold,
              backgroundColor: _s1,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  if (_tabs.isNotEmpty) ...[
                    Text(
                      'Pilih SATOR',
                      style: _outfit(
                        size: 10,
                        weight: FontWeight.w700,
                        color: _muted,
                        letterSpacing: 0.32,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _tabs.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final tab = _tabs[index];
                          final active = index == _selectedTabIndex;
                          final count = _rows
                              .where(
                                (row) => '${row['sator_id']}' == '${tab['id']}',
                              )
                              .length;
                          return _buildSatorTabChip(
                            label: '${tab['name'] ?? 'SATOR'}',
                            count: count,
                            active: active,
                            onTap: () =>
                                setState(() => _selectedTabIndex = index),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                    decoration: BoxDecoration(
                      color: _s1,
                      border: Border.all(color: _s3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                'Masuk kerja hari ini',
                                style: _outfit(
                                  size: 12,
                                  weight: FontWeight.w800,
                                  color: _cream,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: _greenDim,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _green.withValues(alpha: 0.2),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$checkedIn/$working',
                                    style: _display(
                                      size: 16,
                                      weight: FontWeight.w800,
                                      color: _green,
                                    ),
                                  ),
                                  Text(
                                    'sudah masuk',
                                    style: _outfit(size: 7, color: _green),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: progress.clamp(0, 1),
                            minHeight: 5,
                            backgroundColor: _s3,
                            valueColor: AlwaysStoppedAnimation(
                              progress >= 1
                                  ? _green
                                  : (progress >= 0.7 ? _gold : _amber),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: _buildAttendanceStat(
                                label: 'Belum Lapor',
                                value: '$noReport',
                                color: noReport > 0 ? _red : _green,
                                bg: noReport > 0 ? _redDim : _greenDim,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildAttendanceStat(
                                label: 'Terlambat',
                                value: '$late',
                                color: late > 0 ? _amber : _green,
                                bg: late > 0 ? _goldDim : _greenDim,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildAttendanceStat(
                                label: 'Shift Berikut',
                                value: '$waitingShift',
                                color: _blue,
                                bg: _blue.withValues(alpha: 0.10),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _buildAttendanceStat(
                                label: 'Exception',
                                value: '$exceptions',
                                color: exceptions > 0 ? _amber : _green,
                                bg: exceptions > 0 ? _goldDim : _greenDim,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Semua Promotor',
                    style: _outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: _cream2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (rows.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: _s1,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: _s3),
                      ),
                      child: Text(
                        'Belum ada promotor di SATOR ini.',
                        style: _outfit(size: 10, color: _muted),
                      ),
                    )
                  else
                    ...rows.map(_buildPromotorRow),
                ],
              ),
            ),
    );
  }

  Widget _buildAttendanceStat({
    required String label,
    required String value,
    required Color color,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(9, 8, 9, 7),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 7, color: color)),
          const SizedBox(height: 2),
          Text(
            value,
            style: _display(size: 13, weight: FontWeight.w800, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildSatorTabChip({
    required String label,
    required int count,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _goldDim : _s1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: active ? _gold.withValues(alpha: 0.32) : _s3,
          ),
          boxShadow: active
              ? [
                  BoxShadow(
                    color: _gold.withValues(alpha: 0.12),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: _outfit(
                size: 10,
                weight: FontWeight.w800,
                color: active ? _gold : _cream2,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: active ? _gold.withValues(alpha: 0.12) : _s3,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$count',
                style: _outfit(
                  size: 8,
                  weight: FontWeight.w800,
                  color: active ? _gold : _muted,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromotorRow(Map<String, dynamic> row) {
    final statusKey = '${row['status_key'] ?? ''}';
    final tone = _attendanceTone(statusKey);
    final badge = _attendanceStatusLabel(
      statusKey,
      category: '${row['attendance_category'] ?? ''}',
    );
    final extra = <String>[
      '${row['store_name'] ?? '-'}',
      '${row['shift_label'] ?? '-'}',
      if ('${row['clock_in_time'] ?? ''}'.isNotEmpty)
        'Clock in ${row['clock_in_time']}',
    ].where((e) => e.trim().isNotEmpty && e.trim() != '-').join(' · ');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${row['promotor_name'] ?? '-'}',
                  style: _outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: _cream,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  extra,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _outfit(size: 8, color: _muted),
                ),
                const SizedBox(height: 2),
                Text(
                  '${row['status_reason'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _outfit(size: 8, color: tone),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            decoration: BoxDecoration(
              color: tone.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: tone.withValues(alpha: 0.16)),
            ),
            child: Text(
              badge,
              style: _outfit(size: 7, color: tone, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  Color _attendanceTone(String statusKey) {
    switch (statusKey) {
      case 'checked_in':
        return _green;
      case 'waiting_shift':
        return _blue;
      case 'exception':
        return _amber;
      case 'schedule_pending':
      case 'no_schedule':
        return _gold;
      case 'no_report':
      default:
        return _red;
    }
  }

  String _attendanceStatusLabel(String statusKey, {String category = ''}) {
    if (statusKey == 'checked_in' && category == 'late') return 'Terlambat';
    switch (statusKey) {
      case 'checked_in':
        return 'Masuk';
      case 'waiting_shift':
        return 'Menunggu Shift';
      case 'exception':
        return _attendanceCategoryLabel(category);
      case 'schedule_pending':
        return 'Jadwal Pending';
      case 'no_schedule':
        return 'Tanpa Jadwal';
      case 'no_report':
      default:
        return 'Belum Lapor';
    }
  }

  String _attendanceCategoryLabel(String value) {
    switch (value) {
      case 'late':
        return 'Terlambat';
      case 'travel':
        return 'Dinas';
      case 'special_permission':
        return 'Izin Atasan';
      case 'system_issue':
        return 'Kendala Sistem';
      case 'sick':
        return 'Sakit';
      case 'leave':
        return 'Izin';
      case 'management_holiday':
        return 'Libur';
      case 'normal':
        return 'Masuk';
      default:
        return 'Exception';
    }
  }
}
