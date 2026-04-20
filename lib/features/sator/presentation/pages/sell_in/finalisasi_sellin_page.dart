import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/core/utils/device_image_saver.dart';
import 'package:vtrack/core/utils/success_dialog.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import 'sell_in_order_export_widget.dart';

class FinalisasiSellInPage extends StatefulWidget {
  const FinalisasiSellInPage({super.key});

  @override
  State<FinalisasiSellInPage> createState() => _FinalisasiSellInPageState();
}

class _FinalisasiSellInPageState extends State<FinalisasiSellInPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final _dateFormat = DateFormat('d MMM yyyy', 'id_ID');
  final _previewCaptureController = ScreenshotController();

  bool _isLoading = true;
  Set<String> _loadingDetailIds = <String>{};
  Set<String> _finalizingIds = <String>{};
  Set<String> _cancellingIds = <String>{};
  List<Map<String, dynamic>> _pendingOrders = const [];
  List<Map<String, dynamic>> _finalizedOrders = const [];
  List<Map<String, dynamic>> _cancelledOrders = const [];
  Map<String, Map<String, dynamic>> _detailByOrderId = const {};
  Map<String, dynamic> _summary = const {};
  String _activeTab = 'pending';
  late DateTime _selectedMonth;
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month);
    _loadAll();
  }

  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final dateRange = _selectedRange;
      final snapshotRaw = await _supabase.rpc(
        'get_sell_in_finalization_page_snapshot',
        params: {
          'p_start_date': DateFormat('yyyy-MM-dd').format(dateRange.$1),
          'p_end_date': DateFormat('yyyy-MM-dd').format(dateRange.$2),
        },
      );
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final pendingOrders = _parseMapList(snapshot['pending_orders']);
      final finalizedOrders = _parseMapList(snapshot['finalized_orders']);
      final cancelledOrders = _parseMapList(snapshot['cancelled_orders']);

      if (!mounted) return;
      setState(() {
        _pendingOrders = pendingOrders;
        _finalizedOrders = finalizedOrders;
        _cancelledOrders = cancelledOrders;
        _summary = Map<String, dynamic>.from(
          (snapshot['summary'] as Map?) ?? const <String, dynamic>{},
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pendingOrders = const [];
        _finalizedOrders = const [];
        _cancelledOrders = const [];
        _summary = const {};
        _isLoading = false;
      });
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa memuat order sell in: $e',
      );
    }
  }

  bool _isSameDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  (DateTime, DateTime) get _selectedRange {
    if (_selectedDate != null) {
      final start = DateTime(
        _selectedDate!.year,
        _selectedDate!.month,
        _selectedDate!.day,
      );
      return (start, start);
    }

    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    return (monthStart, monthEnd);
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  String _normalizedGroupName(dynamic value) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return '';
    final lower = text.toLowerCase();
    if (lower == 'ungrouped' || lower.startsWith('ungrouped ')) {
      return '';
    }
    return text;
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final months = List<DateTime>.generate(
      18,
      (index) => DateTime(now.year, now.month - index),
    );

    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface1,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pilih Bulan',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 10),
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: months.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: t.surface3),
                    itemBuilder: (context, index) {
                      final month = months[index];
                      final selected =
                          month.year == _selectedMonth.year &&
                          month.month == _selectedMonth.month;
                      return ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 4,
                        ),
                        title: Text(
                          DateFormat('MMMM yyyy', 'id_ID').format(month),
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: selected ? t.primaryAccent : t.textPrimary,
                          ),
                        ),
                        trailing: selected
                            ? Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: t.primaryAccent,
                              )
                            : null,
                        onTap: () => Navigator.of(sheetContext).pop(month),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked == null || !mounted) return;
    setState(() {
      _selectedMonth = DateTime(picked.year, picked.month);
      _selectedDate = null;
    });
    await _loadAll();
  }

  Future<void> _pickDate() async {
    final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1);
    final monthEnd = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 0);
    final dates = List<DateTime>.generate(
      monthEnd.day,
      (index) => DateTime(_selectedMonth.year, _selectedMonth.month, index + 1),
    );
    final clearSelection = DateTime(1900, 1, 1);

    final picked = await showModalBottomSheet<DateTime?>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.surface1,
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Pilih Tanggal',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat('MMMM yyyy', 'id_ID').format(monthStart),
                  style: TextStyle(fontSize: 12, color: t.textMutedStrong),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            Navigator.of(sheetContext).pop(clearSelection),
                        child: const Text('Semua Tanggal'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final today = DateTime.now();
                          if (today.year == _selectedMonth.year &&
                              today.month == _selectedMonth.month) {
                            Navigator.of(
                              sheetContext,
                            ).pop(DateTime(today.year, today.month, today.day));
                          } else {
                            Navigator.of(sheetContext).pop();
                          }
                        },
                        child: const Text('Hari Ini'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: GridView.builder(
                    shrinkWrap: true,
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 4,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 1.9,
                        ),
                    itemCount: dates.length,
                    itemBuilder: (context, index) {
                      final date = dates[index];
                      final selected =
                          _selectedDate != null &&
                          _isSameDate(date, _selectedDate!);
                      return InkWell(
                        onTap: () => Navigator.of(sheetContext).pop(date),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? t.primaryAccentSoft
                                : t.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? t.primaryAccent : t.surface3,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              DateFormat('d').format(date),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: selected
                                    ? t.primaryAccent
                                    : t.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted) return;
    if (picked == null) {
      return;
    }
    if (_isSameDate(picked, clearSelection)) {
      setState(() => _selectedDate = null);
      await _loadAll();
      return;
    }
    setState(() {
      _selectedDate = DateTime(picked.year, picked.month, picked.day);
      _selectedMonth = DateTime(picked.year, picked.month);
    });
    await _loadAll();
  }

  Future<void> _loadOrderDetail(String orderId) async {
    if (_loadingDetailIds.contains(orderId) ||
        _detailByOrderId.containsKey(orderId)) {
      return;
    }

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _loadingDetailIds = {..._loadingDetailIds, orderId});

    try {
      final response = await _supabase.rpc(
        'get_sell_in_order_detail',
        params: {'p_sator_id': userId, 'p_order_id': orderId},
      );
      if (!mounted) return;
      setState(() {
        _detailByOrderId = {
          ..._detailByOrderId,
          orderId: Map<String, dynamic>.from(response ?? const {}),
        };
      });
    } catch (e) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Gagal',
          message: 'Tidak bisa memuat detail order: $e',
        );
      }
    } finally {
      if (mounted) {
        final loading = Set<String>.from(_loadingDetailIds)..remove(orderId);
        setState(() => _loadingDetailIds = loading);
      }
    }
  }

  Future<void> _finalizeOrder(Map<String, dynamic> order) async {
    final orderId = order['id']?.toString();
    final userId = _supabase.auth.currentUser?.id;
    if (orderId == null || orderId.isEmpty || userId == null) return;

    setState(() => _finalizingIds = {..._finalizingIds, orderId});

    try {
      await _supabase.rpc(
        'finalize_sell_in_order_by_id',
        params: {'p_sator_id': userId, 'p_order_id': orderId, 'p_notes': null},
      );
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Finalisasi Berhasil',
        message:
            'Order ${order['store_name'] ?? 'toko'} sudah masuk ke transaksi sell in.',
      );
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa finalisasi order: $e',
      );
    } finally {
      if (mounted) {
        final ids = Set<String>.from(_finalizingIds)..remove(orderId);
        setState(() => _finalizingIds = ids);
      }
    }
  }

  Future<void> _cancelOrder(
    Map<String, dynamic> order, {
    required String reason,
    String? notes,
  }) async {
    final orderId = order['id']?.toString();
    final userId = _supabase.auth.currentUser?.id;
    if (orderId == null || orderId.isEmpty || userId == null) return;

    setState(() => _cancellingIds = {..._cancellingIds, orderId});

    try {
      await _supabase.rpc(
        'cancel_sell_in_order_by_id',
        params: {
          'p_sator_id': userId,
          'p_order_id': orderId,
          'p_reason': reason,
          'p_notes': notes,
        },
      );
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Order Dibatalkan',
        message: 'Order ini tidak akan dihitung ke pencapaian sell in.',
      );
      setState(() => _activeTab = 'cancelled');
      await _loadAll();
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa membatalkan order: $e',
      );
    } finally {
      if (mounted) {
        final ids = Set<String>.from(_cancellingIds)..remove(orderId);
        setState(() => _cancellingIds = ids);
      }
    }
  }

  Future<void> _showCancelDialog(Map<String, dynamic> order) async {
    final reasons = <String>[
      'Transfer belum masuk',
      'Toko batal order',
      'Stok gudang tidak ready',
      'Harga berubah',
      'Revisi order',
    ];
    String selectedReason = reasons.first;
    final notesController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: const Text('Batalkan Order'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${order['store_name'] ?? 'Toko'}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedReason,
                    isExpanded: true,
                    items: reasons
                        .map(
                          (reason) => DropdownMenuItem<String>(
                            value: reason,
                            child: Text(reason),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() => selectedReason = value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Alasan batal',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Catatan',
                      hintText: 'Opsional',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Tutup'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  style: FilledButton.styleFrom(
                    backgroundColor: t.danger,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Batalkan Order'),
                ),
              ],
            );
          },
        );
      },
    );

    final notes = notesController.text.trim();
    notesController.dispose();

    if (confirmed == true) {
      await _cancelOrder(
        order,
        reason: selectedReason,
        notes: notes.isEmpty ? null : notes,
      );
    }
  }

  Future<void> _showOrderPreview(Map<String, dynamic> order) async {
    final orderId = '${order['id'] ?? ''}';
    if (orderId.isEmpty) return;

    if (!_detailByOrderId.containsKey(orderId)) {
      await _loadOrderDetail(orderId);
    }

    final detail = _detailByOrderId[orderId];
    final detailItems = detail == null
        ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(detail['items'] ?? const []);
    if (detailItems.isEmpty) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Preview gambar belum tersedia untuk order ini.',
      );
      return;
    }

    if (!mounted) return;
    final currentContext = context;
    if (!currentContext.mounted) return;
    final imageBytes = await _previewCaptureController.captureFromLongWidget(
      InheritedTheme.captureAll(
        currentContext,
        Material(
          color: Colors.transparent,
          child: Center(
            child: _buildPendingPreviewExportWidget(order, detailItems),
          ),
        ),
      ),
      pixelRatio: 2.2,
      context: currentContext,
      delay: const Duration(milliseconds: 120),
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Preview Order Pending'),
        content: SizedBox(
          width: 920,
          height: 620,
          child: InteractiveViewer(
            minScale: 0.4,
            maxScale: 5,
            child: Center(
              child: SingleChildScrollView(
                child: Image.memory(imageBytes, fit: BoxFit.contain),
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tutup'),
          ),
          FilledButton.icon(
            onPressed: () async {
              Navigator.of(dialogContext).pop();
              await _savePreviewImage(order, imageBytes);
            },
            icon: const Icon(Icons.download_outlined),
            label: const Text('Download Gambar'),
          ),
        ],
      ),
    );
  }

  Future<void> _savePreviewImage(
    Map<String, dynamic> order,
    Uint8List bytes,
  ) async {
    try {
      final storeName = order['store_name']?.toString() ?? 'toko';
      final sanitizedStore = storeName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final fileName =
          'pending_order_${sanitizedStore.isEmpty ? 'toko' : sanitizedStore}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';

      final success = await DeviceImageSaver.saveImage(bytes, name: fileName);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? 'Preview gambar berhasil disimpan ke galeri.'
                : 'Gagal menyimpan preview gambar.',
          ),
          backgroundColor: success ? t.success : t.danger,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa menyimpan preview gambar: $e',
      );
    }
  }

  Widget _buildPendingPreviewExportWidget(
    Map<String, dynamic> order,
    List<Map<String, dynamic>> items,
  ) {
    final detail = _detailByOrderId['${order['id'] ?? ''}'];
    final savedOrder = detail == null
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(detail['order'] ?? const {});
    return buildSellInOrderExportWidget(
      storeName: '${order['store_name'] ?? 'Toko'}',
      orderDate: _toDate(order['order_date']) ?? DateTime.now(),
      items: items,
      totalQty: _toInt(order['total_qty']),
      totalValue: _toNum(order['total_value']),
      notes: '${savedOrder['notes'] ?? order['notes'] ?? ''}'.trim(),
      badgeText: '${order['source'] ?? 'sell in'}'.toUpperCase(),
    );
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }

  DateTime? _toDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Finalisasi Sell In'),
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
        surfaceTintColor: t.background,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadAll,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _buildSummaryHeader(),
                  const SizedBox(height: 12),
                  _buildDateFilterBar(),
                  const SizedBox(height: 12),
                  _buildTabBar(),
                  const SizedBox(height: 12),
                  ..._buildActiveSection(),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryHeader() {
    return Row(
      children: [
        Expanded(
          child: _buildSummaryStat(
            label: 'Pending',
            count: _toInt(_summary['pending_order_count']),
            qty: _toInt(_summary['pending_total_qty']),
            value: _toNum(_summary['pending_total_value']),
            tone: t.warning,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryStat(
            label: 'Selesai',
            count: _toInt(_summary['finalized_order_count']),
            qty: _toInt(_summary['finalized_total_qty']),
            value: _toNum(_summary['finalized_total_value']),
            tone: t.success,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryStat(
            label: 'Batal',
            count: _toInt(_summary['cancelled_order_count']),
            qty: _toInt(_summary['cancelled_total_qty']),
            value: _toNum(_summary['cancelled_total_value']),
            tone: t.danger,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryStat({
    required String label,
    required int count,
    required int qty,
    required num value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tone.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: tone,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '$qty unit',
            style: TextStyle(fontSize: 11, color: t.textMutedStrong),
          ),
          const SizedBox(height: 4),
          Text(
            _currency.format(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateFilterBar() {
    final monthLabel = DateFormat('MMMM yyyy', 'id_ID').format(_selectedMonth);
    final dayLabel = _selectedDate == null
        ? 'Semua Tanggal'
        : DateFormat('d MMM yyyy', 'id_ID').format(_selectedDate!);

    return Row(
      children: [
        Expanded(
          child: _buildFilterPill(
            icon: Icons.calendar_month_outlined,
            label: monthLabel,
            onTap: _pickMonth,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildFilterPill(
            icon: Icons.event_outlined,
            label: dayLabel,
            onTap: _pickDate,
          ),
        ),
        if (_selectedDate != null) ...[
          const SizedBox(width: 8),
          SizedBox(
            height: 36,
            child: OutlinedButton(
              onPressed: () async {
                setState(() => _selectedDate = null);
                await _loadAll();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                side: BorderSide(color: t.surface3),
              ),
              child: const Text('Reset'),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFilterPill({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.surface3),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: t.textMutedStrong),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
            ),
            Icon(Icons.expand_more, size: 16, color: t.textMutedStrong),
          ],
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Row(
      children: [
        Expanded(child: _buildTabChip('pending', 'Pending')),
        const SizedBox(width: 8),
        Expanded(child: _buildTabChip('finalized', 'Selesai')),
        const SizedBox(width: 8),
        Expanded(child: _buildTabChip('cancelled', 'Batal')),
      ],
    );
  }

  Widget _buildTabChip(String value, String label) {
    final selected = _activeTab == value;
    final activeColor = switch (value) {
      'finalized' => t.success,
      'cancelled' => t.danger,
      _ => t.warning,
    };
    return InkWell(
      onTap: () => setState(() => _activeTab = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.12) : t.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? activeColor : t.surface3),
        ),
        child: Center(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: selected ? activeColor : t.textMutedStrong,
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActiveSection() {
    switch (_activeTab) {
      case 'finalized':
        return [
          _buildSectionTitle('Order Yang Sudah Diproses'),
          const SizedBox(height: 8),
          if (_finalizedOrders.isEmpty)
            _buildEmptyCard(
              'Belum ada order yang difinalisasi.',
              'Order final akan muncul di sini setelah benar-benar diproses.',
            )
          else
            ..._finalizedOrders.map(_buildFinalizedOrderCard),
        ];
      case 'cancelled':
        return [
          _buildSectionTitle('Order Yang Dibatalkan'),
          const SizedBox(height: 8),
          if (_cancelledOrders.isEmpty)
            _buildEmptyCard(
              'Belum ada order yang dibatalkan.',
              'Order batal akan tersimpan di sini sebagai jejak audit.',
            )
          else
            ..._cancelledOrders.map(_buildCancelledOrderCard),
        ];
      default:
        return [
          _buildSectionTitle('Review Order'),
          const SizedBox(height: 8),
          if (_pendingOrders.isEmpty)
            _buildEmptyCard(
              'Belum ada order pending.',
              'Simpan draft dari menu rekomendasi atau order manual terlebih dahulu.',
            )
          else
            ..._pendingOrders.map(_buildPendingOrderCard),
        ];
    }
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w800,
        color: t.textPrimary,
      ),
    );
  }

  Widget _buildPendingOrderCard(Map<String, dynamic> order) {
    final orderId = '${order['id'] ?? ''}';
    final detail = _detailByOrderId[orderId];
    final detailItems = detail == null
        ? const <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(detail['items'] ?? const []);
    final isLoadingDetail = _loadingDetailIds.contains(orderId);
    final isFinalizing = _finalizingIds.contains(orderId);
    final isCancelling = _cancellingIds.contains(orderId);
    final orderDate = _toDate(order['order_date']);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        onExpansionChanged: (expanded) {
          if (expanded) _loadOrderDetail(orderId);
        },
        tilePadding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        title: Text(
          '${order['store_name'] ?? 'Toko'}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_normalizedGroupName(order['group_name']).isNotEmpty)
                Text(_normalizedGroupName(order['group_name'])),
              Text(
                [
                  if (orderDate != null) _dateFormat.format(orderDate),
                  '${order['source'] ?? '-'}',
                  '${_toInt(order['total_qty'])} unit',
                ].join(' • '),
              ),
            ],
          ),
        ),
        trailing: Text(
          _currency.format(_toNum(order['total_value'])),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: t.primaryAccent,
          ),
        ),
        children: [
          if (isLoadingDetail)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (detailItems.isEmpty)
            Text(
              'Detail item belum tersedia.',
              style: TextStyle(color: t.textMutedStrong),
            )
          else ...[
            ...detailItems.map(_buildDetailItemRow),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: isFinalizing || isCancelling
                    ? null
                    : () => _showOrderPreview(order),
                icon: const Icon(Icons.image_outlined),
                label: const Text('Lihat Preview Gambar'),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: isFinalizing || isCancelling
                        ? null
                        : () => _finalizeOrder(order),
                    icon: isFinalizing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: Text(
                      isFinalizing ? 'Memfinalisasi...' : 'Finalisasi',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: isFinalizing || isCancelling
                        ? null
                        : () => _showCancelDialog(order),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.danger,
                      side: BorderSide(color: t.danger.withValues(alpha: 0.45)),
                    ),
                    icon: isCancelling
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.close_rounded),
                    label: Text(isCancelling ? 'Membatalkan...' : 'Batalkan'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailItemRow(Map<String, dynamic> item) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.surface3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item['product_name'] ?? 'Produk'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${item['network_type'] ?? '-'} • ${item['variant'] ?? '-'} • ${item['color'] ?? '-'}',
                  style: TextStyle(fontSize: 12, color: t.textMutedStrong),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${_toInt(item['qty'])} unit',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: t.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _currency.format(_toNum(item['subtotal'])),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.primaryAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinalizedOrderCard(Map<String, dynamic> order) {
    final orderDate = _toDate(order['order_date']);
    final finalizedAt = _toDate(order['finalized_at']);
    final storeName = order['store_name']?.toString() ?? 'Order';
    final groupName = _normalizedGroupName(order['group_name']);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: t.success.withValues(alpha: 0.12),
          foregroundColor: t.success,
          child: const Icon(Icons.check_circle),
        ),
        title: Text(
          storeName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
        subtitle: Text(
          [
            if (groupName.isNotEmpty) groupName,
            if (orderDate != null) _dateFormat.format(orderDate),
            '${order['source'] ?? '-'}',
            if (finalizedAt != null)
              'Final ${DateFormat('d MMM HH:mm', 'id_ID').format(finalizedAt)}',
          ].join(' • '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${_toInt(order['total_qty'])} unit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _currency.format(_toNum(order['total_value'])),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: t.primaryAccent,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelledOrderCard(Map<String, dynamic> order) {
    final orderDate = _toDate(order['order_date']);
    final cancelledAt = _toDate(order['cancelled_at']);
    final storeName = order['store_name']?.toString() ?? 'Order';
    final groupName = _normalizedGroupName(order['group_name']);
    final cancellationReason = '${order['cancellation_reason'] ?? ''}'.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        dense: true,
        leading: CircleAvatar(
          backgroundColor: t.danger.withValues(alpha: 0.12),
          foregroundColor: t.danger,
          child: const Icon(Icons.close_rounded),
        ),
        title: Text(
          storeName,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
        subtitle: Text(
          [
            if (groupName.isNotEmpty) groupName,
            if (orderDate != null) _dateFormat.format(orderDate),
            '${order['source'] ?? '-'}',
            if (cancellationReason.isNotEmpty) cancellationReason,
            if (cancelledAt != null)
              'Batal ${DateFormat('d MMM HH:mm', 'id_ID').format(cancelledAt)}',
          ].join(' • '),
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${_toInt(order['total_qty'])} unit',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              _currency.format(_toNum(order['total_value'])),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: t.danger,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyCard(String title, String subtitle) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 36, color: t.textMuted),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: t.textMutedStrong),
            ),
          ],
        ),
      ),
    );
  }
}
