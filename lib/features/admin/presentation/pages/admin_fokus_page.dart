import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

class AdminFokusPage extends StatefulWidget {
  const AdminFokusPage({super.key});

  @override
  State<AdminFokusPage> createState() => _AdminFokusPageState();
}

class _AdminFokusPageState extends State<AdminFokusPage> {
  final int _currentYear = DateTime.now().year;
  final int _currentMonth = DateTime.now().month;

  final List<String> _monthNames = const [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember'
  ];

  bool _isLoading = true;
  int _selectedMonth = DateTime.now().month;
  String? _selectedPeriodId;

  final Map<int, String> _periodIds = {};
  List<Map<String, dynamic>> _products = [];
  final Set<String> _fokusProductIds = {};
  List<Map<String, dynamic>> _specialBundles = [];

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  Future<void> _loadInitial() async {
    setState(() => _isLoading = true);
    try {
      await _loadProducts();
      await _loadPeriods();
      _syncSelectedPeriodByMonth();
      await _ensureSelectedPeriod();
      await _loadFokusProducts();
      await _loadSpecialBundles();
    } catch (e) {
      if (mounted) {
        showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadProducts() async {
    final response = await supabase
        .from('products')
        .select('*')
        .isFilter('deleted_at', null)
        .order('model_name');
    _products = List<Map<String, dynamic>>.from(response);
  }

  Future<void> _loadPeriods() async {
    final response = await supabase
        .from('target_periods')
        .select('id, target_month, target_year')
        .isFilter('deleted_at', null)
        .order('start_date', ascending: false);
    for (var r in response) {
      final month = r['target_month'];
      final periodId = r['id']?.toString() ?? '';
      if (month is int && periodId.isNotEmpty) {
        _periodIds[month] = periodId;
      }
    }
  }

  Future<void> _ensureSelectedPeriod() async {
    if (_selectedPeriodId == null && _periodIds.isNotEmpty) {
      _selectedPeriodId = _periodIds[_selectedMonth] ?? _periodIds.values.first;
    }
  }

  void _syncSelectedPeriodByMonth() {
    final periodId = _periodIds[_selectedMonth];
    if (periodId != null && periodId.isNotEmpty) {
      _selectedPeriodId = periodId;
    }
  }

  Future<void> _loadFokusProducts() async {
    if (_selectedPeriodId == null) return;
    final response = await supabase
        .from('fokus_products')
        .select('product_id')
        .eq('period_id', _selectedPeriodId!);
    _fokusProductIds.clear();
    for (var r in response) {
      _fokusProductIds.add(r['product_id'].toString());
    }
  }

  Future<void> _loadSpecialBundles() async {
    if (_selectedPeriodId == null) return;
    final response = await supabase
        .from('special_focus_bundles')
        .select(
          'id, bundle_name, special_focus_bundle_products(product_id, products(model_name, series))',
        )
        .eq('period_id', _selectedPeriodId!)
        .order('bundle_name');

    _specialBundles = List<Map<String, dynamic>>.from(response);
  }

  Future<bool> _isSpecialBundleReferenced(String bundleId) async {
    if (_selectedPeriodId == null) return false;
    final rows = await supabase
        .from('user_targets')
        .select('target_special_detail')
        .eq('period_id', _selectedPeriodId!);

    for (final raw in rows) {
      final row = Map<String, dynamic>.from(raw);
      final detailRaw = row['target_special_detail'];
      final detail = detailRaw is Map<String, dynamic>
          ? detailRaw
          : (detailRaw is Map ? Map<String, dynamic>.from(detailRaw) : const <String, dynamic>{});
      if (detail.containsKey(bundleId)) {
        return true;
      }
    }

    return false;
  }

  Future<void> _toggleFokus(String productId, bool value) async {
    if (_selectedPeriodId == null) return;
    try {
      if (value) {
        await supabase.from('fokus_products').upsert({
          'period_id': _selectedPeriodId,
          'product_id': productId,
        }, onConflict: 'period_id,product_id');
        _fokusProductIds.add(productId);
      } else {
        await supabase
            .from('fokus_products')
            .delete()
            .eq('period_id', _selectedPeriodId!)
            .eq('product_id', productId);
        _fokusProductIds.remove(productId);
      }
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
        );
      }
    }
  }

  List<Map<String, dynamic>> _currentFokusProducts() {
    return _products
        .where((p) => _fokusProductIds.contains(p['id']?.toString() ?? ''))
        .toList();
  }

  Future<void> _showBundleDialog({Map<String, dynamic>? bundle}) async {
    if (_selectedPeriodId == null) return;
    final fokusProducts = _currentFokusProducts();
    if (fokusProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Set produk fokus dulu sebelum membuat bundle')),
      );
      return;
    }

    final nameController = TextEditingController(text: bundle?['bundle_name'] ?? '');
    final selected = <String>{};

    if (bundle != null) {
      final items = List<Map<String, dynamic>>.from(
        bundle['special_focus_bundle_products'] ?? [],
      );
      for (final item in items) {
        final id = item['product_id']?.toString();
        if (id != null) selected.add(id);
      }
    }

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(bundle == null ? 'Tambah Bundle Tipe Khusus' : 'Edit Bundle Tipe Khusus'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nama Bundle (Series)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                const SizedBox(height: 12),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Pilih tipe produk (harus produk fokus bulan ini):',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 240,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.border),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView(
                    children: fokusProducts.map((product) {
                      final id = product['id']?.toString() ?? '';
                      final name = product['model_name'] ?? '';
                      return CheckboxListTile(
                        value: selected.contains(id),
                        title: Text(name),
                        dense: true,
                        onChanged: (val) {
                          setDialogState(() {
                            if (val == true) {
                              selected.add(id);
                            } else {
                              selected.remove(id);
                            }
                            if (nameController.text.trim().isEmpty) {
                              final names = fokusProducts
                                  .where((p) => selected.contains(p['id']?.toString() ?? ''))
                                  .map((p) => p['model_name']?.toString() ?? '')
                                  .where((v) => v.isNotEmpty)
                                  .toList();
                              nameController.text = names.join('/');
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 8),
                Text('${selected.length} tipe dipilih', style: const TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
            ElevatedButton(
              onPressed: selected.isEmpty ? null : () => Navigator.pop(context, true),
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;

    try {
      final bundleName = nameController.text.trim().isEmpty
          ? fokusProducts
              .where((p) => selected.contains(p['id']?.toString() ?? ''))
              .map((p) => p['model_name']?.toString() ?? '')
              .where((v) => v.isNotEmpty)
              .join('/')
          : nameController.text.trim();
      String bundleId;

      if (bundle == null) {
        final inserted = await supabase.from('special_focus_bundles').insert({
          'period_id': _selectedPeriodId,
          'bundle_name': bundleName,
        }).select('id').single();
        bundleId = inserted['id'] as String;
      } else {
        bundleId = bundle['id'] as String;
        await supabase.from('special_focus_bundles').update({
          'bundle_name': bundleName,
        }).eq('id', bundleId);

        await supabase
            .from('special_focus_bundle_products')
            .delete()
            .eq('bundle_id', bundleId);
      }

      final inserts = selected
          .map((productId) => {
                'bundle_id': bundleId,
                'product_id': productId,
              })
          .toList();
      await supabase.from('special_focus_bundle_products').insert(inserts);

      await _loadSpecialBundles();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
        );
      }
    }
  }

  Future<void> _deleteBundle(Map<String, dynamic> bundle) async {
    final bundleId = '${bundle['id'] ?? ''}';
    if (bundleId.isEmpty) return;

    final isReferenced = await _isSpecialBundleReferenced(bundleId);
    if (isReferenced) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Tidak Bisa Dihapus',
          message:
              'Bundle ini sudah dipakai di target bulan aktif. Edit bundle yang ada, jangan hapus lalu buat ulang, supaya ID dan target tetap konsisten.',
        );
      }
      return;
    }

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Bundle?'),
        content: Text('Bundle "${bundle['bundle_name']}" akan dihapus.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await supabase.from('special_focus_bundles').delete().eq('id', bundleId);
      await _loadSpecialBundles();
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  padding: EdgeInsets.all(isDesktop ? 24 : 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (isDesktop)
                        Text('Produk Fokus Bulanan',
                            style: Theme.of(context).textTheme.headlineMedium),
                      if (isDesktop) const SizedBox(height: 8),
                      const Text(
                        'Pilih produk fokus per bulan dan buat bundle tipe khusus (gabungan tipe).',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              initialValue: _selectedMonth,
                              decoration: const InputDecoration(
                                labelText: 'Bulan',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                              items: List.generate(12, (index) {
                                final month = index + 1;
                                return DropdownMenuItem(
                                  value: month,
                                  child: Text(_monthNames[index]),
                                );
                              }),
                              onChanged: (value) async {
                                if (value == null) return;
                                setState(() {
                                  _selectedMonth = value;
                                  _syncSelectedPeriodByMonth();
                                });
                                setState(() => _isLoading = true);
                                try {
                                  await _ensureSelectedPeriod();
                                  await _loadFokusProducts();
                                  await _loadSpecialBundles();
                                } finally {
                                  if (mounted) setState(() => _isLoading = false);
                                }
                              },
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              initialValue: _currentYear.toString(),
                              enabled: false,
                              decoration: const InputDecoration(
                                labelText: 'Tahun',
                                border: OutlineInputBorder(),
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          Chip(label: Text('Fokus: ${_fokusProductIds.length}')),
                          Chip(label: Text('Bundle Khusus: ${_specialBundles.length}')),
                          if (_selectedMonth == _currentMonth)
                            const Chip(
                              label: Text('Bulan Ini'),
                              backgroundColor: AppColors.info,
                              labelStyle: TextStyle(color: Colors.white),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: DefaultTabController(
                    length: 2,
                    child: Column(
                      children: [
                        const TabBar(
                          tabs: [
                            Tab(text: 'Produk Fokus'),
                            Tab(text: 'Tipe Khusus'),
                          ],
                        ),
                        Expanded(
                          child: TabBarView(
                            children: [
                              _buildFokusProductsList(isDesktop),
                              _buildSpecialBundlesList(isDesktop),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFokusProductsList(bool isDesktop) {
    return _products.isEmpty
        ? const Center(child: Text('Belum ada produk aktif'))
        : ListView.builder(
            padding: EdgeInsets.all(isDesktop ? 24 : 16),
            itemCount: _products.length,
            itemBuilder: (context, index) {
              final product = _products[index];
              final productId = product['id']?.toString() ?? '';
              final modelName = product['model_name'] ?? '';
              final series = product['series'] ?? '';
              final isFokus = _fokusProductIds.contains(productId);

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isFokus,
                        onChanged: (val) => _toggleFokus(productId, val == true),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              modelName,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            if (series.toString().isNotEmpty)
                              Text(series,
                                  style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
  }

  Widget _buildSpecialBundlesList(bool isDesktop) {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(isDesktop ? 24 : 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Bundle Tipe Khusus (gabungan tipe untuk 1 target)',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showBundleDialog(),
                icon: const Icon(Icons.add),
                label: const Text('Buat Bundle'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: _specialBundles.isEmpty
              ? const Center(child: Text('Belum ada bundle tipe khusus'))
              : ListView.builder(
                  padding: EdgeInsets.all(isDesktop ? 24 : 16),
                  itemCount: _specialBundles.length,
                  itemBuilder: (context, index) {
                    final bundle = _specialBundles[index];
                    final items = List<Map<String, dynamic>>.from(
                      bundle['special_focus_bundle_products'] ?? [],
                    );
                    final names = items
                        .map((e) => e['products']?['model_name'])
                        .whereType<String>()
                        .toList();

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.folder, color: AppColors.warning),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    bundle['bundle_name'] ?? 'Bundle',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit, color: AppColors.info),
                                  onPressed: () => _showBundleDialog(bundle: bundle),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: AppColors.danger),
                                  onPressed: () => _deleteBundle(bundle),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 4,
                              children: names
                                  .map((name) => Chip(
                                        label: Text(name, style: const TextStyle(fontSize: 12)),
                                        backgroundColor: Colors.orange.withValues(alpha: 0.1),
                                        padding: EdgeInsets.zero,
                                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      ))
                                  .toList(),
                            ),
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
}
