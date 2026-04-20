import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../ui/promotor/promotor.dart';

class VastPromotorInputViewer {
  VastPromotorInputViewer._();

  static Future<void> show({
    required BuildContext context,
    required SupabaseClient supabase,
    required String promotorId,
    required String promotorName,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final dateFormat = DateFormat('dd MMM yyyy', 'id_ID');
    final currencyFormat = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final future = _fetchApplications(
      supabase: supabase,
      promotorId: promotorId,
      startDate: startDate,
      endDate: endDate,
    );

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final t = context.fieldTokens;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          maxChildSize: 0.95,
          minChildSize: 0.45,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(color: t.surface3),
              ),
              child: FutureBuilder<List<Map<String, dynamic>>>(
                future: future,
                builder: (context, snapshot) {
                  final items = snapshot.data ?? const <Map<String, dynamic>>[];
                  return CustomScrollView(
                    controller: scrollController,
                    slivers: [
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Center(
                                child: Container(
                                  width: 44,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: t.surface3,
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                promotorName,
                                style: PromotorText.display(
                                  size: 22,
                                  color: t.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${dateFormat.format(startDate)} - ${dateFormat.format(endDate)}',
                                style: PromotorText.outfit(
                                  size: 12,
                                  weight: FontWeight.w700,
                                  color: t.primaryAccent,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Daftar input VAST promotor. Tap item untuk lihat isi form lengkap.',
                                style: PromotorText.outfit(
                                  size: 11,
                                  color: t.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: CircularProgressIndicator(
                              color: t.primaryAccent,
                            ),
                          ),
                        )
                      else if (items.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Belum ada input VAST pada periode ini.',
                                textAlign: TextAlign.center,
                                style: PromotorText.outfit(
                                  size: 12,
                                  color: t.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          sliver: SliverList.separated(
                            itemCount: items.length,
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _ApplicationListCard(
                                item: item,
                                dateFormat: dateFormat,
                                currencyFormat: currencyFormat,
                                onTap: () => _showDetail(
                                  context: context,
                                  supabase: supabase,
                                  item: item,
                                  dateFormat: dateFormat,
                                  currencyFormat: currencyFormat,
                                ),
                              );
                            },
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 10),
                          ),
                        ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  static Future<List<Map<String, dynamic>>> _fetchApplications({
    required SupabaseClient supabase,
    required String promotorId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final start = DateFormat('yyyy-MM-dd').format(startDate);
    final endExclusive = DateFormat(
      'yyyy-MM-dd',
    ).format(endDate.add(const Duration(days: 1)));
    final rows = await supabase
        .from('vast_applications')
        .select(
          'id, application_date, customer_name, customer_phone, product_label, '
          'pekerjaan, monthly_income, limit_amount, dp_amount, tenor_months, '
          'outcome_status, lifecycle_status, notes, created_at',
        )
        .eq('promotor_id', promotorId)
        .gte('application_date', start)
        .lt('application_date', endExclusive)
        .isFilter('deleted_at', null)
        .order('application_date', ascending: false)
        .order('created_at', ascending: false);

    return List<Map<String, dynamic>>.from(rows);
  }

  static Future<void> _showDetail({
    required BuildContext context,
    required SupabaseClient supabase,
    required Map<String, dynamic> item,
    required DateFormat dateFormat,
    required NumberFormat currencyFormat,
  }) async {
    final t = context.fieldTokens;
    final applicationId = '${item['id'] ?? ''}'.trim();
    if (applicationId.isEmpty) return;

    final evidences = await supabase
        .from('vast_application_evidences')
        .select('id, file_url, evidence_type, created_at')
        .eq('application_id', applicationId)
        .order('created_at', ascending: true);
    final evidenceRows = List<Map<String, dynamic>>.from(evidences);

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          maxChildSize: 0.96,
          minChildSize: 0.5,
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(color: t.surface3),
              ),
              child: SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 44,
                        height: 4,
                        decoration: BoxDecoration(
                          color: t.surface3,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      item['customer_name']?.toString() ?? '-',
                      style: PromotorText.display(
                        size: 22,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _pill(
                          context,
                          item['product_label']?.toString() ?? '-',
                        ),
                        _pill(
                          context,
                          item['customer_phone']?.toString() ?? '-',
                        ),
                        _pill(context, '${_toInt(item['tenor_months'])} bulan'),
                        _pill(
                          context,
                          (item['outcome_status']?.toString() ?? '-')
                              .toUpperCase(),
                        ),
                        _pill(
                          context,
                          item['lifecycle_status']?.toString() ?? '-',
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _detailTile(
                          context,
                          'Tanggal',
                          dateFormat.format(
                            DateTime.tryParse('${item['application_date']}') ??
                                DateTime.now(),
                          ),
                        ),
                        _detailTile(
                          context,
                          'Pekerjaan',
                          item['pekerjaan']?.toString() ?? '-',
                        ),
                        _detailTile(
                          context,
                          'Penghasilan',
                          currencyFormat.format(_toNum(item['monthly_income'])),
                        ),
                        _detailTile(
                          context,
                          'Limit',
                          currencyFormat.format(_toNum(item['limit_amount'])),
                        ),
                        _detailTile(
                          context,
                          'DP',
                          currencyFormat.format(_toNum(item['dp_amount'])),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Catatan',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Text(
                        (item['notes']?.toString() ?? '').trim().isEmpty
                            ? '-'
                            : item['notes'].toString(),
                        style: PromotorText.outfit(
                          size: 12,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Bukti Foto',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (evidenceRows.isEmpty)
                      Text(
                        'Tidak ada bukti foto.',
                        style: PromotorText.outfit(
                          size: 12,
                          color: t.textSecondary,
                        ),
                      )
                    else
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: evidenceRows.map((evidence) {
                          final imageUrl =
                              evidence['file_url']?.toString() ?? '';
                          final label =
                              evidence['evidence_type']?.toString() ?? 'Bukti';
                          return SizedBox(
                            width: 132,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: AspectRatio(
                                    aspectRatio: 1,
                                    child: imageUrl.isEmpty
                                        ? Container(
                                            color: t.surface2,
                                            alignment: Alignment.center,
                                            child: Icon(
                                              Icons.broken_image_outlined,
                                              color: t.textSecondary,
                                            ),
                                          )
                                        : Image.network(
                                            imageUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) {
                                                  return Container(
                                                    color: t.surface2,
                                                    alignment: Alignment.center,
                                                    child: Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                      color: t.textSecondary,
                                                    ),
                                                  );
                                                },
                                          ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  label,
                                  style: PromotorText.outfit(
                                    size: 11,
                                    weight: FontWeight.w700,
                                    color: t.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Widget _pill(BuildContext context, String text) {
    final t = context.fieldTokens;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 10,
          weight: FontWeight.w700,
          color: t.textPrimary,
        ),
      ),
    );
  }

  static Widget _detailTile(BuildContext context, String label, String value) {
    final t = context.fieldTokens;
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w800,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  static int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  static num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }
}

class _ApplicationListCard extends StatelessWidget {
  const _ApplicationListCard({
    required this.item,
    required this.dateFormat,
    required this.currencyFormat,
    required this.onTap,
  });

  final Map<String, dynamic> item;
  final DateFormat dateFormat;
  final NumberFormat currencyFormat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final date =
        DateTime.tryParse('${item['application_date']}') ?? DateTime.now();
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: t.surface3),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item['customer_name']?.toString() ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                Text(
                  dateFormat.format(date),
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: t.primaryAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '${item['product_label'] ?? '-'} · ${item['customer_phone'] ?? '-'}',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Penghasilan ${currencyFormat.format(VastPromotorInputViewer._toNum(item['monthly_income']))} · '
              'DP ${currencyFormat.format(VastPromotorInputViewer._toNum(item['dp_amount']))} · '
              '${VastPromotorInputViewer._toInt(item['tenor_months'])} bulan',
              style: PromotorText.outfit(size: 10.5, color: t.textMuted),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.open_in_new_rounded,
                  size: 14,
                  color: t.primaryAccent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Lihat isi form',
                  style: PromotorText.outfit(
                    size: 10.5,
                    weight: FontWeight.w800,
                    color: t.primaryAccent,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
