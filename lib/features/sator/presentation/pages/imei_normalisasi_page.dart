import 'dart:convert';
import 'dart:async';

import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/cloudinary_upload_helper.dart';

class ImeiNormalisasiPage extends StatefulWidget {
  const ImeiNormalisasiPage({super.key, this.initialNormalizationId});

  final String? initialNormalizationId;

  @override
  State<ImeiNormalisasiPage> createState() => _ImeiNormalisasiPageState();
}

class _ImeiNormalisasiPageState extends State<ImeiNormalisasiPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSubmitting = false;
  List<Map<String, dynamic>> _items = const [];
  final Set<String> _selectedPendingIds = <String>{};
  String _activeSection = 'pending';

  Future<void> _showSubmittingDialog() {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: t.background,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: t.primaryAccent,
                  ),
                ),
                const SizedBox(width: 14),
                Flexible(
                  child: Text(
                    'Sedang mengirim...',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<XFile?> _pickProofImage(ImageSource source) async {
    final picker = ImagePicker();
    return picker.pickImage(
      source: source,
      maxWidth: 1280,
      maxHeight: 1280,
      imageQuality: 75,
    );
  }

  Future<String?> _uploadProofToCloudinary(XFile imageFile) async {
    final result = await CloudinaryUploadHelper.uploadXFile(
      imageFile,
      folder: 'vtrack/imei-normalization',
      fileName: 'imei_normalization_${DateTime.now().millisecondsSinceEpoch}.jpg',
      maxWidth: 1280,
      quality: 80,
    );
    if (result == null) {
      throw Exception('Upload foto bukti gagal');
    }
    return result.url;
  }

  Future<_ReadyScanDialogResult?> _showReadyScanDialog(
    List<Map<String, dynamic>> items,
  ) async {
    XFile? selectedImage;

    return showDialog<_ReadyScanDialogResult>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 24,
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 420,
                  maxHeight: MediaQuery.of(context).size.height * 0.82,
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: t.background,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 8),
                        child: Row(
                          children: [
                            Icon(Icons.verified_rounded, color: t.success),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Konfirmasi Siap Scan',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Flexible(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${items.length} IMEI akan ditandai siap scan.',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: t.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Container(
                                constraints: const BoxConstraints(maxHeight: 180),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: t.surface1,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: t.surface3),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    ...items.take(6).map((item) {
                                      return Padding(
                                        padding: const EdgeInsets.only(bottom: 6),
                                        child: Text(
                                          '• ${item['imei'] ?? '-'}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                            color: t.textPrimary,
                                          ),
                                        ),
                                      );
                                    }),
                                    if (items.length > 6)
                                      Text(
                                        '+ ${items.length - 6} IMEI lainnya',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: t.textMutedStrong,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Foto bukti opsional',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: t.textSecondary,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                height: 120,
                                decoration: BoxDecoration(
                                  color: t.surface1,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: t.surface3),
                                ),
                                child: selectedImage == null
                                    ? Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Icons.image_outlined,
                                            size: 32,
                                            color: t.textMutedStrong,
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Belum ada foto bukti',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: t.textMutedStrong,
                                            ),
                                          ),
                                        ],
                                      )
                                    : Stack(
                                        fit: StackFit.expand,
                                        children: [
                                          FutureBuilder<Uint8List>(
                                            future: selectedImage!.readAsBytes(),
                                            builder: (context, snapshot) {
                                              if (!snapshot.hasData) {
                                                return const Center(
                                                  child:
                                                      CircularProgressIndicator(),
                                                );
                                              }
                                              return ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(16),
                                                child: Image.memory(
                                                  snapshot.data!,
                                                  fit: BoxFit.cover,
                                                ),
                                              );
                                            },
                                          ),
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: InkWell(
                                              onTap: () => setInnerState(
                                                () => selectedImage = null,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.all(6),
                                                decoration: BoxDecoration(
                                                  color: Colors.black.withValues(
                                                    alpha: 0.45,
                                                  ),
                                                  shape: BoxShape.circle,
                                                ),
                                                child: const Icon(
                                                  Icons.close,
                                                  size: 16,
                                                  color: Colors.white,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final picked = await _pickProofImage(
                                          ImageSource.camera,
                                        );
                                        if (picked == null) return;
                                        setInnerState(
                                          () => selectedImage = picked,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.photo_camera_outlined,
                                      ),
                                      label: const Text('Kamera'),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () async {
                                        final picked = await _pickProofImage(
                                          ImageSource.gallery,
                                        );
                                        if (picked == null) return;
                                        setInnerState(
                                          () => selectedImage = picked,
                                        );
                                      },
                                      icon: const Icon(
                                        Icons.photo_library_outlined,
                                      ),
                                      label: const Text('Galeri'),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextButton(
                                onPressed: () => Navigator.of(dialogContext).pop(),
                                child: const Text('Batal'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => Navigator.of(dialogContext).pop(
                                  _ReadyScanDialogResult(
                                    proofImage: selectedImage,
                                  ),
                                ),
                                child: const Text('Kirim'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _sendReadyCardToStoreChat(
    Map<String, dynamic> item, {
    String? proofImageUrl,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final normalizationRow = await _supabase
        .from('imei_normalizations')
        .select('id, store_id')
        .eq('id', item['id'])
        .maybeSingle();
    final storeId = '${normalizationRow?['store_id'] ?? ''}'.trim();
    if (storeId.isEmpty) return;

    final room = await _supabase
        .from('chat_rooms')
        .select('id')
        .eq('room_type', 'toko')
        .eq('store_id', storeId)
        .eq('is_active', true)
        .maybeSingle();
    final roomId = '${room?['id'] ?? ''}'.trim();
    if (roomId.isEmpty) return;

    final content =
        'imei_normalization_card::${jsonEncode(<String, dynamic>{
          'normalization_id': item['id'],
          'promotor_name': item['promotor_name'],
          'store_name': item['store_name'],
          'product_name': item['product_name'],
          'imei': item['imei'],
          'status': 'ready_to_scan',
          'message': 'IMEI sudah berhasil dinormalkan. Promotor bisa scan di APK utama.',
          'proof_image_url': proofImageUrl,
        })}';

    await _supabase.rpc(
      'send_message',
      params: {
        'p_room_id': roomId,
        'p_sender_id': userId,
        'p_message_type': 'text',
        'p_content': content,
      },
    );
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Sesi login tidak ditemukan');

      final rows = await _supabase.rpc(
        'get_sator_imei_list',
        params: {'p_sator_id': userId},
      );

      if (!mounted) return;
      setState(() {
        _items = List<Map<String, dynamic>>.from(rows ?? const []);
        final focusId = widget.initialNormalizationId?.trim();
        if (focusId != null && focusId.isNotEmpty) {
          _items.sort((a, b) {
            final aFocused = '${a['id']}' == focusId ? 0 : 1;
            final bFocused = '${b['id']}' == focusId ? 0 : 1;
            return aFocused.compareTo(bFocused);
          });
          Map<String, dynamic>? focusedItem;
          for (final item in _items) {
            if ('${item['id']}' == focusId) {
              focusedItem = item;
              break;
            }
          }
          final focusedStatus = '${focusedItem?['status'] ?? ''}';
          if ({
            'reported',
            'processing',
            'sent',
            'pending',
          }.contains(focusedStatus)) {
            _selectedPendingIds
              ..clear()
              ..add(focusId);
          }
        }
        _selectedPendingIds.removeWhere(
          (id) => !_items.any((item) => '${item['id']}' == id),
        );
        final pendingCount = _itemsForStatuses({
          'reported',
          'processing',
          'sent',
          'pending',
        }).length;
        final readyCount = _itemsForStatuses({
          'ready_to_scan',
          'normalized',
          'normal',
        }).length;
        final scannedCount = _itemsForStatuses({'scanned'}).length;
        if (_activeSection == 'pending' && pendingCount == 0) {
          _activeSection = readyCount > 0
              ? 'ready'
              : scannedCount > 0
              ? 'scanned'
              : 'pending';
        } else if (_activeSection == 'ready' && readyCount == 0) {
          _activeSection = pendingCount > 0
              ? 'pending'
              : scannedCount > 0
              ? 'scanned'
              : 'ready';
        } else if (_activeSection == 'scanned' && scannedCount == 0) {
          _activeSection = pendingCount > 0
              ? 'pending'
              : readyCount > 0
              ? 'ready'
              : 'scanned';
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _items = const [];
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> _itemsForStatuses(Set<String> statuses) {
    return _items
        .where((item) => statuses.contains('${item['status'] ?? ''}'))
        .toList();
  }

  bool get _canDismissPage {
    return _itemsForStatuses({
      'reported',
      'processing',
      'sent',
      'pending',
    }).isEmpty;
  }

  Future<void> _markSelectedAsReady() async {
    final userId = _supabase.auth.currentUser?.id;
    if (_selectedPendingIds.isEmpty || userId == null || _isSubmitting) return;

    final selectedItems = _items
        .where((item) => _selectedPendingIds.contains('${item['id']}'))
        .toList();
    final confirmation = await _showReadyScanDialog(selectedItems);
    if (confirmation == null) return;

    if (!mounted) return;
    setState(() => _isSubmitting = true);
    var loadingShown = false;
    try {
      if (mounted) {
        unawaited(_showSubmittingDialog());
        loadingShown = true;
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }

      String? proofImageUrl;
      if (confirmation.proofImage != null) {
        proofImageUrl = await _uploadProofToCloudinary(confirmation.proofImage!);
      }

      for (final id in _selectedPendingIds) {
        await _supabase.rpc(
          'mark_imei_normalized',
          params: {
            'p_normalization_id': id,
            'p_sator_id': userId,
            'p_notes': 'Selesai diproses dan siap scan',
          },
        );
        final item = selectedItems.firstWhere(
          (row) => '${row['id']}' == id,
          orElse: () => <String, dynamic>{'id': id},
        );
        try {
          await _sendReadyCardToStoreChat(item, proofImageUrl: proofImageUrl);
        } catch (_) {}
      }
      final processed = _selectedPendingIds.length;
      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$processed IMEI ditandai siap scan'),
          backgroundColor: t.success,
        ),
      );
    } catch (e) {
      if (loadingShown && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal update IMEI: $e'),
          backgroundColor: t.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _copySelectedPendingImeis() async {
    final items = _items
        .where((item) => _selectedPendingIds.contains('${item['id']}'))
        .toList();
    final text = items
        .map((item) => '${item['imei'] ?? ''}'.trim())
        .where((v) => v.isNotEmpty)
        .join('\n');
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${items.length} IMEI disalin'),
        backgroundColor: t.info,
      ),
    );
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'reported':
        return t.warning;
      case 'processing':
        return t.info;
      case 'ready_to_scan':
        return t.success;
      case 'scanned':
        return t.textMutedStrong;
      default:
        return t.textMuted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'reported':
        return 'Dikirim';
      case 'processing':
        return 'Diproses';
      case 'ready_to_scan':
        return 'Siap Scan';
      case 'scanned':
        return 'Selesai';
      default:
        return status;
    }
  }

  Widget _buildStatusBadge(String status) {
    final tone = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        _statusLabel(status),
        style: TextStyle(
          color: tone,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionChip({
    required String keyName,
    required String label,
    required int count,
  }) {
    final active = _activeSection == keyName;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _activeSection = keyName),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            color: active ? t.primaryAccent : t.surface1,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: active ? t.primaryAccent : t.surface3),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: active ? t.textOnAccent : t.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: active ? t.textOnAccent : t.textMutedStrong,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildItemList(
    List<Map<String, dynamic>> items, {
    required bool selectable,
  }) {
    if (items.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.surface3),
        ),
        child: Text(
          'Belum ada data.',
          style: TextStyle(color: t.textMuted, fontWeight: FontWeight.w700),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: items.asMap().entries.map((entry) {
          final item = entry.value;
          final isLast = entry.key == items.length - 1;
          final status = '${item['status'] ?? '-'}';
          final subtitle = [
            '${item['promotor_name'] ?? '-'}',
            '${item['store_name'] ?? '-'}',
          ].where((part) => part.trim().isNotEmpty).join(' • ');
          final selected = _selectedPendingIds.contains('${item['id']}');
          final isFocused =
              (widget.initialNormalizationId ?? '') == '${item['id']}';

          final rowContent = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${item['product_name'] ?? '-'}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildStatusBadge(status),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'IMEI ${item['imei'] ?? '-'}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: t.textMuted,
                ),
              ),
            ],
          );

          return Container(
            decoration: BoxDecoration(
              color: isFocused
                  ? t.primaryAccentSoft.withValues(alpha: 0.22)
                  : selectable && selected
                  ? t.primaryAccentSoft.withValues(alpha: 0.4)
                  : Colors.transparent,
              border: Border(
                bottom: isLast
                    ? BorderSide.none
                    : BorderSide(color: t.surface3),
              ),
            ),
            child: selectable
                ? CheckboxListTile(
                    value: selected,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 0,
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                    checkboxShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          _selectedPendingIds.add('${item['id']}');
                        } else {
                          _selectedPendingIds.remove('${item['id']}');
                        }
                      });
                    },
                    title: rowContent,
                  )
                : ListTile(
                    dense: true,
                    visualDensity: const VisualDensity(
                      horizontal: -2,
                      vertical: -2,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    title: rowContent,
                  ),
          );
        }).toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final pendingItems = _itemsForStatuses({
      'reported',
      'processing',
      'sent',
      'pending',
    });
    final readyItems = _itemsForStatuses({
      'ready_to_scan',
      'normalized',
      'normal',
    });
    final scannedItems = _itemsForStatuses({'scanned'});
    final activeItems = switch (_activeSection) {
      'ready' => readyItems,
      'scanned' => scannedItems,
      _ => pendingItems,
    };
    final activeTitle = switch (_activeSection) {
      'ready' => 'Siap Scan',
      'scanned' => 'Selesai',
      _ => 'Perlu Diproses',
    };
    final activeSelectable = _activeSection == 'pending';

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('IMEI Normalisasi'),
        actions: [
          if (_canDismissPage)
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Tutup'),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: t.surface3),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: t.primaryAccentSoft,
                          child: Icon(Icons.qr_code_2, color: t.primaryAccent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Monitoring IMEI',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                  color: t.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                pendingItems.isEmpty
                                    ? 'Semua IMEI sudah normal'
                                    : 'Pending ${pendingItems.length} • Siap scan ${readyItems.length} • Selesai ${scannedItems.length}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: t.textMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pendingItems.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    if (_activeSection == 'pending' &&
                        _selectedPendingIds.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: t.surface3),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _copySelectedPendingImeis,
                                child: const Text('Copy IMEI'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: FilledButton(
                                onPressed: _isSubmitting
                                    ? null
                                    : _markSelectedAsReady,
                                child: const Text('Siap Scan'),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 12),
                  if (_items.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: t.surface3),
                      ),
                      child: const Text('Belum ada data normalisasi IMEI.'),
                    )
                  else ...[
                    Row(
                      children: [
                        _buildSectionChip(
                          keyName: 'pending',
                          label: 'Diproses',
                          count: pendingItems.length,
                        ),
                        const SizedBox(width: 8),
                        _buildSectionChip(
                          keyName: 'ready',
                          label: 'Siap Scan',
                          count: readyItems.length,
                        ),
                        const SizedBox(width: 8),
                        _buildSectionChip(
                          keyName: 'scanned',
                          label: 'Selesai',
                          count: scannedItems.length,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildSectionTitle(activeTitle),
                    _buildItemList(activeItems, selectable: activeSelectable),
                  ],
                ],
              ),
            ),
    );
  }
}

class _ReadyScanDialogResult {
  const _ReadyScanDialogResult({this.proofImage});

  final XFile? proofImage;
}
