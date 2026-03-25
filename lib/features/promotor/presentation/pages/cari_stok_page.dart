import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CariStokPage extends StatefulWidget {
  const CariStokPage({super.key});

  @override
  State<CariStokPage> createState() => _CariStokPageState();
}

class _CariStokPageState extends State<CariStokPage>
    with SingleTickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  late TabController _tabController;
  bool _isLoading = false;
  bool _isLoadingMyStock = false;
  List<Map<String, dynamic>> _searchResults = [];
  List<Map<String, dynamic>> _myStockList = [];
  // Removed: _transferRequests - feature removed
  List<Map<String, dynamic>> _products = [];
  String? _selectedProductId;
  String? _selectedVariantId;
  String? _currentArea;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Get current user's store and area
      final userData = await Supabase.instance.client
          .from('users')
          .select('area')
          .eq('id', userId)
          .single();

      _currentArea = userData['area'];

      // _supervisorId is no longer needed here as DB handles it

      // Load products for search
      final productsData = await Supabase.instance.client
          .from('products')
          .select('''
            id,
            model_name,
            series,
            product_variants(
              id,
              ram_rom,
              color
            )
          ''')
          .order('model_name');

      // Removed: Load transfer requests - feature removed

      setState(() {
        _products = List<Map<String, dynamic>>.from(productsData);
        _isLoading = false;
      });

      // Load my stock
      if (mounted) {
        _loadMyStock();
      }
    } catch (e) {
      debugPrint('Error loading initial data: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: t.danger),
        );
      }
    }
  }

  Future<void> _loadMyStock() async {
    setState(() => _isLoadingMyStock = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoadingMyStock = false);
        return;
      }

      List<Map<String, dynamic>> results = [];
      try {
        final rpcResults = await Supabase.instance.client.rpc(
          'get_promotor_my_stock',
          params: {'p_promotor_id': userId},
        );
        results = List<Map<String, dynamic>>.from(rpcResults ?? []);
      } catch (rpcError) {
        debugPrint(
          'RPC get_promotor_my_stock failed, fallback to direct query: $rpcError',
        );
      }

      // Fallback: if RPC is unavailable or returns empty, query stock directly by assigned store.
      if (results.isEmpty) {
        results = await _loadMyStockFallback(userId);
      }

      setState(() {
        _myStockList = results;
        _isLoadingMyStock = false;
      });
    } catch (e) {
      debugPrint('Error loading my stock: $e');
      setState(() => _isLoadingMyStock = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: t.danger),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _loadMyStockFallback(String userId) async {
    final assignedStores = await Supabase.instance.client
        .from('assignments_promotor_store')
        .select('store_id')
        .eq('promotor_id', userId)
        .eq('active', true);

    final storeIds = List<Map<String, dynamic>>.from(assignedStores)
        .map((row) => row['store_id']?.toString())
        .whereType<String>()
        .toSet()
        .toList();

    const stockSelect = '''
      product_id,
      variant_id,
      imei,
      created_at,
      products!product_id(model_name, series),
      product_variants!variant_id(ram_rom, color)
    ''';

    dynamic stockRows;
    if (storeIds.isNotEmpty) {
      stockRows = await Supabase.instance.client
          .from('stok')
          .select(stockSelect)
          .inFilter('store_id', storeIds)
          .eq('is_sold', false)
          .order('created_at', ascending: false);
    } else {
      // Secondary fallback for legacy data/users not yet assigned in junction table.
      stockRows = await Supabase.instance.client
          .from('stok')
          .select(stockSelect)
          .eq('promotor_id', userId)
          .eq('is_sold', false)
          .order('created_at', ascending: false);
    }

    final grouped = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(stockRows)) {
      final productId = row['product_id']?.toString();
      final variantId = row['variant_id']?.toString();
      if (productId == null || variantId == null) continue;

      final key = '$productId|$variantId';
      final product = _asMap(row['products']);
      final variant = _asMap(row['product_variants']);

      final entry = grouped.putIfAbsent(key, () {
        return {
          'product_id': productId,
          'variant_id': variantId,
          'model_name': (product['model_name'] ?? '-').toString(),
          'series': (product['series'] ?? '').toString(),
          'ram_rom': (variant['ram_rom'] ?? '-').toString(),
          'color': (variant['color'] ?? '-').toString(),
          'total_stock': 0,
          'recent_imeis': <String>[],
        };
      });

      entry['total_stock'] = (entry['total_stock'] as int) + 1;
      final imei = row['imei']?.toString();
      final imeiPreview = entry['recent_imeis'] as List<String>;
      if (imei != null && imei.isNotEmpty && imeiPreview.length < 3) {
        imeiPreview.add(imei);
      }
    }

    final results = grouped.values.toList();
    results.sort((a, b) {
      final countCompare = (b['total_stock'] as int).compareTo(
        a['total_stock'] as int,
      );
      if (countCompare != 0) return countCompare;
      return (a['model_name'] as String).compareTo(b['model_name'] as String);
    });

    return results;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  // Removed: _loadTransferRequests() - feature removed

  Future<void> _searchStock() async {
    if (_selectedProductId == null || _selectedVariantId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih produk dan varian terlebih dahulu'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Search stock in stores handled by same SATOR (including current store)
      final results = await Supabase.instance.client.rpc(
        'search_stock_in_area',
        params: {
          'p_product_id': _selectedProductId,
          'p_variant_id': _selectedVariantId,
          'p_area': _currentArea,
        },
      );

      setState(() {
        _searchResults = List<Map<String, dynamic>>.from(results ?? []);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error searching stock: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: t.danger),
        );
      }
    }
  }

  String _getProductName(Map<String, dynamic> item) {
    if (item.containsKey('product_variants')) {
      final variant = item['product_variants'];
      final product = variant['products'];
      return '${product['model_name']} ${variant['ram_rom']} ${variant['color']}';
    }
    return '${item['model_name']} ${item['ram_rom']} ${item['color']}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cari Stok'),
        backgroundColor: t.infoSoft,
        bottom: TabBar(
          controller: _tabController,
          labelColor: t.info,
          unselectedLabelColor: t.textSecondary,
          indicatorColor: t.info,
          tabs: const [
            Tab(icon: Icon(Icons.search), text: 'Cari Stok'),
            Tab(icon: Icon(Icons.inventory_2), text: 'Stok Saya'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildSearchTab(), _buildMyStockTab()],
      ),
    );
  }

  Widget _buildSearchTab() {
    return Column(
      children: [
        // Search Form
        Container(
          padding: const EdgeInsets.all(16),
          color: t.background,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Cari stok di toko lain dalam tim SATOR Anda',
                style: TextStyle(fontSize: AppTypeScale.bodyStrong, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),

              // Product Dropdown
              DropdownButtonFormField<String>(
                initialValue: _selectedProductId,
                decoration: const InputDecoration(
                  labelText: 'Pilih Produk',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone_android),
                ),
                items: _products.map((product) {
                  return DropdownMenuItem<String>(
                    value: product['id'],
                    child: Text(
                      '${product['model_name']} (${product['series']})',
                    ),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedProductId = value;
                    _selectedVariantId = null; // Reset variant
                    _searchResults.clear();
                  });
                },
              ),

              const SizedBox(height: 12),

              // Variant Dropdown
              if (_selectedProductId != null)
                DropdownButtonFormField<String>(
                  initialValue: _selectedVariantId,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Varian',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.tune),
                  ),
                  items: _products
                      .firstWhere(
                        (p) => p['id'] == _selectedProductId,
                      )['product_variants']
                      .map<DropdownMenuItem<String>>((variant) {
                        return DropdownMenuItem<String>(
                          value: variant['id'],
                          child: Text(
                            '${variant['ram_rom']} - ${variant['color']}',
                          ),
                        );
                      })
                      .toList(),
                  onChanged: (value) {
                    setState(() {
                      _selectedVariantId = value;
                      _searchResults.clear();
                    });
                  },
                ),

              const SizedBox(height: 16),

              ElevatedButton.icon(
                onPressed: _isLoading ? null : _searchStock,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(Icons.search),
                label: const Text('Cari Stok'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ],
          ),
        ),

        // Search Results
        Expanded(
          child: _searchResults.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: t.surface4,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _selectedProductId == null
                            ? 'Pilih produk untuk mencari stok'
                            : 'Belum ada pencarian atau stok tidak ditemukan',
                        style: TextStyle(color: t.textSecondary),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _searchResults.length,
                  itemBuilder: (context, index) {
                    final item = _searchResults[index];
                    final isMyStore = item['is_my_store'] == true;

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: isMyStore
                            ? BorderSide(color: t.info, width: 2)
                            : BorderSide.none,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              item['store_name'],
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: AppTypeScale.bodyStrong,
                                              ),
                                            ),
                                          ),
                                          if (isMyStore)
                                            Container(
                                              margin: const EdgeInsets.only(
                                                left: 8,
                                              ),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                              decoration: BoxDecoration(
                                                color: t.infoSoft,
                                                borderRadius:
                                                    BorderRadius.circular(4),
                                                border: Border.all(
                                                  color: t.info,
                                                ),
                                              ),
                                              child: Text(
                                                'Toko Saya',
                                                style: TextStyle(
                                                  fontSize: AppTypeScale.support,
                                                  color: t.info,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        _getProductName(item),
                                        style: TextStyle(
                                          color: t.textSecondary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.successSoft,
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Text(
                                    '${item['total_stock']} unit',
                                    style: TextStyle(
                                      color: t.success,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            Row(
                              children: [
                                if (item['fresh_count'] > 0)
                                  _buildStockChip(
                                    'Fresh',
                                    item['fresh_count'],
                                    t.success,
                                  ),
                                if (item['chip_count'] > 0) ...[
                                  const SizedBox(width: 8),
                                  _buildStockChip(
                                    'Chip',
                                    item['chip_count'],
                                    t.warning,
                                  ),
                                ],
                                if (item['display_count'] > 0) ...[
                                  const SizedBox(width: 8),
                                  _buildStockChip(
                                    'Display',
                                    item['display_count'],
                                    t.info,
                                  ),
                                ],
                              ],
                            ),

                            const SizedBox(height: 12),

                            // Request Transfer button removed as per user request (Manual coordination via WA)
                            /*
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: () => _requestTransfer(item),
                                icon: Icon(Icons.swap_horiz),
                                label: const Text('Request Transfer'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: t.info,
                                  foregroundColor: t.textOnAccent,
                                ),
                              ),
                            ),
                            */
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Removed: _buildRequestsTab() - feature removed

  Widget _buildMyStockTab() {
    return RefreshIndicator(
      onRefresh: _loadMyStock,
      color: t.surface1,
      child: _isLoadingMyStock
          ? const Center(child: CircularProgressIndicator())
          : _myStockList.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.inventory_2_outlined,
                    size: 64,
                    color: t.surface4,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Belum ada stok yang tercatat',
                    style: TextStyle(color: t.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Stok yang Anda input akan muncul di sini',
                    style: TextStyle(color: t.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _myStockList.length,
              itemBuilder: (context, index) {
                final item = _myStockList[index];
                final totalStock = item['total_stock'] as int? ?? 0;
                final recentImeis = item['recent_imeis'] is List
                    ? List<String>.from(item['recent_imeis'])
                    : const <String>[];

                // Determine card color based on stock level
                Color stockColor;
                if (totalStock == 0) {
                  stockColor = t.danger;
                } else if (totalStock <= 3) {
                  stockColor = t.warning;
                } else {
                  stockColor = t.success;
                }

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${item['model_name']} ${item['series']}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTypeScale.bodyStrong,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item['ram_rom']} - ${item['color']}',
                                style: TextStyle(color: t.textSecondary),
                              ),
                              if (recentImeis.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'IMEI terbaru: ${recentImeis.join(', ')}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: t.textSecondary,
                                    fontSize: AppTypeScale.support,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: stockColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: stockColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.inventory_2_outlined,
                                color: stockColor,
                                size: 18,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$totalStock unit',
                                style: TextStyle(
                                  color: stockColor,
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTypeScale.bodyStrong,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  Widget _buildStockChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        '$label: $count',
        style: TextStyle(
          color: color,
          fontSize: AppTypeScale.support,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
