import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
// ignore_for_file: deprecated_member_use
// ignore_for_file: unused_field, unused_element, unused_local_variable
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class KpiBonusPage extends StatefulWidget {
  const KpiBonusPage({super.key});

  @override
  State<KpiBonusPage> createState() => _KpiBonusPageState();
}

class _KpiBonusPageState extends State<KpiBonusPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _kpiData;
  List<Map<String, dynamic>> _kpiComponents = [];
  Map<String, dynamic>? _kpiDetail;
  List<Map<String, dynamic>> _pointRanges = [];
  List<Map<String, dynamic>> _specialRewards = [];
  List<Map<String, dynamic>> _rewards = [];
  Map<String, dynamic>? _bonusDetail;
  bool _isLoading = true;
  String? _loadError;
  final bool _showKpiDetail = false;
  bool _showPointDetail = false;
  bool _showRewardDetail = false;
  bool _showPointRanges = false;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final kpi = await _supabase.rpc(
        'get_sator_kpi_summary',
        params: {'p_sator_id': userId},
      );
      final kpiDetail = await _loadKpiDetail(userId);
      final kpiSettingsRaw = await _supabase
          .from('kpi_settings')
          .select('kpi_name, weight')
          .eq('role', 'sator')
          .order('weight', ascending: false);
      final kpiSettings = List<Map<String, dynamic>>.from(kpiSettingsRaw);
      final totalWeight = kpiSettings.fold<int>(
        0,
        (sum, row) => sum + (row['weight'] as int? ?? 0),
      );
      final resolvedComponents = <Map<String, dynamic>>[];
      if (kpiSettings.isNotEmpty && totalWeight > 0) {
        for (final setting in kpiSettings) {
          final name = '${setting['kpi_name'] ?? '-'}';
          final rawWeight = (setting['weight'] as int? ?? 0);
          final normalizedWeight = (rawWeight * 100 / totalWeight);
          double score = 0;
          final lower = name.toLowerCase();
          if (lower.contains('sell out all')) {
            score = (kpi?['sell_out_all_score'] ?? 0).toDouble();
          }
          if (lower.contains('sell out fokus')) {
            score = (kpi?['sell_out_fokus_score'] ?? 0).toDouble();
          }
          if (lower.contains('sell in')) {
            score = (kpi?['sell_in_score'] ?? 0).toDouble();
          }
          if (lower.contains('kpi ma')) {
            score = (kpi?['kpi_ma_score'] ?? 0).toDouble();
          }
          resolvedComponents.add({
            'name': name,
            'rawWeight': rawWeight,
            'weight': normalizedWeight,
            'score': score,
          });
        }
      }
      final pointRangesRaw = await _supabase
          .from('point_ranges')
          .select('min_price, max_price, points_per_unit, data_source')
          .eq('role', 'sator')
          .order('data_source')
          .order('min_price');

      final specialRewards = await _supabase.rpc(
        'get_special_rewards_by_role',
        params: {'p_role': 'sator'},
      );

      final rewards = await _supabase.rpc(
        'get_sator_rewards',
        params: {'p_sator_id': userId},
      );
      final bonusDetail = await _supabase
          .rpc('get_sator_bonus_detail', params: {'p_sator_id': userId});
      if (mounted) {
        setState(() {
          _loadError = null;
          _kpiData = kpi is Map<String, dynamic>
              ? Map<String, dynamic>.from(kpi)
              : {};
          _kpiComponents = resolvedComponents;
          _kpiDetail = kpiDetail ??
              {
                'target_sellout': 0,
                'target_fokus': 0,
                'target_sellin': 0,
                'actual_sellout': 0,
                'actual_fokus': 0,
                'actual_sellin': 0,
                'kpi_ma': 0,
              };
          _pointRanges = List<Map<String, dynamic>>.from(pointRangesRaw);
          _specialRewards =
              List<Map<String, dynamic>>.from(specialRewards ?? []);
          _rewards = List<Map<String, dynamic>>.from(rewards ?? []);
          _bonusDetail = bonusDetail is Map<String, dynamic>
              ? Map<String, dynamic>.from(bonusDetail)
              : null;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadError = e.toString();
        });
      }
    }
  }

  Future<Map<String, dynamic>?> _loadKpiDetail(String satorId) async {
    try {
      final periodId = await _supabase.rpc('get_current_target_period');
      String? resolvedPeriodId = periodId?.toString();
      if (resolvedPeriodId == null || resolvedPeriodId.isEmpty) {
        final now = DateTime.now();
        final periodRows = await _supabase
            .from('target_periods')
            .select('id')
            .eq('target_month', now.month)
            .eq('target_year', now.year)
            .isFilter('deleted_at', null)
            .order('start_date', ascending: false)
            .limit(1);
        final periodRowList = List<Map<String, dynamic>>.from(periodRows);
        final periodRow = periodRowList.isNotEmpty ? periodRowList.first : null;
        resolvedPeriodId = periodRow?['id']?.toString();
      }
      if (resolvedPeriodId == null || resolvedPeriodId.isEmpty) {
        return {
          'target_sellout': 0,
          'target_fokus': 0,
          'target_sellin': 0,
          'actual_sellout': 0,
          'actual_fokus': 0,
          'actual_sellin': 0,
          'kpi_ma': 0,
        };
      }

      final periodRows = await _supabase
          .from('target_periods')
          .select('start_date, end_date')
          .eq('id', resolvedPeriodId)
          .limit(1);
      final periodRowList = List<Map<String, dynamic>>.from(periodRows);
      final periodRow = periodRowList.isNotEmpty ? periodRowList.first : null;
      final startDate = periodRow?['start_date']?.toString();
      final endDate = periodRow?['end_date']?.toString();

      final targetRows = await _supabase
          .from('user_targets')
          .select('target_sell_out, target_fokus, target_sell_in')
          .eq('user_id', satorId)
          .eq('period_id', resolvedPeriodId)
          .order('updated_at', ascending: false)
          .limit(1);
      final targetRowList = List<Map<String, dynamic>>.from(targetRows);
      final targetRow = targetRowList.isNotEmpty ? targetRowList.first : null;

      final promotorLinks = await _supabase
          .from('hierarchy_sator_promotor')
          .select('promotor_id')
          .eq('sator_id', satorId)
          .eq('active', true);
      final promotorIds = (promotorLinks as List)
          .map((row) => row['promotor_id']?.toString() ?? '')
          .where((id) => id.isNotEmpty)
          .toList();

      num actualSellout = 0;
      int actualFokus = 0;
      if (promotorIds.isNotEmpty) {
          final metricsRows = await _supabase
              .from('dashboard_performance_metrics')
              .select('total_omzet_real, total_units_focus')
              .inFilter('user_id', promotorIds)
              .eq('period_id', resolvedPeriodId);
        for (final row in List<Map<String, dynamic>>.from(metricsRows)) {
          actualSellout += (row['total_omzet_real'] as num?) ?? 0;
          actualFokus += (row['total_units_focus'] as num?)?.toInt() ?? 0;
        }
      }

      num actualSellin = 0;
      if (startDate != null && endDate != null) {
        final sellinRows = await _supabase
            .from('sales_sell_in')
            .select('total_value')
            .eq('sator_id', satorId)
            .gte('transaction_date', startDate)
            .lte('transaction_date', endDate)
            .isFilter('deleted_at', null);
        for (final row in List<Map<String, dynamic>>.from(sellinRows)) {
          actualSellin += (row['total_value'] as num?) ?? 0;
        }
      }

      num kpiMa = 0;
      if (startDate != null) {
        final kpiMaRow = await _supabase
            .from('kpi_ma_scores')
            .select('score')
            .eq('sator_id', satorId)
            .eq('period_date', startDate)
            .maybeSingle();
        kpiMa = (kpiMaRow?['score'] as num?) ?? 0;
      }

      return {
        'target_sellout': (targetRow?['target_sell_out'] as num?) ?? 0,
        'target_fokus': (targetRow?['target_fokus'] as num?) ?? 0,
        'target_sellin': (targetRow?['target_sell_in'] as num?) ?? 0,
        'actual_sellout': actualSellout,
        'actual_fokus': actualFokus,
        'actual_sellin': actualSellin,
        'kpi_ma': kpiMa,
      };
    } catch (_) {
      return {
        'target_sellout': 0,
        'target_fokus': 0,
        'target_sellin': 0,
        'actual_sellout': 0,
        'actual_fokus': 0,
        'actual_sellin': 0,
        'kpi_ma': 0,
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('KPI & Bonus'),
        backgroundColor: Color.lerp(t.info, t.primaryAccentLight, 0.55)!,
        foregroundColor: t.textOnAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  if (_loadError != null) ...[
                    _buildLoadErrorCard(_loadError!),
                    const SizedBox(height: 16),
                  ],
                  _buildKpiCard(),
                  const SizedBox(height: 16),
                  _buildRewardsCard(),
                  const SizedBox(height: 16),
                  _buildBonusPoinCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildKpiCard() {
    final components = _kpiComponents;
    final totalScore = (_kpiData?['total_score'] ?? 0).toDouble();
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'KPI Bulanan',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypeScale.bodyStrong),
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
                    '${_formatNumber(totalScore)}%',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: t.primaryAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (components.isEmpty)
              const Text('Belum ada pengaturan KPI di admin.')
            else
              ...components.map(
                (c) {
                  final name = c['name']?.toString() ?? '-';
                  final lower = name.toLowerCase();
                  num actual = 0;
                  num target = 0;
                  String unitLabel = '';
                  if (lower.contains('sell out all')) {
                    actual = (_kpiDetail?['actual_sellout'] as num?) ?? 0;
                    target = (_kpiDetail?['target_sellout'] as num?) ?? 0;
                    unitLabel = 'Rp';
                  } else if (lower.contains('sell out fokus')) {
                    actual = (_kpiDetail?['actual_fokus'] as num?) ?? 0;
                    target = (_kpiDetail?['target_fokus'] as num?) ?? 0;
                    unitLabel = 'unit';
                  } else if (lower.contains('sell in')) {
                    actual = (_kpiDetail?['actual_sellin'] as num?) ?? 0;
                    target = (_kpiDetail?['target_sellin'] as num?) ?? 0;
                    unitLabel = 'Rp';
                  } else if (lower.contains('kpi ma')) {
                    actual = (_kpiDetail?['kpi_ma'] as num?) ?? 0;
                    target = 100;
                    unitLabel = '%';
                  }
                  final achievement = target > 0 ? (actual * 100 / target) : 0;
                  final weight = (c['rawWeight'] as num?) ?? (c['weight'] as num?) ?? 0;
                  final score = achievement * weight / 100;
                  String formatValue(num value) {
                    if (unitLabel == 'Rp') return formatter.format(value);
                    if (unitLabel == 'unit') return '${value.toInt()} unit';
                    if (unitLabel == '%') return '${value.toStringAsFixed(0)}%';
                    return value.toString();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '$name (Bobot ${weight.toStringAsFixed(0)}%)',
                                style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppTypeScale.body),
                              ),
                            ),
                            Text(
                              '${_formatNumber(achievement)}%',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppTypeScale.body),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Nilai bobot',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${_formatNumber(score)}%',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pencapaian: ${formatValue(actual)} / ${formatValue(target)} × 100',
                          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Hitung skor: ${_formatNumber(achievement)} × ${weight.toStringAsFixed(0)} ÷ 100 = ${_formatNumber(score)}',
                          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                        ),
                      ],
                    ),
                  );
                },
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total KPI',
                  style: TextStyle(fontSize: AppTypeScale.body, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${_formatNumber(totalScore)}%',
                  style: TextStyle(fontSize: AppTypeScale.bodyStrong, fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Total KPI = jumlah nilai bobot',
              style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
            ),
            const SizedBox(height: 6),
            _buildKpiBonusEligibilityNote(totalScore),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadErrorCard(String error) {
    return Card(
      color: t.warning.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Gagal Memuat Bonus Detail',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypeScale.body),
            ),
            const SizedBox(height: 6),
            SelectableText(
              error,
              style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: error));
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Error disalin')),
                    );
                  }
                },
                child: const Text('Copy Error'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiCalculationDetail() {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    if (_kpiDetail == null || _kpiComponents.isEmpty) {
      return const Text('Detail perhitungan belum tersedia.');
    }

    String formatValue(String key, dynamic value) {
      if (key == 'sell_out_all' || key == 'sell_in_all') {
        return formatter.format((value as num?) ?? 0);
      }
      if (key == 'sell_out_fokus') {
        return '${(value as num?)?.toInt() ?? 0} unit';
      }
      if (key == 'kpi_ma') {
        return '${(value as num?)?.toString() ?? '0'}%';
      }
      return '${value ?? 0}';
    }

    Map<String, dynamic> mapDetail(String name) {
      final lower = name.toLowerCase();
      if (lower.contains('sell out all')) {
        return {
          'key': 'sell_out_all',
          'actual': _kpiDetail?['actual_sellout'] ?? 0,
          'target': _kpiDetail?['target_sellout'] ?? 0,
        };
      }
      if (lower.contains('sell out fokus')) {
        return {
          'key': 'sell_out_fokus',
          'actual': _kpiDetail?['actual_fokus'] ?? 0,
          'target': _kpiDetail?['target_fokus'] ?? 0,
        };
      }
      if (lower.contains('sell in')) {
        return {
          'key': 'sell_in_all',
          'actual': _kpiDetail?['actual_sellin'] ?? 0,
          'target': _kpiDetail?['target_sellin'] ?? 0,
        };
      }
      if (lower.contains('kpi ma')) {
        return {
          'key': 'kpi_ma',
          'actual': _kpiDetail?['kpi_ma'] ?? 0,
          'target': 100,
        };
      }
      return {'key': 'other', 'actual': 0, 'target': 0};
    }

    double achievementPct(num actual, num target) {
      if (target <= 0) return 0;
      return (actual / target) * 100;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detail Perhitungan (berdasarkan target admin)',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._kpiComponents.map((c) {
          final detail = mapDetail(c['name']?.toString() ?? '');
          final actual = (detail['actual'] as num?) ?? 0;
          final target = (detail['target'] as num?) ?? 0;
          final achieve = achievementPct(actual, target);
          final weight = (c['rawWeight'] as num?) ?? (c['weight'] as num?) ?? 0;
          final weightedScore = (achieve * weight / 100);
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${c['name']} • Bobot ${weight.toStringAsFixed(0)}%',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Actual ${formatValue(detail['key'], actual)} / Target ${formatValue(detail['key'], target)}',
                  style: TextStyle(fontSize: AppTypeScale.support),
                ),
                Text(
                  'Achievement ${achieve.toStringAsFixed(2)}% → Skor ${weightedScore.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: AppTypeScale.support,
                    color: t.textSecondary,
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildKpiDetailRow(String label, String actual, String target) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label)),
          Text('$actual / $target'),
        ],
      ),
    );
  }

  Widget _buildKpiReason({
    required dynamic actual,
    required dynamic target,
    required String emptyTargetNote,
    required String emptyActualNote,
  }) {
    final actualVal = (actual as num?) ?? 0;
    final targetVal = (target as num?) ?? 0;
    if (targetVal <= 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          emptyTargetNote,
          style: TextStyle(fontSize: AppTypeScale.body, color: t.warning),
        ),
      );
    }
    if (actualVal <= 0) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          emptyActualNote,
          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
        ),
      );
    }
    return const SizedBox(height: 2);
  }

  Widget _buildKpiFormulaNote() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cara hitung KPI:',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 6),
        Text(
          '1. Achievement per kategori = (Actual / Target) × 100%.',
          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
        ),
        Text(
          '2. Skor kategori = Achievement × Bobot / 100.',
          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
        ),
        Text(
          '3. Total KPI = penjumlahan semua skor kategori (maksimal 100%).',
          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
        ),
        SizedBox(height: 6),
        Text(
          'Jika Total KPI < 80%, bonus KPI dari poin Sell Out tidak dicairkan. Jika ≥ 80%, bonus KPI dihitung dari total poin Sell Out berdasarkan tabel harga → poin yang diatur admin.',
          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
        ),
      ],
    );
  }

  Widget _buildKpiBonusEligibilityNote(double totalScore) {
    final isEligible = totalScore >= 80;
    final color = isEligible ? t.success : t.warning;
    final bgColor = isEligible
        ? t.successSoft
        : t.warning.withValues(alpha: 0.08);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isEligible ? Icons.check_circle : Icons.info,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isEligible
                      ? 'Status Bonus KPI: Layak Cair'
                      : 'Status Bonus KPI: Belum capai target (min 80%)',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: AppTypeScale.support,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBonusPoinCard() {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Tabel Bonus Poin',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypeScale.bodyStrong),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () {
                  setState(() => _showPointRanges = !_showPointRanges);
                },
                child: Text(_showPointRanges ? 'Sembunyikan Tabel' : 'Lihat Tabel'),
              ),
            ),
            if (_showPointRanges)
              if (_pointRanges.isEmpty)
                const Text('Belum ada pengaturan poin di admin.')
              else
                ..._pointRanges.map(
                  (p) {
                    final min = (p['min_price'] as num?) ?? 0;
                    final max = (p['max_price'] as num?) ?? 0;
                    final points = (p['points_per_unit'] as num?) ?? 0;
                    final source = (p['data_source'] ?? 'sell_out').toString();
                    final rangeLabel = max > 0
                        ? '${formatter.format(min)} - ${formatter.format(max)}'
                        : '> ${formatter.format(min)}';
                    final sourceLabel = source == 'sell_in'
                        ? 'Sell In'
                        : 'Sell Out';
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text('$sourceLabel • $rangeLabel'),
                          ),
                          Text(
                            '${points.toStringAsFixed(0)} Poin',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewardsCard() {
    final bonus = _bonusDetail;
    final bonusFormatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final rawEffectiveBonus = bonus?['totals']?['total_bonus_effective'] ?? 0;
    final effectiveBonus = rawEffectiveBonus < 0 ? 0 : rawEffectiveBonus;
    final potentialBonus = bonus?['totals']?['total_bonus_potential'] ?? 0;
    final kpiEligible = bonus?['kpi']?['eligible'] == true;
    final totalPoints = bonus?['points']?['total_points'] ?? 0;
    final pointValue = bonus?['points']?['point_value'] ?? 1000;
    final kpiBonusEffective = bonus?['points']?['effective_kpi_bonus'] ?? 0;
    final kpiBonusPotential = bonus?['points']?['potential_kpi_bonus'] ?? 0;
    final pointBreakdown = List<Map<String, dynamic>>.from(
      bonus?['points']?['breakdown'] ?? [],
    );
    final rawSpecialBonus =
        bonus?['special_rewards']?['special_bonus_effective'] ?? 0;
    final specialBonus = rawSpecialBonus < 0 ? 0 : rawSpecialBonus;
    final specialRewardTotal = bonus?['special_rewards']?['reward_total'] ?? 0;
    final specialPenaltyTotal = bonus?['special_rewards']?['penalty_total'] ?? 0;
    final rewardBreakdown = List<Map<String, dynamic>>.from(
      bonus?['special_rewards']?['breakdown'] ?? [],
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ringkasan Bonus',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypeScale.bodyStrong),
            ),
            const SizedBox(height: 12),
            if (bonus != null) ...[
              Text(
                'Bonus KPI (Poin Sell Out)',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    kpiEligible ? 'Status: Layak Cair' : 'Status: Belum Layak',
                    style: TextStyle(
                      fontSize: AppTypeScale.support,
                      color: kpiEligible ? t.success : t.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '${_formatPoints(totalPoints)} poin',
                    style: TextStyle(fontSize: AppTypeScale.support),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Nilai per poin',
                    style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                  ),
                  Text(
                    bonusFormatter.format(pointValue),
                    style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Bonus KPI efektif', style: TextStyle(fontSize: AppTypeScale.support)),
                  Text(
                    bonusFormatter.format(kpiBonusEffective),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypeScale.support),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    kpiEligible ? 'Potensi KPI (jika performa naik)' : 'Potensi KPI (belum cair)',
                    style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                  ),
                  Text(
                    bonusFormatter.format(kpiBonusPotential),
                    style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    setState(() => _showPointDetail = !_showPointDetail);
                  },
                  child: Text(_showPointDetail ? 'Sembunyikan Detail' : 'Lihat Detail'),
                ),
              ),
              if (_showPointDetail && pointBreakdown.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  'Detail Poin Sell Out',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypeScale.support),
                ),
                const SizedBox(height: 8),
                ...pointBreakdown.map((b) {
                  final min = (b['min_price'] as num?) ?? 0;
                  final max = (b['max_price'] as num?) ?? 0;
                  final points = (b['points_per_unit'] as num?) ?? 0;
                  final units = (b['units'] as num?) ?? 0;
                  final totalPoints = (b['total_points'] as num?) ?? 0;
                  final rangeLabel = max > 0
                      ? '${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(min)} - ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(max)}'
                      : '> ${NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0).format(min)}';
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unit ${_formatPoints(units)} × ${points.toStringAsFixed(2)} poin = ${_formatPoints(totalPoints)} poin',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: AppTypeScale.support),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Range harga: $rangeLabel',
                          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 10),
              const Divider(height: 24),
              const Text(
                'Bonus Reward Tipe Khusus',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total reward', style: TextStyle(fontSize: AppTypeScale.support)),
                  Text(
                    bonusFormatter.format(specialRewardTotal),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypeScale.support),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Total denda', style: TextStyle(fontSize: AppTypeScale.support)),
                  Text(
                    bonusFormatter.format(specialPenaltyTotal),
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypeScale.support),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  onPressed: () {
                    setState(() => _showRewardDetail = !_showRewardDetail);
                  },
                  child: Text(_showRewardDetail ? 'Sembunyikan Detail' : 'Lihat Detail'),
                ),
              ),
              if (_showRewardDetail && rewardBreakdown.isNotEmpty) ...[
                const SizedBox(height: 4),
                const Text(
                  'Detail Reward Tipe Khusus',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: AppTypeScale.support),
                ),
                const SizedBox(height: 6),
                ...rewardBreakdown.map((r) {
                  final name = (r['name'] ?? 'Bundle').toString();
                  final minUnit = (r['min_unit'] as num?)?.toInt() ?? 0;
                  final maxUnit = (r['max_unit'] as num?)?.toInt() ?? 0;
                  final actualUnits = (r['actual_units'] as num?)?.toDouble() ?? 0;
                  final rewardAmount = (r['reward_amount'] as num?) ?? 0;
                  final penaltyAmount = (r['penalty_amount'] as num?) ?? 0;
                  final rewardEffective = (r['reward_effective'] as num?) ?? 0;
                  final penaltyEffective = (r['penalty_effective'] as num?) ?? 0;
                  final netBonus = (r['net_bonus'] as num?) ?? 0;
                  final netDisplay = netBonus < 0 ? 0 : netBonus;
                  final dataSource = (r['data_source'] ?? 'sell_out').toString();
                  final unitRange = maxUnit > 0
                      ? '$minUnit - $maxUnit unit'
                      : '>= $minUnit unit';
                  final sourceLabel =
                      dataSource == 'sell_in' ? 'Sell In' : 'Sell Out';

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Expanded(
                              child: Text(
                                '$name • $sourceLabel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: AppTypeScale.support,
                                ),
                              ),
                            ),
                            Text(
                              unitRange,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: AppTypeScale.support,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Pencapaian ${_formatPoints(actualUnits)} unit',
                          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Reward ${bonusFormatter.format(rewardAmount)} → ${bonusFormatter.format(rewardEffective)}',
                          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                        ),
                        Text(
                          'Denda ${bonusFormatter.format(penaltyAmount)} → ${bonusFormatter.format(penaltyEffective)}',
                          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                        ),
                        Text(
                          'Hasil ${bonusFormatter.format(netDisplay)}',
                          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              const SizedBox(height: 10),
              const Divider(height: 24),
              Text(
                'Total bonus efektif',
                style: TextStyle(fontSize: AppTypeScale.support),
              ),
              const SizedBox(height: 2),
              Text(
                bonusFormatter.format(effectiveBonus),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: AppTypeScale.body),
              ),
              const SizedBox(height: 2),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _formatPoints(dynamic value) {
    final num points = (value as num?) ?? 0;
    if (points % 1 == 0) return points.toStringAsFixed(0);
    return points.toStringAsFixed(1);
  }

  String _formatNumber(num value, {int digits = 2}) {
    return value.toStringAsFixed(digits).replaceAll('.', ',');
  }
}
