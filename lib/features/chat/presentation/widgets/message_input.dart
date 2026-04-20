import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/utils/cloudinary_upload_helper.dart';
import '../theme/chat_theme.dart';

class MessageInput extends StatefulWidget {
  final TextEditingController controller;
  final Function(String) onSendText;
  final Function(String imageUrl, int? width, int? height) onSendImage;
  final bool canSendMessages;

  const MessageInput({
    super.key,
    required this.controller,
    required this.onSendText,
    required this.onSendImage,
    this.canSendMessages = true,
  });

  @override
  State<MessageInput> createState() => _MessageInputState();
}

class _MessageInputState extends State<MessageInput> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    final tokens = chatTokensOf(context);
    final c = chatPaletteOf(context);
    if (!widget.canSendMessages) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tokens.surfaceAlt,
          border: Border(top: BorderSide(color: tokens.border)),
        ),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: tokens.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Hanya admin yang dapat mengirim pesan di room ini',
                style: TextStyle(color: tokens.textSecondary, fontSize: 14),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      decoration: BoxDecoration(
        color: tokens.surfaceAlt,
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: tokens.border),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isUploading ? null : _showImagePicker,
                    icon: Icon(
                      Icons.image_outlined,
                      color: _isUploading
                          ? tokens.textMuted
                          : tokens.textSecondary,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: widget.controller,
                      decoration: InputDecoration(
                        hintText: 'Message...',
                        hintStyle: TextStyle(
                          color: tokens.textMuted,
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: tokens.surface,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                      ),
                      style: TextStyle(color: tokens.textPrimary),
                      cursorColor: tokens.textPrimary,
                      maxLines: null,
                      textCapitalization: TextCapitalization.sentences,
                      onSubmitted: _sendMessage,
                    ),
                  ),
                  IconButton(
                    onPressed: _isUploading ? null : () {},
                    icon: Icon(
                      Icons.emoji_emotions_outlined,
                      color: _isUploading
                          ? tokens.textMuted
                          : tokens.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            decoration: BoxDecoration(
              color: tokens.primary,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: c.goldGlow,
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: IconButton(
              onPressed: _isUploading
                  ? null
                  : () => _sendMessage(widget.controller.text),
              icon: _isUploading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(c.onAccent),
                      ),
                    )
                  : Icon(Icons.send, color: c.onAccent),
            ),
          ),
        ],
      ),
    );
  }

  void _sendMessage(String text) {
    if (text.trim().isEmpty || _isUploading) return;
    widget.onSendText(text.trim());
    widget.controller.clear();
  }

  void _showImagePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: chatTokensOf(context).surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Ambil Foto'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.camera);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Pilih dari Galeri'),
              onTap: () {
                Navigator.pop(context);
                _pickImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 70,
      );
      if (image == null) return;

      if (mounted) {
        setState(() => _isUploading = true);
      }

      final result = await _uploadToCloudinary(image);
      if (result != null) {
        widget.onSendImage(
          result['url'] as String,
          result['width'] as int?,
          result['height'] as int?,
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Upload gambar gagal')));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal memilih gambar: $e')));
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  Future<Map<String, Object?>?> _uploadToCloudinary(XFile image) async {
    final result = await CloudinaryUploadHelper.uploadXFile(
      image,
      folder: 'vtrack/chat',
      fileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
      maxWidth: 1280,
      quality: 80,
    );
    if (result == null) return null;
    return <String, Object?>{
      'url': result.url,
      'width': result.width,
      'height': result.height,
    };
  }
}
