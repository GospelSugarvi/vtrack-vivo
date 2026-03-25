import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

class StockValidationPage extends StatefulWidget {
  const StockValidationPage({super.key});

  @override
  State<StockValidationPage> createState() => _StockValidationPageState();
}

class _StockValidationPageState extends State<StockValidationPage> with SingleTickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;
  
  // Data Lists
  List<Map<String, dynamic>> _pendingItems = [];
  List<Map<String, dynamic>> _validatedItems = [];
  
  // Selection for bulk validation in Pending tab
  final Map<String, bool> _selectedPendingItems = {};
  
  // Store info
  String? _storeId;
  String? _storeName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool get _isToday {
    final now = DateTime.now();
    return _selectedDate.year == now.year && 
           _selectedDate.month == now.month && 
           _selectedDate.day == now.day;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  Widget _terminalCell(
    String value, {
    required int flex,
    Color? color,
    FontWeight weight = FontWeight.w600,
    TextAlign textAlign = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: textAlign,
        style: AppTextStyle.mono(
          color ?? t.textPrimary,
          weight: weight,
        ),
      ),
    );
  }

  Widget _buildCompactStockCell({
    required String kategori,
    required String tipe,
    required String warna,
    required String ramRom,
    required String imei,
    String qty = '1',
    Widget? trailing,
    Color? accent,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  kategori,
                  style: AppTextStyle.mono(
                    t.textPrimary,
                    weight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _terminalCell(tipe, flex: 2, color: accent ?? t.info, weight: FontWeight.w700),
                    _terminalCell(warna, flex: 2, color: accent ?? t.info, weight: FontWeight.w700),
                    _terminalCell(ramRom, flex: 2, color: accent ?? t.info, weight: FontWeight.w700),
                    _terminalCell(imei, flex: 5, color: t.textSecondary),
                    SizedBox(
                      width: 32,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          qty,
                          textAlign: TextAlign.right,
                          style: AppTextStyle.mono(
                            t.textPrimary,
                            weight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 10),
            trailing,
          ],
        ],
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('id', 'ID'),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _selectedPendingItems.clear();
      });
      _loadData();
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // 1. Get Promotor's Store
      final storeRows = await Supabase.instance.client
          .from('assignments_promotor_store')
          .select('store_id, stores(store_name)')
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1);
      final assignments = List<Map<String, dynamic>>.from(storeRows);
      final storeData = assignments.isNotEmpty ? assignments.first : null;

      if (storeData == null) {
        throw Exception('Anda belum ditugaskan di toko manapun.');
      }

      final storeId = storeData['store_id'];
      _storeId = storeId;
      _storeName = storeData['stores']['store_name'];

      // 2. Fetch Validated Items for Selected Date
      // Use date range for robustness
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day).toIso8601String();
      final endOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, 23, 59, 59).toIso8601String();

      // Find validations for this store and date
      final validations = await Supabase.instance.client
          .from('stock_validations')
          .select('id')
          .eq('store_id', storeId)
          .gte('validation_date', startOfDay)
          .lte('validation_date', endOfDay);

      final validationRows = List<Map<String, dynamic>>.from(validations);
      final validationIds = validationRows
          .map((v) => v['id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();
      
      List<Map<String, dynamic>> validatedItemsRaw = [];
      Set<String> validatedStockIds = {};

      if (validationIds.isNotEmpty) {
        // Fetch items belonging to these validations
        final itemsData = await Supabase.instance.client
            .from('stock_validation_items')
            .select('''
              *,
              stok:stok_id (
                id,
                imei,
                product_variants (
                  ram_rom,
                  color,
                  products (model_name)
                )
              )
            ''')
            .filter(
              'validation_id',
              'in',
              '(${validationIds.map((id) => '"$id"').join(',')})',
            );
            
        validatedItemsRaw = List<Map<String, dynamic>>.from(itemsData);
        validatedStockIds = validatedItemsRaw.map((e) => e['stok_id'].toString()).toSet();
      }

      // 3. Fetch Pending Items (Only relevant if viewing TODAY)
      // Pending items = Current Active Stock - Already Validated Today
      List<Map<String, dynamic>> pendingItemsRaw = [];
      
      // We always fetch active stock to show what is available to be validated
      // Even if looking at past, we might not show it, but logic is cleaner if we fetch.
      // Optimally: Only fetch if isToday.
      if (_isToday) {
        final stockData = await Supabase.instance.client
            .from('stok')
            .select('''
              id,
              imei,
              tipe_stok,
              product_variants!variant_id(
                id,
                ram_rom,
                color,
                products!product_id(
                  model_name,
                  series
                )
              )
            ''')
            .eq('store_id', storeId)
            .eq('is_sold', false);
            
        // Filter out items that are already validated TODAY
        pendingItemsRaw = List<Map<String, dynamic>>.from(stockData)
            .where((item) => !validatedStockIds.contains(item['id'].toString()))
            .toList();
      }

      if (mounted) {
        setState(() {
          _validatedItems = validatedItemsRaw;
          _pendingItems = pendingItemsRaw;
          _isLoading = false;
        });
      }

    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _isLoading = false);
        showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
      }
    }
  }

  Future<void> _submitValidation() async {
    final selectedEntries = _selectedPendingItems.entries
        .where((entry) => entry.value)
        .toList();
    if (selectedEntries.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null || _storeId == null) {
        throw Exception('Data user atau toko tidak ditemukan');
      }

      final validationDate = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final existingValidation = await Supabase.instance.client
          .from('stock_validations')
          .select('id')
          .eq('promotor_id', userId)
          .eq('store_id', _storeId!)
          .eq('validation_date', validationDate)
          .eq('status', 'completed')
          .maybeSingle();

      String validationId;
      if (existingValidation != null) {
        validationId = existingValidation['id'].toString();
      } else {
        final validationRows = await Supabase.instance.client
            .from('stock_validations')
            .insert({
              'promotor_id': userId,
              'store_id': _storeId,
              'validation_date': validationDate,
              'total_items': _pendingItems.length + _validatedItems.length,
              'validated_items': 0,
              'status': 'completed',
            })
            .select('id')
            .limit(1);
        validationId = List<Map<String, dynamic>>.from(validationRows).first['id']
            .toString();
      }

      // 2. Prepare Items
      final itemsToInsert = <Map<String, dynamic>>[];

      for (final entry in selectedEntries) {
        final stockId = entry.key;
        final stockItem = _pendingItems.firstWhere(
          (e) => e['id'].toString() == stockId,
          orElse: () => {},
        );

        if (stockItem.isNotEmpty) {
          itemsToInsert.add({
            'validation_id': validationId,
            'stok_id': stockId,
            'imei': stockItem['imei'],
            'original_condition': stockItem['tipe_stok'],
            'validated_condition': stockItem['tipe_stok'],
            'is_present': true,
          });
        }
      }

      if (itemsToInsert.isNotEmpty) {
        await Supabase.instance.client
            .from('stock_validation_items')
            .insert(itemsToInsert);
      }

      final allItemsForValidation = await Supabase.instance.client
          .from('stock_validation_items')
          .select('id')
          .eq('validation_id', validationId);
      final validatedCount = List<Map<String, dynamic>>.from(
        allItemsForValidation,
      ).length;

      await Supabase.instance.client
          .from('stock_validations')
          .update({
            'total_items': _pendingItems.length + _validatedItems.length,
            'validated_items': validatedCount,
            'status': 'completed',
          })
          .eq('id', validationId);

      if (mounted) {
        await showSuccessDialog(
          context,
          title: 'Berhasil',
          message: '${itemsToInsert.length} item divalidasi.',
        );
      }

      // Clear selection and reload
      _selectedPendingItems.clear();
      await _loadData();

    } catch (e) {
      debugPrint('Submit error: $e');
      if (mounted) {
        showErrorDialog(context, title: 'Gagal', message: 'Gagal validasi: $e');
        setState(() => _isLoading = false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Validasi Stok Harian', style: TextStyle(fontSize: AppTypeScale.title, fontWeight: FontWeight.bold)),
            Text(
              _storeName ?? 'Loading...',
              style: AppTextStyle.bodySm(t.textMuted),
            ),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: () => _selectDate(context),
            icon: Icon(Icons.calendar_today, size: 16),
            label: Text(DateFormat('dd MMM').format(_selectedDate)),
            style: TextButton.styleFrom(foregroundColor: t.info),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: t.info,
          unselectedLabelColor: t.textSecondary,
          indicatorColor: t.info,
          tabs: [
            Tab(text: 'Belum Validasi (${_pendingItems.length})'),
            Tab(text: 'Sudah Validasi (${_validatedItems.length})'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildPendingTab(),
                _buildValidatedTab(),
              ],
            ),
    );
  }

  Widget _buildPendingTab() {
    if (!_isToday) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: t.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Anda melihat data masa lalu.',
              style: AppTextStyle.bodyLg(t.textPrimary, weight: FontWeight.bold),
            ),
            Text(
              'Tab ini hanya aktif untuk Hari Ini.',
              style: AppTextStyle.bodyMd(t.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_pendingItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 80, color: t.success),
            const SizedBox(height: 16),
            Text(
              'Semua stok sudah divalidasi hari ini!',
              style: AppTextStyle.bodyLg(t.textPrimary, weight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => context.push('/promotor/stock-input'),
              icon: Icon(Icons.add),
              label: const Text('Ada barang fisik tapi tidak ada di list? Input Stok Manual'),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12)),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          color: t.warningSoft,
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 20, color: t.warning),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Centang stok yang fisik unitnya ADA.', 
                  style: AppTextStyle.bodyMd(t.warning),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
          child: Row(
            children: [
              Checkbox(
                value: _selectedPendingItems.length == _pendingItems.length && _pendingItems.isNotEmpty,
                onChanged: (val) {
                  setState(() {
                    if (val == true) {
                      for (var item in _pendingItems) {
                        _selectedPendingItems[item['id'].toString()] = true;
                      }
                    } else {
                      _selectedPendingItems.clear();
                    }
                  });
                },
              ),
              const Text('Pilih Semua'),
              const Spacer(),
              ElevatedButton(
                onPressed: _selectedPendingItems.isEmpty ? null : _submitValidation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.info,
                  foregroundColor: t.textOnAccent,
                ),
                child: Text('Validasi (${_selectedPendingItems.length})'),
              ),
            ],
          ),
        ),
        Expanded(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: Row(
                  children: [
                    _terminalCell('TIPE', flex: 2, color: t.info, weight: FontWeight.w800),
                    _terminalCell('WARNA', flex: 2, color: t.info, weight: FontWeight.w800),
                    _terminalCell('RAM', flex: 2, color: t.info, weight: FontWeight.w800),
                    _terminalCell('IMEI', flex: 5, color: t.info, weight: FontWeight.w800),
                    SizedBox(
                      width: 32,
                      child: Text(
                        'QTY',
                        textAlign: TextAlign.right,
                        style: AppTextStyle.mono(t.info, weight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _pendingItems.length,
                  itemBuilder: (context, index) {
              final item = _pendingItems[index];
              final id = item['id'].toString();
              final variant = _asMap(item['product_variants']);
              final product = _asMap(variant['products']);
              
              return InkWell(
                onTap: () {
                  setState(() {
                    if (_selectedPendingItems[id] == true) {
                      _selectedPendingItems.remove(id);
                    } else {
                      _selectedPendingItems[id] = true;
                    }
                  });
                },
                child: _buildCompactStockCell(
                  kategori: '${product['model_name'] ?? 'Produk'}',
                  tipe: '${item['tipe_stok'] ?? '-'}',
                  warna: '${variant['color'] ?? '-'}',
                  ramRom: '${variant['ram_rom'] ?? '-'}',
                  imei: '${item['imei'] ?? '-'}',
                  trailing: Checkbox(
                    value: _selectedPendingItems[id] ?? false,
                    onChanged: (val) {
                      setState(() {
                        if (val == true) {
                          _selectedPendingItems[id] = true;
                        } else {
                          _selectedPendingItems.remove(id);
                        }
                      });
                    },
                    activeColor: t.info,
                  ),
                  accent: t.info,
                ),
              );
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildValidatedTab() {
    if (_validatedItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.assignment_late_outlined, size: 64, color: t.textSecondary),
            const SizedBox(height: 16),
            Text(
              _isToday ? 'Belum ada item divalidasi hari ini' : 'Tidak ada data validasi pada tanggal ini',
              style: AppTextStyle.bodyMd(t.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Row(
            children: [
              _terminalCell('TIPE', flex: 2, color: t.success, weight: FontWeight.w800),
              _terminalCell('WARNA', flex: 2, color: t.success, weight: FontWeight.w800),
              _terminalCell('RAM', flex: 2, color: t.success, weight: FontWeight.w800),
              _terminalCell('IMEI', flex: 5, color: t.success, weight: FontWeight.w800),
              SizedBox(
                width: 32,
                child: Text(
                  'QTY',
                  textAlign: TextAlign.right,
                  style: AppTextStyle.mono(t.success, weight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _validatedItems.length,
      itemBuilder: (context, index) {
        final item = _validatedItems[index];
        final stockData = _asMap(item['stok']);
        String title = 'Unknown Product';
        String tipe = '${item['validated_condition'] ?? '-'}';
        String subtitle = '';
        String imei = item['imei'] ?? '-';
        
        if (stockData.isNotEmpty &&
            stockData['product_variants'] != null &&
            _asMap(stockData['product_variants'])['products'] != null) {
            final v = _asMap(stockData['product_variants']);
            final p = _asMap(v['products']);
            title = p['model_name'] ?? 'Unknown';
            subtitle = '${v['ram_rom']} - ${v['color']}';
        }

        final parts = subtitle.split(' - ');
        final ramRom = parts.isNotEmpty ? parts.first : '-';
        final warna = parts.length > 1 ? parts[1] : '-';

        return _buildCompactStockCell(
          kategori: title,
          tipe: tipe,
          warna: warna,
          ramRom: ramRom,
          imei: imei,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: t.successSoft,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.success.withValues(alpha: 0.25)),
            ),
            child: Column(
              children: [
                Text(
                  _getTime(item['created_at'] ?? ''),
                  style: AppTextStyle.mono(t.success),
                ),
                const SizedBox(height: 2),
                Text(
                  'OK',
                  style: AppTextStyle.mono(
                    t.success,
                    weight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          accent: t.success,
        );
      },
          ),
        ),
      ],
    );
  }

  String _getTime(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
    } catch (_) {
      return '';
    }
  }
}
