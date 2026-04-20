import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/features/promotor/presentation/pages/barcode_scanner_page.dart';
import 'package:vtrack/features/sator/presentation/pages/sell_in/sell_in_order_composer_page.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class StokTokoPage extends StatefulWidget {
  final String? storeId;
  final String mode;
  final bool enableRecommendationAction;
  final String initialTab;

  const StokTokoPage({
    super.key,
    this.storeId,
    this.mode = 'all',
    this.enableRecommendationAction = false,
    this.initialTab = 'stock',
  });

  @override
  State<StokTokoPage> createState() => _StokTokoPageState();
}

class _StokTokoPageState extends State<StokTokoPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _moveOutImeiController = TextEditingController();
  final _moveOutNoteController = TextEditingController();
  final _soldChipImeiController = TextEditingController();
  final _soldChipReasonController = TextEditingController();

  bool _isLoading = true;
  bool _isSubmittingMoveOut = false;
  bool _isSubmittingSoldChipRequest = false;
  String? _resolvedStoreId;
  String? _storeName;
  String? _groupId;
  String? _groupName;
  List<String> _stockScopeStoreIds = const [];
  int _groupStoreCount = 0;
  String _promotorName = 'Promotor';
  List<Map<String, dynamic>> _summaryRows = const [];
  List<Map<String, dynamic>> _chipRows = const [];
  List<Map<String, dynamic>> _pendingClaimRows = const [];
  List<Map<String, dynamic>> _movementRows = const [];
  List<Map<String, dynamic>> _pendingChipRequestRows = const [];
  String _summaryFilter = 'all';
  String _actionTab = 'move-out';
  String _managerTab = 'stock';

  bool get _isActionMode => widget.mode == 'actions';
  bool get _isManagerMode => widget.mode == 'all';
  bool get _isSummaryMode => widget.mode == 'summary';
  int get _pendingMoveOutCount => _pendingClaimRows
      .where((row) => '${row['move_status'] ?? ''}' == 'pending')
      .length;
  int get _completedMoveOutCount => _pendingClaimRows
      .where((row) => '${row['move_status'] ?? ''}' == 'claimed')
      .length;

  @override
  void initState() {
    super.initState();
    _managerTab = widget.initialTab == 'chip' ? 'chip' : 'stock';
    _loadData();
  }

  @override
  void dispose() {
    _moveOutImeiController.dispose();
    _moveOutNoteController.dispose();
    _soldChipImeiController.dispose();
    _soldChipReasonController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final resolvedStoreId = await _resolveStoreId();
      if (resolvedStoreId == null || resolvedStoreId.isEmpty) {
        if (!mounted) return;
        setState(() {
          _resolvedStoreId = null;
          _storeName = null;
          _summaryRows = const [];
          _chipRows = const [];
          _pendingClaimRows = const [];
          _movementRows = const [];
          _pendingChipRequestRows = const [];
          _isLoading = false;
        });
        return;
      }

      final storeContext = await _loadStoreContext(resolvedStoreId);
      final promotorName = await _loadPromotorName();
      final scopedStoreIds = List<String>.from(
        storeContext['stock_scope_store_ids'] as List? ??
            <String>[resolvedStoreId],
      );

      List<Map<String, dynamic>> summaryRows = const [];
      List<Map<String, dynamic>> chipRows = const [];
      List<Map<String, dynamic>> pendingClaimRows = const [];
      List<Map<String, dynamic>> movementRows = const [];
      List<Map<String, dynamic>> pendingChipRequestRows = const [];

      if (_isSummaryMode || _isManagerMode) {
        summaryRows = await _loadSummaryRows(
          resolvedStoreId,
          scopeStoreIds: scopedStoreIds,
        );
      }

      if (_isActionMode || _isManagerMode) {
        chipRows = await _loadChipRows(
          resolvedStoreId,
          scopeStoreIds: scopedStoreIds,
        );
        pendingChipRequestRows = await _loadPendingChipRequests(
          resolvedStoreId,
          scopeStoreIds: scopedStoreIds,
        );
      }

      if (_isActionMode) {
        pendingClaimRows = await _loadPendingClaimRows(resolvedStoreId);
        movementRows = await _loadMovementRows(resolvedStoreId);
      }

      if (!mounted) return;
      setState(() {
        _resolvedStoreId = resolvedStoreId;
        _storeName = storeContext['store_name']?.toString();
        _groupId = storeContext['group_id']?.toString();
        _groupName = storeContext['group_name']?.toString();
        _stockScopeStoreIds = List<String>.from(
          storeContext['stock_scope_store_ids'] as List? ?? const <String>[],
        );
        _groupStoreCount = _toInt(storeContext['group_store_count']);
        _promotorName = promotorName;
        _summaryRows = summaryRows;
        _chipRows = chipRows;
        _pendingClaimRows = pendingClaimRows;
        _movementRows = movementRows;
        _pendingChipRequestRows = pendingChipRequestRows;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _resolvedStoreId = null;
        _groupId = null;
        _groupName = null;
        _groupStoreCount = 0;
        _summaryRows = const [];
        _chipRows = const [];
        _pendingClaimRows = const [];
        _movementRows = const [];
        _pendingChipRequestRows = const [];
        _isLoading = false;
      });
    }
  }

  Future<String?> _resolveStoreId() async {
    final explicitStoreId = widget.storeId?.trim();
    if (explicitStoreId != null && explicitStoreId.isNotEmpty) {
      return explicitStoreId;
    }

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return null;

    final assignmentRows = await _supabase
        .from('assignments_promotor_store')
        .select('store_id')
        .eq('promotor_id', userId)
        .eq('active', true)
        .order('created_at', ascending: false)
        .limit(1);

    final assignments = List<Map<String, dynamic>>.from(assignmentRows);
    if (assignments.isEmpty) return null;
    return assignments.first['store_id']?.toString();
  }

  Future<Map<String, dynamic>> _loadStoreContext(String storeId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId != null) {
      try {
        final rpcResult = await _supabase.rpc(
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
        final rpcStoreId = '${rpcMap['store_id'] ?? ''}'.trim();
        if (rpcStoreId.isNotEmpty) {
          return {
            'store_name': rpcMap['store_name']?.toString(),
            'group_id': rpcMap['group_id']?.toString(),
            'group_name': rpcMap['group_name']?.toString(),
            'group_mode': rpcMap['group_mode']?.toString() ?? '',
            'stock_scope_store_ids': rpcScope.isNotEmpty
                ? rpcScope
                : <String>[rpcStoreId],
            'group_store_count': rpcMap['group_store_count'] ?? 0,
          };
        }
      } catch (_) {}
    }

    final row = await _supabase
        .from('stores')
        .select('store_name, group_id')
        .eq('id', storeId)
        .maybeSingle();
    final rawGroupId = row?['group_id']?.toString();
    final groupId = rawGroupId == null || rawGroupId.trim().isEmpty
        ? null
        : rawGroupId.trim();
    Map<String, dynamic> group = <String, dynamic>{};
    if (groupId != null) {
      final groupRow = await _supabase
          .from('store_groups')
          .select('group_name, stock_handling_mode')
          .eq('id', groupId)
          .isFilter('deleted_at', null)
          .maybeSingle();
      if (groupRow != null) {
        group = Map<String, dynamic>.from(groupRow);
      }
    }
    final groupMode = group['stock_handling_mode']?.toString().trim() ?? '';
    int groupStoreCount = 0;
    final stockScopeStoreIds = <String>[storeId];
    if (groupId != null) {
      final storeRows = await _supabase
          .from('stores')
          .select('id')
          .eq('group_id', groupId)
          .isFilter('deleted_at', null);
      final groupedStores = List<Map<String, dynamic>>.from(storeRows);
      groupStoreCount = groupedStores.length;
      if (groupMode == 'shared_group') {
        stockScopeStoreIds
          ..clear()
          ..addAll(
            groupedStores
                .map((item) => '${item['id'] ?? ''}'.trim())
                .where((id) => id.isNotEmpty),
          );
      }
    }
    return {
      'store_name': row?['store_name']?.toString(),
      'group_id': groupId,
      'group_name': group['group_name']?.toString(),
      'group_mode': groupMode,
      'stock_scope_store_ids': stockScopeStoreIds,
      'group_store_count': groupStoreCount,
    };
  }

  bool get _hasConfiguredGroupOrder {
    final groupId = (_groupId ?? '').trim();
    final groupName = (_groupName ?? '').trim().toLowerCase();
    if (groupId.isEmpty || groupName.isEmpty) return false;
    if (groupName == 'ungrouped' || groupName.startsWith('ungrouped ')) {
      return false;
    }
    return _groupStoreCount > 1;
  }

  Future<String> _loadPromotorName() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return 'Promotor';

    try {
      final row = await _supabase
          .from('users')
          .select('full_name')
          .eq('id', user.id)
          .maybeSingle();
      final fullName = '${row?['full_name'] ?? ''}'.trim();
      if (fullName.isNotEmpty) return fullName;
    } catch (_) {}

    final metadata = user.userMetadata ?? const <String, dynamic>{};
    final metaName = '${metadata['full_name'] ?? metadata['name'] ?? ''}'
        .trim();
    if (metaName.isNotEmpty) return metaName;
    return 'Promotor';
  }

  Future<List<Map<String, dynamic>>> _loadSummaryRows(
    String storeId, {
    List<String>? scopeStoreIds,
  }) async {
    final scopedIds = _resolveScopeStoreIds(storeId, scopeStoreIds);
    final variantRows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('product_variants')
          .select(
            'id, srp, ram_rom, color, products!product_id(model_name, network_type, status)',
          )
          .eq('active', true)
          .isFilter('deleted_at', null),
    );

    final activeVariants = variantRows.where((row) {
      final product = _asMap(row['products']);
      return '${product['status'] ?? 'active'}' == 'active';
    }).toList();

    try {
      final stockRows = await _supabase
          .from('stok')
          .select(
            'variant_id, imei, tipe_stok, product_variants!variant_id(srp, ram_rom, color, products!product_id(model_name, network_type))',
          )
          .inFilter('store_id', scopedIds)
          .eq('is_sold', false)
          .order('tipe_stok')
          .order('imei');

      final normalized = List<Map<String, dynamic>>.from(stockRows).map((row) {
        final variant = _asMap(row['product_variants']);
        final product = _asMap(variant['products']);
        return {
          'variant_id': (row['variant_id'] ?? '').toString(),
          'kategori': (product['model_name'] ?? 'Produk').toString(),
          'network_type': (product['network_type'] ?? '').toString(),
          'srp': variant['srp'],
          'tipe': (row['tipe_stok'] ?? '-').toString(),
          'ram_rom': (variant['ram_rom'] ?? '').toString(),
          'color': (variant['color'] ?? '').toString(),
          'imei': (row['imei'] ?? '-').toString(),
          'qty': 1,
        };
      }).toList();

      if (normalized.isNotEmpty) {
        final stockedVariantIds = normalized
            .map((row) => '${row['variant_id'] ?? ''}')
            .where((id) => id.isNotEmpty)
            .toSet();

        for (final row in activeVariants) {
          final variantId = '${row['id'] ?? ''}';
          if (variantId.isEmpty || stockedVariantIds.contains(variantId)) {
            continue;
          }
          final product = _asMap(row['products']);
          normalized.add({
            'variant_id': variantId,
            'kategori': (product['model_name'] ?? 'Produk').toString(),
            'network_type': (product['network_type'] ?? '').toString(),
            'srp': row['srp'],
            'tipe': 'kosong',
            'ram_rom': (row['ram_rom'] ?? '').toString(),
            'color': (row['color'] ?? '').toString(),
            'imei': '-',
            'qty': 0,
          });
        }
        return normalized;
      }
    } catch (_) {}

    final inventoryRows = await _supabase
        .from('store_inventory')
        .select(
          'variant_id, quantity, product_variants!variant_id(srp, ram_rom, color, products!product_id(model_name, network_type))',
        )
        .inFilter('store_id', scopedIds)
        .order('quantity', ascending: false);

    final normalizedInventory = List<Map<String, dynamic>>.from(inventoryRows)
        .map((row) {
          final variant = _asMap(row['product_variants']);
          final product = _asMap(variant['products']);
          return {
            'variant_id': (row['variant_id'] ?? '').toString(),
            'kategori': (product['model_name'] ?? 'Produk').toString(),
            'network_type': (product['network_type'] ?? '').toString(),
            'srp': variant['srp'],
            'tipe': 'stok',
            'ram_rom': (variant['ram_rom'] ?? '').toString(),
            'color': (variant['color'] ?? '').toString(),
            'imei': '-',
            'qty': _toInt(row['quantity']),
          };
        })
        .toList();

    final stockedVariantIds = normalizedInventory
        .where((row) => _toInt(row['qty']) > 0)
        .map((row) => '${row['variant_id'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toSet();

    normalizedInventory.removeWhere((row) => _toInt(row['qty']) <= 0);

    for (final row in activeVariants) {
      final variantId = '${row['id'] ?? ''}';
      if (variantId.isEmpty || stockedVariantIds.contains(variantId)) continue;
      final product = _asMap(row['products']);
      normalizedInventory.add({
        'variant_id': variantId,
        'kategori': (product['model_name'] ?? 'Produk').toString(),
        'network_type': (product['network_type'] ?? '').toString(),
        'srp': row['srp'],
        'tipe': 'kosong',
        'ram_rom': (row['ram_rom'] ?? '').toString(),
        'color': (row['color'] ?? '').toString(),
        'imei': '-',
        'qty': 0,
      });
    }

    return normalizedInventory;
  }

  Future<List<Map<String, dynamic>>> _loadChipRows(
    String storeId, {
    List<String>? scopeStoreIds,
  }) async {
    final scopedIds = _resolveScopeStoreIds(storeId, scopeStoreIds);
    final rows = await _supabase
        .from('stok')
        .select(
          'id, imei, chip_reason, chip_approved_at, '
          'promotor:promotor_id(full_name), approver:chip_approved_by(full_name), '
          'product_variants!variant_id(ram_rom, color, products!product_id(model_name, network_type))',
        )
        .inFilter('store_id', scopedIds)
        .eq('is_sold', false)
        .eq('tipe_stok', 'chip')
        .order('chip_approved_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final variant = _asMap(row['product_variants']);
      final product = _asMap(variant['products']);
      return {
        'stok_id': row['id']?.toString(),
        'imei': (row['imei'] ?? '-').toString(),
        'product_name': (product['model_name'] ?? 'Produk').toString(),
        'network_type': (product['network_type'] ?? '').toString(),
        'variant': (variant['ram_rom'] ?? '').toString(),
        'color': (variant['color'] ?? '').toString(),
        'chip_reason': (row['chip_reason'] ?? '').toString(),
        'chip_approved_at': row['chip_approved_at'],
        'promotor_name': '${(_asMap(row['promotor']))['full_name'] ?? ''}'
            .trim(),
        'approver_name': '${(_asMap(row['approver']))['full_name'] ?? ''}'
            .trim(),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadPendingClaimRows(
    String storeId,
  ) async {
    final rows = await _supabase
        .from('stock_movement_log')
        .select(
          'stok_id, imei, note, movement_type, moved_at, '
          'stok:stok_id(id, is_sold, store_id, relocation_status, product_variants!variant_id(ram_rom, color, products!product_id(model_name, network_type)))',
        )
        .eq('from_store_id', storeId)
        .order('moved_at', ascending: false)
        .limit(60);

    final latestByStock = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(rows)) {
      if ('${row['movement_type'] ?? ''}' != 'adjustment') continue;
      final stokId = '${row['stok_id'] ?? ''}'.trim();
      if (stokId.isEmpty || latestByStock.containsKey(stokId)) continue;
      latestByStock[stokId] = row;
    }

    return latestByStock.values
        .where((row) {
          final stok = _asMap(row['stok']);
          if (stok['is_sold'] == true) return false;
          final currentStoreId = '${stok['store_id'] ?? ''}'.trim();
          final relocationStatus = '${stok['relocation_status'] ?? ''}'.trim();
          final isPending =
              currentStoreId.isEmpty && relocationStatus == 'pending_claim';
          final isClaimed =
              currentStoreId.isNotEmpty && currentStoreId != storeId;
          return isPending || isClaimed;
        })
        .map((row) {
          final stok = _asMap(row['stok']);
          final stokVariant = _asMap(stok['product_variants']);
          final product = _asMap(stokVariant['products']);
          final currentStoreId = '${stok['store_id'] ?? ''}'.trim();
          final relocationStatus = '${stok['relocation_status'] ?? ''}'.trim();
          final isPending =
              currentStoreId.isEmpty && relocationStatus == 'pending_claim';
          return {
            'stok_id': row['stok_id']?.toString() ?? stok['id']?.toString(),
            'imei': (row['imei'] ?? '-').toString(),
            'model_name': (product['model_name'] ?? 'Produk').toString(),
            'network_type': (product['network_type'] ?? '').toString(),
            'ram_rom': (stokVariant['ram_rom'] ?? '').toString(),
            'color': (stokVariant['color'] ?? '').toString(),
            'relocation_note': (row['note'] ?? '').toString(),
            'relocation_reported_at': row['moved_at'],
            'move_status': isPending ? 'pending' : 'claimed',
          };
        })
        .toList();
  }

  Future<List<Map<String, dynamic>>> _loadMovementRows(String storeId) async {
    final rows = await _supabase
        .from('stock_movement_log')
        .select(
          'movement_type, moved_at, note, from_store_id, to_store_id, imei, '
          'stok:stok_id(tipe_stok, product_variants!variant_id(ram_rom, color, products!product_id(model_name, network_type)))',
        )
        .or('from_store_id.eq.$storeId,to_store_id.eq.$storeId')
        .order('moved_at', ascending: false)
        .limit(20);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final stok = _asMap(row['stok']);
      final variant = _asMap(stok['product_variants']);
      final product = _asMap(variant['products']);
      return {
        'movement_type': (row['movement_type'] ?? '-').toString(),
        'moved_at': row['moved_at'],
        'note': (row['note'] ?? '').toString(),
        'imei': (row['imei'] ?? '-').toString(),
        'product_name': (product['model_name'] ?? 'Produk').toString(),
        'network_type': (product['network_type'] ?? '').toString(),
        'ram_rom': (variant['ram_rom'] ?? '').toString(),
        'color': (variant['color'] ?? '').toString(),
        'tipe_stok': (stok['tipe_stok'] ?? '').toString(),
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadPendingChipRequests(
    String storeId, {
    List<String>? scopeStoreIds,
  }) async {
    final scopedIds = _resolveScopeStoreIds(storeId, scopeStoreIds);
    final rows = await _supabase
        .from('stock_chip_requests')
        .select(
          'id, reason, requested_at, request_type, source_sale_id, '
          'stok:stok_id(imei, product_variants!variant_id(ram_rom, color, products!product_id(model_name, network_type)))',
        )
        .inFilter('store_id', scopedIds)
        .eq('status', 'pending')
        .order('requested_at', ascending: false)
        .limit(20);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final stok = _asMap(row['stok']);
      final variant = _asMap(stok['product_variants']);
      final product = _asMap(variant['products']);
      return {
        'id': row['id']?.toString(),
        'imei': (stok['imei'] ?? '-').toString(),
        'model_name': (product['model_name'] ?? 'Produk').toString(),
        'network_type': (product['network_type'] ?? '').toString(),
        'ram_rom': (variant['ram_rom'] ?? '').toString(),
        'color': (variant['color'] ?? '').toString(),
        'reason': (row['reason'] ?? '').toString(),
        'requested_at': row['requested_at'],
        'request_type': (row['request_type'] ?? 'fresh_to_chip').toString(),
        'source_sale_id': row['source_sale_id']?.toString(),
      };
    }).toList();
  }

  List<String> _scopeStoreIds(String fallbackStoreId) {
    final ids = _stockScopeStoreIds
        .where((id) => id.trim().isNotEmpty)
        .toList();
    if (ids.isNotEmpty) return ids;
    return <String>[fallbackStoreId];
  }

  List<String> _resolveScopeStoreIds(
    String fallbackStoreId,
    List<String>? override,
  ) {
    final ids = (override ?? _stockScopeStoreIds)
        .where((id) => id.trim().isNotEmpty)
        .toList();
    if (ids.isNotEmpty) return ids;
    return <String>[fallbackStoreId];
  }

  Future<void> _submitSoldChipRequest() async {
    final imei = _soldChipImeiController.text.trim();
    final reason = _soldChipReasonController.text.trim();

    if (imei.length != 15 || int.tryParse(imei) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('IMEI harus 15 digit angka'),
          backgroundColor: t.danger,
        ),
      );
      return;
    }

    if (reason.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Alasan chip minimal 3 karakter'),
          backgroundColor: t.danger,
        ),
      );
      return;
    }

    if (!mounted) return;
    setState(() => _isSubmittingSoldChipRequest = true);
    try {
      await _supabase.rpc(
        'submit_sold_stock_chip_request',
        params: {'p_imei': imei, 'p_reason': reason},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Request chip untuk IMEI $imei berhasil dikirim'),
          backgroundColor: t.success,
        ),
      );
      _soldChipImeiController.clear();
      _soldChipReasonController.clear();
      setState(() => _isSubmittingSoldChipRequest = false);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal kirim request chip: $e'),
          backgroundColor: t.danger,
        ),
      );
      setState(() => _isSubmittingSoldChipRequest = false);
    }
  }

  Future<void> _scanSoldChipBarcode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || result == null) return;

    final imei = result.trim();
    if (imei.isEmpty) return;

    setState(() {
      _soldChipImeiController.text = imei;
      if (_soldChipReasonController.text.trim().isEmpty) {
        _soldChipReasonController.text =
            'Instruksi atasan, fisik barang masih ada di toko';
      }
    });
  }

  Future<void> _scanMoveOutBarcode() async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const BarcodeScannerPage()),
    );
    if (!mounted || result == null) return;

    final imei = result.trim();
    if (imei.isEmpty) return;

    setState(() {
      _moveOutImeiController.text = imei;
      if (_moveOutNoteController.text.trim().isEmpty) {
        _moveOutNoteController.text = 'Barang dipindahkan ke toko lain';
      }
    });
  }

  Future<void> _submitMoveOut() async {
    final imei = _moveOutImeiController.text.trim();
    final note = _moveOutNoteController.text.trim();

    if (imei.length != 15 || int.tryParse(imei) == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('IMEI harus 15 digit angka'),
          backgroundColor: t.danger,
        ),
      );
      return;
    }

    if ((_resolvedStoreId ?? '').isEmpty) return;

    setState(() => _isSubmittingMoveOut = true);
    try {
      final scopedStoreIds = _scopeStoreIds(_resolvedStoreId!);
      final stokRow = await _supabase
          .from('stok')
          .select('id, store_id, is_sold')
          .eq('imei', imei)
          .eq('is_sold', false)
          .inFilter('store_id', scopedStoreIds)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      final stokId = '${stokRow?['id'] ?? ''}'.trim();
      if (stokId.isEmpty) {
        throw Exception('IMEI tidak ditemukan di cakupan stok toko/grup ini');
      }

      await _supabase.rpc(
        'report_stock_moved_out',
        params: {
          'p_stok_id': stokId,
          'p_note': note.isEmpty ? 'Barang dipindahkan ke toko lain' : note,
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('IMEI $imei ditandai keluar dari toko'),
          backgroundColor: t.success,
        ),
      );
      _moveOutImeiController.clear();
      _moveOutNoteController.clear();
      setState(() => _isSubmittingMoveOut = false);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal tandai barang keluar: $e'),
          backgroundColor: t.danger,
        ),
      );
      setState(() => _isSubmittingMoveOut = false);
    }
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

  String _formatCurrencyCompact(dynamic value) {
    final amount = _toInt(value);
    if (amount <= 0) return '-';
    return NumberFormat.compactCurrency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    ).format(amount);
  }

  String _pageTitle() {
    switch (widget.mode) {
      case 'summary':
        return 'Stok Toko';
      case 'actions':
        return 'Aksi Stok';
      default:
        return 'Stok Toko';
    }
  }

  String _productName(Map<String, dynamic> row) {
    final model = '${row['model_name'] ?? row['product_name'] ?? 'Produk'}'
        .trim();
    final networkType = '${row['network_type'] ?? ''}'.trim();
    final ramRom = '${row['ram_rom'] ?? row['variant'] ?? ''}'.trim();
    final color = '${row['color'] ?? ''}'.trim();
    return [
      model,
      networkType,
      ramRom,
      color,
    ].where((part) => part.isNotEmpty).join(' • ');
  }

  int _sortByText(dynamic a, dynamic b) {
    return '${a ?? ''}'.toLowerCase().compareTo('${b ?? ''}'.toLowerCase());
  }

  int _summaryStatusRank(Map<String, dynamic> row) {
    return _toInt(row['qty']) > 0 ? 0 : 1;
  }

  List<Map<String, dynamic>> _sortedSummaryRows() {
    final rows = _groupSummaryRows(_summaryRows);
    rows.sort((a, b) {
      final statusCompare = _summaryStatusRank(
        a,
      ).compareTo(_summaryStatusRank(b));
      if (statusCompare != 0) return statusCompare;
      final tipe = _sortByText(a['tipe'], b['tipe']);
      if (tipe != 0) return tipe;
      final srpCompare = _toInt(a['srp']).compareTo(_toInt(b['srp']));
      if (srpCompare != 0) return srpCompare;
      final kategori = _sortByText(
        '${a['kategori'] ?? ''} ${a['network_type'] ?? ''}',
        '${b['kategori'] ?? ''} ${b['network_type'] ?? ''}',
      );
      if (kategori != 0) return kategori;
      final warna = _sortByText(a['color'], b['color']);
      if (warna != 0) return warna;
      final ramRom = _sortByText(a['ram_rom'], b['ram_rom']);
      if (ramRom != 0) return ramRom;
      return _sortByText(a['variant_id'], b['variant_id']);
    });
    return rows;
  }

  List<Map<String, dynamic>> _groupSummaryRows(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final kategori = '${row['kategori'] ?? '-'}'.trim();
      final networkType = '${row['network_type'] ?? ''}'.trim();
      final tipe = '${row['tipe'] ?? '-'}'.trim().toLowerCase();
      final color = '${row['color'] ?? '-'}'.trim();
      final ramRom = '${row['ram_rom'] ?? '-'}'.trim();
      final variantId = '${row['variant_id'] ?? ''}'.trim();
      final srp = _toInt(row['srp']);
      final key = '$tipe|$variantId|$kategori|$networkType|$color|$ramRom|$srp';

      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = {
          'variant_id': variantId,
          'kategori': kategori,
          'network_type': networkType,
          'tipe': tipe,
          'color': color,
          'ram_rom': ramRom,
          'srp': srp,
          'qty': _toInt(row['qty']),
          'imeis': <String>[
            if ('${row['imei'] ?? '-'}'.trim().isNotEmpty &&
                '${row['imei'] ?? '-'}'.trim() != '-')
              '${row['imei']}'.trim(),
          ],
        };
      } else {
        existing['qty'] = _toInt(existing['qty']) + _toInt(row['qty']);
        final imeis = List<String>.from(existing['imeis'] as List? ?? const []);
        final imei = '${row['imei'] ?? '-'}'.trim();
        if (imei.isNotEmpty && imei != '-' && !imeis.contains(imei)) {
          imeis.add(imei);
        }
        existing['imeis'] = imeis;
      }
    }
    return grouped.values.toList();
  }

  List<Map<String, dynamic>> _filteredSummaryRows() {
    final rows = _sortedSummaryRows();
    switch (_summaryFilter) {
      case 'empty':
        return rows.where((row) => _toInt(row['qty']) <= 0).toList();
      case 'ready':
        return rows.where((row) => _toInt(row['qty']) > 0).toList();
      default:
        return rows;
    }
  }

  String _filterLabel() {
    switch (_summaryFilter) {
      case 'empty':
        return 'KOSONG';
      case 'ready':
        return 'READY';
      default:
        return 'SEMUA';
    }
  }

  String _fixedCell(String text, int width, {bool alignRight = false}) {
    final normalized = text.replaceAll('\n', ' ').trim();
    if (normalized.length >= width) {
      return normalized.substring(0, width);
    }
    return alignRight ? normalized.padLeft(width) : normalized.padRight(width);
  }

  List<Map<String, dynamic>> _buildSummaryCopyGroups() {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in _filteredSummaryRows()) {
      final kategori = '${row['kategori'] ?? '-'}'.trim();
      final networkType = '${row['network_type'] ?? ''}'.trim();
      final tipe = '${row['tipe'] ?? '-'}'.toUpperCase();
      final color = '${row['color'] ?? '-'}'.trim();
      final ramRom = '${row['ram_rom'] ?? '-'}'.trim();
      final key = '$kategori|$networkType|$tipe|$color|$ramRom';

      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = {
          'kategori': kategori,
          'network_type': networkType,
          'tipe': tipe,
          'color': color,
          'ram_rom': ramRom,
          'srp': _toInt(row['srp']),
          'qty': _toInt(row['qty']),
        };
      } else {
        existing['qty'] = _toInt(existing['qty']) + _toInt(row['qty']);
      }
    }

    final results = grouped.values.toList();
    results.sort((a, b) {
      final statusCompare = _summaryStatusRank(
        a,
      ).compareTo(_summaryStatusRank(b));
      if (statusCompare != 0) return statusCompare;
      final kategoriA = '${a['kategori']} ${a['network_type']}'.toLowerCase();
      final kategoriB = '${b['kategori']} ${b['network_type']}'.toLowerCase();
      final kategoriCompare = kategoriA.compareTo(kategoriB);
      if (kategoriCompare != 0) return kategoriCompare;

      final tipeCompare = '${a['tipe']}'.toLowerCase().compareTo(
        '${b['tipe']}'.toLowerCase(),
      );
      if (tipeCompare != 0) return tipeCompare;
      final srpCompare = _toInt(a['srp']).compareTo(_toInt(b['srp']));
      if (srpCompare != 0) return srpCompare;

      final warnaCompare = '${a['color']}'.toLowerCase().compareTo(
        '${b['color']}'.toLowerCase(),
      );
      if (warnaCompare != 0) return warnaCompare;

      return '${a['ram_rom']}'.toLowerCase().compareTo(
        '${b['ram_rom']}'.toLowerCase(),
      );
    });
    return results;
  }

  String _buildSummaryCopyText() {
    final rows = _buildSummaryCopyGroups();
    final dateText = DateFormat('dd MMM yyyy', 'id_ID').format(DateTime.now());
    final buffer = StringBuffer()
      ..writeln('Nama toko: ${_storeName ?? '-'}')
      ..writeln('Tanggal: $dateText')
      ..writeln('Nama promotor: $_promotorName')
      ..writeln('Filter: ${_filterLabel()}')
      ..writeln('')
      ..writeln(
        '${_fixedCell('TIPE', 8)} ${_fixedCell('WARNA', 12)} ${_fixedCell('RAM/ROM', 14)} ${_fixedCell('QTY', 4, alignRight: true)}',
      )
      ..writeln('-' * 44);

    if (rows.isEmpty) {
      buffer.writeln('Tidak ada data.');
      return buffer.toString().trimRight();
    }

    String? lastCategory;
    for (final row in rows) {
      final category = [
        '${row['kategori'] ?? '-'}'.trim(),
        '${row['network_type'] ?? ''}'.trim(),
      ].where((part) => part.isNotEmpty).join(' ');

      if (category != lastCategory) {
        if (lastCategory != null) buffer.writeln('');
        buffer.writeln(category);
        lastCategory = category;
      }

      buffer.writeln(
        '${_fixedCell(_formatCurrencyCompact(row['srp']), 8)} '
        '${_fixedCell('${row['tipe'] ?? '-'}'.toUpperCase(), 8)} '
        '${_fixedCell('${row['color'] ?? '-'}', 12)} '
        '${_fixedCell('${row['ram_rom'] ?? '-'}', 14)} '
        '${_fixedCell('${_toInt(row['qty'])}', 4, alignRight: true)}',
      );
    }

    return buffer.toString().trimRight();
  }

  Future<void> _copySummaryTable() async {
    final text = _buildSummaryCopyText();
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ringkasan stok ${_filterLabel().toLowerCase()} berhasil disalin',
        ),
        backgroundColor: t.success,
      ),
    );
  }

  Widget _buildMonoText(
    String text, {
    Color? color,
    FontWeight weight = FontWeight.w600,
    double size = 12,
    TextAlign textAlign = TextAlign.left,
  }) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: size,
          height: 1.25,
          color: color ?? t.textPrimary,
          fontWeight: weight,
        ),
        textAlign: textAlign,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildCompactStockRow(
    Map<String, dynamic> row, {
    bool showDivider = true,
  }) {
    final kategori = [
      row['kategori'],
      row['network_type'],
    ].where((part) => '${part ?? ''}'.trim().isNotEmpty).join(' ');
    final title = [
      '${row['kategori'] ?? ''}'.trim(),
      '${row['ram_rom'] ?? ''}'.trim(),
      '${row['color'] ?? ''}'.trim(),
    ].where((part) => part.isNotEmpty && part != '-').join(' • ');
    final tipe = '${row['tipe'] ?? '-'}'.toUpperCase();
    final qty = _toInt(row['qty']);
    final imeis = List<String>.from(row['imeis'] as List? ?? const []);
    final imeiText = imeis.isEmpty ? '-' : imeis.join(', ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: t.surface3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? kategori : title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
              height: 1.1,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              Text(
                tipe,
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w900,
                  color: _summaryTypeTone('${row['tipe'] ?? ''}'),
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Qty $qty',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: t.textMutedStrong,
                    height: 1.0,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            imeiText,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: imeis.isEmpty ? t.textMuted : t.textMutedStrong,
              height: 1.15,
            ),
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  String _movementLabel(String movementType) {
    switch (movementType) {
      case 'transfer_in':
        return 'Stok masuk';
      case 'transfer_out':
        return 'Stok keluar';
      case 'adjustment':
        return 'Penyesuaian';
      case 'chip':
        return 'Ubah ke chip';
      case 'sold':
        return 'Terjual';
      case 'initial':
        return 'Input awal';
      default:
        return movementType;
    }
  }

  String _summaryTypeLabel(String rawType) {
    switch (rawType.toLowerCase()) {
      case 'fresh':
      case 'stok':
        return 'READY';
      case 'chip':
        return 'CHIP';
      case 'display':
        return 'DISPLAY';
      case 'kosong':
        return 'KOSONG';
      default:
        return rawType.toUpperCase();
    }
  }

  Color _summaryTypeTone(String rawType) {
    switch (rawType.toLowerCase()) {
      case 'fresh':
      case 'stok':
        return t.success;
      case 'chip':
        return t.warning;
      case 'display':
        return t.primaryAccent;
      case 'kosong':
        return t.danger;
      default:
        return t.textMutedStrong;
    }
  }

  Widget _buildFilterCard({
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
            color: selected ? t.primaryAccentSoft : t.surface1,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: selected
                  ? t.primaryAccent.withValues(alpha: 0.28)
                  : t.surface3,
            ),
          ),
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: selected ? t.primaryAccent : t.textMutedStrong,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryBody() {
    if (_summaryRows.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.enableRecommendationAction) ...[
            _buildOrderEntryActions(),
            const SizedBox(height: 14),
          ],
          _buildCompactSectionCard(
            childKey: 'summary-empty',
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 18),
              child: Center(
                child: Text(
                  'Tidak ada data stok',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final groupedRows = _sortedSummaryRows();
    final filteredRows = _filteredSummaryRows();
    final emptyCount = groupedRows
        .where((row) => _toInt(row['qty']) <= 0)
        .length;
    final readyCount = groupedRows
        .where((row) => _toInt(row['qty']) > 0)
        .fold<int>(0, (total, row) => total + _toInt(row['qty']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.enableRecommendationAction) ...[
          _buildOrderEntryActions(),
          const SizedBox(height: 14),
        ],
        _buildCompactSectionCard(
          childKey: 'summary-table',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isManagerMode) ...[
                Row(
                  children: [
                    _buildManagerPrimaryCard(
                      value: 'stock',
                      label: 'Stok Fresh',
                      icon: Icons.inventory_2_outlined,
                      tone: t.primaryAccent,
                    ),
                    const SizedBox(width: 8),
                    _buildManagerPrimaryCard(
                      value: 'chip',
                      label: 'Stok Chip',
                      icon: Icons.memory_outlined,
                      tone: t.warning,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              if (_isSummaryMode)
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: _copySummaryTable,
                    tooltip: 'Copy ringkasan',
                    icon: const Icon(Icons.copy_all_rounded, size: 20),
                  ),
                ),
              Row(
                children: [
                  _buildFilterCard(
                    value: 'all',
                    label: 'Semua',
                    selectedValue: _summaryFilter,
                    onSelected: (value) =>
                        setState(() => _summaryFilter = value),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterCard(
                    value: 'empty',
                    label: 'Kosong $emptyCount',
                    selectedValue: _summaryFilter,
                    onSelected: (value) =>
                        setState(() => _summaryFilter = value),
                  ),
                  const SizedBox(width: 6),
                  _buildFilterCard(
                    value: 'ready',
                    label: 'Ready $readyCount',
                    selectedValue: _summaryFilter,
                    onSelected: (value) =>
                        setState(() => _summaryFilter = value),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
                decoration: BoxDecoration(
                  color: t.background,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: t.surface3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildMonoText(
                      'DAFTAR STOK',
                      color: t.primaryAccent,
                      weight: FontWeight.w800,
                      size: 11,
                    ),
                    const SizedBox(height: 6),
                    if (filteredRows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: _buildMonoText(
                          'TIDAK ADA DATA UNTUK FILTER INI',
                          color: t.textMuted,
                        ),
                      )
                    else
                      ...() {
                        final widgets = <Widget>[];
                        String? lastType;
                        for (var i = 0; i < filteredRows.length; i++) {
                          final row = filteredRows[i];
                          final currentType = '${row['tipe'] ?? ''}'.trim();
                          if (currentType != lastType) {
                            if (widgets.isNotEmpty) {
                              widgets.add(const SizedBox(height: 8));
                            }
                            widgets.add(
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: _summaryTypeTone(
                                    currentType,
                                  ).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: _summaryTypeTone(
                                      currentType,
                                    ).withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Text(
                                  _summaryTypeLabel(currentType),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w900,
                                    color: _summaryTypeTone(currentType),
                                  ),
                                ),
                              ),
                            );
                            widgets.add(const SizedBox(height: 6));
                            lastType = currentType;
                          }
                          widgets.add(
                            _buildCompactStockRow(
                              row,
                              showDivider: i != filteredRows.length - 1,
                            ),
                          );
                        }
                        return widgets;
                      }(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOrderEntryActions() {
    final canOpen = (_resolvedStoreId ?? '').isNotEmpty;
    final canOpenGroup = _hasConfiguredGroupOrder;
    final showStoreActions = canOpen && !canOpenGroup;
    return _buildCompactSectionCard(
      childKey: 'order-entry-actions',
      child: Column(
        children: [
          if (showStoreActions)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pushNamed(
                      'sator-rekomendasi',
                      pathParameters: {'storeId': _resolvedStoreId!},
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Rekom Toko',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SellInOrderComposerPage(
                          mode: SellInOrderComposerMode.manual,
                          storeId: _resolvedStoreId,
                        ),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Order Toko',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          if (canOpenGroup) ...[
            if (showStoreActions) const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.pushNamed(
                      'sator-rekomendasi-group',
                      pathParameters: {'groupId': _groupId!},
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Order Rekomendasi',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SellInOrderComposerPage(
                          mode: SellInOrderComposerMode.manual,
                          groupId: _groupId,
                        ),
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(double.infinity, 34),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'Order Manual',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionStat(String label, String value, Color tone) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tone.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tone.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: t.textMuted,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: tone,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSimpleCard({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ListTile(
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }

  Widget _buildCompactSectionCard({
    required String childKey,
    required Widget child,
  }) {
    return Container(
      key: ValueKey(childKey),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: child,
    );
  }

  Widget _buildActionTabChip({
    required String value,
    required String label,
    int? count,
    required Color tone,
  }) {
    final selected = _actionTab == value;
    final chipLabel = count == null ? label : '$label $count';
    return ChoiceChip(
      label: Text(chipLabel),
      selected: selected,
      onSelected: (_) => setState(() => _actionTab = value),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        color: selected ? tone : t.textMutedStrong,
      ),
      backgroundColor: t.surface1,
      selectedColor: tone.withValues(alpha: 0.12),
      side: BorderSide(
        color: selected ? tone.withValues(alpha: 0.28) : t.surface3,
      ),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _buildManagerPrimaryCard({
    required String value,
    required String label,
    required IconData icon,
    required Color tone,
  }) {
    final selected = _managerTab == value;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _managerTab = value),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 9),
          decoration: BoxDecoration(
            color: selected ? tone.withValues(alpha: 0.12) : t.surface1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? tone.withValues(alpha: 0.3) : t.surface3,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? tone.withValues(alpha: 0.14) : t.background,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 15, color: tone),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: selected ? tone : t.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDateTime(dynamic value) {
    if (value == null) return '-';
    try {
      return DateFormat(
        'dd MMM yyyy, HH:mm',
        'id_ID',
      ).format(DateTime.parse('$value').toLocal());
    } catch (_) {
      return '$value';
    }
  }

  Widget _buildSoldChipRequestCard() {
    return _buildCompactSectionCard(
      childKey: 'sold-chip-form',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Barang sudah terjual di sistem, tapi fisiknya masih ada di toko.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _soldChipImeiController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'IMEI',
              hintText: 'Scan / input IMEI',
              filled: true,
              fillColor: t.background,
              suffixIcon: IconButton(
                tooltip: 'Scan barcode',
                onPressed: _scanSoldChipBarcode,
                icon: Icon(Icons.qr_code_scanner, color: t.primaryAccent),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.primaryAccent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _soldChipReasonController,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Alasan',
              hintText: 'Kenapa dijadikan chip',
              filled: true,
              fillColor: t.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.primaryAccent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanSoldChipBarcode,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _isSubmittingSoldChipRequest
                      ? null
                      : _submitSoldChipRequest,
                  child: Text(
                    _isSubmittingSoldChipRequest ? 'Mengirim...' : 'Kirim',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMoveOutCard() {
    final pendingRows = _pendingClaimRows
        .where((row) => '${row['move_status'] ?? ''}' == 'pending')
        .toList();
    final completedRows = _pendingClaimRows
        .where((row) => '${row['move_status'] ?? ''}' == 'claimed')
        .toList();

    return _buildCompactSectionCard(
      childKey: 'move-out-form',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tandai barang yang sudah tidak ada di toko ini karena dipindahkan ke toko lain.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _moveOutImeiController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'IMEI',
              hintText: 'Scan / input IMEI',
              filled: true,
              fillColor: t.background,
              suffixIcon: IconButton(
                tooltip: 'Scan barcode',
                onPressed: _scanMoveOutBarcode,
                icon: Icon(Icons.qr_code_scanner, color: t.primaryAccent),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.primaryAccent),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _moveOutNoteController,
            minLines: 2,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: 'Catatan',
              hintText: 'Contoh: dipindahkan ke toko lain',
              filled: true,
              fillColor: t.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.surface3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: t.primaryAccent),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _scanMoveOutBarcode,
                  icon: const Icon(Icons.qr_code_scanner, size: 18),
                  label: const Text('Scan'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: _isSubmittingMoveOut ? null : _submitMoveOut,
                  child: Text(
                    _isSubmittingMoveOut ? 'Menyimpan...' : 'Tandai Keluar',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_pendingClaimRows.isEmpty)
            _buildSimpleCard(
              title: 'Belum ada barang pindahan',
              subtitle: 'Barang yang ditandai keluar akan tampil di sini.',
            )
          else ...[
            if (pendingRows.isNotEmpty) ...[
              Text(
                'Menunggu Claim',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: t.primaryAccent,
                ),
              ),
              const SizedBox(height: 8),
              ...pendingRows.map(
                (row) => _buildSimpleCard(
                  title: _productName(row),
                  subtitle:
                      'IMEI ${row['imei']} • ${row['relocation_note']?.toString().trim().isEmpty == true ? 'Menunggu claim toko penerima' : row['relocation_note']}',
                ),
              ),
            ],
            if (completedRows.isNotEmpty) ...[
              if (pendingRows.isNotEmpty) const SizedBox(height: 8),
              Text(
                'Sudah Diambil Toko Lain',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: t.success,
                ),
              ),
              const SizedBox(height: 8),
              ...completedRows.map(
                (row) => _buildSimpleCard(
                  title: _productName(row),
                  subtitle:
                      'IMEI ${row['imei']} • ${row['relocation_note']?.toString().trim().isEmpty == true ? 'Sudah selesai dipindahkan' : row['relocation_note']}',
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildActionRequestsPanel() {
    return _buildCompactSectionCard(
      childKey: 'action-requests',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_pendingChipRequestRows.isEmpty)
            _buildSimpleCard(
              title: 'Belum ada request chip',
              subtitle: 'Request baru akan tampil di sini.',
            )
          else
            ..._pendingChipRequestRows.map(
              (row) => _buildSimpleCard(
                title: _productName(row),
                subtitle:
                    'IMEI ${row['imei']}'
                    ' • ${row['request_type'] == 'sold_to_chip' ? 'Sold to chip' : 'Fresh to chip'}'
                    ' • ${row['reason']?.toString().trim().isEmpty == true ? 'Menunggu review' : row['reason']}',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionChipStockPanel() {
    return _buildCompactSectionCard(
      childKey: 'action-chip-stock',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_chipRows.isEmpty)
            _buildSimpleCard(
              title: 'Belum ada stok chip aktif',
              subtitle: 'Stok chip yang disetujui akan muncul di sini.',
            )
          else
            ..._chipRows.map(
              (row) => _buildSimpleCard(
                title: _productName(row),
                subtitle:
                    'IMEI ${row['imei']} • ${('${row['chip_reason'] ?? ''}').trim().isEmpty ? 'Chip aktif' : row['chip_reason']}',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChipOverviewBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildActionStat('Chip Aktif', '${_chipRows.length}', t.warning),
            const SizedBox(width: 8),
            _buildActionStat(
              'Pending',
              '${_pendingChipRequestRows.length}',
              t.success,
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildCompactSectionCard(
          childKey: 'manager-chip-overview',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_chipRows.isEmpty)
                _buildSimpleCard(
                  title: 'Belum ada stok chip aktif',
                  subtitle: 'Stok chip aktif toko ini akan tampil di sini.',
                )
              else
                ..._chipRows.asMap().entries.map(
                  (entry) => _buildCompactChipCard(
                    entry.value,
                    showDivider: entry.key != _chipRows.length - 1,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactChipCard(
    Map<String, dynamic> row, {
    bool showDivider = true,
  }) {
    final requester = ('${row['promotor_name'] ?? ''}').trim();
    final approver = ('${row['approver_name'] ?? ''}').trim();
    final reason = ('${row['chip_reason'] ?? ''}').trim();

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: t.surface3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _productName(row),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            'IMEI ${row['imei']}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: t.textMutedStrong,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Input ${requester.isEmpty ? '-' : requester} • Approve ${approver.isEmpty ? '-' : approver}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            '${_formatDateTime(row['chip_approved_at'])}${reason.isEmpty ? '' : ' • $reason'}',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildManagerBody() {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _managerTab == 'chip'
          ? _buildChipOverviewBody()
          : _buildSummaryBody(),
    );
  }

  Widget _buildActionHistoryPanel() {
    return _buildCompactSectionCard(
      childKey: 'action-history',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_movementRows.isEmpty)
            _buildSimpleCard(
              title: 'Belum ada riwayat tindakan',
              subtitle: 'Riwayat stok akan muncul di sini.',
            )
          else
            ..._movementRows.map(
              (row) => _buildSimpleCard(
                title: _movementLabel('${row['movement_type'] ?? '-'}'),
                subtitle:
                    '${_productName(row)} • IMEI ${row['imei']}'
                    '${('${row['note'] ?? ''}').trim().isEmpty ? '' : ' • ${row['note']}'}',
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildActionBody() {
    Widget activeContent;
    switch (_actionTab) {
      case 'move-out':
        activeContent = _buildMoveOutCard();
        break;
      case 'requests':
        activeContent = _buildActionRequestsPanel();
        break;
      case 'chips':
        activeContent = _buildActionChipStockPanel();
        break;
      case 'history':
        activeContent = _buildActionHistoryPanel();
        break;
      default:
        activeContent = _buildSoldChipRequestCard();
        break;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildActionStat(
              'Menunggu',
              '$_pendingMoveOutCount',
              t.primaryAccent,
            ),
            const SizedBox(width: 8),
            _buildActionStat(
              'Request',
              '${_pendingChipRequestRows.length}',
              t.success,
            ),
            const SizedBox(width: 8),
            _buildActionStat('Selesai', '$_completedMoveOutCount', t.warning),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _buildActionTabChip(
              value: 'move-out',
              label: 'Pindah',
              count: _pendingClaimRows.length,
              tone: t.primaryAccent,
            ),
            _buildActionTabChip(
              value: 'sold-chip',
              label: 'Chip',
              tone: t.primaryAccent,
            ),
            _buildActionTabChip(
              value: 'requests',
              label: 'Request',
              count: _pendingChipRequestRows.length,
              tone: t.success,
            ),
            _buildActionTabChip(
              value: 'chips',
              label: 'Aktif',
              count: _chipRows.length,
              tone: t.warning,
            ),
            _buildActionTabChip(
              value: 'history',
              label: 'Riwayat',
              count: _movementRows.length,
              tone: t.textPrimary,
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: activeContent,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeName = (_storeName ?? '').trim();
    return PopScope(
      canPop: !(_isManagerMode && _managerTab == 'chip'),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_isManagerMode && _managerTab == 'chip') {
          setState(() => _managerTab = 'stock');
        }
      },
      child: Scaffold(
        backgroundColor: t.background,
        appBar: AppBar(
          toolbarHeight: storeName.isEmpty ? kToolbarHeight : 72,
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_pageTitle()),
              if (storeName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  storeName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: t.textMutedStrong,
                    height: 1.15,
                  ),
                ),
              ],
            ],
          ),
          backgroundColor: t.background,
          foregroundColor: t.textPrimary,
          surfaceTintColor: t.background,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_isSummaryMode) _buildSummaryBody(),
                    if (_isManagerMode) _buildManagerBody(),
                    if (_isActionMode) _buildActionBody(),
                  ],
                ),
              ),
      ),
    );
  }
}
