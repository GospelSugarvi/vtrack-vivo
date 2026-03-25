import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/core/utils/success_dialog.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../ui/promotor/promotor.dart';

class ImeiNormalizationPage extends StatefulWidget {
  const ImeiNormalizationPage({super.key});

  @override
  State<ImeiNormalizationPage> createState() => _ImeiNormalizationPageState();
}

class _ImeiNormalizationPageState extends State<ImeiNormalizationPage>
    with SingleTickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  final SupabaseClient _supabase = Supabase.instance.client;
  late final TabController _tabController;

  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _promotorName;
  List<Map<String, dynamic>> _unreportedSales = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _imeiItems = <Map<String, dynamic>>[];
  final Set<String> _selectedUnreportedSaleIds = <String>{};
  final Set<String> _selectedReadyIds = <String>{};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!mounted) return;
      if (_tabController.indexIsChanging) return;
      setState(() {});
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final results = await Future.wait([
        _supabase
            .from('users')
            .select('full_name, nickname')
            .eq('id', userId)
            .maybeSingle(),
        _supabase
            .from('imei_normalizations')
            .select(
              'id, imei, status, sold_at, created_at, updated_at, notes, '
              'product_variants!variant_id(ram_rom, color, products!product_id(model_name))',
            )
            .eq('promotor_id', userId)
            .order('created_at', ascending: false),
        _supabase
            .from('sales_sell_out')
            .select(
              'id, transaction_date, serial_imei, variant_id, store_id, '
              'product_variants!inner(ram_rom, color, products!inner(id, model_name))',
            )
            .eq('promotor_id', userId)
            .order('transaction_date', ascending: false),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final imeiRows = List<Map<String, dynamic>>.from(results[1] as List);
      final salesRows = List<Map<String, dynamic>>.from(results[2] as List);
      final reportedImeis = imeiRows
          .map((row) => row['imei']?.toString() ?? '')
          .where((value) => value.isNotEmpty)
          .toSet();

      final unreported = salesRows
          .where((sale) {
            final imei = sale['serial_imei']?.toString() ?? '';
            return imei.isNotEmpty && !reportedImeis.contains(imei);
          })
          .map((sale) {
            final map = Map<String, dynamic>.from(sale);
            map['status'] = 'unreported';
            return map;
          })
          .toList();

      if (!mounted) return;
      setState(() {
        final nickname = profile?['nickname']?.toString().trim();
        final fullName = profile?['full_name']?.toString().trim();
        _promotorName = nickname != null && nickname.isNotEmpty
            ? nickname
            : fullName;
        _imeiItems = imeiRows.map(_normalizeItemStatus).toList();
        _unreportedSales = unreported;
        _selectedUnreportedSaleIds.clear();
        _selectedReadyIds.removeWhere(
          (id) => !_imeiItems.any((item) => '${item['id']}' == id),
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memuat data IMEI: $e')));
    }
  }

  Map<String, dynamic> _normalizeItemStatus(Map<String, dynamic> raw) {
    final item = Map<String, dynamic>.from(raw);
    switch (item['status']?.toString() ?? '') {
      case 'pending':
      case 'reported':
      case 'processing':
        item['status'] = 'reported';
        break;
      case 'sent':
        item['status'] = 'reported';
        break;
      case 'normalized':
      case 'normal':
        item['status'] = 'ready_to_scan';
        break;
    }
    return item;
  }

  List<Map<String, dynamic>> _itemsByStatus(String status) {
    return _imeiItems.where((item) => item['status'] == status).toList();
  }

  bool get _canDismissNormalizationFlow {
    return _unreportedSales.isEmpty && _itemsByStatus('reported').isEmpty;
  }

  String _sellOutMeta(Map<String, dynamic> sale) {
    final variant = sale['product_variants'] as Map<String, dynamic>?;
    final product = variant?['products'] as Map<String, dynamic>?;
    final title = product?['model_name']?.toString() ?? '-';
    final meta = [
      sale['serial_imei']?.toString() ?? '-',
      variant?['ram_rom']?.toString() ?? '',
      variant?['color']?.toString() ?? '',
    ].where((e) => e.isNotEmpty).join(' · ');
    return '$title • $meta';
  }

  Future<void> _submitSelectedImeis() async {
    if (_selectedUnreportedSaleIds.isEmpty || _isSubmitting) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSubmitting = true);
    try {
      final selectedSales = _unreportedSales
          .where((sale) => _selectedUnreportedSaleIds.contains('${sale['id']}'))
          .toList();
      final rows = <Map<String, dynamic>>[];

      for (final sale in selectedSales) {
        final variant = sale['product_variants'] as Map<String, dynamic>?;
        final product = variant?['products'] as Map<String, dynamic>?;
        final imei = sale['serial_imei']?.toString() ?? '';
        if (imei.isEmpty ||
            sale['store_id'] == null ||
            sale['variant_id'] == null ||
            product?['id'] == null) {
          continue;
        }
        rows.add({
          'promotor_id': userId,
          'store_id': sale['store_id'],
          'product_id': product!['id'],
          'variant_id': sale['variant_id'],
          'imei': imei,
          'sold_at': sale['transaction_date'],
          'status': 'reported',
          'sent_to_sator_at': DateTime.now().toIso8601String(),
        });
      }

      if (rows.isEmpty) {
        throw Exception('Tidak ada IMEI valid yang bisa dikirim');
      }

      await _supabase.from('imei_normalizations').upsert(
        rows,
        onConflict: 'imei,sold_at',
      );
      await _loadData();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: '${rows.length} IMEI berhasil dikirim ke SATOR.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal kirim IMEI: $e')));
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _markSelectedAsScanned() async {
    if (_selectedReadyIds.isEmpty) return;
    try {
      for (final id in _selectedReadyIds) {
        await _supabase.rpc('mark_imei_scanned', params: {'p_normalization_id': id});
      }
      await _loadData();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: '${_selectedReadyIds.length} IMEI ditandai selesai scan.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal update status scan: $e')));
    }
  }

  Future<void> _copySelectedReadyImeis() async {
    final selectedItems = _itemsByStatus(
      'ready_to_scan',
    ).where((item) => _selectedReadyIds.contains('${item['id']}')).toList();
    final text = selectedItems
        .map((item) => item['imei']?.toString() ?? '')
        .join('\n');
    if (text.trim().isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${selectedItems.length} IMEI disalin')),
    );
  }

  Future<void> _deleteImeiMessage(Map<String, dynamic> item) async {
    final id = '${item['id'] ?? ''}'.trim();
    if (id.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus item?'),
        content: const Text(
          'Item IMEI ini akan dihapus dari daftar penormalan.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase.from('imei_normalizations').delete().eq('id', id);
      if (!mounted) return;
      setState(() {
        _imeiItems = _imeiItems.where((row) => '${row['id']}' != id).toList();
        _selectedReadyIds.remove(id);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item IMEI dihapus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal menghapus item: $e')));
    }
  }

  String _productName(Map<String, dynamic> item) {
    final variant = item['product_variants'] as Map<String, dynamic>?;
    final product = variant?['products'] as Map<String, dynamic>?;
    final model = product?['model_name']?.toString() ?? '-';
    final ramRom = variant?['ram_rom']?.toString() ?? '';
    final color = variant?['color']?.toString() ?? '';
    final suffix = [ramRom, color].where((e) => e.isNotEmpty).join(' · ');
    return suffix.isEmpty ? model : '$model · $suffix';
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'reported':
        return t.warning;
      case 'processing':
        return t.info;
      case 'ready_to_scan':
        return t.success;
      case 'scanned':
        return t.textSecondary;
      default:
        return t.textSecondary;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'reported':
        return 'Dikirim ke SATOR';
      case 'ready_to_scan':
        return 'Siap Scan';
      case 'scanned':
        return 'Selesai';
      default:
        return status;
    }
  }

  Widget _buildStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _statusColor(status).withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: _statusColor(status),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  PreferredSizeWidget _buildSectionTabBar() {
    return PreferredSize(
      preferredSize: const Size.fromHeight(68),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 12, 12),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.surface3),
          ),
          child: TabBar(
            controller: _tabController,
            isScrollable: true,
            dividerColor: Colors.transparent,
            indicator: BoxDecoration(
              color: t.primaryAccentSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: t.primaryAccent,
            unselectedLabelColor: t.textMutedStrong,
            labelStyle: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w800,
              color: t.primaryAccent,
            ),
            unselectedLabelStyle: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w700,
              color: t.textMutedStrong,
            ),
            tabAlignment: TabAlignment.start,
            labelPadding: const EdgeInsets.symmetric(horizontal: 10),
            tabs: const [
              Tab(text: 'Belum Kirim'),
              Tab(text: 'Dikirim'),
              Tab(text: 'Siap Scan'),
              Tab(text: 'Selesai'),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final reportedItems = _itemsByStatus('reported');
    final readyItems = _itemsByStatus('ready_to_scan');
    final scannedItems = _itemsByStatus('scanned');

    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(
        title: Text(
          _promotorName == null
              ? 'Penormalan IMEI'
              : 'Penormalan IMEI · $_promotorName',
        ),
        actions: [
          if (_canDismissNormalizationFlow)
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Tutup'),
            ),
        ],
        bottom: _buildSectionTabBar(),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUnreportedTab(),
                _buildItemTab(reportedItems, selectable: false),
                _buildItemTab(readyItems, selectable: true),
                _buildItemTab(scannedItems, selectable: false),
              ],
            ),
      bottomNavigationBar: _buildBottomBar(reportedItems.length, readyItems.length),
    );
  }

  Widget _buildBottomBar(int reportedCount, int readyCount) {
    final index = _tabController.index;
    if (index == 0) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _canDismissNormalizationFlow
              ? OutlinedButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: const Text('Tutup'),
                )
              : FilledButton(
                  onPressed: _selectedUnreportedSaleIds.isEmpty || _isSubmitting
                      ? null
                      : _submitSelectedImeis,
                  child: Text(_isSubmitting ? 'Mengirim...' : 'Kirim IMEI Terpilih'),
                ),
        ),
      );
    }
    if (index == 2) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 40),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                  ),
                  onPressed: _selectedReadyIds.isEmpty
                      ? null
                      : _copySelectedReadyImeis,
                  child: const Text('Salin IMEI'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    minimumSize: const Size(0, 40),
                    textStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                  ),
                  onPressed: _selectedReadyIds.isEmpty
                      ? null
                      : _markSelectedAsScanned,
                  child: const Text('Tandai Selesai'),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Dikirim: $reportedCount · Siap scan: $readyCount',
          textAlign: TextAlign.center,
          style: PromotorText.outfit(size: 12, color: t.textSecondary),
        ),
      ),
    );
  }

  Widget _buildUnreportedTab() {
    if (_unreportedSales.isEmpty) {
      return _empty(
        _canDismissNormalizationFlow
            ? 'Semua IMEI sudah normal. Halaman ini bisa ditutup.'
            : 'Tidak ada IMEI yang belum dikirim.',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _unreportedSales.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final sale = _unreportedSales[index];
        final id = '${sale['id']}';
        final selected = _selectedUnreportedSaleIds.contains(id);
        return Container(
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? t.primaryAccent : t.surface3),
          ),
          child: CheckboxListTile(
            value: selected,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            controlAffinity: ListTileControlAffinity.leading,
            checkboxShape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
            onChanged: (value) {
              setState(() {
                if (value == true) {
                  _selectedUnreportedSaleIds.add(id);
                } else {
                  _selectedUnreportedSaleIds.remove(id);
                }
              });
            },
            title: Text(
              _sellOutMeta(sale),
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemTab(
    List<Map<String, dynamic>> items, {
    required bool selectable,
  }) {
    if (items.isEmpty) {
      return _empty('Belum ada data.');
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final item = items[index];
        final id = '${item['id']}';
        final selected = _selectedReadyIds.contains(id);
        final status = item['status']?.toString() ?? '-';

        final rowContent = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    _productName(item),
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _buildStatusBadge(status),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              'IMEI ${item['imei'] ?? '-'}',
              style: PromotorText.outfit(
                size: 12,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
          ],
        );
        if (!selectable) {
          return InkWell(
            onLongPress: () => _deleteImeiMessage(item),
            borderRadius: BorderRadius.circular(18),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: t.surface3),
              ),
              child: rowContent,
            ),
          );
        }
        return InkWell(
          onLongPress: () => _deleteImeiMessage(item),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: selected ? t.primaryAccent : t.surface3),
            ),
            child: CheckboxListTile(
              value: selected,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              controlAffinity: ListTileControlAffinity.leading,
              checkboxShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              onChanged: (value) {
                setState(() {
                  if (value == true) {
                    _selectedReadyIds.add(id);
                  } else {
                    _selectedReadyIds.remove(id);
                  }
                });
              },
              title: rowContent,
            ),
          ),
        );
      },
    );
  }

  Widget _empty(String text) {
    return Center(
      child: Text(
        text,
        style: PromotorText.outfit(size: 12, color: t.textSecondary),
      ),
    );
  }
}
