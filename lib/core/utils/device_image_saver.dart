import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class DeviceImageSaver {
  DeviceImageSaver._();

  static const MethodChannel _channel = MethodChannel('vtrack/export');

  static Future<bool> saveImage(
    Uint8List bytes, {
    required String name,
    String mimeType = 'image/png',
  }) async {
    if (kIsWeb) {
      throw PlatformException(
        code: 'unsupported_platform',
        message: 'Simpan gambar tidak didukung di web.',
      );
    }

    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      await _saveDesktopImage(bytes, name: name);
      return true;
    }

    if (!Platform.isAndroid) {
      throw PlatformException(
        code: 'unsupported_platform',
        message: 'Simpan gambar belum didukung di perangkat ini.',
      );
    }

    await _ensureAndroidWritePermission();

    final result = await _channel.invokeMethod<dynamic>('saveImage', {
      'bytes': bytes,
      'name': name,
      'mimeType': mimeType,
    });

    if (result is Map) {
      final success = result['isSuccess'] == true;
      if (!success) {
        throw PlatformException(
          code: 'save_failed',
          message: '${result['message'] ?? 'Gagal menyimpan gambar.'}',
          details: result,
        );
      }
      return true;
    }

    if (result == true) {
      return true;
    }

    throw PlatformException(
      code: 'save_failed',
      message: 'Gagal menyimpan gambar.',
      details: result,
    );
  }

  static Future<void> _ensureAndroidWritePermission() async {
    final sdkInt =
        await _channel.invokeMethod<int>('getAndroidSdkInt') ?? 0;
    if (sdkInt >= 29) {
      return;
    }

    final statuses = await <Permission>[
      Permission.storage,
      Permission.photos,
    ].request();

    final hasGranted = statuses.values.any((status) => status.isGranted);
    if (hasGranted) {
      return;
    }

    final hasLimited = statuses.values.any((status) => status.isLimited);
    if (hasLimited) {
      return;
    }

    throw PlatformException(
      code: 'permission_denied',
      message: 'Izin simpan gambar ditolak di perangkat.',
    );
  }

  static Future<void> _saveDesktopImage(
    Uint8List bytes, {
    required String name,
  }) async {
    final fileName = name.toLowerCase().endsWith('.png') ? name : '$name.png';
    final baseDir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final targetDir = Directory('${baseDir.path}/VTrack');
    if (!await targetDir.exists()) {
      await targetDir.create(recursive: true);
    }

    final file = File('${targetDir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
  }
}
