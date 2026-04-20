import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'device_image_saver.dart';

const String _kDefaultVtrackDownloadUrl =
    'https://github.com/GospelSugarvi/vtrack-vivo/releases/latest/download/app-release.apk';
const String kVtrackDownloadUrl = String.fromEnvironment(
  'VTRACK_DOWNLOAD_URL',
  defaultValue: _kDefaultVtrackDownloadUrl,
);

Uri getVtrackDownloadUri() {
  final rawDownloadUrl = kVtrackDownloadUrl.trim();
  final resolvedUrl = rawDownloadUrl.isEmpty
      ? _kDefaultVtrackDownloadUrl
      : rawDownloadUrl;
  return Uri.parse(resolvedUrl);
}

Future<void> openLatestAppDownload(BuildContext context) async {
  final launched = await launchUrl(
    getVtrackDownloadUri(),
    mode: LaunchMode.externalApplication,
  );
  if (launched || !context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Link APK terbaru tidak bisa dibuka')),
  );
}

Future<void> showAppAboutWithDownloadQr(BuildContext context) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  var versionLabel = '1.0.0';
  try {
    final info = await PackageInfo.fromPlatform();
    final version = info.version.trim();
    final build = info.buildNumber.trim();
    versionLabel = build.isEmpty ? version : '$version+$build';
  } catch (_) {}
  final downloadUrl = getVtrackDownloadUri().toString();

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
              const SizedBox(height: 14),
              const Text(
                'Scan QR untuk download APK terbaru.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              const Text(
                'Link dan QR di halaman ini selalu mengarah ke file APK terbaru.',
                style: TextStyle(fontSize: 12),
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
            label: const Text('Salin Link'),
          ),
          TextButton.icon(
            onPressed: () => openLatestAppDownload(dialogContext),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Buka Link'),
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
  const double imageSize = 2048;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, imageSize, imageSize),
    Paint()..color = Colors.white,
  );
  painter.paint(canvas, const Size(imageSize, imageSize));

  final picture = recorder.endRecording();
  final image = await picture.toImage(imageSize.toInt(), imageSize.toInt());
  final imageData = await image.toByteData(format: ui.ImageByteFormat.png);
  if (imageData == null) {
    throw Exception('QR bytes kosong');
  }
  return imageData.buffer.asUint8List();
}
