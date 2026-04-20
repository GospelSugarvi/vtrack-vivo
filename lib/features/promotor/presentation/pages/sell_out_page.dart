import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'barcode_scanner_page.dart';
import '../../../../core/utils/success_dialog.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../core/utils/promotor_home_refresh_bus.dart';
import '../../../../ui/foundation/app_text_style.dart';
import '../../../../ui/promotor/promotor.dart';

class SellOutPage extends StatefulWidget {
  const SellOutPage({super.key});

  @override
  State<SellOutPage> createState() => _SellOutPageState();
}

class _SellOutPageState extends State<SellOutPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _imeiController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _priceController = TextEditingController();
  final _notesController = TextEditingController();

  bool _isValidating = false;
  bool _isSubmittingSale = false;
  Map<String, dynamic>? _stockInfo;
  String? _errorMessage;
  XFile? _selectedImage;

  // Form State
  String? _customerType; // vip_call, toko
  String? _paymentMethod; // cash, kredit
  String? _leasingProvider;

  String _customerTypeLabel(String value) {
    switch (value) {
      case 'vip_call':
        return 'VIP Call';
      case 'toko':
      default:
        return 'Toko';
    }
  }

  String _paymentMethodLabel(String value) {
    switch (value) {
      case 'cash':
        return 'Cash';
      case 'kredit':
        return 'Kredit';
      default:
        return value;
    }
  }

  String _buildProductName(Map<String, dynamic> product) {
    final model = '${product['model_name'] ?? product['name'] ?? ''}'.trim();
    final networkType = '${product['network_type'] ?? ''}'.trim().toUpperCase();
    if (model.isEmpty) return 'Unknown Product';
    if (networkType == '5G' && !model.toUpperCase().contains('5G')) {
      return '$model 5G';
    }
    return model;
  }

  Future<bool> _hasCompletedValidationToday(String userId) async {
    final assignmentRows = await Supabase.instance.client
        .from('assignments_promotor_store')
        .select('store_id')
        .eq('promotor_id', userId)
        .eq('active', true)
        .order('created_at', ascending: false)
        .limit(1);

    final assignments = List<Map<String, dynamic>>.from(assignmentRows);
    final assignment = assignments.isNotEmpty ? assignments.first : null;
    final storeId = assignment?['store_id'];
    if (storeId == null) return false;

    final today = DateTime.now();
    final startOfDay = DateTime(
      today.year,
      today.month,
      today.day,
    ).toIso8601String();
    final endOfDay = DateTime(
      today.year,
      today.month,
      today.day,
      23,
      59,
      59,
    ).toIso8601String();

    final validationRows = await Supabase.instance.client
        .from('stock_validations')
        .select('id')
        .eq('promotor_id', userId)
        .eq('store_id', storeId)
        .eq('status', 'completed')
        .gte('validation_date', startOfDay)
        .lte('validation_date', endOfDay)
        .order('created_at', ascending: false)
        .limit(1);

    final validations = List<Map<String, dynamic>>.from(validationRows);
    return validations.isNotEmpty;
  }

  Future<bool> _confirmSellWithoutValidation() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: t.background,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Text(
          'Belum validasi stok',
          style: PromotorText.display(size: 18, color: t.textPrimary),
        ),
        content: Text(
          'Tetap kirim penjualan ini?',
          style: PromotorText.outfit(
            size: 14,
            weight: FontWeight.w700,
            color: t.textMuted,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('Batal', style: TextStyle(color: t.textMuted)),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: t.primaryAccent,
              foregroundColor: t.textOnAccent,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kirim'),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  @override
  void dispose() {
    _imeiController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _priceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  String _formatSoldAt(dynamic soldAt) {
    if (soldAt == null) return 'sebelumnya';

    try {
      final parsed = soldAt is DateTime
          ? soldAt
          : DateTime.parse(soldAt.toString());
      final local = parsed.toLocal();
      return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(local);
    } catch (_) {
      return soldAt.toString();
    }
  }

  InputDecoration _fieldDecoration({String? hintText, Widget? prefixIcon}) {
    return InputDecoration(
      isDense: true,
      hintText: hintText,
      hintStyle: PromotorText.outfit(
        size: 13,
        weight: FontWeight.w700,
        color: t.textMutedStrong,
      ),
      filled: true,
      fillColor: t.surface1,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: t.surface3),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: t.surface3),
      ),
      prefixIcon: prefixIcon,
    );
  }

  Widget _buildFieldLabel(String text, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 2),
      child: RichText(
        text: TextSpan(
          style: PromotorText.outfit(
            size: 12,
            weight: FontWeight.w700,
            color: t.textSecondary,
          ),
          children: [
            TextSpan(text: text),
            if (required)
              TextSpan(
                text: ' *',
                style: PromotorText.outfit(
                  size: 12,
                  weight: FontWeight.w700,
                  color: t.primaryAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: source,
        maxWidth: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        setState(() {
          _selectedImage = image;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final exception = ErrorHandler.handleError(e);
      ErrorHandler.showErrorSnackBar(
        context,
        'Gagal mengambil foto: ${exception.message}',
      );
    }
  }

  Future<void> _showImageSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      backgroundColor: t.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Icon(
                    Icons.photo_camera_outlined,
                    color: t.primaryAccent,
                  ),
                  title: Text(
                    'Ambil foto',
                    style: PromotorText.outfit(
                      size: 14,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(ImageSource.camera),
                ),
                const SizedBox(height: 8),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  leading: Icon(
                    Icons.photo_library_outlined,
                    color: t.primaryAccent,
                  ),
                  title: Text(
                    'Ambil dari galeri',
                    style: PromotorText.outfit(
                      size: 14,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  onTap: () =>
                      Navigator.of(sheetContext).pop(ImageSource.gallery),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (source == null) return;
    await _pickImage(source);
  }

  Future<void> _showCustomerTypeSheet(
    StateSetter setModalState,
    BuildContext modalContext,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: modalContext,
      backgroundColor: t.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget buildOption(String value, IconData icon, String label) {
          final selected = _customerType == value;
          return ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Icon(
              icon,
              color: selected ? t.primaryAccent : t.textMutedStrong,
            ),
            title: Text(
              label,
              style: PromotorText.outfit(
                size: 14,
                weight: FontWeight.w700,
                color: selected ? t.primaryAccent : t.textPrimary,
              ),
            ),
            trailing: selected
                ? Icon(Icons.check_circle, color: t.primaryAccent)
                : null,
            onTap: () => Navigator.of(sheetContext).pop(value),
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pilih Tipe Konsumen',
                  style: PromotorText.display(size: 18, color: t.textPrimary),
                ),
                const SizedBox(height: 12),
                buildOption('toko', Icons.storefront_rounded, 'Toko'),
                const SizedBox(height: 8),
                buildOption(
                  'vip_call',
                  Icons.workspace_premium_rounded,
                  'VIP Call',
                ),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected == _customerType) return;
    setModalState(() => _customerType = selected);
  }

  Future<void> _showPaymentMethodSheet(
    StateSetter setModalState,
    BuildContext modalContext,
  ) async {
    final selected = await showModalBottomSheet<String>(
      context: modalContext,
      backgroundColor: t.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget buildOption(String value, IconData icon, String label) {
          final selected = _paymentMethod == value;
          return ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Icon(
              icon,
              color: selected ? t.primaryAccent : t.textMutedStrong,
            ),
            title: Text(
              label,
              style: PromotorText.outfit(
                size: 14,
                weight: FontWeight.w700,
                color: selected ? t.primaryAccent : t.textPrimary,
              ),
            ),
            trailing: selected
                ? Icon(Icons.check_circle, color: t.primaryAccent)
                : null,
            onTap: () => Navigator.of(sheetContext).pop(value),
          );
        }

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Pilih Metode Pembayaran',
                  style: PromotorText.display(size: 18, color: t.textPrimary),
                ),
                const SizedBox(height: 12),
                buildOption('cash', Icons.payments_rounded, 'Cash'),
                const SizedBox(height: 8),
                buildOption('kredit', Icons.credit_card_rounded, 'Kredit'),
              ],
            ),
          ),
        );
      },
    );

    if (selected == null || selected == _paymentMethod) return;
    setModalState(() {
      _paymentMethod = selected;
      if (selected == 'cash') {
        _leasingProvider = null;
      }
    });
  }

  Future<void> _showLeasingSheet(
    StateSetter setModalState,
    BuildContext modalContext,
  ) async {
    const leasingOptions = [
      'VAST',
      'KREDIVO',
      'KREDIT PLUS',
      'INDODANA',
      'HCI',
      'FIF',
      'Lainnya',
    ];

    final selected = await showModalBottomSheet<String>(
      context: modalContext,
      backgroundColor: t.background,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        Widget buildOption(String value) {
          final selected = _leasingProvider == value;
          return ListTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            leading: Icon(
              Icons.account_balance_rounded,
              color: selected ? t.primaryAccent : t.textMutedStrong,
            ),
            title: Text(
              value,
              style: PromotorText.outfit(
                size: 14,
                weight: FontWeight.w700,
                color: selected ? t.primaryAccent : t.textPrimary,
              ),
            ),
            trailing: selected
                ? Icon(Icons.check_circle, color: t.primaryAccent)
                : null,
            onTap: () => Navigator.of(sheetContext).pop(value),
          );
        }

        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.72,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Pilih Leasing',
                    style: PromotorText.display(size: 18, color: t.textPrimary),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: leasingOptions.length,
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        return buildOption(leasingOptions[index]);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (selected == null || selected == _leasingProvider) return;
    setModalState(() => _leasingProvider = selected);
  }

  Future<String?> _uploadToCloudinary(XFile imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();

      // Compress image (skip on web)
      List<int> compressedBytes = bytes;
      if (!kIsWeb) {
        img.Image? image = img.decodeImage(bytes);
        if (image != null) {
          if (image.width > 1200) {
            image = img.copyResize(image, width: 1200);
          }
          final recompressed = img.encodeJpg(image, quality: 85);
          if (recompressed.length < bytes.length) {
            compressedBytes = recompressed;
          } else {
            compressedBytes = bytes;
          }
        }
      }

      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/dkkbwu8hj/image/upload',
      );
      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = 'vtrack_uploads'
        ..fields['folder'] = 'vtrack/sales'
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            compressedBytes,
            filename: 'sale_${DateTime.now().millisecondsSinceEpoch}.jpg',
          ),
        );

      final response = await request.send().timeout(
        const Duration(seconds: 60),
        onTimeout: () => throw TimeoutException(message: 'Upload timeout'),
      );

      if (response.statusCode == 200) {
        final responseData = await response.stream.toBytes();
        final result = json.decode(String.fromCharCodes(responseData));
        final url = result['secure_url'];
        return url;
      } else {
        throw Exception('Upload failed with status ${response.statusCode}');
      }
    } on SocketException catch (e) {
      throw NetworkException(originalError: e);
    } on TimeoutException catch (e) {
      throw TimeoutException(
        message: 'Upload foto terlalu lama. Coba lagi.',
        originalError: e,
      );
    } catch (e, stackTrace) {
      debugPrint('=== ERROR uploading to Cloudinary ===');
      debugPrint('Error: $e');
      debugPrint('Stack trace: $stackTrace');
      throw AppException('Gagal upload foto: $e', originalError: e);
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
        _validateIMEI();
      }
    } catch (e) {
      if (!mounted) return;
      final exception = ErrorHandler.handleError(e);
      ErrorHandler.showErrorDialog(context, exception);
    }
  }

  Future<void> _validateIMEI() async {
    final imei = _imeiController.text.trim();

    // Validation
    if (imei.isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Masukkan nomor IMEI');
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

    setState(() {
      _isValidating = true;
      _errorMessage = null;
      _stockInfo = null;
    });

    try {
      // Check if IMEI exists in stok table with timeout
      final result = await Supabase.instance.client
          .from('stok')
          .select('id,imei,is_sold,sold_at,variant_id,tipe_stok')
          .eq('imei', imei)
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(
            const Duration(seconds: 10),
            onTimeout: () => throw TimeoutException(
              message: 'Waktu pencarian IMEI habis. Periksa koneksi internet.',
            ),
          );
      final resultRows = List<Map<String, dynamic>>.from(result);
      final stockRow = resultRows.isNotEmpty ? resultRows.first : null;

      if (stockRow == null) {
        setState(() {
          _errorMessage =
              'IMEI tidak ditemukan di stok. Pastikan IMEI sudah terdaftar.';
          _isValidating = false;
        });
        return;
      }

      if (stockRow['is_sold'] == true) {
        setState(() {
          _errorMessage =
              'IMEI sudah terjual pada ${_formatSoldAt(stockRow['sold_at'])}';
          _isValidating = false;
        });
        return;
      }

      // Load variant + product with explicit queries
      final variantId = stockRow['variant_id'];
      Map<String, dynamic> variant = {};
      if (variantId != null) {
        final variantRow = await Supabase.instance.client
            .from('product_variants')
            .select('id,product_id,srp,ram_rom,color')
            .eq('id', variantId)
            .maybeSingle();
        if (variantRow != null) {
          variant = Map<String, dynamic>.from(variantRow);
          final productId = variant['product_id'];
          if (productId != null) {
            final productRow = await Supabase.instance.client
                .from('products')
                .select('id,model_name,network_type')
                .eq('id', productId)
                .maybeSingle();
            if (productRow != null) {
              variant['products'] = productRow;
            }
          }
        }
      }

      // Set default price from SRP
      if (variant['srp'] != null) {
        _priceController.text = variant['srp'].toString();
      }

      setState(() {
        _stockInfo = {...stockRow, 'product_variants': variant};
        _isValidating = false;
      });

      _showSalesForm();
    } on SocketException {
      setState(() {
        _errorMessage = 'Koneksi internet terputus. Periksa koneksi Anda.';
        _isValidating = false;
      });
    } on TimeoutException catch (e) {
      setState(() {
        _errorMessage = e.message;
        _isValidating = false;
      });
    } on PostgrestException catch (e) {
      final exception = ErrorHandler.handleError(e);
      setState(() {
        _errorMessage = exception.message;
        _isValidating = false;
      });
    } catch (e) {
      final exception = ErrorHandler.handleError(e);
      setState(() {
        _errorMessage = exception.message;
        _isValidating = false;
      });
    }
  }

  void _showSalesForm() {
    _isSubmittingSale = false;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: t.surface1.withValues(alpha: 0),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.86,
        minChildSize: 0.5,
        maxChildSize: 0.92,
        expand: false,
        builder: (context, scrollController) => StatefulBuilder(
          builder: (context, setModalState) {
            final variant = _stockInfo!['product_variants'] ?? {};
            final product = variant['products'] ?? {};
            final productName = _buildProductName(
              Map<String, dynamic>.from(product as Map? ?? const {}),
            );
            final isChipStock = '${_stockInfo!['tipe_stok'] ?? ''}' == 'chip';
            final bottomInset = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: t.background,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: t.surface3,
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.shopping_cart_checkout,
                            color: t.primaryAccent,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Konfirmasi Penjualan',
                            style: PromotorText.display(
                              size: 14,
                              color: t.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            icon: Icon(Icons.close, color: t.textSecondary),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints.tightFor(
                              width: 28,
                              height: 28,
                            ),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: t.surface3),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              productName,
                              style: PromotorText.outfit(
                                size: 14,
                                weight: FontWeight.w700,
                                color: t.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              [
                                if ('${variant['ram_rom'] ?? ''}'.trim().isNotEmpty)
                                  '${variant['ram_rom']}',
                                if ('${variant['color'] ?? ''}'.trim().isNotEmpty)
                                  '${variant['color']}',
                                'IMEI ${_stockInfo!['imei']}',
                              ].join(' • '),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.mono(
                                t.textSecondary,
                                size: 11,
                                weight: FontWeight.w700,
                              ),
                            ),
                            if (isChipStock) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: t.warningSoft,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  'Barang CHIP: transaksi tetap disimpan, bonus normal tidak dihitung',
                                  softWrap: true,
                                  style: PromotorText.outfit(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: t.warning,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Data Customer',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Tipe Konsumen',
                        style: PromotorText.outfit(
                          size: 12,
                          weight: FontWeight.w700,
                          color: t.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () =>
                            _showCustomerTypeSheet(setModalState, context),
                        borderRadius: BorderRadius.circular(16),
                        child: InputDecorator(
                          decoration:
                              _fieldDecoration(
                                prefixIcon: Icon(
                                  Icons.groups_rounded,
                                  color: t.textMuted,
                                ),
                              ).copyWith(
                                hintText: 'Tap untuk memilih',
                                suffixIcon: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: t.textMutedStrong,
                                ),
                              ),
                          child: Text(
                            _customerType == null
                                ? 'Tap untuk memilih'
                                : _customerTypeLabel(_customerType!),
                            style: PromotorText.outfit(
                              size: 13,
                              weight: FontWeight.w700,
                              color: _customerType == null
                                  ? t.textMutedStrong
                                  : t.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFieldLabel('Nama Pelanggan', required: true),
                      const SizedBox(height: 6),

                      TextField(
                        controller: _customerNameController,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                        decoration: _fieldDecoration(
                          hintText: 'Masukkan nama pelanggan',
                          prefixIcon: Icon(Icons.person, color: t.textMuted),
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildFieldLabel('No WA'),
                      const SizedBox(height: 6),

                      TextField(
                        controller: _customerPhoneController,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                        decoration:
                            _fieldDecoration(
                              hintText: '81234567890',
                              prefixIcon: Icon(Icons.phone, color: t.textMuted),
                            ).copyWith(
                              prefixStyle: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w600,
                                color: t.textSecondary,
                              ),
                              prefixText: '+62 ',
                            ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                      ),

                      const SizedBox(height: 10),
                      Text(
                        'Data Transaksi',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 6),
                      _buildFieldLabel('Harga SRP', required: true),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _priceController,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                        decoration: _fieldDecoration(
                          hintText: 'Masukkan harga jual',
                          prefixIcon: Icon(
                            Icons.monetization_on,
                            color: t.textMuted,
                          ),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 10),
                      _buildFieldLabel('Metode Pembayaran'),
                      const SizedBox(height: 6),
                      InkWell(
                        onTap: () =>
                            _showPaymentMethodSheet(setModalState, context),
                        borderRadius: BorderRadius.circular(16),
                        child: InputDecorator(
                          decoration: _fieldDecoration().copyWith(
                            hintText: 'Tap untuk memilih',
                            suffixIcon: Icon(
                              Icons.keyboard_arrow_down_rounded,
                              color: t.textMutedStrong,
                            ),
                          ),
                          child: Text(
                            _paymentMethod == null
                                ? 'Tap untuk memilih'
                                : _paymentMethodLabel(_paymentMethod!),
                            style: PromotorText.outfit(
                              size: 13,
                              weight: FontWeight.w700,
                              color: _paymentMethod == null
                                  ? t.textMutedStrong
                                  : t.textPrimary,
                            ),
                          ),
                        ),
                      ),
                      if (_paymentMethod == 'kredit') ...[
                        const SizedBox(height: 8),
                        _buildFieldLabel('Leasing', required: true),
                        const SizedBox(height: 6),
                        InkWell(
                          onTap: () => _showLeasingSheet(setModalState, context),
                          borderRadius: BorderRadius.circular(16),
                          child: InputDecorator(
                            decoration: _fieldDecoration().copyWith(
                              hintText: 'Tap untuk memilih',
                              suffixIcon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: t.textMutedStrong,
                              ),
                            ),
                            child: Text(
                              _leasingProvider ?? 'Tap untuk memilih',
                              style: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w700,
                                color: _leasingProvider == null
                                    ? t.textMutedStrong
                                    : t.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 10),
                      Text(
                        'Foto & Catatan',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 6),

                      InkWell(
                        onTap: () async {
                          await _showImageSourceSheet();
                          setModalState(() {});
                        },
                        child: Container(
                          height: 110,
                          decoration: BoxDecoration(
                            border: Border.all(color: t.surface3),
                            borderRadius: BorderRadius.circular(16),
                            color: t.surface1,
                          ),
                          child: _selectedImage == null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.add_a_photo,
                                      size: 38,
                                      color: t.textMuted,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Ambil foto atau pilih dari galeri',
                                      style: PromotorText.outfit(
                                        size: 12,
                                        weight: FontWeight.w600,
                                        color: t.textSecondary,
                                      ),
                                    ),
                                  ],
                                )
                              : Stack(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(16),
                                      child: kIsWeb
                                          ? Image.network(
                                              _selectedImage!.path,
                                              width: double.infinity,
                                              height: 110,
                                              fit: BoxFit.cover,
                                            )
                                          : FutureBuilder<Uint8List>(
                                              future: _selectedImage!
                                                  .readAsBytes(),
                                              builder: (context, snapshot) {
                                                if (snapshot.hasData) {
                                                  return Image.memory(
                                                    snapshot.data!,
                                                    width: double.infinity,
                                                    height: 110,
                                                    fit: BoxFit.cover,
                                                  );
                                                }
                                                return const Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                );
                                              },
                                            ),
                                    ),
                                    Positioned(
                                      top: 8,
                                      right: 8,
                                      child: IconButton(
                                        icon: Icon(
                                          Icons.close,
                                          color: t.textOnAccent,
                                        ),
                                        style: IconButton.styleFrom(
                                          backgroundColor: t.background
                                              .withValues(alpha: 0.54),
                                        ),
                                        onPressed: () => setModalState(
                                          () => _selectedImage = null,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildFieldLabel('Catatan'),
                      const SizedBox(height: 6),

                      TextField(
                        controller: _notesController,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                        decoration: _fieldDecoration(
                          prefixIcon: Icon(Icons.note, color: t.textMuted),
                        ),
                        maxLines: 3,
                      ),

                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _isSubmittingSale
                              ? null
                              : () => _processSale(context, setModalState),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: t.primaryAccent,
                            foregroundColor: t.textOnAccent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                          child: _isSubmittingSale
                              ? FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Sedang mengirim',
                                    style: PromotorText.outfit(
                                      size: 15,
                                      weight: FontWeight.w700,
                                      color: t.textOnAccent,
                                    ),
                                  ),
                                )
                              : FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'Kirim',
                                    style: PromotorText.outfit(
                                      size: 15,
                                      weight: FontWeight.w700,
                                      color: t.textOnAccent,
                                    ),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _processSale(
    BuildContext modalContext,
    void Function(void Function()) setModalState,
  ) async {
    if (_isSubmittingSale) return;

    // Basic Validation
    if (_customerNameController.text.trim().isEmpty) {
      ErrorHandler.showErrorSnackBar(
        modalContext,
        'Nama pelanggan wajib diisi',
      );
      return;
    }

    if (_customerNameController.text.trim().length < 3) {
      ErrorHandler.showErrorSnackBar(
        modalContext,
        'Nama pelanggan minimal 3 karakter',
      );
      return;
    }

    if (_customerType == null) {
      ErrorHandler.showErrorSnackBar(modalContext, 'Pilih tipe konsumen');
      return;
    }

    if (_priceController.text.isEmpty) {
      ErrorHandler.showErrorSnackBar(modalContext, 'Harga wajib diisi');
      return;
    }

    final price =
        int.tryParse(_priceController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
        0;
    if (price <= 0) {
      ErrorHandler.showErrorSnackBar(modalContext, 'Harga harus lebih dari 0');
      return;
    }

    if (_paymentMethod == null) {
      ErrorHandler.showErrorSnackBar(
        modalContext,
        'Pilih metode pembayaran',
      );
      return;
    }

    if (_paymentMethod == 'kredit' && _leasingProvider == null) {
      ErrorHandler.showErrorSnackBar(modalContext, 'Pilih leasing');
      return;
    }

    setModalState(() => _isSubmittingSale = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        throw SessionExpiredException();
      }

      final hasValidationToday = await _hasCompletedValidationToday(userId);
      if (!hasValidationToday) {
        final proceed = await _confirmSellWithoutValidation();
        if (!proceed) {
          setModalState(() => _isSubmittingSale = false);
          return;
        }
      }

      final stokId = _stockInfo!['id'];
      final imei = _stockInfo!['imei'];
      final selectedImage = _selectedImage;

      final cleanedPhone = _normalizePhone(_customerPhoneController.text);
      final customerPhone = cleanedPhone.isEmpty ? null : '+62$cleanedPhone';

      // Atomic sell-out transaction on server
      final rpcResult = await Supabase.instance.client
          .rpc(
            'process_sell_out_atomic',
            params: {
              'p_promotor_id': userId,
              'p_stok_id': stokId,
              'p_serial_imei': imei,
              'p_price_at_transaction': price,
              'p_payment_method': _paymentMethod!,
              'p_leasing_provider': _paymentMethod == 'kredit'
                  ? _leasingProvider
                  : null,
              'p_customer_name': _customerNameController.text.trim(),
              'p_customer_phone': customerPhone,
              'p_customer_type': _customerType!,
              // Save sale first, upload photo asynchronously after sale is committed.
              'p_image_proof_url': null,
              'p_notes': _notesController.text.trim().isNotEmpty
                  ? _notesController.text.trim()
                  : null,
            },
          )
          .timeout(const Duration(seconds: 20));

      String? saleId;
      if (rpcResult is Map<String, dynamic>) {
        saleId = rpcResult['sale_id']?.toString();
      } else if (rpcResult is Map) {
        saleId = rpcResult['sale_id']?.toString();
      }

      if (selectedImage != null && saleId != null && saleId.isNotEmpty) {
        unawaited(
          _uploadProofInBackground(saleId: saleId, imageFile: selectedImage),
        );
      }

      if (!mounted) return;
      if (modalContext.mounted) {
        Navigator.pop(modalContext);
      }
      await showSuccessDialog(
        context,
        title: 'Penjualan Berhasil!',
        message: 'Data penjualan telah disimpan ke sistem 💰',
      );
      notifyPromotorHomeRefresh();
      _resetForm();
      if (!mounted) return;
      context.go('/promotor?tab=workplace');
    } catch (e) {
      debugPrint('Error saving sale: $e');

      final exception = ErrorHandler.handleError(e);

      if (mounted) {
        ErrorHandler.showErrorDialog(
          context,
          exception,
          onRetry: () => _processSale(modalContext, setModalState),
        );
      }
      setModalState(() => _isSubmittingSale = false);
    } finally {
      // Keep loading state local in modal submit to avoid unnecessary page rebuilds.
    }
  }

  Future<void> _uploadProofInBackground({
    required String saleId,
    required XFile imageFile,
  }) async {
    Object? lastError;
    StackTrace? lastStackTrace;

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final imageUrl = await _uploadToCloudinary(imageFile);
        if (imageUrl == null || imageUrl.isEmpty) return;

        await Supabase.instance.client.rpc(
          'attach_sell_out_proof',
          params: {'p_sale_id': saleId, 'p_image_proof_url': imageUrl},
        );
        return;
      } catch (e, stackTrace) {
        lastError = e;
        lastStackTrace = stackTrace;
        if (attempt < 3) {
          await Future<void>.delayed(Duration(seconds: attempt * 2));
          continue;
        }
      }
    }

    if (lastError != null && lastStackTrace != null) {
      // Do not break main flow if proof upload fails after successful sale save.
      ErrorHandler.handleError(
        lastError,
        context: 'Background upload proof',
        stackTrace: lastStackTrace,
      );
    }
  }

  String _normalizePhone(String raw) {
    var digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    if (digits.startsWith('62')) {
      digits = digits.substring(2);
    }
    return digits;
  }

  void _resetForm() {
    _imeiController.clear();
    _customerNameController.clear();
    _customerPhoneController.clear();
    _priceController.clear();
    _notesController.clear();
    _customerType = null;
    _paymentMethod = null;
    _leasingProvider = null;
    _selectedImage = null;
    setState(() {
      _stockInfo = null;
      _isValidating = false;
    });
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
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, 'Input Penjualan'),
                const SizedBox(height: 10),

                TextField(
                  controller: _imeiController,
                  autofocus: true,
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                  decoration: InputDecoration(
                    isDense: true,
                    labelText: 'Nomor IMEI',
                    filled: true,
                    fillColor: t.surface1,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: t.surface3),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: t.surface3),
                    ),
                    prefixIcon: Icon(Icons.smartphone, color: t.textMuted),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.qr_code_scanner, color: t.primaryAccent),
                      onPressed: _scanBarcode,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                  maxLength: 15,
                  onSubmitted: (_) => _validateIMEI(),
                ),
                const SizedBox(height: 10),

                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.danger.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: t.danger.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline, color: t.danger),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(color: t.danger),
                          ),
                        ),
                      ],
                    ),
                  ),

                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _isValidating ? null : _validateIMEI,
                        icon: _isValidating
                            ? SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: t.textOnAccent,
                                ),
                              )
                            : Icon(Icons.search, size: 18),
                        label: Text(_isValidating ? 'Mengecek...' : 'Cek IMEI'),
                        style: FilledButton.styleFrom(
                          backgroundColor: t.primaryAccent,
                          foregroundColor: t.textOnAccent,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(vertical: 11),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: _isValidating ? null : _scanBarcode,
                      icon: Icon(Icons.qr_code_scanner, size: 18),
                      label: const Text('Scan'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                      ),
                    ),
                  ],
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
    return Row(
      children: [
        InkWell(
          onTap: () => Navigator.of(context).maybePop(),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: t.surface3),
            ),
            child: Icon(
              Icons.arrow_back_ios_new_rounded,
              color: t.textSecondary,
              size: 16,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: PromotorText.display(size: 16, color: t.textPrimary),
        ),
      ],
    );
  }
}
