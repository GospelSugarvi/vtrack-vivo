import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';

class AdminMinStockPage extends StatefulWidget {
  const AdminMinStockPage({super.key});

  @override
  State<AdminMinStockPage> createState() => _AdminMinStockPageState();
}

class _AdminMinStockPageState extends State<AdminMinStockPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _stores = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _products = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final stores = await supabase
          .from('stores')
          .select('id, store_name, area, grade')
          .isFilter('deleted_at', null)
          .order('store_name');
      final products = await supabase
          .from('products')
          .select('id, model_name, series')
          .isFilter('deleted_at', null)
          .order('model_name');
      if (!mounted) return;
      setState(() {
        _stores = List<Map<String, dynamic>>.from(stores);
        _products = List<Map<String, dynamic>>.from(products);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Stok Minimal'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: ListTile(
                    title: const Text('Ringkasan'),
                    subtitle: Text(
                      '${_stores.length} toko terdaftar\n${_products.length} produk aktif',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Halaman stok minimal sedang distabilkan ulang.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Data utama sudah berhasil dimuat. Rule detail dan override akan disempurnakan setelah struktur error project selesai dibersihkan.',
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
