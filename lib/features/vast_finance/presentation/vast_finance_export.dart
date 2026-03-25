import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_xlsio/xlsio.dart' as xlsio;

class VastFinanceExport {
  VastFinanceExport._();

  static Future<Directory> _getExportDirectory() async {
    if (Platform.isAndroid) {
      await Permission.storage.request();
      await Permission.manageExternalStorage.request();
      final downloadDir = Directory('/storage/emulated/0/Download');
      if (!downloadDir.existsSync()) {
        downloadDir.createSync(recursive: true);
      }
      return downloadDir;
    }
    return getApplicationDocumentsDirectory();
  }

  static Future<String> exportXlsx({
    required String fileName,
    required List<String> headers,
    required List<List<Object?>> rows,
    required String sheetName,
  }) async {
    final workbook = xlsio.Workbook();
    final sheet = workbook.worksheets[0];
    sheet.name = sheetName;

    final headerStyle = workbook.styles.add('header');
    headerStyle.bold = true;
    headerStyle.fontColor = '#FFFFFF';
    headerStyle.backColor = '#C9923A';

    for (var i = 0; i < headers.length; i++) {
      final cell = sheet.getRangeByIndex(1, i + 1);
      cell.setText(headers[i]);
      cell.cellStyle = headerStyle;
    }

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      for (var colIndex = 0; colIndex < row.length; colIndex++) {
        final value = row[colIndex];
        final cell = sheet.getRangeByIndex(rowIndex + 2, colIndex + 1);
        if (value is num) {
          cell.setNumber(value.toDouble());
        } else if (value is bool) {
          cell.setText(value ? 'YA' : 'TIDAK');
        } else {
          cell.setText('${value ?? ''}');
        }
      }
    }

    for (var i = 1; i <= headers.length; i++) {
      sheet.autoFitColumn(i);
    }
    final bytes = workbook.saveAsStream();
    workbook.dispose();

    final dir = await _getExportDirectory();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    if (kDebugMode) {
      debugPrint('VAST export saved: ${file.path}');
    }
    return file.path;
  }
}
