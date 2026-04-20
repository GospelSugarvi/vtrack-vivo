import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';
import '../widgets/admin_dialog_sync.dart';

class AdminStockPage extends StatefulWidget {
  const AdminStockPage({super.key});

  @override
  State<AdminStockPage> createState() => _AdminStockPageState();
}

class _AdminStockPageState extends State<AdminStockPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data
  List<Map<String, dynamic>> _stores = [];
  List<Map<String, dynamic>> _stockSummary = [];
  List<Map<String, dynamic>> _stockDetail = [];
  List<Map<String, dynamic>> _transfers = [];
  List<Map<String, dynamic>> _products = [];
  List<Map<String, dynamic>> _variants = [];

  bool _isLoading = true;
  String? _selectedStoreId;
  String _searchImei = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      // Load stores
      final stores = await supabase
          .from('stores')
          .select('id, store_name, area')
          .isFilter('deleted_at', null)
          .order('store_name');
      _stores = List<Map<String, dynamic>>.from(stores);

      // Load products for dropdown
      final products = await supabase
          .from('products')
          .select('id, model_name, network_type')
          .isFilter('deleted_at', null);
      _products = List<Map<String, dynamic>>.from(products);

      // Load stock summary (aggregate by store)
      await _loadStockSummary();

      // Load pending transfers
      await _loadTransfers();

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading stock data: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadStockSummary() async {
    final summary = await supabase.rpc('get_stock_summary_by_store');
    _stockSummary = List<Map<String, dynamic>>.from(summary ?? []);
  }

  Future<void> _loadStockDetail() async {
    if (_selectedStoreId == null) return;

    dynamic query = supabase
        .from('stok')
        .select('*, products(model_name), product_variants(ram_rom, color)')
        .eq('store_id', _selectedStoreId!)
        .eq('is_sold', false);

    if (_searchImei.isNotEmpty) {
      query = query.ilike('imei', '%$_searchImei%');
    }

    final detail = await query.order('created_at', ascending: false);
    setState(() => _stockDetail = List<Map<String, dynamic>>.from(detail));
  }

  Future<void> _loadTransfers() async {
    final transfers = await supabase
        .from('stock_transfer_requests')
        .select(
          '*, from_store:stores!stock_transfer_requests_from_store_id_fkey(store_name), to_store:stores!stock_transfer_requests_to_store_id_fkey(store_name), requester:users!stock_transfer_requests_requested_by_fkey(full_name)',
        )
        .order('requested_at', ascending: false)
        .limit(50);
    _transfers = List<Map<String, dynamic>>.from(transfers);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddStockDialog,
        icon: const Icon(Icons.add),
        label: const Text('Input Stok Baru'),
      ),
      body: Column(
        children: [
          if (isDesktop)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Text(
                    '📦 Stock Management (IMEI)',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _loadData,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.dashboard), text: 'Overview'),
              Tab(icon: Icon(Icons.inventory), text: 'Detail IMEI'),
              Tab(icon: Icon(Icons.swap_horiz), text: 'Transfer'),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildOverviewTab(),
                      _buildDetailTab(),
                      _buildTransferTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ============ OVERVIEW TAB ============
  Widget _buildOverviewTab() {
    // Summary stats
    int totalFresh = 0, totalChip = 0, totalDisplay = 0;
    for (var s in _stockSummary) {
      totalFresh += (s['fresh_count'] ?? 0) as int;
      totalChip += (s['chip_count'] ?? 0) as int;
      totalDisplay += (s['display_count'] ?? 0) as int;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Stats Cards
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildStatCard(
              'Fresh',
              totalFresh,
              AppColors.success,
              Icons.check_circle,
            ),
            _buildStatCard('Chip', totalChip, AppColors.warning, Icons.memory),
            _buildStatCard('Display', totalDisplay, AppColors.info, Icons.tv),
            _buildStatCard(
              'Total',
              totalFresh + totalChip + totalDisplay,
              Colors.purple,
              Icons.inventory_2,
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Per Store Summary
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'Stok per Toko',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              if (_stockSummary.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                    child: Text(
                      'Belum ada data stok',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                )
              else
                DataTable(
                  columns: const [
                    DataColumn(label: Text('Toko')),
                    DataColumn(label: Text('Fresh'), numeric: true),
                    DataColumn(label: Text('Chip'), numeric: true),
                    DataColumn(label: Text('Display'), numeric: true),
                    DataColumn(label: Text('Total'), numeric: true),
                  ],
                  rows: _stockSummary
                      .map(
                        (s) => DataRow(
                          cells: [
                            DataCell(Text(s['store_name'] ?? 'Unknown')),
                            DataCell(Text('${s['fresh_count'] ?? 0}')),
                            DataCell(Text('${s['chip_count'] ?? 0}')),
                            DataCell(Text('${s['display_count'] ?? 0}')),
                            DataCell(
                              Text(
                                '${(s['fresh_count'] ?? 0) + (s['chip_count'] ?? 0) + (s['display_count'] ?? 0)}',
                              ),
                            ),
                          ],
                        ),
                      )
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, int value, Color color, IconData icon) {
    return Card(
      child: Container(
        width: 150,
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(label, style: const TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  // ============ DETAIL TAB ============
  Widget _buildDetailTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Store selector
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _selectedStoreId,
                  decoration: const InputDecoration(
                    labelText: 'Pilih Toko',
                    border: OutlineInputBorder(),
                  ),
                  items: _stores
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(s['store_name'] ?? 'Unknown'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() => _selectedStoreId = v);
                    _loadStockDetail();
                  },
                ),
              ),
              const SizedBox(width: 16),
              // IMEI search
              SizedBox(
                width: 200,
                child: TextField(
                  decoration: const InputDecoration(
                    labelText: 'Cari IMEI',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    _searchImei = v;
                    _loadStockDetail();
                  },
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _selectedStoreId == null
              ? const Center(
                  child: Text('Pilih toko untuk melihat detail stok'),
                )
              : _stockDetail.isEmpty
              ? const Center(child: Text('Tidak ada stok di toko ini'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _stockDetail.length,
                  itemBuilder: (ctx, i) => _buildStockItem(_stockDetail[i]),
                ),
        ),
      ],
    );
  }

  Widget _buildStockItem(Map<String, dynamic> item) {
    final product = item['products'] as Map<String, dynamic>?;
    final variant = item['product_variants'] as Map<String, dynamic>?;
    final tipe = item['tipe_stok'] ?? 'fresh';
    final bonusPaid = item['bonus_paid'] == true;

    Color statusColor;
    IconData statusIcon;
    switch (tipe) {
      case 'chip':
        statusColor = AppColors.warning;
        statusIcon = Icons.memory;
        break;
      case 'display':
        statusColor = AppColors.info;
        statusIcon = Icons.tv;
        break;
      default:
        statusColor = AppColors.success;
        statusIcon = Icons.check_circle;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.2),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(product?['model_name'] ?? 'Unknown'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${variant?['ram_rom'] ?? ''} • ${variant?['color'] ?? ''}'),
            Text(
              'IMEI: ${item['imei']}',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
            if (bonusPaid)
              const Text(
                '💰 Bonus sudah dibayar',
                style: TextStyle(color: AppColors.success, fontSize: 13),
              ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (ctx) => [
            if (tipe == 'fresh')
              const PopupMenuItem(
                value: 'chip',
                child: Text('🔄 Chip Activation'),
              ),
            if (tipe == 'fresh')
              const PopupMenuItem(
                value: 'sell',
                child: Text('💰 Mark as Sold'),
              ),
            const PopupMenuItem(value: 'transfer', child: Text('📦 Transfer')),
            const PopupMenuItem(
              value: 'history',
              child: Text('📋 Lihat History'),
            ),
          ],
          onSelected: (v) => _handleStockAction(v, item),
        ),
      ),
    );
  }

  void _handleStockAction(String action, Map<String, dynamic> item) {
    switch (action) {
      case 'chip':
        _showChipDialog(item);
        break;
      case 'sell':
        _showSellDialog(item);
        break;
      case 'transfer':
        _showTransferDialog(item);
        break;
      case 'history':
        _showHistoryDialog(item);
        break;
    }
  }

  // ============ TRANSFER TAB ============
  Widget _buildTransferTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_transfers.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Belum ada transfer request')),
            ),
          )
        else
          ..._transfers.map((t) => _buildTransferCard(t)),
      ],
    );
  }

  Widget _buildTransferCard(Map<String, dynamic> transfer) {
    final status = transfer['status'] ?? 'pending';
    Color statusColor;
    switch (status) {
      case 'approved':
        statusColor = AppColors.success;
        break;
      case 'rejected':
        statusColor = AppColors.danger;
        break;
      case 'received':
        statusColor = AppColors.info;
        break;
      default:
        statusColor = AppColors.warning;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.2),
          child: Icon(Icons.swap_horiz, color: statusColor),
        ),
        title: Text(
          '${transfer['from_store']?['store_name']} → ${transfer['to_store']?['store_name']}',
        ),
        subtitle: Text(
          '${transfer['qty_requested']} unit • Oleh: ${transfer['requester']?['full_name']}',
        ),
        trailing: Chip(
          label: Text(
            status.toUpperCase(),
            style: TextStyle(color: statusColor, fontSize: 13),
          ),
          backgroundColor: statusColor.withValues(alpha: 0.1),
        ),
      ),
    );
  }

  // ============ DIALOGS ============
  void _showAddStockDialog() {
    final messenger = ScaffoldMessenger.of(context);
    String? selectedProductId;
    String? selectedVariantId;
    String? selectedStoreId;
    final imeiController = TextEditingController();
    String tipeStok = 'fresh';

    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Input Stok Baru'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedStoreId,
                  decoration: const InputDecoration(
                    labelText: 'Toko',
                    border: OutlineInputBorder(),
                  ),
                  items: _stores
                      .map(
                        (s) => DropdownMenuItem(
                          value: s['id'] as String,
                          child: Text(s['store_name'] ?? 'Unknown'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedStoreId = v),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedProductId,
                  decoration: const InputDecoration(
                    labelText: 'Produk',
                    border: OutlineInputBorder(),
                  ),
                  items: _products
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(
                            '${p['model_name']} (${p['network_type'] ?? '4G'})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) async {
                    setDialogState(() => selectedProductId = v);
                    if (v != null) {
                      final vars = await supabase
                          .from('product_variants')
                          .select('id, ram_rom, color')
                          .eq('product_id', v)
                          .isFilter('deleted_at', null);
                      setDialogState(() {
                        _variants = List<Map<String, dynamic>>.from(vars);
                        selectedVariantId = null;
                      });
                    }
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedVariantId,
                  decoration: const InputDecoration(
                    labelText: 'Varian',
                    border: OutlineInputBorder(),
                  ),
                  items: _variants
                      .map(
                        (v) => DropdownMenuItem(
                          value: v['id'] as String,
                          child: Text('${v['ram_rom']} - ${v['color']}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedVariantId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: imeiController,
                  decoration: const InputDecoration(
                    labelText: 'IMEI',
                    hintText: 'Scan atau input IMEI',
                    border: OutlineInputBorder(),
                  ),
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: tipeStok,
                  decoration: const InputDecoration(
                    labelText: 'Kondisi',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'fresh',
                      child: Text('🟢 Fresh (Baru)'),
                    ),
                    DropdownMenuItem(
                      value: 'chip',
                      child: Text('🟠 Chip (Sudah aktif)'),
                    ),
                    DropdownMenuItem(
                      value: 'display',
                      child: Text('🔵 Display (Demo)'),
                    ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => tipeStok = v ?? 'fresh'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedStoreId == null ||
                    selectedProductId == null ||
                    selectedVariantId == null ||
                    imeiController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Lengkapi semua field'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                  return;
                }

                try {
                  await supabase.from('stok').insert({
                    'store_id': selectedStoreId,
                    'product_id': selectedProductId,
                    'variant_id': selectedVariantId,
                    'imei': imeiController.text,
                    'tipe_stok': tipeStok,
                    'created_by': supabase.auth.currentUser?.id,
                  });

                  // Log movement
                  await supabase.from('stock_movement_log').insert({
                    'imei': imeiController.text,
                    'to_store_id': selectedStoreId,
                    'movement_type': 'initial',
                    'moved_by': supabase.auth.currentUser?.id,
                    'note': 'Initial stock input',
                  });

                  if (!ctx.mounted) return;

                  closeAdminDialog(ctx, changed: true);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Stok berhasil ditambahkan!'),
                      backgroundColor: AppColors.success,
                    ),
                  );
                } catch (e) {
                  if (!ctx.mounted) return;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text('Error: $e'),
                      backgroundColor: AppColors.danger,
                    ),
                  );
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showChipDialog(Map<String, dynamic> item) {
    final messenger = ScaffoldMessenger.of(context);
    final reasonController = TextEditingController();

    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (ctx) => AlertDialog(
        title: const Text('Chip Activation'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('IMEI: ${item['imei']}'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Alasan Chip',
                hintText: 'Contoh: Customer mau test',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await supabase
                    .from('stok')
                    .update({
                      'tipe_stok': 'chip',
                      'chip_reason': reasonController.text,
                      'chip_approved_by': supabase.auth.currentUser?.id,
                      'chip_approved_at': DateTime.now().toIso8601String(),
                      'bonus_paid': true,
                      'bonus_paid_at': DateTime.now().toIso8601String(),
                      'bonus_paid_to': item['promotor_id'],
                    })
                    .eq('id', item['id']);

                await supabase.from('stock_movement_log').insert({
                  'stok_id': item['id'],
                  'imei': item['imei'],
                  'movement_type': 'chip',
                  'moved_by': supabase.auth.currentUser?.id,
                  'note': reasonController.text,
                });

                if (!ctx.mounted) return;

                closeAdminDialog(ctx, changed: true);
                messenger.showSnackBar(
                  const SnackBar(
                    content: Text('Chip activation berhasil!'),
                    backgroundColor: AppColors.success,
                  ),
                );
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            child: const Text('Approve Chip'),
          ),
        ],
      ),
    );
  }

  void _showSellDialog(Map<String, dynamic> item) {
    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (ctx) => AlertDialog(
        title: const Text('Mark as Sold'),
        content: Text('Tandai IMEI ${item['imei']} sebagai terjual?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await supabase
                    .from('stok')
                    .update({
                      'is_sold': true,
                      'sold_at': DateTime.now().toIso8601String(),
                      'bonus_paid': true,
                      'bonus_paid_at': DateTime.now().toIso8601String(),
                      'bonus_paid_to': item['promotor_id'],
                    })
                    .eq('id', item['id']);

                await supabase.from('stock_movement_log').insert({
                  'stok_id': item['id'],
                  'imei': item['imei'],
                  'movement_type': 'sold',
                  'moved_by': supabase.auth.currentUser?.id,
                });

                if (!ctx.mounted) return;

                closeAdminDialog(ctx, changed: true);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: AppColors.danger,
                  ),
                );
              }
            },
            child: const Text('Confirm Sold'),
          ),
        ],
      ),
    );
  }

  void _showTransferDialog(Map<String, dynamic> item) {
    final messenger = ScaffoldMessenger.of(context);
    String? toStoreId;

    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Transfer Stock'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('IMEI: ${item['imei']}'),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: toStoreId,
                decoration: const InputDecoration(
                  labelText: 'Toko Tujuan',
                  border: OutlineInputBorder(),
                ),
                items: _stores
                    .where((s) => s['id'] != item['store_id'])
                    .map(
                      (s) => DropdownMenuItem(
                        value: s['id'] as String,
                        child: Text(s['store_name'] ?? 'Unknown'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setDialogState(() => toStoreId = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: toStoreId == null
                  ? null
                  : () async {
                      try {
                        final fromStoreId = item['store_id'];

                        // Update stock location
                        await supabase
                            .from('stok')
                            .update({'store_id': toStoreId})
                            .eq('id', item['id']);

                        // Log movement
                        await supabase.from('stock_movement_log').insert({
                          'stok_id': item['id'],
                          'imei': item['imei'],
                          'from_store_id': fromStoreId,
                          'to_store_id': toStoreId,
                          'movement_type': 'transfer_direct',
                          'moved_by': supabase.auth.currentUser?.id,
                        });

                        if (!ctx.mounted) return;

                        closeAdminDialog(ctx, changed: true);
                        messenger.showSnackBar(
                          const SnackBar(
                            content: Text('Transfer berhasil!'),
                            backgroundColor: AppColors.success,
                          ),
                        );
                      } catch (e) {
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text('Error: $e'),
                            backgroundColor: AppColors.danger,
                          ),
                        );
                      }
                    },
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  void _showHistoryDialog(Map<String, dynamic> item) async {
    final history = await supabase
        .from('stock_movement_log')
        .select('*, mover:users!stock_movement_log_moved_by_fkey(full_name)')
        .eq('imei', item['imei'])
        .order('moved_at', ascending: false);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('History - ${item['imei']}'),
        content: SizedBox(
          width: 400,
          height: 300,
          child: ListView.builder(
            itemCount: (history as List).length,
            itemBuilder: (ctx, i) {
              final h = history[i];
              return ListTile(
                leading: const Icon(Icons.history),
                title: Text(h['movement_type'] ?? 'Unknown'),
                subtitle: Text(
                  '${h['mover']?['full_name'] ?? 'Unknown'}\n${h['moved_at']}',
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }
}
