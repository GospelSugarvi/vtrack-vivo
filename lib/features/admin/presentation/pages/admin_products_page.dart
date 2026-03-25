import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

// Currency Input Formatter for Indonesian Rupiah (thousand separator with dot)
class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Remove all non-digit characters
    String digitsOnly = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digitsOnly.isEmpty) {
      return newValue.copyWith(text: '');
    }

    // Format with thousand separators (dots)
    String formatted = _formatWithDots(digitsOnly);

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  String _formatWithDots(String digitsOnly) {
    // Add dots as thousand separators
    String result = '';
    int count = 0;

    for (int i = digitsOnly.length - 1; i >= 0; i--) {
      if (count == 3) {
        result = '.$result';
        count = 0;
      }
      result = digitsOnly[i] + result;
      count++;
    }

    return result;
  }
}

// Upper case text formatter
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class AdminProductsPage extends StatefulWidget {
  const AdminProductsPage({super.key});

  @override
  State<AdminProductsPage> createState() => _AdminProductsPageState();
}

class _AdminProductsPageState extends State<AdminProductsPage> {
  List<Map<String, dynamic>> _products = [];
  Map<String, List<Map<String, dynamic>>> _productVariants =
      {}; // productId -> variants
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterSeries = 'all';

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  List<Map<String, dynamic>> get _filteredProducts {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _products;
    }
    return _products.where((product) {
      final name = '${product['model_name'] ?? ''}'.toLowerCase();
      final series = '${product['series'] ?? ''}'.toLowerCase();
      return name.contains(query) || series.contains(query);
    }).toList();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      var query = supabase
          .from('products')
          .select('*')
          .isFilter('deleted_at', null);

      if (_filterSeries != 'all') {
        query = query.eq('series', _filterSeries);
      }

      final productsResponse = await query.order('model_name');
      final products = List<Map<String, dynamic>>.from(productsResponse);

      // Load variants for each product
      Map<String, List<Map<String, dynamic>>> variantsMap = {};
      for (var product in products) {
        final variantsResponse = await supabase
            .from('product_variants')
            .select('*')
            .eq('product_id', product['id'])
            .isFilter('deleted_at', null)
            .order('srp');
        variantsMap[product['id']] = List<Map<String, dynamic>>.from(
          variantsResponse,
        );
      }

      if (mounted) {
        setState(() {
          _products = products;
          _productVariants = variantsMap;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddProductDialog,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Produk'),
      ),
      body: Column(
        children: [
          Container(
            padding: EdgeInsets.all(isDesktop ? 24 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDesktop)
                  Text(
                    'Produk Management',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                if (isDesktop) const SizedBox(height: 16),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Cari nama produk...',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _filterSeries,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('Semua Series'),
                        ),
                        DropdownMenuItem(
                          value: 'Y-Series',
                          child: Text('Y-Series'),
                        ),
                        DropdownMenuItem(
                          value: 'V-Series',
                          child: Text('V-Series'),
                        ),
                        DropdownMenuItem(
                          value: 'X-Series',
                          child: Text('X-Series'),
                        ),
                        DropdownMenuItem(value: 'iQOO', child: Text('iQOO')),
                      ],
                      onChanged: (value) {
                        setState(() => _filterSeries = value ?? 'all');
                        _loadProducts();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredProducts.isEmpty
                ? const Center(child: Text('Tidak ada produk'))
                : _buildProductList(),
          ),
        ],
      ),
    );
  }

  Widget _buildProductList() {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _filteredProducts.length,
      itemBuilder: (context, index) {
        final product = _filteredProducts[index];
        final variants = _productVariants[product['id']] ?? [];

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ExpansionTile(
            leading: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _getSeriesColor(
                  product['series'],
                ).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.phone_android,
                color: _getSeriesColor(product['series']),
              ),
            ),
            title: Row(
              children: [
                Text(
                  product['model_name'] ?? 'Unknown',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(width: 8),
                _buildSeriesBadge(product['series']),
                const SizedBox(width: 4),
                _buildNetworkBadge(product['network_type']),
              ],
            ),
            subtitle: Text('${variants.length} varian'),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'edit', child: Text('Edit Produk')),
                const PopupMenuItem(
                  value: 'addVariant',
                  child: Text('Tambah Varian'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Hapus Produk'),
                ),
              ],
              onSelected: (value) {
                if (value == 'edit') _showEditProductDialog(product);
                if (value == 'addVariant') _showVariantsDialog(product);
                if (value == 'delete') _confirmDelete(product);
              },
            ),
            children: [
              if (variants.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Belum ada varian. Klik "Tambah Varian" untuk menambah.',
                    style: TextStyle(
                      fontStyle: FontStyle.italic,
                      color: AppColors.textSecondary,
                    ),
                  ),
                )
              else
                ...variants.map(
                  (variant) => _buildVariantListItem(variant, product),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVariantListItem(
    Map<String, dynamic> variant,
    Map<String, dynamic> product,
  ) {
    final ram =
        variant['ram'] ?? variant['ram_rom']?.split('/').firstOrNull ?? '-';
    final storage =
        variant['storage'] ?? variant['ram_rom']?.split('/').lastOrNull ?? '-';
    final modal = variant['modal'] ?? 0;
    final srp = variant['srp'] ?? 0;

    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 4),
        title: Row(
          children: [
            Text(
              'RAM $ram GB / $storage GB',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                variant['color'] ?? '-',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          'Modal: Rp ${_formatCurrency(modal)} | SRP: Rp ${_formatCurrency(srp)}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: AppColors.info, size: 20),
              tooltip: 'Edit Varian',
              onPressed: () => _editVariantInline(variant, product),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: AppColors.danger, size: 20),
              tooltip: 'Hapus Varian',
              onPressed: () => _confirmDeleteVariant(variant),
            ),
          ],
        ),
      ),
    );
  }

  void _editVariantInline(
    Map<String, dynamic> variant,
    Map<String, dynamic> product,
  ) {
    // Show dialog to edit this variant
    _showVariantsDialog(product);
    // TODO: Could pre-populate form with this variant's data
  }

  Future<void> _confirmDeleteVariant(Map<String, dynamic> variant) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Varian'),
        content: const Text('Yakin ingin menghapus varian ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await supabase
            .from('product_variants')
            .update({
              'active': false,
              'deleted_at': DateTime.now().toIso8601String(),
            })
            .eq('id', variant['id']);
        await _loadProducts();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Varian berhasil dihapus'),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        showErrorDialog(
          context,
          title: 'Gagal hapus varian',
          message: 'Error: $e',
        );
      }
    }
  }

  String _formatCurrency(dynamic value) {
    final numValue = value is int ? value : int.tryParse(value.toString()) ?? 0;
    return numValue.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match.group(1)}.',
    );
  }

  Widget _buildSeriesBadge(String? series) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _getSeriesColor(series).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        series ?? 'N/A',
        style: TextStyle(
          fontSize: 13,
          color: _getSeriesColor(series),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildNetworkBadge(String? networkType) {
    final is5G = networkType == '5G';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: is5G
            ? Colors.purple.withValues(alpha: 0.2)
            : Colors.grey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        networkType ?? '4G',
        style: TextStyle(
          fontSize: 12,
          color: is5G ? Colors.purple : AppColors.textSecondary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getSeriesColor(String? series) {
    switch (series) {
      case 'Y-Series':
        return AppColors.info;
      case 'V-Series':
        return AppColors.success;
      case 'X-Series':
        return Colors.purple;
      case 'iQOO':
        return AppColors.warning;
      default:
        return AppColors.textSecondary;
    }
  }

  void _showAddProductDialog() {
    _showProductFormDialog(null);
  }

  void _showEditProductDialog(Map<String, dynamic> product) {
    _showProductFormDialog(product);
  }

  void _showProductFormDialog(Map<String, dynamic>? product) {
    final isEdit = product != null;
    final nameController = TextEditingController(
      text: product?['model_name'] ?? '',
    );
    String selectedSeries = product?['series'] ?? 'Y-Series';
    String networkType = product?['network_type'] ?? '4G';
    String bonusType = product?['bonus_type'] ?? 'range';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Edit Produk' : 'Tambah Produk'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nama Model (e.g. Y400)',
                  ),
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [UpperCaseTextFormatter()],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedSeries,
                  decoration: const InputDecoration(labelText: 'Series'),
                  items: ['Y-Series', 'V-Series', 'X-Series', 'iQOO']
                      .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                      .toList(),
                  onChanged: (v) => selectedSeries = v ?? 'Y-Series',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: networkType,
                  decoration: const InputDecoration(labelText: 'Network'),
                  items: const [
                    DropdownMenuItem(value: '4G', child: Text('4G')),
                    DropdownMenuItem(value: '5G', child: Text('5G')),
                  ],
                  onChanged: (v) => networkType = v ?? '4G',
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: bonusType,
                  decoration: const InputDecoration(labelText: 'Tipe Bonus'),
                  items: const [
                    DropdownMenuItem(
                      value: 'range',
                      child: Text('Range-Based'),
                    ),
                    DropdownMenuItem(value: 'flat', child: Text('Flat Bonus')),
                    DropdownMenuItem(
                      value: 'ratio',
                      child: Text('Ratio (2:1)'),
                    ),
                  ],
                  onChanged: (v) => bonusType = v ?? 'range',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                final data = {
                  'model_name': nameController.text.trim(),
                  'series': selectedSeries,
                  'network_type': networkType,
                  'is_npo': false,
                  'bonus_type': bonusType,
                  'status': 'active',
                };

                if (isEdit) {
                  await supabase
                      .from('products')
                      .update(data)
                      .eq('id', product['id']);
                } else {
                  await supabase.from('products').insert(data);
                }

                if (!context.mounted) return;
                Navigator.pop(context);
                _loadProducts();
              },
              child: Text(isEdit ? 'Simpan' : 'Tambah'),
            ),
          ],
        ),
      ),
    );
  }

  void _showVariantsDialog(Map<String, dynamic> product) {
    showDialog(
      context: context,
      builder: (context) => _VariantsDialog(product: product),
    );
  }

  void _confirmDelete(Map<String, dynamic> product) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Produk'),
        content: Text('Yakin ingin menghapus ${product['model_name']}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await supabase
          .from('products')
          .update({'deleted_at': DateTime.now().toIso8601String()})
          .eq('id', product['id']);
      _loadProducts();
    }
  }
}

class _VariantsDialog extends StatefulWidget {
  final Map<String, dynamic> product;

  const _VariantsDialog({required this.product});

  @override
  State<_VariantsDialog> createState() => _VariantsDialogState();
}

class _VariantsDialogState extends State<_VariantsDialog> {
  List<Map<String, dynamic>> _variants = [];
  bool _isLoading = true;

  // Controllers
  final _ramController = TextEditingController();
  final _storageController = TextEditingController();
  final _colorInputController = TextEditingController(); // For typing color
  final _modalController = TextEditingController();
  final _srpController = TextEditingController();

  // List of colors (chips)
  List<String> _selectedColors = [];

  @override
  void initState() {
    super.initState();
    _loadVariants();
  }

  Future<void> _loadVariants() async {
    setState(() => _isLoading = true);
    final response = await supabase
        .from('product_variants')
        .select('*')
        .eq('product_id', widget.product['id'])
        .isFilter('deleted_at', null)
        .order('srp');

    if (mounted) {
      setState(() {
        _variants = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    }
  }

  void _addColor() {
    final color = _colorInputController.text.trim().toUpperCase();
    if (color.isNotEmpty && !_selectedColors.contains(color)) {
      setState(() {
        _selectedColors.add(color);
        _colorInputController.clear();
      });
    }
  }

  void _removeColor(String color) {
    setState(() {
      _selectedColors.remove(color);
    });
  }

  Future<void> _addVariant() async {
    if (_ramController.text.isEmpty ||
        _storageController.text.isEmpty ||
        _selectedColors.isEmpty ||
        _modalController.text.isEmpty ||
        _srpController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Semua field wajib diisi, minimal 1 warna'),
        ),
      );
      return;
    }

    try {
      // Create one variant for EACH color
      final modal =
          int.tryParse(
            _modalController.text.replaceAll(RegExp(r'[^0-9]'), ''),
          ) ??
          0;
      final srp =
          int.tryParse(_srpController.text.replaceAll(RegExp(r'[^0-9]'), '')) ??
          0;
      final ram = _ramController.text.trim();
      final storage = _storageController.text.trim();

      List<Map<String, dynamic>> variantsToInsert = [];

      for (String color in _selectedColors) {
        variantsToInsert.add({
          'product_id': widget.product['id'],
          'ram': ram,
          'storage': storage,
          'ram_rom': '$ram/$storage',
          'color': color,
          'modal': modal,
          'srp': srp,
        });
      }

      await supabase.from('product_variants').insert(variantsToInsert);

      _clearForm();
      _loadVariants();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Berhasil menambahkan ${variantsToInsert.length} varian',
            ),
            backgroundColor: AppTheme.successGreen,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.errorRed,
          ),
        );
      }
    }
  }

  void _clearForm() {
    _ramController.clear();
    _storageController.clear();
    _colorInputController.clear();
    _modalController.clear();
    _srpController.clear();
    setState(() {
      _selectedColors.clear();
    });
  }

  void _editVariant(Map<String, dynamic> variant) {
    // Populate form with variant data
    _ramController.text = variant['ram']?.toString() ?? '';
    _storageController.text = variant['storage']?.toString() ?? '';
    _colorInputController.clear();
    setState(() {
      _selectedColors = [variant['color']?.toString() ?? ''];
    });

    // Format price for display
    final modal = variant['modal'];
    final srp = variant['srp'];
    _modalController.text = modal != null ? _formatCurrency(modal) : '';
    _srpController.text = srp != null ? _formatCurrency(srp) : '';

    // Delete the old variant after editing
    _deleteVariant(variant['id']);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Data varian dimuat ke form. Edit dan klik Tambah Varian untuk menyimpan.',
        ),
      ),
    );
  }

  String _formatCurrency(dynamic value) {
    final numValue = value is int ? value : int.tryParse(value.toString()) ?? 0;
    return numValue.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (match) => '${match.group(1)}.',
    );
  }

  Future<void> _deleteVariant(String id) async {
    try {
      await supabase
          .from('product_variants')
          .update({
            'active': false,
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id);
      await _loadVariants();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Varian berhasil dihapus'),
          backgroundColor: AppTheme.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal hapus varian: $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('KELOLA VARIAN: ${widget.product['model_name']}'),
      content: SizedBox(
        width: 650,
        height: 700,
        child: Column(
          children: [
            // Form Add Varian
            Card(
              elevation: 0,
              color: AppColors.textSecondary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: AppColors.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Tambah Varian Baru',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _ramController,
                            decoration: const InputDecoration(
                              labelText: 'RAM (GB)',
                              hintText: 'e.g. 8',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _storageController,
                            decoration: const InputDecoration(
                              labelText: 'Internal (GB)',
                              hintText: 'e.g. 128',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Color chips area
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Warna (HURUF BESAR)',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Display chips with scroll
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxHeight: 100,
                                ), // Limit height
                                child: SingleChildScrollView(
                                  child: _selectedColors.isNotEmpty
                                      ? Wrap(
                                          spacing: 6,
                                          runSpacing: 6,
                                          children: _selectedColors.map((
                                            color,
                                          ) {
                                            return Chip(
                                              label: Text(
                                                color,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              backgroundColor: Colors.black,
                                              labelStyle: const TextStyle(
                                                color: Colors.white,
                                              ),
                                              deleteIcon: const Icon(
                                                Icons.close,
                                                size: 16,
                                                color: Colors.white,
                                              ),
                                              onDeleted: () =>
                                                  _removeColor(color),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2,
                                                  ),
                                            );
                                          }).toList(),
                                        )
                                      : const Text(
                                          'Belum ada warna ditambahkan',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: AppColors.textSecondary,
                                            fontStyle: FontStyle.italic,
                                          ),
                                        ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Input field for new color
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _colorInputController,
                                      decoration: const InputDecoration(
                                        hintText: 'Ketik warna (misal: HITAM)',
                                        isDense: true,
                                        border: OutlineInputBorder(),
                                        contentPadding: EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 8,
                                        ),
                                      ),
                                      textCapitalization:
                                          TextCapitalization.characters,
                                      onSubmitted: (_) => _addColor(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _addColor,
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text(
                                      'Tambah',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    style: ElevatedButton.styleFrom(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      minimumSize: const Size(0, 36),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _modalController,
                            decoration: const InputDecoration(
                              labelText: 'Harga Modal',
                              prefixText: 'Rp ',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [CurrencyInputFormatter()],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _srpController,
                            decoration: const InputDecoration(
                              labelText: 'Harga SRP',
                              prefixText: 'Rp ',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [CurrencyInputFormatter()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _addVariant,
                        icon: const Icon(Icons.add),
                        label: const Text('Tambah Varian'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryBlue,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(),

            // List Varian
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _variants.isEmpty
                  ? const Center(child: Text('Belum ada varian tersimpan'))
                  : ListView.separated(
                      itemCount: _variants.length,
                      separatorBuilder: (ctx, i) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final variant = _variants[index];
                        final ram =
                            variant['ram'] ??
                            variant['ram_rom']?.split('/').firstOrNull ??
                            '-';
                        final storage =
                            variant['storage'] ??
                            variant['ram_rom']?.split('/').lastOrNull ??
                            '-';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                          ),
                          title: Row(
                            children: [
                              Text(
                                'RAM $ram GB / $storage GB',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  variant['color'] ?? '-',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(
                            'Modal: Rp ${_formatCurrency(variant['modal'] ?? 0)} | SRP: Rp ${_formatCurrency(variant['srp'] ?? 0)}',
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(
                                  Icons.edit,
                                  color: AppColors.info,
                                  size: 20,
                                ),
                                tooltip: 'Edit Varian',
                                onPressed: () => _editVariant(variant),
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.delete,
                                  color: AppColors.textSecondary,
                                  size: 20,
                                ),
                                tooltip: 'Hapus Varian',
                                onPressed: () => _deleteVariant(variant['id']),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Selesai'),
        ),
      ],
    );
  }
}
