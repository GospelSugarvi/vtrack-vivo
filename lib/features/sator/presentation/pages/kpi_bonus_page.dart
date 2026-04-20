import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
// ignore_for_file: deprecated_member_use
// ignore_for_file: unused_field, unused_element, unused_local_variable
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../../ui/promotor/promotor.dart';

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
      final snapshotRaw = await _supabase.rpc(
        'get_sator_kpi_page_snapshot',
        params: {'p_sator_id': userId},
      );
      final snapshot = snapshotRaw is Map
          ? Map<String, dynamic>.from(snapshotRaw)
          : <String, dynamic>{};
      if (mounted) {
        setState(() {
          _loadError = null;
          _kpiData = Map<String, dynamic>.from(
            snapshot['kpi_data'] as Map? ?? const {},
          );
          _kpiComponents = _parseMapList(snapshot['kpi_components']);
          _kpiDetail = Map<String, dynamic>.from(
            snapshot['kpi_detail'] as Map? ?? const {},
          );
          _pointRanges = _parseMapList(snapshot['point_ranges']);
          _specialRewards = _parseMapList(snapshot['special_rewards']);
          _rewards = _parseMapList(snapshot['rewards']);
          _bonusDetail = Map<String, dynamic>.from(
            snapshot['bonus_detail'] as Map? ?? const {},
          );
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('KPI & Bonus'),
        backgroundColor: t.primaryAccent,
        foregroundColor: t.textOnAccent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
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

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Widget _buildKpiCard() {
    final components = _kpiComponents;
    final totalScore = (_kpiData?['total_score'] ?? 0).toDouble();
    final currencyFormatter = NumberFormat.currency(
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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'KPI Bulanan',
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
                    '${_formatNumber(totalScore)}%',
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
              'Pilih kategori untuk lihat detail hitungan.',
              style: PromotorText.outfit(
                size: 10.5,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
            const SizedBox(height: 16),
            if (components.isEmpty)
              const Text('Belum ada pengaturan KPI di admin.')
            else
              ...components.map((component) {
                final metrics = _resolveKpiMetrics(
                  component,
                  currencyFormatter,
                );
                return _buildKpiCategoryTile(
                  component: component,
                  metrics: metrics,
                  onTap: () => _showKpiCategoryDetail(
                    component: component,
                    metrics: metrics,
                  ),
                );
              }),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total KPI',
                  style: TextStyle(
                    fontSize: AppTypeScale.body,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${_formatNumber(totalScore)}%',
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              'Total KPI = jumlah nilai bobot',
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
            const SizedBox(height: 6),
            _buildKpiBonusEligibilityNote(totalScore),
          ],
        ),
      ),
    );
  }

  Map<String, dynamic> _resolveKpiMetrics(
    Map<String, dynamic> component,
    NumberFormat currencyFormatter,
  ) {
    final code = component['metricCode']?.toString() ?? '';
    num actual = 0;
    num target = 0;
    String unit = '';
    String note = '';

    switch (code) {
      case 'sell_out_all':
        actual = (_kpiDetail?['actual_sellout'] as num?) ?? 0;
        target = (_kpiDetail?['target_sellout'] as num?) ?? 0;
        unit = 'currency';
        note = 'Pencapaian omzet sell out area SATOR.';
        break;
      case 'sell_out_focus':
        actual = (_kpiDetail?['actual_fokus'] as num?) ?? 0;
        target = (_kpiDetail?['target_fokus'] as num?) ?? 0;
        unit = 'unit';
        note = 'Pencapaian unit produk fokus area SATOR.';
        break;
      case 'sell_in_all':
        actual = (_kpiDetail?['actual_sellin'] as num?) ?? 0;
        target = (_kpiDetail?['target_sellin'] as num?) ?? 0;
        unit = 'currency';
        note = 'Total sell in SATOR pada periode berjalan.';
        break;
      case 'kpi_ma':
        actual = (_kpiDetail?['kpi_ma'] as num?) ?? 0;
        target = 100;
        unit = 'percent';
        note = 'Nilai subjektif dari MA. Bisa aktif walau belum otomatis.';
        break;
      case 'low_sellout':
        actual = (_kpiDetail?['low_sellout_pct'] as num?) ?? 0;
        target = 10;
        unit = 'percent';
        note =
            'Persentase promotor low sellout: ${_kpiDetail?['low_sellout_count'] ?? 0} dari ${_kpiDetail?['total_promotor'] ?? 0} promotor.';
        break;
    }

    final weight =
        (component['rawWeight'] as num?) ?? (component['weight'] as num?) ?? 0;
    final rawScore = (component['score'] as num?) ?? 0;
    final achievement = code == 'low_sellout'
        ? rawScore
        : target > 0
        ? (actual * 100 / target)
        : 0.0;
    final contribution = rawScore * weight / 100;

    String formatValue(num value) {
      if (unit == 'currency') return currencyFormatter.format(value);
      if (unit == 'unit') return '${value.toInt()} unit';
      if (unit == 'percent') return '${value.toStringAsFixed(1)}%';
      return value.toString();
    }

    return {
      'actual': actual,
      'target': target,
      'weight': weight,
      'achievement': achievement,
      'score': rawScore,
      'contribution': contribution,
      'note': note,
      'actualLabel': formatValue(actual),
      'targetLabel': formatValue(target),
    };
  }

  Widget _buildKpiCategoryTile({
    required Map<String, dynamic> component,
    required Map<String, dynamic> metrics,
    required VoidCallback onTap,
  }) {
    final name = component['name']?.toString() ?? '-';
    final achievement = (metrics['achievement'] as num?) ?? 0;
    final score = (metrics['score'] as num?) ?? 0;
    final contribution = (metrics['contribution'] as num?) ?? 0;
    final weight = (metrics['weight'] as num?) ?? 0;
    final tone = achievement >= 100
        ? t.success
        : achievement >= 80
        ? t.warning
        : t.danger;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.surface3),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: PromotorText.outfit(
                        size: 11,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Bobot ${weight.toStringAsFixed(0)}% • Skor ${_formatNumber(score)}%',
                      style: PromotorText.outfit(
                        size: 9.5,
                        weight: FontWeight.w700,
                        color: t.textMutedStrong,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
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
                          '${_formatNumber(contribution)}%',
                          style: PromotorText.outfit(
                            size: 12,
                            weight: FontWeight.w900,
                            color: t.primaryAccent,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: tone.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '${_formatNumber(achievement)}%',
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w800,
                        color: tone,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 18, color: t.textMuted),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showKpiCategoryDetail({
    required Map<String, dynamic> component,
    required Map<String, dynamic> metrics,
  }) async {
    final name = component['name']?.toString() ?? '-';
    final weight = (metrics['weight'] as num?) ?? 0;
    final achievement = (metrics['achievement'] as num?) ?? 0;
    final score = (metrics['score'] as num?) ?? 0;
    final contribution = (metrics['contribution'] as num?) ?? 0;
    final actualLabel = metrics['actualLabel']?.toString() ?? '0';
    final targetLabel = metrics['targetLabel']?.toString() ?? '0';
    final note = metrics['note']?.toString() ?? '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: t.surface3,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  name,
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bobot ${weight.toStringAsFixed(0)}%',
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: t.textMutedStrong,
                  ),
                ),
                const SizedBox(height: 14),
                _detailLine('Pencapaian', '$actualLabel / $targetLabel'),
                _detailLine(
                  'Rumus Achievement',
                  '($actualLabel ÷ $targetLabel) × 100 = ${_formatNumber(achievement)}%',
                ),
                _detailLine(
                  'Rumus Nilai Bobot',
                  '${_formatNumber(score)} × ${weight.toStringAsFixed(0)} ÷ 100 = ${_formatNumber(contribution)}%',
                ),
                if (note.isNotEmpty) _detailLine('Catatan', note),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
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
          const SizedBox(height: 2),
          Text(
            value,
            style: PromotorText.outfit(
              size: 10.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ],
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
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: AppTypeScale.body,
              ),
            ),
            const SizedBox(height: 6),
            SelectableText(
              error,
              style: TextStyle(
                fontSize: AppTypeScale.body,
                color: t.textSecondary,
              ),
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
        Text('Cara hitung KPI:', style: TextStyle(fontWeight: FontWeight.bold)),
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
            Text(
              'Tabel Bonus Poin',
              style: PromotorText.outfit(
                size: 14,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Rentang harga dan poin per unit.',
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: _actionLink(
                onPressed: () {
                  setState(() => _showPointRanges = !_showPointRanges);
                },
                label: _showPointRanges ? 'Sembunyikan Tabel' : 'Lihat Tabel',
              ),
            ),
            if (_showPointRanges)
              if (_pointRanges.isEmpty)
                Text(
                  'Belum ada pengaturan poin di admin.',
                  style: PromotorText.outfit(
                    size: 10.5,
                    weight: FontWeight.w700,
                    color: t.textMutedStrong,
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    children: _pointRanges.map((p) {
                      final min = (p['min_price'] as num?) ?? 0;
                      final max = (p['max_price'] as num?) ?? 0;
                      final points = (p['points_per_unit'] as num?) ?? 0;
                      final source = (p['data_source'] ?? 'sell_out')
                          .toString();
                      final rangeLabel = max > 0
                          ? '${formatter.format(min)} - ${formatter.format(max)}'
                          : '> ${formatter.format(min)}';
                      final sourceLabel = source == 'sell_in'
                          ? 'Sell In'
                          : 'Sell Out';
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '$sourceLabel • $rangeLabel',
                                style: PromotorText.outfit(
                                  size: 9.8,
                                  weight: FontWeight.w700,
                                  color: t.textPrimary,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
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
                  ),
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
    final specialPenaltyTotal =
        bonus?['special_rewards']?['penalty_total'] ?? 0;
    final rewardBreakdown = List<Map<String, dynamic>>.from(
      bonus?['special_rewards']?['breakdown'] ?? [],
    );

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: bonus == null
            ? Text(
                'Data bonus belum tersedia.',
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ringkasan Bonus',
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
                      border: Border.all(
                        color: t.primaryAccent.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _summaryItem(
                            'Total Bonus Efektif',
                            bonusFormatter.format(effectiveBonus),
                            t.primaryAccent,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _summaryItem(
                            'Total Potensi',
                            bonusFormatter.format(potentialBonus),
                            t.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildBonusSection(
                    title: 'Bonus KPI (Poin Sell Out)',
                    children: [
                      _valueRow(
                        'Status',
                        kpiEligible ? 'Layak Cair' : 'Belum Layak',
                        valueColor: kpiEligible ? t.success : t.warning,
                      ),
                      _valueRow(
                        'Total Poin',
                        '${_formatPoints(totalPoints)} poin',
                      ),
                      _valueRow(
                        'Nilai per poin',
                        bonusFormatter.format(pointValue),
                      ),
                      _valueRow(
                        'Bonus KPI Efektif',
                        bonusFormatter.format(kpiBonusEffective),
                        valueColor: t.primaryAccent,
                      ),
                      _valueRow(
                        'Potensi KPI',
                        bonusFormatter.format(kpiBonusPotential),
                        muted: true,
                      ),
                    ],
                    action: _actionLink(
                      onPressed: () {
                        setState(() => _showPointDetail = !_showPointDetail);
                      },
                      label: _showPointDetail
                          ? 'Sembunyikan Detail'
                          : 'Lihat Detail',
                    ),
                  ),
                  if (_showPointDetail && pointBreakdown.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...pointBreakdown.map((item) {
                      final min = (item['min_price'] as num?) ?? 0;
                      final max = (item['max_price'] as num?) ?? 0;
                      final points = (item['points_per_unit'] as num?) ?? 0;
                      final units = (item['units'] as num?) ?? 0;
                      final total = (item['total_points'] as num?) ?? 0;
                      final rangeLabel = max > 0
                          ? '${bonusFormatter.format(min)} - ${bonusFormatter.format(max)}'
                          : '> ${bonusFormatter.format(min)}';
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
                              'Unit ${_formatPoints(units)} × ${points.toStringAsFixed(2)} = ${_formatPoints(total)} poin',
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
                  _buildBonusSection(
                    title: 'Bonus Reward Tipe Khusus',
                    children: [
                      _valueRow(
                        'Total Reward',
                        bonusFormatter.format(specialRewardTotal),
                      ),
                      _valueRow(
                        'Total Denda',
                        bonusFormatter.format(specialPenaltyTotal),
                        valueColor: t.danger,
                      ),
                      _valueRow(
                        'Bonus Efektif Reward',
                        bonusFormatter.format(specialBonus),
                        valueColor: t.primaryAccent,
                      ),
                    ],
                    action: _actionLink(
                      onPressed: () {
                        setState(() => _showRewardDetail = !_showRewardDetail);
                      },
                      label: _showRewardDetail
                          ? 'Sembunyikan Detail'
                          : 'Lihat Detail',
                    ),
                  ),
                  if (_showRewardDetail && rewardBreakdown.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    ...rewardBreakdown.map((item) {
                      final name = (item['name'] ?? 'Bundle').toString();
                      final targetQty =
                          (item['target_qty'] as num?)?.toDouble() ?? 0;
                      final actualUnits =
                          (item['actual_units'] as num?)?.toDouble() ?? 0;
                      final achievementPct =
                          (item['achievement_pct'] as num?)?.toDouble() ?? 0;
                      final rewardAmount = (item['reward_amount'] as num?) ?? 0;
                      final penaltyAmount =
                          (item['penalty_amount'] as num?) ?? 0;
                      final rewardEffective =
                          (item['reward_effective'] as num?) ?? 0;
                      final penaltyEffective =
                          (item['penalty_effective'] as num?) ?? 0;
                      final netBonus = (item['net_bonus'] as num?) ?? 0;
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
                                    name,
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
                              '${_formatPoints(targetQty)} unit',
                              compact: true,
                            ),
                            _valueRow(
                              'Pencapaian',
                              '${_formatPoints(actualUnits)} unit',
                              compact: true,
                            ),
                            _valueRow(
                              'Achievement',
                              '${achievementPct.toStringAsFixed(1)}%',
                              compact: true,
                            ),
                            _valueRow(
                              'Reward',
                              '${bonusFormatter.format(rewardAmount)} -> ${bonusFormatter.format(rewardEffective)}',
                              compact: true,
                            ),
                            _valueRow(
                              'Denda',
                              '${bonusFormatter.format(penaltyAmount)} -> ${bonusFormatter.format(penaltyEffective)}',
                              compact: true,
                            ),
                            _valueRow(
                              'Hasil',
                              bonusFormatter.format(
                                netBonus < 0 ? 0 : netBonus,
                              ),
                              valueColor: t.primaryAccent,
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

  Widget _buildBonusSection({
    required String title,
    required List<Widget> children,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: PromotorText.outfit(
              size: 11.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ...children,
          if (action != null) ...[const SizedBox(height: 4), action],
        ],
      ),
    );
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
        const SizedBox(height: 2),
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

  Widget _actionLink({required VoidCallback onPressed, required String label}) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: t.primaryAccent,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: const Size(0, 28),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 9.5,
          weight: FontWeight.w800,
          color: t.primaryAccent,
        ),
      ),
    );
  }

  Widget _valueRow(
    String label,
    String value, {
    Color? valueColor,
    bool muted = false,
    bool compact = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 4 : 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: PromotorText.outfit(
                size: compact ? 9 : 10,
                weight: FontWeight.w700,
                color: muted ? t.textMutedStrong : t.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            value,
            textAlign: TextAlign.right,
            style: PromotorText.outfit(
              size: compact ? 9.5 : 10.5,
              weight: FontWeight.w800,
              color: valueColor ?? t.textPrimary,
            ),
          ),
        ],
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
