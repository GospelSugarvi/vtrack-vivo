import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';

class AdminUsersPage extends StatefulWidget {
  const AdminUsersPage({super.key});

  @override
  State<AdminUsersPage> createState() => _AdminUsersPageState();
}

class _AdminUsersPageState extends State<AdminUsersPage> {
  List<Map<String, dynamic>> _users = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _stores = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _managers = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _spvs = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _sators = <Map<String, dynamic>>[];
  final Map<String, String> _spvToManager = <String, String>{};
  final Map<String, String> _satorToSpv = <String, String>{};
  final Map<String, String> _promotorToSator = <String, String>{};
  final Map<String, String> _promotorToStore = <String, String>{};

  bool _isLoading = true;
  String _searchQuery = '';
  String _filterRole = 'all';
  String _filterStatus = 'all';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final query = _searchQuery.trim().toLowerCase();
    return _users.where((user) {
      if (_filterRole != 'all' && '${user['role']}' != _filterRole) {
        return false;
      }
      if (_filterStatus != 'all' && '${user['status'] ?? 'active'}' != _filterStatus) {
        return false;
      }
      if (query.isEmpty) return true;
      final fullName = '${user['full_name'] ?? ''}'.toLowerCase();
      final nickname = '${user['nickname'] ?? ''}'.toLowerCase();
      final email = '${user['email'] ?? ''}'.toLowerCase();
      final area = '${user['area'] ?? ''}'.toLowerCase();
      return fullName.contains(query) ||
          nickname.contains(query) ||
          email.contains(query) ||
          area.contains(query);
    }).toList();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final usersReq = supabase
          .from('users')
          .select(
            'id, full_name, nickname, email, role, area, status, created_at, promotor_type, promotor_status',
          )
          .isFilter('deleted_at', null)
          .order('created_at', ascending: false);
      final storesReq = supabase
          .from('stores')
          .select('id, store_name')
          .isFilter('deleted_at', null)
          .order('store_name');
      final managerSpvReq = supabase
          .from('hierarchy_manager_spv')
          .select('manager_id, spv_id')
          .eq('active', true);
      final spvSatorReq = supabase
          .from('hierarchy_spv_sator')
          .select('spv_id, sator_id')
          .eq('active', true);
      final satorPromotorReq = supabase
          .from('hierarchy_sator_promotor')
          .select('sator_id, promotor_id')
          .eq('active', true);
      final promotorStoreReq = supabase
          .from('assignments_promotor_store')
          .select('promotor_id, store_id')
          .eq('active', true);

      final results = await Future.wait([
        usersReq,
        storesReq,
        managerSpvReq,
        spvSatorReq,
        satorPromotorReq,
        promotorStoreReq,
      ]);
      final users = List<Map<String, dynamic>>.from(results[0] as List);
      final stores = List<Map<String, dynamic>>.from(results[1] as List);
      final managerSpv = List<Map<String, dynamic>>.from(results[2] as List);
      final spvSator = List<Map<String, dynamic>>.from(results[3] as List);
      final satorPromotor = List<Map<String, dynamic>>.from(results[4] as List);
      final promotorStore = List<Map<String, dynamic>>.from(results[5] as List);

      _spvToManager
        ..clear()
        ..addEntries(
          managerSpv.map(
            (row) => MapEntry('${row['spv_id']}', '${row['manager_id']}'),
          ),
        );
      _satorToSpv
        ..clear()
        ..addEntries(
          spvSator.map(
            (row) => MapEntry('${row['sator_id']}', '${row['spv_id']}'),
          ),
        );
      _promotorToSator
        ..clear()
        ..addEntries(
          satorPromotor.map(
            (row) => MapEntry('${row['promotor_id']}', '${row['sator_id']}'),
          ),
        );
      _promotorToStore
        ..clear()
        ..addEntries(
          promotorStore.map(
            (row) => MapEntry('${row['promotor_id']}', '${row['store_id']}'),
          ),
        );

      if (!mounted) return;
      setState(() {
        _users = users;
        _stores = stores;
        _managers = users.where((row) => row['role'] == 'manager').toList();
        _spvs = users.where((row) => row['role'] == 'spv').toList();
        _sators = users.where((row) => row['role'] == 'sator').toList();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Color _getRoleColor(String? role) {
    switch (role) {
      case 'admin':
        return Colors.purple;
      case 'manager':
        return Colors.indigo;
      case 'spv':
        return AppColors.info;
      case 'sator':
        return AppColors.primary;
      case 'promotor':
        return AppColors.success;
      default:
        return AppColors.textSecondary;
    }
  }

  Color _getStatusColor(String? status) {
    switch (status) {
      case 'inactive':
        return AppColors.textSecondary;
      case 'suspended':
        return AppColors.danger;
      default:
        return AppColors.success;
    }
  }

  int _countRole(String role) {
    return _users.where((row) => row['role'] == role).length;
  }

  Future<void> _toggleUserStatus(Map<String, dynamic> user) async {
    final currentStatus = '${user['status'] ?? 'active'}';
    final nextStatus = currentStatus == 'active' ? 'inactive' : 'active';
    try {
      await supabase
          .from('users')
          .update({'status': nextStatus})
          .eq('id', user['id']);
      await _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Status user diubah ke $nextStatus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal ubah status: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _saveSingleAssignment({
    required String tableName,
    required String parentColumn,
    required String childColumn,
    required String parentId,
    String? oldChildId,
    String? newChildId,
  }) async {
    if (oldChildId != null && oldChildId.isNotEmpty && oldChildId != newChildId) {
      await supabase
          .from(tableName)
          .update({'active': false})
          .eq(parentColumn, parentId)
          .eq(childColumn, oldChildId);
    }
    if (newChildId != null && newChildId.isNotEmpty) {
      await supabase.from(tableName).upsert({
        parentColumn: parentId,
        childColumn: newChildId,
        'active': true,
      }, onConflict: '$parentColumn,$childColumn');
    }
  }

  Future<void> _softDeleteUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Hapus User'),
        content: Text(
          'User ${user['full_name'] ?? '-'} akan di-soft delete dan assignment aktifnya dimatikan. Lanjut?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final userId = '${user['id']}';
    final role = '${user['role'] ?? ''}';

    try {
      if (role == 'spv') {
        await supabase
            .from('hierarchy_manager_spv')
            .update({'active': false})
            .eq('spv_id', userId);
      }
      if (role == 'sator') {
        await supabase
            .from('hierarchy_spv_sator')
            .update({'active': false})
            .eq('sator_id', userId);
      }
      if (role == 'promotor') {
        await supabase
            .from('hierarchy_sator_promotor')
            .update({'active': false})
            .eq('promotor_id', userId);
        await supabase
            .from('assignments_promotor_store')
            .update({'active': false})
            .eq('promotor_id', userId);
      }

      await supabase
          .from('users')
          .update({
            'status': 'inactive',
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      await _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User berhasil dihapus')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal hapus user: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  Future<void> _showCreateUserDialog() async {
    final formKey = GlobalKey<FormState>();
    final fullNameC = TextEditingController();
    final nickNameC = TextEditingController();
    final emailC = TextEditingController();
    final passwordC = TextEditingController();
    final areaC = TextEditingController();

    String role = 'promotor';
    String promotorStatus = 'training';
    String? supervisorId;
    String? storeId;
    bool isSubmitting = false;

    List<Map<String, dynamic>> getSupervisorOptions(String currentRole) {
      switch (currentRole) {
        case 'spv':
          return _managers;
        case 'sator':
          return _spvs;
        case 'promotor':
          return _sators;
        default:
          return const [];
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final supervisorOptions = getSupervisorOptions(role);
          final needsSupervisor = role == 'spv' || role == 'sator' || role == 'promotor';
          final needsStore = role == 'promotor';

          return AlertDialog(
            title: const Text('Tambah User'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: fullNameC,
                        decoration: const InputDecoration(labelText: 'Nama lengkap'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Wajib diisi' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nickNameC,
                        decoration: const InputDecoration(labelText: 'Nama panggilan'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailC,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Wajib diisi' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordC,
                        decoration: const InputDecoration(labelText: 'Password'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Wajib diisi' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: areaC,
                        decoration: const InputDecoration(labelText: 'Area'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                          DropdownMenuItem(value: 'manager', child: Text('Manager')),
                          DropdownMenuItem(value: 'spv', child: Text('SPV')),
                          DropdownMenuItem(value: 'sator', child: Text('SATOR')),
                          DropdownMenuItem(value: 'promotor', child: Text('Promotor')),
                        ],
                        onChanged: (value) {
                          setDialogState(() {
                            role = value ?? 'promotor';
                            supervisorId = null;
                            storeId = null;
                          });
                        },
                      ),
                      if (role == 'promotor') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: promotorStatus,
                          decoration: const InputDecoration(labelText: 'Tipe Promotor'),
                          items: const [
                            DropdownMenuItem(
                              value: 'official',
                              child: Text('Official'),
                            ),
                            DropdownMenuItem(
                              value: 'training',
                              child: Text('Training'),
                            ),
                          ],
                          onChanged: (value) => setDialogState(
                            () => promotorStatus = value ?? 'training',
                          ),
                        ),
                      ],
                      if (needsSupervisor) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: supervisorId,
                          decoration: InputDecoration(
                            labelText: role == 'spv'
                                ? 'Manager'
                                : role == 'sator'
                                ? 'SPV'
                                : 'SATOR',
                          ),
                          items: supervisorOptions
                              .map(
                                (row) => DropdownMenuItem(
                                  value: '${row['id']}',
                                  child: Text('${row['full_name'] ?? '-'}'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setDialogState(() => supervisorId = value),
                        ),
                      ],
                      if (needsStore) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: storeId,
                          decoration: const InputDecoration(labelText: 'Toko'),
                          items: _stores
                              .map(
                                (row) => DropdownMenuItem(
                                  value: '${row['id']}',
                                  child: Text('${row['store_name'] ?? '-'}'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(() => storeId = value),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => isSubmitting = true);
                        try {
                          final res = await supabase.functions.invoke(
                            'create-user',
                            body: {
                              'email': emailC.text.trim(),
                              'password': passwordC.text.trim(),
                              'full_name': fullNameC.text.trim(),
                              'nickname': nickNameC.text.trim().isEmpty
                                  ? null
                                  : nickNameC.text.trim(),
                              'role': role,
                              'area': areaC.text.trim().isEmpty ? null : areaC.text.trim(),
                              'supervisor_id': supervisorId,
                              'store_id': storeId,
                              'promotor_status': role == 'promotor'
                                  ? promotorStatus
                                  : null,
                            },
                          );
                          if (res.status >= 400) {
                            throw Exception(res.data.toString());
                          }
                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          await _loadUsers();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User berhasil dibuat')),
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() => isSubmitting = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Gagal membuat user: $e'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      },
                child: Text(isSubmitting ? 'Membuat...' : 'Buat User'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showEditUserDialog(Map<String, dynamic> user) async {
    final formKey = GlobalKey<FormState>();
    final fullNameC = TextEditingController(text: '${user['full_name'] ?? ''}');
    final nickNameC = TextEditingController(text: '${user['nickname'] ?? ''}');
    final areaC = TextEditingController(text: '${user['area'] ?? ''}');

    String role = '${user['role'] ?? 'promotor'}';
    String status = '${user['status'] ?? 'active'}';
    String promotorType = '${user['promotor_type'] ?? user['promotor_status'] ?? 'training'}';
    String? supervisorId = switch (role) {
      'spv' => _spvToManager['${user['id']}'],
      'sator' => _satorToSpv['${user['id']}'],
      'promotor' => _promotorToSator['${user['id']}'],
      _ => null,
    };
    String? storeId = role == 'promotor' ? _promotorToStore['${user['id']}'] : null;
    bool isSubmitting = false;

    List<Map<String, dynamic>> getSupervisorOptions(String currentRole) {
      switch (currentRole) {
        case 'spv':
          return _managers;
        case 'sator':
          return _spvs;
        case 'promotor':
          return _sators;
        default:
          return const [];
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final supervisorOptions = getSupervisorOptions(role);
          final needsSupervisor =
              role == 'spv' || role == 'sator' || role == 'promotor';
          final needsStore = role == 'promotor';
          return AlertDialog(
            title: const Text('Edit User'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: fullNameC,
                        decoration: const InputDecoration(labelText: 'Nama lengkap'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty) ? 'Wajib diisi' : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        initialValue: '${user['email'] ?? ''}',
                        decoration: const InputDecoration(labelText: 'Email'),
                        readOnly: true,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nickNameC,
                        decoration: const InputDecoration(labelText: 'Nama panggilan'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: areaC,
                        decoration: const InputDecoration(labelText: 'Area'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                          DropdownMenuItem(value: 'manager', child: Text('Manager')),
                          DropdownMenuItem(value: 'spv', child: Text('SPV')),
                          DropdownMenuItem(value: 'sator', child: Text('SATOR')),
                          DropdownMenuItem(value: 'promotor', child: Text('Promotor')),
                        ],
                        onChanged: (value) => setDialogState(() {
                          role = value ?? 'promotor';
                          supervisorId = null;
                          if (role != 'promotor') {
                            storeId = null;
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => status = value ?? 'active'),
                      ),
                      if (role == 'promotor') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: promotorType,
                          decoration: const InputDecoration(labelText: 'Tipe Promotor'),
                          items: const [
                            DropdownMenuItem(
                              value: 'official',
                              child: Text('Official'),
                            ),
                            DropdownMenuItem(
                              value: 'training',
                              child: Text('Training'),
                            ),
                          ],
                          onChanged: (value) => setDialogState(
                            () => promotorType = value ?? 'training',
                          ),
                        ),
                      ],
                      if (needsSupervisor) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: supervisorId,
                          decoration: InputDecoration(
                            labelText: role == 'spv'
                                ? 'Manager'
                                : role == 'sator'
                                ? 'SPV'
                                : 'SATOR',
                          ),
                          items: supervisorOptions
                              .map(
                                (row) => DropdownMenuItem(
                                  value: '${row['id']}',
                                  child: Text('${row['full_name'] ?? '-'}'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) =>
                              setDialogState(() => supervisorId = value),
                        ),
                      ],
                      if (needsStore) ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: storeId,
                          decoration: const InputDecoration(labelText: 'Toko'),
                          items: _stores
                              .map(
                                (row) => DropdownMenuItem(
                                  value: '${row['id']}',
                                  child: Text('${row['store_name'] ?? '-'}'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) => setDialogState(() => storeId = value),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting ? null : () => Navigator.pop(dialogContext),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => isSubmitting = true);
                        try {
                          final userId = '${user['id']}';
                          final oldRole = '${user['role'] ?? ''}';
                          await supabase
                              .from('users')
                              .update({
                                'full_name': fullNameC.text.trim(),
                                'nickname': nickNameC.text.trim().isEmpty
                                    ? null
                                    : nickNameC.text.trim(),
                                'area': areaC.text.trim().isEmpty
                                    ? null
                                    : areaC.text.trim(),
                                'role': role,
                                'status': status,
                                'promotor_type': role == 'promotor'
                                    ? promotorType
                                    : null,
                                'promotor_status': role == 'promotor'
                                    ? promotorType
                                    : null,
                              })
                              .eq('id', userId);

                          if (oldRole == 'spv' || role == 'spv') {
                            await _saveSingleAssignment(
                              tableName: 'hierarchy_manager_spv',
                              parentColumn: 'spv_id',
                              childColumn: 'manager_id',
                              parentId: userId,
                              oldChildId: _spvToManager[userId],
                              newChildId: role == 'spv' ? supervisorId : null,
                            );
                          }
                          if (oldRole == 'sator' || role == 'sator') {
                            await _saveSingleAssignment(
                              tableName: 'hierarchy_spv_sator',
                              parentColumn: 'sator_id',
                              childColumn: 'spv_id',
                              parentId: userId,
                              oldChildId: _satorToSpv[userId],
                              newChildId: role == 'sator' ? supervisorId : null,
                            );
                          }
                          if (oldRole == 'promotor' || role == 'promotor') {
                            await _saveSingleAssignment(
                              tableName: 'hierarchy_sator_promotor',
                              parentColumn: 'promotor_id',
                              childColumn: 'sator_id',
                              parentId: userId,
                              oldChildId: _promotorToSator[userId],
                              newChildId: role == 'promotor' ? supervisorId : null,
                            );
                            await _saveSingleAssignment(
                              tableName: 'assignments_promotor_store',
                              parentColumn: 'promotor_id',
                              childColumn: 'store_id',
                              parentId: userId,
                              oldChildId: _promotorToStore[userId],
                              newChildId: role == 'promotor' ? storeId : null,
                            );
                          }

                          if (!dialogContext.mounted) return;
                          Navigator.pop(dialogContext);
                          await _loadUsers();
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('User berhasil diperbarui')),
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() => isSubmitting = false);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Gagal update user: $e'),
                              backgroundColor: AppColors.danger,
                            ),
                          );
                        }
                      },
                child: Text(isSubmitting ? 'Menyimpan...' : 'Simpan'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusChip(String value) {
    final color = _getStatusColor(value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildRoleChip(String role) {
    final roleColor = _getRoleColor(role);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: roleColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        role.toUpperCase(),
        style: TextStyle(
          color: roleColor,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metrics = [
      ('Admin', _countRole('admin').toString(), Colors.purple),
      ('Manager', _countRole('manager').toString(), Colors.indigo),
      ('SPV', _countRole('spv').toString(), AppColors.info),
      ('Sator', _countRole('sator').toString(), AppColors.primary),
      ('Promotor', _countRole('promotor').toString(), AppColors.success),
    ];

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            onPressed: _loadUsers,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateUserDialog,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Tambah User'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildMetricCard('Total', '${_users.length}', AppColors.primary),
                    const SizedBox(width: 10),
                    _buildMetricCard(
                      'Aktif',
                      '${_users.where((u) => '${u['status'] ?? 'active'}' == 'active').length}',
                      AppColors.success,
                    ),
                    const SizedBox(width: 10),
                    _buildMetricCard(
                      'Nonaktif',
                      '${_users.where((u) => '${u['status'] ?? 'active'}' != 'active').length}',
                      AppColors.danger,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 82,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: metrics.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 10),
                    itemBuilder: (context, index) {
                      final metric = metrics[index];
                      return SizedBox(
                        width: 124,
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                metric.$2,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: metric.$3,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                metric.$1,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              children: [
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Cari nama, nickname, email, area...',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                  onChanged: (value) => setState(() => _searchQuery = value),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _filterRole,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Semua Role')),
                          DropdownMenuItem(value: 'admin', child: Text('Admin')),
                          DropdownMenuItem(value: 'manager', child: Text('Manager')),
                          DropdownMenuItem(value: 'spv', child: Text('SPV')),
                          DropdownMenuItem(value: 'sator', child: Text('SATOR')),
                          DropdownMenuItem(value: 'promotor', child: Text('Promotor')),
                        ],
                        onChanged: (value) =>
                            setState(() => _filterRole = value ?? 'all'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _filterStatus,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(value: 'all', child: Text('Semua Status')),
                          DropdownMenuItem(value: 'active', child: Text('Active')),
                          DropdownMenuItem(value: 'inactive', child: Text('Inactive')),
                          DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
                        ],
                        onChanged: (value) =>
                            setState(() => _filterStatus = value ?? 'all'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? const Center(child: Text('Tidak ada user'))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
                        itemCount: _filteredUsers.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final user = _filteredUsers[index];
                          final role = '${user['role'] ?? '-'}';
                          final roleColor = _getRoleColor(role);
                          final status = '${user['status'] ?? 'active'}';
                          final nickname = '${user['nickname'] ?? ''}'.trim();
                          final promotorType =
                              '${user['promotor_type'] ?? user['promotor_status'] ?? ''}'
                                  .trim();
                          return Card(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => _showEditUserDialog(user),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        CircleAvatar(
                                          radius: 24,
                                          backgroundColor: roleColor.withValues(alpha: 0.15),
                                          child: Text(
                                            '${user['full_name'] ?? 'U'}'
                                                .substring(0, 1)
                                                .toUpperCase(),
                                            style: TextStyle(
                                              color: roleColor,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                '${user['full_name'] ?? '-'}',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                ),
                                              ),
                                              if (nickname.isNotEmpty) ...[
                                                const SizedBox(height: 2),
                                                Text(
                                                  nickname,
                                                  style: const TextStyle(
                                                    color: AppColors.textSecondary,
                                                  ),
                                                ),
                                              ],
                                              const SizedBox(height: 4),
                                              Text(
                                                '${user['email'] ?? '-'}',
                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${user['area'] ?? '-'}',
                                                style: const TextStyle(
                                                  color: AppColors.textSecondary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        PopupMenuButton<String>(
                                          onSelected: (value) {
                                            if (value == 'edit') {
                                              _showEditUserDialog(user);
                                            } else if (value == 'toggle') {
                                              _toggleUserStatus(user);
                                            } else if (value == 'delete') {
                                              _softDeleteUser(user);
                                            }
                                          },
                                          itemBuilder: (context) => [
                                            const PopupMenuItem(
                                              value: 'edit',
                                              child: Text('Edit User'),
                                            ),
                                            PopupMenuItem(
                                              value: 'toggle',
                                              child: Text(
                                                status == 'active'
                                                    ? 'Nonaktifkan'
                                                    : 'Aktifkan',
                                              ),
                                            ),
                                            const PopupMenuItem(
                                              value: 'delete',
                                              child: Text('Hapus User'),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _buildRoleChip(role),
                                        _buildStatusChip(status),
                                        if (promotorType.isNotEmpty)
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.warning.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              promotorType.toUpperCase(),
                                              style: const TextStyle(
                                                color: AppColors.warning,
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
