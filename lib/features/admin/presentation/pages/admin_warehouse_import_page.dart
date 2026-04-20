import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/foundation/app_colors.dart';
import '../../data/warehouse_excel_import_parser.dart';

class AdminWarehouseImportPage extends StatefulWidget {
  const AdminWarehouseImportPage({super.key});

  @override
  State<AdminWarehouseImportPage> createState() =>
      _AdminWarehouseImportPageState();
}

class _AdminWarehouseImportPageState extends State<AdminWarehouseImportPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isBootstrapping = true;
  bool _isParsing = false;
  bool _isSaving = false;
  String? _errorMessage;
  WarehouseImportPreview? _preview;
  List<Map<String, dynamic>> _stores = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _groups = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _variants = const <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _recentRuns = const <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    if (mounted) {
      setState(() {
        _isBootstrapping = true;
        _errorMessage = null;
        _preview = null;
      });
    }

    try {
      final stores = await _supabase
          .from('stores')
          .select(
            'id, store_name, area, group_id, store_groups(group_name, is_spc, stock_handling_mode)',
          )
          .isFilter('deleted_at', null)
          .order('store_name');

      final groups = await _supabase
          .from('store_groups')
          .select('id, group_name, is_spc, stock_handling_mode')
          .isFilter('deleted_at', null)
          .order('group_name');

      final variants = await _supabase
          .from('product_variants')
          .select(
            'id, product_id, ram_rom, color, products(model_name, network_type)',
          )
          .order('products(model_name)');

      final recentRuns = await _supabase
          .from('warehouse_import_runs')
          .select(
            'id, file_name, status, total_rows, ready_rows, inserted_store_rows, staged_group_rows, duplicate_imei_rows, created_at',
          )
          .order('created_at', ascending: false)
          .limit(10);

      if (!mounted) return;
      setState(() {
        _stores = List<Map<String, dynamic>>.from(stores);
        _groups = List<Map<String, dynamic>>.from(groups);
        _variants = variants.map<Map<String, dynamic>>((row) {
          final map = Map<String, dynamic>.from(row);
          final product = map['products'] is Map
              ? Map<String, dynamic>.from(map['products'] as Map)
              : const <String, dynamic>{};
          return <String, dynamic>{
            'id': map['id'],
            'product_id': map['product_id'],
            'ram_rom': map['ram_rom'],
            'color': map['color'],
            'model_name': product['model_name'],
            'network_type': product['network_type'],
          };
        }).toList();
        _recentRuns = List<Map<String, dynamic>>.from(recentRuns);
        _isBootstrapping = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isBootstrapping = false;
        _errorMessage = '$error';
      });
    }
  }

  Future<void> _pickExcelFile() async {
    setState(() {
      _isParsing = true;
      _errorMessage = null;
      _preview = null;
    });

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (!mounted) return;
        setState(() => _isParsing = false);
        return;
      }

      final file = result.files.single;
      final bytes = await _resolveBytes(file);
      final preview = WarehouseImportParser.parse(
        bytes: bytes,
        fileName: file.name,
        stores: _stores,
        groups: _groups,
        variants: _variants,
      );

      if (!mounted) return;
      setState(() {
        _preview = preview;
        _isParsing = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isParsing = false;
        _errorMessage = '$error';
      });
    }
  }

  void _resetPreview() {
    setState(() {
      _preview = null;
      _errorMessage = null;
      _isParsing = false;
      _isSaving = false;
    });
  }

  Future<void> _savePreview() async {
    final preview = _preview;
    if (preview == null || _isSaving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Simpan Import'),
        content: Text(
          'Baris ready akan diproses. Single store akan masuk ke stok toko, sedangkan shared/distributed group dicatat sebagai staging. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      final payload = preview.rows.map((row) => row.toCommitJson()).toList();
      final result = await _supabase.rpc(
        'commit_warehouse_import',
        params: {'p_file_name': preview.fileName, 'p_rows': payload},
      );

      if (!mounted) return;
      final map = result is Map<String, dynamic>
          ? result
          : Map<String, dynamic>.from(result as Map);
      final runId = '${map['run_id'] ?? '-'}';
      final inserted = map['inserted_store_rows'] ?? 0;
      final staged = map['staged_group_rows'] ?? 0;
      final duplicates = map['duplicate_imei_rows'] ?? 0;

      setState(() => _isSaving = false);
      await _bootstrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Import tersimpan. Run: $runId • stok masuk: $inserted • staging grup: $staged • duplicate IMEI: $duplicates',
          ),
          backgroundColor: AppColors.success,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _errorMessage = '$error';
      });
    }
  }

  Future<Uint8List> _resolveBytes(PlatformFile file) async {
    if (file.bytes != null) {
      return file.bytes!;
    }
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const FormatException('File Excel tidak bisa dibaca');
    }
    return File(path).readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Import Gudang Excel'),
        actions: [
          IconButton(
            onPressed: _bootstrap,
            icon: const Icon(Icons.refresh),
            tooltip: 'Reload master data',
          ),
        ],
      ),
      body: _isBootstrapping
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildIntroCard(),
                const SizedBox(height: 16),
                _buildActionBar(),
                const SizedBox(height: 16),
                _buildHistoryCard(),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 16),
                  _buildErrorCard(),
                ],
                if (_preview != null) ...[
                  const SizedBox(height: 16),
                  _buildSummaryCards(_preview!.summary),
                  const SizedBox(height: 16),
                  _buildPreviewTable(_preview!),
                ],
              ],
            ),
    );
  }

  Widget _buildIntroCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: const Text(
          'Preview Import Stok Gudang',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }

  Widget _buildActionBar() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: _isParsing || _isSaving ? null : _pickExcelFile,
                  icon: _isParsing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(
                    _isParsing ? 'Membaca Excel...' : 'Pilih File Excel',
                  ),
                ),
                if (_preview != null)
                  ElevatedButton.icon(
                    onPressed: _isParsing || _isSaving ? null : _savePreview,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save),
                    label: Text(_isSaving ? 'Menyimpan...' : 'Save Stok'),
                  ),
                if (_preview != null)
                  OutlinedButton.icon(
                    onPressed: _isParsing || _isSaving ? null : _pickExcelFile,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Ganti File'),
                  ),
                if (_preview != null || _errorMessage != null)
                  OutlinedButton.icon(
                    onPressed: _isParsing || _isSaving ? null : _resetPreview,
                    icon: const Icon(Icons.close),
                    label: const Text('Reset'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Master aktif: ${_stores.length} toko • ${_groups.length} grup • ${_variants.length} varian',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard() {
    return Card(
      color: AppColors.danger.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          _errorMessage ?? 'Terjadi kesalahan',
          style: const TextStyle(color: AppColors.danger),
        ),
      ),
    );
  }

  Widget _buildHistoryCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'History Save Stok',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (_recentRuns.isEmpty)
              const Text(
                'Belum ada history save stok.',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              ..._recentRuns.map(_buildHistoryItem),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> run) {
    final runId = '${run['id'] ?? '-'}';
    final fileName = '${run['file_name'] ?? '-'}';
    final status = '${run['status'] ?? '-'}';
    final totalRows = run['total_rows'] ?? 0;
    final readyRows = run['ready_rows'] ?? 0;
    final insertedRows = run['inserted_store_rows'] ?? 0;
    final stagedRows = run['staged_group_rows'] ?? 0;
    final duplicateRows = run['duplicate_imei_rows'] ?? 0;
    final createdAt = _formatRunDate(run['created_at']);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fileName,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            'Dipakai: $createdAt',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'Run ID: $runId',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildHistoryChip('Status $status', AppColors.info),
              _buildHistoryChip('Total $totalRows', AppColors.textSecondary),
              _buildHistoryChip('Ready $readyRows', AppColors.success),
              _buildHistoryChip('Masuk $insertedRows', AppColors.success),
              _buildHistoryChip('Staging $stagedRows', Colors.indigo),
              _buildHistoryChip('Duplikat $duplicateRows', Colors.deepOrange),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHistoryChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildSummaryCards(WarehouseImportSummary summary) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _buildStatCard('Total', summary.totalRows, AppColors.info),
        _buildStatCard('Siap', summary.readyRows, AppColors.success),
        _buildStatCard('Issue', summary.issueRows, AppColors.danger),
        _buildStatCard('Skipped', summary.skippedRows, AppColors.warning),
        _buildStatCard('Single', summary.singleStoreRows, Colors.teal),
        _buildStatCard('Shared', summary.sharedGroupRows, Colors.orange),
        _buildStatCard(
          'Distributed',
          summary.distributedGroupRows,
          Colors.indigo,
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, int value, Color color) {
    return Card(
      child: SizedBox(
        width: 128,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewTable(WarehouseImportPreview preview) {
    final rows = preview.rows.take(200).toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Row')),
              DataColumn(label: Text('Toko Excel')),
              DataColumn(label: Text('Produk Excel')),
              DataColumn(label: Text('IMEI')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Target Sistem')),
              DataColumn(label: Text('Varian Sistem')),
              DataColumn(label: Text('Catatan')),
            ],
            rows: rows
                .map(
                  (row) => DataRow(
                    cells: [
                      DataCell(Text('${row.rowNumber}')),
                      DataCell(Text(row.warehouseName)),
                      DataCell(
                        SizedBox(width: 220, child: Text(row.productName)),
                      ),
                      DataCell(Text(row.imei.isEmpty ? '-' : row.imei)),
                      DataCell(_buildStatusChip(row.status)),
                      DataCell(
                        SizedBox(width: 180, child: Text(row.targetLabel)),
                      ),
                      DataCell(
                        SizedBox(width: 220, child: Text(row.variantLabel)),
                      ),
                      DataCell(
                        SizedBox(
                          width: 240,
                          child: Text(
                            row.notes.isEmpty ? '-' : row.notes.join(' • '),
                          ),
                        ),
                      ),
                    ],
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status) {
    final (label, color) = switch (status) {
      'ready' => ('Siap', AppColors.success),
      'skipped_spc' => ('Skip SPC', AppColors.warning),
      'unknown_target' => ('Target Tidak Dikenal', AppColors.danger),
      'unknown_variant' => ('Varian Tidak Dikenal', AppColors.danger),
      'invalid_imei' => ('IMEI Invalid', AppColors.danger),
      'duplicate_in_file' => ('Duplikat di File', Colors.deepOrange),
      'ambiguous_variant' => ('Varian Ambigu', Colors.deepOrange),
      _ => (status, AppColors.textSecondary),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  String _formatRunDate(dynamic value) {
    final raw = '$value'.trim();
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.isEmpty ? '-' : raw;
    return DateFormat('dd MMM yyyy, HH:mm').format(parsed.toLocal());
  }
}
