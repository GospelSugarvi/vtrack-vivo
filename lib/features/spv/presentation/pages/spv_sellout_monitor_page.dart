import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/foundation/field_theme_extensions.dart';
import '../../../../ui/promotor/promotor.dart';

class SpvSellOutMonitorPage extends StatefulWidget {
  const SpvSellOutMonitorPage({super.key});

  @override
  State<SpvSellOutMonitorPage> createState() => _SpvSellOutMonitorPageState();
}

class _SpvSellOutMonitorPageState extends State<SpvSellOutMonitorPage> {
  final _supabase = Supabase.instance.client;
  final _compactCurrency = NumberFormat.compactCurrency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _isLoading = true;
  String _selectedFilter = 'today';
  String? _expandedSatorId;
  late DateTime _rangeStart;
  late DateTime _rangeEnd;
  Map<String, dynamic> _range = const {};
  Map<String, dynamic> _summary = const {};
  List<Map<String, dynamic>> _sators = const [];

  FieldThemeTokens get t => context.fieldTokens;
  Color get _s1 => t.surface1;
  Color get _s2 => t.surface2;
  Color get _s3 => t.surface3;
  Color get _gold => t.primaryAccent;
  Color get _goldDim => t.primaryAccentSoft;
  Color get _cream => t.textPrimary;
  Color get _cream2 => t.textSecondary;
  Color get _muted => t.textMuted;
  Color get _green => t.success;
  Color get _greenDim => t.successSoft;
  Color get _red => t.danger;

  TextStyle _display({
    double size = 28,
    FontWeight weight = FontWeight.w800,
    Color? color,
  }) =>
      PromotorText.display(size: size, weight: weight, color: color ?? _cream);

  TextStyle _outfit({
    double size = 12,
    FontWeight weight = FontWeight.w700,
    Color? color,
    double letterSpacing = 0,
  }) => PromotorText.outfit(
    size: size,
    weight: weight,
    color: color ?? _cream,
    letterSpacing: letterSpacing,
  );

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _rangeStart = DateTime(now.year, now.month, now.day);
    _rangeEnd = DateTime(now.year, now.month, now.day);
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final spvId = _supabase.auth.currentUser?.id;
      if (spvId == null) throw Exception('Sesi login tidak ditemukan');

      final response = await _supabase.rpc(
        'get_spv_sellout_monitor',
        params: {
          'p_spv_id': spvId,
          'p_filter': _selectedFilter,
          'p_start_date': DateFormat('yyyy-MM-dd').format(_rangeStart),
          'p_end_date': DateFormat('yyyy-MM-dd').format(_rangeEnd),
        },
      );

      final payload = Map<String, dynamic>.from(response ?? const {});
      final sators = List<Map<String, dynamic>>.from(
        payload['sators'] ?? const <Map<String, dynamic>>[],
      );

      if (!mounted) return;
      setState(() {
        _range = Map<String, dynamic>.from(
          payload['range'] ?? const <String, dynamic>{},
        );
        _summary = Map<String, dynamic>.from(
          payload['summary'] ?? const <String, dynamic>{},
        );
        _sators = sators;
        final ids = sators.map((row) => '${row['sator_id']}').toSet();
        if (_expandedSatorId == null && sators.isNotEmpty) {
          _expandedSatorId = '${sators.first['sator_id']}';
        } else if (!ids.contains(_expandedSatorId)) {
          _expandedSatorId = sators.isEmpty
              ? null
              : '${sators.first['sator_id']}';
        }
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _range = const {};
        _summary = const {};
        _sators = const [];
        _expandedSatorId = null;
        _isLoading = false;
      });
    }
  }

  double _toDouble(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  String _formatMoney(num value) => _compactCurrency.format(value);

  String _formatPct(double value) => '${value.toStringAsFixed(1)}%';

  Map<String, dynamic> _metric(Map<String, dynamic> source, String key) =>
      Map<String, dynamic>.from(source[key] ?? const <String, dynamic>{});

  Future<void> _setTodayRange() async {
    final now = DateTime.now();
    setState(() {
      _selectedFilter = 'today';
      _rangeStart = DateTime(now.year, now.month, now.day);
      _rangeEnd = DateTime(now.year, now.month, now.day);
    });
    await _loadData();
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
      helpText: 'Pilih Rentang Tanggal',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _selectedFilter = 'custom';
      _rangeStart = DateTime(
        picked.start.year,
        picked.start.month,
        picked.start.day,
      );
      _rangeEnd = DateTime(picked.end.year, picked.end.month, picked.end.day);
    });
    await _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.shellBackground,
      appBar: AppBar(
        backgroundColor: t.shellBackground,
        foregroundColor: _cream,
        title: const Text('Monitor Sell Out'),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: _gold))
          : RefreshIndicator(
              onRefresh: _loadData,
              color: _gold,
              backgroundColor: _s1,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _buildActionChip(
                          icon: Icons.today_outlined,
                          label: 'Hari Ini',
                          onTap: _setTodayRange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildActionChip(
                          icon: Icons.date_range_outlined,
                          label: 'Rentang Tanggal',
                          onTap: _pickDateRange,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildSummaryCard(),
                  const SizedBox(height: 14),
                  Text(
                    'Achievement SATOR',
                    style: _outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: _cream2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_sators.isEmpty)
                    _buildEmptyState()
                  else
                    ..._sators.asMap().entries.map(
                      (entry) => _buildSatorCard(
                        rank: entry.key + 1,
                        row: entry.value,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildSummaryCard() {
    final allType = _metric(_summary, 'all_type');
    final fokus = _metric(_summary, 'focus');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: _s1,
        border: Border.all(color: _s3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Achievement area',
            style: _outfit(size: 12, weight: FontWeight.w800, color: _cream),
          ),
          const SizedBox(height: 2),
          Text(
            '${_range['label'] ?? '-'}',
            style: _outfit(size: 9, color: _muted),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildMetricPanel(
                  title: 'All Type',
                  accent: _green,
                  accentBg: _greenDim,
                  targetLabel: _formatMoney(_toDouble(allType['target'])),
                  actualLabel: _formatMoney(_toDouble(allType['actual'])),
                  achievementLabel: _formatPct(
                    _toDouble(allType['achievement_pct']),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildMetricPanel(
                  title: 'Produk Fokus',
                  accent: _gold,
                  accentBg: _goldDim,
                  targetLabel: _toDouble(fokus['target']).toStringAsFixed(1),
                  actualLabel: '${_toInt(fokus['actual'])}',
                  achievementLabel: _formatPct(
                    _toDouble(fokus['achievement_pct']),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _s1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _s3),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: _muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _outfit(size: 11.5, weight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricPanel({
    required String title,
    required Color accent,
    required Color accentBg,
    required String targetLabel,
    required String actualLabel,
    required String achievementLabel,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: accentBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: _outfit(size: 8, color: accent)),
          const SizedBox(height: 6),
          Text(
            achievementLabel,
            style: _display(size: 15, weight: FontWeight.w800, color: accent),
          ),
          const SizedBox(height: 6),
          Text('Target $targetLabel', style: _outfit(size: 8, color: accent)),
          const SizedBox(height: 2),
          Text('Actual $actualLabel', style: _outfit(size: 8, color: accent)),
        ],
      ),
    );
  }

  Widget _buildSatorCard({
    required int rank,
    required Map<String, dynamic> row,
  }) {
    final satorId = '${row['sator_id'] ?? ''}';
    final expanded = _expandedSatorId == satorId;
    final allType = _metric(row, 'all_type');
    final fokus = _metric(row, 'focus');
    final promotors = List<Map<String, dynamic>>.from(
      row['promotors'] ?? const <Map<String, dynamic>>[],
    );
    final tone = _toDouble(allType['achievement_pct']) >= 100
        ? _green
        : (_toDouble(allType['achievement_pct']) >= 70 ? _gold : _red);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? tone.withValues(alpha: 0.28) : _s3,
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () =>
                setState(() => _expandedSatorId = expanded ? null : satorId),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: tone.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$rank',
                          style: _outfit(
                            size: 10,
                            weight: FontWeight.w800,
                            color: tone,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '${row['sator_name'] ?? 'SATOR'}',
                          style: _outfit(
                            size: 11,
                            weight: FontWeight.w800,
                            color: _cream,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        expanded ? 'Tutup' : 'Promotor',
                        style: _outfit(size: 7, color: _muted),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _buildMetricMiniCard(
                          label: 'All Type',
                          target: _formatMoney(_toDouble(allType['target'])),
                          actual: _formatMoney(_toDouble(allType['actual'])),
                          achievement: _formatPct(
                            _toDouble(allType['achievement_pct']),
                          ),
                          tone: _green,
                          bg: _greenDim,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _buildMetricMiniCard(
                          label: 'Fokus',
                          target: _toDouble(fokus['target']).toStringAsFixed(1),
                          actual: '${_toInt(fokus['actual'])}',
                          achievement: _formatPct(
                            _toDouble(fokus['achievement_pct']),
                          ),
                          tone: _gold,
                          bg: _goldDim,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            Divider(height: 1, color: _s3),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Achievement Promotor',
                    style: _outfit(
                      size: 10,
                      weight: FontWeight.w800,
                      color: _cream2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (promotors.isEmpty)
                    _buildEmptyState(
                      message: 'Belum ada promotor di SATOR ini.',
                    )
                  else
                    ...promotors.map(_buildPromotorCard),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetricMiniCard({
    required String label,
    required String target,
    required String actual,
    required String achievement,
    required Color tone,
    required Color bg,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tone.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 8, color: tone)),
          const SizedBox(height: 3),
          Text(
            achievement,
            style: _outfit(size: 10, weight: FontWeight.w800, color: tone),
          ),
          const SizedBox(height: 4),
          Text('T $target', style: _outfit(size: 7, color: tone)),
          const SizedBox(height: 1),
          Text('A $actual', style: _outfit(size: 7, color: tone)),
        ],
      ),
    );
  }

  Widget _buildPromotorCard(Map<String, dynamic> row) {
    final allType = _metric(row, 'all_type');
    final fokus = _metric(row, 'focus');
    final fokusDetails = List<Map<String, dynamic>>.from(
      fokus['details'] ?? const <Map<String, dynamic>>[],
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: _s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${row['promotor_name'] ?? 'Promotor'}',
            style: _outfit(size: 10, weight: FontWeight.w800, color: _cream),
          ),
          const SizedBox(height: 2),
          Text(
            '${row['store_name'] ?? 'Belum ada toko'}',
            style: _outfit(size: 8, color: _muted),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildMetricMiniCard(
                  label: 'All Type',
                  target: _formatMoney(_toDouble(allType['target'])),
                  actual: _formatMoney(_toDouble(allType['actual'])),
                  achievement: _formatPct(
                    _toDouble(allType['achievement_pct']),
                  ),
                  tone: _green,
                  bg: _greenDim,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: _buildMetricMiniCard(
                  label: 'Fokus',
                  target: _toDouble(fokus['target']).toStringAsFixed(1),
                  actual: '${_toInt(fokus['actual'])}',
                  achievement: _formatPct(_toDouble(fokus['achievement_pct'])),
                  tone: _gold,
                  bg: _goldDim,
                ),
              ),
            ],
          ),
          if (fokusDetails.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Tipe Fokus',
              style: _outfit(size: 8, weight: FontWeight.w800, color: _cream2),
            ),
            const SizedBox(height: 6),
            ...fokusDetails.map(_buildFocusDetailRow),
          ],
        ],
      ),
    );
  }

  Widget _buildFocusDetailRow(Map<String, dynamic> row) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _s3),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${row['bundle_name'] ?? 'Fokus'}',
              style: _outfit(size: 8.5, weight: FontWeight.w700, color: _cream),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_toDouble(row['actual_qty']).toStringAsFixed(0)} / ${_toDouble(row['target_qty']).toStringAsFixed(1)}',
            style: _outfit(size: 8, color: _gold, weight: FontWeight.w800),
          ),
          const SizedBox(width: 8),
          Text(
            _formatPct(_toDouble(row['achievement_pct'])),
            style: _outfit(size: 8, color: _green, weight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState({String? message}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Text(
        message ?? 'Belum ada data achievement untuk periode ini.',
        style: _outfit(size: 10, color: _muted),
      ),
    );
  }
}
