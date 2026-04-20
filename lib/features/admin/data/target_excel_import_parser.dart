import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

enum TargetImportRole { promotor, sator, spv }

extension TargetImportRoleLabel on TargetImportRole {
  String get label => switch (this) {
    TargetImportRole.promotor => 'Promotor',
    TargetImportRole.sator => 'SATOR',
    TargetImportRole.spv => 'SPV',
  };
}

class TargetExcelImportPreview {
  const TargetExcelImportPreview({
    required this.fileName,
    required this.sheetName,
    required this.role,
    required this.rows,
    required this.summary,
    required this.bundleNamesById,
  });

  final String fileName;
  final String sheetName;
  final TargetImportRole role;
  final List<TargetExcelImportRow> rows;
  final TargetExcelImportSummary summary;
  final Map<String, String> bundleNamesById;
}

class TargetExcelImportSummary {
  const TargetExcelImportSummary({
    required this.totalRows,
    required this.readyRows,
    required this.issueRows,
    required this.skippedRows,
    required this.unknownUserRows,
    required this.duplicateUserRows,
  });

  final int totalRows;
  final int readyRows;
  final int issueRows;
  final int skippedRows;
  final int unknownUserRows;
  final int duplicateUserRows;
}

class TargetExcelImportRow {
  const TargetExcelImportRow({
    required this.rowNumber,
    required this.sourceName,
    required this.matchedUserId,
    required this.matchedUserName,
    required this.hireDateIso,
    required this.status,
    required this.notes,
    required this.values,
    required this.bundleValues,
  });

  final int rowNumber;
  final String sourceName;
  final String? matchedUserId;
  final String? matchedUserName;
  final String? hireDateIso;
  final String status;
  final List<String> notes;
  final Map<String, int> values;
  final Map<String, int> bundleValues;
}

class TargetExcelImportParser {
  static TargetExcelImportPreview parse({
    required Uint8List bytes,
    required String fileName,
    required TargetImportRole role,
    required List<Map<String, dynamic>> users,
    required List<Map<String, dynamic>> specialBundles,
  }) {
    final workbook = _parseWorkbook(bytes);
    final bundleLookup = _buildBundleLookup(specialBundles);
    final header = _resolveHeader(
      rows: workbook.rows,
      role: role,
      bundleLookup: bundleLookup,
    );

    if (header == null) {
      throw FormatException(
        'Header Excel target tidak dikenali untuk tab ${role.label}.',
      );
    }

    final usersByName = _buildUserLookup(users);
    final rows = <TargetExcelImportRow>[];
    var readyRows = 0;
    var issueRows = 0;
    var skippedRows = 0;
    var unknownUserRows = 0;
    var duplicateUserRows = 0;

    for (final row in workbook.rows.skip(header.headerRowIndex + 1)) {
      final sourceName = _cell(row.values, header.nameColumnIndex);
      final hasAnyMappedValue = _rowHasAnyMappedValue(row.values, header);
      if (sourceName.isEmpty && !hasAnyMappedValue) {
        continue;
      }
      if (sourceName.isEmpty) {
        skippedRows += 1;
        continue;
      }

      final values = <String, int>{};
      for (final entry in header.fieldColumns.entries) {
        if (entry.key == 'hire_date') continue;
        final value = _normalizeImportedValue(
          role: role,
          fieldKey: entry.key,
          rawValue: _parseInt(_cell(row.values, entry.value)),
        );
        if (value != null) {
          values[entry.key] = value;
        }
      }
      final hireDateIso = header.fieldColumns.containsKey('hire_date')
          ? _parseDateCell(_cell(row.values, header.fieldColumns['hire_date']!))
          : null;

      final bundleValues = <String, int>{};
      for (final entry in header.bundleColumns.entries) {
        final value = _parseInt(_cell(row.values, entry.value));
        if (value != null) {
          bundleValues[entry.key] = value;
        }
      }

      if (values.isEmpty && bundleValues.isEmpty) {
        skippedRows += 1;
        continue;
      }

      final notes = <String>[];
      String status = 'ready';
      String? matchedUserId;
      String? matchedUserName;

      final matches = usersByName[_normalizeName(sourceName)] ?? const [];
      if (matches.isEmpty) {
        status = 'unknown_user';
        notes.add('Nama belum cocok dengan user sistem');
        unknownUserRows += 1;
      } else if (matches.length > 1) {
        status = 'duplicate_user';
        notes.add('Nama cocok ke lebih dari satu user sistem');
        duplicateUserRows += 1;
      } else {
        matchedUserId = matches.first.userId;
        matchedUserName = matches.first.fullName;
      }

      if (status == 'ready') {
        readyRows += 1;
      } else {
        issueRows += 1;
      }

      rows.add(
        TargetExcelImportRow(
          rowNumber: row.rowNumber,
          sourceName: sourceName,
          matchedUserId: matchedUserId,
          matchedUserName: matchedUserName,
          hireDateIso: hireDateIso,
          status: status,
          notes: notes,
          values: values,
          bundleValues: bundleValues,
        ),
      );
    }

    return TargetExcelImportPreview(
      fileName: fileName,
      sheetName: workbook.sheetName,
      role: role,
      rows: rows,
      summary: TargetExcelImportSummary(
        totalRows: rows.length,
        readyRows: readyRows,
        issueRows: issueRows,
        skippedRows: skippedRows,
        unknownUserRows: unknownUserRows,
        duplicateUserRows: duplicateUserRows,
      ),
      bundleNamesById: {
        for (final bundle in specialBundles)
          '${bundle['id']}': '${bundle['bundle_name'] ?? 'Bundle'}',
      },
    );
  }

  static bool _rowHasAnyMappedValue(
    List<String> values,
    _ResolvedHeader header,
  ) {
    for (final index in header.fieldColumns.values) {
      if (_cell(values, index).isNotEmpty) return true;
    }
    for (final index in header.bundleColumns.values) {
      if (_cell(values, index).isNotEmpty) return true;
    }
    return false;
  }

  static _ResolvedHeader? _resolveHeader({
    required List<_ParsedRow> rows,
    required TargetImportRole role,
    required Map<String, _BundleAlias> bundleLookup,
  }) {
    final nameAliases = _nameAliases(role);
    final fieldAliases = _fieldAliases(role);

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex += 1) {
      final row = rows[rowIndex];
      final normalizedCells = row.values.map(_normalizeHeader).toList();
      final nameColumnIndex = _findHeaderIndex(normalizedCells, nameAliases);
      if (nameColumnIndex == null) {
        continue;
      }

      final fieldColumns = <String, int>{};
      for (final entry in fieldAliases.entries) {
        final fieldIndex = _findHeaderIndex(normalizedCells, entry.value);
        if (fieldIndex != null) {
          fieldColumns[entry.key] = fieldIndex;
        }
      }

      final bundleColumns = <String, int>{};
      for (var i = 0; i < normalizedCells.length; i += 1) {
        final cell = normalizedCells[i];
        if (cell.isEmpty || !cell.contains('TARGET')) {
          continue;
        }
        final matchedBundle = _matchBundleColumn(cell, bundleLookup);
        if (matchedBundle != null) {
          bundleColumns[matchedBundle.bundleId] = i;
        }
      }

      if (fieldColumns.isNotEmpty || bundleColumns.isNotEmpty) {
        return _ResolvedHeader(
          headerRowIndex: rowIndex,
          nameColumnIndex: nameColumnIndex,
          fieldColumns: fieldColumns,
          bundleColumns: bundleColumns,
        );
      }
    }

    return null;
  }

  static int? _findHeaderIndex(
    List<String> normalizedCells,
    List<String> aliases,
  ) {
    for (var i = 0; i < normalizedCells.length; i += 1) {
      final cell = normalizedCells[i];
      if (cell.isEmpty) continue;
      for (final alias in aliases) {
        if (cell == alias || cell.contains(alias) || alias.contains(cell)) {
          return i;
        }
      }
    }
    return null;
  }

  static List<String> _nameAliases(TargetImportRole role) => switch (role) {
    TargetImportRole.promotor => const ['PROMOTOR', 'NAMA PROMOTOR', 'NAMA'],
    TargetImportRole.sator => const ['SATOR', 'NAMA SATOR', 'NAMA'],
    TargetImportRole.spv => const ['SPV', 'NAMA SPV', 'NAMA'],
  };

  static Map<String, List<String>> _fieldAliases(TargetImportRole role) =>
      switch (role) {
        TargetImportRole.promotor => const {
          'hire_date': ['HIRE DATE', 'TANGGAL MASUK', 'JOIN DATE'],
          'target_omzet': [
            'TARGET SELL OUT',
            'SELL OUT',
            'TARGET OMZET',
            'OMZET',
            'T1 VALUE',
            'T1 VALUE APRIL',
            'T1 VALUE TARGET',
          ],
          'target_tiktok': ['TIKTOK', 'TARGET TIKTOK'],
          'target_follower': ['FOLLOWER', 'FOLLOWERS', 'TARGET FOLLOWER'],
          'target_vast': ['VAST', 'TARGET VAST'],
        },
        TargetImportRole.sator => const {
          'target_sell_in': ['SELL IN', 'TARGET SELL IN'],
          'target_sell_out': ['SELL OUT', 'TARGET SELL OUT', 'OMZET'],
          'target_fokus': ['FOKUS', 'TARGET FOKUS', 'FOCUS', 'TARGET FOCUS'],
          'target_sellout_asp': ['ASP', 'SELL OUT ASP', 'TARGET ASP'],
          'target_vast': ['VAST', 'TARGET VAST'],
        },
        TargetImportRole.spv => const {
          'target_sell_in': ['SELL IN', 'TARGET SELL IN'],
          'target_sell_out': ['SELL OUT', 'TARGET SELL OUT', 'OMZET'],
          'target_fokus': ['FOKUS', 'TARGET FOKUS', 'FOCUS', 'TARGET FOCUS'],
          'target_sellout_asp': ['ASP', 'SELL OUT ASP', 'TARGET ASP'],
          'target_vast': ['VAST', 'TARGET VAST'],
        },
      };

  static Map<String, List<_MatchedUser>> _buildUserLookup(
    List<Map<String, dynamic>> users,
  ) {
    final lookup = <String, List<_MatchedUser>>{};
    for (final user in users) {
      final userId = '${user['user_id'] ?? ''}'.trim();
      final fullName = '${user['full_name'] ?? ''}'.trim();
      if (userId.isEmpty || fullName.isEmpty) continue;
      lookup
          .putIfAbsent(_normalizeName(fullName), () => <_MatchedUser>[])
          .add(_MatchedUser(userId: userId, fullName: fullName));
    }
    return lookup;
  }

  static int? _normalizeImportedValue({
    required TargetImportRole role,
    required String fieldKey,
    required int? rawValue,
  }) {
    if (rawValue == null) return null;

    // Target omzet from the provided promotor Excel is expressed in thousands.
    // Convert it to full rupiah before it reaches the admin form/database.
    if (role == TargetImportRole.promotor && fieldKey == 'target_omzet') {
      return rawValue * 1000;
    }

    return rawValue;
  }

  static Map<String, _BundleAlias> _buildBundleLookup(
    List<Map<String, dynamic>> bundles,
  ) {
    final lookup = <String, _BundleAlias>{};
    for (final bundle in bundles) {
      final bundleId = '${bundle['id'] ?? ''}'.trim();
      final bundleName = '${bundle['bundle_name'] ?? ''}'.trim();
      if (bundleId.isEmpty || bundleName.isEmpty) continue;
      final normalized = _normalizeBundle(bundleName);
      if (normalized.isEmpty) continue;
      lookup[bundleId] = _BundleAlias(
        bundleId: bundleId,
        bundleName: bundleName,
        normalized: normalized,
      );
    }
    return lookup;
  }

  static _BundleAlias? _matchBundleColumn(
    String normalizedHeader,
    Map<String, _BundleAlias> bundleLookup,
  ) {
    final candidate = _normalizeBundle(normalizedHeader);
    if (candidate.isEmpty) return null;

    _BundleAlias? bestMatch;
    var bestScore = 0;
    for (final bundle in bundleLookup.values) {
      final score = _bundleMatchScore(candidate, bundle.normalized);
      if (score > bestScore) {
        bestMatch = bundle;
        bestScore = score;
      }
    }
    return bestMatch;
  }

  static int _bundleMatchScore(String candidate, String normalizedBundle) {
    if (candidate == normalizedBundle) return 100;
    if (candidate.contains(normalizedBundle) ||
        normalizedBundle.contains(candidate)) {
      return normalizedBundle.length.clamp(1, 99);
    }
    final candidateTokens = candidate
        .split(' ')
        .where((item) => item.isNotEmpty);
    final bundleTokens = normalizedBundle
        .split(' ')
        .where((item) => item.isNotEmpty)
        .toSet();
    var hits = 0;
    for (final token in candidateTokens) {
      if (bundleTokens.contains(token)) {
        hits += 1;
      }
    }
    return hits >= 2 ? hits * 10 : 0;
  }

  static String _normalizeBundle(String value) {
    var normalized = _normalizeHeader(value);
    normalized = normalized.replaceAll(RegExp(r'\bY31D SERIES\b'), 'Y31D PRO');
    normalized = normalized.replaceAll(RegExp(r'\bY21D SERIES\b'), 'Y21D');
    normalized = normalized.replaceAll(RegExp(r'\bV70 V70 FE SERIES\b'), 'V70');
    normalized = normalized.replaceAll(RegExp(r'\bV70 FE SERIES\b'), 'V70');
    normalized = normalized.replaceAll(RegExp(r'\bSERIES\b'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\bTARGET\b'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\bALL TYPE\b'), ' ');
    normalized = normalized.replaceAll(
      RegExp(
        r'\b(JANUARI|FEBRUARI|MARET|APRIL|MEI|JUNI|JULI|AGUSTUS|SEPTEMBER|OKTOBER|NOVEMBER|DESEMBER)\b',
      ),
      ' ',
    );
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  static int? _parseInt(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.replaceAll('.', '').replaceAll(',', '');
    final intValue = int.tryParse(normalized);
    if (intValue != null) return intValue;
    final doubleValue = double.tryParse(trimmed);
    if (doubleValue != null) return doubleValue.round();
    return null;
  }

  static String? _parseDateCell(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final direct = DateTime.tryParse(trimmed);
    if (direct != null) {
      return DateTime(
        direct.year,
        direct.month,
        direct.day,
      ).toIso8601String().split('T').first;
    }

    final serial = double.tryParse(trimmed);
    if (serial != null) {
      final date = DateTime(1899, 12, 30).add(Duration(days: serial.floor()));
      return DateTime(
        date.year,
        date.month,
        date.day,
      ).toIso8601String().split('T').first;
    }

    final slashMatch = RegExp(
      r'^(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})$',
    ).firstMatch(trimmed);
    if (slashMatch != null) {
      final day = int.parse(slashMatch.group(1)!);
      final month = int.parse(slashMatch.group(2)!);
      var year = int.parse(slashMatch.group(3)!);
      if (year < 100) year += 2000;
      final date = DateTime(year, month, day);
      return date.toIso8601String().split('T').first;
    }

    return null;
  }

  static String _normalizeHeader(String value) {
    var normalized = value.toUpperCase().trim();
    normalized = normalized.replaceAll('（', '(').replaceAll('）', ')');
    normalized = normalized.replaceAll(RegExp(r'[^A-Z0-9]+'), ' ');
    normalized = normalized.replaceAll(RegExp(r'\s+'), ' ').trim();
    return normalized;
  }

  static String _normalizeName(String value) {
    return _normalizeHeader(value);
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

  static String _cell(List<String> values, int index) {
    if (index < 0 || index >= values.length) return '';
    return values[index].trim();
  }
}

class _ResolvedHeader {
  const _ResolvedHeader({
    required this.headerRowIndex,
    required this.nameColumnIndex,
    required this.fieldColumns,
    required this.bundleColumns,
  });

  final int headerRowIndex;
  final int nameColumnIndex;
  final Map<String, int> fieldColumns;
  final Map<String, int> bundleColumns;
}

class _MatchedUser {
  const _MatchedUser({required this.userId, required this.fullName});

  final String userId;
  final String fullName;
}

class _BundleAlias {
  const _BundleAlias({
    required this.bundleId,
    required this.bundleName,
    required this.normalized,
  });

  final String bundleId;
  final String bundleName;
  final String normalized;
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

const String _officeNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
