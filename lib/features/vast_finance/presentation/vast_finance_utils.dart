import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class VastFinanceUtils {
  VastFinanceUtils._();

  static const String cloudinaryCloudName = 'dkkbwu8hj';
  static const String cloudinaryUploadPreset = 'vtrack_uploads';
  static const List<String> pekerjaanOptions = <String>[
    'Karyawan Swasta',
    'PNS/ASN',
    'Wiraswasta',
    'TNI/Polri',
    'Pensiunan',
    'Tidak Bekerja',
    'Lainnya',
  ];

  static String exactHashHex(Uint8List bytes) {
    const int fnvPrime = 1099511628211;
    const int fnvOffset = 1469598103934665603;
    var hash = fnvOffset;
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static String perceptualHash(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return '';
    final resized = img.copyResize(decoded, width: 8, height: 8);
    final luminances = <int>[];
    var total = 0;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        final pixel = resized.getPixel(x, y);
        final luminance =
            ((pixel.r.toInt() * 299) +
                    (pixel.g.toInt() * 587) +
                    (pixel.b.toInt() * 114)) ~/
                1000;
        luminances.add(luminance);
        total += luminance;
      }
    }
    final avg = total / luminances.length;
    final bits = luminances.map((v) => v >= avg ? '1' : '0').join();
    final buffer = StringBuffer();
    for (var i = 0; i < bits.length; i += 4) {
      buffer.write(int.parse(bits.substring(i, i + 4), radix: 2).toRadixString(16));
    }
    return buffer.toString();
  }

  static Future<Uint8List> compressForUpload(XFile file) async {
    final bytes = await file.readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return bytes;
    var working = decoded;
    if (working.width > 1400) {
      working = img.copyResize(working, width: 1400);
    }
    return Uint8List.fromList(img.encodeJpg(working, quality: 86));
  }

  static Future<String?> uploadImage(
    Uint8List bytes, {
    required String folder,
    String fileName = 'vast.jpg',
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload',
    );
    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = cloudinaryUploadPreset
      ..fields['folder'] = folder
      ..files.add(
        http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ),
      );

    final response = await request.send();
    final body = await response.stream.bytesToString();
    if (response.statusCode != 200) {
      return null;
    }
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    return decoded['secure_url']?.toString();
  }
}
