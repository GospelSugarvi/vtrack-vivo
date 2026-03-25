import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/utils/success_dialog.dart';
import '../../../../core/utils/error_handler.dart';
import '../../../../ui/promotor/promotor.dart';

class LaporanFollowerPage extends StatefulWidget {
  const LaporanFollowerPage({super.key});

  @override
  State<LaporanFollowerPage> createState() => _LaporanFollowerPageState();
}

class _LaporanFollowerPageState extends State<LaporanFollowerPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _followerCountController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedPlatform = 'tiktok';
  File? _screenshot;
  Uint8List? _screenshotBytes;
  bool _isLoading = false;
  static const int _notesMaxLength = 500;

  // Cloudinary config
  static const String cloudinaryCloudName = 'dkkbwu8hj';
  static const String cloudinaryUploadPreset = 'vtrack_uploads';

  @override
  void dispose() {
    _usernameController.dispose();
    _followerCountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _screenshot = File(image.path);
          _screenshotBytes = bytes;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final exception = ErrorHandler.handleError(e);
      ErrorHandler.showErrorSnackBar(
        context,
        'Gagal memilih foto: ${exception.message}',
      );
    }
  }

  Future<void> _takePicture() async {
    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1200,
        imageQuality: 85,
      );

      if (image != null) {
        final bytes = await image.readAsBytes();
        setState(() {
          _screenshot = File(image.path);
          _screenshotBytes = bytes;
        });
      }
    } catch (e) {
      if (!mounted) return;
      final exception = ErrorHandler.handleError(e);
      ErrorHandler.showErrorSnackBar(
        context,
        'Gagal mengambil foto: ${exception.message}',
      );
    }
  }

  Future<File> _compressImage(File file) async {
    if (kIsWeb) {
      return file;
    }

    try {
      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) return file;

      if (image.width > 1200) {
        image = img.copyResize(image, width: 1200);
      }

      final compressedBytes = img.encodeJpg(image, quality: 85);

      final tempDir = await Directory.systemTemp.createTemp();
      final tempFile = File(
        '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(compressedBytes);

      return tempFile;
    } catch (e) {
      debugPrint('Compression error: $e');
      return file;
    }
  }

  Future<String?> _uploadToCloudinary(File file) async {
    try {
      final compressedFile = await _compressImage(file);

      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload',
      );

      final request = http.MultipartRequest('POST', url);
      request.fields['upload_preset'] = cloudinaryUploadPreset;
      request.fields['folder'] = 'vtrack/followers';

      request.files.add(
        await http.MultipartFile.fromPath('file', compressedFile.path),
      );

      final response = await request.send().timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw TimeoutException(message: 'Upload timeout'),
      );

      if (response.statusCode == 200) {
        final responseData = await response.stream.toBytes();
        final responseString = String.fromCharCodes(responseData);
        final jsonMap = json.decode(responseString);

        if (!kIsWeb && compressedFile.path != file.path) {
          try {
            await compressedFile.delete();
          } catch (e) {
            debugPrint('Error deleting temp file: $e');
          }
        }

        return jsonMap['secure_url'];
      } else {
        final responseData = await response.stream.toBytes();
        final errorMsg = String.fromCharCodes(responseData);
        throw AppException('Upload gagal: $errorMsg');
      }
    } on SocketException catch (e) {
      throw NetworkException(originalError: e);
    } on TimeoutException catch (e) {
      throw TimeoutException(
        message: 'Upload terlalu lama. Coba lagi.',
        originalError: e,
      );
    } catch (e) {
      throw AppException('Gagal upload foto: $e', originalError: e);
    }
  }

  String _formatUsername(String username) {
    String cleaned = username.trim().replaceAll('@', '');
    if (cleaned.isEmpty) {
      throw ValidationException(message: 'Username tidak boleh kosong');
    }
    if (cleaned.length < 3) {
      throw ValidationException(message: 'Username minimal 3 karakter');
    }
    if (!RegExp(r'^[a-zA-Z0-9._]+$').hasMatch(cleaned)) {
      throw ValidationException(
        message: 'Username hanya boleh huruf, angka, titik, dan underscore',
      );
    }
    return '@$cleaned';
  }

  Future<void> _submitReport() async {
    // Validation
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_usernameController.text.trim().isEmpty) {
      ErrorHandler.showErrorSnackBar(context, 'Username wajib diisi');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;

      if (userId == null) {
        throw SessionExpiredException();
      }

      // Get store ID
      final storeRows = await Supabase.instance.client
          .from('assignments_promotor_store')
          .select('store_id')
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1)
          .timeout(const Duration(seconds: 10));

      final assignments = List<Map<String, dynamic>>.from(storeRows);
      final storeData = assignments.isNotEmpty ? assignments.first : null;
      if (storeData == null || storeData['store_id'] == null) {
        throw AppException('Toko aktif promotor tidak ditemukan');
      }

      final storeId = storeData['store_id'];

      // Upload screenshot if provided
      String? screenshotUrl;
      if (_screenshot != null) {
        screenshotUrl = await _uploadToCloudinary(_screenshot!);
      }

      // Format username
      String formattedUsername;
      try {
        formattedUsername = _formatUsername(_usernameController.text);
      } on ValidationException {
        rethrow;
      }

      // Parse follower count if provided
      int? followerCount;
      if (_followerCountController.text.trim().isNotEmpty) {
        followerCount = int.tryParse(_followerCountController.text.trim());
        if (followerCount == null) {
          throw ValidationException(message: 'Jumlah follower harus angka');
        }
      }

      // Save to database
      await Supabase.instance.client
          .from('follower_reports')
          .insert({
            'promotor_id': userId,
            'store_id': storeId,
            'platform': _selectedPlatform,
            'username': formattedUsername,
            'screenshot_url': screenshotUrl,
            'follower_count': followerCount,
            'notes': _notesController.text.trim().isNotEmpty
                ? _notesController.text.trim()
                : null,
            'status': 'submitted',
          })
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Laporan Terkirim!',
        message: 'Laporan follower Anda telah berhasil dikirim',
      );
      if (!mounted) return;
      Navigator.pop(context);
    } on SocketException catch (e) {
      if (mounted) {
        ErrorHandler.showErrorDialog(
          context,
          NetworkException(originalError: e),
        );
      }
    } on TimeoutException catch (e) {
      if (mounted) {
        ErrorHandler.showErrorDialog(
          context,
          e as AppException,
          onRetry: _submitReport,
        );
      }
    } on ValidationException catch (e) {
      if (mounted) {
        ErrorHandler.showErrorDialog(context, e as AppException);
      }
    } catch (e) {
      if (mounted) {
        final exception = ErrorHandler.handleError(e);
        ErrorHandler.showErrorDialog(
          context,
          exception,
          onRetry: _submitReport,
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final canPreviewImage = _screenshot != null || _screenshotBytes != null;

    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: Form(
        key: _formKey,
        child: Container(
          color: t.background,
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
              children: [
                _buildHeader(context),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildFieldLabel('Platform', required: true),
                      const SizedBox(height: 8),
                      _buildCapsuleField(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedPlatform,
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: t.textMuted,
                            size: 18,
                          ),
                          dropdownColor: t.surface1,
                          decoration: _inputDecoration(
                            hintText: '',
                            prefixIcon: Icons.music_note_rounded,
                          ),
                          style: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'tiktok',
                              child: Text('TikTok'),
                            ),
                            DropdownMenuItem(
                              value: 'instagram',
                              child: Text('Instagram'),
                            ),
                            DropdownMenuItem(
                              value: 'facebook',
                              child: Text('Facebook'),
                            ),
                            DropdownMenuItem(
                              value: 'youtube',
                              child: Text('YouTube'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _selectedPlatform = value);
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildFieldLabel('Username Follower', required: true),
                      const SizedBox(height: 8),
                      _buildCapsuleField(
                        child: TextFormField(
                          controller: _usernameController,
                          cursorColor: t.textPrimary,
                          style: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                          decoration: _inputDecoration(
                            hintText: 'contoh: budisantoso',
                            prefixIcon: Icons.person_outline_rounded,
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Username harus diisi';
                            }
                            if (value.trim().length < 3) {
                              return 'Username minimal 3 karakter';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildFieldLabel('Jumlah Follower Saat Ini'),
                      const SizedBox(height: 8),
                      _buildCapsuleField(
                        child: TextFormField(
                          controller: _followerCountController,
                          keyboardType: TextInputType.number,
                          cursorColor: t.textPrimary,
                          style: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                          decoration: _inputDecoration(
                            hintText: '0',
                            prefixIcon: Icons.groups_2_outlined,
                          ),
                          validator: (value) {
                            if (value != null && value.isNotEmpty) {
                              final num = int.tryParse(value);
                              if (num == null) return 'Harus angka';
                              if (num < 0) return 'Tidak boleh negatif';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildFieldLabel('Screenshot Bukti'),
                      const SizedBox(height: 8),
                      if (canPreviewImage) ...[
                        _buildImagePreview(),
                        const SizedBox(height: 10),
                      ],
                      Row(
                        children: [
                          Expanded(
                            child: _buildUploadButton(
                              onTap: _pickImage,
                              icon: Icons.photo_library_outlined,
                              label: 'Pilih Foto',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _buildUploadButton(
                              onTap: _takePicture,
                              icon: Icons.photo_camera_outlined,
                              label: 'Ambil Foto',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      _buildFieldLabel('Catatan'),
                      const SizedBox(height: 8),
                      _buildTextareaField(),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _notesController,
                          builder: (context, value, _) {
                            return Text(
                              '${value.text.characters.length}/$_notesMaxLength',
                              style: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w700,
                                color: t.textMuted,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSubmitButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final t = context.fieldTokens;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.96),
        border: Border(bottom: BorderSide(color: t.surface2)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () => Navigator.of(context).maybePop(),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.surface3),
              ),
              child: Icon(
                Icons.arrow_back_ios_new_rounded,
                color: t.textSecondary,
                size: 17,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            'Laporan Follower',
            style: PromotorText.display(size: 18, color: t.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldLabel(String title, {bool required = false}) {
    return Padding(
      padding: const EdgeInsets.only(left: 14),
      child: RichText(
        text: TextSpan(
          style: PromotorText.outfit(
            size: 13,
            weight: FontWeight.w700,
            color: t.textSecondary,
          ),
          children: [
            TextSpan(text: title),
            if (required)
              TextSpan(
                text: ' *',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: t.primaryAccent,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapsuleField({required Widget child}) {
    return Theme(
      data: Theme.of(
        context,
      ).copyWith(inputDecorationTheme: const InputDecorationTheme()),
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: t.surface1.withValues(alpha: 0)),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
  }) {
    return InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      filled: true,
      fillColor: t.surface1.withValues(alpha: 0),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      hintText: hintText,
      hintStyle: PromotorText.outfit(
        size: 13,
        weight: FontWeight.w700,
        color: t.textMutedStrong,
      ),
      prefixIcon: Icon(prefixIcon, color: t.textMuted, size: 18),
      prefixIconConstraints: const BoxConstraints(minWidth: 46, minHeight: 20),
      errorStyle: PromotorText.outfit(
        size: 13,
        weight: FontWeight.w700,
        color: t.danger,
      ),
    );
  }

  Widget _buildImagePreview() {
    final imageProvider = kIsWeb
        ? MemoryImage(_screenshotBytes!) as ImageProvider
        : FileImage(_screenshot!);

    return Container(
      height: 180,
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: t.surface3),
        image: DecorationImage(image: imageProvider, fit: BoxFit.cover),
      ),
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: InkWell(
            onTap: () {
              setState(() {
                _screenshot = null;
                _screenshotBytes = null;
              });
            },
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: t.background.withValues(alpha: 0.5),
                shape: BoxShape.circle,
                border: Border.all(
                  color: t.textOnAccent.withValues(alpha: 0.2),
                ),
              ),
              child: Icon(Icons.close_rounded, color: t.textOnAccent, size: 18),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUploadButton({
    required VoidCallback onTap,
    required IconData icon,
    required String label,
  }) {
    return Material(
      color: t.background.withValues(alpha: 0),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: t.textMuted, size: 18),
              const SizedBox(width: 8),
              Text(
                label,
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextareaField() {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(24),
      ),
      child: TextFormField(
        controller: _notesController,
        minLines: 4,
        maxLines: 5,
        maxLength: _notesMaxLength,
        cursorColor: t.textPrimary,
        buildCounter:
            (_, {required currentLength, required isFocused, maxLength}) =>
                null,
        style: PromotorText.outfit(
          size: 13,
          weight: FontWeight.w700,
          color: t.textPrimary,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          errorBorder: InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          disabledBorder: InputBorder.none,
          filled: true,
          fillColor: t.surface1.withValues(alpha: 0),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
          hintText: 'Contoh: Follower dari video unboxing...',
          hintStyle: PromotorText.outfit(
            size: 13,
            weight: FontWeight.w700,
            color: t.textMutedStrong,
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [t.primaryAccent, t.warning],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(999),
          boxShadow: [
            BoxShadow(
              color: t.primaryAccentGlow,
              blurRadius: 20,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ElevatedButton(
          onPressed: _isLoading ? null : _submitReport,
          style: ElevatedButton.styleFrom(
            backgroundColor: t.surface1.withValues(alpha: 0),
            shadowColor: t.surface1.withValues(alpha: 0),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          child: _isLoading
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(t.textOnAccent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Sedang mengirim...',
                      style: PromotorText.outfit(
                        size: 16,
                        weight: FontWeight.w800,
                        color: t.textOnAccent,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.send_rounded, color: t.textOnAccent, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      'Kirim',
                      style: PromotorText.outfit(
                        size: 16,
                        weight: FontWeight.w800,
                        color: t.textOnAccent,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
