import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';
import '../widgets/admin_dialog_sync.dart';

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
  final TextEditingController _officialSalaryController = TextEditingController(
    text: 'Rp 0',
  );
  final TextEditingController _trainingSalaryController = TextEditingController(
    text: 'Rp 0',
  );
  final TextEditingController _satorSalaryController = TextEditingController(
    text: 'Rp 0',
  );

  bool _isLoading = true;
  bool _isSavingSalarySettings = false;
  String _searchQuery = '';
  String _filterRole = 'all';
  String _filterStatus = 'all';
  num _officialSalary = 0;
  num _trainingSalary = 0;
  num _satorSalary = 0;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  @override
  void dispose() {
    _officialSalaryController.dispose();
    _trainingSalaryController.dispose();
    _satorSalaryController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final query = _searchQuery.trim().toLowerCase();
    return _users.where((user) {
      if (_filterRole != 'all' && '${user['role']}' != _filterRole) {
        return false;
      }
      if (_filterStatus != 'all' &&
          '${user['status'] ?? 'active'}' != _filterStatus) {
        return false;
      }
      if (query.isEmpty) return true;
      final fullName = '${user['full_name'] ?? ''}'.toLowerCase();
      final nickname = '${user['nickname'] ?? ''}'.toLowerCase();
      final email = '${user['email'] ?? ''}'.toLowerCase();
      final whatsappPhone = '${user['whatsapp_phone'] ?? ''}'.toLowerCase();
      final area = '${user['area'] ?? ''}'.toLowerCase();
      return fullName.contains(query) ||
          nickname.contains(query) ||
          email.contains(query) ||
          whatsappPhone.contains(query) ||
          area.contains(query);
    }).toList();
  }

  Future<void> _loadUsers() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      Future<dynamic> usersReq() async {
        try {
          return await supabase
              .from('users')
              .select(
                'id, full_name, nickname, email, role, area, status, created_at, hire_date, promotor_type, promotor_status, base_salary, whatsapp_phone',
              )
              .isFilter('deleted_at', null)
              .order('created_at', ascending: false);
        } catch (_) {
          return supabase
              .from('users')
              .select(
                'id, full_name, nickname, email, role, area, status, created_at, hire_date, promotor_type, promotor_status, base_salary',
              )
              .isFilter('deleted_at', null)
              .order('created_at', ascending: false);
        }
      }

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
      final salarySettingsReq = supabase
          .from('promotor_salary_settings')
          .select('promotor_type, amount');

      final results = await Future.wait([
        usersReq(),
        storesReq,
        managerSpvReq,
        spvSatorReq,
        satorPromotorReq,
        promotorStoreReq,
        salarySettingsReq,
      ]);
      final users = List<Map<String, dynamic>>.from(results[0] as List);
      final stores = List<Map<String, dynamic>>.from(results[1] as List);
      final managerSpv = List<Map<String, dynamic>>.from(results[2] as List);
      final spvSator = List<Map<String, dynamic>>.from(results[3] as List);
      final satorPromotor = List<Map<String, dynamic>>.from(results[4] as List);
      final promotorStore = List<Map<String, dynamic>>.from(results[5] as List);
      final salarySettings = List<Map<String, dynamic>>.from(
        results[6] as List,
      );
      num officialSalary = 0;
      num trainingSalary = 0;
      num satorSalary = 0;
      for (final row in salarySettings) {
        final type = '${row['promotor_type'] ?? ''}'.trim().toLowerCase();
        final amount = row['amount'] is num
            ? row['amount'] as num
            : num.tryParse('${row['amount'] ?? ''}') ?? 0;
        if (type == 'official') officialSalary = amount;
        if (type == 'training') trainingSalary = amount;
        if (type == 'sator') satorSalary = amount;
      }

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
        _officialSalary = officialSalary;
        _trainingSalary = trainingSalary;
        _satorSalary = satorSalary;
        _officialSalaryController.text = _formatCurrency(officialSalary);
        _trainingSalaryController.text = _formatCurrency(trainingSalary);
        _satorSalaryController.text = _formatCurrency(satorSalary);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  String _formatHireDate(dynamic value) {
    final raw = '$value'.trim();
    if (raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('dd MMM yyyy', 'id_ID').format(parsed);
  }

  DateTime? _parseHireDate(dynamic value) {
    final raw = '$value'.trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }

  String _formatCurrency(dynamic value) {
    final amount = value is num ? value : num.tryParse('${value ?? ''}') ?? 0;
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(amount);
  }

  num _parseCurrency(dynamic value) {
    final digits = '$value'.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return 0;
    return num.tryParse(digits) ?? 0;
  }

  num _salaryForPromotorType(String type) {
    return type == 'official' ? _officialSalary : _trainingSalary;
  }

  num _salaryForRole(String role, {String promotorType = 'training'}) {
    if (role == 'promotor') {
      return _salaryForPromotorType(promotorType);
    }
    if (role == 'sator') {
      return _satorSalary;
    }
    return 0;
  }

  void _handleSalaryFieldTap(TextEditingController controller) {
    if (_parseCurrency(controller.text) == 0) {
      controller.clear();
      return;
    }
    controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: controller.text.length,
    );
  }

  Future<void> _savePromotorSalarySettings() async {
    if (_isSavingSalarySettings) return;
    final officialSalary = _parseCurrency(_officialSalaryController.text);
    final trainingSalary = _parseCurrency(_trainingSalaryController.text);
    final satorSalary = _parseCurrency(_satorSalaryController.text);
    if (!mounted) return;
    setState(() => _isSavingSalarySettings = true);
    try {
      await supabase.from('promotor_salary_settings').upsert([
        {'promotor_type': 'official', 'amount': officialSalary},
        {'promotor_type': 'training', 'amount': trainingSalary},
        {'promotor_type': 'sator', 'amount': satorSalary},
      ], onConflict: 'promotor_type');
      await supabase
          .from('users')
          .update({'base_salary': officialSalary})
          .eq('role', 'promotor')
          .or('promotor_type.eq.official,promotor_status.eq.official');
      await supabase
          .from('users')
          .update({'base_salary': trainingSalary})
          .eq('role', 'promotor')
          .or('promotor_type.eq.training,promotor_status.eq.training');
      await supabase
          .from('users')
          .update({'base_salary': satorSalary})
          .eq('role', 'sator');
      await _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gaji promotor berhasil diperbarui')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal simpan gaji promotor: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSavingSalarySettings = false);
      }
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

  int _countRole(String role) {
    return _users.where((row) => row['role'] == role).length;
  }

  Future<void> _updatePromotorType(
    Map<String, dynamic> user,
    String nextType,
  ) async {
    final role = '${user['role'] ?? ''}';
    if (role != 'promotor') return;
    final currentType =
        '${user['promotor_type'] ?? user['promotor_status'] ?? 'training'}';
    if (currentType == nextType) return;
    try {
      await supabase
          .from('users')
          .update({
            'promotor_type': nextType,
            'promotor_status': nextType,
            'base_salary': _salaryForPromotorType(nextType),
          })
          .eq('id', user['id']);
      await _loadUsers();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Jenis promotor diubah ke $nextType')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal ubah jenis promotor: $e'),
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
    if (oldChildId != null &&
        oldChildId.isNotEmpty &&
        oldChildId != newChildId) {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('User berhasil dihapus')));
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
    final messenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>(debugLabel: 'admin_users_create_form');
    final fullNameC = TextEditingController();
    final nickNameC = TextEditingController();
    final emailC = TextEditingController();
    final passwordC = TextEditingController();
    final areaC = TextEditingController();
    final whatsappPhoneC = TextEditingController();

    String role = 'promotor';
    String promotorStatus = 'training';
    String? supervisorId;
    String? storeId;
    DateTime? hireDate;
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

    await showAdminChangedDialog(
      context: context,
      onChanged: _loadUsers,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final supervisorOptions = getSupervisorOptions(role);
          final needsSupervisor =
              role == 'spv' || role == 'sator' || role == 'promotor';
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
                        decoration: const InputDecoration(
                          labelText: 'Nama lengkap',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nickNameC,
                        decoration: const InputDecoration(
                          labelText: 'Nama panggilan',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailC,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordC,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: areaC,
                        decoration: const InputDecoration(labelText: 'Area'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: whatsappPhoneC,
                        decoration: const InputDecoration(
                          labelText: 'Nomor WhatsApp',
                          hintText: '08xxxxxxxxxx',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: hireDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => hireDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Tanggal masuk',
                            suffixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(
                            hireDate == null
                                ? '-'
                                : _formatHireDate(hireDate!.toIso8601String()),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Admin'),
                          ),
                          DropdownMenuItem(
                            value: 'manager',
                            child: Text('Manager'),
                          ),
                          DropdownMenuItem(value: 'spv', child: Text('SPV')),
                          DropdownMenuItem(
                            value: 'sator',
                            child: Text('SATOR'),
                          ),
                          DropdownMenuItem(
                            value: 'promotor',
                            child: Text('Promotor'),
                          ),
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
                          decoration: const InputDecoration(
                            labelText: 'Tipe Promotor',
                          ),
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
                          onChanged: (value) =>
                              setDialogState(() => storeId = value),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => closeAdminDialog(dialogContext),
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
                              'area': areaC.text.trim().isEmpty
                                  ? null
                                  : areaC.text.trim(),
                              'whatsapp_phone':
                                  whatsappPhoneC.text.trim().isEmpty
                                  ? null
                                  : whatsappPhoneC.text.trim(),
                              'base_salary': _salaryForRole(
                                role,
                                promotorType: promotorStatus,
                              ),
                              'hire_date': hireDate
                                  ?.toIso8601String()
                                  .split('T')
                                  .first,
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
                          closeAdminDialog(dialogContext, changed: true);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('User berhasil dibuat'),
                            ),
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() => isSubmitting = false);
                          messenger.showSnackBar(
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
    final messenger = ScaffoldMessenger.of(context);
    final formKey = GlobalKey<FormState>(debugLabel: 'admin_users_edit_form');
    final fullNameC = TextEditingController(text: '${user['full_name'] ?? ''}');
    final nickNameC = TextEditingController(text: '${user['nickname'] ?? ''}');
    final areaC = TextEditingController(text: '${user['area'] ?? ''}');
    final whatsappPhoneC = TextEditingController(
      text: '${user['whatsapp_phone'] ?? ''}',
    );

    String role = '${user['role'] ?? 'promotor'}';
    String status = '${user['status'] ?? 'active'}';
    String promotorType =
        '${user['promotor_type'] ?? user['promotor_status'] ?? 'training'}';
    String? supervisorId = switch (role) {
      'spv' => _spvToManager['${user['id']}'],
      'sator' => _satorToSpv['${user['id']}'],
      'promotor' => _promotorToSator['${user['id']}'],
      _ => null,
    };
    String? storeId = role == 'promotor'
        ? _promotorToStore['${user['id']}']
        : null;
    DateTime? hireDate = _parseHireDate(user['hire_date']);
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

    await showAdminChangedDialog(
      context: context,
      onChanged: _loadUsers,
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
                        decoration: const InputDecoration(
                          labelText: 'Nama lengkap',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Wajib diisi'
                            : null,
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
                        decoration: const InputDecoration(
                          labelText: 'Nama panggilan',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: areaC,
                        decoration: const InputDecoration(labelText: 'Area'),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: whatsappPhoneC,
                        decoration: const InputDecoration(
                          labelText: 'Nomor WhatsApp',
                          hintText: '08xxxxxxxxxx',
                        ),
                        keyboardType: TextInputType.phone,
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: hireDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => hireDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Tanggal masuk',
                            suffixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(
                            hireDate == null
                                ? '-'
                                : _formatHireDate(hireDate!.toIso8601String()),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: role,
                        decoration: const InputDecoration(labelText: 'Role'),
                        items: const [
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Admin'),
                          ),
                          DropdownMenuItem(
                            value: 'manager',
                            child: Text('Manager'),
                          ),
                          DropdownMenuItem(value: 'spv', child: Text('SPV')),
                          DropdownMenuItem(
                            value: 'sator',
                            child: Text('SATOR'),
                          ),
                          DropdownMenuItem(
                            value: 'promotor',
                            child: Text('Promotor'),
                          ),
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
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('Inactive'),
                          ),
                          DropdownMenuItem(
                            value: 'suspended',
                            child: Text('Suspended'),
                          ),
                        ],
                        onChanged: (value) =>
                            setDialogState(() => status = value ?? 'active'),
                      ),
                      if (role == 'promotor') ...[
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: promotorType,
                          decoration: const InputDecoration(
                            labelText: 'Tipe Promotor',
                          ),
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
                          onChanged: (value) =>
                              setDialogState(() => storeId = value),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => closeAdminDialog(dialogContext),
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
                                'whatsapp_phone':
                                    whatsappPhoneC.text.trim().isEmpty
                                    ? null
                                    : whatsappPhoneC.text.trim(),
                                'base_salary': _salaryForRole(
                                  role,
                                  promotorType: promotorType,
                                ),
                                'hire_date': hireDate
                                    ?.toIso8601String()
                                    .split('T')
                                    .first,
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
                              newChildId: role == 'promotor'
                                  ? supervisorId
                                  : null,
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
                          closeAdminDialog(dialogContext, changed: true);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text('User berhasil diperbarui'),
                            ),
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() => isSubmitting = false);
                          messenger.showSnackBar(
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

  Future<void> _showEditNicknameDialog(Map<String, dynamic> user) async {
    final messenger = ScaffoldMessenger.of(context);
    final nicknameC = TextEditingController(text: '${user['nickname'] ?? ''}');
    bool isSubmitting = false;

    await showAdminChangedDialog(
      context: context,
      onChanged: _loadUsers,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Ubah Nama Panggilan'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${user['full_name'] ?? '-'}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nicknameC,
                    decoration: const InputDecoration(
                      labelText: 'Nama panggilan (boleh kosong)',
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => closeAdminDialog(dialogContext),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        setDialogState(() => isSubmitting = true);
                        try {
                          await supabase
                              .from('users')
                              .update({
                                'nickname': nicknameC.text.trim().isEmpty
                                    ? null
                                    : nicknameC.text.trim(),
                              })
                              .eq('id', user['id']);
                          if (!dialogContext.mounted) return;
                          closeAdminDialog(dialogContext, changed: true);
                          messenger.showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Nama panggilan berhasil diperbarui',
                              ),
                            ),
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() => isSubmitting = false);
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text('Gagal update nama panggilan: $e'),
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
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

  Widget _buildMiniMetricPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotorSalaryPanel() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.textSecondary.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gaji Kategori Role',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Dipakai otomatis saat buat user, edit user, atau ubah tipe promotor.',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _isSavingSalarySettings
                    ? null
                    : _savePromotorSalarySettings,
                icon: const Icon(Icons.save_outlined, size: 18),
                label: Text(
                  _isSavingSalarySettings ? 'Menyimpan...' : 'Simpan Gaji',
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: _officialSalaryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [_RupiahInputFormatter()],
                  onTap: () => _handleSalaryFieldTap(_officialSalaryController),
                  decoration: const InputDecoration(
                    labelText: 'Promotor Official',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _trainingSalaryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [_RupiahInputFormatter()],
                  onTap: () => _handleSalaryFieldTap(_trainingSalaryController),
                  decoration: const InputDecoration(
                    labelText: 'Promotor Training',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _satorSalaryController,
            keyboardType: TextInputType.number,
            inputFormatters: const [_RupiahInputFormatter()],
            onTap: () => _handleSalaryFieldTap(_satorSalaryController),
            decoration: const InputDecoration(labelText: 'SATOR'),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotorTypeDropdown(Map<String, dynamic> user) {
    final promotorType =
        '${user['promotor_type'] ?? user['promotor_status'] ?? 'training'}';
    final typeColor = promotorType == 'official'
        ? AppColors.success
        : AppColors.warning;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: typeColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: typeColor.withValues(alpha: 0.18)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: promotorType,
          isDense: true,
          style: TextStyle(
            color: typeColor,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
          items: const [
            DropdownMenuItem(value: 'official', child: Text('OFFICIAL')),
            DropdownMenuItem(value: 'training', child: Text('TRAINING')),
          ],
          onChanged: (value) {
            if (value != null) {
              _updatePromotorType(user, value);
            }
          },
        ),
      ),
    );
  }

  Widget _buildDesktopUserTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: AppColors.textSecondary.withValues(alpha: 0.12),
          ),
        ),
        child: DataTable(
          columnSpacing: 16,
          horizontalMargin: 12,
          headingRowHeight: 42,
          dataRowMinHeight: 58,
          dataRowMaxHeight: 64,
          columns: const [
            DataColumn(label: Text('User')),
            DataColumn(label: Text('Nickname')),
            DataColumn(label: Text('Role')),
            DataColumn(label: Text('Jenis')),
            DataColumn(label: Text('Gaji')),
            DataColumn(label: Text('Tanggal Masuk')),
            DataColumn(label: Text('Area')),
            DataColumn(label: Text('Email')),
            DataColumn(label: Text('Aksi')),
          ],
          rows: _filteredUsers.map((user) {
            final role = '${user['role'] ?? '-'}';
            final nickname = '${user['nickname'] ?? ''}'.trim();
            return DataRow(
              cells: [
                DataCell(
                  InkWell(
                    onTap: () => _showEditUserDialog(user),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${user['full_name'] ?? '-'}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        if (nickname.isNotEmpty)
                          Text(
                            nickname,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          nickname.isEmpty ? '-' : nickname,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: nickname.isEmpty
                                ? AppColors.textSecondary
                                : AppColors.textPrimary,
                            fontWeight: nickname.isEmpty
                                ? FontWeight.w500
                                : FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit nickname',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _showEditNicknameDialog(user),
                        icon: const Icon(
                          Icons.drive_file_rename_outline,
                          size: 16,
                        ),
                      ),
                    ],
                  ),
                ),
                DataCell(_buildRoleChip(role)),
                DataCell(
                  role == 'promotor'
                      ? _buildPromotorTypeDropdown(user)
                      : const Text('-'),
                ),
                DataCell(Text(_formatCurrency(user['base_salary']))),
                DataCell(Text(_formatHireDate(user['hire_date']))),
                DataCell(
                  Text(
                    '${user['area'] ?? '-'}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 220,
                    child: Text(
                      '${user['email'] ?? '-'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Edit',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _showEditUserDialog(user),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                      ),
                      IconButton(
                        tooltip: 'Hapus',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _softDeleteUser(user),
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 18,
                          color: AppColors.danger,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCompactUserList() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 90),
      itemCount: _filteredUsers.length,
      separatorBuilder: (_, _) => const SizedBox(height: 6),
      itemBuilder: (context, index) {
        final user = _filteredUsers[index];
        final role = '${user['role'] ?? '-'}';
        final roleColor = _getRoleColor(role);
        final nickname = '${user['nickname'] ?? ''}'.trim();
        return Material(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _showEditUserDialog(user),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: roleColor.withValues(alpha: 0.15),
                    child: Text(
                      '${user['full_name'] ?? 'U'}'
                          .substring(0, 1)
                          .toUpperCase(),
                      style: TextStyle(
                        color: roleColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${user['full_name'] ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          nickname.isNotEmpty
                              ? '$nickname • ${user['area'] ?? '-'}'
                              : '${user['area'] ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          'Masuk ${_formatHireDate(user['hire_date'])}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (role == 'promotor')
                          Text(
                            'Gaji ${_formatCurrency(user['base_salary'])}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        Text(
                          '${user['email'] ?? '-'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  role == 'promotor'
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildRoleChip(role),
                            const SizedBox(height: 6),
                            _buildPromotorTypeDropdown(user),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 24,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  minimumSize: const Size(0, 24),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _showEditNicknameDialog(user),
                                child: const Text(
                                  'Nickname',
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            ),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _buildRoleChip(role),
                            const SizedBox(height: 4),
                            SizedBox(
                              height: 24,
                              child: TextButton(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  minimumSize: const Size(0, 24),
                                  tapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                ),
                                onPressed: () => _showEditNicknameDialog(user),
                                child: const Text(
                                  'Nickname',
                                  style: TextStyle(fontSize: 11),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
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
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Column(
              children: [
                Row(
                  children: [
                    _buildMetricCard(
                      'Total',
                      '${_users.length}',
                      AppColors.primary,
                    ),
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
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: metrics
                        .map(
                          (metric) => _buildMiniMetricPill(
                            metric.$1,
                            metric.$2,
                            metric.$3,
                          ),
                        )
                        .toList(),
                  ),
                ),
                const SizedBox(height: 10),
                _buildPromotorSalaryPanel(),
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
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Semua Role'),
                          ),
                          DropdownMenuItem(
                            value: 'admin',
                            child: Text('Admin'),
                          ),
                          DropdownMenuItem(
                            value: 'manager',
                            child: Text('Manager'),
                          ),
                          DropdownMenuItem(value: 'spv', child: Text('SPV')),
                          DropdownMenuItem(
                            value: 'sator',
                            child: Text('SATOR'),
                          ),
                          DropdownMenuItem(
                            value: 'promotor',
                            child: Text('Promotor'),
                          ),
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
                          DropdownMenuItem(
                            value: 'all',
                            child: Text('Semua Status'),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text('Active'),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text('Inactive'),
                          ),
                          DropdownMenuItem(
                            value: 'suspended',
                            child: Text('Suspended'),
                          ),
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
                : isDesktop
                ? _buildDesktopUserTable()
                : _buildCompactUserList(),
          ),
        ],
      ),
    );
  }
}

class _RupiahInputFormatter extends TextInputFormatter {
  const _RupiahInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }
    final formatted = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(num.tryParse(digits) ?? 0);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
