import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class CloudinaryUploadResult {
  const CloudinaryUploadResult({
    required this.url,
    this.width,
    this.height,
  });

  final String url;
  final int? width;
  final int? height;
}

class CloudinaryUploadHelper {
  CloudinaryUploadHelper._();

  static const String cloudName = 'dkkbwu8hj';
  static const String uploadPreset = 'vtrack_uploads';

  static Future<Uint8List> compressXFile(
    XFile file, {
    int maxWidth = 1280,
    int quality = 82,
  }) async {
    final bytes = await file.readAsBytes();
    return compressBytes(bytes, maxWidth: maxWidth, quality: quality);
  }

  static Uint8List compressBytes(
    List<int> bytes, {
    int maxWidth = 1280,
    int quality = 82,
  }) {
    final normalizedBytes = Uint8List.fromList(bytes);
    final decoded = img.decodeImage(normalizedBytes);
    if (decoded == null) {
      return normalizedBytes;
    }

    var working = decoded;
    if (working.width > maxWidth) {
      working = img.copyResize(working, width: maxWidth);
    }

    final compressed = img.encodeJpg(working, quality: quality);
    return Uint8List.fromList(compressed);
  }

  static Future<CloudinaryUploadResult?> uploadXFile(
    XFile file, {
    String? folder,
    String? fileName,
    int maxWidth = 1280,
    int quality = 82,
  }) async {
    final compressed = await compressXFile(
      file,
      maxWidth: maxWidth,
      quality: quality,
    );
    return uploadBytes(
      compressed,
      folder: folder,
      fileName: fileName,
    );
  }

  static Future<CloudinaryUploadResult?> uploadBytes(
    List<int> bytes, {
    String? folder,
    String? fileName,
  }) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
        ),
      );
      request.fields['upload_preset'] = uploadPreset;
      if (folder != null && folder.trim().isNotEmpty) {
        request.fields['folder'] = folder.trim();
      }
      request.files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName ?? 'upload.jpg',
        ),
      );

      final response = await request.send();
      if (response.statusCode != 200) {
        return null;
      }

      final responseData = await response.stream.bytesToString();
      final jsonData = json.decode(responseData) as Map<String, dynamic>;
      final url = '${jsonData['secure_url'] ?? ''}'.trim();
      if (url.isEmpty) {
        return null;
      }
      return CloudinaryUploadResult(
        url: url,
        width: jsonData['width'] as int?,
        height: jsonData['height'] as int?,
      );
    } catch (_) {
      return null;
    }
  }
}
