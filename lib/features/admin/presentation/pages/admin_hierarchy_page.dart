import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';

class AdminHierarchyPage extends StatefulWidget {
  const AdminHierarchyPage({super.key});

  @override
  State<AdminHierarchyPage> createState() => _AdminHierarchyPageState();
}

class _AdminHierarchyPageState extends State<AdminHierarchyPage> {
  List<Map<String, dynamic>> _managers = [];
  List<Map<String, dynamic>> _spvs = [];
  List<Map<String, dynamic>> _sators = [];
  List<Map<String, dynamic>> _promotors = [];
  List<Map<String, dynamic>> _stores = [];
  
  // Hierarchy mappings
  Map<String, List<String>> _managerSpvMap = {}; // manager_id -> [spv_ids]
  Map<String, List<String>> _spvSatorMap = {}; // spv_id -> [sator_ids]
  Map<String, List<String>> _satorPromotorMap = {}; // sator_id -> [promotor_ids]
  Map<String, List<String>> _promotorStoreMap = {}; // promotor_id -> [store_ids]
  
  bool _isLoading = true;

  static const Map<String, String> _assignmentTitles = <String, String>{
    'Manager': 'SPV',
    'SPV': 'SATOR',
    'SATOR': 'Promotor',
    'Promotor': 'Toko',
  };

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
      // Load users
      final users = await supabase
          .from('users')
          .select('*')
          .isFilter('deleted_at', null)
          .order('full_name');

      final usersList = List<Map<String, dynamic>>.from(users);
      
      // Load stores
      final storesRes = await supabase
          .from('stores')
          .select('*')
          .isFilter('deleted_at', null)
          .order('store_name');
      _stores = List<Map<String, dynamic>>.from(storesRes);
      
      // Load hierarchy mappings
      final managerSpv = await supabase.from('hierarchy_manager_spv').select('*').eq('active', true);
      final spvSator = await supabase.from('hierarchy_spv_sator').select('*').eq('active', true);
      final satorPromotor = await supabase.from('hierarchy_sator_promotor').select('*').eq('active', true);
      final promotorStore = await supabase.from('assignments_promotor_store').select('*').eq('active', true);
      
      // Build maps
      _managerSpvMap = {};
      for (var h in managerSpv) {
        final managerId = h['manager_id'] as String;
        _managerSpvMap.putIfAbsent(managerId, () => []);
        _managerSpvMap[managerId]!.add(h['spv_id'] as String);
      }
      
      _spvSatorMap = {};
      for (var h in spvSator) {
        final spvId = h['spv_id'] as String;
        _spvSatorMap.putIfAbsent(spvId, () => []);
        _spvSatorMap[spvId]!.add(h['sator_id'] as String);
      }
      
      _satorPromotorMap = {};
      for (var h in satorPromotor) {
        final satorId = h['sator_id'] as String;
        _satorPromotorMap.putIfAbsent(satorId, () => []);
        _satorPromotorMap[satorId]!.add(h['promotor_id'] as String);
      }
      
      _promotorStoreMap = {};
      for (var h in promotorStore) {
        final promotorId = h['promotor_id'] as String;
        _promotorStoreMap.putIfAbsent(promotorId, () => []);
        _promotorStoreMap[promotorId]!.add(h['store_id'] as String);
      }
      
      if (!mounted) return;
      setState(() {
        _managers = usersList.where((u) => u['role'] == 'manager').toList();
        _spvs = usersList.where((u) => u['role'] == 'spv').toList();
        _sators = usersList.where((u) => u['role'] == 'sator').toList();
        _promotors = usersList.where((u) => u['role'] == 'promotor').toList();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading hierarchy: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isDesktop) Text('Hierarchy Management', style: Theme.of(context).textTheme.headlineMedium),
                  if (isDesktop) const SizedBox(height: 8),
                  if (isDesktop) Text('Kelola siapa di bawah siapa, dan promotor pegang toko mana', style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 24),

                  _buildInfoCard(),
                  const SizedBox(height: 16),

                  _buildSection('Manager', _managers, Colors.indigo, 'SPV'),
                  const SizedBox(height: 16),
                  _buildSection('SPV', _spvs, AppColors.info, 'SATOR'),
                  const SizedBox(height: 16),
                  _buildSection('SATOR', _sators, AppColors.primary, 'Promotor'),
                  const SizedBox(height: 16),
                  _buildSection('Promotor', _promotors, AppColors.success, 'Toko'),
                ],
              ),
            ),
    );
  }

  Widget _buildSection(String title, List<Map<String, dynamic>> users, Color color, String assignLabel) {
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.2),
          child: Text('${users.length}', style: TextStyle(color: color, fontWeight: FontWeight.bold)),
        ),
        title: Text(title),
        subtitle: Text('${users.length} orang'),
        children: users.map((u) {
          final assignedCount = _getAssignedCount(u['id'], title);
          final assignedNames = _getAssignedNames(u['id'] as String?, title);
          return ListTile(
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              child: Text((u['full_name'] ?? 'U')[0].toUpperCase(), style: TextStyle(color: color)),
            ),
            title: Text(u['full_name'] ?? 'Unknown'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${u['area'] ?? 'No Area'} • $assignedCount $assignLabel'),
                  const SizedBox(height: 6),
                  Text(
                    assignedNames.isEmpty
                        ? 'Belum ada $assignLabel terhubung'
                        : '${_assignmentTitles[title] ?? assignLabel}: ${assignedNames.join(', ')}',
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            isThreeLine: true,
            trailing: SizedBox(
              width: 124,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.account_tree, size: 16),
                label: Text('Kelola'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => _showAssignDialog(u, title),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text(
              'Aturan halaman ini',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            SizedBox(height: 8),
            Text('Manager mengelola SPV.'),
            Text('SPV mengelola SATOR.'),
            Text('SATOR mengelola Promotor.'),
            Text('Promotor terhubung ke Toko.'),
            SizedBox(height: 8),
            Text(
              'Tambah atau hilangkan relasi dilakukan dari tombol Kelola pada masing-masing baris.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
  
  int _getAssignedCount(String? userId, String role) {
    if (userId == null) return 0;
    switch (role) {
      case 'Manager':
        return _managerSpvMap[userId]?.length ?? 0;
      case 'SPV':
        return _spvSatorMap[userId]?.length ?? 0;
      case 'SATOR':
        return _satorPromotorMap[userId]?.length ?? 0;
      case 'Promotor':
        return _promotorStoreMap[userId]?.length ?? 0;
      default:
        return 0;
    }
  }

  List<String> _getAssignedNames(String? userId, String role) {
    if (userId == null) return <String>[];
    switch (role) {
      case 'Manager':
        return _lookupUserNames(_managerSpvMap[userId] ?? <String>[], _spvs);
      case 'SPV':
        return _lookupUserNames(_spvSatorMap[userId] ?? <String>[], _sators);
      case 'SATOR':
        return _lookupUserNames(_satorPromotorMap[userId] ?? <String>[], _promotors);
      case 'Promotor':
        return _lookupStoreNames(_promotorStoreMap[userId] ?? <String>[]);
      default:
        return <String>[];
    }
  }

  List<String> _lookupUserNames(List<String> ids, List<Map<String, dynamic>> source) {
    if (ids.isEmpty) return <String>[];
    final namesById = <String, String>{
      for (final item in source) item['id'] as String: '${item['full_name'] ?? 'Unknown'}',
    };
    return ids.map((id) => namesById[id]).whereType<String>().toList();
  }

  List<String> _lookupStoreNames(List<String> ids) {
    if (ids.isEmpty) return <String>[];
    final storesById = <String, String>{
      for (final item in _stores) item['id'] as String: '${item['store_name'] ?? 'Unknown'}',
    };
    return ids.map((id) => storesById[id]).whereType<String>().toList();
  }

  void _showAssignDialog(Map<String, dynamic> user, String role) {
    final userId = user['id'] as String;
    final userName = user['full_name'] ?? 'Unknown';
    
    List<Map<String, dynamic>> availableItems = [];
    List<String> currentAssignments = [];
    String tableName = '';
    String parentColumn = '';
    String childColumn = '';
    String itemLabel = '';
    
    switch (role) {
      case 'Manager':
        availableItems = _spvs;
        currentAssignments = _managerSpvMap[userId] ?? [];
        tableName = 'hierarchy_manager_spv';
        parentColumn = 'manager_id';
        childColumn = 'spv_id';
        itemLabel = 'SPV';
        break;
      case 'SPV':
        availableItems = _sators;
        currentAssignments = _spvSatorMap[userId] ?? [];
        tableName = 'hierarchy_spv_sator';
        parentColumn = 'spv_id';
        childColumn = 'sator_id';
        itemLabel = 'SATOR';
        break;
      case 'SATOR':
        availableItems = _promotors;
        currentAssignments = _satorPromotorMap[userId] ?? [];
        tableName = 'hierarchy_sator_promotor';
        parentColumn = 'sator_id';
        childColumn = 'promotor_id';
        itemLabel = 'Promotor';
        break;
      case 'Promotor':
        availableItems = _stores;
        currentAssignments = _promotorStoreMap[userId] ?? [];
        tableName = 'assignments_promotor_store';
        parentColumn = 'promotor_id';
        childColumn = 'store_id';
        itemLabel = 'Toko';
        break;
    }
    
    // Create mutable copy for dialog
    List<String> selectedIds = List.from(currentAssignments);
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text('Kelola $itemLabel untuk $userName'),
          content: SizedBox(
            width: 400,
            height: 400,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Centang untuk menambah. Hilangkan centang untuk melepas.', style: const TextStyle(fontWeight: FontWeight.bold)),
                Text('${selectedIds.length} $itemLabel aktif', style: const TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 12),
                Expanded(
                  child: availableItems.isEmpty
                      ? Center(child: Text('Tidak ada $itemLabel tersedia'))
                      : ListView.builder(
                          itemCount: availableItems.length,
                          itemBuilder: (ctx, i) {
                            final item = availableItems[i];
                            final itemId = item['id'] as String;
                            final isSelected = selectedIds.contains(itemId);
                            final displayName = role == 'Promotor' 
                                ? (item['store_name'] ?? 'Unknown')
                                : (item['full_name'] ?? 'Unknown');
                            final subtitle = role == 'Promotor'
                                ? (item['area'] ?? 'No Area')
                                : (item['area'] ?? 'No Area');
                            
                            return CheckboxListTile(
                              value: isSelected,
                              title: Text(displayName),
                              subtitle: Text(subtitle),
                              onChanged: (val) {
                                setDialogState(() {
                                  if (val == true) {
                                    selectedIds.add(itemId);
                                  } else {
                                    selectedIds.remove(itemId);
                                  }
                                });
                              },
                            );
                          },
                        ),
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
                Navigator.pop(ctx);
                await _saveAssignments(
                  userId, 
                  selectedIds, 
                  currentAssignments, 
                  tableName, 
                  parentColumn, 
                  childColumn,
                );
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
  
  Future<void> _saveAssignments(
    String parentId,
    List<String> newAssignments,
    List<String> oldAssignments,
    String tableName,
    String parentColumn,
    String childColumn,
  ) async {
    try {
      // Find items to add
      final toAdd = newAssignments.where((id) => !oldAssignments.contains(id)).toList();
      // Find items to remove
      final toRemove = oldAssignments.where((id) => !newAssignments.contains(id)).toList();
      
      // Add new assignments
      for (final childId in toAdd) {
        await supabase.from(tableName).upsert({
          parentColumn: parentId,
          childColumn: childId,
          'active': true,
        }, onConflict: '$parentColumn,$childColumn');
      }
      
      // Deactivate removed assignments
      for (final childId in toRemove) {
        await supabase.from(tableName)
            .update({'active': false})
            .eq(parentColumn, parentId)
            .eq(childColumn, childId);
      }
      
      // Reload data
      await _loadData();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Assignment berhasil disimpan!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      debugPrint('Error saving assignments: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }
}
