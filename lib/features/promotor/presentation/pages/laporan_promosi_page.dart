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
import '../../../../ui/promotor/promotor.dart';

class LaporanPromosiPage extends StatefulWidget {
  const LaporanPromosiPage({super.key});

  @override
  State<LaporanPromosiPage> createState() => _LaporanPromosiPageState();
}

class _LaporanPromosiPageState extends State<LaporanPromosiPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _formKey = GlobalKey<FormState>();
  final _postUrlController = TextEditingController();
  final _notesController = TextEditingController();

  String _selectedPlatform = 'tiktok';
  List<File> _selectedImages = [];
  bool _isLoading = false;
  static const int _notesMaxLength = 500;

  // Cloudinary config
  static const String cloudinaryCloudName = 'dkkbwu8hj';
  static const String cloudinaryUploadPreset = 'vtrack_uploads';

  @override
  void dispose() {
    _postUrlController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _pickImages() async {
    final ImagePicker picker = ImagePicker();
    final List<XFile> images = await picker.pickMultiImage();

    if (images.isNotEmpty) {
      setState(() {
        _selectedImages = images.map((xFile) => File(xFile.path)).toList();
      });
    }
  }

  Future<void> _takePicture() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.camera);

    if (image != null) {
      setState(() {
        _selectedImages.add(File(image.path));
      });
    }
  }

  Future<File> _compressImage(File file) async {
    // Skip compression on web
    if (kIsWeb) {
      return file;
    }

    try {
      // Read image
      final bytes = await file.readAsBytes();
      img.Image? image = img.decodeImage(bytes);

      if (image == null) return file;

      // Resize if too large (max 1200px width)
      if (image.width > 1200) {
        image = img.copyResize(image, width: 1200);
      }

      // Compress to JPEG with quality 85
      final compressedBytes = img.encodeJpg(image, quality: 85);

      // Save to temp file
      final tempDir = await Directory.systemTemp.createTemp();
      final tempFile = File(
        '${tempDir.path}/compressed_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );
      await tempFile.writeAsBytes(compressedBytes);

      return tempFile;
    } catch (e) {
      debugPrint('Compression error: $e');
      return file; // Return original if compression fails
    }
  }

  Future<String?> _uploadToCloudinary(File file) async {
    try {
      debugPrint('=== CLOUDINARY UPLOAD START (PROMOTION) ===');

      // Compress image first (skip on web)
      debugPrint('=== Compressing image... ===');
      final compressedFile = await _compressImage(file);
      debugPrint('=== Compression done ===');

      final url = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload',
      );
      debugPrint('=== Cloudinary URL: $url ===');

      final request = http.MultipartRequest('POST', url);
      request.fields['upload_preset'] = cloudinaryUploadPreset;
      request.fields['folder'] = 'vtrack/promotions';

      debugPrint('=== Adding file to request... ===');
      request.files.add(
        await http.MultipartFile.fromPath('file', compressedFile.path),
      );

      debugPrint('=== Sending request to Cloudinary... ===');
      final response = await request.send();
      debugPrint('=== Response status: ${response.statusCode} ===');

      if (response.statusCode == 200) {
        final responseData = await response.stream.toBytes();
        final responseString = String.fromCharCodes(responseData);
        final jsonMap = json.decode(responseString);

        debugPrint('=== Upload SUCCESS: ${jsonMap['secure_url']} ===');

        // Clean up temp file (only if different from original)
        if (!kIsWeb && compressedFile.path != file.path) {
          try {
            await compressedFile.delete();
          } catch (e) {
            debugPrint('=== Error deleting temp file: $e ===');
          }
        }

        return jsonMap['secure_url'];
      } else {
        final responseData = await response.stream.toBytes();
        final errorMsg = String.fromCharCodes(responseData);
        debugPrint('=== Upload FAILED: $errorMsg ===');
      }

      return null;
    } catch (e, stackTrace) {
      debugPrint('=== ERROR uploading to Cloudinary: $e ===');
      debugPrint('=== STACK TRACE: $stackTrace ===');
      return null;
    }
  }

  Future<void> _submitReport() async {
    debugPrint('=== SUBMIT PROMOTION REPORT START ===');

    if (!_formKey.currentState!.validate()) {
      debugPrint('=== Form validation failed ===');
      return;
    }

    if (_selectedImages.isEmpty) {
      debugPrint('=== ERROR: No images selected ===');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Minimal 1 screenshot harus diupload')),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      debugPrint('=== User ID: $userId ===');

      if (userId == null) throw Exception('User not logged in');

      // Get store ID
      debugPrint('=== Getting store ID... ===');
      final storeRows = await Supabase.instance.client
          .from('assignments_promotor_store')
          .select('store_id')
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1);

      final assignments = List<Map<String, dynamic>>.from(storeRows);
      final storeData = assignments.isNotEmpty ? assignments.first : null;
      if (storeData == null || storeData['store_id'] == null) {
        throw Exception('Toko aktif promotor tidak ditemukan');
      }

      final storeId = storeData['store_id'];
      debugPrint('=== Store ID: $storeId ===');

      // Upload images to Cloudinary
      debugPrint('=== Uploading ${_selectedImages.length} images... ===');
      List<String> uploadedUrls = [];
      for (int i = 0; i < _selectedImages.length; i++) {
        debugPrint(
          '=== Uploading image ${i + 1}/${_selectedImages.length} ===',
        );
        setState(() {
        });

        final url = await _uploadToCloudinary(_selectedImages[i]);
        if (url != null) {
          uploadedUrls.add(url);
          debugPrint('=== Image ${i + 1} uploaded: $url ===');
        } else {
          debugPrint('=== Image ${i + 1} upload FAILED ===');
        }
      }

      debugPrint(
        '=== Total uploaded: ${uploadedUrls.length}/${_selectedImages.length} ===',
      );

      if (uploadedUrls.isEmpty) {
        throw Exception('Gagal upload gambar');
      }

      // Save to database
      debugPrint('=== Saving to database... ===');
      await Supabase.instance.client.from('promotion_reports').insert({
        'promotor_id': userId,
        'store_id': storeId,
        'platform': _selectedPlatform,
        'post_url': _postUrlController.text.trim().isEmpty
            ? null
            : _postUrlController.text.trim(),
        'screenshot_urls': uploadedUrls,
        'notes': _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
        'status': 'submitted',
      });

      debugPrint('=== Promotion report SUCCESS ===');

      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Laporan Terkirim!',
        message: 'Laporan promosi Anda telah berhasil dikirim',
      );
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e, stackTrace) {
      debugPrint('=== ERROR PROMOTION REPORT: $e ===');
      debugPrint('=== STACK TRACE: $stackTrace ===');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: t.danger),
        );
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
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
                          dropdownColor: t.surface1,
                          icon: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: t.textMuted,
                            size: 18,
                          ),
                          decoration: _inputDecoration(
                            hintText: '',
                            prefixIcon: Icons.campaign_outlined,
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
                              value: 'whatsapp',
                              child: Text('WhatsApp'),
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
                      _buildFieldLabel('Link Postingan'),
                      const SizedBox(height: 8),
                      _buildCapsuleField(
                        child: TextFormField(
                          controller: _postUrlController,
                          keyboardType: TextInputType.url,
                          cursorColor: t.textPrimary,
                          style: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                          decoration: _inputDecoration(
                            hintText: '',
                            prefixIcon: Icons.link_rounded,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildFieldLabel('Screenshot Postingan', required: true),
                      const SizedBox(height: 8),
                      if (_selectedImages.isNotEmpty) ...[
                        _buildImageGallery(),
                        const SizedBox(height: 10),
                      ],
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: [
                          SizedBox(
                            width: (MediaQuery.of(context).size.width - 58) / 2,
                            child: _buildUploadButton(
                              onTap: _pickImages,
                              icon: Icons.photo_library_outlined,
                              label: 'Ambil dari Galeri',
                            ),
                          ),
                          SizedBox(
                            width: (MediaQuery.of(context).size.width - 58) / 2,
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
            'Laporan Promosi',
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
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(999),
      ),
      alignment: Alignment.center,
      child: child,
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

  Widget _buildImageGallery() {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _selectedImages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          return Stack(
            children: [
              Container(
                width: 116,
                height: 116,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.surface3),
                  image: DecorationImage(
                    image: FileImage(_selectedImages[index]),
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedImages.removeAt(index);
                    });
                  },
                  borderRadius: BorderRadius.circular(999),
                  child: Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: t.background.withValues(alpha: 0.5),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close_rounded,
                      color: t.textOnAccent,
                      size: 16,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
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
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
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
          gradient: LinearGradient(colors: [t.primaryAccent, t.warning]),
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
