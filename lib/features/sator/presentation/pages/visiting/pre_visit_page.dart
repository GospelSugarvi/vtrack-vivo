import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../../ui/promotor/promotor.dart';

class PreVisitPage extends StatefulWidget {
  final String storeId;

  const PreVisitPage({super.key, required this.storeId});

  @override
  State<PreVisitPage> createState() => _PreVisitPageState();
}

class _PreVisitPageState extends State<PreVisitPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _commentController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  int _tabIndex = 0;
  Map<String, dynamic>? _store;
  List<Map<String, dynamic>> _comments = const [];
  Map<String, dynamic>? _performance;
  int _visitCount = 0;
  DateTime? _lastVisitAt;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Sesi login tidak ditemukan');

      final storeFuture = _supabase
          .from('stores')
          .select('id, store_name, address, area')
          .eq('id', widget.storeId)
          .maybeSingle();

      final commentsFuture = _supabase
          .from('store_visit_comments')
          .select(
            'id, comment_text, created_at, users!store_visit_comments_author_id_fkey(full_name)',
          )
          .eq('store_id', widget.storeId)
          .or('target_sator_id.eq.$userId,author_id.eq.$userId')
          .order('created_at', ascending: false)
          .limit(12);

      final performanceFuture = _supabase.rpc(
        'get_sator_visiting_briefing',
        params: {
          'p_sator_id': userId,
          'p_store_id': widget.storeId,
          'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        },
      );

      final results = await Future.wait<dynamic>([
        storeFuture,
        commentsFuture,
        performanceFuture,
      ]);
      final store = results[0] as Map<String, dynamic>?;
      final comments = List<Map<String, dynamic>>.from(results[1] as List);
      final performance = Map<String, dynamic>.from(results[2] as Map? ?? {});
      final visiting = Map<String, dynamic>.from(
        performance['visiting'] as Map? ?? const {},
      );

      if (!mounted) return;
      setState(() {
        _store = store;
        _comments = comments;
        _performance = performance;
        _visitCount = _toInt(visiting['visit_count']);
        _lastVisitAt = DateTime.tryParse(
          '${visiting['last_visit_at'] ?? ''}',
        )?.toLocal();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveNote() async {
    final text = _commentController.text.trim();
    if (text.isEmpty) return;
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isSaving = true);
    try {
      await _supabase.from('store_visit_comments').insert({
        'store_id': widget.storeId,
        'author_id': userId,
        'target_sator_id': userId,
        'comment_text': text,
      });
      _commentController.clear();
      await _loadData();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Catatan gagal disimpan. $e'),
          backgroundColor: t.danger,
        ),
      );
      setState(() => _isSaving = false);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _goToForm() {
    context.push('/sator/visiting/form/${widget.storeId}');
  }

  void _openStoreBriefing() {
    context.push('/sator/toko/${widget.storeId}');
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  String _formatCommentDate(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    final date = raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(date);
  }

  String _formatCompactDate(dynamic value) {
    if (value is DateTime) {
      return DateFormat('dd MMM yy', 'id_ID').format(value);
    }
    final raw = '${value ?? ''}'.trim();
    final date = raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '-';
    return DateFormat('dd MMM yy', 'id_ID').format(date);
  }

  String _compactCurrency(int value) {
    if (value >= 1000000) {
      final amount = value / 1000000;
      return 'Rp${amount.toStringAsFixed(amount >= 10 ? 0 : 1)}jt';
    }
    if (value >= 1000) {
      final amount = value / 1000;
      return 'Rp${amount.toStringAsFixed(amount >= 10 ? 0 : 1)}rb';
    }
    return 'Rp$value';
  }

  List<String> _briefingWarnings() {
    final warnings = <String>[];
    final allbrand = _performance?['allbrand'] as Map<String, dynamic>?;
    final activity = Map<String, dynamic>.from(
      _performance?['activity'] as Map? ?? const {},
    );
    final priority = Map<String, dynamic>.from(
      _performance?['priority'] as Map? ?? const {},
    );
    final vivoMs = _toDouble(allbrand?['vivo_market_share']);
    warnings.addAll(List<String>.from(priority['reasons'] ?? const []));
    if (vivoMs > 0 && vivoMs < 35) {
      warnings.add('Market share VIVO masih rendah');
    }
    if (_toInt(activity['low_activity_count']) > 0) {
      warnings.add(
        '${_toInt(activity['low_activity_count'])} promotor aktivitasnya rendah',
      );
    }
    return warnings;
  }

  @override
  Widget build(BuildContext context) {
    final storeName = '${_store?['store_name'] ?? '-'}';
    final address = '${_store?['address'] ?? '-'}';
    final area = '${_store?['area'] ?? '-'}';
    final target = _performance?['target'] as Map<String, dynamic>?;
    final allbrand = _performance?['allbrand'] as Map<String, dynamic>?;
    final promotors = List<Map<String, dynamic>>.from(
      _performance?['promotors'] ?? const [],
    );
    final vastHistory = List<Map<String, dynamic>>.from(
      _performance?['vast_last_3_months'] ?? const [],
    );
    final warnings = _briefingWarnings();

    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: const Text('Pre Visit')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storeName,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$area · $address',
                        style: PromotorText.outfit(
                          size: 9.5,
                          weight: FontWeight.w700,
                          color: t.textMutedStrong,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _tinyPill('Visit $_visitCount', t.primaryAccent),
                          _tinyPill(
                            _lastVisitAt == null
                                ? 'Belum Visit'
                                : _formatCompactDate(_lastVisitAt),
                            _lastVisitAt == null ? t.warning : t.success,
                          ),
                          if (warnings.isNotEmpty)
                            _tinyPill('${warnings.length} warning', t.danger),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _briefPill(
                            'All Type ${_toInt(target?['all_type_units'])}/${_toInt(target?['daily_target'])}',
                            t.primaryAccent,
                          ),
                          _briefPill(
                            'Fokus ${_toInt(target?['fokus_achievement'])}/${_toInt(target?['fokus_target'])}',
                            t.warning,
                          ),
                          _briefPill(
                            'AllBrand ${_toDouble(allbrand?['vivo_market_share']).toStringAsFixed(1)}%',
                            t.success,
                          ),
                          _briefPill(
                            'VAST ${vastHistory.isEmpty ? 0 : _toInt(vastHistory.first['total_submissions'])}/${vastHistory.isEmpty ? 0 : _toInt(vastHistory.first['target_submissions'])}',
                            t.primaryAccent,
                          ),
                        ],
                      ),
                      if (vastHistory.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: vastHistory.map((row) {
                            final month = DateTime.tryParse(
                              '${row['month_key'] ?? ''}',
                            );
                            final monthLabel = month == null
                                ? '-'
                                : DateFormat('MMM yy', 'id_ID').format(month);
                            return _tinyPill(
                              '$monthLabel ${_toInt(row['total_submissions'])}/${_toInt(row['target_submissions'])}',
                              t.primaryAccent,
                            );
                          }).toList(),
                        ),
                      ],
                      if (warnings.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: warnings
                              .map((item) => _warningChip(item))
                              .toList(),
                        ),
                      ],
                      const SizedBox(height: 8),
                      OutlinedButton(
                        onPressed: _openStoreBriefing,
                        child: const Text('Buka Briefing Toko'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _tabButton(0, 'Promotor')),
                      Expanded(child: _tabButton(1, 'AllBrand')),
                      Expanded(child: _tabButton(2, 'VAST')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (_tabIndex == 0)
                  _buildPromotorTab(promotors)
                else if (_tabIndex == 1)
                  _buildAllBrandTab(allbrand, promotors)
                else
                  _buildVastTab(vastHistory, promotors),
                const SizedBox(height: 10),
                _buildNotesSection(),
                const SizedBox(height: 10),
                _buildCommentHistory(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _goToForm,
              child: Text(
                'Lanjut ke Form Visit',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w800,
                  color: t.textOnAccent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPromotorTab(List<Map<String, dynamic>> promotors) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: promotors.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Belum ada data promotor.',
                style: PromotorText.outfit(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
            )
          : Column(
              children: promotors.asMap().entries.map((entry) {
                final row = entry.value;
                final lastThree = List<Map<String, dynamic>>.from(
                  row['vast_last_3_months'] ?? const [],
                );
                return Container(
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  decoration: BoxDecoration(
                    border: entry.key == promotors.length - 1
                        ? null
                        : Border(bottom: BorderSide(color: t.surface3)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${row['promotor_name'] ?? 'Promotor'}',
                              style: PromotorText.outfit(
                                size: 11.5,
                                weight: FontWeight.w800,
                                color: t.textPrimary,
                              ),
                            ),
                          ),
                          if (row['allbrand_sent'] == true)
                            _tinyPill('AB', t.success),
                          const SizedBox(width: 6),
                          _tinyPill(
                            row['clock_in'] == true ? 'Absen' : 'Belum',
                            row['clock_in'] == true ? t.success : t.danger,
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _tinyPill(
                            'SO ${_toInt(row['sales_count'])}',
                            t.primaryAccent,
                          ),
                          _tinyPill(
                            '${_compactCurrency(_toInt(row['daily_omzet']))}/${_compactCurrency(_toInt(row['daily_target']))}',
                            t.primaryAccent,
                          ),
                          _tinyPill(
                            'Fokus ${_toInt(row['focus_units'])}/${_toInt(row['focus_target'])}',
                            t.warning,
                          ),
                          _tinyPill(
                            'Stok ${_toInt(row['stock_count'])}',
                            t.warning,
                          ),
                          _tinyPill(
                            'VAST ${_toInt(row['vast_month_submissions'])}/${_toInt(row['vast_target'])}',
                            t.success,
                          ),
                        ],
                      ),
                      if (lastThree.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: lastThree.map((item) {
                            final month = DateTime.tryParse(
                              '${item['month_key'] ?? ''}',
                            );
                            final label = month == null
                                ? '-'
                                : DateFormat('MMM', 'id_ID').format(month);
                            return _tinyPill(
                              '$label ${_toInt(item['total_submissions'])}/${_toInt(item['target_submissions'])}',
                              t.surface3,
                              foreground: t.textMutedStrong,
                            );
                          }).toList(),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildAllBrandTab(
    Map<String, dynamic>? allbrand,
    List<Map<String, dynamic>> promotors,
  ) {
    final rows = promotors
        .where(
          (row) =>
              '${row['latest_allbrand_report_date'] ?? ''}'.trim().isNotEmpty,
        )
        .toList();
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _briefPill(
                  'MS ${_toDouble(allbrand?['vivo_market_share']).toStringAsFixed(1)}%',
                  t.success,
                ),
                _briefPill(
                  'VIVO ${_toInt(allbrand?['vivo_units'])}',
                  t.success,
                ),
                _briefPill(
                  'Kompetitor ${_toInt(allbrand?['total_units'])}',
                  t.warning,
                ),
                _briefPill(
                  _formatCompactDate(allbrand?['report_date']),
                  t.primaryAccent,
                ),
              ],
            ),
          ),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Belum ada laporan AllBrand.',
                style: PromotorText.outfit(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
            )
          else
            ...rows.asMap().entries.map((entry) {
              final row = entry.value;
              return Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                decoration: BoxDecoration(
                  border: entry.key == rows.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: t.surface3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${row['promotor_name'] ?? 'Promotor'}',
                            style: PromotorText.outfit(
                              size: 11.5,
                              weight: FontWeight.w800,
                              color: t.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          _formatCompactDate(
                            row['latest_allbrand_report_date'],
                          ),
                          style: PromotorText.outfit(
                            size: 9,
                            weight: FontWeight.w700,
                            color: t.textMutedStrong,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _tinyPill(
                          'MS ${_toDouble(row['latest_allbrand_vivo_market_share']).toStringAsFixed(1)}%',
                          t.success,
                        ),
                        _tinyPill(
                          'VIVO ${_toInt(row['latest_allbrand_vivo_units'])}',
                          t.success,
                        ),
                        _tinyPill(
                          'Kompetitor ${_toInt(row['latest_allbrand_total_units'])}',
                          t.warning,
                        ),
                        _tinyPill(
                          'Cum ${_toInt(row['latest_allbrand_cumulative_total_units'])}',
                          t.primaryAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildVastTab(
    List<Map<String, dynamic>> vastHistory,
    List<Map<String, dynamic>> promotors,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (vastHistory.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: vastHistory.map((row) {
                  final month = DateTime.tryParse('${row['month_key'] ?? ''}');
                  final monthLabel = month == null
                      ? '-'
                      : DateFormat('MMM yy', 'id_ID').format(month);
                  return _briefPill(
                    '$monthLabel ${_toInt(row['total_submissions'])}/${_toInt(row['target_submissions'])}',
                    t.primaryAccent,
                  );
                }).toList(),
              ),
            ),
          if (promotors.isEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Belum ada data VAST.',
                style: PromotorText.outfit(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
            )
          else
            ...promotors.asMap().entries.map((entry) {
              final row = entry.value;
              final lastThree = List<Map<String, dynamic>>.from(
                row['vast_last_3_months'] ?? const [],
              );
              return Container(
                padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                decoration: BoxDecoration(
                  border: entry.key == promotors.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: t.surface3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${row['promotor_name'] ?? 'Promotor'}',
                            style: PromotorText.outfit(
                              size: 11.5,
                              weight: FontWeight.w800,
                              color: t.textPrimary,
                            ),
                          ),
                        ),
                        _tinyPill(
                          '${_toDouble(row['vast_month_achievement_pct']).toStringAsFixed(0)}%',
                          t.success,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        _tinyPill(
                          'Input ${_toInt(row['vast_month_submissions'])}/${_toInt(row['vast_target'])}',
                          t.primaryAccent,
                        ),
                        _tinyPill(
                          'ACC ${_toInt(row['vast_month_acc'])}',
                          t.success,
                        ),
                        _tinyPill(
                          'Pending ${_toInt(row['vast_month_pending'])}',
                          t.warning,
                        ),
                      ],
                    ),
                    if (lastThree.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: lastThree.map((item) {
                          final month = DateTime.tryParse(
                            '${item['month_key'] ?? ''}',
                          );
                          final label = month == null
                              ? '-'
                              : DateFormat('MMM', 'id_ID').format(month);
                          return _tinyPill(
                            '$label ${_toInt(item['total_submissions'])}/${_toInt(item['target_submissions'])}',
                            t.surface3,
                            foreground: t.textMutedStrong,
                          );
                        }).toList(),
                      ),
                    ],
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Catatan Sebelum Visit',
            style: PromotorText.outfit(
              size: 12.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _commentController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Tulis fokus kunjungan',
              filled: true,
              fillColor: t.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.surface3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.surface3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.primaryAccent),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _isSaving ? null : _saveNote,
              child: Text(_isSaving ? 'Menyimpan...' : 'Simpan Catatan'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommentHistory() {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(
              'Riwayat Catatan',
              style: PromotorText.outfit(
                size: 12.5,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
          ),
          if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'Belum ada catatan.',
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
            )
          else
            ..._comments.asMap().entries.map((entry) {
              final row = entry.value;
              final author = row['users']?['full_name']?.toString() ?? 'User';
              return Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  border: entry.key == _comments.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: t.surface3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['comment_text'] ?? '-'}',
                      style: PromotorText.outfit(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$author · ${_formatCommentDate(row['created_at'])}',
                      style: PromotorText.outfit(
                        size: 9,
                        weight: FontWeight.w700,
                        color: t.textMutedStrong,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label) {
    final active = _tabIndex == index;
    final tone = active ? t.primaryAccent : t.textMutedStrong;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _tabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? t.primaryAccent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: PromotorText.outfit(
            size: 10,
            weight: FontWeight.w800,
            color: tone,
          ),
        ),
      ),
    );
  }

  Widget _briefPill(String text, Color tone) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.14)),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 8.8,
          weight: FontWeight.w800,
          color: tone,
        ),
      ),
    );
  }

  Widget _warningChip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.danger.withValues(alpha: 0.16)),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 8.5,
          weight: FontWeight.w800,
          color: t.danger,
        ),
      ),
    );
  }

  Widget _tinyPill(String text, Color tone, {Color? foreground}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 8,
          weight: FontWeight.w800,
          color: foreground ?? tone,
        ),
      ),
    );
  }
}
