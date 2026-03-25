import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

class AdminStoresPage extends StatefulWidget {
  const AdminStoresPage({super.key});

  @override
  State<AdminStoresPage> createState() => _AdminStoresPageState();
}

class _AdminStoresPageState extends State<AdminStoresPage> {
  List<Map<String, dynamic>> _stores = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _filterGrade = 'all';

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  List<Map<String, dynamic>> get _filteredStores {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return _stores;
    }
    return _stores.where((store) {
      final name = '${store['store_name'] ?? ''}'.toLowerCase();
      final area = '${store['area'] ?? ''}'.toLowerCase();
      final address = '${store['address'] ?? ''}'.toLowerCase();
      return name.contains(query) || area.contains(query) || address.contains(query);
    }).toList();
  }

  Future<void> _loadStores() async {
    setState(() => _isLoading = true);
    try {
      var query = supabase.from('stores').select('*').isFilter('deleted_at', null);
      
      if (_filterGrade != 'all') {
        query = query.eq('grade', _filterGrade);
      }

      final response = await query.order('store_name');
      
      setState(() {
        _stores = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
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
        onPressed: _showAddStoreDialog,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Toko'),
      ),
      body: Column(
        children: [
          // Header & Filters
          Container(
            padding: EdgeInsets.all(isDesktop ? 24 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isDesktop)
                  Text('Toko Management', style: Theme.of(context).textTheme.headlineMedium),
                if (isDesktop) const SizedBox(height: 16),
                
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Cari nama toko atau area...',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onChanged: (value) => setState(() => _searchQuery = value),
                      ),
                    ),
                    const SizedBox(width: 12),
                    DropdownButton<String>(
                      value: _filterGrade,
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('Semua Grade')),
                        DropdownMenuItem(value: 'A', child: Text('Grade A')),
                        DropdownMenuItem(value: 'B', child: Text('Grade B')),
                        DropdownMenuItem(value: 'C', child: Text('Grade C')),
                        DropdownMenuItem(value: 'D', child: Text('Grade D')),
                      ],
                      onChanged: (value) {
                        setState(() => _filterGrade = value ?? 'all');
                        _loadStores();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Store List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredStores.isEmpty
                    ? const Center(child: Text('Tidak ada toko'))
                    : isDesktop
                        ? _buildDesktopTable()
                        : _buildMobileList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        width: double.infinity,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(AppTheme.primaryBlue.withValues(alpha: 0.1)),
          columns: const [
            DataColumn(label: Text('Nama Toko')),
            DataColumn(label: Text('Area')),
            DataColumn(label: Text('Grade')),
            DataColumn(label: Text('Alamat')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Aksi')),
          ],
          rows: _filteredStores.map((store) => DataRow(
            cells: [
              DataCell(Text(store['store_name'] ?? '-')),
              DataCell(Text(store['area'] ?? '-')),
              DataCell(_buildGradeBadge(store['grade'])),
              DataCell(Text(store['address'] ?? '-', overflow: TextOverflow.ellipsis)),
              DataCell(_buildStatusBadge(store['status'])),
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.people, size: 20, color: AppColors.info),
                    tooltip: 'Manage Promotor',
                    onPressed: () => _showManagePromotorDialog(store),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, size: 20),
                    onPressed: () => _showEditStoreDialog(store),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete, size: 20, color: AppTheme.errorRed),
                    onPressed: () => _confirmDelete(store),
                  ),
                ],
              )),
            ],
          )).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredStores.length,
      itemBuilder: (context, index) {
        final store = _filteredStores[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: _getGradeColor(store['grade']).withValues(alpha: 0.2),
              child: Text(
                store['grade'] ?? '?',
                style: TextStyle(color: _getGradeColor(store['grade']), fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(store['store_name'] ?? 'Unknown'),
            subtitle: Text('${store['area'] ?? 'No Area'} • ${store['address'] ?? ''}'),
            trailing: PopupMenuButton(
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'promotor', child: Row(children: [Icon(Icons.people, size: 18), SizedBox(width: 8), Text('Manage Promotor')])),
                const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18), SizedBox(width: 8), Text('Hapus')])),
              ],
              onSelected: (value) {
                if (value == 'promotor') _showManagePromotorDialog(store);
                if (value == 'edit') _showEditStoreDialog(store);
                if (value == 'delete') _confirmDelete(store);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _buildGradeBadge(String? grade) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: _getGradeColor(grade).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        grade ?? '-',
        style: TextStyle(
          color: _getGradeColor(grade),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildStatusBadge(String? status) {
    final isActive = status == 'active';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (isActive ? AppTheme.successGreen : AppTheme.errorRed).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        isActive ? 'Active' : 'Inactive',
        style: TextStyle(
          color: isActive ? AppTheme.successGreen : AppTheme.errorRed,
          fontSize: 12,
        ),
      ),
    );
  }

  Color _getGradeColor(String? grade) {
    switch (grade) {
      case 'A': return AppColors.success;
      case 'B': return AppColors.info;
      case 'C': return AppColors.warning;
      case 'D': return AppColors.danger;
      default: return AppColors.textSecondary;
    }
  }

  void _showAddStoreDialog() {
    _showStoreFormDialog(null);
  }

  void _showEditStoreDialog(Map<String, dynamic> store) {
    _showStoreFormDialog(store);
  }

  void _showStoreFormDialog(Map<String, dynamic>? store) {
    final isEdit = store != null;
    final nameController = TextEditingController(text: store?['store_name'] ?? '');
    String? selectedAreaId;
    String selectedGrade = store?['grade'] ?? 'A';
    List<Map<String, dynamic>> areas = [];
    bool isLoading = true;

    // Load areas
    Future<void> loadAreas(StateSetter setDialogState) async {
      final result = await supabase.from('areas').select('id, area_name').order('area_name');
      setDialogState(() {
        areas = List<Map<String, dynamic>>.from(result);
        
        // Find area ID if editing
        if (store != null && store['area'] != null) {
          final found = areas.firstWhere((a) => a['area_name'] == store['area'], orElse: () => {});
          if (found.isNotEmpty) selectedAreaId = found['id'] as String;
        } else if (areas.isNotEmpty) {
           // Optional: default to first area
        }
        isLoading = false;
      });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (isLoading) {
             loadAreas(setDialogState);
             isLoading = false; // Prevent loop
          }

          return AlertDialog(
            title: Text(isEdit ? 'Edit Toko' : 'Tambah Toko'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(labelText: 'Nama Toko (HURUF BESAR)', hintText: 'VIVO OFFICIAL STORE'),
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (v) => nameController.value = nameController.value.copyWith(text: v.toUpperCase(), selection: TextSelection.collapsed(offset: v.length)),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedAreaId,
                    decoration: const InputDecoration(labelText: 'Area'),
                    hint: const Text('Pilih Area'),
                    items: areas.map((a) => DropdownMenuItem(value: a['id'] as String, child: Text(a['area_name'] ?? '-'))).toList(),
                    onChanged: (v) => setDialogState(() => selectedAreaId = v),
                  ),
                  if (areas.isEmpty) 
                     const Padding(padding: EdgeInsets.only(top:4), child: Text('Loading areas...', style: TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedGrade,
                    decoration: const InputDecoration(labelText: 'Grade'),
                    items: ['A', 'B', 'C', 'D'].map((g) => DropdownMenuItem(value: g, child: Text('Grade $g'))).toList(),
                    onChanged: (v) => selectedGrade = v ?? 'A',
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
                onPressed: isLoading ? null : () async {
                  if (nameController.text.isEmpty || selectedAreaId == null) {
                     showErrorDialog(context, title: 'Gagal', message: 'Nama dan Area wajib diisi');
                     return;
                  }

                  setDialogState(() => isLoading = true);

                  try {
                    final areaName = areas.firstWhere((a) => a['id'] == selectedAreaId, orElse: () => {})['area_name'] ?? '';

                    final data = {
                      'store_name': nameController.text.trim(),
                      'area': areaName,
                      'address': '', // Empty as requested
                      'grade': selectedGrade,
                      'status': 'active',
                    };

                    if (isEdit) {
                      await supabase.from('stores').update(data).eq('id', store['id']);
                    } else {
                      await supabase.from('stores').insert(data);
                    }

                    if (!context.mounted) return;
                    Navigator.pop(context);
                    showSuccessDialog(context, title: 'Berhasil', message: 'Berhasil menyimpan data toko');
                    _loadStores();
                  } catch (e) {
                    setDialogState(() => isLoading = false);
                    if (!context.mounted) return;
                    showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
                  }
                },
                child: isLoading 
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) 
                  : Text(isEdit ? 'Simpan' : 'Tambah'),
              ),
            ],
          );
        }
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> store) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Toko'),
        content: Text('Yakin ingin menghapus ${store['store_name']}?'),
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
      await supabase.from('stores').update({
        'deleted_at': DateTime.now().toIso8601String(),
      }).eq('id', store['id']);
      _loadStores();
    }
  }

  void _showManagePromotorDialog(Map<String, dynamic> store) async {
    // Load all promotors and current assignments
    final promotorsResult = await supabase
        .from('users')
        .select('id, full_name, area')
        .eq('role', 'promotor')
        .isFilter('deleted_at', null)
        .order('full_name');
    
    final assignmentsResult = await supabase
        .from('assignments_promotor_store')
        .select('promotor_id, active')
        .eq('store_id', store['id']);

    final allPromotors = List<Map<String, dynamic>>.from(promotorsResult);
    final currentAssignments = List<Map<String, dynamic>>.from(assignmentsResult);
    
    // Create a set of assigned promotor IDs
    final assignedIds = currentAssignments
        .where((a) => a['active'] == true)
        .map((a) => a['promotor_id'] as String)
        .toSet();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Manage Promotor'),
                const SizedBox(height: 4),
                Text(
                  store['store_name'] ?? '',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal, color: AppColors.textSecondary),
                ),
              ],
            ),
            content: SizedBox(
              width: 500,
              height: 400,
              child: allPromotors.isEmpty
                  ? const Center(child: Text('Tidak ada promotor'))
                  : ListView.builder(
                      itemCount: allPromotors.length,
                      itemBuilder: (context, index) {
                        final promotor = allPromotors[index];
                        final isAssigned = assignedIds.contains(promotor['id']);
                        
                        return CheckboxListTile(
                          title: Text(promotor['full_name'] ?? ''),
                          subtitle: Text(promotor['area'] ?? 'No Area'),
                          value: isAssigned,
                          onChanged: (bool? value) async {
                            if (value == true) {
                              // Assign promotor to store
                              await supabase.from('assignments_promotor_store').upsert({
                                'promotor_id': promotor['id'],
                                'store_id': store['id'],
                                'active': true,
                              });
                              assignedIds.add(promotor['id'] as String);
                            } else {
                              // Unassign promotor from store
                              await supabase
                                  .from('assignments_promotor_store')
                                  .update({'active': false})
                                  .eq('promotor_id', promotor['id'])
                                  .eq('store_id', store['id']);
                              assignedIds.remove(promotor['id']);
                            }
                            setDialogState(() {});
                          },
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup'),
              ),
            ],
          );
        },
      ),
    );
  }
}
