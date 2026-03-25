import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:vtrack/core/utils/success_dialog.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  static const MethodChannel _exportChannel = MethodChannel('vtrack/export');
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _startDate;
  late DateTime _endDate;
  String _exportType = 'jadwal'; // Default ke jadwal sesuai request terakhir
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _applyMonthRange(_selectedMonth);
  }

  Map<String, dynamic> _safeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int _sumBrandUnits(Map<String, dynamic> data) {
    return _toInt(data['under_2m']) +
        _toInt(data['2m_4m']) +
        _toInt(data['4m_6m']) +
        _toInt(data['above_6m']);
  }

  String _formatTimeRange(dynamic start, dynamic end) {
    String normalize(dynamic value) {
      final raw = '$value';
      if (!raw.contains(':')) return raw;
      final parts = raw.split(':');
      if (parts.length < 2) return raw;
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    }

    return '${normalize(start)}-${normalize(end)}';
  }

  Future<Directory> _getExportDirectory() async {
    if (Platform.isAndroid) {
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!downloadDir.existsSync()) {
        downloadDir.createSync(recursive: true);
      }
      return downloadDir;
    }
    return getApplicationDocumentsDirectory();
  }

  Future<void> _notifyExportReady({
    required String path,
    required String title,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _exportChannel.invokeMethod('notifyExportReady', {
        'path': path,
        'title': title,
        'mimeType':
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      });
    } catch (_) {}
  }

  void _applyMonthRange(DateTime month) {
    final now = DateTime.now();
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = (month.year == now.year && month.month == now.month)
        ? DateTime(now.year, now.month, now.day)
        : DateTime(month.year, month.month + 1, 0);
    _selectedMonth = monthStart;
    _startDate = monthStart;
    _endDate = monthEnd;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Export Data'),
        backgroundColor: t.textSecondary,
        foregroundColor: t.textOnAccent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateRange(),
            const SizedBox(height: 20),
            _buildExportTypes(),
            const SizedBox(height: 24),
            _buildExportButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildDateRange() {
    final dateFormat = DateFormat('d MMM yyyy');
    final monthFormat = DateFormat('MMMM yyyy');

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rentang Tanggal',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypeScale.bodyStrong),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickMonth,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: t.divider),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_view_month, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bulan: ${monthFormat.format(_selectedMonth)}',
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(true),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: t.divider),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              dateFormat.format(_startDate),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('s/d'),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () => _pickDate(false),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: t.divider),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.calendar_today, size: 18),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              dateFormat.format(_endDate),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportTypes() {
    final types = [
      {
        'key': 'jadwal',
        'label': 'Laporan Jadwal',
        'icon': Icons.calendar_month,
        'color': t.info,
      },
      {
        'key': 'allbrand',
        'label': 'AllBrand',
        'icon': Icons.analytics,
        'color': t.warning,
      },
      {
        'key': 'sell_in',
        'label': 'Sell In',
        'icon': Icons.inventory_2,
        'color': t.info,
      },
      {
        'key': 'aktivitas',
        'label': 'Aktivitas Tim',
        'icon': Icons.checklist,
        'color': t.warning,
      },
    ];

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Jenis Export',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypeScale.bodyStrong),
            ),
            const SizedBox(height: 16),
            RadioGroup<String>(
              groupValue: _exportType,
              onChanged: (v) => setState(() => _exportType = v!),
              child: Column(
                children: types.map((t) {
                  return RadioListTile<String>(
                    value: t['key'] as String,
                    title: Row(
                      children: [
                        Icon(
                          t['icon'] as IconData,
                          color: t['color'] as Color,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Text(t['label'] as String),
                      ],
                    ),
                    contentPadding: EdgeInsets.zero,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isExporting ? null : _doExport,
        icon: _isExporting
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.download),
        label: Text(_isExporting ? 'Mendownload...' : 'Download Excel'),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: t.textSecondary,
          foregroundColor: t.textOnAccent,
        ),
      ),
    );
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(
        const Duration(days: 365),
      ), // Future date allowed for schedule
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          _startDate = picked;
        } else {
          _endDate = picked;
        }
        _selectedMonth = DateTime(_startDate.year, _startDate.month);
      });
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final months = List<DateTime>.generate(24, (index) {
      final date = DateTime(now.year, now.month - index, 1);
      return DateTime(date.year, date.month, 1);
    });

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      builder: (context) {
        final formatter = DateFormat('MMMM yyyy');
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: months
                .map(
                  (month) => ListTile(
                    title: Text(formatter.format(month)),
                    onTap: () => Navigator.pop(context, month),
                  ),
                )
                .toList(),
          ),
        );
      },
    );

    if (picked == null) return;
    setState(() {
      _applyMonthRange(picked);
    });
  }

  Future<void> _doExport() async {
    setState(() => _isExporting = true);
    try {
      if (_exportType == 'allbrand') {
        await _exportAllbrand();
        return;
      }

      final userId = _supabase.auth.currentUser!.id;
      final dateFormat = DateFormat('yyyy-MM-dd');
      final currentUser = await _supabase
          .from('users')
          .select('full_name, role')
          .eq('id', userId)
          .single();
      final currentRole = (currentUser['role'] ?? '').toString();

      final promotorIds = <String>{};
      final satorNameByPromotor = <String, String>{};

      if (currentRole == 'sator') {
        final storesRes = await _supabase
            .from('assignments_sator_store')
            .select('store_id')
            .eq('sator_id', userId)
            .eq('active', true);

        final storeIds = List<Map<String, dynamic>>.from(storesRes)
            .map((row) => row['store_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();

        if (storeIds.isEmpty) {
          throw Exception('Tidak ada toko yang di-handle.');
        }

        final promotorRes = await _supabase
            .from('assignments_promotor_store')
            .select('promotor_id')
            .inFilter('store_id', storeIds)
            .eq('active', true);

        for (final row in List<Map<String, dynamic>>.from(promotorRes)) {
          final promotorId = row['promotor_id']?.toString() ?? '';
          if (promotorId.isEmpty) continue;
          promotorIds.add(promotorId);
          satorNameByPromotor[promotorId] =
              (currentUser['full_name'] ?? 'SATOR').toString();
        }
      } else if (currentRole == 'spv') {
        final satorLinks = await _supabase
            .from('hierarchy_spv_sator')
            .select('sator_id')
            .eq('spv_id', userId)
            .eq('active', true);

        final satorIds = List<Map<String, dynamic>>.from(satorLinks)
            .map((row) => row['sator_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toList();

        if (satorIds.isEmpty) {
          throw Exception('Tidak ada SATOR di bawah SPV ini.');
        }

        final satorUsers = await _supabase
            .from('users')
            .select('id, full_name')
            .inFilter('id', satorIds);

        final satorNameById = {
          for (final row in List<Map<String, dynamic>>.from(satorUsers))
            row['id'].toString(): (row['full_name'] ?? 'SATOR').toString(),
        };

        final teamLinks = await _supabase
            .from('hierarchy_sator_promotor')
            .select('sator_id, promotor_id')
            .inFilter('sator_id', satorIds)
            .eq('active', true);

        for (final row in List<Map<String, dynamic>>.from(teamLinks)) {
          final promotorId = row['promotor_id']?.toString() ?? '';
          final satorId = row['sator_id']?.toString() ?? '';
          if (promotorId.isEmpty) continue;
          promotorIds.add(promotorId);
          satorNameByPromotor[promotorId] = satorNameById[satorId] ?? 'SATOR';
        }
      } else {
        throw Exception('Role ini belum didukung untuk export jadwal.');
      }

      if (promotorIds.isEmpty) {
        throw Exception('Tidak ada promotor untuk diexport.');
      }

      final promotorUsers = await _supabase
          .from('users')
          .select('id, full_name, area')
          .inFilter('id', promotorIds.toList());

      final storeAssignments = await _supabase
          .from('assignments_promotor_store')
          .select('promotor_id, stores(store_name)')
          .inFilter('promotor_id', promotorIds.toList())
          .eq('active', true);

      final schedules = await _supabase
          .from('schedules')
          .select('promotor_id, schedule_date, shift_type, status')
          .inFilter('promotor_id', promotorIds.toList())
          .gte('schedule_date', dateFormat.format(_startDate))
          .lte('schedule_date', dateFormat.format(_endDate))
          .order('schedule_date');

      if ((schedules as List).isEmpty) {
        throw Exception('Tidak ada data jadwal pada rentang tanggal ini.');
      }

      final promotorNameById = {
        for (final row in List<Map<String, dynamic>>.from(promotorUsers))
          row['id'].toString(): (row['full_name'] ?? 'Unknown').toString(),
      };
      final sortedPromotorIds = promotorIds.toList()
        ..sort(
          (a, b) =>
              (promotorNameById[a] ?? '').compareTo(promotorNameById[b] ?? ''),
        );
      final promotorAreaById = {
        for (final row in List<Map<String, dynamic>>.from(promotorUsers))
          row['id'].toString(): (row['area'] ?? 'default').toString(),
      };

      final relevantAreas = promotorAreaById.values
          .where((area) => area.trim().isNotEmpty)
          .toSet()
          .toList();
      if (!relevantAreas.contains('default')) {
        relevantAreas.add('default');
      }

      final shiftSettings = await _supabase
          .from('shift_settings')
          .select('shift_type, start_time, end_time, area')
          .inFilter('area', relevantAreas)
          .eq('active', true);

      final shiftSettingByArea = <String, Map<String, String>>{};
      for (final row in List<Map<String, dynamic>>.from(shiftSettings)) {
        final area = (row['area'] ?? 'default').toString();
        final shiftType = (row['shift_type'] ?? '').toString();
        if (shiftType.isEmpty) continue;
        shiftSettingByArea.putIfAbsent(area, () => <String, String>{});
        shiftSettingByArea[area]![shiftType] = _formatTimeRange(
          row['start_time'],
          row['end_time'],
        );
      }

      String resolveShiftTime(String promotorId, String shiftType) {
        if (shiftType.toLowerCase() == 'libur') return 'Libur';
        if (shiftType.toLowerCase() == 'fullday') {
          return shiftSettingByArea[promotorAreaById[promotorId]]?['fullday'] ??
              shiftSettingByArea['default']?['fullday'] ??
              '08:00-22:00';
        }
        return shiftSettingByArea[promotorAreaById[promotorId]]?[shiftType] ??
            shiftSettingByArea['default']?[shiftType] ??
            '-';
      }

      String legendTimeForShift(String shiftType) {
        if (shiftType == 'libur') return 'Libur';
        final times = sortedPromotorIds
            .map((promotorId) => resolveShiftTime(promotorId, shiftType))
            .where((time) => time.trim().isNotEmpty && time != '-')
            .toSet()
            .toList()
          ..sort();
        if (times.isEmpty) {
          return shiftType == 'fullday' ? '08:00-22:00' : '-';
        }
        return times.join(' / ');
      }

      final storeByPromotor = <String, Set<String>>{};
      for (final row in List<Map<String, dynamic>>.from(storeAssignments)) {
        final promotorId = row['promotor_id']?.toString() ?? '';
        final storeName = row['stores']?['store_name']?.toString() ?? '';
        if (promotorId.isEmpty || storeName.isEmpty) continue;
        storeByPromotor.putIfAbsent(promotorId, () => <String>{});
        storeByPromotor[promotorId]!.add(storeName);
      }

      final scheduleMap = <String, Map<String, String>>{};
      final statusByPromotor = <String, String>{};
      for (final row in List<Map<String, dynamic>>.from(schedules)) {
        final promotorId = row['promotor_id']?.toString() ?? '';
        final scheduleDate = row['schedule_date']?.toString() ?? '';
        if (promotorId.isEmpty || scheduleDate.isEmpty) continue;
        scheduleMap.putIfAbsent(promotorId, () => <String, String>{});
        final shiftType = (row['shift_type'] ?? '-').toString();
        final shiftTime = resolveShiftTime(promotorId, shiftType);
        scheduleMap[promotorId]![scheduleDate] =
            '${shiftType.toUpperCase()}\n$shiftTime';
        statusByPromotor[promotorId] = (row['status'] ?? '-')
            .toString()
            .toUpperCase();
      }

      final dates = <DateTime>[];
      for (
        DateTime date = DateTime(
          _startDate.year,
          _startDate.month,
          _startDate.day,
        );
        !date.isAfter(_endDate);
        date = date.add(const Duration(days: 1))
      ) {
        dates.add(date);
      }

      final xlsio.Workbook workbook = xlsio.Workbook();
      final xlsio.Worksheet sheet = workbook.worksheets[0];
      sheet.name = 'Jadwal Tim';

      sheet.getRangeByIndex(1, 1).setText('Nama Promotor');
      sheet.getRangeByIndex(1, 2).setText('Toko');
      sheet.getRangeByIndex(1, 3).setText('SATOR');
      sheet.getRangeByIndex(1, 4).setText('Status');
      for (int i = 0; i < dates.length; i++) {
        sheet
            .getRangeByIndex(1, i + 5)
            .setText(DateFormat('dd/MM').format(dates[i]));
      }

      final xlsio.Style headerStyle = workbook.styles.add('headerStyle');
      headerStyle.bold = true;
      sheet.getRangeByIndex(1, 1, 1, dates.length + 4).cellStyle = headerStyle;

      for (int i = 0; i < sortedPromotorIds.length; i++) {
        final promotorId = sortedPromotorIds[i];
        final rowIndex = i + 2;
        sheet
            .getRangeByIndex(rowIndex, 1)
            .setText(promotorNameById[promotorId] ?? 'Unknown');
        sheet
            .getRangeByIndex(rowIndex, 2)
            .setText((storeByPromotor[promotorId] ?? <String>{}).join(', '));
        sheet
            .getRangeByIndex(rowIndex, 3)
            .setText(satorNameByPromotor[promotorId] ?? '-');
        sheet
            .getRangeByIndex(rowIndex, 4)
            .setText(statusByPromotor[promotorId] ?? 'BELUM_KIRIM');
        for (int j = 0; j < dates.length; j++) {
          final dateKey = dateFormat.format(dates[j]);
          final cell = sheet.getRangeByIndex(rowIndex, j + 5);
          cell.setText(scheduleMap[promotorId]?[dateKey] ?? '');
          cell.cellStyle.wrapText = true;
        }
      }

      var footerRow = sortedPromotorIds.length + 3;
      sheet.getRangeByIndex(footerRow, 1).setText('Keterangan Shift');
      sheet.getRangeByIndex(footerRow, 1).cellStyle.bold = true;
      footerRow += 1;
      sheet.getRangeByIndex(footerRow, 1).setText('Shift');
      sheet.getRangeByIndex(footerRow, 2).setText('Jam');
      sheet.getRangeByIndex(footerRow, 1, footerRow, 2).cellStyle.bold = true;
      footerRow += 1;

      final legendRows = <Map<String, String>>[
        {'shift': 'PAGI', 'time': legendTimeForShift('pagi')},
        {'shift': 'SIANG', 'time': legendTimeForShift('siang')},
        {'shift': 'FULLDAY', 'time': legendTimeForShift('fullday')},
        {'shift': 'LIBUR', 'time': 'Libur'},
      ];

      for (final legend in legendRows) {
        sheet.getRangeByIndex(footerRow, 1).setText(legend['shift'] ?? '');
        sheet.getRangeByIndex(footerRow, 2).setText(legend['time'] ?? '');
        footerRow += 1;
      }

      for (int column = 1; column <= dates.length + 4; column++) {
        sheet.autoFitColumn(column);
      }

      final List<int> fileBytes = workbook.saveAsStream();
      workbook.dispose();

      final directory = await _getExportDirectory();
      final fileName =
          'Jadwal_Tim_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
      final file = File('${directory.path}/$fileName')
        ..createSync(recursive: true)
        ..writeAsBytesSync(fileBytes);
      await _notifyExportReady(
        path: file.path,
        title: 'Jadwal Tim siap dibuka',
      );

      if (mounted) {
        showErrorDialog(context, title: 'Gagal', message: Platform.isAndroid
                  ? '✅ File jadwal masuk folder Download'
                  : '✅ File jadwal tersimpan di: ${file.path}',);
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportAllbrand() async {
    final userId = _supabase.auth.currentUser!.id;
    final dateFormat = DateFormat('yyyy-MM-dd');
    final currentUser = await _supabase
        .from('users')
        .select('full_name, role')
        .eq('id', userId)
        .single();
    final currentRole = (currentUser['role'] ?? '').toString();

    final promotorIds = <String>{};
    final satorNameByPromotor = <String, String>{};

    if (currentRole == 'sator') {
      final storesRes = await _supabase
          .from('assignments_sator_store')
          .select('store_id')
          .eq('sator_id', userId)
          .eq('active', true);

      final storeIds = List<Map<String, dynamic>>.from(storesRes)
          .map((row) => row['store_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (storeIds.isEmpty) {
        throw Exception('Tidak ada toko yang di-handle.');
      }

      final promotorRes = await _supabase
          .from('assignments_promotor_store')
          .select('promotor_id')
          .inFilter('store_id', storeIds)
          .eq('active', true);

      for (final row in List<Map<String, dynamic>>.from(promotorRes)) {
        final promotorId = row['promotor_id']?.toString() ?? '';
        if (promotorId.isEmpty) continue;
        promotorIds.add(promotorId);
        satorNameByPromotor[promotorId] = (currentUser['full_name'] ?? 'SATOR')
            .toString();
      }
    } else if (currentRole == 'spv') {
      final satorLinks = await _supabase
          .from('hierarchy_spv_sator')
          .select('sator_id')
          .eq('spv_id', userId)
          .eq('active', true);

      final satorIds = List<Map<String, dynamic>>.from(satorLinks)
          .map((row) => row['sator_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      if (satorIds.isEmpty) {
        throw Exception('Tidak ada SATOR di bawah SPV ini.');
      }

      final satorUsers = await _supabase
          .from('users')
          .select('id, full_name')
          .inFilter('id', satorIds);
      final satorNameById = {
        for (final row in List<Map<String, dynamic>>.from(satorUsers))
          row['id'].toString(): (row['full_name'] ?? 'SATOR').toString(),
      };

      final teamLinks = await _supabase
          .from('hierarchy_sator_promotor')
          .select('sator_id, promotor_id')
          .inFilter('sator_id', satorIds)
          .eq('active', true);

      for (final row in List<Map<String, dynamic>>.from(teamLinks)) {
        final promotorId = row['promotor_id']?.toString() ?? '';
        final satorId = row['sator_id']?.toString() ?? '';
        if (promotorId.isEmpty) continue;
        promotorIds.add(promotorId);
        satorNameByPromotor[promotorId] = satorNameById[satorId] ?? 'SATOR';
      }
    } else {
      throw Exception('Role ini belum didukung untuk export AllBrand.');
    }

    if (promotorIds.isEmpty) {
      throw Exception('Tidak ada promotor untuk diexport.');
    }

    final promotorUsers = await _supabase
        .from('users')
        .select('id, full_name')
        .inFilter('id', promotorIds.toList());
    final promotorNameById = {
      for (final row in List<Map<String, dynamic>>.from(promotorUsers))
        row['id'].toString(): (row['full_name'] ?? 'Unknown').toString(),
    };

    final assignments = await _supabase
        .from('assignments_promotor_store')
        .select('promotor_id, store_id')
        .inFilter('promotor_id', promotorIds.toList())
        .eq('active', true);
    final storeIds = List<Map<String, dynamic>>.from(assignments)
        .map((row) => row['store_id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    final storesRaw = storeIds.isEmpty
        ? <dynamic>[]
        : await _supabase
              .from('stores')
              .select('id, store_name')
              .inFilter('id', storeIds);
    final storeNameById = {
      for (final row in List<Map<String, dynamic>>.from(storesRaw))
        row['id'].toString(): (row['store_name'] ?? '-').toString(),
    };

    final reports = await _supabase
        .from('allbrand_reports')
        .select(
          'promotor_id, store_id, report_date, created_at, updated_at, '
          'brand_data, brand_data_daily, leasing_sales, leasing_sales_daily, '
          'daily_total_units, cumulative_total_units, vivo_auto_data, '
          'vivo_promotor_count, notes, status',
        )
        .inFilter('promotor_id', promotorIds.toList())
        .gte('report_date', dateFormat.format(_startDate))
        .lte('report_date', dateFormat.format(_endDate))
        .order('report_date', ascending: false)
        .order('updated_at', ascending: false);

    final rows = List<Map<String, dynamic>>.from(reports);
    if (rows.isEmpty) {
      throw Exception('Tidak ada laporan AllBrand pada rentang tanggal ini.');
    }

    final salesRows = storeIds.isEmpty
        ? <dynamic>[]
        : await _supabase
              .from('sales_sell_out')
              .select('store_id, transaction_date')
              .inFilter('store_id', storeIds)
              .lte('transaction_date', dateFormat.format(_endDate));

    final vivoDailyByStoreDate = <String, int>{};
    final vivoCumulativeByStoreDate = <String, int>{};
    final salesByStore = <String, List<String>>{};
    for (final row in List<Map<String, dynamic>>.from(salesRows)) {
      final storeId = row['store_id']?.toString() ?? '';
      final transactionDate = row['transaction_date']?.toString() ?? '';
      if (storeId.isEmpty || transactionDate.isEmpty) continue;
      salesByStore.putIfAbsent(storeId, () => []);
      salesByStore[storeId]!.add(transactionDate);
      final dailyKey = '$storeId|$transactionDate';
      vivoDailyByStoreDate[dailyKey] =
          (vivoDailyByStoreDate[dailyKey] ?? 0) + 1;
    }
    for (final entry in salesByStore.entries) {
      final storeId = entry.key;
      final dates = entry.value..sort();
      var running = 0;
      final grouped = <String, int>{};
      for (final date in dates) {
        grouped[date] = (grouped[date] ?? 0) + 1;
      }
      final sortedDates = grouped.keys.toList()..sort();
      for (final date in sortedDates) {
        running += grouped[date] ?? 0;
        vivoCumulativeByStoreDate['$storeId|$date'] = running;
      }
    }

    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'AllBrand';

    final headers = [
      'Tanggal',
      'Nama Promotor',
      'Toko',
      'SATOR',
      'Status',
      'Edited',
      'VIVO Hari Ini',
      'VIVO Akumulasi',
      'Competitor Hari Ini',
      'Competitor Akumulasi',
      'Total Toko Hari Ini',
      'Total Toko Akumulasi',
      'MS VIVO %',
      'Jumlah Promotor VIVO',
      'Brand Harian',
      'Brand Akumulasi',
      'Leasing Harian',
      'Leasing Akumulasi',
      'Catatan',
    ];

    for (int i = 0; i < headers.length; i++) {
      sheet.getRangeByIndex(1, i + 1).setText(headers[i]);
    }
    final headerStyle = workbook.styles.add('headerStyleAllbrand');
    headerStyle.bold = true;
    sheet.getRangeByIndex(1, 1, 1, headers.length).cellStyle = headerStyle;

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final excelRow = i + 2;
      final promotorId = row['promotor_id']?.toString() ?? '';
      final storeId = row['store_id']?.toString() ?? '';
      final brandDaily = _safeMap(row['brand_data_daily'] ?? row['brand_data']);
      final brandCumulative = _safeMap(row['brand_data']);
      final leasingDaily = _safeMap(
        row['leasing_sales_daily'] ?? row['leasing_sales'],
      );
      final leasingCumulative = _safeMap(row['leasing_sales']);
      final reportDate = row['report_date']?.toString() ?? '';
      final vivoAuto = _safeMap(row['vivo_auto_data']);
      final vivoToday =
          vivoDailyByStoreDate['$storeId|$reportDate'] ??
          _toInt(vivoAuto['total']);
      final vivoCumulative =
          vivoCumulativeByStoreDate['$storeId|$reportDate'] ?? vivoToday;
      final competitorToday = _toInt(row['daily_total_units']) > 0
          ? _toInt(row['daily_total_units'])
          : brandDaily.values.fold<int>(
              0,
              (sum, item) => sum + _sumBrandUnits(_safeMap(item)),
            );
      final competitorCumulative = _toInt(row['cumulative_total_units']) > 0
          ? _toInt(row['cumulative_total_units'])
          : brandCumulative.values.fold<int>(
              0,
              (sum, item) => sum + _sumBrandUnits(_safeMap(item)),
            );
      final totalStoreToday = vivoToday + competitorToday;
      final totalStoreCumulative = vivoCumulative + competitorCumulative;
      final ms = totalStoreCumulative > 0
          ? (vivoCumulative * 100.0 / totalStoreCumulative)
          : 0.0;
      final createdAt = DateTime.tryParse('${row['created_at'] ?? ''}');
      final updatedAt = DateTime.tryParse('${row['updated_at'] ?? ''}');
      final edited =
          createdAt != null &&
          updatedAt != null &&
          updatedAt.isAfter(createdAt);

      final brandDailyText = brandDaily.entries
          .map(
            (entry) => '${entry.key}:${_sumBrandUnits(_safeMap(entry.value))}',
          )
          .join(' | ');
      final brandCumulativeText = brandCumulative.entries
          .map(
            (entry) => '${entry.key}:${_sumBrandUnits(_safeMap(entry.value))}',
          )
          .join(' | ');
      final leasingDailyText = leasingDaily.entries
          .map((entry) => '${entry.key}:${_toInt(entry.value)}')
          .join(' | ');
      final leasingCumulativeText = leasingCumulative.entries
          .map((entry) => '${entry.key}:${_toInt(entry.value)}')
          .join(' | ');

      final values = [
        '${row['report_date'] ?? '-'}',
        promotorNameById[promotorId] ?? 'Unknown',
        storeNameById[storeId] ?? '-',
        satorNameByPromotor[promotorId] ?? '-',
        '${row['status'] ?? '-'}',
        edited ? 'YA' : 'TIDAK',
        '$vivoToday',
        '$vivoCumulative',
        '$competitorToday',
        '$competitorCumulative',
        '$totalStoreToday',
        '$totalStoreCumulative',
        ms.toStringAsFixed(1),
        '${_toInt(row['vivo_promotor_count'])}',
        brandDailyText,
        brandCumulativeText,
        leasingDailyText,
        leasingCumulativeText,
        '${row['notes'] ?? ''}',
      ];

      for (int col = 0; col < values.length; col++) {
        sheet.getRangeByIndex(excelRow, col + 1).setText(values[col]);
      }
    }

    sheet
        .getRangeByIndex(1, 1, rows.length + 1, headers.length)
        .autoFitColumns();

    final fileBytes = workbook.saveAsStream();
    workbook.dispose();

    final directory = await _getExportDirectory();
    final fileName =
        'AllBrand_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    final file = File('${directory.path}/$fileName')
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes);
    await _notifyExportReady(path: file.path, title: 'AllBrand siap dibuka');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Platform.isAndroid
                ? '✅ File AllBrand masuk folder Download'
                : '✅ File AllBrand tersimpan di: ${file.path}',
          ),
        ),
      );
    }
  }
}
