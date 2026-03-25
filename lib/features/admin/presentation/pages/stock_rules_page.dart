import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../ui/foundation/app_colors.dart';

class StockRulesPage extends StatefulWidget {
  const StockRulesPage({super.key});

  @override
  State<StockRulesPage> createState() => _StockRulesPageState();
}

class _StockRulesPageState extends State<StockRulesPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  // Data
  List<Map<String, dynamic>> _products = [];
  String _selectedGrade = 'A'; // Start with A tab

  // Controllers Map to track changes: ProductID -> min Ctrl
  final Map<String, TextEditingController> _minControllers = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadRules('A');
  }

  void _handleTabSelection() {
    if (_tabController.indexIsChanging) {
      final grades = ['A', 'B', 'C'];
      _loadRules(grades[_tabController.index]);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    for (var c in _minControllers.values) {
      c.dispose();
    }
    _minControllers.clear();
  }

  Future<void> _loadRules(String grade) async {
    setState(() {
      _isLoading = true;
      _selectedGrade = grade;
    });

    try {
      // Clear old controllers
      _disposeControllers();

      final data = await _supabase.rpc(
        'get_products_with_rules',
        params: {'p_grade': grade},
      );

      final List<Map<String, dynamic>> products =
          List<Map<String, dynamic>>.from(data);

      // Init controllers
      for (var p in products) {
        final id = p['product_id'].toString();
        _minControllers[id] = TextEditingController(
          text: p['min_qty'].toString(),
        );
      }

      setState(() {
        _products = products;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading rules: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveAll() async {
    setState(() => _isLoading = true);

    int successCount = 0;
    int errorCount = 0;
    String lastError = '';

    for (var p in _products) {
      final id = p['product_id'].toString();
      final minVal = int.tryParse(_minControllers[id]?.text ?? '0') ?? 0;

      try {
        await _supabase.rpc(
          'update_stock_rule',
          params: {
            'p_grade': _selectedGrade,
            'p_product_id': id,
            'p_min': minVal,
          },
        );
        successCount++;
      } catch (e) {
        errorCount++;
        lastError = e.toString();
        debugPrint('Error saving product $id: $e');
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);

      if (errorCount == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Berhasil menyimpan $successCount produk!'),
            backgroundColor: AppColors.success,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Error: $lastError\nBerhasil: $successCount, Gagal: $errorCount',
            ),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 15),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aturan Stok Toko'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Grade A'),
            Tab(text: 'Grade B'),
            Tab(text: 'Grade C'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _saveAll,
            icon: const Icon(Icons.save),
            tooltip: 'Simpan Semua',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  color: AppColors.infoSurface,
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: const [
                      Icon(Icons.info_outline, color: AppColors.info),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Input Stok Minimal per Model. Jika stok toko kurang dari ini, akan muncul rekomendasi order.',
                          style: TextStyle(fontSize: 12, color: Colors.indigo),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: _products.length,
                    separatorBuilder: (ctx, i) => const Divider(),
                    itemBuilder: (context, index) {
                      final item = _products[index];
                      final id = item['product_id'].toString();

                      return Row(
                        children: [
                          // Product Info
                          Expanded(
                            flex: 4,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item['model_name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    if (item['series'] != null)
                                      _buildBadge(item['series'], AppColors.textSecondary),
                                    if (item['network_type'] != null &&
                                        item['network_type'] == '5G')
                                      _buildBadge('5G', Colors.purple),
                                    if (item['ram_rom_info'] != null)
                                      _buildBadge(
                                        item['ram_rom_info'],
                                        Colors.blueGrey,
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 16),

                          // Min Qty Input
                          Expanded(
                            flex: 2,
                            child: Tooltip(
                              message:
                                  'Total Minimum untuk 1 Model (Semua Warna)',
                              child: TextField(
                                controller: _minControllers[id],
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                decoration: InputDecoration(
                                  labelText: 'Min (Total)',
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 0,
                                  ),
                                  fillColor: Colors.orange.shade50,
                                  filled: true,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _saveAll,
        backgroundColor: AppColors.info,
        child: const Icon(Icons.save),
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
