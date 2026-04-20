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

class _StockValidationPageState extends State<StockValidationPage>
    with SingleTickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  late TabController _tabController;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = false;

  // Data Lists
  List<Map<String, dynamic>> _pendingItems = [];
  List<Map<String, dynamic>> _validatedItems = [];
  String _pendingFilter = 'all';
  String _validatedFilter = 'all';

  // Selection for bulk validation in Pending tab
  final Map<String, bool> _selectedPendingItems = {};

  // Store info
  String? _storeId;
  String? _storeName;
  List<String> _stockScopeStoreIds = const <String>[];

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

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int _sortByText(dynamic a, dynamic b) {
    return '${a ?? ''}'.toLowerCase().compareTo('${b ?? ''}'.toLowerCase());
  }

  String _normalizedStockType(dynamic rawType) {
    final type = '${rawType ?? ''}'.trim().toLowerCase();
    if (type == 'fresh' || type == 'stok') return 'ready';
    return type;
  }

  Color _typeTone(String rawType) {
    switch (rawType.toLowerCase()) {
      case 'fresh':
      case 'stok':
        return t.success;
      case 'chip':
        return t.warning;
      case 'display':
        return t.info;
      default:
        return t.textMutedStrong;
    }
  }

  String _typeLabel(String rawType) {
    switch (rawType.toLowerCase()) {
      case 'fresh':
      case 'stok':
        return 'READY';
      case 'chip':
        return 'CHIP';
      case 'display':
        return 'DISPLAY';
      default:
        return rawType.toUpperCase();
    }
  }

  List<Map<String, dynamic>> _sortValidationItems(
    List<Map<String, dynamic>> rows,
  ) {
    final sorted = List<Map<String, dynamic>>.from(rows);
    sorted.sort((a, b) {
      final typeCompare = _sortByText(a['tipe_stok'], b['tipe_stok']);
      if (typeCompare != 0) return typeCompare;
      final srpCompare = _toInt(a['srp']).compareTo(_toInt(b['srp']));
      if (srpCompare != 0) return srpCompare;
      final modelCompare = _sortByText(a['model_name'], b['model_name']);
      if (modelCompare != 0) return modelCompare;
      final ramCompare = _sortByText(a['ram_rom'], b['ram_rom']);
      if (ramCompare != 0) return ramCompare;
      final colorCompare = _sortByText(a['color'], b['color']);
      if (colorCompare != 0) return colorCompare;
      return _sortByText(a['imei'], b['imei']);
    });
    return sorted;
  }

  List<Map<String, dynamic>> _filterValidationItems(
    List<Map<String, dynamic>> rows,
    String filter,
  ) {
    final sorted = _sortValidationItems(rows);
    if (filter == 'all') return sorted;
    return sorted
        .where((row) => _normalizedStockType(row['tipe_stok']) == filter)
        .toList();
  }

  Widget _buildFilterChip({
    required String value,
    required String label,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    final selected = value == selectedValue;
    return Expanded(
      child: InkWell(
        onTap: () => onSelected(value),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? t.info.withValues(alpha: 0.12) : t.surface1,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected ? t.info.withValues(alpha: 0.26) : t.divider,
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.bodySm(
                selected ? t.info : t.textMutedStrong,
                weight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCompactStockCell({
    required Map<String, dynamic> item,
    Widget? trailing,
    Color? accent,
  }) {
    final modelName = '${item['model_name'] ?? 'Produk'}'.trim();
    final ramRom = '${item['ram_rom'] ?? '-'}'.trim();
    final warna = '${item['color'] ?? '-'}'.trim();
    final title = [
      modelName,
      ramRom,
      warna,
    ].where((part) => part.isNotEmpty && part != '-').join(' • ');
    final tipe = _typeLabel('${item['tipe_stok'] ?? '-'}');
    final imei = '${item['imei'] ?? '-'}';
    final qty = '${item['qty'] ?? '1'}';
    final tone = accent ?? _typeTone('${item['tipe_stok'] ?? ''}');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: t.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title.isEmpty ? modelName : title,
                  style: AppTextStyle.bodyMd(
                    t.textPrimary,
                    weight: FontWeight.w800,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                tipe,
                style: AppTextStyle.bodySm(tone, weight: FontWeight.w900),
              ),
              const SizedBox(width: 8),
              Text(
                'Qty $qty',
                style: AppTextStyle.bodySm(
                  t.textMutedStrong,
                  weight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            imei,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: t.textMutedStrong,
              height: 1.15,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  List<Widget> _buildGroupedValidationList(
    List<Map<String, dynamic>> rows, {
    required Widget Function(Map<String, dynamic> item) rowBuilder,
  }) {
    final widgets = <Widget>[];
    String? lastType;
    for (var i = 0; i < rows.length; i++) {
      final item = rows[i];
      final currentType = '${item['tipe_stok'] ?? ''}'.trim();
      if (currentType != lastType) {
        if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
        widgets.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: _typeTone(currentType).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: _typeTone(currentType).withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                _typeLabel(currentType),
                style: AppTextStyle.bodySm(
                  _typeTone(currentType),
                  weight: FontWeight.w900,
                ),
              ),
            ),
          ),
        );
        lastType = currentType;
      }
      widgets.add(rowBuilder(item));
    }
    return widgets;
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
      _stockScopeStoreIds = await _loadStockScopeStoreIds('$storeId');

      // 2. Fetch Validated Items for Selected Date
      // Use date range for robustness
      final startOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      ).toIso8601String();
      final endOfDay = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
        23,
        59,
        59,
      ).toIso8601String();

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
                  srp,
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
        validatedItemsRaw = validatedItemsRaw.map((item) {
          final stok = _asMap(item['stok']);
          final variant = _asMap(stok['product_variants']);
          final product = _asMap(variant['products']);
          return {
            ...item,
            'model_name': '${product['model_name'] ?? 'Produk'}',
            'ram_rom': '${variant['ram_rom'] ?? '-'}',
            'color': '${variant['color'] ?? '-'}',
            'imei': '${stok['imei'] ?? item['imei'] ?? '-'}',
            'tipe_stok': '${item['validated_condition'] ?? '-'}',
            'srp': variant['srp'],
            'qty': 1,
          };
        }).toList();
        validatedStockIds = validatedItemsRaw
            .map((e) => e['stok_id'].toString())
            .toSet();
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
                srp,
                ram_rom,
                color,
                products!product_id(
                  model_name,
                  series
                )
              )
            ''')
            .inFilter(
              'store_id',
              _stockScopeStoreIds.isNotEmpty
                  ? _stockScopeStoreIds
                  : <String>['$storeId'],
            )
            .eq('is_sold', false);

        // Filter out items that are already validated TODAY
        pendingItemsRaw = List<Map<String, dynamic>>.from(stockData)
            .where((item) => !validatedStockIds.contains(item['id'].toString()))
            .map((item) {
              final variant = _asMap(item['product_variants']);
              final product = _asMap(variant['products']);
              return {
                ...item,
                'model_name': '${product['model_name'] ?? 'Produk'}',
                'ram_rom': '${variant['ram_rom'] ?? '-'}',
                'color': '${variant['color'] ?? '-'}',
                'tipe_stok': '${item['tipe_stok'] ?? '-'}',
                'srp': variant['srp'],
                'qty': 1,
              };
            })
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

  Future<List<String>> _loadStockScopeStoreIds(String storeId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final rpcResult = await Supabase.instance.client.rpc(
          'get_promotor_stock_scope',
          params: {'p_promotor_id': userId},
        );
        final rpcMap = rpcResult is Map<String, dynamic>
            ? rpcResult
            : Map<String, dynamic>.from(rpcResult as Map);
        final rpcScope = (rpcMap['stock_scope_store_ids'] as List? ?? const [])
            .map((item) => '${item ?? ''}'.trim())
            .where((id) => id.isNotEmpty)
            .toList();
        if (rpcScope.isNotEmpty) {
          return rpcScope;
        }
      } catch (_) {}
    }

    final storeRow = await Supabase.instance.client
        .from('stores')
        .select('group_id')
        .eq('id', storeId)
        .maybeSingle();
    final groupId = '${storeRow?['group_id'] ?? ''}'.trim();
    Map<String, dynamic> group = <String, dynamic>{};
    if (groupId.isNotEmpty) {
      final groupRow = await Supabase.instance.client
          .from('store_groups')
          .select('stock_handling_mode')
          .eq('id', groupId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (groupRow != null) {
        group = Map<String, dynamic>.from(groupRow);
      }
    }
    final groupMode = '${group['stock_handling_mode'] ?? ''}'.trim();
    if (groupId.isEmpty || groupMode != 'shared_group') {
      return <String>[storeId];
    }

    final storeRows = await Supabase.instance.client
        .from('stores')
        .select('id')
        .eq('group_id', groupId)
        .isFilter('deleted_at', null);
    final ids = List<Map<String, dynamic>>.from(storeRows)
        .map((row) => '${row['id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    return ids.isEmpty ? <String>[storeId] : ids;
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

      final validationDate = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        _selectedDate.day,
      );
      final rpcResult = await Supabase.instance.client.rpc(
        'submit_promotor_stock_validation',
        params: {
          'p_validation_date': DateFormat('yyyy-MM-dd').format(validationDate),
          'p_stock_ids': selectedEntries.map((entry) => entry.key).toList(),
        },
      );
      final payload = rpcResult is Map<String, dynamic>
          ? rpcResult
          : Map<String, dynamic>.from(rpcResult as Map);
      final insertedCount = (payload['inserted_count'] as num?)?.toInt() ?? 0;

      if (mounted) {
        await showSuccessDialog(
          context,
          title: 'Berhasil',
          message: '$insertedCount item divalidasi.',
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
            const Text(
              'Validasi Stok Harian',
              style: TextStyle(
                fontSize: AppTypeScale.title,
                fontWeight: FontWeight.bold,
              ),
            ),
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
              children: [_buildPendingTab(), _buildValidatedTab()],
            ),
    );
  }

  Widget _buildPendingTab() {
    final filteredPending = _filterValidationItems(
      _pendingItems,
      _pendingFilter,
    );
    if (!_isToday) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 64, color: t.textSecondary),
            const SizedBox(height: 16),
            Text(
              'Anda melihat data masa lalu.',
              style: AppTextStyle.bodyLg(
                t.textPrimary,
                weight: FontWeight.bold,
              ),
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
              style: AppTextStyle.bodyLg(
                t.textPrimary,
                weight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => context.push('/promotor/stock-input'),
              icon: Icon(Icons.add),
              label: const Text(
                'Ada barang fisik tapi tidak ada di list? Input Stok Manual',
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
              ),
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
                value:
                    _selectedPendingItems.length == _pendingItems.length &&
                    _pendingItems.isNotEmpty,
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
                onPressed: _selectedPendingItems.isEmpty
                    ? null
                    : _submitValidation,
                style: ElevatedButton.styleFrom(
                  backgroundColor: t.info,
                  foregroundColor: t.textOnAccent,
                ),
                child: Text('Validasi (${_selectedPendingItems.length})'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              _buildFilterChip(
                value: 'all',
                label: 'Semua ${_pendingItems.length}',
                selectedValue: _pendingFilter,
                onSelected: (value) => setState(() => _pendingFilter = value),
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                value: 'ready',
                label: 'Ready',
                selectedValue: _pendingFilter,
                onSelected: (value) => setState(() => _pendingFilter = value),
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                value: 'chip',
                label: 'Chip',
                selectedValue: _pendingFilter,
                onSelected: (value) => setState(() => _pendingFilter = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: _buildGroupedValidationList(
              filteredPending,
              rowBuilder: (item) {
                final id = item['id'].toString();
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
                    item: item,
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
        ),
      ],
    );
  }

  Widget _buildValidatedTab() {
    final filteredValidated = _filterValidationItems(
      _validatedItems,
      _validatedFilter,
    );
    if (_validatedItems.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.assignment_late_outlined,
              size: 64,
              color: t.textSecondary,
            ),
            const SizedBox(height: 16),
            Text(
              _isToday
                  ? 'Belum ada item divalidasi hari ini'
                  : 'Tidak ada data validasi pada tanggal ini',
              style: AppTextStyle.bodyMd(t.textSecondary),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              _buildFilterChip(
                value: 'all',
                label: 'Semua ${_validatedItems.length}',
                selectedValue: _validatedFilter,
                onSelected: (value) => setState(() => _validatedFilter = value),
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                value: 'ready',
                label: 'Ready',
                selectedValue: _validatedFilter,
                onSelected: (value) => setState(() => _validatedFilter = value),
              ),
              const SizedBox(width: 6),
              _buildFilterChip(
                value: 'chip',
                label: 'Chip',
                selectedValue: _validatedFilter,
                onSelected: (value) => setState(() => _validatedFilter = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            children: _buildGroupedValidationList(
              filteredValidated,
              rowBuilder: (item) => _buildCompactStockCell(
                item: item,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: t.successSoft,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: t.success.withValues(alpha: 0.25),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
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
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _getTime(String isoString) {
    if (isoString.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoString).toLocal();
      return '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }
}
