import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;

const double kSatorPromotorAchievementExportCanvasWidth = 1500;
const double kSatorPromotorAchievementExportMinCanvasWidth = 1080;

Widget buildSatorPromotorAchievementExportWidget({
  required String satorName,
  required DateTime dataDate,
  required DateTime monthStart,
  required List<Map<String, dynamic>> rows,
  required Map<String, dynamic> totals,
  double canvasWidth = kSatorPromotorAchievementExportCanvasWidth,
}) {
  final dateText = DateFormat('dd MMM yyyy', 'id_ID').format(dataDate);
  final periodText =
      '${DateFormat('d MMM', 'id_ID').format(monthStart)} - ${DateFormat('d MMM yyyy', 'id_ID').format(dataDate)}';
  final specialLabels = _resolveSpecialLabels(rows);
  final daysInMonth = DateTime(dataDate.year, dataDate.month + 1, 0).day;
  final timeGonePct = daysInMonth == 0
      ? 0.0
      : (dataDate.day / daysInMonth) * 100;

  const noWidth = 30.0;
  const nameWidth = 172.0;
  const statusWidth = 64.0;
  const selloutMetricWidth = 78.0;
  const focusWidth = 98.0;
  const vastMetricWidth = 66.0;
  const vastClosingWidth = 94.0;
  const unitWidth = 48.0;
  const outerHorizontalPadding = 28.0;
  const tableHorizontalBorder = 2.0;
  const horizontalPadding = 20.0;
  const specialMinWidth = 64.0;
  const specialMaxWidth = 84.0;
  final fixedMetricWidth =
      noWidth +
      nameWidth +
      statusWidth +
      (selloutMetricWidth * 4) +
      focusWidth +
      (vastMetricWidth * 5) +
      vastClosingWidth +
      unitWidth;

  final minimumCanvasWidth =
      outerHorizontalPadding +
      tableHorizontalBorder +
      horizontalPadding +
      fixedMetricWidth +
      (specialLabels.length * specialMinWidth) +
      0;

  final resolvedCanvasWidth = canvasWidth
      .clamp(
        math.max(
          kSatorPromotorAchievementExportMinCanvasWidth,
          minimumCanvasWidth,
        ),
        math.max(
          kSatorPromotorAchievementExportCanvasWidth,
          minimumCanvasWidth,
        ),
      )
      .toDouble();

  final tableContentWidth =
      resolvedCanvasWidth -
      outerHorizontalPadding -
      tableHorizontalBorder -
      horizontalPadding;

  final specialWidth = specialLabels.isEmpty
      ? 0.0
      : ((tableContentWidth - fixedMetricWidth) /
                specialLabels.length)
            .clamp(specialMinWidth, specialMaxWidth);

  return Container(
    width: resolvedCanvasWidth,
    color: const Color(0xFFF7F3EC),
    padding: const EdgeInsets.all(14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFBF8F2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD9D1C2)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Laporan Pencapaian Promotor',
                      style: GoogleFonts.playfairDisplay(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF1D1A16),
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$satorName • $dateText',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF241F19),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Periode data: $periodText',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF4A4237),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _infoBadge(
                          'Time Gone ${_formatPct(timeGonePct)}',
                          bg: const Color(0xFFECE4D4),
                          fg: const Color(0xFF2A251F),
                        ),
                        _infoBadge(
                          'Hijau aman • Kuning waspada • Merah low',
                          bg: const Color(0xFFF5EFE3),
                          fg: const Color(0xFF544B3F),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFBF8F2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD9D1C2)),
          ),
          child: Column(
            children: [
              _buildTableHeader(
                specialLabels,
                noWidth: noWidth,
                nameWidth: nameWidth,
                statusWidth: statusWidth,
                selloutMetricWidth: selloutMetricWidth,
                focusWidth: focusWidth,
                specialWidth: specialWidth,
                vastMetricWidth: vastMetricWidth,
                vastClosingWidth: vastClosingWidth,
                unitWidth: unitWidth,
              ),
              ...rows.asMap().entries.map((entry) {
                final index = entry.key;
                return _buildTableRow(
                  row: Map<String, dynamic>.from(entry.value),
                  specialLabels: specialLabels,
                  noWidth: noWidth,
                  nameWidth: nameWidth,
                  statusWidth: statusWidth,
                  selloutMetricWidth: selloutMetricWidth,
                  focusWidth: focusWidth,
                  specialWidth: specialWidth,
                  vastMetricWidth: vastMetricWidth,
                  vastClosingWidth: vastClosingWidth,
                  unitWidth: unitWidth,
                  timeGonePct: timeGonePct,
                  isLast: index == rows.length - 1,
                );
              }),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildTableHeader(
  List<String> specialLabels, {
  required double noWidth,
  required double nameWidth,
  required double statusWidth,
  required double selloutMetricWidth,
  required double focusWidth,
  required double specialWidth,
  required double vastMetricWidth,
  required double vastClosingWidth,
  required double unitWidth,
}) {
  return Container(
    padding: const EdgeInsets.fromLTRB(10, 11, 10, 10),
    decoration: const BoxDecoration(
      color: Color(0xFFF1EADD),
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    child: Row(
      children: [
        _headerCell('No', noWidth, TextAlign.center),
        _headerCell('Promotor / Toko', nameWidth, TextAlign.left),
        _headerCell('Status', statusWidth, TextAlign.center),
        _headerMetricCell('SO Target', selloutMetricWidth),
        _headerMetricCell('SO Capai', selloutMetricWidth),
        _headerMetricCell('SO %', selloutMetricWidth),
        _headerMetricCell('SO Selisih', selloutMetricWidth),
        _headerCell(
          'Tipe Fokus',
          focusWidth,
          TextAlign.left,
          subtitle: 'Target / Capai / %',
        ),
        ...specialLabels.map(
          (label) => _headerCell(
            label,
            specialWidth,
            TextAlign.left,
            subtitle: 'Target / Capai / %',
          ),
        ),
        _headerMetricCell('VAST Tgt', vastMetricWidth),
        _headerMetricCell('VAST In', vastMetricWidth),
        _headerMetricCell('VAST %', vastMetricWidth),
        _headerMetricCell('VAST P', vastMetricWidth),
        _headerMetricCell('VAST R', vastMetricWidth),
        _headerMetricCell('VAST Closing', vastClosingWidth),
        _headerCell('Unit', unitWidth, TextAlign.center),
      ],
    ),
  );
}

Widget _buildTableRow({
  required Map<String, dynamic> row,
  required List<String> specialLabels,
  required double noWidth,
  required double nameWidth,
  required double statusWidth,
  required double selloutMetricWidth,
  required double focusWidth,
  required double specialWidth,
  required double vastMetricWidth,
  required double vastClosingWidth,
  required double unitWidth,
  required double timeGonePct,
  required bool isLast,
}) {
  final specials = (row['specials'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => Map<String, dynamic>.from(item))
      .toList();
  final specialMap = <String, Map<String, dynamic>>{
    for (final item in specials) '${item['label'] ?? ''}': item,
  };
  final status = '${row['status_label'] ?? '-'}'.toLowerCase();
  final selloutTone = _resolveTone(_toNum(row['sellout_pct']), timeGonePct);
  final focusTone = _resolveTone(_toNum(row['focus_pct']), timeGonePct);
  final vastTone = _resolveTone(_toNum(row['vast_pct']), timeGonePct);

  return Container(
    padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      border: Border(
        top: const BorderSide(color: Color(0xFFE3DACD)),
        bottom: isLast
            ? BorderSide.none
            : const BorderSide(color: Color(0xFFF0E8DB)),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _rowTextCell('${row['no'] ?? '-'}', noWidth, align: TextAlign.center),
        SizedBox(
          width: nameWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${row['promotor_name'] ?? '-'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 12.4,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF1D1A16),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${row['store_name'] ?? '-'}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(
                  fontSize: 11.1,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF5E5549),
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: statusWidth,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: status == 'official'
                    ? const Color(0xFFDFF1E3)
                    : const Color(0xFFF8EBCF),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${row['status_label'] ?? '-'}',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceMono(
                  fontSize: 8.8,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2A251F),
                ),
              ),
            ),
          ),
        ),
        _metricNumberCell(
          _formatCompactMoney(_toNum(row['sellout_target'])),
          selloutMetricWidth,
          tone: selloutTone,
          align: TextAlign.right,
        ),
        _metricNumberCell(
          _formatCompactMoney(_toNum(row['sellout_actual'])),
          selloutMetricWidth,
          tone: selloutTone,
          align: TextAlign.right,
        ),
        _metricNumberCell(
          _formatPct(_toNum(row['sellout_pct'])),
          selloutMetricWidth,
          tone: selloutTone,
          align: TextAlign.right,
        ),
        _metricNumberCell(
          _formatCompactMoney(_toNum(row['sellout_gap'])),
          selloutMetricWidth,
          tone: selloutTone,
          align: TextAlign.right,
        ),
        _metricValueCell(
          width: focusWidth,
          primary:
              '${_toInt(row['focus_target'])} / ${_toInt(row['focus_actual'])}',
          secondary: _formatPct(_toNum(row['focus_pct'])),
          tone: focusTone,
        ),
        ...specialLabels.map((label) {
          final item = specialMap[label] ?? const <String, dynamic>{};
          return _metricValueCell(
            width: specialWidth,
            primary: '${_toInt(item['target'])} / ${_toInt(item['actual'])}',
            secondary: _formatPct(_toNum(item['pct'])),
            tone: _resolveTone(_toNum(item['pct']), timeGonePct),
          );
        }),
        _metricNumberCell(
          '${_toInt(row['vast_target_input'])}',
          vastMetricWidth,
          tone: vastTone,
          align: TextAlign.right,
        ),
        _metricNumberCell(
          '${_toInt(row['vast_total_input'])}',
          vastMetricWidth,
          tone: vastTone,
          align: TextAlign.right,
        ),
        _metricNumberCell(
          _formatPct(_toNum(row['vast_pct'])),
          vastMetricWidth,
          tone: vastTone,
          align: TextAlign.right,
        ),
        _metricNumberCell(
          '${_toInt(row['vast_pending'])}',
          vastMetricWidth,
          tone: vastTone,
          align: TextAlign.right,
        ),
        _metricNumberCell(
          '${_toInt(row['vast_reject'])}',
          vastMetricWidth,
          tone: vastTone,
          align: TextAlign.right,
        ),
        _metricNumberCell(
          _formatCompactMoney(_toNum(row['vast_closing_amount'])),
          vastClosingWidth,
          tone: vastTone,
          align: TextAlign.right,
        ),
        _rowTextCell(
          '${_toInt(row['total_unit'])}',
          unitWidth,
          align: TextAlign.center,
        ),
      ],
    ),
  );
}

Widget _metricNumberCell(
  String value,
  double width, {
  required _MetricTone tone,
  TextAlign align = TextAlign.left,
}) {
  return SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Text(
        value,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.outfit(
          fontSize: 11.6,
          fontWeight: FontWeight.w800,
          color: tone.primaryText,
          height: 1.05,
        ),
      ),
    ),
  );
}

Widget _headerCell(
  String label,
  double width,
  TextAlign align, {
  String? subtitle,
}) {
  return SizedBox(
    width: width,
    child: Column(
      crossAxisAlignment: align == TextAlign.center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Text(
          label,
          textAlign: align,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.outfit(
            fontSize: 11.8,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF2A251F),
            height: 1.1,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle,
            textAlign: align,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 9.6,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF544B3F),
              height: 1.08,
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _headerMetricCell(String label, double width) {
  return SizedBox(
    width: width,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        label,
        textAlign: TextAlign.right,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.outfit(
          fontSize: 11.8,
          fontWeight: FontWeight.w800,
          color: const Color(0xFF2A251F),
          height: 1.1,
        ),
      ),
    ),
  );
}

Widget _rowTextCell(
  String value,
  double width, {
  TextAlign align = TextAlign.left,
}) {
  return SizedBox(
    width: width,
    child: Text(
      value,
      textAlign: align,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: GoogleFonts.outfit(
        fontSize: 12.2,
        fontWeight: FontWeight.w700,
        color: const Color(0xFF1D1A16),
      ),
    ),
  );
}

Widget _infoBadge(String text, {required Color bg, required Color fg}) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: GoogleFonts.outfit(
        fontSize: 10.8,
        fontWeight: FontWeight.w800,
        color: fg,
      ),
    ),
  );
}

Widget _metricValueCell({
  required double width,
  required String primary,
  required String secondary,
  required _MetricTone tone,
}) {
  return SizedBox(
    width: width,
    child: Container(
      padding: const EdgeInsets.fromLTRB(7, 6, 7, 6),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: tone.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            primary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: tone.primaryText,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            secondary,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              fontSize: 11.2,
              fontWeight: FontWeight.w700,
              color: tone.secondaryText,
              height: 1.1,
            ),
          ),
        ],
      ),
    ),
  );
}

_MetricTone _resolveTone(num pct, double timeGonePct) {
  if (pct <= 0) return _MetricTone.red();
  if (pct >= timeGonePct + 5) return _MetricTone.green();
  if (pct >= timeGonePct - 10) return _MetricTone.yellow();
  return _MetricTone.red();
}

class _MetricTone {
  final Color background;
  final Color border;
  final Color primaryText;
  final Color secondaryText;

  const _MetricTone({
    required this.background,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
  });

  factory _MetricTone.green() => const _MetricTone(
    background: Color(0xFFE5F5E9),
    border: Color(0xFF9FD3AE),
    primaryText: Color(0xFF165A2D),
    secondaryText: Color(0xFF246E3C),
  );

  factory _MetricTone.yellow() => const _MetricTone(
    background: Color(0xFFFFF4D9),
    border: Color(0xFFE7C87A),
    primaryText: Color(0xFF7C5600),
    secondaryText: Color(0xFF8E680D),
  );

  factory _MetricTone.red() => const _MetricTone(
    background: Color(0xFFFBE3E3),
    border: Color(0xFFE0A3A3),
    primaryText: Color(0xFF8B2323),
    secondaryText: Color(0xFFA23838),
  );
}

List<String> _resolveSpecialLabels(List<Map<String, dynamic>> rows) {
  final labels = <String>{};
  for (final row in rows) {
    final specials = (row['specials'] as List? ?? const []).whereType<Map>();
    for (final item in specials) {
      final label = '${item['label'] ?? ''}'.trim();
      if (label.isNotEmpty) labels.add(label);
    }
  }
  final ordered = labels.toList()..sort();
  return ordered;
}

String _formatPct(num value) => '${value.toStringAsFixed(1)}%';

String _formatCompactMoney(num value) {
  final compact = NumberFormat.compactCurrency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final prefix = value > 0 ? '+' : '';
  return '$prefix${compact.format(value)}';
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? 0;
}

num _toNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse('${value ?? ''}') ?? 0;
}
