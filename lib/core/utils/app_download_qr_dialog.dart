import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'device_image_saver.dart';

const String _kDefaultVtrackDownloadUrl =
    'https://github.com/GospelSugarvi/vtrack-vivo/releases/latest/download/app-release.apk';
const String kVtrackDownloadUrl = String.fromEnvironment(
  'VTRACK_DOWNLOAD_URL',
  defaultValue: _kDefaultVtrackDownloadUrl,
);

Future<void> showAppAboutWithDownloadQr(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var versionLabel = '1.0.0';
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    final build = info.buildNumber.trim();
    versionLabel = build.isEmpty ? version : '$version+$build';
  } catch (_) {}
  final rawDownloadUrl = kVtrackDownloadUrl.trim();
  final downloadUrl = rawDownloadUrl.isEmpty
      ? _kDefaultVtrackDownloadUrl
      : rawDownloadUrl;

  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return AlertDialog(
        scrollable: true,
        title: const Text('Tentang Aplikasi'),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'VTrack v$versionLabel',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              const Text('Internal distribution'),
              const SizedBox(height: 14),
              const Text(
                'Scan QR untuk download aplikasi:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 234,
                  height: 234,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.black12),
                  ),
                  child: QrImageView(
                    data: downloadUrl,
                    size: 210,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: Colors.black,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: Colors.black,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                downloadUrl,
                style: const TextStyle(fontSize: 12),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: downloadUrl));
              messenger?.showSnackBar(
                const SnackBar(content: Text('Link download disalin')),
              );
            },
            icon: const Icon(Icons.copy_rounded),
            label: const Text('Copy Link'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Tutup'),
          ),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                final pngBytes = await _buildQrPngBytes(data: downloadUrl);
                final name =
                    'vtrack_download_qr_${DateTime.now().millisecondsSinceEpoch}.png';
                await DeviceImageSaver.saveImage(pngBytes, name: name);
                if (dialogContext.mounted) {
                  Navigator.of(dialogContext).pop();
                }
                messenger?.showSnackBar(
                  const SnackBar(content: Text('QR berhasil disimpan')),
                );
              } catch (e) {
                messenger?.showSnackBar(
                  SnackBar(content: Text('Gagal simpan QR: $e')),
                );
              }
            },
            icon: const Icon(Icons.download_rounded),
            label: const Text('Download QR'),
          ),
        ],
      );
    },
  );
}

Future<Uint8List> _buildQrPngBytes({required String data}) async {
  final painter = QrPainter(
    data: data,
    version: QrVersions.auto,
    gapless: true,
    eyeStyle: const QrEyeStyle(
      eyeShape: QrEyeShape.square,
      color: Colors.black,
    ),
    dataModuleStyle: const QrDataModuleStyle(
      dataModuleShape: QrDataModuleShape.square,
      color: Colors.black,
    ),
  );
  final imageData = await painter.toImageData(
    2048,
    format: ui.ImageByteFormat.png,
  );
  if (imageData == null) {
    throw Exception('QR bytes kosong');
  }
  return imageData.buffer.asUint8List();
}
