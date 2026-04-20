import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../ui/foundation/app_colors.dart';

class AdminSystemGroupsPage extends StatefulWidget {
  const AdminSystemGroupsPage({super.key});

  @override
  State<AdminSystemGroupsPage> createState() => _AdminSystemGroupsPageState();
}

class _AdminSystemGroupsPageState extends State<AdminSystemGroupsPage> {
  final TextEditingController _searchController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _groups = [];
  List<_OwnerOption> _owners = [];
  bool _isLoading = true;
  bool _isSaving = false;
  String _kindFilter = 'all';
  String _statusFilter = 'all';
  String? _ownerFilterId;

  @override
  void initState() {
    super.initState();
    _loadInitial();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitial() async {
    await Future.wait<void>([_loadOwners(), _loadGroups()]);
  }

  Future<void> _loadOwners() async {
    try {
      final rows = await _supabase
          .from('users')
          .select('id, full_name, nickname, role')
          .inFilter('role', ['sator', 'spv'])
          .isFilter('deleted_at', null)
          .order('role')
          .order('full_name');
      if (!mounted) return;
      setState(() {
        _owners = List<Map<String, dynamic>>.from(
          rows,
        ).map(_OwnerOption.fromMap).toList();
      });
    } catch (e) {
      debugPrint('Error loading group owners: $e');
    }
  }

  Future<void> _loadGroups() async {
    try {
      if (mounted) {
        setState(() => _isLoading = true);
      }
      final rows = await _supabase.rpc(
        'get_system_chat_groups_admin',
        params: {
          'p_group_kind': _kindFilter == 'all' ? null : _kindFilter,
          'p_status': _statusFilter,
          'p_owner_user_id': _ownerFilterId,
          'p_search': _searchController.text.trim().isEmpty
              ? null
              : _searchController.text.trim(),
          'p_include_unclassified': true,
        },
      );
      if (!mounted) return;
      setState(() {
        _groups = List<Map<String, dynamic>>.from(rows ?? const []);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading system groups: $e');
      if (!mounted) return;
      setState(() {
        _groups = [];
        _isLoading = false;
      });
      _showSnack('Gagal memuat grup sistem. $e');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _setGroupActive(Map<String, dynamic> row, bool active) async {
    try {
      await _supabase.rpc(
        'set_chat_group_active_admin',
        params: {'p_room_id': row['room_id'], 'p_is_active': active},
      );
      await _loadGroups();
      _showSnack(active ? 'Grup diaktifkan.' : 'Grup dinonaktifkan.');
    } catch (e) {
      _showSnack('Gagal mengubah status grup. $e');
    }
  }

  Future<void> _syncGroup(Map<String, dynamic> row) async {
    try {
      await _supabase.rpc(
        'sync_system_chat_group_members',
        params: {'p_room_id': row['room_id']},
      );
      await _loadGroups();
      _showSnack('Anggota grup berhasil disinkronkan.');
    } catch (e) {
      _showSnack('Gagal sync anggota grup. $e');
    }
  }

  Future<void> _deleteGroup(Map<String, dynamic> row) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Hapus Grup'),
          content: Text(
            'Yakin hapus grup "${row['room_name'] ?? 'Tanpa Nama'}"? Semua chat akan terhapus.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Batal'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Hapus'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    try {
      await _supabase.rpc(
        'delete_chat_group_admin',
        params: {'p_room_id': row['room_id']},
      );
      await _loadGroups();
      _showSnack('Grup berhasil dihapus.');
    } catch (e) {
      _showSnack('Gagal hapus grup. $e');
    }
  }

  Future<void> _openGroupDialog({Map<String, dynamic>? initialRow}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: !_isSaving,
      builder: (context) {
        return _SystemGroupDialog(
          owners: _owners,
          initialRow: initialRow,
          onSubmit:
              (kind, ownerId, chatTab, name, description, isActive) async {
                setState(() => _isSaving = true);
                try {
                  if (initialRow == null) {
                    final roomId = await _supabase.rpc(
                      'create_system_chat_group',
                      params: {
                        'p_room_type': _roomTypeForKind(kind),
                        'p_group_kind': kind,
                        'p_owner_user_id': ownerId,
                        'p_name': name,
                        'p_description': description,
                        'p_is_active': isActive,
                      },
                    );
                    await _supabase.rpc(
                      'set_chat_group_tab_admin',
                      params: {'p_room_id': roomId, 'p_chat_tab': chatTab},
                    );
                  } else {
                    await _supabase.rpc(
                      'reclassify_system_chat_group',
                      params: {
                        'p_room_id': initialRow['room_id'],
                        'p_room_type': _roomTypeForKind(kind),
                        'p_group_kind': kind,
                        'p_owner_user_id': ownerId,
                        'p_name': name,
                        'p_description': description,
                        'p_is_active': isActive,
                      },
                    );
                    await _supabase.rpc(
                      'set_chat_group_tab_admin',
                      params: {
                        'p_room_id': initialRow['room_id'],
                        'p_chat_tab': chatTab,
                      },
                    );
                  }
                  if (!mounted) return;
                  Navigator.of(this.context, rootNavigator: true).pop(true);
                } catch (e) {
                  _showSnack('Gagal menyimpan grup. $e');
                } finally {
                  if (mounted) {
                    setState(() => _isSaving = false);
                  }
                }
              },
        );
      },
    );
    if (result == true) {
      await _loadGroups();
      _showSnack(
        initialRow == null
            ? 'Grup sistem berhasil dibuat.'
            : 'Grup sistem berhasil diperbarui.',
      );
    }
  }

  String _roomTypeForKind(String kind) =>
      kind == 'spv_leader' ? 'leader' : 'tim';

  String _chatTabLabel(String? chatTab) {
    switch ((chatTab ?? '').toLowerCase()) {
      case 'team':
      case 'tim':
        return 'Tab: Tim';
      case 'global':
        return 'Tab: Global';
      case 'announcement':
      case 'info':
        return 'Tab: Info';
      case 'store':
      case 'toko':
        return 'Tab: Toko';
      default:
        return 'Tab: Otomatis';
    }
  }

  String _kindLabel(String? kind) {
    switch (kind) {
      case 'sator_main':
        return 'Grup Utama SATOR';
      case 'spv_leader':
        return 'Grup Leader SPV';
      default:
        return 'Belum diklasifikasi';
    }
  }

  Color _kindColor(String? kind) {
    switch (kind) {
      case 'sator_main':
        return AppColors.success;
      case 'spv_leader':
        return AppColors.info;
      default:
        return AppColors.warning;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _isSaving ? null : () => _openGroupDialog(),
        icon: const Icon(Icons.add),
        label: const Text('Buat Grup Sistem'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadGroups,
        child: ListView(
          padding: EdgeInsets.all(isDesktop ? 24 : 16),
          children: [
            Text(
              'Grup Sistem',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Kelola grup hierarchy untuk SATOR dan SPV, klasifikasikan grup lama, lalu sinkronkan anggota otomatis.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 20),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  children: [
                    SizedBox(
                      width: isDesktop ? 240 : double.infinity,
                      child: TextField(
                        controller: _searchController,
                        decoration: const InputDecoration(
                          labelText: 'Cari grup / owner',
                          prefixIcon: Icon(Icons.search),
                        ),
                        onSubmitted: (_) => _loadGroups(),
                      ),
                    ),
                    SizedBox(
                      width: isDesktop ? 200 : double.infinity,
                      child: DropdownButtonFormField<String>(
                        initialValue: _kindFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Tipe Grup',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(
                              'Semua',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'sator_main',
                            child: Text(
                              'Grup Utama SATOR',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'spv_leader',
                            child: Text(
                              'Grup Leader SPV',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _kindFilter = value ?? 'all'),
                      ),
                    ),
                    SizedBox(
                      width: isDesktop ? 170 : double.infinity,
                      child: DropdownButtonFormField<String>(
                        initialValue: _statusFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Status'),
                        items: const [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(
                              'Semua',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'active',
                            child: Text(
                              'Aktif',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'inactive',
                            child: Text(
                              'Nonaktif',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 'unclassified',
                            child: Text(
                              'Belum diklasifikasi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _statusFilter = value ?? 'all'),
                      ),
                    ),
                    SizedBox(
                      width: isDesktop ? 240 : double.infinity,
                      child: DropdownButtonFormField<String?>(
                        initialValue: _ownerFilterId,
                        isExpanded: true,
                        decoration: const InputDecoration(labelText: 'Owner'),
                        items: [
                          const DropdownMenuItem<String?>(
                            value: null,
                            child: Text(
                              'Semua owner',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          ..._owners.map(
                            (owner) => DropdownMenuItem<String?>(
                              value: owner.id,
                              child: Text(
                                owner.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _ownerFilterId = value),
                      ),
                    ),
                    FilledButton.icon(
                      onPressed: _loadGroups,
                      icon: const Icon(Icons.filter_alt),
                      label: const Text('Terapkan'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.only(top: 48),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_groups.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Belum ada grup yang cocok dengan filter ini.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              )
            else
              ..._groups.map(_buildGroupCard),
          ],
        ),
      ),
    );
  }

  Widget _buildGroupCard(Map<String, dynamic> row) {
    final isSystem = '${row['group_mode'] ?? ''}' == 'system';
    final isActive = row['is_active'] == true;
    final kind = row['system_group_kind']?.toString();
    final ownerName = '${row['owner_name'] ?? '-'}';
    final ownerRole = '${row['owner_role'] ?? '-'}'.toUpperCase();
    final description = '${row['room_description'] ?? ''}'.trim();
    final tone = _kindColor(kind);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['room_name'] ?? '-'}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _buildBadge(_kindLabel(kind), tone),
                          _buildBadge(
                            isActive ? 'Aktif' : 'Nonaktif',
                            isActive ? AppColors.success : AppColors.warning,
                          ),
                          _buildBadge(
                            isSystem ? 'Sistem' : 'Perlu klasifikasi',
                            isSystem ? AppColors.info : AppColors.warning,
                          ),
                          _buildBadge(
                            '${row['member_count'] ?? 0} anggota',
                            AppColors.textSecondary,
                          ),
                          _buildBadge(
                            _chatTabLabel(row['chat_tab']?.toString()),
                            AppColors.info,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _openGroupDialog(initialRow: row);
                        break;
                      case 'sync':
                        _syncGroup(row);
                        break;
                      case 'toggle':
                        _setGroupActive(row, !isActive);
                        break;
                      case 'delete':
                        _deleteGroup(row);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text(isSystem ? 'Edit Grup' : 'Tetapkan Tipe'),
                    ),
                    if (isSystem)
                      const PopupMenuItem(
                        value: 'sync',
                        child: Text('Sync Anggota'),
                      ),
                    PopupMenuItem(
                      value: 'toggle',
                      child: Text(isActive ? 'Nonaktifkan' : 'Aktifkan'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Hapus Grup'),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$ownerRole • $ownerName',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(description, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _SystemGroupDialog extends StatefulWidget {
  const _SystemGroupDialog({
    required this.owners,
    required this.onSubmit,
    this.initialRow,
  });

  final List<_OwnerOption> owners;
  final Map<String, dynamic>? initialRow;
  final Future<void> Function(
    String kind,
    String ownerId,
    String chatTab,
    String name,
    String description,
    bool isActive,
  )
  onSubmit;

  @override
  State<_SystemGroupDialog> createState() => _SystemGroupDialogState();
}

class _SystemGroupDialogState extends State<_SystemGroupDialog> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final SupabaseClient _supabase = Supabase.instance.client;

  String _kind = 'sator_main';
  String _chatTab = 'team';
  String? _ownerId;
  bool _isActive = true;
  bool _isPreviewLoading = false;
  List<Map<String, dynamic>> _previewMembers = [];

  bool get _isExisting => widget.initialRow != null;

  @override
  void initState() {
    super.initState();
    final row = widget.initialRow;
    if (row != null) {
      _kind = '${row['system_group_kind'] ?? 'sator_main'}';
      _chatTab = '${row['chat_tab'] ?? 'team'}';
      _ownerId = row['system_owner_user_id']?.toString();
      _isActive = row['is_active'] == true;
      _nameController.text = '${row['room_name'] ?? ''}';
      _descriptionController.text = '${row['room_description'] ?? ''}';
    }
    _syncOwnerWithKind();
    _loadPreview();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  List<_OwnerOption> get _filteredOwners => widget.owners.where((owner) {
    if (_kind == 'sator_main') return owner.role == 'sator';
    return owner.role == 'spv';
  }).toList();

  void _syncOwnerWithKind() {
    if (_ownerId == null) return;
    final stillValid = _filteredOwners.any((owner) => owner.id == _ownerId);
    if (!stillValid) {
      _ownerId = _filteredOwners.isEmpty ? null : _filteredOwners.first.id;
    }
  }

  Future<void> _loadPreview() async {
    if (_ownerId == null) {
      setState(() => _previewMembers = []);
      return;
    }
    setState(() => _isPreviewLoading = true);
    try {
      final rows = await _supabase.rpc(
        'get_system_chat_group_preview_members',
        params: {'p_group_kind': _kind, 'p_owner_user_id': _ownerId},
      );
      if (!mounted) return;
      setState(() {
        _previewMembers = List<Map<String, dynamic>>.from(rows ?? const []);
        _isPreviewLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewMembers = [];
        _isPreviewLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Preview anggota gagal dimuat. $e')),
      );
    }
  }

  Future<void> _submit() async {
    if (_ownerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih owner grup terlebih dahulu.')),
      );
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Nama grup wajib diisi.')));
      return;
    }
    if (_previewMembers.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Grup tidak bisa dibuat karena anggota hierarchy belum tersedia.',
          ),
        ),
      );
      return;
    }
    await widget.onSubmit(
      _kind,
      _ownerId!,
      _chatTab,
      _nameController.text.trim(),
      _descriptionController.text.trim(),
      _isActive,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isExisting ? 'Edit Grup Sistem' : 'Buat Grup Sistem'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Tipe Grup'),
                items: const [
                  DropdownMenuItem(
                    value: 'sator_main',
                    child: Text(
                      'Grup Utama SATOR',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'spv_leader',
                    child: Text(
                      'Grup Leader SPV',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _kind = value;
                    _syncOwnerWithKind();
                  });
                  _loadPreview();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _ownerId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: _kind == 'sator_main'
                      ? 'Pilih SATOR'
                      : 'Pilih SPV',
                ),
                items: _filteredOwners
                    .map(
                      (owner) => DropdownMenuItem<String>(
                        value: owner.id,
                        child: Text(
                          owner.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() => _ownerId = value);
                  _loadPreview();
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _chatTab,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Masuk ke Tab'),
                items: const [
                  DropdownMenuItem(
                    value: 'team',
                    child: Text(
                      'Tim',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'global',
                    child: Text(
                      'Global',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'announcement',
                    child: Text(
                      'Info',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _chatTab = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nama Grup'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _descriptionController,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Deskripsi'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Aktif'),
                value: _isActive,
                onChanged: (value) => setState(() => _isActive = value),
              ),
              const SizedBox(height: 12),
              Text(
                'Preview anggota hierarchy',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 220),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: _isPreviewLoading
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    : _previewMembers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text(
                          'Belum ada anggota hierarchy. Lengkapi hierarchy dulu sebelum buat grup.',
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _previewMembers.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final member = _previewMembers[index];
                          return ListTile(
                            dense: true,
                            title: Text('${member['full_name'] ?? '-'}'),
                            subtitle: Text(
                              '${member['role'] ?? '-'}'.toUpperCase(),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Batal'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(_isExisting ? 'Simpan' : 'Buat Grup'),
        ),
      ],
    );
  }
}

class _OwnerOption {
  const _OwnerOption({
    required this.id,
    required this.name,
    required this.role,
  });

  factory _OwnerOption.fromMap(Map<String, dynamic> map) {
    final display = '${map['nickname'] ?? ''}'.trim().isNotEmpty
        ? '${map['nickname']}'
        : '${map['full_name'] ?? '-'}';
    return _OwnerOption(
      id: '${map['id'] ?? ''}',
      name: display,
      role: '${map['role'] ?? ''}'.toLowerCase(),
    );
  }

  final String id;
  final String name;
  final String role;

  String get label => '${role.toUpperCase()} • $name';
}
