import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../ui/promotor/promotor.dart';

class SpvKpiMonitorPage extends StatefulWidget {
  const SpvKpiMonitorPage({super.key});

  @override
  State<SpvKpiMonitorPage> createState() => _SpvKpiMonitorPageState();
}

class _SpvKpiMonitorPageState extends State<SpvKpiMonitorPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _money = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _isLoading = true;
  String? _errorText;
  Map<String, dynamic>? _kpiData;
  Map<String, dynamic>? _kpiDetail;
  Map<String, dynamic>? _bonusDetail;
  List<Map<String, dynamic>> _kpiComponents = [];
  List<Map<String, dynamic>> _pointRanges = [];
  bool _showPointDetail = false;
  bool _showRewardDetail = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
    });
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      final response = await _supabase.rpc(
        'get_spv_kpi_page_snapshot',
        params: {'p_spv_id': userId},
      );
      final snapshot = response is Map
          ? Map<String, dynamic>.from(response)
          : <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _kpiData = Map<String, dynamic>.from(
          snapshot['kpi_data'] as Map? ?? const {},
        );
        _kpiDetail = Map<String, dynamic>.from(
          snapshot['kpi_detail'] as Map? ?? const {},
        );
        _bonusDetail = Map<String, dynamic>.from(
          snapshot['bonus_detail'] as Map? ?? const {},
        );
        _kpiComponents = _parseMapList(snapshot['kpi_components']);
        _pointRanges = _parseMapList(snapshot['point_ranges']);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorText = e.toString();
      });
    }
  }

  String _formatCompact(num value) {
    if (value % 1 == 0) return value.toInt().toString();
    return value.toStringAsFixed(2);
  }

  Widget _summaryItem(String label, String value, Color tone) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PromotorText.outfit(
            size: 9.5,
            weight: FontWeight.w700,
            color: t.textMutedStrong,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: PromotorText.outfit(
            size: 12,
            weight: FontWeight.w800,
            color: tone,
          ),
        ),
      ],
    );
  }

  Widget _valueRow(
    String label,
    String value, {
    bool compact = false,
    bool muted = false,
    Color? valueColor,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PromotorText.outfit(
                size: compact ? 9.8 : 10.5,
                weight: FontWeight.w700,
                color: muted ? t.textMutedStrong : t.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            style: PromotorText.outfit(
              size: compact ? 9.8 : 10.5,
              weight: FontWeight.w800,
              color: valueColor ?? t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionLink({
    required VoidCallback onPressed,
    required String label,
  }) {
    return InkWell(
      onTap: onPressed,
      child: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          label,
          style: PromotorText.outfit(
            size: 10,
            weight: FontWeight.w800,
            color: t.primaryAccent,
          ),
        ),
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required List<Widget> children,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: PromotorText.outfit(
                    size: 11.5,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              // ignore: use_null_aware_elements
              if (action != null) action,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }

  String _formatMetricValue(String unit, num value) {
    switch (unit) {
      case 'currency':
        return _money.format(value);
      case 'percent':
        return '${value.toStringAsFixed(2)}%';
      default:
        return '${_formatCompact(value)} unit';
    }
  }

  Map<String, dynamic> _resolveKpiMetrics(Map<String, dynamic> component) {
    final code = '${component['metricCode'] ?? ''}';
    switch (code) {
      case 'sell_out_all':
        return {
          'actual': _toNum(_kpiDetail?['actual_sellout']),
          'target': _toNum(_kpiDetail?['target_sellout']),
          'unit': 'currency',
          'note': 'Pencapaian omzet sell out area SPV.',
        };
      case 'sell_out_focus':
        return {
          'actual': _toNum(_kpiDetail?['actual_fokus']),
          'target': _toNum(_kpiDetail?['target_fokus']),
          'unit': 'unit',
          'note': 'Pencapaian unit produk fokus area SPV.',
        };
      case 'sell_in_all':
        return {
          'actual': _toNum(_kpiDetail?['actual_sellin']),
          'target': _toNum(_kpiDetail?['target_sellin']),
          'unit': 'currency',
          'note': 'Total sell in seluruh SATOR di bawah SPV.',
        };
      case 'kpi_ma':
        return {
          'actual': _toNum(_kpiDetail?['kpi_ma']),
          'target': 100,
          'unit': 'percent',
          'note': 'Nilai subjektif dari MA. Bisa aktif walau belum otomatis.',
        };
      case 'low_sellout':
        return {
          'actual': _toNum(_kpiDetail?['low_sellout_pct']),
          'target': 10,
          'unit': 'percent',
          'note':
              'Persentase promotor low sellout: ${_kpiDetail?['low_sellout_count'] ?? 0} dari ${_kpiDetail?['total_promotor'] ?? 0} promotor.',
        };
      default:
        return {
          'actual': 0,
          'target': 0,
          'unit': 'unit',
          'note': 'Belum ada rumus otomatis untuk kategori ini.',
        };
    }
  }

  Future<void> _showKpiCategoryDetail({
    required Map<String, dynamic> component,
    required Map<String, dynamic> metrics,
  }) async {
    final score = _toNum(component['score']);
    final weight = _toNum(component['rawWeight']);
    final actual = _toNum(metrics['actual']);
    final target = _toNum(metrics['target']);
    final unit = '${metrics['unit'] ?? 'unit'}';
    final note = '${metrics['note'] ?? ''}';
    final contribution = score * weight / 100;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            color: t.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.surface3,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${component['name'] ?? '-'}',
                  style: PromotorText.outfit(
                    size: 14,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
                _buildSection(
                  title: 'Ringkasan Hitung',
                  children: [
                    _valueRow('Bobot', '${weight.toStringAsFixed(0)}%'),
                    _valueRow('Score', '${score.toStringAsFixed(2)}%'),
                    _valueRow(
                      'Kontribusi',
                      '${contribution.toStringAsFixed(2)}%',
                      valueColor: t.primaryAccent,
                    ),
                    _valueRow('Actual', _formatMetricValue(unit, actual)),
                    _valueRow('Target/Patokan', _formatMetricValue(unit, target)),
                  ],
                ),
                if (note.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    note,
                    style: PromotorText.outfit(
                      size: 10.5,
                      weight: FontWeight.w700,
                      color: t.textMutedStrong,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildKpiCard() {
    final totalScore = _toNum(_kpiData?['total_score']);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'KPI Bulanan SPV',
                    style: PromotorText.outfit(
                      size: 14,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: t.primaryAccentSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${totalScore.toStringAsFixed(2)}%',
                    style: PromotorText.outfit(
                      size: 12,
                      weight: FontWeight.w800,
                      color: t.primaryAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Tap kategori untuk lihat detail actual, target, dan kontribusi bobot.',
              style: PromotorText.outfit(
                size: 10.5,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
            const SizedBox(height: 14),
            if (_kpiComponents.isEmpty)
              Text(
                'Belum ada pengaturan KPI SPV untuk periode ini.',
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              )
            else
              ..._kpiComponents.map((component) {
                final metrics = _resolveKpiMetrics(component);
                final contribution =
                    _toNum(component['score']) * _toNum(component['rawWeight']) / 100;
                return InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _showKpiCategoryDetail(
                    component: component,
                    metrics: metrics,
                  ),
                  child: Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: t.surface3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                '${component['name'] ?? '-'}',
                                style: PromotorText.outfit(
                                  size: 11,
                                  weight: FontWeight.w800,
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: t.primaryAccent.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: t.primaryAccent.withValues(alpha: 0.24),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    'Kontribusi',
                                    style: PromotorText.outfit(
                                      size: 8.8,
                                      weight: FontWeight.w800,
                                      color: t.primaryAccent,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${contribution.toStringAsFixed(2)}%',
                                    style: PromotorText.outfit(
                                      size: 12,
                                      weight: FontWeight.w900,
                                      color: t.primaryAccent,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bobot ${_toNum(component['rawWeight']).toStringAsFixed(0)}% • Skor ${_toNum(component['score']).toStringAsFixed(2)}%',
                          style: PromotorText.outfit(
                            size: 9.8,
                            weight: FontWeight.w700,
                            color: t.textMutedStrong,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildPointRangesCard() {
    if (_pointRanges.isEmpty) {
      return _buildSection(
        title: 'Point Range',
        children: [
          Text(
            'Belum ada point range SPV.',
            style: PromotorText.outfit(
              size: 10.5,
              weight: FontWeight.w700,
              color: t.textMutedStrong,
            ),
          ),
        ],
      );
    }

    return _buildSection(
      title: 'Point Range',
      children: _pointRanges.map((p) {
        final min = _toNum(p['min_price']);
        final max = _toNum(p['max_price']);
        final points = _toNum(p['points_per_unit']);
        final source = '${p['data_source'] ?? 'sell_out'}' == 'sell_in'
            ? 'Sell In'
            : 'Sell Out';
        final rangeLabel = max > 0
            ? '${_money.format(min)} - ${_money.format(max)}'
            : '> ${_money.format(min)}';
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '$source • $rangeLabel',
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
              Text(
                '${points.toStringAsFixed(0)} poin',
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w800,
                  color: t.primaryAccent,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBonusCard() {
    final bonus = _bonusDetail;
    if (bonus == null) {
      return const SizedBox.shrink();
    }
    final totalEffective =
        (_toNum(bonus['totals']?['total_bonus_effective']) < 0)
        ? 0
        : _toNum(bonus['totals']?['total_bonus_effective']);
    final totalPotential = _toNum(bonus['totals']?['total_bonus_potential']);
    final kpiEligible = bonus['kpi']?['eligible'] == true;
    final pointBreakdown = _parseMapList(bonus['points']?['breakdown']);
    final rewardBreakdown =
        _parseMapList(bonus['special_rewards']?['breakdown']);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ringkasan Bonus SPV',
              style: PromotorText.outfit(
                size: 14,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.primaryAccent.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.primaryAccent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _summaryItem(
                      'Bonus Efektif',
                      _money.format(totalEffective),
                      t.primaryAccent,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _summaryItem(
                      'Potensi',
                      _money.format(totalPotential),
                      t.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildSection(
              title: 'Bonus KPI (Poin)',
              action: _actionLink(
                onPressed: () {
                  setState(() => _showPointDetail = !_showPointDetail);
                },
                label: _showPointDetail ? 'Sembunyikan Detail' : 'Lihat Detail',
              ),
              children: [
                _valueRow(
                  'Status',
                  kpiEligible ? 'Layak Cair' : 'Belum Layak',
                  valueColor: kpiEligible ? t.success : t.warning,
                ),
                _valueRow(
                  'Total Poin',
                  '${_formatCompact(_toNum(bonus['points']?['total_points']))} poin',
                ),
                _valueRow(
                  'Nilai per poin',
                  _money.format(_toNum(bonus['points']?['point_value'])),
                ),
                _valueRow(
                  'Bonus Efektif',
                  _money.format(_toNum(bonus['points']?['effective_kpi_bonus'])),
                  valueColor: t.primaryAccent,
                ),
              ],
            ),
            if (_showPointDetail && pointBreakdown.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...pointBreakdown.map((item) {
                final min = _toNum(item['min_price']);
                final max = _toNum(item['max_price']);
                final units = _toNum(item['units']);
                final points = _toNum(item['points_per_unit']);
                final total = _toNum(item['total_points']);
                final rangeLabel = max > 0
                    ? '${_money.format(min)} - ${_money.format(max)}'
                    : '> ${_money.format(min)}';
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unit ${_formatCompact(units)} × ${points.toStringAsFixed(2)} = ${_formatCompact(total)} poin',
                        style: PromotorText.outfit(
                          size: 10.5,
                          weight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Range harga: $rangeLabel',
                        style: PromotorText.outfit(
                          size: 9.5,
                          weight: FontWeight.w700,
                          color: t.textMutedStrong,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
            const SizedBox(height: 10),
            _buildSection(
              title: 'Reward Tipe Khusus',
              action: _actionLink(
                onPressed: () {
                  setState(() => _showRewardDetail = !_showRewardDetail);
                },
                label:
                    _showRewardDetail ? 'Sembunyikan Detail' : 'Lihat Detail',
              ),
              children: [
                _valueRow(
                  'Total Reward',
                  _money.format(_toNum(bonus['special_rewards']?['reward_total'])),
                ),
                _valueRow(
                  'Total Denda',
                  _money.format(_toNum(bonus['special_rewards']?['penalty_total'])),
                  valueColor: t.danger,
                ),
                _valueRow(
                  'Bonus Efektif Reward',
                  _money.format(
                    _toNum(bonus['special_rewards']?['special_bonus_effective']),
                  ),
                  valueColor: t.primaryAccent,
                ),
              ],
            ),
            if (_showRewardDetail && rewardBreakdown.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...rewardBreakdown.map((item) {
                final eligible = item['eligible'] == true;
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${item['name'] ?? 'Bundle'}',
                              style: PromotorText.outfit(
                                size: 10.5,
                                weight: FontWeight.w800,
                                color: t.textPrimary,
                              ),
                            ),
                          ),
                          Text(
                            eligible ? 'Cair' : 'Belum Cair',
                            style: PromotorText.outfit(
                              size: 9.5,
                              weight: FontWeight.w700,
                              color: eligible ? t.success : t.warning,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _valueRow(
                        'Target',
                        '${_formatCompact(_toNum(item['target_qty']))} unit',
                        compact: true,
                      ),
                      _valueRow(
                        'Actual',
                        '${_formatCompact(_toNum(item['actual_units']))} unit',
                        compact: true,
                      ),
                      _valueRow(
                        'Achievement',
                        '${_toNum(item['achievement_pct']).toStringAsFixed(1)}%',
                        compact: true,
                      ),
                      _valueRow(
                        'Reward',
                        '${_money.format(_toNum(item['reward_amount']))} -> ${_money.format(_toNum(item['reward_effective']))}',
                        compact: true,
                      ),
                      _valueRow(
                        'Denda',
                        '${_money.format(_toNum(item['penalty_amount']))} -> ${_money.format(_toNum(item['penalty_effective']))}',
                        compact: true,
                      ),
                    ],
                  ),
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalScore = _toNum(_kpiData?['total_score']);
    final totalBonus = _toNum(_kpiData?['total_bonus']);

    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(title: const Text('KPI Monitoring SPV')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                children: [
                  if (_errorText != null) ...[
                    Text(
                      _errorText!,
                      style: PromotorText.outfit(
                        size: 10.5,
                        weight: FontWeight.w700,
                        color: t.danger,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: t.surface3),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _summaryItem(
                            'Total KPI',
                            totalScore.toStringAsFixed(2),
                            t.primaryAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _summaryItem(
                            'Estimasi Bonus',
                            _money.format(totalBonus),
                            t.success,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildKpiCard(),
                  const SizedBox(height: 12),
                  _buildBonusCard(),
                  const SizedBox(height: 12),
                  _buildPointRangesCard(),
                ],
              ),
            ),
    );
  }
}
