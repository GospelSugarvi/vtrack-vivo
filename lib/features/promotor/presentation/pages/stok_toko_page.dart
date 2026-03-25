import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/features/sator/presentation/pages/sell_in/sell_in_order_composer_page.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class StokTokoPage extends StatefulWidget {
  final String? storeId;
  final String mode;
  final bool enableRecommendationAction;

  const StokTokoPage({
    super.key,
    this.storeId,
    this.mode = 'all',
    this.enableRecommendationAction = false,
  });

  @override
  State<StokTokoPage> createState() => _StokTokoPageState();
}

class _StokTokoPageState extends State<StokTokoPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isProcessingClaim = false;
  String? _resolvedStoreId;
  String? _storeName;
  String? _groupId;
  String? _groupName;
  int _groupStoreCount = 0;
  String _promotorName = 'Promotor';
  List<Map<String, dynamic>> _summaryRows = const [];
  List<Map<String, dynamic>> _chipRows = const [];
  List<Map<String, dynamic>> _pendingClaimRows = const [];
  List<Map<String, dynamic>> _movementRows = const [];
  List<Map<String, dynamic>> _pendingChipRequestRows = const [];
  String _summaryFilter = 'all';

  bool get _isActionMode => widget.mode == 'actions';
  bool get _isSummaryMode => widget.mode == 'summary' || widget.mode == 'all';

  @override
  void initState() {
    super.initState();
    _loadData();
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

      List<Map<String, dynamic>> summaryRows = const [];
      List<Map<String, dynamic>> chipRows = const [];
      List<Map<String, dynamic>> pendingClaimRows = const [];
      List<Map<String, dynamic>> movementRows = const [];
      List<Map<String, dynamic>> pendingChipRequestRows = const [];

      if (_isSummaryMode) {
        summaryRows = await _loadSummaryRows(resolvedStoreId);
      }

      if (_isActionMode) {
        chipRows = await _loadChipRows(resolvedStoreId);
        pendingClaimRows = await _loadPendingClaimRows();
        movementRows = await _loadMovementRows(resolvedStoreId);
        pendingChipRequestRows = await _loadPendingChipRequests(
          resolvedStoreId,
        );
      }

      if (!mounted) return;
      setState(() {
        _resolvedStoreId = resolvedStoreId;
        _storeName = storeContext['store_name']?.toString();
        _groupId = storeContext['group_id']?.toString();
        _groupName = storeContext['group_name']?.toString();
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
    final row = await _supabase
        .from('stores')
        .select('store_name, group_id, store_groups(group_name)')
        .eq('id', storeId)
        .maybeSingle();
    final group = row?['store_groups'] is Map
        ? Map<String, dynamic>.from(row?['store_groups'] as Map)
        : <String, dynamic>{};
    final rawGroupId = row?['group_id']?.toString();
    final groupId = rawGroupId == null || rawGroupId.trim().isEmpty
        ? null
        : rawGroupId.trim();
    int groupStoreCount = 0;
    if (groupId != null) {
      final countRows = await _supabase
          .from('stores')
          .select('id')
          .eq('group_id', groupId)
          .isFilter('deleted_at', null);
      groupStoreCount = List<Map<String, dynamic>>.from(countRows).length;
    }
    return {
      'store_name': row?['store_name']?.toString(),
      'group_id': groupId,
      'group_name': group['group_name']?.toString(),
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

  Future<List<Map<String, dynamic>>> _loadSummaryRows(String storeId) async {
    final variantRows = List<Map<String, dynamic>>.from(
      await _supabase
          .from('product_variants')
          .select(
            'id, ram_rom, color, products!product_id(model_name, network_type, status)',
          )
          .eq('active', true),
    );

    final activeVariants = variantRows.where((row) {
      final product = _asMap(row['products']);
      return '${product['status'] ?? 'active'}' == 'active';
    }).toList();

    try {
      final stockRows = await _supabase
          .from('stok')
          .select(
            'variant_id, imei, tipe_stok, product_variants!variant_id(ram_rom, color, products!product_id(model_name, network_type))',
          )
          .eq('store_id', storeId)
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
          'variant_id, quantity, product_variants!variant_id(ram_rom, color, products!product_id(model_name, network_type))',
        )
        .eq('store_id', storeId)
        .order('quantity', ascending: false);

    final normalizedInventory = List<Map<String, dynamic>>.from(inventoryRows)
        .map((row) {
          final variant = _asMap(row['product_variants']);
          final product = _asMap(variant['products']);
          return {
            'variant_id': (row['variant_id'] ?? '').toString(),
            'kategori': (product['model_name'] ?? 'Produk').toString(),
            'network_type': (product['network_type'] ?? '').toString(),
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
        'tipe': 'kosong',
        'ram_rom': (row['ram_rom'] ?? '').toString(),
        'color': (row['color'] ?? '').toString(),
        'imei': '-',
        'qty': 0,
      });
    }

    return normalizedInventory;
  }

  Future<List<Map<String, dynamic>>> _loadChipRows(String storeId) async {
    try {
      final response = await _supabase.rpc(
        'get_store_chip_summary',
        params: {'p_store_id': storeId},
      );
      if (response is Map) {
        return List<Map<String, dynamic>>.from(response['items'] ?? const []);
      }
    } catch (_) {}

    final rows = await _supabase
        .from('stok')
        .select(
          'id, imei, chip_reason, chip_approved_at, product_variants!variant_id(ram_rom, color, products!product_id(model_name, network_type))',
        )
        .eq('store_id', storeId)
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
      };
    }).toList();
  }

  Future<List<Map<String, dynamic>>> _loadPendingClaimRows() async {
    final rows = await _supabase
        .from('stok')
        .select(
          'id, imei, variant_id, relocation_note, relocation_reported_at, product_variants!variant_id(ram_rom, color, products!product_id(model_name, network_type))',
        )
        .eq('is_sold', false)
        .isFilter('store_id', null)
        .eq('relocation_status', 'pending_claim')
        .order('relocation_reported_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows).map((row) {
      final variant = _asMap(row['product_variants']);
      final product = _asMap(variant['products']);
      return {
        'stok_id': row['id']?.toString(),
        'imei': (row['imei'] ?? '-').toString(),
        'variant_id': row['variant_id']?.toString(),
        'model_name': (product['model_name'] ?? 'Produk').toString(),
        'network_type': (product['network_type'] ?? '').toString(),
        'ram_rom': (variant['ram_rom'] ?? '').toString(),
        'color': (variant['color'] ?? '').toString(),
        'relocation_note': (row['relocation_note'] ?? '').toString(),
        'relocation_reported_at': row['relocation_reported_at'],
      };
    }).toList();
  }

  Future<void> _claimPendingStock(Map<String, dynamic> row) async {
    final imei = '${row['imei'] ?? ''}'.trim();
    final variantId = '${row['variant_id'] ?? ''}'.trim();
    if (imei.isEmpty) return;

    if (!mounted) return;
    setState(() => _isProcessingClaim = true);
    try {
      await _supabase.rpc(
        'claim_relocated_stock',
        params: {
          'p_imei': imei,
          'p_variant_id': variantId.isEmpty ? null : variantId,
          'p_note': 'Claim dari menu aksi stok',
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stok IMEI $imei berhasil diklaim'),
          backgroundColor: t.success,
        ),
      );
      setState(() => _isProcessingClaim = false);
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal klaim stok: $e'),
          backgroundColor: t.danger,
        ),
      );
      setState(() => _isProcessingClaim = false);
    }
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
    String storeId,
  ) async {
    final rows = await _supabase
        .from('stock_chip_requests')
        .select(
          'id, reason, requested_at, stok:stok_id(imei, product_variants!variant_id(ram_rom, color, products!product_id(model_name, network_type)))',
        )
        .eq('store_id', storeId)
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
      };
    }).toList();
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

  String _pageTitle() {
    switch (widget.mode) {
      case 'summary':
        return 'Ringkasan Stok';
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
    final rows = List<Map<String, dynamic>>.from(_summaryRows);
    rows.sort((a, b) {
      final statusCompare = _summaryStatusRank(
        a,
      ).compareTo(_summaryStatusRank(b));
      if (statusCompare != 0) return statusCompare;
      final kategori = _sortByText(
        '${a['kategori'] ?? ''} ${a['network_type'] ?? ''}',
        '${b['kategori'] ?? ''} ${b['network_type'] ?? ''}',
      );
      if (kategori != 0) return kategori;
      final tipe = _sortByText(a['tipe'], b['tipe']);
      if (tipe != 0) return tipe;
      final warna = _sortByText(a['color'], b['color']);
      if (warna != 0) return warna;
      final ramRom = _sortByText(a['ram_rom'], b['ram_rom']);
      if (ramRom != 0) return ramRom;
      return _sortByText(a['imei'], b['imei']);
    });
    return rows;
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

  Widget _terminalCell(
    String value, {
    required int flex,
    Color? color,
    FontWeight weight = FontWeight.w600,
    double size = 10,
    TextAlign textAlign = TextAlign.left,
  }) {
    return Expanded(
      flex: flex,
      child: _buildMonoText(
        value,
        color: color,
        weight: weight,
        size: size,
        textAlign: textAlign,
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
    final tipe = '${row['tipe'] ?? '-'}'.toUpperCase();
    final warna = '${row['color'] ?? '-'}';
    final ramRom = '${row['ram_rom'] ?? '-'}';
    final imei = '${row['imei'] ?? '-'}';
    final qty = _toInt(row['qty']);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      decoration: BoxDecoration(
        border: showDivider
            ? Border(bottom: BorderSide(color: t.surface3))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMonoText(
            kategori,
            color: t.textPrimary,
            weight: FontWeight.w800,
            size: 12,
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _terminalCell(
                tipe,
                flex: 2,
                color: t.primaryAccent,
                weight: FontWeight.w700,
              ),
              _terminalCell(
                warna,
                flex: 2,
                color: t.primaryAccent,
                weight: FontWeight.w700,
              ),
              _terminalCell(
                ramRom,
                flex: 2,
                color: t.primaryAccent,
                weight: FontWeight.w700,
              ),
              _terminalCell(imei, flex: 5, color: t.textMuted),
              SizedBox(
                width: 32,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _buildMonoText(
                    '$qty',
                    color: t.textPrimary,
                    weight: FontWeight.w800,
                    size: 10,
                    textAlign: TextAlign.right,
                  ),
                ),
              ),
            ],
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

  Widget _buildSectionTitle(String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: t.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String value,
    required String label,
    required String selectedValue,
    required ValueChanged<String> onSelected,
  }) {
    final selected = value == selectedValue;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(value),
      labelStyle: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w800,
        color: selected ? t.primaryAccent : t.textMutedStrong,
      ),
      backgroundColor: t.surface1,
      selectedColor: t.primaryAccentSoft,
      side: BorderSide(
        color: selected ? t.primaryAccent.withValues(alpha: 0.28) : t.surface3,
      ),
      visualDensity: VisualDensity.compact,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }

  Widget _buildSummaryBody() {
    if (_summaryRows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.enableRecommendationAction) ...[
              _buildOrderEntryActions(),
              const SizedBox(height: 12),
            ],
            _buildMonoText('TIDAK ADA DATA STOK', color: t.textMuted),
          ],
        ),
      );
    }

    final filteredRows = _filteredSummaryRows();
    final emptyCount = _summaryRows
        .where((row) => _toInt(row['qty']) <= 0)
        .length;
    final readyCount = _summaryRows
        .where((row) => _toInt(row['qty']) > 0)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.enableRecommendationAction) ...[
          _buildOrderEntryActions(),
          const SizedBox(height: 16),
        ],
        _buildSectionTitle('Tabel Stok', ''),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildFilterChip(
                value: 'all',
                label: 'Semua ${_summaryRows.length}',
                selectedValue: _summaryFilter,
                onSelected: (value) => setState(() => _summaryFilter = value),
              ),
              _buildFilterChip(
                value: 'empty',
                label: 'Kosong $emptyCount',
                selectedValue: _summaryFilter,
                onSelected: (value) => setState(() => _summaryFilter = value),
              ),
              _buildFilterChip(
                value: 'ready',
                label: 'Ready $readyCount',
                selectedValue: _summaryFilter,
                onSelected: (value) => setState(() => _summaryFilter = value),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMonoText(
                'KATEGORI',
                color: t.primaryAccent,
                weight: FontWeight.w800,
                size: 11,
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  _terminalCell(
                    'TIPE',
                    flex: 2,
                    color: t.primaryAccent,
                    weight: FontWeight.w800,
                  ),
                  _terminalCell(
                    'WARNA',
                    flex: 2,
                    color: t.primaryAccent,
                    weight: FontWeight.w800,
                  ),
                  _terminalCell(
                    'RAM',
                    flex: 2,
                    color: t.primaryAccent,
                    weight: FontWeight.w800,
                  ),
                  _terminalCell(
                    'IMEI',
                    flex: 5,
                    color: t.primaryAccent,
                    weight: FontWeight.w800,
                  ),
                  SizedBox(
                    width: 32,
                    child: _buildMonoText(
                      'QTY',
                      color: t.primaryAccent,
                      weight: FontWeight.w800,
                      size: 10,
                      textAlign: TextAlign.right,
                    ),
                  ),
                ],
              ),
              _buildMonoText('-' * 44, color: t.surface4),
              if (filteredRows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: _buildMonoText(
                    'TIDAK ADA DATA UNTUK FILTER INI',
                    color: t.textMuted,
                  ),
                )
              else
                ...filteredRows.asMap().entries.map(
                  (entry) => _buildCompactStockRow(
                    entry.value,
                    showDivider: entry.key != filteredRows.length - 1,
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
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: canOpen
                      ? () => context.pushNamed(
                          'sator-rekomendasi',
                          pathParameters: {'storeId': _resolvedStoreId!},
                        )
                      : null,
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: canOpen
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SellInOrderComposerPage(
                              mode: SellInOrderComposerMode.manual,
                              storeId: _resolvedStoreId,
                            ),
                          ),
                        )
                      : null,
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
          if (canOpenGroup) ...[
            const SizedBox(height: 8),
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
                    child: Text(
                      (_groupName ?? '').trim().isNotEmpty
                          ? 'Rekom Grup'
                          : 'Rekom Grup',
                      style: const TextStyle(
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
                      'Order Grup',
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
      child: ListTile(
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: trailing,
      ),
    );
  }

  Widget _buildActionBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _buildActionStat('Stok chip', '${_chipRows.length}', t.warning),
            const SizedBox(width: 8),
            _buildActionStat(
              'Pending claim',
              '${_pendingClaimRows.length}',
              t.primaryAccent,
            ),
            const SizedBox(width: 8),
            _buildActionStat(
              'Request chip',
              '${_pendingChipRequestRows.length}',
              t.success,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionTitle(
          'Request Chip Pending',
          'Daftar pengajuan chip yang masih menunggu review.',
        ),
        if (_pendingChipRequestRows.isEmpty)
          _buildSimpleCard(
            title: 'Belum ada request chip pending',
            subtitle: 'Permintaan ubah stok ke chip akan muncul di sini.',
          )
        else
          ..._pendingChipRequestRows.map(
            (row) => _buildSimpleCard(
              title: _productName(row),
              subtitle:
                  'IMEI ${row['imei']} • ${row['reason']?.toString().trim().isEmpty == true ? 'Menunggu review' : row['reason']}',
            ),
          ),
        const SizedBox(height: 10),
        _buildSectionTitle(
          'Pending Claim',
          'Stok yang sedang menunggu diklaim kembali ke toko.',
        ),
        if (_pendingClaimRows.isEmpty)
          _buildSimpleCard(
            title: 'Tidak ada stok pending claim',
            subtitle: 'Stok yang dipindahkan keluar akan tampil di sini.',
          )
        else
          ..._pendingClaimRows.map(
            (row) => _buildSimpleCard(
              title: _productName(row),
              subtitle:
                  'IMEI ${row['imei']} • ${row['relocation_note']?.toString().trim().isEmpty == true ? 'Menunggu klaim' : row['relocation_note']}',
              trailing: FilledButton(
                onPressed: _isProcessingClaim
                    ? null
                    : () => _claimPendingStock(row),
                child: const Text('Klaim'),
              ),
            ),
          ),
        const SizedBox(height: 10),
        _buildSectionTitle('Stok Chip', 'Daftar stok chip aktif di toko ini.'),
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
        const SizedBox(height: 10),
        _buildSectionTitle(
          'Riwayat Tindakan',
          'Pergerakan stok terbaru untuk toko ini.',
        ),
        if (_movementRows.isEmpty)
          _buildSimpleCard(
            title: 'Belum ada riwayat tindakan',
            subtitle: 'Perpindahan atau perubahan stok akan tercatat di sini.',
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(
        title: Row(
          children: [
            Text(_pageTitle()),
            if ((_storeName ?? '').trim().isNotEmpty) ...[
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _storeName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: t.textMuted,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: _isSummaryMode
            ? [
                IconButton(
                  onPressed: _isLoading ? null : _copySummaryTable,
                  tooltip: 'Copy ringkasan',
                  icon: const Icon(Icons.copy_all_rounded),
                ),
              ]
            : null,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_isSummaryMode) _buildSummaryBody(),
                  if (_isActionMode) _buildActionBody(),
                ],
              ),
            ),
    );
  }
}
