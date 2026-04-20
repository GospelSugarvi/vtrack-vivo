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
  static const String _sharedGroupMode = 'shared_group';
  static const String _distributedGroupMode = 'distributed_group';
  static const String _splitStoreChatMode = 'split_store';
  static const String _singleGroupChatMode = 'single_group';

  List<Map<String, dynamic>> _groups = <Map<String, dynamic>>[];
  bool _isLoading = true;
  bool _isSyncingChatRooms = false;

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
      List groupRows;
      try {
        groupRows = await _supabase
            .from('store_groups')
            .select(
              'id, group_name, contact_info, owner_name, is_spc, stock_handling_mode, chat_room_mode',
            )
            .isFilter('deleted_at', null)
            .order('group_name');
      } on PostgrestException catch (e) {
        if (e.code == '42703') {
          groupRows = await _supabase
              .from('store_groups')
              .select('id, group_name, contact_info, owner_name, is_spc, chat_room_mode')
              .order('group_name');
        } else {
          rethrow;
        }
      }

      final stores = await _loadAllStores();
      final storesByGroupId = <String, List<Map<String, dynamic>>>{};
      for (final store in stores) {
        final rawGroupId = store['group_id']?.toString();
        if (rawGroupId == null || rawGroupId.isEmpty) continue;
        storesByGroupId
            .putIfAbsent(rawGroupId, () => <Map<String, dynamic>>[])
            .add(store);
      }

      final data = List<Map<String, dynamic>>.from(groupRows).map((group) {
        final groupId = group['id']?.toString() ?? '';
        return <String, dynamic>{
          ...group,
          'stores': storesByGroupId[groupId] ?? const <Map<String, dynamic>>[],
        };
      }).toList();

      if (!mounted) return;
      setState(() {
        _groups = data;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Gagal memuat grup toko: $e',
      );
    }
  }

  Future<List<Map<String, dynamic>>> _loadAllStores() async {
    final response = await _supabase
        .from('stores')
        .select('id, store_name, area, group_id')
        .isFilter('deleted_at', null)
        .order('store_name');
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _createGroup() async {
    await _showGroupFormDialog();
  }

  Future<void> _editGroup(Map<String, dynamic> group) async {
    await _showGroupFormDialog(group: group);
  }

  Future<void> _showGroupFormDialog({Map<String, dynamic>? group}) async {
    final isEdit = group != null;
    final nameController = TextEditingController(
      text:
          group?['group_name']?.toString() ?? group?['name']?.toString() ?? '',
    );
    final contactController = TextEditingController(
      text: group?['contact_info']?.toString() ?? '',
    );
    final ownerController = TextEditingController(
      text: group?['owner_name']?.toString() ?? '',
    );
    bool isSpc = group?['is_spc'] == true;
    String stockHandlingMode =
        group?['stock_handling_mode']?.toString() ?? _distributedGroupMode;
    String chatRoomMode =
        group?['chat_room_mode']?.toString() ?? _splitStoreChatMode;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isEdit ? 'Edit Grup Toko' : 'Buat Grup Toko Baru'),
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
                controller: contactController,
                decoration: const InputDecoration(
                  labelText: 'Kontak',
                  hintText: 'No HP / info kontak grup',
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
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (context, setInnerState) => SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Grup SPC'),
                  subtitle: const Text('Tandai jika grup ini termasuk SPC'),
                  value: isSpc,
                  onChanged: (value) {
                    setInnerState(() => isSpc = value);
                  },
                ),
              ),
              const SizedBox(height: 8),
              StatefulBuilder(
                builder: (context, setInnerState) =>
                    DropdownButtonFormField<String>(
                      initialValue: stockHandlingMode,
                      decoration: const InputDecoration(
                        labelText: 'Mode Stok Gudang',
                        helperText:
                            'Shared: satu pool stok grup. Distributed: distribusi ke cabang.',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _sharedGroupMode,
                          child: Text('Shared Group'),
                        ),
                        DropdownMenuItem(
                          value: _distributedGroupMode,
                          child: Text('Distributed Group'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setInnerState(() => stockHandlingMode = value);
                      },
                    ),
              ),
              const SizedBox(height: 12),
              StatefulBuilder(
                builder: (context, setInnerState) =>
                    DropdownButtonFormField<String>(
                      initialValue: chatRoomMode,
                      decoration: const InputDecoration(
                        labelText: 'Mode Chat Toko',
                        helperText:
                            'Pisah = room per toko. Gabung = satu room untuk semua toko dalam grup.',
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: _splitStoreChatMode,
                          child: Text('Pisah Per Toko'),
                        ),
                        DropdownMenuItem(
                          value: _singleGroupChatMode,
                          child: Text('Gabung Per Grup'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setInnerState(() => chatRoomMode = value);
                      },
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
              final groupName = nameController.text.trim();
              if (groupName.isEmpty) {
                showErrorDialog(
                  context,
                  title: 'Gagal',
                  message: 'Nama grup harus diisi',
                );
                return;
              }

              try {
                final payload = <String, dynamic>{
                  'group_name': groupName,
                  'contact_info': contactController.text.trim().isEmpty
                      ? null
                      : contactController.text.trim(),
                  'owner_name': ownerController.text.trim(),
                  'is_spc': isSpc,
                  'stock_handling_mode': stockHandlingMode,
                  'chat_room_mode': chatRoomMode,
                };

                if (isEdit) {
                  await _supabase
                      .from('store_groups')
                      .update(payload)
                      .eq('id', group['id']);
                } else {
                  await _supabase.from('store_groups').insert(payload);
                }

                if (context.mounted) {
                  Navigator.pop(context, true);
                }
              } catch (e) {
                if (context.mounted) {
                  showErrorDialog(
                    context,
                    title: 'Gagal',
                    message: isEdit
                        ? 'Gagal memperbarui grup: $e'
                        : 'Gagal membuat grup: $e',
                  );
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
        await showSuccessDialog(
          context,
          title: 'Berhasil',
          message: isEdit
              ? 'Grup toko berhasil diperbarui'
              : 'Grup toko berhasil dibuat',
        );
      }
    }
  }

  Future<void> _manageStores(Map<String, dynamic> group) async {
    final groupId = group['id']?.toString();
    if (groupId == null || groupId.isEmpty) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'ID grup toko tidak valid',
      );
      return;
    }

    try {
      final stores = await _loadAllStores();
      final initiallySelectedStoreIds = stores
          .where((store) => store['group_id']?.toString() == groupId)
          .map((store) => store['id'].toString())
          .toSet();
      final selectedStoreIds = <String>{...initiallySelectedStoreIds};
      String searchQuery = '';

      if (!mounted) return;
      final shouldReload = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final filteredStores = stores.where((store) {
              final query = searchQuery.trim().toLowerCase();
              if (query.isEmpty) return true;
              final name = '${store['store_name'] ?? ''}'.toLowerCase();
              final area = '${store['area'] ?? ''}'.toLowerCase();
              return name.contains(query) || area.contains(query);
            }).toList();

            return AlertDialog(
              title: Text('Kelola Toko - ${group['group_name'] ?? '-'}'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        hintText: 'Cari toko atau area...',
                        prefixIcon: Icon(Icons.search),
                      ),
                      onChanged: (value) {
                        setDialogState(() => searchQuery = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${selectedStoreIds.length} toko dipilih',
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: filteredStores.isEmpty
                          ? const Center(
                              child: Text('Tidak ada toko yang cocok'),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              itemCount: filteredStores.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final store = filteredStores[index];
                                final storeId = store['id'].toString();
                                final assignedGroupId = store['group_id']
                                    ?.toString();
                                final isSelected = selectedStoreIds.contains(
                                  storeId,
                                );
                                final isAssignedElsewhere =
                                    assignedGroupId != null &&
                                    assignedGroupId.isNotEmpty &&
                                    assignedGroupId != groupId;

                                return CheckboxListTile(
                                  value: isSelected,
                                  controlAffinity:
                                      ListTileControlAffinity.leading,
                                  title: Text(
                                    store['store_name']?.toString() ?? '-',
                                  ),
                                  subtitle: Text(
                                    [
                                      if ((store['area'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty)
                                        store['area'].toString(),
                                      if (isAssignedElsewhere)
                                        'Sudah ada di grup lain',
                                    ].join(' • '),
                                  ),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        selectedStoreIds.add(storeId);
                                      } else {
                                        selectedStoreIds.remove(storeId);
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
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    try {
                      final storeIdsToRemove = initiallySelectedStoreIds
                          .difference(selectedStoreIds)
                          .toList();
                      final storeIdsToAdd = selectedStoreIds
                          .difference(initiallySelectedStoreIds)
                          .toList();

                      if (storeIdsToRemove.isNotEmpty) {
                        await _supabase
                            .from('stores')
                            .update({'group_id': null})
                            .inFilter('id', storeIdsToRemove);
                      }

                      if (storeIdsToAdd.isNotEmpty) {
                        await _supabase
                            .from('stores')
                            .update({'group_id': groupId})
                            .inFilter('id', storeIdsToAdd);
                      }

                      if (context.mounted) {
                        Navigator.pop(context, true);
                      }
                    } catch (e) {
                      if (context.mounted) {
                        await showErrorDialog(
                          context,
                          title: 'Gagal',
                          message: 'Gagal memperbarui anggota grup: $e',
                        );
                      }
                    }
                  },
                  child: const Text('Simpan'),
                ),
              ],
            );
          },
        ),
      );

      if (shouldReload == true) {
        await _loadGroups();
        if (mounted) {
          await showSuccessDialog(
            context,
            title: 'Berhasil',
            message: 'Anggota grup toko berhasil diperbarui',
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Gagal memuat daftar toko: $e',
      );
    }
  }

  Future<void> _deleteGroup(Map<String, dynamic> group) async {
    final groupId = group['id']?.toString();
    if (groupId == null || groupId.isEmpty) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'ID grup toko tidak valid',
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hapus Grup Toko'),
        content: Text(
          'Grup "${group['group_name'] ?? '-'}" akan dihapus. Semua toko di grup ini akan dilepas dari grup. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _supabase
          .from('stores')
          .update({'group_id': null})
          .eq('group_id', groupId);

      try {
        await _supabase
            .from('store_groups')
            .update({'deleted_at': DateTime.now().toIso8601String()})
            .eq('id', groupId);
      } on PostgrestException catch (e) {
        if (e.code == '42703') {
          await _supabase.from('store_groups').delete().eq('id', groupId);
        } else {
          rethrow;
        }
      }

      await _loadGroups();
      if (mounted) {
        await showSuccessDialog(
          context,
          title: 'Berhasil',
          message: 'Grup toko berhasil dihapus',
        );
      }
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Gagal menghapus grup toko: $e',
      );
    }
  }

  Future<void> _syncChatRoomsFromAdmin() async {
    if (_isSyncingChatRooms) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sinkronisasi Chat Toko'),
        content: const Text(
          'Tindakan ini akan memicu sinkron ulang room chat per toko sesuai setting mode chat tiap grup. Lanjutkan?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sinkronkan'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      setState(() => _isSyncingChatRooms = true);
    }

    var successCount = 0;
    var failedCount = 0;

    try {
      for (final group in _groups) {
        final groupId = group['id']?.toString();
        if (groupId == null || groupId.isEmpty) {
          failedCount++;
          continue;
        }

        final chatRoomMode =
            group['chat_room_mode']?.toString() ?? _splitStoreChatMode;

        try {
          await _supabase
              .from('store_groups')
              .update({
                'chat_room_mode': chatRoomMode,
                'updated_at': DateTime.now().toIso8601String(),
              })
              .eq('id', groupId);
          successCount++;
        } catch (_) {
          failedCount++;
        }
      }
    } finally {
      await _loadGroups();
      if (mounted) {
        setState(() => _isSyncingChatRooms = false);
      }
    }

    if (!mounted) return;

    if (failedCount == 0) {
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message:
            'Sinkronisasi chat toko selesai. Grup tersinkron: $successCount.',
      );
      return;
    }

    await showErrorDialog(
      context,
      title: 'Sinkronisasi Sebagian',
      message:
          'Sinkronisasi selesai dengan catatan. Berhasil: $successCount, gagal: $failedCount.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Toko'),
        actions: [
          IconButton(
            onPressed: _isSyncingChatRooms ? null : _syncChatRoomsFromAdmin,
            tooltip: 'Sinkronkan chat toko',
            icon: _isSyncingChatRooms
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(onPressed: _loadGroups, icon: const Icon(Icons.refresh)),
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
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${group['group_name'] ?? group['name'] ?? '-'}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.info.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text('${stores.length} toko'),
                                      ),
                                      if ((group['owner_name'] ?? '')
                                          .toString()
                                          .trim()
                                          .isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.success.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Text(
                                            'Owner: ${group['owner_name']}',
                                          ),
                                        ),
                                      if (group['is_spc'] == true)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.warning.withValues(
                                              alpha: 0.14,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: const Text('SPC'),
                                        ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.warning.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          group['chat_room_mode'] ==
                                                  _singleGroupChatMode
                                              ? 'Chat: Gabung'
                                              : 'Chat: Pisah',
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _resolveModeColor(
                                            group['stock_handling_mode']
                                                ?.toString(),
                                          ).withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          _modeLabel(
                                            group['stock_handling_mode']
                                                ?.toString(),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            PopupMenuButton<String>(
                              onSelected: (value) {
                                if (value == 'manage') {
                                  _manageStores(group);
                                } else if (value == 'edit') {
                                  _editGroup(group);
                                } else if (value == 'delete') {
                                  _deleteGroup(group);
                                }
                              },
                              itemBuilder: (context) => const [
                                PopupMenuItem(
                                  value: 'manage',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.store_mall_directory,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Kelola Toko'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'edit',
                                  child: Row(
                                    children: [
                                      Icon(Icons.edit, size: 18),
                                      SizedBox(width: 8),
                                      Text('Edit Grup'),
                                    ],
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: Row(
                                    children: [
                                      Icon(Icons.delete, size: 18),
                                      SizedBox(width: 8),
                                      Text('Hapus Grup'),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          '${group['contact_info'] ?? '-'}',
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (stores.isEmpty)
                          const Text(
                            'Belum ada toko di grup ini',
                            style: TextStyle(color: AppColors.textSecondary),
                          )
                        else
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: stores.map((store) {
                              final storeName =
                                  store['store_name']?.toString() ?? '-';
                              final area =
                                  store['area']?.toString().trim() ?? '';
                              return Chip(
                                label: Text(
                                  area.isEmpty
                                      ? storeName
                                      : '$storeName • $area',
                                ),
                              );
                            }).toList(),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }

  String _modeLabel(String? mode) {
    switch (mode) {
      case _sharedGroupMode:
        return 'Shared Group';
      case _distributedGroupMode:
        return 'Distributed Group';
      default:
        return 'Distributed Group';
    }
  }

  Color _resolveModeColor(String? mode) {
    switch (mode) {
      case _sharedGroupMode:
        return AppColors.warning;
      case _distributedGroupMode:
        return AppColors.info;
      default:
        return AppColors.info;
    }
  }
}
