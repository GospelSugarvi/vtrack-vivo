import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'barcode_scanner_page.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../ui/foundation/app_type_scale.dart';
import '../../../../ui/foundation/app_text_style.dart';
import '../../../../ui/promotor/promotor.dart';

Map<String, dynamic> _extractProductData(Map<String, dynamic> variant) {
  final rawProduct = variant['products'];
  if (rawProduct is Map<String, dynamic>) {
    return rawProduct;
  }
  if (rawProduct is Map) {
    return rawProduct.map((key, value) => MapEntry(key.toString(), value));
  }
  return {};
}

String _stringValue(dynamic value) {
  if (value == null) return '';
  return value.toString().trim();
}

String _buildVariantLabel(
  Map<String, dynamic> variant, {
  bool includeModel = true,
}) {
  final product = _extractProductData(variant);
  final model = _buildProductName(product);
  final ramRom = _stringValue(variant['ram_rom']);
  final color = _stringValue(variant['color']);

  final details = <String>[
    if (ramRom.isNotEmpty) ramRom,
    if (color.isNotEmpty) color,
  ].join(' • ');

  if (includeModel) {
    if (model.isEmpty && details.isEmpty) return 'Varian tanpa nama';
    if (model.isEmpty) return details;
    if (details.isEmpty) return model;
    return '$model - $details';
  }

  if (details.isNotEmpty) return details;
  if (model.isNotEmpty) return model;
  return 'Detail varian belum diisi';
}

String _buildProductName(Map<String, dynamic> product) {
  final model = _stringValue(product['model_name']);
  final networkType = _stringValue(product['network_type']).toUpperCase();
  if (model.isEmpty) return '';
  if (networkType == '5G' && !model.toUpperCase().contains('5G')) {
    return '$model 5G';
  }
  return model;
}

int _variantPrice(Map<String, dynamic> variant) {
  final raw = variant['srp'];
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return int.tryParse('${raw ?? ''}') ?? 0;
}

class StockInputPage extends StatefulWidget {
  const StockInputPage({super.key});

  @override
  State<StockInputPage> createState() => _StockInputPageState();
}

class _StockInputPageState extends State<StockInputPage> {
  static List<Map<String, dynamic>> _variantCache = <Map<String, dynamic>>[];

  FieldThemeTokens get t => context.fieldTokens;
  final _imeiController = TextEditingController();
  bool _isCheckingImei = false;
  bool _isSubmittingStock = false;
  String _selectedTipeStok = 'fresh'; // fresh, chip, display
  final List<Map<String, dynamic>> _addedItems = [];
  List<Map<String, dynamic>> _variants = [];
  String? _selectedVariantId;
  bool _isLoadingVariants = false;

  Future<Map<String, String>> _loadPendingClaimContext(String stokId) async {
    try {
      final row = await Supabase.instance.client
          .from('stock_movement_log')
          .select('from_store_id, moved_by')
          .eq('stok_id', stokId)
          .order('moved_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final fromStoreId = '${row?['from_store_id'] ?? ''}';
      final movedBy = '${row?['moved_by'] ?? ''}';

      String storeName = '-';
      String promotorName = '-';

      if (fromStoreId.isNotEmpty && fromStoreId != 'null') {
        final storeRow = await Supabase.instance.client
            .from('stores')
            .select('store_name')
            .eq('id', fromStoreId)
            .maybeSingle();
        storeName = '${storeRow?['store_name'] ?? '-'}';
      }

      if (movedBy.isNotEmpty && movedBy != 'null') {
        final userRow = await Supabase.instance.client
            .from('users')
            .select('full_name')
            .eq('id', movedBy)
            .maybeSingle();
        promotorName = '${userRow?['full_name'] ?? '-'}';
      }

      return {'store_name': storeName, 'promotor_name': promotorName};
    } catch (e) {
      return {'store_name': '-', 'promotor_name': '-'};
    }
  }

  Map<String, dynamic>? _findVariantById(String? variantId) {
    if (variantId == null) return null;
    for (final variant in _variants) {
      if (_stringValue(variant['id']) == variantId) {
        return variant;
      }
    }
    return null;
  }

  Future<void> _openVariantPicker() async {
    if (_variants.isEmpty) return;

    final selectedVariantId = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) => _VariantPickerSheet(
        variants: _variants,
        selectedVariantId: _selectedVariantId,
      ),
    );

    if (!mounted || selectedVariantId == null) return;
    setState(() => _selectedVariantId = selectedVariantId);
  }

  String _selectedVariantText() {
    final selected = _findVariantById(_selectedVariantId);
    if (selected == null) return 'Tap untuk pilih varian';
    return _buildVariantLabel(selected);
  }

  @override
  void initState() {
    super.initState();
    if (_variantCache.isNotEmpty) {
      _variants = List<Map<String, dynamic>>.from(_variantCache);
    }
    unawaited(_loadVariants(forceRefresh: _variantCache.isNotEmpty));
  }

  Future<void> _loadVariants({bool forceRefresh = false}) async {
    if (!forceRefresh && _variantCache.isNotEmpty) {
      if (!mounted) return;
      setState(() {
        _variants = List<Map<String, dynamic>>.from(_variantCache);
        _isLoadingVariants = false;
      });
      return;
    }
    setState(() => _isLoadingVariants = true);

    try {
      final result = await Supabase.instance.client
          .from('product_variants')
          .select(
            'id, srp, ram_rom, color, products(id, model_name, network_type)',
          )
          .isFilter('deleted_at', null)
          .order('products(model_name)')
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(message: 'Waktu memuat data produk habis');
            },
          );

      setState(() {
        _variants = List<Map<String, dynamic>>.from(result);
        _variantCache = List<Map<String, dynamic>>.from(result);
        _isLoadingVariants = false;
      });
    } on SocketException catch (e) {
      setState(() => _isLoadingVariants = false);
      if (mounted) {
        ErrorHandler.showErrorDialog(
          context,
          NetworkException(originalError: e),
        );
      }
    } on TimeoutException catch (e) {
      setState(() => _isLoadingVariants = false);
      if (mounted) {
        ErrorHandler.showErrorDialog(
          context,
          e as AppException,
          onRetry: _loadVariants,
        );
      }
    } catch (e) {
      setState(() => _isLoadingVariants = false);
      debugPrint('Error loading variants: $e');
      if (mounted) {
        final exception = ErrorHandler.handleError(e);
        ErrorHandler.showErrorDialog(context, exception);
      }
    }
  }

  Future<void> _scanBarcode() async {
    try {
      final result = await Navigator.push<String>(
        context,
        MaterialPageRoute(builder: (context) => const BarcodeScannerPage()),
      );

      if (result != null && mounted) {
        setState(() {
          _imeiController.text = result;
        });
        _addIMEI();
      }
    } catch (e) {
      if (!mounted) return;
      final exception = ErrorHandler.handleError(e);
      ErrorHandler.showErrorDialog(context, exception);
    }
  }

  Future<void> _addIMEI() async {
    final imei = _imeiController.text.trim();

    // Validation
    if (imei.isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Masukkan IMEI');
      return;
    }

    if (imei.length != 15) {
      ErrorHandler.showErrorSnackBar(context, 'IMEI harus 15 digit');
      return;
    }

    if (!RegExp(r'^[0-9]+$').hasMatch(imei)) {
      ErrorHandler.showErrorSnackBar(context, 'IMEI hanya boleh berisi angka');
      return;
    }

    // Check if already added locally
    if (_addedItems.any((item) => item['imei'] == imei)) {
      ErrorHandler.showErrorSnackBar(context, 'IMEI sudah ditambahkan');
      return;
    }

    setState(() => _isCheckingImei = true);

    try {
      // Check if IMEI already exists in database
      final existing = await Supabase.instance.client
          .from('stok')
          .select(
            'id, imei, is_sold, store_id, variant_id, relocation_status, tipe_stok',
          )
          .eq('imei', imei)
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () {
              throw TimeoutException(message: 'Waktu pengecekan IMEI habis');
            },
          );
      final existingRows = List<Map<String, dynamic>>.from(existing);
      final existingStock = existingRows.isNotEmpty ? existingRows.first : null;

      if (existingStock != null) {
        final isPendingClaim =
            existingStock['is_sold'] != true &&
            existingStock['store_id'] == null &&
            _stringValue(existingStock['relocation_status']) == 'pending_claim';
        if (isPendingClaim) {
          final pendingClaimContext = await _loadPendingClaimContext(
            '${existingStock['id']}',
          );
          final claimed = await _claimRelocatedStock(
            imei: imei,
            sourceStoreName: pendingClaimContext['store_name'] ?? '-',
            sourcePromotorName: pendingClaimContext['promotor_name'] ?? '-',
          );
          if (!mounted) return;
          if (claimed) {
            _imeiController.clear();
          }
          setState(() => _isCheckingImei = false);
          return;
        }

        if (!mounted) return;
        ErrorHandler.showErrorSnackBar(
          context,
          'IMEI sudah ada di database (${existingStock['is_sold'] == true ? 'Terjual' : 'Tersedia'})',
        );
        setState(() => _isCheckingImei = false);
        return;
      }

      // Get selected variant info
      String variantLabel = 'Pilih varian';
      final selectedVariant = _findVariantById(_selectedVariantId);
      if (selectedVariant != null) {
        variantLabel = _buildVariantLabel(selectedVariant);
      }

      setState(() {
        _addedItems.add({
          'imei': imei,
          'variant_id': _selectedVariantId,
          'variant_label': variantLabel,
          'tipe_stok': _selectedTipeStok,
        });
      });

      _imeiController.clear();
    } on SocketException catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorDialog(context, NetworkException(originalError: e));
    } on TimeoutException catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorDialog(
        context,
        e as AppException,
        onRetry: () => _addIMEI(),
      );
    } catch (e) {
      if (!mounted) return;
      final exception = ErrorHandler.handleError(e);
      ErrorHandler.showErrorDialog(context, exception);
    } finally {
      setState(() => _isCheckingImei = false);
    }
  }

  Future<bool> _claimRelocatedStock({
    required String imei,
    required String sourceStoreName,
    required String sourcePromotorName,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Barang Pindahan Terdeteksi'),
        content: SingleChildScrollView(
          child: Text(
            'IMEI ini sudah ada di sistem dan sedang menunggu claim toko penerima.\n\nToko asal: $sourceStoreName\nPromotor asal: $sourcePromotorName\n\nSistem tidak akan membuat stok baru. IMEI lama akan dipindahkan ke toko Anda.\n\nLanjut claim sekarang?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Claim'),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;

    await Supabase.instance.client.rpc(
      'claim_relocated_stock',
      params: {'p_imei': imei, 'p_note': 'Claimed from stock input page'},
    );

    if (!mounted) return false;
    ErrorHandler.showSuccessSnackBar(
      context,
      'IMEI pindahan berhasil di-claim ke toko Anda',
    );
    return true;
  }

  Future<void> _submitStock() async {
    if (_addedItems.isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Tambahkan minimal 1 IMEI');
      return;
    }

    // Check all items have variant selected
    final noVariant = _addedItems.any((item) => item['variant_id'] == null);
    if (noVariant) {
      ErrorHandler.showErrorSnackBar(context, 'Pilih varian untuk semua IMEI');
      return;
    }

    setState(() => _isSubmittingStock = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw SessionExpiredException();
      }
      final rpcResult = await Supabase.instance.client
          .rpc(
            'submit_promotor_stock_input',
            params: {
              'p_items': _addedItems
                  .map(
                    (item) => <String, dynamic>{
                      'imei': item['imei'],
                      'variant_id': item['variant_id'],
                      'tipe_stok': item['tipe_stok'],
                    },
                  )
                  .toList(),
            },
          )
          .timeout(
            const Duration(seconds: 20),
            onTimeout: () {
              throw TimeoutException(message: 'Waktu kirim stok habis');
            },
          );

      final payload = rpcResult is Map<String, dynamic>
          ? rpcResult
          : Map<String, dynamic>.from(rpcResult as Map);
      final successCount = (payload['success_count'] as num?)?.toInt() ?? 0;
      final duplicateImeis = List<String>.from(
        payload['duplicate_imeis'] as List? ?? const [],
      );
      final failedImeis = List<String>.from(
        payload['failed_imeis'] as List? ?? const [],
      );

      if (!mounted) return;
      String message = '';

      if (successCount > 0) {
        message = '$successCount IMEI berhasil ditambahkan!';
      }
      if (duplicateImeis.isNotEmpty) {
        message += '\n${duplicateImeis.length} IMEI sudah ada di database';
      }
      if (failedImeis.isNotEmpty) {
        message += '\n${failedImeis.length} IMEI gagal disimpan';
      }

      if (successCount == _addedItems.length) {
        ErrorHandler.showSuccessSnackBar(context, message);
      } else if (successCount > 0) {
        ErrorHandler.showErrorSnackBar(context, message);
      } else {
        ErrorHandler.showErrorDialog(
          context,
          AppException('Gagal menyimpan semua IMEI'),
        );
      }

      // Clear successfully added items
      setState(() {
        _addedItems.removeWhere(
          (item) =>
              !duplicateImeis.contains(item['imei']) &&
              !failedImeis.contains(item['imei']),
        );
      });
    } on SocketException catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorDialog(context, NetworkException(originalError: e));
    } on TimeoutException catch (e) {
      if (!mounted) return;
      ErrorHandler.showErrorDialog(
        context,
        e as AppException,
        onRetry: _submitStock,
      );
    } catch (e) {
      if (!mounted) return;
      final exception = ErrorHandler.handleError(e);
      ErrorHandler.showErrorDialog(context, exception);
    } finally {
      setState(() => _isSubmittingStock = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: Container(
        color: t.background,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, 'Input Stok'),
                const SizedBox(height: 20),
                // Variant selector
                if (_isLoadingVariants)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: t.surface3),
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: t.primaryAccent,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'Memuat produk...',
                          style: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: t.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  InkWell(
                    onTap: _openVariantPicker,
                    borderRadius: BorderRadius.circular(18),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Pilih Produk & Varian',
                        labelStyle: PromotorText.outfit(
                          size: 15,
                          weight: FontWeight.w600,
                          color: t.textMuted,
                        ),
                        floatingLabelStyle: PromotorText.outfit(
                          size: 15,
                          weight: FontWeight.w700,
                          color: t.primaryAccent,
                        ),
                        filled: true,
                        fillColor: t.surface1,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: t.surface3),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide(color: t.surface3),
                        ),
                        prefixIcon: Icon(
                          Icons.phone_android,
                          color: t.textMuted,
                        ),
                        suffixIcon: Icon(
                          Icons.arrow_drop_down,
                          color: t.textMuted,
                        ),
                      ),
                      child: Text(
                        _selectedVariantText(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w600,
                          color: _selectedVariantId == null
                              ? t.textMuted
                              : t.textPrimary,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 12),

                // Tipe Stok selector
                SegmentedButton<String>(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return t.primaryAccent;
                      }
                      return t.surface1;
                    }),
                    foregroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.selected)) {
                        return t.textOnAccent;
                      }
                      return t.textSecondary;
                    }),
                    side: WidgetStatePropertyAll(BorderSide(color: t.surface3)),
                    textStyle: WidgetStatePropertyAll(
                      PromotorText.outfit(size: 15, weight: FontWeight.w700),
                    ),
                    padding: const WidgetStatePropertyAll(
                      EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    ),
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 'fresh',
                      label: Text('Fresh'),
                      icon: Icon(Icons.new_releases, size: 16),
                    ),
                    ButtonSegment(
                      value: 'chip',
                      label: Text('Chip'),
                      icon: Icon(Icons.memory, size: 16),
                    ),
                    ButtonSegment(
                      value: 'display',
                      label: Text('Display'),
                      icon: Icon(Icons.phone_android, size: 16),
                    ),
                  ],
                  selected: {_selectedTipeStok},
                  onSelectionChanged: (Set<String> selection) {
                    setState(() => _selectedTipeStok = selection.first);
                  },
                ),
                const SizedBox(height: 16),

                // IMEI Input
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _imeiController,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Scan/Input IMEI (15 digit)',
                          labelStyle: PromotorText.outfit(
                            size: 15,
                            weight: FontWeight.w600,
                            color: t.textMuted,
                          ),
                          floatingLabelStyle: PromotorText.outfit(
                            size: 15,
                            weight: FontWeight.w700,
                            color: t.primaryAccent,
                          ),
                          counterStyle: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: t.textMuted,
                          ),
                          filled: true,
                          fillColor: t.surface1,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: t.surface3),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: t.surface3),
                          ),
                          prefixIcon: Icon(Icons.qr_code, color: t.textMuted),
                          suffixIcon: IconButton(
                            icon: Icon(
                              Icons.qr_code_scanner,
                              color: t.primaryAccent,
                            ),
                            onPressed: _scanBarcode,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                        maxLength: 15,
                        onSubmitted: (_) => _addIMEI(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      onPressed: _isCheckingImei ? null : _addIMEI,
                      style: IconButton.styleFrom(
                        backgroundColor: t.primaryAccent,
                        foregroundColor: t.textOnAccent,
                      ),
                      icon: _isCheckingImei
                          ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: t.textOnAccent,
                              ),
                            )
                          : Icon(Icons.add),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Added items list
                Expanded(
                  child: _addedItems.isEmpty
                      ? LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: Center(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.inventory_2_outlined,
                                            size: 48,
                                            color: t.textMuted,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Belum ada IMEI ditambahkan',
                                            style: PromotorText.outfit(
                                              size: 15,
                                              weight: FontWeight.w700,
                                              color: t.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                        )
                      : ListView.builder(
                          itemCount: _addedItems.length,
                          itemBuilder: (context, index) {
                            final item = _addedItems[index];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 10),
                              color: t.surface1,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                                side: BorderSide(color: t.surface3),
                              ),
                              child: ListTile(
                                leading: Icon(
                                  item['tipe_stok'] == 'fresh'
                                      ? Icons.new_releases
                                      : item['tipe_stok'] == 'chip'
                                      ? Icons.memory
                                      : Icons.phone_android,
                                  color: item['tipe_stok'] == 'fresh'
                                      ? t.success
                                      : item['tipe_stok'] == 'chip'
                                      ? t.warning
                                      : t.info,
                                ),
                                title: Text(
                                  item['imei'],
                                  style: AppTextStyle.mono(
                                    t.textPrimary,
                                    size: AppTypeScale.body,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete_outline,
                                    color: t.danger,
                                  ),
                                  onPressed: () {
                                    setState(() => _addedItems.removeAt(index));
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Submit button
                if (_addedItems.isNotEmpty)
                  ElevatedButton.icon(
                    onPressed: _isSubmittingStock ? null : _submitStock,
                    icon: _isSubmittingStock
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.textOnAccent,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      _isSubmittingStock
                          ? 'Sedang mengirim'
                          : 'Kirim',
                    ),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: t.primaryAccent,
                      foregroundColor: t.textOnAccent,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    final t = context.fieldTokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 12),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.surface3),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: t.textSecondary,
                size: 17,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            title,
            style: PromotorText.display(size: 18, color: t.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _VariantPickerSheet extends StatefulWidget {
  const _VariantPickerSheet({
    required this.variants,
    required this.selectedVariantId,
  });

  final List<Map<String, dynamic>> variants;
  final String? selectedVariantId;

  @override
  State<_VariantPickerSheet> createState() => _VariantPickerSheetState();
}

class _VariantPickerSheetState extends State<_VariantPickerSheet> {
  FieldThemeTokens get t => context.fieldTokens;
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedModels = {};
  String _query = '';

  @override
  void initState() {
    super.initState();
    final selected = widget.variants.cast<Map<String, dynamic>?>().firstWhere(
      (variant) => _stringValue(variant?['id']) == widget.selectedVariantId,
      orElse: () => null,
    );
    if (selected != null) {
      final model = _stringValue(_extractProductData(selected)['model_name']);
      if (model.isNotEmpty) {
        _expandedModels.add(model);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<_VariantGroup> _buildGroups() {
    final keyword = _query.trim().toLowerCase();
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final variant in widget.variants) {
      final fullLabel = _buildVariantLabel(variant).toLowerCase();
      if (keyword.isNotEmpty && !fullLabel.contains(keyword)) continue;

      final modelRaw = _stringValue(_extractProductData(variant)['model_name']);
      final modelName = modelRaw.isEmpty ? 'Tanpa Model' : modelRaw;
      grouped.putIfAbsent(modelName, () => <Map<String, dynamic>>[]).add(variant);
    }

      final groups = grouped.entries.map((entry) {
      final variants = List<Map<String, dynamic>>.from(entry.value)
        ..sort(
          (a, b) {
            final priceCompare = _variantPrice(a).compareTo(_variantPrice(b));
            if (priceCompare != 0) return priceCompare;
            return _buildVariantLabel(a, includeModel: false)
                .toLowerCase()
                .compareTo(
                  _buildVariantLabel(b, includeModel: false).toLowerCase(),
                );
          },
        );
      return _VariantGroup(model: entry.key, variants: variants);
    }).toList()
      ..sort((a, b) {
        final aPrice = a.variants.isEmpty ? 0 : _variantPrice(a.variants.first);
        final bPrice = b.variants.isEmpty ? 0 : _variantPrice(b.variants.first);
        final priceCompare = aPrice.compareTo(bPrice);
        if (priceCompare != 0) return priceCompare;
        return a.model.toLowerCase().compareTo(b.model.toLowerCase());
      });

    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final groups = _buildGroups();

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Container(
        decoration: BoxDecoration(
          color: t.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Stack(
                alignment: Alignment.topCenter,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: t.surface3,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  Align(
                    alignment: Alignment.topRight,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: t.surface3),
                        ),
                        child: Icon(
                          Icons.close_rounded,
                          size: 16,
                          color: t.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pilih Produk',
                      style: PromotorText.display(
                        size: 16,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    '${widget.variants.length} varian',
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: t.textPrimary,
                ),
                decoration: InputDecoration(
                  hintText: 'Cari model / RAM / warna',
                  hintStyle: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                  counterStyle: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                  prefixIcon: Icon(Icons.search, color: t.textMuted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          icon: Icon(Icons.close, color: t.textMuted),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                        ),
                  filled: true,
                  fillColor: t.surface1,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: t.surface3),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: t.surface3),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide(color: t.primaryAccent),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: groups.isEmpty
                  ? Center(
                      child: Text(
                        'Varian tidak ditemukan',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.textMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                      itemCount: groups.length,
                      itemBuilder: (context, index) {
                        final group = groups[index];
                        final shouldExpand =
                            _query.isNotEmpty || _expandedModels.contains(group.model);

                        return Card(
                          color: t.surface1,
                          margin: const EdgeInsets.only(bottom: 6),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: t.surface3),
                          ),
                          child: ExpansionTile(
                            key: PageStorageKey<String>('group_${group.model}_$index'),
                            tilePadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 0,
                            ),
                            childrenPadding: const EdgeInsets.only(bottom: 4),
                            dense: true,
                            minTileHeight: 44,
                            iconColor: t.primaryAccent,
                            collapsedIconColor: t.textMuted,
                            initiallyExpanded: shouldExpand,
                            onExpansionChanged: (isExpanded) {
                              setState(() {
                                if (isExpanded) {
                                  _expandedModels.add(group.model);
                                } else {
                                  _expandedModels.remove(group.model);
                                }
                              });
                            },
                            title: Text(
                              group.model,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w700,
                                color: t.textPrimary,
                              ),
                            ),
                            children: group.variants.map((variant) {
                              final variantId = _stringValue(variant['id']);
                              final isSelected =
                                  variantId == widget.selectedVariantId;

                              return ListTile(
                                dense: true,
                                visualDensity: const VisualDensity(
                                  horizontal: -2,
                                  vertical: -3,
                                ),
                                minTileHeight: 38,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                ),
                                leading: Icon(
                                  isSelected
                                      ? Icons.radio_button_checked
                                      : Icons.radio_button_off,
                                  size: 18,
                                  color: isSelected
                                      ? t.primaryAccent
                                      : t.textMuted,
                                ),
                                title: Text(
                                  _buildVariantLabel(
                                    variant,
                                    includeModel: false,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: PromotorText.outfit(
                                    size: 12,
                                    weight: FontWeight.w600,
                                    color: t.textPrimary,
                                  ),
                                ),
                                onTap: () => Navigator.pop(context, variantId),
                              );
                            }).toList(),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VariantGroup {
  const _VariantGroup({required this.model, required this.variants});

  final String model;
  final List<Map<String, dynamic>> variants;
}
