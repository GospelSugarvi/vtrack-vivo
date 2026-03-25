import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

enum ShiftType { pagi, siang, fullday, libur }

class JadwalBulananPage extends StatefulWidget {
  const JadwalBulananPage({super.key});

  @override
  State<JadwalBulananPage> createState() => _JadwalBulananPageState();
}

class _JadwalBulananPageState extends State<JadwalBulananPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  DateTime _selectedMonth = DateTime.now();
  Map<DateTime, ShiftType> _schedules = {};
  bool _isLoading = false;
  String _status = 'draft'; // draft, submitted, approved, rejected
  String? _rejectionReason;

  @override
  void initState() {
    super.initState();
    _loadSchedule();
  }

  String get _monthYear => DateFormat('yyyy-MM').format(_selectedMonth);

  Future<void> _loadSchedule() async {
    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser!.id;

      final response = await _supabase
          .from('schedules')
          .select('schedule_date, shift_type, status, rejection_reason')
          .eq('promotor_id', userId)
          .eq('month_year', _monthYear);

      final Map<DateTime, ShiftType> loaded = {};
      String currentStatus = 'draft';
      String? reason;

      for (final item in response) {
        final date = DateTime.parse(item['schedule_date']);
        final shift = ShiftType.values
            .where((e) => e.name == item['shift_type'])
            .firstOrNull;
        if (shift == null) continue;
        loaded[date] = shift;
        currentStatus = item['status'] ?? 'draft';
        reason = item['rejection_reason'];
      }

      setState(() {
        _schedules = loaded;
        _status = currentStatus;
        _rejectionReason = reason;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading schedule: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importPreviousMonth() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Import Jadwal Bulan Lalu'),
        content: const Text(
          'Ini akan menghapus jadwal yang ada dan mengcopy jadwal bulan lalu. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser!.id;

      // Delete existing schedules for this month
      await _supabase
          .from('schedules')
          .delete()
          .eq('promotor_id', userId)
          .eq('month_year', _monthYear);

      // Call copy function
      final result = await _supabase.rpc(
        'copy_previous_month_schedule',
        params: {'p_promotor_id': userId, 'p_target_month': _monthYear},
      );

      if (mounted) {
        if (result['success'] == true) {
          await showSuccessDialog(
            context,
            title: 'Berhasil',
            message: result['message'] ?? 'Import jadwal berhasil.',
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Import gagal'),
              backgroundColor: t.danger,
            ),
          );
        }
      }

      await _loadSchedule();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: t.danger),
        );
      }
    }
  }

  Future<void> _submitSchedule() async {
    final daysInMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    ).day;

    if (_schedules.length != daysInMonth) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Jadwal belum lengkap. Isi semua tanggal terlebih dahulu.',
          ),
          backgroundColor: t.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser!.id;

      final result = await _supabase.rpc(
        'submit_monthly_schedule',
        params: {'p_promotor_id': userId, 'p_month_year': _monthYear},
      );

      if (mounted) {
        if (result['success'] == true) {
          await showSuccessDialog(
            context,
            title: 'Berhasil',
            message: result['message'] ?? 'Jadwal berhasil dikirim.',
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['message'] ?? 'Submit gagal'),
              backgroundColor: t.danger,
            ),
          );
        }
      }

      await _loadSchedule();
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: t.danger),
        );
      }
    }
  }

  void _setShift(DateTime date, ShiftType shift) {
    if (_status == 'submitted') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Jadwal sudah disubmit, tidak bisa diedit'),
        ),
      );
      return;
    }

    setState(() {
      _schedules[date] = shift;
    });

    _saveSchedule(date, shift);
  }

  Future<void> _saveSchedule(DateTime date, ShiftType shift) async {
    try {
      final userId = _supabase.auth.currentUser!.id;

      await _supabase.from('schedules').upsert({
        'promotor_id': userId,
        'schedule_date': DateFormat('yyyy-MM-dd').format(date),
        'shift_type': shift.name,
        'status': 'draft',
        'month_year': _monthYear,
      }, onConflict: 'promotor_id,schedule_date');
    } catch (e) {
      debugPrint('Error saving schedule: $e');
    }
  }

  void _showShiftPicker(DateTime date) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Pilih Shift - ${DateFormat('d MMM yyyy', 'id_ID').format(date)}',
              style: TextStyle(
                fontSize: AppTypeScale.bodyStrong,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.wb_sunny, color: t.warning),
              title: const Text('Pagi'),
              onTap: () {
                Navigator.pop(context);
                _setShift(date, ShiftType.pagi);
              },
            ),
            ListTile(
              leading: Icon(Icons.wb_twilight, color: t.info),
              title: const Text('Siang'),
              onTap: () {
                Navigator.pop(context);
                _setShift(date, ShiftType.siang);
              },
            ),
            ListTile(
              leading: Icon(Icons.schedule, color: t.success),
              title: const Text('Fullday'),
              onTap: () {
                Navigator.pop(context);
                _setShift(date, ShiftType.fullday);
              },
            ),
            ListTile(
              leading: Icon(Icons.block, color: t.danger),
              title: const Text('Libur'),
              onTap: () {
                Navigator.pop(context);
                _setShift(date, ShiftType.libur);
              },
            ),
          ],
        ),
      ),
    );
  }

  Color _getShiftColor(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return t.warning;
      case ShiftType.siang:
        return t.info;
      case ShiftType.fullday:
        return t.success;
      case ShiftType.libur:
        return t.danger;
    }
  }

  String _getShiftLabel(ShiftType shift) {
    switch (shift) {
      case ShiftType.pagi:
        return 'P';
      case ShiftType.siang:
        return 'S';
      case ShiftType.fullday:
        return 'FD';
      case ShiftType.libur:
        return 'L';
    }
  }

  Widget _buildStatusBadge() {
    Color bgColor;
    String text;
    IconData icon;

    switch (_status) {
      case 'submitted':
        bgColor = t.warning;
        text = 'Menunggu Approval';
        icon = Icons.pending;
        break;
      case 'approved':
        bgColor = t.success;
        text = 'Disetujui';
        icon = Icons.check_circle;
        break;
      case 'rejected':
        bgColor = t.danger;
        text = 'Ditolak';
        icon = Icons.cancel;
        break;
      default:
        bgColor = t.textSecondary;
        text = 'Draft';
        icon = Icons.edit;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: t.textOnAccent),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              color: t.textOnAccent,
              fontSize: AppTypeScale.support,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final daysInMonth = DateTime(
      _selectedMonth.year,
      _selectedMonth.month + 1,
      0,
    ).day;
    final scheduledDays = _schedules.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Jadwal Bulanan'),
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _loadSchedule),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.all(16),
                  color: t.infoSoft,
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left),
                                onPressed: () {
                                  setState(() {
                                    _selectedMonth = DateTime(
                                      _selectedMonth.year,
                                      _selectedMonth.month - 1,
                                    );
                                  });
                                  _loadSchedule();
                                },
                              ),
                              Text(
                                DateFormat(
                                  'MMMM yyyy',
                                  'id_ID',
                                ).format(_selectedMonth),
                                style: TextStyle(
                                  fontSize: AppTypeScale.title,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.chevron_right),
                                onPressed: () {
                                  setState(() {
                                    _selectedMonth = DateTime(
                                      _selectedMonth.year,
                                      _selectedMonth.month + 1,
                                    );
                                  });
                                  _loadSchedule();
                                },
                              ),
                            ],
                          ),
                          _buildStatusBadge(),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Terjadwal: $scheduledDays / $daysInMonth hari',
                        style: TextStyle(
                          color: scheduledDays == daysInMonth
                              ? t.success
                              : t.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (_rejectionReason != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: t.dangerSoft,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: t.danger.withValues(alpha: 0.25),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.error, color: t.danger, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Alasan Ditolak:',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: AppTypeScale.support,
                                      ),
                                    ),
                                    Text(
                                      _rejectionReason!,
                                      style: TextStyle(
                                        fontSize: AppTypeScale.support,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Calendar
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: TableCalendar(
                      firstDay: DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month,
                        1,
                      ),
                      lastDay: DateTime(
                        _selectedMonth.year,
                        _selectedMonth.month + 1,
                        0,
                      ),
                      focusedDay: _selectedMonth,
                      calendarFormat: CalendarFormat.month,
                      startingDayOfWeek: StartingDayOfWeek.monday,
                      headerVisible: false,
                      availableGestures: AvailableGestures.none,
                      calendarStyle: const CalendarStyle(
                        outsideDaysVisible: false,
                      ),
                      daysOfWeekHeight: 25,
                      rowHeight: 50,
                      calendarBuilders: CalendarBuilders(
                        defaultBuilder: (context, day, focusedDay) {
                          final shift = _schedules[day];

                          return GestureDetector(
                            onTap: () => _showShiftPicker(day),
                            child: Container(
                              margin: const EdgeInsets.all(2),
                              decoration: BoxDecoration(
                                color: shift != null
                                    ? _getShiftColor(shift)
                                    : t.surface3,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      '${day.day}',
                                      style: TextStyle(
                                        color: shift != null
                                            ? t.textOnAccent
                                            : t.textPrimary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: AppTypeScale.body,
                                      ),
                                    ),
                                    if (shift != null)
                                      Text(
                                        _getShiftLabel(shift),
                                        style: TextStyle(
                                          color: t.textOnAccent,
                                          fontSize: AppTypeScale.body,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),

                // Actions
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    boxShadow: [
                      BoxShadow(
                        color: t.textPrimary.withValues(alpha: 0.08),
                        blurRadius: 4,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_status == 'draft' || _status == 'rejected') ...[
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _importPreviousMonth,
                                icon: Icon(Icons.copy_all, size: 18),
                                label: const Text(
                                  'Import',
                                  style: TextStyle(fontSize: AppTypeScale.body),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: scheduledDays == daysInMonth
                                    ? _submitSchedule
                                    : null,
                                icon: Icon(Icons.send, size: 18),
                                label: const Text(
                                  'Submit',
                                  style: TextStyle(fontSize: AppTypeScale.body),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: t.success,
                                  foregroundColor: t.textOnAccent,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],
                      // Legend
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _buildLegend(t.warning, 'Pagi'),
                          const SizedBox(width: 12),
                          _buildLegend(t.info, 'Siang'),
                          const SizedBox(width: 12),
                          _buildLegend(t.success, 'Fullday'),
                          const SizedBox(width: 12),
                          _buildLegend(t.danger, 'Libur'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(fontSize: AppTypeScale.support)),
      ],
    );
  }
}
