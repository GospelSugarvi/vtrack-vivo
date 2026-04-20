import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:screenshot/screenshot.dart';

import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

import 'package:vtrack/core/utils/device_image_saver.dart';
import 'package:vtrack/core/utils/success_dialog.dart';
import 'package:vtrack/core/utils/cloudinary_upload_helper.dart';
import 'package:vtrack/features/chat/repository/chat_repository.dart';

import '../widgets/sator_promotor_achievement_export_widget.dart';

class ExportPage extends StatefulWidget {
  const ExportPage({super.key});

  @override
  State<ExportPage> createState() => _ExportPageState();
}

class _ExportPageState extends State<ExportPage> {
  static const List<String> _allbrandRangeKeys = <String>[
    'under_2m',
    '2m_4m',
    '4m_6m',
    'above_6m',
  ];
  static const List<String> _allbrandBrandOrder = <String>[
    'Samsung',
    'OPPO',
    'Realme',
    'Xiaomi',
    'Infinix',
    'Tecno',
  ];
  static const List<String> _allbrandLeasingOrder = <String>[
    'HCI',
    'Kredivo',
    'FIF',
    'Indodana',
    'Kredit Plus',
    'Home Credit',
    'VAST Finance',
  ];

  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _chatRepository = ChatRepository();
  final _previewCaptureController = ScreenshotController();
  static const MethodChannel _exportChannel = MethodChannel('vtrack/export');
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  late DateTime _startDate;
  late DateTime _endDate;
  String _exportType = 'jadwal'; // Default ke jadwal sesuai request terakhir
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    if (_exportType == 'jadwal') {
      _applyScheduleMonthRange(_selectedMonth);
    } else {
      _applyAllbrandMonthRange(_selectedMonth);
    }
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

  void _applyAllbrandMonthRange(DateTime month) {
    final now = DateTime.now();
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = (month.year == now.year && month.month == now.month)
        ? DateTime(now.year, now.month, now.day)
        : DateTime(month.year, month.month + 1, 0);
    _selectedMonth = monthStart;
    _startDate = monthStart;
    _endDate = monthEnd;
  }

  void _applyScheduleMonthRange(DateTime month) {
    final monthStart = DateTime(month.year, month.month, 1);
    final monthEnd = DateTime(month.year, month.month + 1, 0);
    _selectedMonth = monthStart;
    _startDate = monthStart;
    _endDate = monthEnd;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Export Data'),
        backgroundColor: t.surface1,
        foregroundColor: t.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPeriodSelector(),
            const SizedBox(height: 20),
            _buildExportTypes(),
            const SizedBox(height: 24),
            _buildExportButton(),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodSelector() {
    if (_exportType == 'jadwal') {
      return _buildJadwalMonthSelector();
    }
    if (_exportType == 'achievement_report') {
      return _buildAchievementDateSelector();
    }
    return _buildAllbrandDateRange();
  }

  Widget _buildJadwalMonthSelector() {
    final monthFormat = DateFormat('MMMM yyyy');
    return Card(
      color: t.surface1,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Periode Bulanan',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTypeScale.bodyStrong,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickMonth,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surface2,
                  border: Border.all(color: t.surface3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month, size: 18),
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
            const SizedBox(height: 10),
            Text(
              'Export jadwal otomatis mengambil tanggal 1 sampai akhir bulan.',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAllbrandDateRange() {
    final dateFormat = DateFormat('d MMM yyyy');
    final monthFormat = DateFormat('MMMM yyyy');

    return Card(
      color: t.surface1,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Rentang Tanggal',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTypeScale.bodyStrong,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickMonth,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surface2,
                  border: Border.all(color: t.surface3),
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
                        color: t.surface2,
                        border: Border.all(color: t.surface3),
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
                        color: t.surface2,
                        border: Border.all(color: t.surface3),
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

  Widget _buildAchievementDateSelector() {
    final dateFormat = DateFormat('d MMMM yyyy', 'id_ID');
    final periodStart = DateTime(_endDate.year, _endDate.month, 1);

    return Card(
      color: t.surface1,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tanggal Data',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTypeScale.bodyStrong,
              ),
            ),
            const SizedBox(height: 16),
            InkWell(
              onTap: _pickAchievementDate,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surface2,
                  border: Border.all(color: t.surface3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.calendar_month_rounded, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        dateFormat.format(_endDate),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Laporan dihitung month-to-date dari ${dateFormat.format(periodStart)} sampai ${dateFormat.format(_endDate)}.',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
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
        'key': 'achievement_report',
        'label': 'Laporan Pencapaian Promotor',
        'icon': Icons.image_outlined,
        'color': t.success,
      },
      {
        'key': 'allbrand',
        'label': 'AllBrand',
        'icon': Icons.analytics,
        'color': t.warning,
      },
    ];

    return Card(
      color: t.surface1,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Jenis Export',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTypeScale.bodyStrong,
              ),
            ),
            const SizedBox(height: 16),
            RadioGroup<String>(
              groupValue: _exportType,
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _exportType = v;
                  if (_exportType == 'jadwal') {
                    _applyScheduleMonthRange(_selectedMonth);
                  } else if (_exportType == 'achievement_report') {
                    _endDate = DateTime.now();
                    _selectedMonth = DateTime(_endDate.year, _endDate.month);
                    _startDate = DateTime(_endDate.year, _endDate.month, 1);
                  } else {
                    _applyAllbrandMonthRange(_selectedMonth);
                  }
                });
              },
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
                        Expanded(
                          child: Text(
                            t['label'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    contentPadding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
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
    final isImageExport = _exportType == 'achievement_report';
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
            : Icon(isImageExport ? Icons.visibility_rounded : Icons.download),
        label: Text(
          _isExporting
              ? (isImageExport ? 'Membuat preview...' : 'Mendownload...')
              : (isImageExport ? 'Buat Preview Gambar' : 'Download Excel'),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 16),
          backgroundColor: t.primaryAccent,
          disabledBackgroundColor: t.surface3,
          foregroundColor: t.textOnAccent,
          disabledForegroundColor: t.textMuted,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
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

  Future<void> _pickAchievementDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _endDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('id', 'ID'),
    );
    if (picked == null) return;
    setState(() {
      _endDate = DateTime(picked.year, picked.month, picked.day);
      _selectedMonth = DateTime(picked.year, picked.month);
      _startDate = DateTime(picked.year, picked.month, 1);
    });
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
      if (_exportType == 'jadwal') {
        _applyScheduleMonthRange(picked);
      } else if (_exportType == 'achievement_report') {
        final lastDay = DateTime(picked.year, picked.month + 1, 0);
        final now = DateTime.now();
        final safeDay = picked.year == now.year && picked.month == now.month
            ? DateTime(picked.year, picked.month, now.day)
            : lastDay;
        _selectedMonth = DateTime(picked.year, picked.month);
        _startDate = DateTime(picked.year, picked.month, 1);
        _endDate = safeDay;
      } else {
        _applyAllbrandMonthRange(picked);
      }
    });
  }

  Future<void> _doExport() async {
    setState(() => _isExporting = true);
    try {
      switch (_exportType) {
        case 'achievement_report':
          await _exportPromotorAchievementReport();
          return;
        case 'allbrand':
          await _exportAllbrand();
          return;
        case 'jadwal':
          await _exportJadwal();
          return;
        default:
          throw Exception('Jenis export belum didukung.');
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _exportPromotorAchievementReport() async {
    try {
      final snapshot = await _buildPromotorAchievementSnapshot();
      if (!mounted || !context.mounted) return;
      await _showPromotorAchievementPreview(snapshot);
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa membuat laporan pencapaian promotor: $e',
      );
    }
  }

  Future<_PromotorAchievementExportSnapshot>
  _buildPromotorAchievementSnapshot() async {
    final satorId = _supabase.auth.currentUser?.id;
    if (satorId == null) {
      throw Exception('User tidak terautentikasi.');
    }

    final dataDate = DateTime(_endDate.year, _endDate.month, _endDate.day);
    final monthStart = DateTime(dataDate.year, dataDate.month, 1);
    final startIso = DateFormat('yyyy-MM-dd').format(monthStart);
    final endIso = DateFormat('yyyy-MM-dd').format(dataDate);

    final hierarchyRows = _parseMapList(
      await _supabase
          .from('hierarchy_sator_promotor')
          .select('promotor_id')
          .eq('sator_id', satorId)
          .eq('active', true),
    );
    final promotorIds = hierarchyRows
        .map((row) => '${row['promotor_id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toList();

    if (promotorIds.isEmpty) {
      throw Exception('Belum ada promotor aktif di bawah Sator ini.');
    }

    final periodRow = await _supabase
        .from('target_periods')
        .select('id')
        .lte('start_date', endIso)
        .gte('end_date', endIso)
        .isFilter('deleted_at', null)
        .order('start_date', ascending: false)
        .limit(1)
        .maybeSingle();
    final periodId = '${periodRow?['id'] ?? ''}'.trim();

    final baseResults = await Future.wait<dynamic>([
      _supabase
          .from('users')
          .select('id, full_name, nickname, promotor_type, promotor_status')
          .eq('id', satorId)
          .maybeSingle(),
      _supabase
          .from('users')
          .select('id, full_name, nickname, promotor_type, promotor_status')
          .inFilter('id', promotorIds),
      _supabase
          .from('assignments_promotor_store')
          .select('promotor_id, created_at, stores!left(store_name)')
          .inFilter('promotor_id', promotorIds)
          .eq('active', true)
          .order('created_at', ascending: false),
      _supabase
          .from('sales_sell_out')
          .select(
            'promotor_id, transaction_date, is_chip_sale, price_at_transaction, '
            'product_variants!left(products!left(id, model_name))',
          )
          .inFilter('promotor_id', promotorIds)
          .isFilter('deleted_at', null)
          .gte('transaction_date', startIso)
          .lte('transaction_date', endIso),
      _supabase
          .from('vast_applications')
          .select(
            'promotor_id, application_date, outcome_status, lifecycle_status, product_variant_id',
          )
          .inFilter('promotor_id', promotorIds)
          .isFilter('deleted_at', null)
          .gte('application_date', startIso)
          .lte('application_date', endIso),
      periodId.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : _supabase
                .from('user_targets')
                .select(
                  'user_id, target_omzet, target_sell_out, target_fokus_total, '
                  'target_special, target_fokus_detail, target_special_detail, target_vast',
                )
                .eq('period_id', periodId)
                .inFilter('user_id', promotorIds),
    ]);

    final satorProfile = _safeMap(baseResults[0]);
    final userRows = _parseMapList(baseResults[1]);
    final assignmentRows = _parseMapList(baseResults[2]);
    final salesRows = _parseMapList(baseResults[3]);
    final vastRows = _parseMapList(baseResults[4]);
    final targetRows = _parseMapList(baseResults[5]);

    final focusBundleIds = <String>{};
    final specialBundleIds = <String>{};
    for (final row in targetRows) {
      focusBundleIds.addAll(_safeMap(row['target_fokus_detail']).keys);
      specialBundleIds.addAll(_safeMap(row['target_special_detail']).keys);
    }

    final extraResults = await Future.wait<dynamic>([
      focusBundleIds.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : _supabase
                .from('fokus_bundles')
                .select('id, bundle_name, product_types')
                .inFilter('id', focusBundleIds.toList()),
      specialBundleIds.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : _supabase
                .from('special_focus_bundles')
                .select('id, bundle_name')
                .inFilter('id', specialBundleIds.toList()),
      specialBundleIds.isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : _supabase
                .from('special_focus_bundle_products')
                .select('bundle_id, product_id')
                .inFilter('bundle_id', specialBundleIds.toList()),
      vastRows.where((row) => row['product_variant_id'] != null).isEmpty
          ? Future.value(const <Map<String, dynamic>>[])
          : _supabase
                .from('product_variants')
                .select('id, srp')
                .inFilter(
                  'id',
                  vastRows
                      .map((row) => '${row['product_variant_id'] ?? ''}'.trim())
                      .where((id) => id.isNotEmpty)
                      .toSet()
                      .toList(),
                ),
    ]);

    final focusBundles = _parseMapList(extraResults[0]);
    final specialBundles = _parseMapList(extraResults[1]);
    final specialBundleProducts = _parseMapList(extraResults[2]);
    final variantRows = _parseMapList(extraResults[3]);

    final userMap = {for (final row in userRows) '${row['id'] ?? ''}': row};
    final storeMap = <String, String>{};
    for (final row in assignmentRows) {
      final promotorId = '${row['promotor_id'] ?? ''}'.trim();
      if (promotorId.isEmpty || storeMap.containsKey(promotorId)) continue;
      storeMap[promotorId] =
          _safeMap(row['stores'])['store_name']?.toString() ?? 'Belum ada toko';
    }
    final targetMap = {
      for (final row in targetRows) '${row['user_id'] ?? ''}': row,
    };
    final focusBundleMap = {
      for (final row in focusBundles) '${row['id'] ?? ''}': row,
    };
    final specialBundleMap = {
      for (final row in specialBundles) '${row['id'] ?? ''}': row,
    };
    final specialBundleProductMap = <String, Set<String>>{};
    for (final row in specialBundleProducts) {
      final bundleId = '${row['bundle_id'] ?? ''}'.trim();
      final productId = '${row['product_id'] ?? ''}'.trim();
      if (bundleId.isEmpty || productId.isEmpty) continue;
      specialBundleProductMap
          .putIfAbsent(bundleId, () => <String>{})
          .add(productId);
    }
    final variantSrpMap = {
      for (final row in variantRows)
        '${row['id'] ?? ''}': _toExcelNumber(row['srp']),
    };

    final exportRows = <_PromotorAchievementExportRow>[];
    for (final promotorId in promotorIds) {
      final user = userMap[promotorId] ?? const <String, dynamic>{};
      final targetMeta = targetMap[promotorId] ?? const <String, dynamic>{};
      final promotorSales = salesRows
          .where((row) => '${row['promotor_id'] ?? ''}' == promotorId)
          .toList();
      final promotorVast = vastRows
          .where((row) => '${row['promotor_id'] ?? ''}' == promotorId)
          .toList();

      final freshSales = promotorSales
          .where((row) => row['is_chip_sale'] != true)
          .toList();
      final selloutActual = freshSales.fold<num>(
        0,
        (sum, row) => sum + _toExcelNumber(row['price_at_transaction']),
      );
      final selloutTarget = _resolveSelloutTarget(targetMeta);
      final selloutPct = selloutTarget > 0
          ? (selloutActual / selloutTarget) * 100
          : 0;

      final focusDetail = _safeMap(targetMeta['target_fokus_detail']);
      final specialDetail = _safeMap(targetMeta['target_special_detail']);
      final effectiveFocusModels = <String>{};
      for (final bundleId in focusDetail.keys) {
        final focusBundle = _safeMap(focusBundleMap[bundleId]);
        final productTypes = (focusBundle['product_types'] as List? ?? const [])
            .map((item) => '$item'.trim())
            .where((item) => item.isNotEmpty);
        effectiveFocusModels.addAll(productTypes);
      }
      final effectiveSpecialProductIds = <String>{};
      for (final bundleId in specialDetail.keys) {
        effectiveSpecialProductIds.addAll(
          specialBundleProductMap[bundleId] ?? const <String>{},
        );
      }
      final focusActual = freshSales.where((sale) {
        final product = _safeMap(
          _safeMap(sale['product_variants'])['products'],
        );
        final productId = '${product['id'] ?? ''}'.trim();
        final modelName = '${product['model_name'] ?? ''}'.trim();
        return effectiveSpecialProductIds.contains(productId) ||
            effectiveFocusModels.contains(modelName);
      }).length;
      final focusTarget = _resolveFocusTarget(targetMeta);
      final focusPct = focusTarget > 0 ? (focusActual / focusTarget) * 100 : 0;

      final specials = <_PromotorAchievementSpecialMetric>[];
      final specialKeys = specialDetail.keys.toList()
        ..sort((a, b) {
          final left = '${specialBundleMap[a]?['bundle_name'] ?? ''}';
          final right = '${specialBundleMap[b]?['bundle_name'] ?? ''}';
          return left.compareTo(right);
        });
      for (final bundleId in specialKeys) {
        final targetQty = _toExcelNumber(specialDetail[bundleId]).toInt();
        final productIds =
            specialBundleProductMap[bundleId] ?? const <String>{};
        final actualQty = freshSales.where((sale) {
          final product = _safeMap(
            _safeMap(sale['product_variants'])['products'],
          );
          final productId = '${product['id'] ?? ''}'.trim();
          return productIds.contains(productId);
        }).length;
        specials.add(
          _PromotorAchievementSpecialMetric(
            label:
                '${specialBundleMap[bundleId]?['bundle_name'] ?? 'Tipe Khusus'}',
            target: targetQty,
            actual: actualQty,
            pct: targetQty > 0 ? (actualQty / targetQty) * 100 : 0,
          ),
        );
      }

      final vastTarget = _toExcelNumber(targetMeta['target_vast']).toInt();
      final vastInput = promotorVast.length;
      final vastPending = promotorVast.where(_isPendingVast).length;
      final vastReject = promotorVast.where(_isRejectVast).length;
      final vastClosingAmount = promotorVast
          .where(_isClosingVast)
          .fold<num>(
            0,
            (sum, row) =>
                sum +
                (variantSrpMap['${row['product_variant_id'] ?? ''}'] ?? 0),
          );

      exportRows.add(
        _PromotorAchievementExportRow(
          no: exportRows.length + 1,
          storeName: storeMap[promotorId] ?? 'Belum ada toko',
          promotorName: _resolveDisplayName(user),
          statusLabel: _resolvePromotorStatus(user),
          selloutTarget: selloutTarget,
          selloutActual: selloutActual,
          selloutPct: selloutPct,
          selloutGap: selloutActual - selloutTarget,
          focusTarget: focusTarget,
          focusActual: focusActual,
          focusPct: focusPct,
          specials: specials,
          vastTargetInput: vastTarget,
          vastTotalInput: vastInput,
          vastPct: vastTarget > 0 ? (vastInput / vastTarget) * 100 : 0,
          vastPending: vastPending,
          vastReject: vastReject,
          vastClosingAmount: vastClosingAmount,
          totalUnit: freshSales.length,
        ),
      );
    }

    exportRows.sort((a, b) {
      final storeCompare = a.storeName.compareTo(b.storeName);
      if (storeCompare != 0) return storeCompare;
      return a.promotorName.compareTo(b.promotorName);
    });
    for (var i = 0; i < exportRows.length; i++) {
      exportRows[i] = exportRows[i].copyWith(no: i + 1);
    }

    final totals = <String, dynamic>{
      'promotor_count': exportRows.length,
      'sellout_actual': exportRows.fold<num>(
        0,
        (sum, row) => sum + row.selloutActual,
      ),
      'vast_input': exportRows.fold<int>(
        0,
        (sum, row) => sum + row.vastTotalInput,
      ),
      'vast_amount': exportRows.fold<num>(
        0,
        (sum, row) => sum + row.vastClosingAmount,
      ),
    };

    final satorFullName = (satorProfile['full_name'] ?? '').toString().trim();

    return _PromotorAchievementExportSnapshot(
      satorName: satorFullName.isNotEmpty
          ? satorFullName
          : _resolveDisplayName(satorProfile, fallback: 'Sator'),
      dataDate: dataDate,
      monthStart: monthStart,
      rows: exportRows,
      totals: totals,
    );
  }

  num _resolveSelloutTarget(Map<String, dynamic> meta) {
    final omzet = _toExcelNumber(meta['target_omzet']);
    if (omzet > 0) return omzet;
    return _toExcelNumber(meta['target_sell_out']);
  }

  int _resolveFocusTarget(Map<String, dynamic> meta) {
    final explicit = _toExcelNumber(meta['target_fokus_total']).toInt();
    if (explicit > 0) return explicit;
    return _sumJsonValues(meta['target_fokus_detail']) +
        _sumJsonValues(meta['target_special_detail']);
  }

  int _sumJsonValues(dynamic value) {
    final map = _safeMap(value);
    var total = 0;
    for (final item in map.values) {
      total += _toExcelNumber(item).toInt();
    }
    return total;
  }

  String _resolveDisplayName(
    Map<String, dynamic> row, {
    String fallback = 'Promotor',
  }) {
    final nickname = '${row['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    final fullName = '${row['full_name'] ?? ''}'.trim();
    return fullName.isEmpty ? fallback : fullName;
  }

  String _resolvePromotorStatus(Map<String, dynamic> row) {
    final raw =
        '${row['promotor_status'] ?? row['promotor_type'] ?? 'training'}'
            .trim()
            .toLowerCase();
    if (raw.isEmpty) return 'Training';
    return raw[0].toUpperCase() + raw.substring(1);
  }

  bool _isClosingVast(Map<String, dynamic> row) {
    final outcome = '${row['outcome_status'] ?? ''}'.trim().toLowerCase();
    final lifecycle = '${row['lifecycle_status'] ?? ''}'.trim().toLowerCase();
    return outcome == 'acc' ||
        lifecycle == 'closed_direct' ||
        lifecycle == 'closed_follow_up';
  }

  bool _isPendingVast(Map<String, dynamic> row) {
    final outcome = '${row['outcome_status'] ?? ''}'.trim().toLowerCase();
    final lifecycle = '${row['lifecycle_status'] ?? ''}'.trim().toLowerCase();
    return outcome == 'pending' || lifecycle == 'approved_pending';
  }

  bool _isRejectVast(Map<String, dynamic> row) {
    final outcome = '${row['outcome_status'] ?? ''}'.trim().toLowerCase();
    final lifecycle = '${row['lifecycle_status'] ?? ''}'.trim().toLowerCase();
    return outcome == 'reject' || lifecycle == 'rejected';
  }

  Future<void> _showPromotorAchievementPreview(
    _PromotorAchievementExportSnapshot snapshot,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 18,
          ),
          backgroundColor: t.surface1,
          child: SizedBox(
            width: math.min(MediaQuery.of(dialogContext).size.width - 24, 980),
            height: math.min(
              MediaQuery.of(dialogContext).size.height - 36,
              760,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Preview Laporan Pencapaian',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  Text(
                    'Periksa tanggal dan isi laporan sebelum download atau kirim ke grup.',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: t.textMutedStrong,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.surface3),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(10),
                        child: FittedBox(
                          fit: BoxFit.fitWidth,
                          alignment: Alignment.topCenter,
                          child: _buildPromotorAchievementExportWidget(
                            snapshot,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            await _savePromotorAchievementImage(snapshot);
                          },
                          icon: const Icon(Icons.download_outlined, size: 18),
                          label: const Text(
                            'Download',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            Navigator.of(dialogContext).pop();
                            await _sharePromotorAchievementToTeam(snapshot);
                          },
                          icon: const Icon(Icons.send_rounded, size: 18),
                          label: const Text(
                            'Bagikan',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                            textStyle: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _savePromotorAchievementImage(
    _PromotorAchievementExportSnapshot snapshot,
  ) async {
    try {
      final fileName = snapshot.fileNameBase;
      var success = false;
      await _runBlockingAction(
        message: 'Sedang menyiapkan gambar laporan...',
        action: () async {
          final bytes = await _capturePromotorAchievementImage(snapshot);
          success = await DeviceImageSaver.saveImage(bytes, name: fileName);
        },
      );
      if (!mounted) return;
      if (success) {
        await showSuccessDialog(
          context,
          title: 'Berhasil',
          message: 'Laporan pencapaian promotor berhasil disimpan ke galeri.',
        );
      } else {
        await showErrorDialog(
          context,
          title: 'Gagal',
          message: 'Gagal menyimpan gambar laporan ke galeri.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa menyimpan gambar laporan: $e',
      );
    }
  }

  Future<void> _sharePromotorAchievementToTeam(
    _PromotorAchievementExportSnapshot snapshot,
  ) async {
    final satorId = _supabase.auth.currentUser?.id;
    if (satorId == null) return;

    await _runBlockingAction(
      message: 'Sedang mengirim laporan ke grup...',
      action: () async {
        final bytes = await _capturePromotorAchievementImage(snapshot);
        final room = await _chatRepository.getTeamChatRoom(satorId: satorId);
        if (room == null) {
          throw Exception('Grup utama Sator tidak ditemukan.');
        }

        final imageUrl = await _uploadExportImage(
          bytes,
          fileName: '${snapshot.fileNameBase}.png',
        );
        if (imageUrl == null || imageUrl.isEmpty) {
          throw Exception('Upload gambar laporan gagal.');
        }

        await _chatRepository.sendImageMessage(
          roomId: room.id,
          imageUrl: imageUrl,
          caption:
              'Laporan Pencapaian Promotor • ${DateFormat('d MMM yyyy', 'id_ID').format(snapshot.dataDate)}',
        );
      },
    );

    if (!mounted) return;
    await showSuccessDialog(
      context,
      title: 'Berhasil',
      message:
          'Laporan pencapaian promotor berhasil dikirim ke grup utama Sator.',
    );
  }

  Widget _buildPromotorAchievementExportWidget(
    _PromotorAchievementExportSnapshot snapshot, {
    double canvasWidth = kSatorPromotorAchievementExportCanvasWidth,
  }) {
    return buildSatorPromotorAchievementExportWidget(
      satorName: snapshot.satorName,
      dataDate: snapshot.dataDate,
      monthStart: snapshot.monthStart,
      rows: snapshot.rows.map((row) => row.toMap()).toList(),
      totals: snapshot.totals,
      canvasWidth: canvasWidth,
    );
  }

  Future<Uint8List> _capturePromotorAchievementImage(
    _PromotorAchievementExportSnapshot snapshot,
  ) async {
    final mediaQuery = MediaQuery.of(context);
    final rowCount = snapshot.rows.length;
    final canvasWidth = _resolvePromotorAchievementCanvasWidth(
      mediaQuery,
      rowCount,
    );
    final pixelRatio = _resolvePromotorAchievementPixelRatio(
      mediaQuery,
      rowCount,
    );

    return _previewCaptureController.captureFromLongWidget(
      InheritedTheme.captureAll(
        context,
        Material(
          color: const Color(0xFFF7F3EC),
          child: _buildPromotorAchievementExportWidget(
            snapshot,
            canvasWidth: canvasWidth,
          ),
        ),
      ),
      pixelRatio: pixelRatio,
      context: context,
      delay: const Duration(milliseconds: 160),
    );
  }

  double _resolvePromotorAchievementCanvasWidth(
    MediaQueryData mediaQuery,
    int rowCount,
  ) {
    if (!Platform.isAndroid) {
      return kSatorPromotorAchievementExportCanvasWidth;
    }

    final shortestSide = mediaQuery.size.shortestSide;
    var width = shortestSide <= 420 ? 1120.0 : 1200.0;
    if (rowCount >= 18) {
      width -= 40;
    }
    if (rowCount >= 24) {
      width -= 40;
    }
    return width.clamp(
      kSatorPromotorAchievementExportMinCanvasWidth,
      kSatorPromotorAchievementExportCanvasWidth,
    );
  }

  double _resolvePromotorAchievementPixelRatio(
    MediaQueryData mediaQuery,
    int rowCount,
  ) {
    final devicePixelRatio = mediaQuery.devicePixelRatio;
    var pixelRatio = Platform.isAndroid ? 1.8 : 2.4;

    if (rowCount >= 12) {
      pixelRatio -= 0.2;
    }
    if (rowCount >= 18) {
      pixelRatio -= 0.2;
    }
    if (rowCount >= 24) {
      pixelRatio -= 0.2;
    }

    if (devicePixelRatio <= 2.0) {
      pixelRatio = math.min(pixelRatio, 1.6);
    }

    return pixelRatio.clamp(1.2, 2.4);
  }

  Future<void> _runBlockingAction({
    required String message,
    required Future<void> Function() action,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            content: SizedBox(
              width: 250,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    try {
      await action();
    } finally {
      if (mounted && Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
  }

  Future<String?> _uploadExportImage(
    Uint8List bytes, {
    required String fileName,
  }) async {
    try {
      final result = await CloudinaryUploadHelper.uploadBytes(
        bytes,
        folder: 'vtrack/sator_exports',
        fileName: fileName,
      );
      return result?.url;
    } catch (_) {
      return null;
    }
  }

  Future<void> _exportJadwal() async {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final snapshotRaw = await _supabase.rpc(
      'get_export_schedule_snapshot',
      params: {
        'p_start_date': dateFormat.format(_startDate),
        'p_end_date': dateFormat.format(_endDate),
      },
    );
    final snapshot = _safeMap(snapshotRaw);
    final rows = _parseMapList(snapshot['rows']);

    if (rows.isEmpty) {
      throw Exception('Tidak ada data jadwal pada rentang tanggal ini.');
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
    final totalColumns = 4 + (dates.length * 4);

    final headerStyle = workbook.styles.add('scheduleHeaderStyle');
    headerStyle.bold = true;
    headerStyle.hAlign = xlsio.HAlignType.center;
    headerStyle.vAlign = xlsio.VAlignType.center;
    headerStyle.wrapText = true;
    headerStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    final cellStyle = workbook.styles.add('scheduleCellStyle');
    cellStyle.hAlign = xlsio.HAlignType.center;
    cellStyle.vAlign = xlsio.VAlignType.center;
    cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    final textCellStyle = workbook.styles.add('scheduleTextCellStyle');
    textCellStyle.hAlign = xlsio.HAlignType.left;
    textCellStyle.vAlign = xlsio.VAlignType.center;
    textCellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    const headerRowDate = 1;
    const headerRowWeekday = 2;
    const headerRowLabel = 3;

    for (final label in const [
      'Name',
      'NAMA TOKO',
      'TUTOR',
      'JAM RAMAI DI TOKO',
    ]) {
      final colIndex =
          const [
            'Name',
            'NAMA TOKO',
            'TUTOR',
            'JAM RAMAI DI TOKO',
          ].indexOf(label) +
          1;
      sheet
          .getRangeByIndex(headerRowDate, colIndex, headerRowLabel, colIndex)
          .merge();
      final cell = sheet.getRangeByIndex(headerRowDate, colIndex);
      cell.setText(label);
      cell.cellStyle = headerStyle;
    }

    var startColumn = 5;
    for (final date in dates) {
      sheet
          .getRangeByIndex(
            headerRowDate,
            startColumn,
            headerRowDate,
            startColumn + 3,
          )
          .merge();
      final dateCell = sheet.getRangeByIndex(headerRowDate, startColumn);
      dateCell.setText(
        DateFormat('dd MMM yyyy', 'id_ID').format(date).toUpperCase(),
      );
      dateCell.cellStyle = headerStyle;

      sheet
          .getRangeByIndex(
            headerRowWeekday,
            startColumn,
            headerRowWeekday,
            startColumn + 3,
          )
          .merge();
      final weekdayCell = sheet.getRangeByIndex(headerRowWeekday, startColumn);
      weekdayCell.setText(
        DateFormat('EEEE', 'id_ID').format(date).toUpperCase(),
      );
      weekdayCell.cellStyle = headerStyle;

      final labels = const [
        'IN (MASUK KERJA)',
        'OUT (KELUAR ISTIRAHAT)',
        'IN (HABIS ISTIRAHAT)',
        'OUT (PULANG KERJA)',
      ];
      for (int i = 0; i < labels.length; i++) {
        final cell = sheet.getRangeByIndex(headerRowLabel, startColumn + i);
        cell.setText(labels[i]);
        cell.cellStyle = headerStyle;
      }
      startColumn += 4;
    }

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final rowIndex = i + 4;
      final scheduleMap = _safeMap(row['schedule_map']);
      final leftValues = <String>[
        '${row['promotor_name'] ?? 'Unknown'}',
        '${row['store_name'] ?? row['store_names'] ?? '-'}',
        '${row['sator_name'] ?? '-'}',
        '${row['peak_hours'] ?? '-'}',
      ];

      for (int col = 0; col < leftValues.length; col++) {
        final cell = sheet.getRangeByIndex(rowIndex, col + 1);
        cell.setText(leftValues[col]);
        cell.cellStyle = textCellStyle;
      }

      var dayColumn = 5;
      for (final date in dates) {
        final dateKey = dateFormat.format(date);
        final dayData = _safeMap(scheduleMap[dateKey]);
        final shiftType = '${dayData['shift_type'] ?? ''}'.trim().toUpperCase();
        final values = shiftType == 'LIBUR'
            ? const ['Libur', 'Libur', 'Libur', 'Libur']
            : [
                '${dayData['clock_in'] ?? ''}',
                '${dayData['break_start'] ?? ''}',
                '${dayData['break_end'] ?? ''}',
                '${dayData['clock_out'] ?? ''}',
              ];
        for (int i = 0; i < values.length; i++) {
          final cell = sheet.getRangeByIndex(rowIndex, dayColumn + i);
          cell.setText(values[i]);
          cell.cellStyle = cellStyle;
        }
        dayColumn += 4;
      }
    }

    for (int column = 1; column <= totalColumns; column++) {
      sheet.autoFitColumn(column);
    }
    sheet
            .getRangeByIndex(1, 1, rows.length + 3, totalColumns)
            .cellStyle
            .fontSize =
        10;
    sheet.getRangeByIndex(1, 1, rows.length + 3, totalColumns).rowHeight = 24;
    sheet
            .getRangeByIndex(headerRowDate, 1, headerRowDate, totalColumns)
            .rowHeight =
        28;
    sheet
            .getRangeByIndex(
              headerRowWeekday,
              1,
              headerRowWeekday,
              totalColumns,
            )
            .rowHeight =
        26;
    sheet
            .getRangeByIndex(headerRowLabel, 1, headerRowLabel, totalColumns)
            .rowHeight =
        42;
    sheet.getRangeByIndex(1, 1, rows.length + 3, 1).columnWidth = 22;
    sheet.getRangeByIndex(1, 2, rows.length + 3, 2).columnWidth = 20;
    sheet.getRangeByIndex(1, 3, rows.length + 3, 3).columnWidth = 16;
    sheet.getRangeByIndex(1, 4, rows.length + 3, 4).columnWidth = 16;
    for (int column = 5; column <= totalColumns; column++) {
      sheet.getRangeByIndex(1, column, rows.length + 3, column).columnWidth =
          12;
    }

    final List<int> fileBytes = workbook.saveAsStream();
    workbook.dispose();

    final directory = await _getExportDirectory();
    final fileName =
        'Jadwal_Tim_${DateFormat('yyyyMMdd').format(DateTime.now())}.xlsx';
    final file = File('${directory.path}/$fileName')
      ..createSync(recursive: true)
      ..writeAsBytesSync(fileBytes);
    await _notifyExportReady(path: file.path, title: 'Jadwal Tim siap dibuka');

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Platform.isAndroid
                ? '✅ File jadwal masuk folder Download'
                : '✅ File jadwal tersimpan di: ${file.path}',
          ),
        ),
      );
    }
  }

  Future<void> _exportAllbrand() async {
    final dateFormat = DateFormat('yyyy-MM-dd');
    final snapshotRaw = await _supabase.rpc(
      'get_export_allbrand_snapshot',
      params: {
        'p_start_date': dateFormat.format(_startDate),
        'p_end_date': dateFormat.format(_endDate),
      },
    );
    final snapshot = _safeMap(snapshotRaw);
    final rows = _parseMapList(snapshot['rows']);
    if (rows.isEmpty) {
      throw Exception('Tidak ada laporan AllBrand pada rentang tanggal ini.');
    }

    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = 'AllBrand';
    final brands = _resolveAllbrandBrands(rows);
    final dateTitle =
        'Penjualan ${DateFormat('d MMM yyyy').format(_startDate)} - ${DateFormat('d MMM yyyy').format(_endDate)}';

    final titleStyle = workbook.styles.add('allbrandTitle');
    titleStyle.bold = true;
    titleStyle.hAlign = xlsio.HAlignType.center;
    titleStyle.vAlign = xlsio.VAlignType.center;
    titleStyle.fontSize = 12;

    final headerStyle = workbook.styles.add('allbrandHeader');
    headerStyle.bold = true;
    headerStyle.hAlign = xlsio.HAlignType.center;
    headerStyle.vAlign = xlsio.VAlignType.center;
    headerStyle.wrapText = true;
    headerStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    final cellStyle = workbook.styles.add('allbrandCell');
    cellStyle.hAlign = xlsio.HAlignType.center;
    cellStyle.vAlign = xlsio.VAlignType.center;
    cellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    final textCellStyle = workbook.styles.add('allbrandTextCell');
    textCellStyle.hAlign = xlsio.HAlignType.left;
    textCellStyle.vAlign = xlsio.VAlignType.center;
    textCellStyle.borders.all.lineStyle = xlsio.LineStyle.thin;

    var column = 1;
    const fixedInfoColumns = 4;
    const totalStoreColumn = 1;
    final vivoColumns = _allbrandRangeKeys.length;
    final brandColumns = brands.length * _allbrandRangeKeys.length;
    final leasingColumns = _allbrandLeasingOrder.length;
    final promotorColumns = brands.length + 1;
    final totalColumns =
        fixedInfoColumns +
        totalStoreColumn +
        vivoColumns +
        brandColumns +
        leasingColumns +
        promotorColumns;

    sheet.getRangeByIndex(1, 5, 1, totalColumns).merge();
    final titleRange = sheet.getRangeByIndex(1, 5, 1, totalColumns);
    titleRange.setText(dateTitle);
    titleRange.cellStyle = titleStyle;

    for (final label in const ['No', 'Area', 'Nama Sator', 'Nama Toko']) {
      sheet.getRangeByIndex(2, column, 3, column).merge();
      final range = sheet.getRangeByIndex(2, column, 3, column);
      range.setText(label);
      range.cellStyle = headerStyle;
      column++;
    }

    sheet.getRangeByIndex(2, column, 3, column).merge();
    sheet.getRangeByIndex(2, column).setText('Penjualan Toko');
    sheet.getRangeByIndex(2, column, 3, column).cellStyle = headerStyle;
    column++;

    sheet.getRangeByIndex(2, column, 2, column + vivoColumns - 1).merge();
    sheet.getRangeByIndex(2, column).setText('Penjualan Vivo');
    sheet.getRangeByIndex(2, column, 2, column + vivoColumns - 1).cellStyle =
        headerStyle;
    for (int i = 0; i < _allbrandRangeKeys.length; i++) {
      final cell = sheet.getRangeByIndex(3, column + i);
      cell.setText(_allbrandRangeLabel(_allbrandRangeKeys[i]));
      cell.cellStyle = headerStyle;
    }
    column += vivoColumns;

    for (final brand in brands) {
      sheet
          .getRangeByIndex(2, column, 2, column + _allbrandRangeKeys.length - 1)
          .merge();
      sheet.getRangeByIndex(2, column).setText('Penjualan $brand');
      sheet
              .getRangeByIndex(
                2,
                column,
                2,
                column + _allbrandRangeKeys.length - 1,
              )
              .cellStyle =
          headerStyle;
      for (int i = 0; i < _allbrandRangeKeys.length; i++) {
        final cell = sheet.getRangeByIndex(3, column + i);
        cell.setText(_allbrandRangeLabel(_allbrandRangeKeys[i]));
        cell.cellStyle = headerStyle;
      }
      column += _allbrandRangeKeys.length;
    }

    sheet.getRangeByIndex(2, column, 2, column + leasingColumns - 1).merge();
    sheet.getRangeByIndex(2, column).setText('Leasing');
    sheet.getRangeByIndex(2, column, 2, column + leasingColumns - 1).cellStyle =
        headerStyle;
    for (int i = 0; i < _allbrandLeasingOrder.length; i++) {
      sheet.getRangeByIndex(2, column + i, 3, column + i).merge();
      final cell = sheet.getRangeByIndex(2, column + i);
      cell.setText(_allbrandLeasingOrder[i]);
      cell.cellStyle = headerStyle;
    }
    column += leasingColumns;

    sheet.getRangeByIndex(2, column, 2, column + promotorColumns - 1).merge();
    sheet.getRangeByIndex(2, column).setText('Promotor');
    sheet
            .getRangeByIndex(2, column, 2, column + promotorColumns - 1)
            .cellStyle =
        headerStyle;
    final promotorLabels = <String>['Vivo', ...brands];
    for (int i = 0; i < promotorLabels.length; i++) {
      sheet.getRangeByIndex(2, column + i, 3, column + i).merge();
      final cell = sheet.getRangeByIndex(2, column + i);
      cell.setText(promotorLabels[i]);
      cell.cellStyle = headerStyle;
    }

    for (int i = 0; i < rows.length; i++) {
      final row = rows[i];
      final excelRow = i + 4;
      final brandData = _safeMap(row['brand_data']);
      final leasingSales = _safeMap(row['leasing_sales']);
      final vivoAuto = _safeMap(row['vivo_auto_data']);

      var dataColumn = 1;
      final fixedValues = <String>[
        '${i + 1}',
        '${row['area'] ?? '-'}',
        '${row['sator_name'] ?? '-'}',
        '${row['store_name'] ?? '-'}',
        '${row['total_unit_allbrand_toko'] ?? row['total_store_cumulative'] ?? 0}',
      ];
      for (int idx = 0; idx < fixedValues.length; idx++) {
        final cell = sheet.getRangeByIndex(excelRow, dataColumn++);
        cell.setText(fixedValues[idx]);
        cell.cellStyle = idx >= 1 && idx <= 3 ? textCellStyle : cellStyle;
      }

      for (final rangeKey in _allbrandRangeKeys) {
        final cell = sheet.getRangeByIndex(excelRow, dataColumn++);
        cell.setNumber(_toExcelNumber(vivoAuto[rangeKey]));
        cell.cellStyle = cellStyle;
      }

      for (final brand in brands) {
        final brandRow = _safeMap(brandData[brand]);
        for (final rangeKey in _allbrandRangeKeys) {
          final cell = sheet.getRangeByIndex(excelRow, dataColumn++);
          cell.setNumber(_toExcelNumber(brandRow[rangeKey]));
          cell.cellStyle = cellStyle;
        }
      }

      for (final provider in _allbrandLeasingOrder) {
        final cell = sheet.getRangeByIndex(excelRow, dataColumn++);
        cell.setNumber(_toExcelNumber(leasingSales[provider]));
        cell.cellStyle = cellStyle;
      }

      final vivoPromotorCell = sheet.getRangeByIndex(excelRow, dataColumn++);
      vivoPromotorCell.setNumber(_toExcelNumber(row['vivo_promotor_count']));
      vivoPromotorCell.cellStyle = cellStyle;
      for (final brand in brands) {
        final brandRow = _safeMap(brandData[brand]);
        final cell = sheet.getRangeByIndex(excelRow, dataColumn++);
        cell.setNumber(_toExcelNumber(brandRow['promotor_count']));
        cell.cellStyle = cellStyle;
      }
    }

    sheet
            .getRangeByIndex(1, 1, rows.length + 3, totalColumns)
            .cellStyle
            .fontSize =
        10;
    sheet.getRangeByIndex(1, 1, rows.length + 3, totalColumns).autoFitColumns();
    sheet.getRangeByIndex(1, 4, rows.length + 3, 4).columnWidth = 24;
    sheet.getRangeByIndex(1, 3, rows.length + 3, 3).columnWidth = 18;
    sheet.getRangeByIndex(1, 2, rows.length + 3, 2).columnWidth = 14;
    sheet.getRangeByIndex(1, 1, 3, totalColumns).rowHeight = 24;

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

  Map<String, dynamic> _safeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  List<String> _resolveAllbrandBrands(List<Map<String, dynamic>> rows) {
    final discovered = <String>{};
    for (final row in rows) {
      final brandData = _safeMap(row['brand_data']);
      for (final key in brandData.keys) {
        final brand = key.toString().trim();
        if (brand.isEmpty) continue;
        if (brand.toLowerCase() == 'nubia') continue;
        discovered.add(brand);
      }
    }

    final ordered = <String>[];
    for (final brand in _allbrandBrandOrder) {
      if (discovered.contains(brand)) {
        ordered.add(brand);
      }
    }
    final extras =
        discovered
            .where((brand) => !_allbrandBrandOrder.contains(brand))
            .toList()
          ..sort();
    ordered.addAll(extras);
    return ordered;
  }

  String _allbrandRangeLabel(String rangeKey) {
    switch (rangeKey) {
      case 'under_2m':
        return '< 2 Jt';
      case '2m_4m':
        return '2 - 4 Jt';
      case '4m_6m':
        return '4 - 6 Jt';
      case 'above_6m':
        return '> 6 Jt';
      default:
        return rangeKey;
    }
  }

  double _toExcelNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value') ?? 0;
  }
}

class _PromotorAchievementExportSnapshot {
  const _PromotorAchievementExportSnapshot({
    required this.satorName,
    required this.dataDate,
    required this.monthStart,
    required this.rows,
    required this.totals,
  });

  final String satorName;
  final DateTime dataDate;
  final DateTime monthStart;
  final List<_PromotorAchievementExportRow> rows;
  final Map<String, dynamic> totals;

  String get fileNameBase {
    final safeName = satorName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');
    return 'laporan_pencapaian_promotor_${safeName.isEmpty ? 'sator' : safeName}_${DateFormat('yyyyMMdd').format(dataDate)}';
  }
}

class _PromotorAchievementExportRow {
  const _PromotorAchievementExportRow({
    required this.no,
    required this.storeName,
    required this.promotorName,
    required this.statusLabel,
    required this.selloutTarget,
    required this.selloutActual,
    required this.selloutPct,
    required this.selloutGap,
    required this.focusTarget,
    required this.focusActual,
    required this.focusPct,
    required this.specials,
    required this.vastTargetInput,
    required this.vastTotalInput,
    required this.vastPct,
    required this.vastPending,
    required this.vastReject,
    required this.vastClosingAmount,
    required this.totalUnit,
  });

  final int no;
  final String storeName;
  final String promotorName;
  final String statusLabel;
  final num selloutTarget;
  final num selloutActual;
  final num selloutPct;
  final num selloutGap;
  final int focusTarget;
  final int focusActual;
  final num focusPct;
  final List<_PromotorAchievementSpecialMetric> specials;
  final int vastTargetInput;
  final int vastTotalInput;
  final num vastPct;
  final int vastPending;
  final int vastReject;
  final num vastClosingAmount;
  final int totalUnit;

  _PromotorAchievementExportRow copyWith({int? no}) {
    return _PromotorAchievementExportRow(
      no: no ?? this.no,
      storeName: storeName,
      promotorName: promotorName,
      statusLabel: statusLabel,
      selloutTarget: selloutTarget,
      selloutActual: selloutActual,
      selloutPct: selloutPct,
      selloutGap: selloutGap,
      focusTarget: focusTarget,
      focusActual: focusActual,
      focusPct: focusPct,
      specials: specials,
      vastTargetInput: vastTargetInput,
      vastTotalInput: vastTotalInput,
      vastPct: vastPct,
      vastPending: vastPending,
      vastReject: vastReject,
      vastClosingAmount: vastClosingAmount,
      totalUnit: totalUnit,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'no': no,
      'store_name': storeName,
      'promotor_name': promotorName,
      'status_label': statusLabel,
      'sellout_target': selloutTarget,
      'sellout_actual': selloutActual,
      'sellout_pct': selloutPct,
      'sellout_gap': selloutGap,
      'focus_target': focusTarget,
      'focus_actual': focusActual,
      'focus_pct': focusPct,
      'specials': specials.map((item) => item.toMap()).toList(),
      'vast_target_input': vastTargetInput,
      'vast_total_input': vastTotalInput,
      'vast_pct': vastPct,
      'vast_pending': vastPending,
      'vast_reject': vastReject,
      'vast_closing_amount': vastClosingAmount,
      'total_unit': totalUnit,
    };
  }
}

class _PromotorAchievementSpecialMetric {
  const _PromotorAchievementSpecialMetric({
    required this.label,
    required this.target,
    required this.actual,
    required this.pct,
  });

  final String label;
  final int target;
  final int actual;
  final num pct;

  Map<String, dynamic> toMap() {
    return {'label': label, 'target': target, 'actual': actual, 'pct': pct};
  }
}
