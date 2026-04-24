import 'dart:async';

import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';
import 'package:flutter/material.dart';

class BarcodeScannerPage extends StatefulWidget {
  const BarcodeScannerPage({super.key});

  @override
  State<BarcodeScannerPage> createState() => _BarcodeScannerPageState();
}

class _BarcodeScannerPageState extends State<BarcodeScannerPage> {
  static final RegExp _imeiPattern = RegExp(r'(?<!\d)\d{15}(?!\d)');

  late final MobileScannerController _controller;
  bool _isHandlingScan = false;
  String? _lastRejectedValue;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      autoStart: true,
      detectionSpeed: DetectionSpeed.normal,
      detectionTimeoutMs: 450,
      formats: const [
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.codabar,
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.itf,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
      ],
      autoZoom: false,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_isHandlingScan) return;
    if (capture.barcodes.isEmpty) return;

    String? imei;

    for (final barcode in capture.barcodes) {
      final candidate = barcode.rawValue?.trim() ?? '';
      if (candidate.isEmpty) continue;

      final match = _imeiPattern.firstMatch(candidate);
      if (match != null) {
        imei = match.group(0);
        break;
      }

      final digitsOnly = candidate.replaceAll(RegExp(r'\D'), '');
      final digitMatch = _imeiPattern.firstMatch(digitsOnly);
      if (digitMatch != null) {
        imei = digitMatch.group(0);
        break;
      }
    }

    if (imei == null) {
      final firstRawValue = capture.barcodes.first.rawValue?.trim() ?? '';
      if (_lastRejectedValue != firstRawValue && mounted) {
        _lastRejectedValue = firstRawValue;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('Barcode terbaca, tetapi bukan IMEI 15 digit.'),
              duration: Duration(seconds: 2),
            ),
          );
      }
      return;
    }

    _isHandlingScan = true;

    try {
      await _controller.stop();
    } catch (_) {
      // Biarkan halaman kembali walau penghentian kamera gagal.
    }

    if (!mounted) return;
    Navigator.of(context).pop(imei);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scanWindow = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: size.width * 0.68,
      height: size.height * 0.18,
    );

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Scan IMEI'),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            fit: BoxFit.cover,
            tapToFocus: true,
            onDetect: (capture) {
              unawaited(_handleDetect(capture));
            },
            errorBuilder: (context, error) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Kamera tidak bisa dibuka.\n$error',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              );
            },
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _ScannerOverlayPainter(scanWindow: scanWindow),
            ),
          ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Text(
                  'Arahkan garis scan tepat ke barcode IMEI di dus HP.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter({required this.scanWindow});

  final Rect scanWindow;

  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Offset.zero & size;
    final overlayPath = Path()
      ..addRect(screenRect)
      ..addRRect(
        RRect.fromRectAndRadius(scanWindow, const Radius.circular(20)),
      )
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(
      overlayPath,
      Paint()..color = Colors.black.withValues(alpha: 0.48),
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(scanWindow, const Radius.circular(20)),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );

    final lineY = scanWindow.center.dy;
    canvas.drawLine(
      Offset(scanWindow.left + 12, lineY),
      Offset(scanWindow.right - 12, lineY),
      Paint()
        ..color = const Color(0xFF4DFFB2)
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
  }

  @override
  bool shouldRepaint(covariant _ScannerOverlayPainter oldDelegate) {
    return oldDelegate.scanWindow != scanWindow;
  }
}
