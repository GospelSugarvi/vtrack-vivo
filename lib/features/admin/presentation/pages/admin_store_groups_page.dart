import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/foundation/app_colors.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

class AdminStoreGroupsPage extends StatefulWidget {
  const AdminStoreGroupsPage({super.key});

  @override
  State<AdminStoreGroupsPage> createState() => _AdminStoreGroupsPageState();
}

class _AdminStoreGroupsPageState extends State<AdminStoreGroupsPage> {
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _groups = <Map<String, dynamic>>[];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      List data;
      try {
        data = await _supabase
            .from('store_groups')
            .select('*, stores!stores_group_id_fkey(id, store_name)')
            .isFilter('deleted_at', null)
            .order('group_name');
      } on PostgrestException catch (e) {
        if (e.code == '42703') {
          data = await _supabase
              .from('store_groups')
              .select('*, stores!stores_group_id_fkey(id, store_name)')
              .order('group_name');
        } else {
          rethrow;
        }
      }

      if (mounted) {
        setState(() {
          _groups = List<Map<String, dynamic>>.from(data);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorDialog(context, title: 'Gagal', message: 'Gagal memuat grup toko: $e');
    }
  }

  Future<void> _createGroup() async {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final ownerController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Buat Grup Toko Baru'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Nama Grup *',
                  hintText: 'Contoh: MAJU MULIA MANDIRI',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: 'Deskripsi',
                  hintText: 'Keterangan grup',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ownerController,
                decoration: const InputDecoration(
                  labelText: 'Nama Pemilik',
                  hintText: 'Nama owner toko',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.trim().isEmpty) {
                showErrorDialog(context, title: 'Gagal', message: 'Nama grup harus diisi');
                return;
              }
              try {
                await _supabase.from('store_groups').insert({
                  'group_name': nameController.text.trim(),
                  'description': descController.text.trim(),
                  'owner_name': ownerController.text.trim(),
                });
                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (context.mounted) {
                  showErrorDialog(context, title: 'Gagal', message: 'Gagal membuat grup: $e');
                }
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == true) {
      await _loadGroups();
      if (mounted) {
        showSuccessDialog(context, title: 'Berhasil', message: 'Grup toko berhasil dibuat');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Toko'),
        actions: [
          IconButton(
            onPressed: _loadGroups,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createGroup,
        icon: const Icon(Icons.add),
        label: const Text('Buat Grup'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _groups.isEmpty
              ? const Center(child: Text('Belum ada grup toko'))
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _groups.length,
                  separatorBuilder: (context, index) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final group = _groups[index];
                    final stores = List<Map<String, dynamic>>.from(
                      group['stores'] ?? const <Map<String, dynamic>>[],
                    );
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${group['group_name'] ?? group['name'] ?? '-'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: AppColors.info.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text('${stores.length} toko'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text('${group['description'] ?? '-'}'),
                            const SizedBox(height: 4),
                            Text(
                              'Owner: ${group['owner_name'] ?? '-'}',
                              style: const TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
