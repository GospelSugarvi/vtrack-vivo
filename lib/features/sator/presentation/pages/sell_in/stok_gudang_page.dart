// ignore_for_file: deprecated_member_use
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/foundation.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:screenshot/screenshot.dart';
import 'package:vtrack/core/utils/device_image_saver.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

class StokGudangPage extends StatefulWidget {
  const StokGudangPage({super.key});

  @override
  State<StokGudangPage> createState() => _StokGudangPageState();
}

class _StokGudangPageState extends State<StokGudangPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _stockList = [];
  bool _isLoading = true;
  bool _isExporting = false;
  String _searchQuery = '';
  String _userArea = 'Gudang';
  DateTime _selectedDate = DateTime.now(); // Add selected date
  String? _errorMessage;

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

  String _statusLabelForQty(int qty) {
    if (qty >= 10) return 'Aman';
    if (qty >= 5) return 'Cukup';
    return 'Tipis';
  }

  Color _statusColorForQty(int qty) {
    if (qty >= 10) return t.success;
    if (qty >= 5) return t.warning;
    return t.danger;
  }

  double _marginPct(Map<String, dynamic> item) {
    final modal = _toDouble(item['modal'] ?? item['price']);
    final srp = _toDouble(item['srp']);
    if (srp <= 0 || srp <= modal) return 0;
    return ((srp - modal) / srp) * 100;
  }

  int _profitValue(Map<String, dynamic> item) {
    final modal = _toInt(item['modal'] ?? item['price']);
    final srp = _toInt(item['srp']);
    if (srp <= modal) return 0;
    return srp - modal;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;

      final profileRaw = await _supabase.rpc('get_my_profile_snapshot');
      final profile = Map<String, dynamic>.from(
        (profileRaw as Map?) ?? const <String, dynamic>{},
      );
      _userArea = '${profile['area'] ?? 'Gudang'}';

      final dateStr = _selectedDate.toIso8601String().split('T')[0];

      // Pass selected date to RPC
      final data = await _supabase.rpc(
        'get_gudang_stock',
        params: {'p_sator_id': userId, 'p_tanggal': dateStr},
      );

      if (mounted) {
        setState(() {
          // Sort: Quantity DESC, then OTW DESC, then Price ASC
          final List<Map<String, dynamic>> sortedList =
              List<Map<String, dynamic>>.from(data ?? []);
          for (var item in sortedList) {
            item['qty'] = _toInt(item['qty']);
            item['otw'] = _toInt(item['otw']);
            item['price'] = _toInt(item['price']);
            item['modal'] = _toInt(item['modal'] ?? item['price']);
            item['srp'] = _toInt(item['srp']);
          }

          sortedList.sort((a, b) {
            final qtyA = a['qty'] as int;
            final qtyB = b['qty'] as int;
            if (qtyA != qtyB) return qtyB.compareTo(qtyA); // Higher qty first

            final otwA = a['otw'] as int;
            final otwB = b['otw'] as int;
            if (otwA != otwB) return otwB.compareTo(otwA); // Higher otw first

            final priceA = a['price'] as int;
            final priceB = b['price'] as int;
            return priceA.compareTo(priceB); // Lower price first (if no stock)
          });

          // Treat as "empty day" when no stock snapshot exists for selected date.
          // Some RPC versions may still return full product placeholders with qty=0.
          final hasSnapshot = sortedList.any(
            (item) => item['last_updated'] != null,
          );
          _stockList = hasSnapshot ? sortedList : [];
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Error loading stock: $e');
      if (mounted) {
        setState(() {
          _stockList = [];
          _isLoading = false;
          _errorMessage = 'Tidak bisa memuat stok gudang.';
        });
      }
    }
  }

  Future<void> _showDatePicker() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 7)),
      locale: const Locale('id', 'ID'),
    );

    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      _loadData();
    }
  }

  Future<void> _showCreateStockDialog() async {
    DateTime selectedDate = DateTime.now();

    final result = await showDialog<DateTime>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          contentPadding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: selectedDate,
                    firstDate: DateTime.now().subtract(const Duration(days: 7)),
                    lastDate: DateTime.now().add(const Duration(days: 7)),
                  );
                  if (picked != null) {
                    setDialogState(() => selectedDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: t.surface3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.calendar_today_outlined,
                        size: 18,
                        color: t.primaryAccent,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          DateFormat(
                            'dd MMM yyyy',
                            'id_ID',
                          ).format(selectedDate),
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: AppTypeScale.body,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, selectedDate),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primaryAccent,
                foregroundColor: t.textOnAccent,
                minimumSize: const Size(0, 40),
              ),
              child: const Text('Lanjutkan'),
            ),
          ],
        ),
      ),
    );

    if (result != null && mounted) {
      _checkAndNavigateToScan(result);
    }
  }

  Future<void> _checkAndNavigateToScan(DateTime selectedDate) async {
    var loadingShown = false;
    try {
      final userId = _supabase.auth.currentUser!.id;

      showDialog(
        context: context,
        useRootNavigator: true,
        barrierDismissible: false,
        builder: (context) {
          loadingShown = true;
          return const Center(child: CircularProgressIndicator());
        },
      );

      final data = await _supabase.rpc(
        'get_stok_gudang_status_for_date',
        params: {
          'p_tanggal': selectedDate.toIso8601String().split('T')[0],
          'p_sator_id': userId,
        },
      );

      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }

      final hasData = data['has_data'] == true;
      final createdBy = data['created_by'] as String?;
      final createdAt = data['created_at'] as String?;

      if (mounted) {
        // Navigate to scan page with date and status info
        final result = await context.pushNamed(
          'sator-scan-gudang',
          extra: {
            'selectedDate': selectedDate,
            'hasExistingData': hasData,
            'createdBy': createdBy,
            'createdAt': createdAt,
          },
        );

        // If returned from scan page (after save), reload with that date
        if (result == true && mounted) {
          setState(() => _selectedDate = selectedDate);
          _loadData();
        }
      }
    } catch (e) {
      if (mounted) {
        if (loadingShown) {
          Navigator.of(context, rootNavigator: true).pop();
        }
        await showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
      }
    }
  }

  List<Map<String, dynamic>> get _filteredList {
    var list = _stockList;
    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      list = list
          .where(
            (s) =>
                (s['product_name'] ?? '').toString().toLowerCase().contains(
                  query,
                ) ||
                (s['variant'] ?? '').toString().toLowerCase().contains(query) ||
                (s['color'] ?? '').toString().toLowerCase().contains(query),
          )
          .toList();
    }
    return list;
  }

  List<Map<String, dynamic>> get _visibleList {
    return _filteredList
        .where((item) => ((item['qty'] as num?)?.toInt() ?? 0) > 0)
        .toList();
  }

  Map<String, List<Map<String, dynamic>>> get _groupedVisibleList {
    final grouped = <String, List<Map<String, dynamic>>>{};

    for (final item in _visibleList) {
      final productName = (item['product_name'] ?? '').toString();
      final networkType = (item['network_type'] ?? '').toString();
      final key = '$productName|$networkType';
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(item);
    }

    grouped.forEach((_, items) {
      items.sort((a, b) {
        final qtyA = (a['qty'] as num?)?.toInt() ?? 0;
        final qtyB = (b['qty'] as num?)?.toInt() ?? 0;
        if (qtyA != qtyB) return qtyB.compareTo(qtyA);
        final priceA = (a['price'] as num?)?.toInt() ?? 0;
        final priceB = (b['price'] as num?)?.toInt() ?? 0;
        return priceA.compareTo(priceB);
      });
    });

    return grouped;
  }

  String _variantDescriptor(Map<String, dynamic> item) {
    final parts = <String>[
      '${item['variant'] ?? ''}'.trim(),
      '${item['color'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return '-';
    return parts.join(' • ');
  }

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDate);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Stok Gudang', style: AppTextStyle.titleSm(t.textPrimary)),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                InkWell(
                  onTap: _showDatePicker,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 2,
                      vertical: 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dateStr,
                          style: AppTextStyle.bodySm(
                            t.textPrimary,
                            weight: FontWeight.normal,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.expand_more,
                          size: 16,
                          color: t.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        foregroundColor: t.textPrimary,
        surfaceTintColor: t.background,
        backgroundColor: t.background,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _isExporting ? null : _showPreviewAndSave,
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 38),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                backgroundColor: t.primaryAccentSoft,
                foregroundColor: t.primaryAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isExporting
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: t.primaryAccent,
                      ),
                    )
                  : const Icon(Icons.image_outlined, size: 18),
              label: Text(
                _isExporting ? 'Memuat...' : 'Preview Gambar',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: _filteredList.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: _showCreateStockDialog,
              backgroundColor: t.success,
              foregroundColor: t.textPrimary,
              icon: Icon(Icons.add),
              label: const Text('Buat Stok Baru'),
            ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? RefreshIndicator(
                    onRefresh: _loadData,
                    color: t.primaryAccent,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: t.surface1,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: t.surface3),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Data stok gudang belum bisa dimuat',
                                style: AppTextStyle.titleMd(t.textPrimary),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!,
                                style: AppTextStyle.bodySm(t.textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : _visibleList.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
                    onRefresh: _loadData,
                    child: ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _groupedVisibleList.length,
                      itemBuilder: (context, index) {
                        final entry = _groupedVisibleList.entries.elementAt(
                          index,
                        );
                        return _buildProductGroupCard(entry.value);
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Cari model, varian, atau warna',
          prefixIcon: Icon(Icons.search, color: t.textMutedStrong),
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
            borderSide: BorderSide(color: t.primaryAccent, width: 1.4),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildProductGroupCard(List<Map<String, dynamic>> items) {
    final first = items.first;
    final productName = (first['product_name'] ?? '').toString();
    final networkType = (first['network_type'] ?? '').toString();
    final totalQty = items.fold<int>(
      0,
      (sum, item) => sum + _toInt(item['qty']),
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: t.surface3),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Row(
          children: [
            Expanded(
              child: Text(
                productName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.bodyMd(
                  t.textPrimary,
                  weight: FontWeight.w700,
                ),
              ),
            ),
            if (networkType.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: t.primaryAccentSoft,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  networkType,
                  style: AppTextStyle.bodySm(
                    t.primaryAccent,
                    weight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Total stok: $totalQty unit',
            style: AppTextStyle.bodySm(
              t.textSecondary,
              weight: FontWeight.w600,
            ),
          ),
        ),
        children: items.asMap().entries.map((entry) {
          return Column(
            children: [
              if (entry.key == 0) Divider(height: 1, color: t.surface3),
              if (entry.key > 0) Divider(height: 10, color: t.surface3),
              _buildVariantRow(entry.value),
            ],
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVariantRow(Map<String, dynamic> stock) {
    final qty = _toInt(stock['qty']);
    final statusColor = _statusColorForQty(qty);
    final statusLabel = _statusLabelForQty(qty);
    final descriptor = _variantDescriptor(stock);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              descriptor,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.bodySm(
                t.textPrimary,
                weight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 72,
            child: Text(
              '$qty unit',
              textAlign: TextAlign.right,
              style: AppTextStyle.bodySm(
                t.textSecondary,
                weight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              statusLabel,
              style: AppTextStyle.bodySm(statusColor, weight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final dateStr = DateFormat('dd MMMM yyyy', 'id_ID').format(_selectedDate);
    final isToday =
        _selectedDate.year == DateTime.now().year &&
        _selectedDate.month == DateTime.now().month &&
        _selectedDate.day == DateTime.now().day;

    final subtitle =
        'Belum ada data stok gudang tersedia untuk tanggal $dateStr.\nSilakan update stok terbaru.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: t.primaryAccentSoft,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inventory_2_outlined,
                size: 64,
                color: t.primaryAccent.withValues(alpha: 0.8),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'Stok Belum Diisi',
              style: AppFontTokens.resolve(
                AppFontRole.display,
                fontSize: AppTypeScale.title,
                fontWeight: FontWeight.bold,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: AppFontTokens.resolve(
                AppFontRole.primary,
                fontSize: AppTypeScale.body,
                color: t.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (isToday)
              SizedBox(
                width: 200,
                child: ElevatedButton.icon(
                  onPressed: _showCreateStockDialog,
                  icon: Icon(Icons.add),
                  label: const Text('Input Stok Sekarang'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: t.primaryAccent,
                    foregroundColor: t.textOnAccent,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showPreviewAndSave() async {
    if (!mounted) return;
    setState(() => _isExporting = true);

    try {
      final imageBytes = await ScreenshotController().captureFromLongWidget(
        InheritedTheme.captureAll(
          context,
          Material(
            color: Colors.transparent,
            child: Center(child: _buildExportWidget()),
          ),
        ),
        pixelRatio: 2.2,
        context: context,
        delay: const Duration(milliseconds: 120),
      );

      if (!mounted) return;
      setState(() => _isExporting = false);

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Preview Gambar Stok'),
          content: SizedBox(
            width: 920,
            height: 620,
            child: Column(
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
                        child: Image.memory(imageBytes, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Pastikan data sudah benar sebelum dikirim ke toko.',
                  style: AppTextStyle.bodySm(t.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Batal'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                if (dialogContext.mounted) {
                  Navigator.pop(dialogContext);
                }
                await _saveImageToGallery(imageBytes);
              },
              icon: const Icon(Icons.download),
              label: const Text('Simpan ke Galeri'),
              style: ElevatedButton.styleFrom(
                backgroundColor: t.primaryAccent,
                foregroundColor: t.textOnAccent,
              ),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('❌ Capture error: $e');
      if (mounted) {
        setState(() => _isExporting = false);
        await showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
      }
    }
  }

  Future<void> _saveImageToGallery(Uint8List bytes) async {
    try {
      final fileName =
          'stok_gudang_${DateFormat('yyyyMMdd_HHmm').format(_selectedDate)}.png';

      if (!kIsWeb) {
        final success = await DeviceImageSaver.saveImage(bytes, name: fileName);

        if (mounted) {
          if (success) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✅ Gambar tersimpan di Gallery'),
                backgroundColor: t.success,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('❌ Gagal menyimpan gambar'),
                backgroundColor: t.danger,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Save error: $e');
    }
  }

  Widget _buildExportWidget() {
    final dateStr = DateFormat(
      'EEEE, dd MMMM yyyy',
      'id_ID',
    ).format(_selectedDate);
    final amount = NumberFormat.decimalPattern('id_ID');
    final yearText = DateTime.now().year.toString();

    final list = List<Map<String, dynamic>>.from(_visibleList);
    list.sort((a, b) {
      final qtyA = _toInt(a['qty']);
      final qtyB = _toInt(b['qty']);
      if (qtyA != qtyB) return qtyB.compareTo(qtyA);
      return _toInt(
        a['modal'] ?? a['price'],
      ).compareTo(_toInt(b['modal'] ?? b['price']));
    });

    return Container(
      width: 860,
      color: const Color(0xFFFAF8F3),
      padding: const EdgeInsets.all(10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                    'STOK VIVO ${_userArea.toUpperCase()}',
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
                          dateStr,
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
                          'STOK',
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
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFAF8F3),
              border: Border.all(color: const Color(0xFFD8D2C4)),
            ),
            child: Column(
              children: [
                _buildStockExportTableHeader(),
                ...list.asMap().entries.map(
                  (entry) => _buildStockExportTableRow(
                    entry.key + 1,
                    entry.value,
                    amount,
                  ),
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
                  'STOK VIVO ${_userArea.toUpperCase()} © $yearText',
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

  Widget _buildStockExportTableHeader() {
    return Container(
      color: const Color(0xFFF0ECE3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        children: [
          _stockExportHeaderCell('Item', flex: 9, align: TextAlign.left),
          _stockExportHeaderCell(
            'Harga Modal',
            flex: 4,
            align: TextAlign.right,
          ),
          _stockExportHeaderCell('Profit', flex: 5, align: TextAlign.right),
          _stockExportHeaderCell('Status', flex: 3, align: TextAlign.center),
        ],
      ),
    );
  }

  Widget _buildStockExportTableRow(
    int index,
    Map<String, dynamic> item,
    NumberFormat amount,
  ) {
    final qty = _toInt(item['qty']);
    final modal = _toInt(item['modal'] ?? item['price']);
    final profit = _profitValue(item);
    final marginPct = _marginPct(item);
    final specs = [
      '${item['network_type'] ?? ''}'.trim(),
      '${item['variant'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty).join(' • ');
    final color = '${item['color'] ?? ''}'.trim();
    final productTitle = color.isEmpty
        ? '${item['product_name'] ?? 'Produk'}'
        : '${item['product_name'] ?? 'Produk'} ($color)';

    final statusText = _statusLabelForQty(qty).toUpperCase();

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
          _stockExportValueCell(
            amount.format(modal),
            flex: 4,
            align: TextAlign.right,
            scaleDown: true,
            fontSize: 14.5,
            color: const Color(0xFF7A7060),
          ),
          _stockExportValueCell(
            profit > 0
                ? '${amount.format(profit)} (${marginPct.toStringAsFixed(1)}%)'
                : '-',
            flex: 5,
            align: TextAlign.right,
            scaleDown: true,
            fontSize: 14.5,
            weight: FontWeight.w700,
            color: const Color(0xFF7A7060),
            fontFamily: GoogleFonts.spaceMono().fontFamily,
          ),
          _stockExportValueCell(
            statusText,
            flex: 3,
            align: TextAlign.center,
            fontSize: 13.5,
            weight: FontWeight.w700,
            color: const Color(0xFF1C1A16),
          ),
        ],
      ),
    );
  }

  Widget _stockExportHeaderCell(
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

  Widget _stockExportValueCell(
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
}
