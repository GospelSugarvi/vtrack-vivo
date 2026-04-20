import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

class WarehouseImportPreview {
  const WarehouseImportPreview({
    required this.fileName,
    required this.sheetName,
    required this.rows,
    required this.summary,
    required this.targets,
  });

  final String fileName;
  final String sheetName;
  final List<WarehouseImportPreviewRow> rows;
  final WarehouseImportSummary summary;
  final List<WarehouseImportTargetSummary> targets;
}

class WarehouseImportSummary {
  const WarehouseImportSummary({
    required this.totalRows,
    required this.readyRows,
    required this.issueRows,
    required this.skippedRows,
    required this.sharedGroupRows,
    required this.distributedGroupRows,
    required this.singleStoreRows,
  });

  final int totalRows;
  final int readyRows;
  final int issueRows;
  final int skippedRows;
  final int sharedGroupRows;
  final int distributedGroupRows;
  final int singleStoreRows;
}

class WarehouseImportTargetSummary {
  const WarehouseImportTargetSummary({
    required this.targetLabel,
    required this.targetType,
    required this.totalRows,
    required this.readyRows,
    required this.issueRows,
  });

  final String targetLabel;
  final String targetType;
  final int totalRows;
  final int readyRows;
  final int issueRows;
}

class WarehouseImportPreviewRow {
  const WarehouseImportPreviewRow({
    required this.rowNumber,
    required this.warehouseName,
    required this.productName,
    required this.imei,
    required this.status,
    required this.targetType,
    required this.storeId,
    required this.groupId,
    required this.variantId,
    required this.productId,
    required this.targetLabel,
    required this.variantLabel,
    required this.notes,
  });

  final int rowNumber;
  final String warehouseName;
  final String productName;
  final String imei;
  final String status;
  final String? targetType;
  final String? storeId;
  final String? groupId;
  final String? variantId;
  final String? productId;
  final String targetLabel;
  final String variantLabel;
  final List<String> notes;

  Map<String, dynamic> toCommitJson() {
    return <String, dynamic>{
      'row_number': rowNumber,
      'warehouse_name': warehouseName,
      'product_name': productName,
      'imei': imei,
      'preview_status': status,
      'target_type': targetType,
      'store_id': storeId,
      'group_id': groupId,
      'variant_id': variantId,
      'product_id': productId,
      'notes': notes,
    };
  }
}

class WarehouseImportParser {
  static const String sharedGroupMode = 'shared_group';
  static const String distributedGroupMode = 'distributed_group';

  static WarehouseImportPreview parse({
    required Uint8List bytes,
    required String fileName,
    required List<Map<String, dynamic>> stores,
    required List<Map<String, dynamic>> groups,
    required List<Map<String, dynamic>> variants,
  }) {
    final workbook = _parseWorkbook(bytes);
    final variantLookup = _buildVariantLookup(variants);
    final entityLookup = _buildEntityLookup(stores, groups);

    final previewRows = <WarehouseImportPreviewRow>[];
    final targetStats = <String, _TargetAccumulator>{};
    var readyRows = 0;
    var issueRows = 0;
    var skippedRows = 0;
    var sharedGroupRows = 0;
    var distributedGroupRows = 0;
    var singleStoreRows = 0;
    final seenImeis = <String, int>{};
    var lastWarehouseName = '';

    for (final row in workbook.rows.skip(2)) {
      final rowNumber = row.rowNumber;
      final rawWarehouseName = _cell(row.values, 0);
      final warehouseName = rawWarehouseName.isNotEmpty
          ? rawWarehouseName
          : lastWarehouseName;
      final productName = _cell(row.values, 2);
      final imei = _cell(row.values, 7);

      if (rawWarehouseName.isEmpty && productName.isEmpty && imei.isEmpty) {
        continue;
      }

      if (rawWarehouseName.isNotEmpty) {
        lastWarehouseName = rawWarehouseName;
      }

      final entity = _resolveEntity(warehouseName, entityLookup);
      final variant = _resolveVariant(productName, variantLookup);
      final notes = <String>[];
      final normalizedImei = imei.replaceAll(RegExp(r'\s+'), '');

      String status = 'ready';
      if (entity == null) {
        status = 'unknown_target';
        notes.add('Nama toko/grup tidak dikenali');
      } else {
        switch (entity.targetType) {
          case _ImportTargetType.singleStore:
            singleStoreRows += 1;
            break;
          case _ImportTargetType.sharedGroup:
            sharedGroupRows += 1;
            break;
          case _ImportTargetType.distributedGroup:
            distributedGroupRows += 1;
            break;
        }
      }

      if (variant.status == _VariantResolutionStatus.unknown) {
        status = status == 'ready' ? 'unknown_variant' : status;
        notes.add('Varian produk belum ada di master sistem');
      } else if (variant.status == _VariantResolutionStatus.ambiguous) {
        status = status == 'ready' ? 'ambiguous_variant' : status;
        notes.add('Varian cocok ke lebih dari satu master produk');
      }

      if (normalizedImei.isEmpty ||
          normalizedImei.length != 15 ||
          int.tryParse(normalizedImei) == null) {
        status = status == 'ready' ? 'invalid_imei' : status;
        notes.add('IMEI harus 15 digit angka');
      } else {
        final duplicateRowNumber = seenImeis[normalizedImei];
        if (duplicateRowNumber != null) {
          status = status == 'ready' ? 'duplicate_in_file' : status;
          notes.add('IMEI duplikat di file yang sama (row $duplicateRowNumber)');
        } else {
          seenImeis[normalizedImei] = rowNumber;
        }
      }

      if (status == 'ready') {
        readyRows += 1;
      } else {
        issueRows += 1;
      }

      previewRows.add(
        WarehouseImportPreviewRow(
          rowNumber: rowNumber,
          warehouseName: warehouseName,
          productName: productName,
          imei: normalizedImei,
          status: status,
          targetType: entity?.targetType.name,
          storeId: entity?.storeId,
          groupId: entity?.groupId,
          variantId: variant.variantId,
          productId: variant.productId,
          targetLabel: entity?.label ?? '-',
          variantLabel: variant.label,
          notes: notes,
        ),
      );

      final targetLabel = entity?.label ?? warehouseName;
      final targetType = entity?.targetType.name ?? 'unknown';
      final key = '$targetType|$targetLabel';
      final bucket = targetStats.putIfAbsent(
        key,
        () => _TargetAccumulator(
          targetLabel: targetLabel.isEmpty ? '-' : targetLabel,
          targetType: targetType,
        ),
      );
      bucket.totalRows += 1;
      if (status == 'ready') {
        bucket.readyRows += 1;
      } else {
        bucket.issueRows += 1;
      }
    }

    return WarehouseImportPreview(
      fileName: fileName,
      sheetName: workbook.sheetName,
      rows: previewRows,
      summary: WarehouseImportSummary(
        totalRows: previewRows.length,
        readyRows: readyRows,
        issueRows: issueRows,
        skippedRows: skippedRows,
        sharedGroupRows: sharedGroupRows,
        distributedGroupRows: distributedGroupRows,
        singleStoreRows: singleStoreRows,
      ),
      targets: targetStats.values
          .map(
            (item) => WarehouseImportTargetSummary(
              targetLabel: item.targetLabel,
              targetType: item.targetType,
              totalRows: item.totalRows,
              readyRows: item.readyRows,
              issueRows: item.issueRows,
            ),
          )
          .toList()
        ..sort((a, b) {
          final byIssue = b.issueRows.compareTo(a.issueRows);
          if (byIssue != 0) return byIssue;
          return a.targetLabel.compareTo(b.targetLabel);
        }),
    );
  }

  static _ParsedWorkbook _parseWorkbook(Uint8List bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sharedStrings = _readSharedStrings(archive);

    final workbookXml = _readZipText(archive, 'xl/workbook.xml');
    final workbookDoc = XmlDocument.parse(workbookXml);
    final sheet = workbookDoc.findAllElements('sheet').first;
    final sheetName = sheet.getAttribute('name') ?? 'Sheet1';
    final relationId = sheet.getAttribute('id', namespace: _officeNs) ?? '';

    final relationsXml = _readZipText(archive, 'xl/_rels/workbook.xml.rels');
    final relationsDoc = XmlDocument.parse(relationsXml);
    String? target;
    for (final relation in relationsDoc.findAllElements('Relationship')) {
      if (relation.getAttribute('Id') == relationId) {
        target = relation.getAttribute('Target');
        break;
      }
    }

    if (target == null || target.isEmpty) {
      throw const FormatException('Sheet Excel tidak ditemukan');
    }

    final normalizedTarget = target.startsWith('xl/') ? target : 'xl/$target';
    final sheetXml = _readZipText(archive, normalizedTarget);
    final sheetDoc = XmlDocument.parse(sheetXml);
    final rows = <_ParsedRow>[];

    for (final rowElement in sheetDoc.findAllElements('row')) {
      final rowNumber = int.tryParse(rowElement.getAttribute('r') ?? '') ?? 0;
      final values = <String>[];
      for (final cell in rowElement.findElements('c')) {
        final reference = cell.getAttribute('r') ?? 'A1';
        final index = _columnIndex(reference);
        while (values.length <= index) {
          values.add('');
        }
        values[index] = _readCellValue(cell, sharedStrings);
      }
      rows.add(_ParsedRow(rowNumber: rowNumber, values: values));
    }

    return _ParsedWorkbook(sheetName: sheetName, rows: rows);
  }

  static List<String> _readSharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return const <String>[];
    final doc = XmlDocument.parse(utf8.decode(file.content as List<int>));
    return doc
        .findAllElements('si')
        .map((node) => node.findAllElements('t').map((t) => t.innerText).join())
        .toList();
  }

  static String _readCellValue(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t');
    final valueElements = cell.findElements('v');
    final valueElement = valueElements.isEmpty ? null : valueElements.first;
    if (type == 's' && valueElement != null) {
      final index = int.tryParse(valueElement.innerText) ?? -1;
      if (index >= 0 && index < sharedStrings.length) {
        return sharedStrings[index];
      }
    }
    if (type == 'inlineStr') {
      return cell.findAllElements('t').map((t) => t.innerText).join();
    }
    return valueElement?.innerText ?? '';
  }

  static String _readZipText(Archive archive, String path) {
    final file = archive.findFile(path);
    if (file == null) {
      throw FormatException('File Excel tidak lengkap: $path');
    }
    return utf8.decode(file.content as List<int>);
  }

  static int _columnIndex(String reference) {
    final letters = RegExp(r'^[A-Z]+').stringMatch(reference) ?? 'A';
    var value = 0;
    for (final codeUnit in letters.codeUnits) {
      value = (value * 26) + (codeUnit - 64);
    }
    return value - 1;
  }

  static _EntityLookup _buildEntityLookup(
    List<Map<String, dynamic>> stores,
    List<Map<String, dynamic>> groups,
  ) {
    final storeMap = <String, _EntityMatch>{};
    final groupMap = <String, _EntityMatch>{};

    for (final store in stores) {
      final name = '${store['store_name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      storeMap[_normalizeEntityName(name)] = _EntityMatch(
        targetType: _ImportTargetType.singleStore,
        label: name,
        storeId: store['id']?.toString(),
      );
    }

    for (final group in groups) {
      final name = '${group['group_name'] ?? ''}'.trim();
      if (name.isEmpty) continue;
      final rawMode = '${group['stock_handling_mode'] ?? distributedGroupMode}';
      groupMap[_normalizeEntityName(name)] = _EntityMatch(
        targetType: rawMode == sharedGroupMode
            ? _ImportTargetType.sharedGroup
            : _ImportTargetType.distributedGroup,
        label: name,
        groupId: group['id']?.toString(),
      );
    }

    return _EntityLookup(storeMap: storeMap, groupMap: groupMap);
  }

  static _EntityMatch? _resolveEntity(String rawName, _EntityLookup lookup) {
    final normalized = _normalizeEntityName(rawName);
    if (normalized.isEmpty) return null;

    final store = lookup.storeMap[normalized];
    if (store != null) return store;

    final group = lookup.groupMap[normalized];
    if (group != null) return group;

    return null;
  }

  static String _normalizeEntityName(String value) {
    var normalized = value.toUpperCase().trim();
    normalized = normalized.replaceAll('（', '(').replaceAll('）', ')');
    normalized = normalized.replaceFirst(RegExp(r'^KPG[-\s]*'), '');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ');
    normalized = normalized.replaceAllMapped(
      RegExp(r'[^A-Z0-9\s&()/]'),
      (_) => '',
    );
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  static _VariantLookup _buildVariantLookup(
    List<Map<String, dynamic>> variants,
  ) {
    final exact = <String, _VariantMatch>{};
    final noNet = <String, Set<_VariantMatch>>{};
    final modelNames = <String>{};
    final colors = <String>{};

    for (final variant in variants) {
      final model = '${variant['model_name'] ?? ''}'.trim().toUpperCase();
      final ramRom = '${variant['ram_rom'] ?? ''}'.trim().toUpperCase();
      final color = _normalizeColor('${variant['color'] ?? ''}');
      final network = '${variant['network_type'] ?? ''}'.trim().toUpperCase();
      if (model.isEmpty || ramRom.isEmpty || color.isEmpty) continue;

      modelNames.add(model);
      colors.add(color);

      final label = _buildVariantLabel(
        model: model,
        ramRom: ramRom,
        color: color,
        network: network,
      );
      final match = _VariantMatch(
        status: _VariantResolutionStatus.matched,
        label: label,
        variantId: variant['id']?.toString(),
        productId: variant['product_id']?.toString(),
      );
      exact['$model|$ramRom|$color|$network'] = match;
      noNet
          .putIfAbsent('$model|$ramRom|$color', () => <_VariantMatch>{})
          .add(match);
    }

    return _VariantLookup(
      exact: exact,
      noNetwork: noNet,
      modelNames: modelNames.toList()
        ..sort((a, b) => b.length.compareTo(a.length)),
      colors: colors.toList()..sort((a, b) => b.length.compareTo(a.length)),
    );
  }

  static _VariantMatch _resolveVariant(String rawName, _VariantLookup lookup) {
    final normalized = _normalizeProductName(rawName);
    if (normalized.isEmpty) {
      return const _VariantMatch(
        status: _VariantResolutionStatus.unknown,
        label: '-',
      );
    }

    String? model;
    for (final candidate in lookup.modelNames) {
      if (normalized.contains(candidate)) {
        model = candidate;
        break;
      }
    }

    final ramRomMatch = RegExp(
      r'(\d{1,2})\s*(?:\+|/)\s*(\d{2,3})\s*G?',
    ).firstMatch(normalized);
    final ramRom = ramRomMatch == null
        ? null
        : '${ramRomMatch.group(1)}/${ramRomMatch.group(2)}';

    String? color;
    for (final candidate in lookup.colors) {
      if (normalized.contains(candidate) ||
          normalized.contains(_colorAlias(candidate))) {
        color = candidate;
        break;
      }
    }

    String? network;
    if (normalized.contains('5G')) {
      network = '5G';
    } else if (normalized.contains('4G')) {
      network = '4G';
    } else {
      network = '4G';
    }

    if (model == null || ramRom == null || color == null) {
      return const _VariantMatch(
        status: _VariantResolutionStatus.unknown,
        label: '-',
      );
    }

    final exact = lookup.exact['$model|$ramRom|$color|$network'];
    if (exact != null) {
      return exact;
    }

    final candidates =
        lookup.noNetwork['$model|$ramRom|$color'] ?? <_VariantMatch>{};
    if (candidates.length == 1) {
      return candidates.first;
    }
    if (candidates.length > 1) {
      return _VariantMatch(
        status: _VariantResolutionStatus.ambiguous,
        label: candidates.map((item) => item.label).join(' / '),
      );
    }

    return const _VariantMatch(
      status: _VariantResolutionStatus.unknown,
      label: '-',
    );
  }

  static String _normalizeProductName(String value) {
    var normalized = value.toUpperCase().trim();
    normalized = normalized.replaceAll('（', '(').replaceAll('）', ')');
    normalized = normalized.replaceAllMapped(RegExp(r'\bY05\b'), (_) => 'Y05S');
    return normalized;
  }

  static String _normalizeColor(String value) {
    final normalized = value.toUpperCase().trim();
    switch (normalized) {
      case 'GRAY':
        return 'GREY';
      default:
        return normalized;
    }
  }

  static String _colorAlias(String color) {
    switch (color) {
      case 'GREY':
        return 'GRAY';
      default:
        return color;
    }
  }

  static String _buildVariantLabel({
    required String model,
    required String ramRom,
    required String color,
    required String network,
  }) {
    return '$model $ramRom $color${network.isNotEmpty ? ' $network' : ''}';
  }

  static String _cell(List<String> values, int index) {
    if (index < 0 || index >= values.length) return '';
    return values[index].trim();
  }
}

class _ParsedWorkbook {
  const _ParsedWorkbook({required this.sheetName, required this.rows});

  final String sheetName;
  final List<_ParsedRow> rows;
}

class _ParsedRow {
  const _ParsedRow({required this.rowNumber, required this.values});

  final int rowNumber;
  final List<String> values;
}

class _EntityLookup {
  const _EntityLookup({required this.storeMap, required this.groupMap});

  final Map<String, _EntityMatch> storeMap;
  final Map<String, _EntityMatch> groupMap;
}

class _EntityMatch {
  const _EntityMatch({
    required this.targetType,
    required this.label,
    this.storeId,
    this.groupId,
  });

  final _ImportTargetType targetType;
  final String label;
  final String? storeId;
  final String? groupId;
}

enum _ImportTargetType { singleStore, sharedGroup, distributedGroup }

class _VariantLookup {
  const _VariantLookup({
    required this.exact,
    required this.noNetwork,
    required this.modelNames,
    required this.colors,
  });

  final Map<String, _VariantMatch> exact;
  final Map<String, Set<_VariantMatch>> noNetwork;
  final List<String> modelNames;
  final List<String> colors;
}

class _VariantMatch {
  const _VariantMatch({
    required this.status,
    required this.label,
    this.variantId,
    this.productId,
  });

  final _VariantResolutionStatus status;
  final String label;
  final String? variantId;
  final String? productId;

  @override
  bool operator ==(Object other) {
    return other is _VariantMatch &&
        other.status == status &&
        other.label == label &&
        other.variantId == variantId &&
        other.productId == productId;
  }

  @override
  int get hashCode => Object.hash(status, label, variantId, productId);
}

enum _VariantResolutionStatus { matched, ambiguous, unknown }

class _TargetAccumulator {
  _TargetAccumulator({required this.targetLabel, required this.targetType});

  final String targetLabel;
  final String targetType;
  int totalRows = 0;
  int readyRows = 0;
  int issueRows = 0;
}

const String _officeNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
