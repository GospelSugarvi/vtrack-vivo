import 'package:flutter/material.dart';
import 'package:ai_barcode_scanner/ai_barcode_scanner.dart';

class BarcodeScannerPage extends StatelessWidget {
  const BarcodeScannerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AiBarcodeScanner(
        onDetect: (BarcodeCapture capture) {
          final String? scannedValue = capture.barcodes.first.rawValue;
          if (scannedValue != null && scannedValue.isNotEmpty) {
            debugPrint('=== SCANNER: Scanned = $scannedValue ===');
            Navigator.pop(context, scannedValue);
          }
        },
        onDispose: () {
          debugPrint('=== SCANNER: Disposed ===');
        },
        controller: MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
        ),
      ),
    );
  }
}

