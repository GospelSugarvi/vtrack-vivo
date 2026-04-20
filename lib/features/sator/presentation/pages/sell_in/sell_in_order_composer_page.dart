import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/core/utils/device_image_saver.dart';
import 'package:vtrack/core/utils/success_dialog.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import 'sell_in_order_export_widget.dart';

enum SellInOrderComposerMode { recommendation, manual }

class SellInOrderComposerPage extends StatefulWidget {
  final SellInOrderComposerMode mode;
  final String? storeId;
  final String? groupId;

  const SellInOrderComposerPage({
    super.key,
    required this.mode,
    this.storeId,
    this.groupId,
  });

  @override
  State<SellInOrderComposerPage> createState() =>
      _SellInOrderComposerPageState();
}

class _SellInOrderComposerPageState extends State<SellInOrderComposerPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _screenshotController = ScreenshotController();
  final _notesController = TextEditingController();
  final _searchController = TextEditingController();
  final _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSyncingPreview = false;
  String _searchQuery = '';
  String _seriesFilter = 'Y';
  String? _selectedStoreId;
  String _selectedStoreName = 'Pilih toko';
  String _currentUserName = 'SATOR';
  List<Map<String, dynamic>> _stores = const [];
  List<Map<String, dynamic>> _rows = const [];
  Map<String, dynamic>? _serverPreview;
  Timer? _previewSyncDebounce;
  final Set<String> _expandedModelKeys = <String>{};

  bool get _isRecommendation =>
      widget.mode == SellInOrderComposerMode.recommendation;
  bool get _isGroupMode => (widget.groupId ?? '').trim().isNotEmpty;

  String get _pageTitle =>
      _isRecommendation ? 'Rekomendasi Sell In' : 'Order Manual';

  String get _saveLabel =>
      _isRecommendation ? 'Preview Gambar Rekomendasi' : 'Preview Draft Manual';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _previewSyncDebounce?.cancel();
    _notesController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final snapshotRaw = await _supabase.rpc(
        'get_sell_in_order_composer_snapshot',
        params: {
          'p_mode': _isRecommendation ? 'recommendation' : 'manual',
          'p_store_id': widget.storeId,
          'p_group_id': widget.groupId,
        },
      );
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final stores = _parseMapList(snapshot['stores']);
      final rows = _parseMapList(snapshot['rows']);
      final selectedStoreId = snapshot['selected_store_id']?.toString();
      final selectedStoreName =
          '${snapshot['selected_store_name'] ?? _selectedStoreName}';
      final currentUserName =
          '${snapshot['current_user_name'] ?? _currentUserName}';

      if (!mounted) return;
      setState(() {
        _stores = stores;
        _selectedStoreId = selectedStoreId;
        _selectedStoreName = selectedStoreName;
        _currentUserName = currentUserName;
        _rows = rows;
        _seriesFilter = _defaultSeriesFilter(rows);
        _isLoading = false;
        _serverPreview = null;
      });
      _scheduleServerPreviewSync(immediate: true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stores = const [];
        _rows = const [];
        _isLoading = false;
      });
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa memuat data sell in: $e',
      );
    }
  }

  Future<void> _onStoreChanged(String? storeId) async {
    if (storeId == null || storeId.isEmpty || storeId == _selectedStoreId) {
      return;
    }

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _selectedStoreId = storeId;
      _rows = const [];
    });

    try {
      final snapshotRaw = await _supabase.rpc(
        'get_sell_in_order_composer_snapshot',
        params: {
          'p_mode': _isRecommendation ? 'recommendation' : 'manual',
          'p_store_id': storeId,
          'p_group_id': widget.groupId,
        },
      );
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final rows = _parseMapList(snapshot['rows']);
      if (!mounted) return;
      setState(() {
        _stores = _parseMapList(snapshot['stores']);
        _selectedStoreName = '${snapshot['selected_store_name'] ?? 'Toko'}';
        _rows = rows;
        _seriesFilter = _defaultSeriesFilter(rows);
        _isLoading = false;
        _serverPreview = null;
      });
      _scheduleServerPreviewSync(immediate: true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa memuat produk toko ini: $e',
      );
    }
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }

  void _changeQty(int index, int delta) {
    final rows = List<Map<String, dynamic>>.from(_rows);
    final current = _toInt(rows[index]['selected_qty']);
    final maxQty = _maxSelectableQty(rows[index]);
    rows[index] = {
      ...rows[index],
      'selected_qty': (current + delta).clamp(0, maxQty),
    };
    setState(() {
      _rows = rows;
      _serverPreview = null;
    });
    _scheduleServerPreviewSync();
  }

  List<Map<String, dynamic>> get _filteredRows {
    return _rows.where((row) {
      final product = '${row['product_name'] ?? ''}'.toLowerCase();
      final variant = '${row['variant'] ?? ''}'.toLowerCase();
      final color = '${row['color'] ?? ''}'.toLowerCase();
      final series = _seriesForRow(row).toLowerCase();
      final matchesSeries = series == _seriesFilter.toLowerCase();
      final matchesQuery =
          _searchQuery.isEmpty ||
          product.contains(_searchQuery) ||
          variant.contains(_searchQuery) ||
          color.contains(_searchQuery);
      return matchesSeries && matchesQuery;
    }).toList();
  }

  List<String> get _availableSeries {
    return const ['Y', 'V', 'X', 'IQOO'];
  }

  List<MapEntry<String, List<Map<String, dynamic>>>> get _groupedModelRows {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in _filteredRows) {
      final key =
          '${row['product_name'] ?? ''}|${row['variant'] ?? ''}|${_seriesForRow(row)}';
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
    }
    final entries = grouped.entries.toList()
      ..sort((a, b) {
        final priceA = a.value.isEmpty ? 0 : _toNum(a.value.first['price']);
        final priceB = b.value.isEmpty ? 0 : _toNum(b.value.first['price']);
        final priceCompare = priceA.compareTo(priceB);
        if (priceCompare != 0) return priceCompare;
        return a.key.compareTo(b.key);
      });
    for (final entry in entries) {
      entry.value.sort((a, b) {
        final priceA = _toNum(a['price']);
        final priceB = _toNum(b['price']);
        final priceCompare = priceA.compareTo(priceB);
        if (priceCompare != 0) return priceCompare;
        return '${a['color'] ?? ''}'.compareTo('${b['color'] ?? ''}');
      });
    }
    return entries;
  }

  String _seriesForRow(Map<String, dynamic> row) {
    final name = '${row['product_name'] ?? ''}'.trim().toUpperCase();
    if (name.contains('IQOO')) return 'IQOO';
    if (name.startsWith('Y')) return 'Y';
    if (name.startsWith('V')) return 'V';
    if (name.startsWith('X')) return 'X';
    return '';
  }

  String _defaultSeriesFilter(List<Map<String, dynamic>> rows) {
    const ordered = ['Y', 'V', 'X', 'IQOO'];
    for (final series in ordered) {
      if (rows.any((row) => _seriesForRow(row) == series)) {
        return series;
      }
    }
    return 'Y';
  }

  List<Map<String, dynamic>> get _selectedItems {
    return _rows.where((row) => _toInt(row['selected_qty']) > 0).toList();
  }

  int get _selectedTotalQty {
    return _toInt(_serverPreview?['total_qty']);
  }

  int get _selectedTotalItems {
    return _toInt(_serverPreview?['total_items']);
  }

  num get _selectedTotalValue {
    return _toNum(_serverPreview?['total_value']);
  }

  List<Map<String, dynamic>> get _serverPreviewItems {
    return List<Map<String, dynamic>>.from(
      _serverPreview?['items'] ?? const [],
    );
  }

  Map<String, Map<String, dynamic>> get _serverPreviewItemByVariantId {
    return {
      for (final item in _serverPreviewItems)
        '${item['variant_id'] ?? ''}': item,
    };
  }

  Future<void> _refreshServerPreview() async {
    final storeId = _selectedStoreId;
    final groupId = widget.groupId?.trim();
    final selected = _selectedItems
        .map(
          (row) => {
            'variant_id': row['variant_id'],
            'qty': _toInt(row['selected_qty']),
          },
        )
        .toList();

    if (((_isGroupMode && (groupId == null || groupId.isEmpty)) ||
            (!_isGroupMode && (storeId == null || storeId.isEmpty))) ||
        selected.isEmpty) {
      if (!mounted) return;
      setState(() {
        _serverPreview = null;
        _isSyncingPreview = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _isSyncingPreview = true);
    }

    try {
      final response = _isGroupMode
          ? await _supabase.rpc(
              'get_sell_in_group_order_preview',
              params: {'p_group_id': groupId, 'p_items': selected},
            )
          : await _supabase.rpc(
              'get_sell_in_order_preview',
              params: {'p_store_id': storeId, 'p_items': selected},
            );
      if (!mounted) return;
      setState(() {
        _serverPreview = Map<String, dynamic>.from(response ?? const {});
        _isSyncingPreview = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isSyncingPreview = false);
    }
  }

  void _scheduleServerPreviewSync({bool immediate = false}) {
    _previewSyncDebounce?.cancel();
    if (immediate) {
      unawaited(_refreshServerPreview());
      return;
    }
    _previewSyncDebounce = Timer(
      const Duration(milliseconds: 220),
      () => unawaited(_refreshServerPreview()),
    );
  }

  Future<void> _handlePrimaryAction() async {
    await _showOrderPreview();
  }

  Future<void> _saveDraft() async {
    final userId = _supabase.auth.currentUser?.id;
    final storeId = _selectedStoreId;
    final groupId = widget.groupId?.trim();
    if (userId == null) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Sesi login tidak ditemukan.',
      );
      return;
    }
    if (!_isGroupMode && (storeId == null || storeId.isEmpty)) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Pilih toko terlebih dahulu.',
      );
      return;
    }
    if (_isGroupMode && (groupId == null || groupId.isEmpty)) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Grup toko tidak ditemukan.',
      );
      return;
    }
    if (_selectedItems.isEmpty) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Belum ada item yang dipilih untuk disimpan.',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      final params = {
        'p_sator_id': userId,
        'p_order_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'p_source': _isRecommendation ? 'recommendation' : 'manual',
        'p_notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'p_items': _selectedItems
            .map(
              (row) => {
                'variant_id': row['variant_id'],
                'qty': _toInt(row['selected_qty']),
              },
            )
            .toList(),
      };

      await _supabase.rpc(
        _isGroupMode
            ? 'save_sell_in_group_order_draft'
            : 'save_sell_in_order_draft',
        params: _isGroupMode
            ? {...params, 'p_group_id': groupId}
            : {...params, 'p_store_id': storeId},
      );

      if (!mounted) return;
      setState(() => _isSaving = false);
      await showSuccessDialog(
        context,
        title: 'Draft Tersimpan',
        message:
            'Order untuk $_selectedStoreName disimpan ke pending finalisasi.',
      );
      if (!mounted) return;
      context.push('/sator/sell-in/finalisasi');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa menyimpan draft order: $e',
      );
    }
  }

  Future<void> _showOrderPreview() async {
    if (_selectedItems.isEmpty) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Pilih minimal 1 item untuk dibuatkan preview.',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      await _refreshServerPreview();
      if (_serverPreviewItems.isEmpty) {
        throw Exception('Preview order dari server kosong.');
      }
      if (!mounted || !context.mounted) return;
      final imageBytes = await _screenshotController.captureFromLongWidget(
        InheritedTheme.captureAll(
          context,
          Material(
            color: Colors.transparent,
            child: Center(child: _buildRecommendationExportWidget()),
          ),
        ),
        pixelRatio: 2.2,
        context: context,
        delay: const Duration(milliseconds: 120),
      );

      if (!mounted) return;
      setState(() => _isSaving = false);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(
            _isRecommendation ? 'Preview Rekomendasi' : 'Preview Order Manual',
          ),
          content: SizedBox(
            width: 920,
            height: 620,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    Text(
                      'Preview utuh. Zoom bila perlu.',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: t.textMutedStrong,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: InteractiveViewer(
                        minScale: 0.4,
                        maxScale: 5,
                        child: Center(
                          child: SingleChildScrollView(
                            child: Image.memory(
                              imageBytes,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Tutup'),
            ),
            if (!_isRecommendation)
              TextButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
                  await _saveDraft();
                },
                child: const Text('Simpan Draft'),
              ),
            FilledButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                await _saveOrderImage(imageBytes);
              },
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download Gambar'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa membuat preview gambar: $e',
      );
    }
  }

  Future<void> _saveOrderImage(Uint8List bytes) async {
    try {
      final sanitizedStore = _selectedStoreName
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
          .replaceAll(RegExp(r'_+'), '_')
          .replaceAll(RegExp(r'^_|_$'), '');
      final prefix = _isRecommendation ? 'rekomendasi' : 'order_manual';
      final fileName =
          '${prefix}_${sanitizedStore.isEmpty ? 'toko' : sanitizedStore}_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}';

      if (!kIsWeb) {
        final success = await DeviceImageSaver.saveImage(bytes, name: fileName);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              success
                  ? (_isRecommendation
                        ? 'Gambar rekomendasi tersimpan di galeri'
                        : 'Gambar order manual tersimpan di galeri')
                  : (_isRecommendation
                        ? 'Gagal menyimpan gambar rekomendasi'
                        : 'Gagal menyimpan gambar order manual'),
            ),
            backgroundColor: success ? t.success : t.danger,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan gambar: $e'),
          backgroundColor: t.danger,
        ),
      );
    }
  }

  Color _statusColor(String status) {
    switch (status.toUpperCase()) {
      case 'HABIS':
        return t.danger;
      case 'KURANG':
        return t.warning;
      case 'CUKUP':
      case 'READY':
        return t.success;
      default:
        return t.textMuted;
    }
  }

  Color _recommendationColor(String status) {
    switch (status.toUpperCase()) {
      case 'READY_TO_ORDER':
        return t.success;
      case 'LIMITED_GUDANG':
        return t.warning;
      case 'NO_GUDANG':
        return t.danger;
      case 'NO_NEED':
        return t.textMuted;
      default:
        return t.textMuted;
    }
  }

  String _recommendationLabel(String status) {
    switch (status.toUpperCase()) {
      case 'READY_TO_ORDER':
        return 'Siap Order';
      case 'LIMITED_GUDANG':
        return 'Gudang Terbatas';
      case 'NO_GUDANG':
        return 'Gudang Kosong';
      case 'NO_NEED':
        return 'Stok Toko Aman';
      default:
        return status;
    }
  }

  int _displayQty(Map<String, dynamic> row) {
    final selected = _toInt(row['selected_qty']);
    if (selected > 0) return selected;
    final qty = _toInt(row['qty']);
    if (qty > 0) return qty;
    return _toInt(row['order_qty']);
  }

  String _storeStockLabel(int currentStock, int minStock) {
    if (currentStock <= 0) return 'Habis';
    if (currentStock < minStock) return 'Kurang';
    return 'Ready';
  }

  Color _warehouseStockColor(int warehouseStock) {
    if (warehouseStock <= 0) return t.danger;
    if (warehouseStock < 5) return t.warning;
    return t.success;
  }

  Color _statusSurface(Color color) {
    return Color.alphaBlend(color.withValues(alpha: 0.10), t.surface1);
  }

  Color _statusStroke(Color color) {
    return color.withValues(alpha: 0.16);
  }

  Color _statusInk(Color color) {
    return Color.lerp(color, t.textPrimary, 0.38) ?? color;
  }

  String _warehouseStockLabel(int warehouseStock) {
    if (warehouseStock <= 0) return 'Kosong';
    return 'Ready';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int _maxSelectableQty(Map<String, dynamic> row) {
    final availableGudang = _toInt(row['available_gudang']);
    final warehouseStock = _toInt(row['warehouse_stock']);
    final maxQty = availableGudang > 0 ? availableGudang : warehouseStock;
    return maxQty < 0 ? 0 : maxQty;
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }

  Widget _buildRecommendationExportWidget() {
    return buildSellInOrderExportWidget(
      storeName: _selectedStoreName,
      orderDate: DateTime.now(),
      authorName: _currentUserName,
      items: List<Map<String, dynamic>>.from(_serverPreviewItems),
      totalQty: _selectedTotalQty,
      totalValue: _selectedTotalValue,
      notes: _notesController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: Text(_pageTitle),
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
        surfaceTintColor: t.background,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadInitialData,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
                children: [
                  _buildControls(),
                  const SizedBox(height: 10),
                  if (_groupedModelRows.isEmpty)
                    _buildEmptyState()
                  else ...[
                    ..._groupedModelRows.map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _buildModelGroup(group.key, group.value),
                      ),
                    ),
                  ],
                  if (!_isRecommendation) ...[
                    const SizedBox(height: 4),
                    _buildNotesField(),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
          decoration: BoxDecoration(
            color: t.background,
            border: Border(top: BorderSide(color: t.surface3)),
          ),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.surface3),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '$_selectedTotalItems item • $_selectedTotalQty unit',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    Text(
                      _isSyncingPreview
                          ? '...'
                          : _currency.format(_selectedTotalValue),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: t.primaryAccent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _isSaving ? null : _handlePrimaryAction,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            _isRecommendation
                                ? Icons.image_outlined
                                : Icons.save_outlined,
                          ),
                    label: Text(
                      _isSaving
                          ? (_isRecommendation
                                ? 'Menyiapkan Preview...'
                                : 'Menyimpan...')
                          : _saveLabel,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildControlSectionLabel(
              _isGroupMode ? 'Pencarian Produk' : 'Toko & Pencarian',
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isGroupMode)
                  Expanded(
                    flex: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.surface3),
                      ),
                      child: DropdownButtonFormField<String>(
                        key: ValueKey(_selectedStoreId),
                        initialValue: _selectedStoreId,
                        isExpanded: true,
                        icon: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: t.textMutedStrong,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Nama Toko',
                          labelStyle: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: t.textMutedStrong,
                          ),
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                        ),
                        dropdownColor: t.background,
                        items: _stores
                            .map(
                              (store) => DropdownMenuItem<String>(
                                value: store['store_id']?.toString(),
                                child: Text(
                                  [
                                    '${store['store_name'] ?? 'Toko'}',
                                    if (_shouldShowStoreGroupName(
                                      store['group_name'],
                                    ))
                                      '${store['group_name']}',
                                  ].join(' • '),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: t.textPrimary,
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: _onStoreChanged,
                      ),
                    ),
                  ),
                if (!_isGroupMode) const SizedBox(width: 8),
                Expanded(
                  flex: _isGroupMode ? 1 : 5,
                  child: Container(
                    decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.surface3),
                    ),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(
                        () => _searchQuery = value.trim().toLowerCase(),
                      ),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Cari produk atau warna',
                        hintStyle: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: t.textMuted,
                        ),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: t.textMutedStrong,
                        ),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _buildControlSectionLabel('Seri Produk'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: t.surface3),
              ),
              child: Row(
                children: _availableSeries
                    .map(
                      (series) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            right: series == _availableSeries.last ? 0 : 6,
                          ),
                          child: _buildFilterChip(series, series),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlSectionLabel(String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.8,
        color: t.textMutedStrong,
      ),
    );
  }

  Widget _buildNotesField() {
    return Card(
      margin: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.surface3),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'NOTES',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: t.textMutedStrong,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.surface3),
                ),
                child: TextField(
                  controller: _notesController,
                  minLines: 2,
                  maxLines: 3,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Contoh: batas transfer jam 3 sore',
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _shouldShowStoreGroupName(dynamic groupName) {
    final normalized = '${groupName ?? ''}'.trim();
    if (normalized.isEmpty) return false;
    final lower = normalized.toLowerCase();
    return lower != 'ungrouped' && !lower.startsWith('ungrouped ');
  }

  Widget _buildFilterChip(String value, String label) {
    final selected = _seriesFilter == value;
    return ChoiceChip(
      label: SizedBox(
        width: double.infinity,
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? t.textOnAccent : t.textMutedStrong,
            letterSpacing: 0.25,
          ),
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _seriesFilter = value),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: EdgeInsets.zero,
      side: BorderSide(
        color: selected ? t.primaryAccent : Colors.transparent,
        width: selected ? 1.3 : 1,
      ),
      backgroundColor: t.background,
      selectedColor: t.primaryAccent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  Widget _buildModelGroup(String key, List<Map<String, dynamic>> rows) {
    final first = rows.first;
    final productName = '${first['product_name'] ?? 'Produk'}';
    final variantLabel = '${first['variant'] ?? '-'}';
    final totalStoreStock = rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['current_stock']),
    );
    final totalMinStock = rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['min_stock']),
    );
    final totalWarehouseStock = rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['warehouse_stock']),
    );
    final storeTone = _statusColor(
      totalStoreStock <= 0
          ? 'HABIS'
          : totalStoreStock < totalMinStock
          ? 'KURANG'
          : 'CUKUP',
    );
    final storeLabel = _storeStockLabel(totalStoreStock, totalMinStock);
    final warehouseTone = _warehouseStockColor(totalWarehouseStock);
    final warehouseLabel = _warehouseStockLabel(totalWarehouseStock);
    final isExpanded = _expandedModelKeys.contains(key);

    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isExpanded ? t.primaryAccentSoft : t.surface3,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(key),
          tilePadding: const EdgeInsets.fromLTRB(10, 6, 10, 5),
          childrenPadding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
          minTileHeight: 52,
          initiallyExpanded: isExpanded,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          trailing: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: isExpanded ? t.primaryAccentSoft : t.surface2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isExpanded
                    ? t.primaryAccent.withValues(alpha: 0.28)
                    : t.surface3,
              ),
            ),
            child: Icon(
              isExpanded
                  ? Icons.keyboard_arrow_up_rounded
                  : Icons.keyboard_arrow_down_rounded,
              size: 14,
              color: isExpanded ? t.primaryAccent : t.textMutedStrong,
            ),
          ),
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedModelKeys.add(key);
              } else {
                _expandedModelKeys.remove(key);
              }
            });
          },
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          productName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w900,
                            color: t.textPrimary,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 0),
                        Text(
                          variantLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: t.textMutedStrong,
                            letterSpacing: 0.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Flexible(
                    child: _buildHeaderInlineStatus(
                      icon: Icons.storefront_outlined,
                      title: 'Toko',
                      status: storeLabel,
                      value: '$totalStoreStock',
                      color: storeTone,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Flexible(
                    child: _buildHeaderInlineStatus(
                      icon: Icons.warehouse_outlined,
                      title: 'Gudang',
                      status: warehouseLabel,
                      value: '$totalWarehouseStock',
                      color: warehouseTone,
                    ),
                  ),
                ],
              ),
            ],
          ),
          children: rows
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: _buildProductCard(row),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildHeaderInlineStatus({
    required IconData icon,
    required String title,
    required String status,
    required String value,
    required Color color,
  }) {
    final surfaceColor = _statusSurface(color);
    final borderColor = _statusStroke(color);
    final inkColor = _statusInk(color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: inkColor),
          const SizedBox(width: 2),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w800,
                      color: inkColor,
                    ),
                  ),
                  const SizedBox(width: 1),
                  Text(
                    status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: inkColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: inkColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> row) {
    final qty = _toInt(row['selected_qty']);
    final currentStock = _toInt(row['current_stock']);
    final minStock = _toInt(row['min_stock']);
    final shortageQty = _toInt(row['shortage_qty']);
    final warehouseStock = _toInt(row['warehouse_stock']);
    final maxSelectableQty = _maxSelectableQty(row);
    final unfulfilledQty = _toInt(row['unfulfilled_qty']);
    final statusColor = _statusColor('${row['status'] ?? 'CUKUP'}');
    final storeStockLabel = _storeStockLabel(currentStock, minStock);
    final warehouseTone = _warehouseStockColor(warehouseStock);
    final warehouseLabel = _warehouseStockLabel(warehouseStock);
    final recommendationStatus = '${row['recommendation_status'] ?? ''}';
    final recommendationColor = _recommendationColor(recommendationStatus);
    final storeSurfaceColor = _statusSurface(statusColor);
    final storeBorderColor = _statusStroke(statusColor);
    final storeInkColor = _statusInk(statusColor);
    final warehouseSurfaceColor = _statusSurface(warehouseTone);
    final warehouseBorderColor = _statusStroke(warehouseTone);
    final warehouseInkColor = _statusInk(warehouseTone);
    final previewItem =
        _serverPreviewItemByVariantId['${row['variant_id'] ?? ''}'];
    final previewQty = _displayQty(
      Map<String, dynamic>.from(previewItem ?? const {}),
    );
    final lineSubtotal = _toNum(previewItem?['subtotal']);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.surface3.withValues(alpha: 0.85)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['product_name'] ?? 'Produk'}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${row['variant'] ?? '-'} • ${row['color'] ?? '-'}',
                      style: TextStyle(fontSize: 11, color: t.textMutedStrong),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: storeSurfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: storeBorderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.storefront_outlined,
                        size: 11,
                        color: storeInkColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'Stok toko $storeStockLabel',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: storeInkColor,
                          ),
                        ),
                      ),
                      Text(
                        '$currentStock',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: storeInkColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: warehouseSurfaceColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: warehouseBorderColor),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warehouse_outlined,
                        size: 11,
                        color: warehouseInkColor,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Gudang $warehouseLabel',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                              color: warehouseInkColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$warehouseStock',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          color: warehouseInkColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          if (_isRecommendation) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                color: recommendationColor.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: recommendationColor.withValues(alpha: 0.22),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.inventory_outlined,
                    size: 16,
                    color: recommendationColor,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _recommendationLabel(recommendationStatus),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: recommendationColor,
                      ),
                    ),
                  ),
                  if (unfulfilledQty > 0)
                    Text(
                      'Kurang $unfulfilledQty',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: recommendationColor,
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _metricChip('Min', '$minStock')),
              const SizedBox(width: 6),
              Expanded(child: _metricChip('Butuh', '$shortageQty')),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _metricChip(
                  'Harga Modal',
                  _currency.format(_toNum(row['modal'])),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _metricChip(
                  'Harga SRP',
                  _currency.format(_toNum(row['price'])),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _qtyButton(
                Icons.remove,
                qty > 0 ? () => _changeQty(_rows.indexOf(row), -1) : null,
              ),
              Container(
                width: 44,
                alignment: Alignment.center,
                child: Text(
                  '$qty',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              _qtyButton(
                Icons.add,
                qty < maxSelectableQty
                    ? () => _changeQty(_rows.indexOf(row), 1)
                    : null,
              ),
              const Spacer(),
              Text(
                qty > 0 && previewItem == null
                    ? '...'
                    : _currency.format(lineSubtotal),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: qty > 0 ? t.primaryAccent : t.textMuted,
                ),
              ),
            ],
          ),
          if (previewQty > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Qty preview $previewQty unit',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback? onTap) {
    final isEnabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isEnabled ? t.surface2 : t.surface1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.surface3),
        ),
        child: Icon(
          icon,
          size: 16,
          color: isEnabled ? t.textPrimary : t.textMuted,
        ),
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w800,
              color: t.textMutedStrong,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              color: t.textPrimary,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.inventory_2_outlined, size: 40, color: t.textMuted),
            const SizedBox(height: 10),
            Text(
              _isRecommendation
                  ? 'Belum ada rekomendasi order untuk toko ini.'
                  : 'Tidak ada produk yang cocok dengan filter saat ini.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: t.textMutedStrong,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
