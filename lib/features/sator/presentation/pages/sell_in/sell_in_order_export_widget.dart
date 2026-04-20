import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

const double kSellInOrderExportCanvasWidth = 860;

Widget buildSellInOrderExportWidget({
  required String storeName,
  required DateTime orderDate,
  required List<Map<String, dynamic>> items,
  required int totalQty,
  required num totalValue,
  String? notes,
  String? authorName,
  String badgeText = 'SELL IN',
}) {
  final amount = NumberFormat.decimalPattern('id_ID');
  final currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final dateText = DateFormat('dd MMMM yyyy', 'id_ID').format(orderDate);
  final headerMeta = [dateText, if ((authorName ?? '').trim().isNotEmpty) authorName!.trim()]
      .join('\n');
  final exportNotes = (notes ?? '').trim();
  final yearText = DateTime.now().year.toString();
  final sortedItems = List<Map<String, dynamic>>.from(items)
    ..sort((a, b) {
      final productCompare = '${a['product_name'] ?? ''}'.compareTo(
        '${b['product_name'] ?? ''}',
      );
      if (productCompare != 0) return productCompare;
      final networkCompare = '${a['network_type'] ?? ''}'.compareTo(
        '${b['network_type'] ?? ''}',
      );
      if (networkCompare != 0) return networkCompare;
      final variantCompare = '${a['variant'] ?? ''}'.compareTo(
        '${b['variant'] ?? ''}',
      );
      if (variantCompare != 0) return variantCompare;
      return '${a['color'] ?? ''}'.compareTo('${b['color'] ?? ''}');
    });

  return Container(
    width: kSellInOrderExportCanvasWidth,
    color: const Color(0xFFFAF8F3),
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAF8F3),
            border: Border.all(color: const Color(0xFFD8D2C4)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(26, 20, 26, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  storeName,
                  softWrap: true,
                  style: GoogleFonts.playfairDisplay(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF1C1A16),
                    height: 1,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        headerMeta,
                        textAlign: TextAlign.left,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: const Color(0xFF7A7060),
                          height: 1.6,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      color: const Color(0xFF1C1A16),
                      child: Text(
                        badgeText,
                        style: GoogleFonts.spaceMono(
                          fontSize: 7.5,
                          fontWeight: FontWeight.w700,
                          color: const Color(0xFFFAF8F3),
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Container(height: 2, color: const Color(0xFF1C1A16)),
        Container(height: 1, color: const Color(0xFF1C1A16)),
        _buildTransferAccountCard(),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFFAF8F3),
            border: Border.all(color: const Color(0xFFD8D2C4)),
          ),
          child: Column(
            children: [
              _buildExportTableHeader(),
              ...sortedItems.asMap().entries.map(
                (entry) => _buildExportTableRow(entry.key + 1, entry.value, amount),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
          decoration: const BoxDecoration(
            color: Color(0xFFFAF8F3),
            border: Border(
              left: BorderSide(color: Color(0xFFD8D2C4)),
              right: BorderSide(color: Color(0xFFD8D2C4)),
              bottom: BorderSide(color: Color(0xFFD8D2C4)),
              top: BorderSide(color: Color(0xFF1C1A16), width: 2),
            ),
          ),
          child: Column(
            children: [
              _buildExportTotalLine('Total Qty', '$totalQty unit'),
              _buildExportTotalLine(
                'Total Nominal',
                currency.format(totalValue),
                emphasize: true,
              ),
            ],
          ),
        ),
        if (exportNotes.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            decoration: const BoxDecoration(
              color: Color(0xFFF7F3EB),
              border: Border(
                left: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
                right: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
                bottom: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOTES',
                  style: GoogleFonts.spaceMono(
                    fontSize: 8,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF8E836F),
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  exportNotes,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: const Color(0xFF3E372D),
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: const BoxDecoration(
            color: Color(0xFFF7F3EB),
            border: Border(
              top: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
              left: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
              right: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
              bottom: BorderSide(color: Color(0xFFD8D2C4), width: 0.8),
            ),
          ),
          child: Row(
            children: [
              Text(
                '${storeName.toUpperCase()} © $yearText',
                style: GoogleFonts.spaceMono(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8E836F),
                  letterSpacing: 0.9,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _buildTransferAccountCard() {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
    decoration: BoxDecoration(
      color: const Color(0xFFF0ECE3),
      border: Border.all(color: const Color(0xFFD8D2C4)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'REKENING TUJUAN TRANSFER',
                style: GoogleFonts.spaceMono(
                  fontSize: 7.5,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF9A9080),
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bank BNI',
                style: GoogleFonts.playfairDisplay(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF1C1A16),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                'PT. Long Yin Teknologi Informasi',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  fontWeight: FontWeight.w400,
                  color: const Color(0xFF5A5040),
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'NO. REKENING',
              style: GoogleFonts.spaceMono(
                fontSize: 7.5,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF9A9080),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '804 879 804',
              style: GoogleFonts.spaceMono(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: const Color(0xFF1C1A16),
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

Widget _buildExportTableHeader() {
  return Container(
    color: const Color(0xFFF0ECE3),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    child: Row(
      children: [
        _exportHeaderCell('Item', flex: 8, align: TextAlign.left),
        _exportHeaderCell('Qty', flex: 2, align: TextAlign.center),
        Expanded(
          flex: 8,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'Modal',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceMono(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF9A9080),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const SizedBox(width: 116),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'SRP',
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceMono(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF9A9080),
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _exportHeaderCell('Subtotal', flex: 4, align: TextAlign.right),
      ],
    ),
  );
}

Widget _buildExportTableRow(
  int index,
  Map<String, dynamic> row,
  NumberFormat amount,
) {
  final qty = _toInt(row['qty']);
  final modal = _toNum(row['modal'] ?? row['price']);
  final price = _toNum(row['price'] ?? row['srp']);
  final subtotal = _toNum(row['subtotal']) > 0
      ? _toNum(row['subtotal'])
      : modal * qty;
  final profitValue = price > modal ? (price - modal) : 0.0;
  final marginPct = price > 0 && price > modal
      ? (((price - modal) / price) * 100)
      : 0.0;
  final profitLabel = profitValue > 0
      ? 'profit ${amount.format(profitValue)}(${marginPct.toStringAsFixed(0)}%)'
      : '';
  final specs = [
    '${row['network_type'] ?? ''}'.trim(),
    '${row['variant'] ?? ''}'.trim(),
  ].where((part) => part.isNotEmpty).join(' • ');
  final color = '${row['color'] ?? ''}'.trim();
  final productTitle = color.isEmpty
      ? '${row['product_name'] ?? 'Produk'}'
      : '${row['product_name'] ?? 'Produk'} ($color)';

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: index.isEven ? const Color(0xFFF5F1EA) : const Color(0xFFFAF8F3),
      border: const Border(
        top: BorderSide(color: Color(0xFFDDD8CE), width: 0.5),
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 8,
          child: Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  productTitle,
                  softWrap: true,
                  style: GoogleFonts.outfit(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1C1A16),
                    height: 1.2,
                  ),
                ),
                if (specs.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    specs,
                    softWrap: true,
                    style: GoogleFonts.outfit(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: const Color(0xFF6E6253),
                      height: 1.1,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        _exportValueCell(
          '$qty',
          flex: 2,
          align: TextAlign.center,
          weight: FontWeight.w700,
          fontFamily: GoogleFonts.spaceMono().fontFamily,
          fontSize: 14.5,
        ),
        Expanded(
          flex: 8,
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      modal > 0 ? amount.format(modal) : '-',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF7A7060),
                        fontFamily: GoogleFonts.outfit().fontFamily,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 116,
                child: Text(
                  profitLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: const Color(0xFF8E836F),
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerRight,
                    child: Text(
                      price > 0 ? amount.format(price) : '-',
                      textAlign: TextAlign.right,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: const Color(0xFF1C1A16),
                        fontFamily: GoogleFonts.outfit().fontFamily,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        _exportValueCell(
          amount.format(subtotal),
          flex: 4,
          align: TextAlign.right,
          scaleDown: true,
          weight: FontWeight.w600,
          fontSize: 14.5,
          color: const Color(0xFF1C1A16),
        ),
      ],
    ),
  );
}

Widget _exportHeaderCell(
  String text, {
  required int flex,
  TextAlign align = TextAlign.left,
}) {
  return Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Text(
        text,
        textAlign: align,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.spaceMono(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF9A9080),
          letterSpacing: 0.8,
        ),
      ),
    ),
  );
}

Widget _exportValueCell(
  String text, {
  required int flex,
  TextAlign align = TextAlign.left,
  FontWeight weight = FontWeight.w600,
  bool scaleDown = false,
  double fontSize = 10,
  String? fontFamily,
  Color? color,
}) {
  return Expanded(
    flex: flex,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: scaleDown
          ? FittedBox(
              fit: BoxFit.scaleDown,
              alignment: align == TextAlign.right
                  ? Alignment.centerRight
                  : align == TextAlign.center
                  ? Alignment.center
                  : Alignment.centerLeft,
              child: Text(
                text,
                textAlign: align,
                maxLines: 1,
                style: TextStyle(
                  fontSize: fontSize,
                  fontWeight: weight,
                  color: color ?? const Color(0xFF1C1A16),
                  fontFamily: fontFamily ?? GoogleFonts.outfit().fontFamily,
                ),
              ),
            )
          : Text(
              text,
              textAlign: align,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: weight,
                color: color ?? const Color(0xFF1C1A16),
                fontFamily: fontFamily ?? GoogleFonts.outfit().fontFamily,
              ),
            ),
    ),
  );
}

Widget _buildExportTotalLine(
  String label,
  String value, {
  bool emphasize = false,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      children: [
        Text(
          label.toUpperCase(),
          style: GoogleFonts.spaceMono(
            fontSize: 8,
            fontWeight: FontWeight.w700,
            color: const Color(0xFF8E836F),
            letterSpacing: 0.9,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.outfit(
            fontSize: emphasize ? 17 : 14,
            fontWeight: emphasize ? FontWeight.w700 : FontWeight.w600,
            color: const Color(0xFF1C1A16),
          ),
        ),
      ],
    ),
  );
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
