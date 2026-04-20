import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/core/utils/success_dialog.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../services/stok_gudang_ai_service.dart';

enum _StockInputMode { gemini, manualJson }

class _CatalogCandidate {
  const _CatalogCandidate({required this.item, required this.score});

  final Map<String, dynamic> item;
  final int score;
}

class ScanStokGudangPage extends StatefulWidget {
  final Map<String, dynamic>? params;

  const ScanStokGudangPage({super.key, this.params});

  @override
  State<ScanStokGudangPage> createState() => _ScanStokGudangPageState();
}

class _ScanStokGudangPageState extends State<ScanStokGudangPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _aiService = StokGudangAIService();
  final _supabase = Supabase.instance.client;
  final _imagePicker = ImagePicker();
  final _manualJsonController = TextEditingController();

  bool _isLoadingCatalog = true;
  bool _isProcessing = false;
  bool _isSaving = false;
  _StockInputMode _inputMode = _StockInputMode.gemini;
  Uint8List? _selectedImageBytes;
  String _selectedMimeType = 'image/jpeg';
  String? _selectedImageName;
  List<Map<String, dynamic>> _catalog = const [];
  List<Map<String, dynamic>> _parsedItems = const [];
  List<Map<String, dynamic>> _unmatchedItems = const [];

  DateTime get _selectedDate {
    final date = widget.params?['selectedDate'];
    if (date is DateTime) return date;
    return DateTime.now();
  }

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  @override
  void dispose() {
    _manualJsonController.dispose();
    super.dispose();
  }

  Future<void> _loadCatalog() async {
    if (!mounted) return;
    setState(() => _isLoadingCatalog = true);

    try {
      final snapshotRaw = await _supabase.rpc(
        'get_active_product_variant_catalog',
      );
      final snapshot = Map<String, dynamic>.from(
        (snapshotRaw as Map?) ?? const <String, dynamic>{},
      );
      final catalog = _parseMapList(snapshot['items']);

      if (!mounted) return;
      setState(() {
        _catalog = catalog;
        _isLoadingCatalog = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingCatalog = false);
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa memuat katalog varian aktif: $e',
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

  Future<void> _pickImage(ImageSource source) async {
    try {
      final file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 85,
      );
      if (file == null) return;

      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImageBytes = bytes;
        _selectedImageName = file.name;
        _selectedMimeType = _guessMimeType(file.name);
        _parsedItems = const [];
        _unmatchedItems = const [];
      });
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa mengambil gambar: $e',
      );
    }
  }

  Future<void> _parseImage() async {
    if (_selectedImageBytes == null) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Pilih gambar stok gudang terlebih dahulu.',
      );
      return;
    }
    if (_catalog.isEmpty) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Katalog produk aktif belum tersedia.',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _parsedItems = const [];
      _unmatchedItems = const [];
    });

    try {
      final aiItems = await _aiService.parseStockImage(
        _selectedImageBytes!.toList(),
        _selectedMimeType,
        catalog: _catalog
            .map(
              (row) => {
                'variant_id': row['variant_id'],
                'product_name': row['product_name'],
                'network_type': row['network_type'],
                'variant': row['variant'],
                'color': row['color'],
              },
            )
            .toList(),
      );

      final catalogByVariantId = {
        for (final item in _catalog) '${item['variant_id']}': item,
      };

      final grouped = <String, Map<String, dynamic>>{};
      final unmatched = <Map<String, dynamic>>[];

      for (final item in aiItems) {
        final variantId = '${item['variant_id'] ?? ''}';
        final catalogItem = catalogByVariantId[variantId];
        if (catalogItem == null) {
          unmatched.add(item);
          continue;
        }

        final existing = grouped[variantId];
        final qty = _toInt(item['qty']);
        grouped[variantId] = {
          ...catalogItem,
          'qty': qty + (existing == null ? 0 : _toInt(existing['qty'])),
          'confidence': _toDouble(item['confidence']),
        };
      }

      final parsed = grouped.values.toList()
        ..sort((a, b) {
          final qtyCompare = _toInt(b['qty']).compareTo(_toInt(a['qty']));
          if (qtyCompare != 0) return qtyCompare;
          return '${a['product_name']}'.compareTo('${b['product_name']}');
        });

      if (!mounted) return;
      setState(() {
        _parsedItems = parsed;
        _unmatchedItems = unmatched;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Gemini tidak bisa mem-parsing gambar: $e',
      );
    }
  }

  Future<void> _processManualJson() async {
    final raw = _manualJsonController.text.trim();
    if (raw.isEmpty) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Paste JSON hasil parsing terlebih dahulu.',
      );
      return;
    }
    if (_catalog.isEmpty) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Katalog produk aktif belum tersedia.',
      );
      return;
    }

    if (!mounted) return;
    setState(() {
      _isProcessing = true;
      _parsedItems = const [];
      _unmatchedItems = const [];
    });

    try {
      final decoded = jsonDecode(raw);
      final items = decoded is Map<String, dynamic>
          ? decoded['items']
          : (decoded is List ? decoded : null);
      if (items is! List) {
        throw FormatException(
          'Format JSON harus berupa array atau object dengan key "items".',
        );
      }

      final catalogByVariantId = {
        for (final item in _catalog) '${item['variant_id']}': item,
      };
      final grouped = <String, Map<String, dynamic>>{};
      final unmatched = <Map<String, dynamic>>[];

      for (final dynamic rawItem in items) {
        if (rawItem is! Map) continue;
        final item = Map<String, dynamic>.from(rawItem);
        final matchedCatalog = _resolveCatalogItem(item, catalogByVariantId);
        final qty = _extractQty(item);
        final otw = _extractOtw(item);

        if (matchedCatalog == null) {
          final diagnostics = _buildMatchDiagnostics(item);
          unmatched.add({
            'variant_id': '${item['variant_id'] ?? ''}',
            'product_name': _extractProductName(item),
            'network_type': _extractNetworkType(item),
            'variant': _extractVariant(item),
            'color': _extractColor(item),
            'qty': qty,
            'otw': otw,
            'reason': diagnostics['reason'],
            'suggestion': diagnostics['suggestion'],
          });
          continue;
        }

        final variantId = '${matchedCatalog['variant_id']}';
        final existing = grouped[variantId];
        grouped[variantId] = {
          ...matchedCatalog,
          'qty': qty + (existing == null ? 0 : _toInt(existing['qty'])),
          'otw': otw + (existing == null ? 0 : _toInt(existing['otw'])),
          'confidence': 1.0,
        };
      }

      final parsed = grouped.values.toList()
        ..sort((a, b) {
          final qtyCompare = _toInt(b['qty']).compareTo(_toInt(a['qty']));
          if (qtyCompare != 0) return qtyCompare;
          return '${a['product_name']}'.compareTo('${b['product_name']}');
        });

      if (!mounted) return;
      setState(() {
        _parsedItems = parsed;
        _unmatchedItems = unmatched;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isProcessing = false);
      await showErrorDialog(context, title: 'JSON Tidak Valid', message: '$e');
    }
  }

  Map<String, dynamic>? _resolveCatalogItem(
    Map<String, dynamic> item,
    Map<String, Map<String, dynamic>> catalogByVariantId,
  ) {
    final variantId = _readString(item, const ['variant_id']);
    if (variantId.isNotEmpty) {
      return catalogByVariantId[variantId];
    }

    final targetProduct = _normalizeText(_extractProductName(item));
    final candidates = _scoredCatalogCandidates(item);
    if (targetProduct.isEmpty || candidates.isEmpty) {
      return null;
    }

    final best = candidates.first;
    if (!_candidatePassesThreshold(best, item)) {
      return null;
    }

    if (candidates.length == 1) {
      return best.item;
    }

    final runnerUp = candidates[1];
    if (best.score == runnerUp.score) return null;
    if ((best.score - runnerUp.score) < 2) return null;
    return best.item;
  }

  String _extractProductName(Map<String, dynamic> item) {
    final direct = _readString(item, const [
      'product_name',
      'model_name',
      'model',
      'nama_produk',
    ]);
    if (direct.isNotEmpty) return direct;
    return _parseLegacyProductLabel(
          _readString(item, const ['produk']),
        )['product_name'] ??
        '';
  }

  String _extractVariant(Map<String, dynamic> item) {
    final direct = _readString(item, const [
      'variant',
      'ram_rom',
      'memory',
      'memori',
    ]);
    if (direct.isNotEmpty) {
      return direct.replaceAll('+', '/').replaceAll(RegExp(r'[gG]\b'), '');
    }
    return _parseLegacyProductLabel(
          _readString(item, const ['produk']),
        )['variant'] ??
        '';
  }

  String _extractColor(Map<String, dynamic> item) {
    final direct = _readString(item, const ['color', 'warna']);
    if (direct.isNotEmpty) return direct;
    return _parseLegacyProductLabel(
          _readString(item, const ['produk']),
        )['color'] ??
        '';
  }

  String _extractNetworkType(Map<String, dynamic> item) {
    final direct = _readString(item, const [
      'network_type',
      'network',
      'jaringan',
    ]);
    if (direct.isNotEmpty) return direct;
    return _parseLegacyProductLabel(
          _readString(item, const ['produk']),
        )['network_type'] ??
        '';
  }

  Map<String, String> _parseLegacyProductLabel(String rawLabel) {
    final raw = rawLabel.trim();
    if (raw.isEmpty) return const <String, String>{};

    final result = <String, String>{};
    final colorMatch = RegExp(r'\(([^)]+)\)\s*$').firstMatch(raw);
    if (colorMatch != null) {
      result['color'] = colorMatch.group(1)?.trim() ?? '';
    }

    final upper = raw.toUpperCase();
    if (upper.contains('5G')) {
      result['network_type'] = '5G';
    } else if (upper.contains('4G')) {
      result['network_type'] = '4G';
    } else {
      // Untuk format gudang yang tidak menulis network,
      // absence of "5G" berarti default ke varian 4G.
      result['network_type'] = '4G';
    }

    final variantMatch = RegExp(
      r'(\d+\s*[\+/]\s*\d+)\s*[gG]?',
      caseSensitive: false,
    ).firstMatch(raw);
    if (variantMatch != null) {
      result['variant'] = (variantMatch.group(1) ?? '')
          .replaceAll(RegExp(r'\s+'), '')
          .replaceAll('+', '/');
    }

    var productName = raw
        .replaceAll(RegExp(r'\(([^)]+)\)\s*$'), '')
        .replaceAll(RegExp(r'\bTRAINING\s*PHONE\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\bDM\b', caseSensitive: false), '')
        .replaceAll(RegExp(r'\b[45]G\b', caseSensitive: false), '')
        .replaceAll(
          RegExp(r'(\d+\s*[\+/]\s*\d+)\s*[gG]?', caseSensitive: false),
          '',
        )
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (productName.isNotEmpty) {
      result['product_name'] = productName;
    }

    return result;
  }

  int _extractQty(Map<String, dynamic> item) {
    return _toInt(
      item['qty'] ??
          item['stok'] ??
          item['stok_gudang'] ??
          item['stock'] ??
          item['quantity'] ??
          item['jumlah'],
    );
  }

  int _extractOtw(Map<String, dynamic> item) {
    return _toInt(
      item['on_the_way'] ??
          item['of_the_way'] ??
          item['otw'] ??
          item['incoming'],
    );
  }

  String _readString(Map<String, dynamic> item, List<String> keys) {
    for (final key in keys) {
      final value = item[key];
      final text = '${value ?? ''}'.trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  String _normalizeText(dynamic value) {
    return '${value ?? ''}'
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  String _compactText(dynamic value) {
    return _normalizeText(value).replaceAll(' ', '');
  }

  String _normalizeVariant(dynamic value) {
    return '${value ?? ''}'
        .toLowerCase()
        .replaceAll('gb', '')
        .replaceAll('ram', '')
        .replaceAll('rom', '')
        .replaceAll('+', '/')
        .replaceAll(RegExp(r'[^a-z0-9/]+'), '')
        .trim();
  }

  String _normalizeColor(dynamic value) {
    var normalized = _normalizeText(
      value,
    ).replaceAll(' colour', '').replaceAll(' color', '').trim();

    const colorAliases = <String, String>{
      'grey': 'gray',
      'space grey': 'space gray',
      'spacegrey': 'space gray',
      'midnight black': 'black',
      'night black': 'black',
      'jet black': 'black',
      'dark black': 'black',
      'navy': 'blue',
      'dark blue': 'blue',
      'ocean blue': 'blue',
      'sky blue': 'blue',
      'ice blue': 'blue',
      'golden': 'gold',
      'sunset gold': 'gold',
      'rose gold': 'gold',
      'silver grey': 'silver gray',
      'silver grey blue': 'silver gray blue',
      'violet': 'purple',
      'lavender': 'purple',
    };

    normalized = colorAliases[normalized] ?? normalized;
    return normalized;
  }

  String _normalizeNetwork(dynamic value) {
    final raw = '${value ?? ''}'.toUpperCase().replaceAll(
      RegExp(r'[^0-9A-Z]'),
      '',
    );
    if (raw.contains('5G')) return '5G';
    if (raw.contains('4G')) return '4G';
    if (raw.contains('LTE')) return '4G';
    if (raw.contains('NR')) return '5G';
    return raw;
  }

  bool _looselyMatches(String left, String right) {
    if (left.isEmpty || right.isEmpty) return false;
    return left == right || left.contains(right) || right.contains(left);
  }

  bool _colorMatches(String left, String right) {
    if (left.isEmpty || right.isEmpty) return false;
    final normalizedLeft = _normalizeColor(left);
    final normalizedRight = _normalizeColor(right);
    return _looselyMatches(normalizedLeft, normalizedRight);
  }

  bool _productMatches(String catalogProduct, String targetProduct) {
    if (catalogProduct.isEmpty || targetProduct.isEmpty) return false;

    final catalogCompact = _compactText(catalogProduct);
    final targetCompact = _compactText(targetProduct);
    if (catalogCompact == targetCompact) return true;

    final catalogTokens = _normalizeText(
      catalogProduct,
    ).split(' ').where((token) => token.isNotEmpty).toList();
    final targetTokens = _normalizeText(
      targetProduct,
    ).split(' ').where((token) => token.isNotEmpty).toList();

    if (catalogTokens.isEmpty || targetTokens.isEmpty) return false;

    final allTargetInCatalog = targetTokens.every(catalogTokens.contains);
    final allCatalogInTarget = catalogTokens.every(targetTokens.contains);

    return allTargetInCatalog && allCatalogInTarget;
  }

  List<_CatalogCandidate> _scoredCatalogCandidates(Map<String, dynamic> item) {
    final targetProduct = _normalizeText(_extractProductName(item));
    final targetVariant = _normalizeVariant(_extractVariant(item));
    final targetColor = _normalizeColor(_extractColor(item));
    final targetNetwork = _normalizeNetwork(_extractNetworkType(item));

    final candidates = <_CatalogCandidate>[];
    for (final catalogItem in _catalog) {
      final productName = _normalizeText(catalogItem['product_name']);
      final variant = _normalizeVariant(catalogItem['variant']);
      final color = _normalizeColor(catalogItem['color']);
      final network = _normalizeNetwork(catalogItem['network_type']);

      final productMatch =
          targetProduct.isNotEmpty &&
          _productMatches(productName, targetProduct);
      if (!productMatch) continue;

      var score = 6;
      if (targetVariant.isEmpty) {
        score += 1;
      } else if (_looselyMatches(variant, targetVariant)) {
        score += variant == targetVariant ? 4 : 2;
      }

      if (targetColor.isEmpty) {
        score += 1;
      } else if (_colorMatches(color, targetColor)) {
        score += color == targetColor ? 3 : 1;
      }

      if (targetNetwork.isEmpty) {
        score += 1;
      } else if (_looselyMatches(network, targetNetwork)) {
        score += network == targetNetwork ? 3 : 1;
      }

      candidates.add(_CatalogCandidate(item: catalogItem, score: score));
    }

    candidates.sort((a, b) => b.score.compareTo(a.score));
    return candidates;
  }

  bool _candidatePassesThreshold(
    _CatalogCandidate candidate,
    Map<String, dynamic> sourceItem,
  ) {
    final targetVariant = _normalizeVariant(_extractVariant(sourceItem));
    final targetColor = _normalizeColor(_extractColor(sourceItem));
    final targetNetwork = _normalizeNetwork(_extractNetworkType(sourceItem));
    final variant = _normalizeVariant(candidate.item['variant']);
    final color = _normalizeColor(candidate.item['color']);
    final network = _normalizeNetwork(candidate.item['network_type']);

    final variantOk =
        targetVariant.isEmpty || _looselyMatches(variant, targetVariant);
    final colorOk = targetColor.isEmpty || _colorMatches(color, targetColor);
    final networkOk =
        targetNetwork.isEmpty || _looselyMatches(network, targetNetwork);

    return variantOk && colorOk && networkOk && candidate.score >= 8;
  }

  Map<String, String> _buildMatchDiagnostics(Map<String, dynamic> item) {
    final targetVariant = _extractVariant(item);
    final targetColor = _extractColor(item);
    final targetNetwork = _extractNetworkType(item);
    final candidates = _scoredCatalogCandidates(item);

    if (candidates.isEmpty) {
      return {
        'reason': 'Nama produk tidak ketemu di katalog aktif.',
        'suggestion': '',
      };
    }

    final best = candidates.first.item;
    final reasons = <String>[];

    final bestVariant = '${best['variant'] ?? ''}'.trim();
    if (targetVariant.isNotEmpty &&
        !_looselyMatches(
          _normalizeVariant(bestVariant),
          _normalizeVariant(targetVariant),
        )) {
      reasons.add('varian beda');
    }

    final bestColor = '${best['color'] ?? ''}'.trim();
    if (targetColor.isNotEmpty &&
        !_colorMatches(
          _normalizeColor(bestColor),
          _normalizeColor(targetColor),
        )) {
      reasons.add('warna beda');
    }

    final bestNetwork = '${best['network_type'] ?? ''}'.trim();
    if (targetNetwork.isNotEmpty &&
        !_looselyMatches(
          _normalizeNetwork(bestNetwork),
          _normalizeNetwork(targetNetwork),
        )) {
      reasons.add('network beda');
    }

    final reason = reasons.isEmpty
        ? 'Ada lebih dari satu kandidat mirip, sistem belum berani pilih otomatis.'
        : 'Cocok sebagian, tapi ${reasons.join(', ')}.';

    final suggestionParts = <String>[
      '${best['product_name'] ?? ''}'.trim(),
      '${best['network_type'] ?? ''}'.trim(),
      '${best['variant'] ?? ''}'.trim(),
      '${best['color'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).toList();

    return {'reason': reason, 'suggestion': suggestionParts.join(' • ')};
  }

  void _changeQty(String variantId, int delta) {
    final updated = _parsedItems.map((item) {
      if ('${item['variant_id']}' != variantId) return item;
      return {...item, 'qty': (_toInt(item['qty']) + delta).clamp(0, 9999)};
    }).toList();

    setState(() => _parsedItems = updated);
  }

  Future<void> _saveParsedStock() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Sesi login tidak ditemukan.',
      );
      return;
    }
    if (_parsedItems.isEmpty) {
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Belum ada hasil parse yang bisa disimpan.',
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSaving = true);

    try {
      final qtyByVariantId = {
        for (final item in _parsedItems)
          '${item['variant_id']}': _toInt(item['qty']),
      };

      await _supabase.rpc(
        'bulk_upsert_stok_gudang',
        params: {
          'p_sator_id': userId,
          'p_tanggal': DateFormat('yyyy-MM-dd').format(_selectedDate),
          'p_data': _catalog
              .map(
                (item) => {
                  'variant_id': item['variant_id'],
                  'stok_gudang': qtyByVariantId['${item['variant_id']}'] ?? 0,
                },
              )
              .toList(),
        },
      );

      if (!mounted) return;
      setState(() => _isSaving = false);
      await showSuccessDialog(
        context,
        title: 'Stok Gudang Tersimpan',
        message:
            'Hasil parsing untuk ${DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDate)} sudah masuk ke stok gudang.',
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Tidak bisa menyimpan stok gudang: $e',
      );
    }
  }

  String _guessMimeType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  ButtonStyle _compactFilledButtonStyle() {
    return FilledButton.styleFrom(
      minimumSize: const Size(double.infinity, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  ButtonStyle _compactOutlinedButtonStyle() {
    return OutlinedButton.styleFrom(
      minimumSize: const Size(double.infinity, 44),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Stok Gudang'),
        backgroundColor: t.background,
        foregroundColor: t.textPrimary,
        surfaceTintColor: t.background,
      ),
      body: _isLoadingCatalog
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
              children: [
                _buildInputModeSwitcher(),
                const SizedBox(height: 16),
                if (_inputMode == _StockInputMode.gemini) ...[
                  _buildImagePickerCard(),
                  const SizedBox(height: 14),
                  if (_selectedImageBytes != null) _buildImagePreview(),
                  if (_selectedImageBytes != null) const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isProcessing ? null : _parseImage,
                      style: _compactFilledButtonStyle(),
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.document_scanner_outlined,
                              size: 18,
                            ),
                      label: Text(_isProcessing ? 'Scan...' : 'Scan'),
                    ),
                  ),
                ] else ...[
                  _buildManualJsonCard(),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isProcessing ? null : _processManualJson,
                      style: _compactFilledButtonStyle(),
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.data_object_outlined, size: 18),
                      label: Text(_isProcessing ? 'Memproses...' : 'Proses'),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                _buildResultSummary(),
                const SizedBox(height: 12),
                if (_unmatchedItems.isNotEmpty) _buildUnmatchedCard(),
                if (_unmatchedItems.isNotEmpty) const SizedBox(height: 12),
                ..._parsedItems.map(_buildParsedItemCard),
                if (_parsedItems.isNotEmpty) const SizedBox(height: 16),
                if (_parsedItems.isNotEmpty)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _isSaving ? null : _saveParsedStock,
                      style: _compactFilledButtonStyle(),
                      icon: _isSaving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_outlined, size: 18),
                      label: Text(
                        _isSaving ? 'Menyimpan...' : 'Simpan Stok Gudang',
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _buildHeaderCard(String dateLabel) {
    return Row(
      children: [
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            dateLabel,
            textAlign: TextAlign.right,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: t.textMutedStrong,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildInputModeSwitcher() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeaderCard(
          DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDate),
        ),
        SegmentedButton<_StockInputMode>(
          style: ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: const VisualDensity(horizontal: -2, vertical: -3),
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            ),
            textStyle: WidgetStateProperty.all(
              const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ),
          segments: const [
            ButtonSegment<_StockInputMode>(
              value: _StockInputMode.gemini,
              label: Text('Scan'),
              icon: Icon(Icons.document_scanner_outlined, size: 16),
            ),
            ButtonSegment<_StockInputMode>(
              value: _StockInputMode.manualJson,
              label: Text('Manual'),
              icon: Icon(Icons.data_object_outlined, size: 16),
            ),
          ],
          selected: {_inputMode},
          onSelectionChanged: (selection) {
            setState(() {
              _inputMode = selection.first;
              _parsedItems = const [];
              _unmatchedItems = const [];
            });
          },
        ),
      ],
    );
  }

  Widget _buildImagePickerCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: OutlinedButton.icon(
        onPressed: () => _pickImage(ImageSource.gallery),
        icon: const Icon(Icons.photo_library_outlined),
        label: Text(
          _selectedImageName == null ? 'Pilih dari Galeri' : 'Ganti Gambar',
        ),
        style: _compactOutlinedButtonStyle(),
      ),
    );
  }

  Widget _buildImagePreview() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: t.surface3),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedImageName ?? 'Preview gambar',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          AspectRatio(
            aspectRatio: 4 / 5,
            child: Image.memory(
              _selectedImageBytes!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: t.surface2,
                alignment: Alignment.center,
                child: const Text('Preview gambar tidak tersedia'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualJsonCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: TextField(
        controller: _manualJsonController,
        minLines: 10,
        maxLines: 16,
        decoration: InputDecoration(
          filled: true,
          fillColor: t.background,
          alignLabelWithHint: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: t.surface3),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: t.surface3),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: t.primaryAccent, width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _buildResultSummary() {
    final totalQty = _parsedItems.fold<int>(
      0,
      (sum, item) => sum + _toInt(item['qty']),
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildResultStat(
              label: 'Varian',
              value: '${_parsedItems.length}',
              accentColor: t.primaryAccent,
              backgroundColor: t.primaryAccentSoft,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _buildResultStat(
              label: 'Unit',
              value: '$totalQty',
              accentColor: t.success,
              backgroundColor: t.success.withValues(alpha: 0.12),
            ),
          ),
          if (_unmatchedItems.isNotEmpty) ...[
            const SizedBox(width: 10),
            Expanded(
              child: _buildResultStat(
                label: 'Belum Cocok',
                value: '${_unmatchedItems.length}',
                accentColor: t.warning,
                backgroundColor: t.warningSoft,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultStat({
    required String label,
    required String value,
    required Color accentColor,
    required Color backgroundColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: accentColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnmatchedCard() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: t.surface3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Item Belum Cocok ke Katalog',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: t.warning,
              ),
            ),
            const SizedBox(height: 8),
            ..._unmatchedItems.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  [
                    '${item['product_name'] ?? '-'}',
                    if ('${item['network_type'] ?? ''}'.trim().isNotEmpty)
                      '${item['network_type']}',
                    '${item['variant'] ?? '-'}',
                    '${item['color'] ?? '-'}',
                    'qty ${_toInt(item['qty'])}',
                    if (_toInt(item['otw']) > 0) 'otw ${_toInt(item['otw'])}',
                  ].join(' • '),
                  style: TextStyle(fontSize: 12, color: t.textMutedStrong),
                ),
              ),
            ),
            ..._unmatchedItems.map((item) {
              final reason = '${item['reason'] ?? ''}'.trim();
              final suggestion = '${item['suggestion'] ?? ''}'.trim();
              if (reason.isEmpty && suggestion.isEmpty) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 8, left: 4),
                child: Text(
                  [
                    if (reason.isNotEmpty) reason,
                    if (suggestion.isNotEmpty) 'Kandidat terdekat: $suggestion',
                  ].join(' '),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: t.warning,
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildParsedItemCard(Map<String, dynamic> item) {
    final variantId = '${item['variant_id']}';
    final qty = _toInt(item['qty']);
    final otw = _toInt(item['otw']);
    final confidence = _toDouble(item['confidence']);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: t.surface3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                        '${item['product_name'] ?? 'Produk'}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item['network_type'] ?? '-'} • ${item['variant'] ?? '-'} • ${item['color'] ?? '-'}',
                        style: TextStyle(
                          fontSize: 12,
                          color: t.textMutedStrong,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: t.primaryAccentSoft,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${(confidence * 100).clamp(0, 100).toStringAsFixed(0)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: t.primaryAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _qtyButton(Icons.remove, () => _changeQty(variantId, -1)),
                Container(
                  width: 60,
                  alignment: Alignment.center,
                  child: Text(
                    '$qty',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                _qtyButton(Icons.add, () => _changeQty(variantId, 1)),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (otw > 0)
                      Text(
                        'OTW $otw',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: t.warning,
                        ),
                      ),
                    Text(
                      'Variant ID: ${variantId.substring(0, 8)}...',
                      style: TextStyle(fontSize: 11, color: t.textMuted),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _qtyButton(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: t.surface3),
        ),
        child: Icon(icon, size: 18, color: t.textPrimary),
      ),
    );
  }
}
