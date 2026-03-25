import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_gallery_saver_plus/image_gallery_saver_plus.dart';
import 'package:intl/intl.dart';
import 'package:screenshot/screenshot.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/core/utils/success_dialog.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

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
  static const double _exportCanvasWidth = 860;
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
  final _amount = NumberFormat.decimalPattern('id_ID');

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

  String get _exportDocumentTitle =>
      _isRecommendation ? 'REKOMENDASI ORDER SELL IN' : 'ORDER MANUAL SELL IN';

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
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Sesi login tidak ditemukan');

      final currentUserName = await _loadCurrentUserName(userId);
      final storeResponse = await _supabase.rpc(
        'get_store_stock_status',
        params: {'p_sator_id': userId},
      );
      final stores = List<Map<String, dynamic>>.from(storeResponse ?? []);

      if (_isGroupMode) {
        final groupId = widget.groupId!.trim();
        final groupName = await _loadGroupName(groupId);
        final rows = await _loadGroupRecommendationRows(groupId);
        if (!mounted) return;
        setState(() {
          _stores = const [];
          _selectedStoreId = null;
          _selectedStoreName = groupName;
          _currentUserName = currentUserName;
          _rows = rows;
          _seriesFilter = _defaultSeriesFilter(rows);
          _isLoading = false;
          _serverPreview = null;
        });
        _scheduleServerPreviewSync(immediate: true);
        return;
      }

      String? selectedStoreId = widget.storeId;
      String selectedStoreName = _selectedStoreName;

      if (selectedStoreId == null || selectedStoreId.isEmpty) {
        if (stores.isNotEmpty) {
          selectedStoreId = stores.first['store_id']?.toString();
          selectedStoreName = '${stores.first['store_name'] ?? 'Toko'}';
        }
      } else {
        final matchedStore = stores.cast<Map<String, dynamic>?>().firstWhere(
          (row) => row?['store_id']?.toString() == selectedStoreId,
          orElse: () => null,
        );
        if (matchedStore != null) {
          selectedStoreName = '${matchedStore['store_name'] ?? 'Toko'}';
        } else {
          final store = await _supabase
              .from('stores')
              .select('store_name')
              .eq('id', selectedStoreId)
              .maybeSingle();
          selectedStoreName = '${store?['store_name'] ?? 'Toko'}';
          if (store != null) {
            stores.insert(0, {
              'store_id': selectedStoreId,
              'store_name': selectedStoreName,
              'group_name': '',
              'empty_count': 0,
              'low_count': 0,
            });
          }
        }
      }

      final rows = selectedStoreId == null || selectedStoreId.isEmpty
          ? const <Map<String, dynamic>>[]
          : await _loadRecommendationRows(selectedStoreId);

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

  Future<String> _loadCurrentUserName(String userId) async {
    try {
      final row = await _supabase
          .from('users')
          .select('full_name')
          .eq('id', userId)
          .maybeSingle();
      final fullName = '${row?['full_name'] ?? ''}'.trim();
      if (fullName.isNotEmpty) return fullName;
    } catch (_) {}

    final metadata =
        _supabase.auth.currentUser?.userMetadata ?? const <String, dynamic>{};
    final fallback = '${metadata['full_name'] ?? metadata['name'] ?? ''}'
        .trim();
    if (fallback.isNotEmpty) return fallback;
    return 'SATOR';
  }

  Future<String> _loadGroupName(String groupId) async {
    final row = await _supabase
        .from('store_groups')
        .select('group_name')
        .eq('id', groupId)
        .maybeSingle();
    return '${row?['group_name'] ?? 'Grup Toko'}';
  }

  Future<List<Map<String, dynamic>>> _loadRecommendationRows(
    String storeId,
  ) async {
    final response = await _supabase.rpc(
      'get_store_recommendations',
      params: {'p_store_id': storeId},
    );
    final rows = List<Map<String, dynamic>>.from(response ?? []);

    final normalized = rows
        .map((row) {
          final orderQty = _toInt(row['order_qty']);
          final variantId = '${row['variant_id'] ?? ''}';
          return {
            ...row,
            'variant_id': variantId,
            'product_name': '${row['product_name'] ?? 'Produk'}',
            'network_type': '${row['network_type'] ?? ''}',
            'variant': '${row['variant'] ?? '-'}',
            'color': '${row['color'] ?? '-'}',
            'modal': _toNum(row['modal']),
            'selected_qty': _isRecommendation ? orderQty : 0,
          };
        })
        .where((row) {
          if (!_isRecommendation) return true;
          return _toInt(row['order_qty']) > 0;
        })
        .toList();

    normalized.sort((a, b) {
      final orderCompare = _toInt(
        b['order_qty'],
      ).compareTo(_toInt(a['order_qty']));
      if (orderCompare != 0) return orderCompare;
      return '${a['product_name']}'.compareTo('${b['product_name']}');
    });

    return normalized;
  }

  Future<List<Map<String, dynamic>>> _loadGroupRecommendationRows(
    String groupId,
  ) async {
    final response = await _supabase.rpc(
      'get_group_store_recommendations',
      params: {'p_group_id': groupId},
    );
    final rows = List<Map<String, dynamic>>.from(response ?? []);

    final normalized = rows
        .map((row) {
          final orderQty = _toInt(row['order_qty']);
          final variantId = '${row['variant_id'] ?? ''}';
          return {
            ...row,
            'variant_id': variantId,
            'product_name': '${row['product_name'] ?? 'Produk'}',
            'network_type': '${row['network_type'] ?? ''}',
            'variant': '${row['variant'] ?? '-'}',
            'color': '${row['color'] ?? '-'}',
            'modal': _toNum(row['modal']),
            'selected_qty': _isRecommendation ? orderQty : 0,
          };
        })
        .where((row) {
          if (!_isRecommendation) return true;
          return _toInt(row['order_qty']) > 0;
        })
        .toList();

    normalized.sort((a, b) {
      final orderCompare = _toInt(
        b['order_qty'],
      ).compareTo(_toInt(a['order_qty']));
      if (orderCompare != 0) return orderCompare;
      return '${a['product_name']}'.compareTo('${b['product_name']}');
    });

    return normalized;
  }

  Future<void> _onStoreChanged(String? storeId) async {
    if (storeId == null || storeId.isEmpty || storeId == _selectedStoreId) {
      return;
    }

    final matchedStore = _stores.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['store_id']?.toString() == storeId,
      orElse: () => null,
    );

    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _selectedStoreId = storeId;
      _selectedStoreName = '${matchedStore?['store_name'] ?? 'Toko'}';
      _rows = const [];
    });

    try {
      final rows = await _loadRecommendationRows(storeId);
      if (!mounted) return;
      setState(() {
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

  void _changeQty(int index, int delta) {
    final rows = List<Map<String, dynamic>>.from(_rows);
    final current = _toInt(rows[index]['selected_qty']);
    rows[index] = {
      ...rows[index],
      'selected_qty': (current + delta).clamp(0, 9999),
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
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      entry.value.sort(
        (a, b) => '${a['color'] ?? ''}'.compareTo('${b['color'] ?? ''}'),
      );
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
        final result = await ImageGallerySaverPlus.saveImage(
          bytes,
          quality: 100,
          name: fileName,
        );
        if (!mounted) return;
        final success = result['isSuccess'] == true;
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

  String _warehouseStockLabel(int warehouseStock) {
    if (warehouseStock <= 0) return 'Kosong';
    return 'Ready';
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

  List<Map<String, dynamic>> get _exportItems {
    final rows = List<Map<String, dynamic>>.from(_serverPreviewItems);
    rows.sort((a, b) {
      final productCompare = '${a['product_name'] ?? ''}'.compareTo(
        '${b['product_name'] ?? ''}',
      );
      if (productCompare != 0) return productCompare;
      final networkCompare = '${a['network_type'] ?? ''}'.compareTo(
        '${b['network_type'] ?? ''}',
      );
      if (networkCompare != 0) return networkCompare;
      final variantCompare = '${a['variant'] ?? ''}'.compareTo(
        '${b['variant'] ?? ''}',
      );
      if (variantCompare != 0) return variantCompare;
      return '${a['color'] ?? ''}'.compareTo('${b['color'] ?? ''}');
    });
    return rows;
  }

  Widget _buildRecommendationExportWidget() {
    final dateText = DateFormat('dd MMMM yyyy', 'id_ID').format(DateTime.now());
    final items = _exportItems;
    final yearText = DateTime.now().year.toString();
    return Container(
      width: _exportCanvasWidth,
      color: const Color(0xFFFAF8F3),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAF8F3),
              border: Border.all(color: const Color(0xFFD8D2C4)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(26, 20, 26, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _exportDocumentTitle,
                    style: GoogleFonts.spaceMono(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF9A9080),
                      letterSpacing: 1.8,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _selectedStoreName,
                    softWrap: true,
                    style: GoogleFonts.playfairDisplay(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF1C1A16),
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Text(
                          '$dateText\n$_currentUserName',
                          textAlign: TextAlign.left,
                          style: GoogleFonts.outfit(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: const Color(0xFF7A7060),
                            height: 1.6,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        color: const Color(0xFF1C1A16),
                        child: Text(
                  'SELL IN',
                          style: GoogleFonts.spaceMono(
                            fontSize: 7.5,
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFFFAF8F3),
                            letterSpacing: 1,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          Container(height: 2, color: const Color(0xFF1C1A16)),
          Container(height: 1, color: const Color(0xFF1C1A16)),
          _buildTransferAccountCard(),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAF8F3),
              border: Border.all(color: const Color(0xFFD8D2C4)),
            ),
            child: Column(
              children: [
                _buildExportTableHeader(),
                ...items.asMap().entries.map(
                  (entry) => _buildExportTableRow(entry.key + 1, entry.value),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
            decoration: const BoxDecoration(
              color: Color(0xFFFAF8F3),
              border: Border(
                left: BorderSide(color: Color(0xFFD8D2C4)),
                right: BorderSide(color: Color(0xFFD8D2C4)),
                bottom: BorderSide(color: Color(0xFFD8D2C4)),
                top: BorderSide(color: Color(0xFF1C1A16), width: 2),
              ),
            ),
            child: Column(
              children: [
                _buildExportTotalLine('Total Qty', '$_selectedTotalQty unit'),
                _buildExportTotalLine(
                  'Total Nominal',
                  _currency.format(_selectedTotalValue),
                  emphasize: true,
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F3EB),
              border: Border(
                top: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
                left: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
                right: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
                bottom: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
              ),
            ),
            child: Row(
              children: [
                Text(
                  '${_selectedStoreName.toUpperCase()} © $yearText',
                  style: GoogleFonts.spaceMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF8E836F),
                    letterSpacing: 0.9,
                  ),
                ),
                const Spacer(),
                Text(
                  'VIVO INDONESIA',
                  style: GoogleFonts.spaceMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF8E836F),
                    letterSpacing: 0.9,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferAccountCard() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0ECE3),
        border: Border.all(color: const Color(0xFFD8D2C4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'REKENING TUJUAN TRANSFER',
                  style: GoogleFonts.spaceMono(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF9A9080),
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Bank BNI',
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1A16),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'PT. Long Yin Teknologi Informasi',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    color: const Color(0xFF5A5040),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'NO. REKENING',
                style: GoogleFonts.spaceMono(
                  fontSize: 7.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9A9080),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '804 879 804',
                style: GoogleFonts.spaceMono(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1C1A16),
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildExportTableHeader() {
    return Container(
      color: const Color(0xFFF0ECE3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          _exportHeaderCell('Item', flex: 9, align: TextAlign.left),
          _exportHeaderCell('Qty', flex: 2, align: TextAlign.center),
          _exportHeaderCell('Modal', flex: 4, align: TextAlign.right),
          _exportHeaderCell('SRP', flex: 4, align: TextAlign.right),
          _exportHeaderCell('Subtotal', flex: 4, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _buildExportTableRow(int index, Map<String, dynamic> row) {
    final qty = _displayQty(row);
    final price = _toNum(row['price']);
    final modal = _toNum(row['modal']);
    final specs = [
      '${row['network_type'] ?? ''}'.trim(),
      '${row['variant'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).join(' • ');
    final color = '${row['color'] ?? ''}'.trim();
    final productTitle = color.isEmpty
        ? '${row['product_name'] ?? 'Produk'}'
        : '${row['product_name'] ?? 'Produk'} ($color)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: index.isEven ? const Color(0xFFF5F1EA) : const Color(0xFFFAF8F3),
        border: const Border(
          top: BorderSide(color: Color(0xFFDDD8CE), width: 0.5),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 9,
            child: Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    productTitle,
                    softWrap: true,
                    style: GoogleFonts.outfit(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF1C1A16),
                      height: 1.2,
                    ),
                  ),
                  if (specs.isNotEmpty) ...[
                    const SizedBox(height: 1),
                    Text(
                      specs,
                      softWrap: true,
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF6E6253),
                        height: 1.1,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _exportValueCell(
            '$qty',
            flex: 2,
            align: TextAlign.center,
            weight: FontWeight.w700,
            fontFamily: GoogleFonts.spaceMono().fontFamily,
            fontSize: 14.5,
          ),
          _exportValueCell(
            modal > 0 ? _amount.format(modal) : '-',
            flex: 4,
            align: TextAlign.right,
            scaleDown: true,
            fontSize: 14.5,
            color: const Color(0xFF7A7060),
          ),
          _exportValueCell(
            _amount.format(price),
            flex: 4,
            align: TextAlign.right,
            scaleDown: true,
            fontSize: 14.5,
            color: const Color(0xFF1C1A16),
          ),
          _exportValueCell(
            _amount.format(_toNum(row['subtotal']) > 0 ? _toNum(row['subtotal']) : modal * qty),
            flex: 4,
            align: TextAlign.right,
            scaleDown: true,
            weight: FontWeight.w600,
            fontSize: 14.5,
            color: const Color(0xFF1C1A16),
          ),
        ],
      ),
    );
  }

  Widget _exportHeaderCell(
    String text, {
    required int flex,
    TextAlign align = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Text(
          text,
          textAlign: align,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceMono(
            fontSize: 8.5,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF9A9080),
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  Widget _exportValueCell(
    String text, {
    required int flex,
    TextAlign align = TextAlign.left,
    FontWeight weight = FontWeight.w600,
    bool scaleDown = false,
    double fontSize = 10,
    String? fontFamily,
    Color? color,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: scaleDown
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: align == TextAlign.right
                    ? Alignment.centerRight
                    : align == TextAlign.center
                    ? Alignment.center
                    : Alignment.centerLeft,
                child: Text(
                  text,
                  textAlign: align,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: fontSize,
                    fontWeight: weight,
                    fontFamily: fontFamily,
                    color: color ?? const Color(0xFF2A2620),
                    height: 1.2,
                  ),
                ),
              )
            : Text(
                text,
                textAlign: align,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: weight,
                  fontFamily: fontFamily,
                  color: color ?? const Color(0xFF2A2620),
                  height: 1.2,
                ),
              ),
      ),
    );
  }

  Widget _buildExportTotalLine(
    String label,
    String value, {
    bool emphasize = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: emphasize ? Colors.transparent : const Color(0xFFDDD8CE),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            label.toUpperCase(),
            style: GoogleFonts.spaceMono(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF9A9080),
              letterSpacing: 0.8,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: emphasize
                ? GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1A16),
                    height: 1.05,
                  )
                : GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1A16),
                  ),
          ),
        ],
      ),
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
                  if (!_isGroupMode) _buildStoreSelector(),
                  if (!_isGroupMode) const SizedBox(height: 12),
                  _buildControls(),
                  const SizedBox(height: 12),
                  if (_groupedModelRows.isEmpty)
                    _buildEmptyState()
                  else ...[
                    ..._groupedModelRows.map(
                      (group) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildModelGroup(group.key, group.value),
                      ),
                    ),
                  ],
                ],
              ),
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: BoxDecoration(
            color: t.surface1,
            border: Border(top: BorderSide(color: t.surface3)),
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
                        fontSize: 13,
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
    );
  }

  Widget _buildStoreSelector() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: DropdownButtonFormField<String>(
          key: ValueKey(_selectedStoreId),
          initialValue: _selectedStoreId,
          isExpanded: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: _stores
              .map(
                (store) => DropdownMenuItem<String>(
                  value: store['store_id']?.toString(),
                  child: Text(
                    [
                      '${store['store_name'] ?? 'Toko'}',
                      if ('${store['group_name'] ?? ''}'.trim().isNotEmpty)
                        '${store['group_name']}',
                    ].join(' • '),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: _onStoreChanged,
        ),
      ),
    );
  }

  Widget _buildControls() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              onChanged: (value) =>
                  setState(() => _searchQuery = value.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Cari produk, varian, atau warna',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
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
            if (!_isRecommendation) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Catatan order (opsional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
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
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: selected ? t.primaryAccent : t.textMutedStrong,
          ),
        ),
      ),
      selected: selected,
      onSelected: (_) => setState(() => _seriesFilter = value),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      visualDensity: const VisualDensity(horizontal: -3, vertical: -4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      labelPadding: EdgeInsets.zero,
      side: BorderSide(color: selected ? t.primaryAccent : t.surface3),
      backgroundColor: t.background,
      selectedColor: t.primaryAccentSoft,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }

  Widget _buildModelGroup(String key, List<Map<String, dynamic>> rows) {
    final first = rows.first;
    final title =
        '${first['product_name'] ?? 'Produk'} ${first['variant'] ?? '-'}';
    final selectedQty = rows.fold<int>(
      0,
      (sum, row) => sum + _toInt(row['selected_qty']),
    );

    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey(key),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
          minTileHeight: 52,
          initiallyExpanded: _expandedModelKeys.contains(key),
          onExpansionChanged: (expanded) {
            setState(() {
              if (expanded) {
                _expandedModelKeys.add(key);
              } else {
                _expandedModelKeys.remove(key);
              }
            });
          },
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          subtitle: Text(
            '${rows.length} warna${selectedQty > 0 ? ' • dipilih $selectedQty' : ''}',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: t.textMutedStrong,
            ),
          ),
          children: rows
              .map(
                (row) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildProductCard(row),
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  Widget _buildProductCard(Map<String, dynamic> row) {
    final qty = _toInt(row['selected_qty']);
    final orderQty = _toInt(row['order_qty']);
    final currentStock = _toInt(row['current_stock']);
    final minStock = _toInt(row['min_stock']);
    final shortageQty = _toInt(row['shortage_qty']);
    final warehouseStock = _toInt(row['warehouse_stock']);
    final unfulfilledQty = _toInt(row['unfulfilled_qty']);
    final status = '${row['status'] ?? 'CUKUP'}';
    final statusColor = _statusColor(status);
    final storeStockLabel = _storeStockLabel(currentStock, minStock);
    final warehouseTone = _warehouseStockColor(warehouseStock);
    final warehouseLabel = _warehouseStockLabel(warehouseStock);
    final recommendationStatus = '${row['recommendation_status'] ?? ''}';
    final recommendationColor = _recommendationColor(recommendationStatus);
    final previewItem =
        _serverPreviewItemByVariantId['${row['variant_id'] ?? ''}'];
    final previewQty = _displayQty(Map<String, dynamic>.from(previewItem ?? const {}));
    final lineSubtotal = _toNum(previewItem?['subtotal']);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(10),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: statusColor.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.storefront_outlined, size: 16, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Stok toko $storeStockLabel',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                          ),
                        ),
                      ),
                      Text(
                        '$currentStock',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: warehouseTone.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: warehouseTone.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warehouse_outlined, size: 16, color: warehouseTone),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Gudang $warehouseLabel',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: warehouseTone,
                          ),
                        ),
                      ),
                      Text(
                        '$warehouseStock',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: warehouseTone,
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _metricChip('Stok', '$currentStock')),
              const SizedBox(width: 6),
              Expanded(child: _metricChip('Min', '$minStock')),
              const SizedBox(width: 6),
              Expanded(child: _metricChip('Butuh', '$shortageQty')),
              const SizedBox(width: 6),
              Expanded(child: _metricChip('Gudang', '$warehouseStock')),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(child: _metricChip('Saran', '$orderQty')),
              const SizedBox(width: 6),
              Expanded(
                flex: 2,
                child: _metricChip(
                  'Harga',
                  _currency.format(_toNum(row['price'])),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _qtyButton(
                Icons.remove,
                () => _changeQty(_rows.indexOf(row), -1),
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
              _qtyButton(Icons.add, () => _changeQty(_rows.indexOf(row), 1)),
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

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: t.surface3),
        ),
        child: Icon(icon, size: 16, color: t.textPrimary),
      ),
    );
  }

  Widget _metricChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: t.textMutedStrong,
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
