import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:vtrack/ui/promotor/promotor.dart';

class CustomerDataPage extends StatefulWidget {
  const CustomerDataPage({
    super.key,
    required this.scope,
  });

  final String scope; // promotor | sator | spv

  @override
  State<CustomerDataPage> createState() => _CustomerDataPageState();
}

class _CustomerDataPageState extends State<CustomerDataPage> {
  final _supabase = Supabase.instance.client;

  bool _loading = true;
  bool _exporting = false;
  DateTime _startDate = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _endDate = DateTime.now();
  String _paymentFilter = 'all';
  List<_CustomerSaleRow> _rows = const [];

  FieldThemeTokens get t => context.fieldTokens;
  bool get _allowExport => widget.scope == 'sator' || widget.scope == 'spv';
  String get _scopeLabel {
    switch (widget.scope) {
      case 'promotor':
        return 'Promotor';
      case 'sator':
        return 'SATOR';
      case 'spv':
        return 'SPV';
      default:
        return '-';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final currentUserId = _supabase.auth.currentUser?.id;
    if (currentUserId == null) return;
    if (mounted) setState(() => _loading = true);

    try {
      final promotorIds = await _resolvePromotorScopeIds(currentUserId);
      if (promotorIds.isEmpty) {
        if (!mounted) return;
        setState(() {
          _rows = const [];
          _loading = false;
        });
        return;
      }

      dynamic query = _supabase
          .from('sales_sell_out')
          .select(
            'id, promotor_id, store_id, transaction_date, customer_name, customer_phone, '
            'payment_method, leasing_provider, product_variants!left(ram_rom, color, products!left(model_name))',
          )
          .inFilter('promotor_id', promotorIds)
          .isFilter('deleted_at', null)
          .gte('transaction_date', _fmtDate(_startDate))
          .lte('transaction_date', _fmtDate(_endDate));

      if (_paymentFilter != 'all') {
        query = query.eq('payment_method', _paymentFilter);
      }
      query = query.order('transaction_date', ascending: false);

      final saleRows = _asList(await query);
      final userIds = saleRows
          .map((row) => '${row['promotor_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      final storeIds = saleRows
          .map((row) => '${row['store_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      final profiles = userIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : _asList(
              await _supabase
                  .from('users')
                  .select('id, full_name, nickname')
                  .inFilter('id', userIds),
            );

      final stores = storeIds.isEmpty
          ? const <Map<String, dynamic>>[]
          : _asList(
              await _supabase
                  .from('stores')
                  .select('id, store_name')
                  .inFilter('id', storeIds),
            );

      final promotorMap = <String, String>{
        for (final row in profiles)
          '${row['id'] ?? ''}': _displayName(row, fallback: 'Promotor'),
      };
      final storeMap = <String, String>{
        for (final row in stores)
          '${row['id'] ?? ''}': '${row['store_name'] ?? '-'}',
      };

      final built = saleRows.map((row) {
        final productVariant = _asMap(row['product_variants']);
        final products = _asMap(productVariant['products']);
        final productName = _buildProductName(
          products['model_name']?.toString(),
          productVariant['ram_rom']?.toString(),
          productVariant['color']?.toString(),
        );
        final payment = '${row['payment_method'] ?? '-'}'.trim().toLowerCase();
        return _CustomerSaleRow(
          transactionDate: _parseDate(row['transaction_date']),
          customerName: '${row['customer_name'] ?? '-'}',
          customerPhone: '${row['customer_phone'] ?? '-'}',
          promotorName:
              promotorMap['${row['promotor_id'] ?? ''}'] ?? 'Promotor',
          storeName: storeMap['${row['store_id'] ?? ''}'] ?? '-',
          productName: productName,
          paymentMethod: payment.isEmpty ? '-' : payment,
          leasingProvider: '${row['leasing_provider'] ?? ''}',
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _rows = built;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _rows = const [];
        _loading = false;
      });
    }
  }

  Future<List<String>> _resolvePromotorScopeIds(String currentUserId) async {
    if (widget.scope == 'promotor') {
      return [currentUserId];
    }

    if (widget.scope == 'sator') {
      final links = _asList(
        await _supabase
            .from('hierarchy_sator_promotor')
            .select('promotor_id')
            .eq('sator_id', currentUserId)
            .eq('active', true),
      );
      return links
          .map((row) => '${row['promotor_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
    }

    if (widget.scope == 'spv') {
      final spvLinks = _asList(
        await _supabase
            .from('hierarchy_spv_sator')
            .select('sator_id')
            .eq('spv_id', currentUserId)
            .eq('active', true),
      );
      final satorIds = spvLinks
          .map((row) => '${row['sator_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
      if (satorIds.isEmpty) return const [];
      final links = _asList(
        await _supabase
            .from('hierarchy_sator_promotor')
            .select('promotor_id')
            .inFilter('sator_id', satorIds)
            .eq('active', true),
      );
      return links
          .map((row) => '${row['promotor_id'] ?? ''}')
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();
    }

    return const [];
  }

  Future<void> _pickDate({required bool isStart}) async {
    final initial = isStart ? _startDate : _endDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;

    setState(() {
      if (isStart) {
        _startDate = DateTime(picked.year, picked.month, picked.day);
        if (_startDate.isAfter(_endDate)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = DateTime(picked.year, picked.month, picked.day);
        if (_endDate.isBefore(_startDate)) {
          _startDate = _endDate;
        }
      }
    });
    await _loadData();
  }

  Future<void> _exportExcel() async {
    if (!_allowExport || _rows.isEmpty) return;
    setState(() => _exporting = true);
    try {
      final workbook = xlsio.Workbook();
      final sheet = workbook.worksheets[0];
      sheet.name = 'Data Konsumen';
      final headers = <String>[
        'Tanggal Pembelian',
        'Nama Konsumen',
        'No Telp',
        'Promotor',
        'Toko',
        'Tipe HP',
        'Metode Pembayaran',
        'Leasing',
      ];

      final headerStyle = workbook.styles.add('header_customer_data');
      headerStyle.bold = true;
      headerStyle.fontColor = '#FFFFFF';
      headerStyle.backColor = '#C9923A';

      for (var i = 0; i < headers.length; i++) {
        final cell = sheet.getRangeByIndex(1, i + 1);
        cell.setText(headers[i]);
        cell.cellStyle = headerStyle;
      }

      for (var rowIndex = 0; rowIndex < _rows.length; rowIndex++) {
        final row = _rows[rowIndex];
        final values = <Object?>[
          DateFormat('dd MMM yyyy', 'id_ID').format(row.transactionDate),
          row.customerName,
          row.customerPhone,
          row.promotorName,
          row.storeName,
          row.productName,
          row.paymentMethod.toUpperCase(),
          row.leasingProvider.trim().isEmpty ? '-' : row.leasingProvider,
        ];
        for (var col = 0; col < values.length; col++) {
          final cell = sheet.getRangeByIndex(rowIndex + 2, col + 1);
          cell.setText('${values[col] ?? ''}');
        }
      }

      for (var i = 1; i <= headers.length; i++) {
        sheet.autoFitColumn(i);
      }

      final bytes = workbook.saveAsStream();
      workbook.dispose();

      final fileName =
          'Data_Konsumen_${widget.scope.toUpperCase()}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.xlsx';
      final dir = await _getExportDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export tersimpan di ${file.path}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal export: $e')),
      );
    } finally {
      if (mounted) setState(() => _exporting = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Data Konsumen'),
        backgroundColor: t.surface1,
        foregroundColor: t.textPrimary,
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 20),
          children: [
            _buildFilterCard(),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_rows.length} data • Scope $_scopeLabel',
                    style: PromotorText.outfit(
                      size: 12,
                      weight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                  ),
                ),
                if (_allowExport)
                  FilledButton.icon(
                    onPressed: _exporting || _rows.isEmpty ? null : _exportExcel,
                    icon: _exporting
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 16),
                    label: Text(_exporting ? 'Export...' : 'Export Excel'),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 30),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_rows.isEmpty)
              _buildEmptyState()
            else
              ..._rows.map(_buildRowCard),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterCard() {
    final dateText =
        '${DateFormat('dd MMM yyyy', 'id_ID').format(_startDate)} - ${DateFormat('dd MMM yyyy', 'id_ID').format(_endDate)}';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter',
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () async {
              await _pickDate(isStart: true);
              if (!mounted) return;
              await _pickDate(isStart: false);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.surface3),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dateText,
                      style: PromotorText.outfit(
                        size: 12,
                        weight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _paymentFilter,
            decoration: InputDecoration(
              filled: true,
              fillColor: t.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: t.surface3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: t.surface3),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Metode: Semua')),
              DropdownMenuItem(value: 'cash', child: Text('Metode: Cash')),
              DropdownMenuItem(value: 'kredit', child: Text('Metode: Kredit')),
            ],
            onChanged: (value) async {
              if (value == null) return;
              setState(() => _paymentFilter = value);
              await _loadData();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildRowCard(_CustomerSaleRow row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  row.customerName,
                  style: PromotorText.outfit(
                    size: 14,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              Text(
                DateFormat('dd MMM yyyy', 'id_ID').format(row.transactionDate),
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${row.customerPhone} • ${row.paymentMethod.toUpperCase()}',
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '${row.promotorName} • ${row.storeName}',
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            row.productName,
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          if (row.paymentMethod == 'kredit' &&
              row.leasingProvider.trim().isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              'Leasing: ${row.leasingProvider}',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        'Belum ada data konsumen pada filter ini.',
        textAlign: TextAlign.center,
        style: PromotorText.outfit(
          size: 12,
          weight: FontWeight.w700,
          color: t.textSecondary,
        ),
      ),
    );
  }

  List<Map<String, dynamic>> _asList(dynamic value) {
    if (value is List) {
      return value.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    return const [];
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return const {};
  }

  String _fmtDate(DateTime value) => DateFormat('yyyy-MM-dd').format(value);

  DateTime _parseDate(dynamic value) {
    if (value is DateTime) return value;
    final parsed = DateTime.tryParse('${value ?? ''}');
    return parsed ?? DateTime.now();
  }

  String _displayName(Map<String, dynamic> row, {required String fallback}) {
    final nickname = '${row['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    final fullName = '${row['full_name'] ?? ''}'.trim();
    if (fullName.isNotEmpty) return fullName;
    return fallback;
  }

  String _buildProductName(String? modelName, String? ramRom, String? color) {
    final parts = <String>[
      if ((modelName ?? '').trim().isNotEmpty) modelName!.trim(),
      if ((ramRom ?? '').trim().isNotEmpty) ramRom!.trim(),
      if ((color ?? '').trim().isNotEmpty) color!.trim(),
    ];
    if (parts.isEmpty) return '-';
    return parts.join(' • ');
  }
}

class _CustomerSaleRow {
  const _CustomerSaleRow({
    required this.transactionDate,
    required this.customerName,
    required this.customerPhone,
    required this.promotorName,
    required this.storeName,
    required this.productName,
    required this.paymentMethod,
    required this.leasingProvider,
  });

  final DateTime transactionDate;
  final String customerName;
  final String customerPhone;
  final String promotorName;
  final String storeName;
  final String productName;
  final String paymentMethod;
  final String leasingProvider;
}
