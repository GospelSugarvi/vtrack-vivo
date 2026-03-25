import 'dart:io';

import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../../ui/promotor/promotor.dart';

class VisitFormPage extends StatefulWidget {
  final String storeId;

  const VisitFormPage({super.key, required this.storeId});

  @override
  State<VisitFormPage> createState() => _VisitFormPageState();
}

class _VisitFormPageState extends State<VisitFormPage> {
  FieldThemeTokens get t => context.fieldTokens;
  static const _conditionOptions = [
    'Toko ramai',
    'Toko sepi',
    'Display lengkap',
    'Display kurang',
    'Kompetitor promo',
    'Promotor semangat',
    'Butuh motivasi',
  ];

  static const _actionOptions = [
    'Follow up kredit Vast',
    'Pasang materi promo',
    'Perbaiki display',
    'Coaching produk Vivo',
    'Target minggu depan',
    'Pantau lebih sering',
  ];

  final _supabase = Supabase.instance.client;
  final _notesController = TextEditingController();
  final _followUpController = TextEditingController();
  final _photos = <File>[];
  final _selectedConditions = <String>{};
  final _selectedActions = <String>{};

  bool _isSubmitting = false;
  Map<String, dynamic>? _store;

  @override
  void initState() {
    super.initState();
    _loadStore();
  }

  @override
  void dispose() {
    _notesController.dispose();
    _followUpController.dispose();
    super.dispose();
  }

  Future<void> _loadStore() async {
    final store = await _supabase
        .from('stores')
        .select('id, store_name, area')
        .eq('id', widget.storeId)
        .maybeSingle();
    if (!mounted) return;
    setState(() => _store = store);
  }

  Future<void> _pickPhoto() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 70,
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() {
      if (_photos.length < 2) {
        _photos.add(File(picked.path));
      }
    });
  }

  Future<void> _submit() async {
    if (_photos.isEmpty) {
      _showNotice('Minimal 1 foto diperlukan.', isError: true);
      return;
    }

    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      _showNotice('Session tidak ditemukan. Login ulang.', isError: true);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final photoUrls = <String>[];
      for (var i = 0; i < _photos.length; i++) {
        final photo = _photos[i];
        final fileName = '${DateTime.now().millisecondsSinceEpoch}_$i.jpg';
        final path = 'visits/$userId/${widget.storeId}/$fileName';
        await _supabase.storage.from('photos').upload(path, photo);
        photoUrls.add(_supabase.storage.from('photos').getPublicUrl(path));
      }

      await _supabase.from('store_visits').insert({
        'store_id': widget.storeId,
        'sator_id': userId,
        'visit_date': DateTime.now().toIso8601String().split('T')[0],
        'check_in_time': DateTime.now().toIso8601String(),
        'check_in_photo': photoUrls.isNotEmpty ? photoUrls.first : null,
        'check_out_photo': photoUrls.length > 1 ? photoUrls[1] : null,
        'notes': _buildNotesPayload(),
        'follow_up': _buildFollowUpPayload(),
        'checklist': {
          'conditions': _selectedConditions.toList(),
          'actions': _selectedActions.toList(),
        },
      });

      if (!mounted) return;
      context.go('/sator/visiting/success');
    } catch (e) {
      if (!mounted) return;
      _showNotice('Visit gagal disimpan. $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _buildNotesPayload() {
    final tags = _selectedConditions.join(', ');
    final notes = _notesController.text.trim();
    if (tags.isEmpty) return notes;
    if (notes.isEmpty) return tags;
    return '$tags\n$notes';
  }

  String _buildFollowUpPayload() {
    final tags = _selectedActions.join(', ');
    final notes = _followUpController.text.trim();
    if (tags.isEmpty) return notes;
    if (notes.isEmpty) return tags;
    return '$tags\n$notes';
  }

  void _showNotice(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? t.danger : t.success,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final storeName = '${_store?['store_name'] ?? 'Form Visit'}';
    final storeSub = '${_store?['area'] ?? '-'}';

    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              child: Row(
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => context.pop(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Icon(
                        Icons.arrow_back_rounded,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Form Visit',
                          style: PromotorText.outfit(
                            size: 17,
                            weight: FontWeight.w800,
                            color: t.textPrimary,
                          ),
                        ),
                        Text(
                          '$storeName · $storeSub',
                          style: PromotorText.outfit(
                            size: 11,
                            weight: FontWeight.w700,
                            color: t.textMutedStrong,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 112),
                children: [
                  _buildSection(
                    icon: Icons.camera_alt_rounded,
                    tone: t.info,
                    title: 'Foto Visit',
                    subtitle: 'Min. 1 foto',
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ..._photos.asMap().entries.map((entry) {
                          return Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.file(
                                  entry.value,
                                  width: 72,
                                  height: 68,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Positioned(
                                top: -2,
                                right: -2,
                                child: InkWell(
                                  onTap: () => setState(
                                    () => _photos.removeAt(entry.key),
                                  ),
                                  child: Container(
                                    width: 18,
                                    height: 18,
                                    decoration: BoxDecoration(
                                      color: t.danger,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 15,
                                      color: t.textOnAccent,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: _photos.length >= 2 ? null : _pickPhoto,
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              color: t.surface2,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: t.surface3),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.add_a_photo_rounded,
                                  color: t.textMuted,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _photos.length >= 2 ? 'Maks 2' : 'Ambil Foto',
                                  style: PromotorText.outfit(
                                    size: 7.5,
                                    weight: FontWeight.w700,
                                    color: t.textMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildSection(
                    icon: Icons.store_mall_directory_rounded,
                    tone: t.primaryAccent,
                    title: 'Kondisi Toko',
                    subtitle: 'Pilih yang sesuai',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTagWrap(_conditionOptions, _selectedConditions),
                        const SizedBox(height: 8),
                        _buildTextArea(
                          controller: _notesController,
                          hint: 'Catatan kondisi toko...',
                          minLines: 1,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildSection(
                    icon: Icons.bolt_rounded,
                    tone: t.warning,
                    title: 'Follow-up Action',
                    subtitle: 'Tindak lanjut',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildTagWrap(_actionOptions, _selectedActions),
                        const SizedBox(height: 8),
                        _buildTextArea(
                          controller: _followUpController,
                          hint: 'Kesepakatan dengan promotor...',
                          minLines: 1,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            height: 46,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.primaryAccent,
                foregroundColor: t.textOnAccent,
              ),
              onPressed: _isSubmitting ? null : _submit,
              child: _isSubmitting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Selesai & Simpan Visit',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w800,
                        color: t.textOnAccent,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required IconData icon,
    required Color tone,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 14, color: tone),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: PromotorText.outfit(
                          size: 9.5,
                          weight: FontWeight.w600,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: child,
          ),
        ],
      ),
    );
  }

  Widget _buildTagWrap(List<String> options, Set<String> selected) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: options.map((label) {
        final on = selected.contains(label);
        return InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            setState(() {
              if (on) {
                selected.remove(label);
              } else {
                selected.add(label);
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: on ? t.primaryAccentSoft : t.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: on ? t.primaryAccentGlow : t.surface3),
            ),
            child: Text(
              label,
              style: PromotorText.outfit(
                size: 9.5,
                weight: FontWeight.w700,
                color: on ? t.primaryAccentLight : t.textSecondary,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildTextArea({
    required TextEditingController controller,
    required String hint,
    required int minLines,
  }) {
    return TextField(
      controller: controller,
      minLines: minLines,
      maxLines: minLines + 1,
      style: PromotorText.outfit(size: 12, weight: FontWeight.w600),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: PromotorText.outfit(
          size: 12,
          weight: FontWeight.w700,
          color: t.textMutedStrong,
        ),
        filled: true,
        fillColor: t.surface2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.surface3),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.surface3),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: t.primaryAccent),
        ),
      ),
    );
  }
}
