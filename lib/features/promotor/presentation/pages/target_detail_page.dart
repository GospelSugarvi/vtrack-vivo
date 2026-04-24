// ignore_for_file: unused_element
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/foundation.dart';
import '../../../../main.dart';

class TargetDetailPage extends StatefulWidget {
  const TargetDetailPage({super.key});

  @override
  State<TargetDetailPage> createState() => _TargetDetailPageState();
}

class _TargetDetailPageState extends State<TargetDetailPage>
    with TickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  Map<String, dynamic>? _targetData;
  final Set<String> _specialBundleNames = {};
  bool _isLoading = true;
  String? _error;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('$value') ?? 0;
  }

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _loadTargetData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadTargetData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = supabase.auth.currentUser?.id;
      if (userId == null) {
        setState(() {
          _error = 'User not authenticated';
          _isLoading = false;
        });
        return;
      }

      final response = await supabase.rpc(
        'get_target_dashboard',
        params: {
          'p_user_id': userId,
          'p_period_id': null, // current period
        },
      );

      if (response != null && response.isNotEmpty) {
        final data = response[0] as Map<String, dynamic>;
        setState(() {
          _targetData = data;
          _isLoading = false;
          _error = null;
        });
        final periodId = data['period_id']?.toString();
        if (periodId != null && periodId.isNotEmpty) {
          await _loadSpecialBundles(periodId);
        }
        _animationController.forward();
      } else {
        setState(() {
          _error = 'No target data found for current period';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load target data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSpecialBundles(String periodId) async {
    try {
      final rows = await supabase
          .from('special_focus_bundles')
          .select('id, bundle_name, special_focus_bundle_products(product_id)')
          .eq('period_id', periodId);
      final names = <String>{};
      for (final row in (rows as List? ?? const [])) {
        if (row is Map<String, dynamic>) {
          final name = (row['bundle_name'] ?? '').toString().trim();
          if (name.isNotEmpty) names.add(name);
        }
      }
      if (!mounted) return;
      setState(() {
        _specialBundleNames
          ..clear()
          ..addAll(names);
      });
    } catch (_) {
      // If RLS blocks or table missing, just skip special labels.
      if (!mounted) return;
      setState(() {
        _specialBundleNames.clear();
      });
    }
  }

  String _formatCurrency(num value) {
    return 'Rp ${value.toString().replaceAllMapped(RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (Match m) => '${m[1]}.')}';
  }

  Color _getStatusColor(String status, bool warning) {
    if (status == 'ACHIEVED') return t.success;
    if (warning) return t.danger;
    return t.warning;
  }

  IconData _getStatusIcon(String status, bool warning) {
    if (status == 'ACHIEVED') return Icons.check_circle;
    if (warning) return Icons.warning_amber;
    return Icons.trending_up;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.background,
      appBar: AppBar(
        title: const Text('Detail Target Harian'),
        actions: [
          IconButton(icon: Icon(Icons.refresh), onPressed: _loadTargetData),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _buildErrorView()
          : _targetData == null
          ? _buildNoTargetView()
          : RefreshIndicator(
              onRefresh: _loadTargetData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildPeriodHeader(),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildStickyFooter() {
    // Sell out data
    final actualOmzet = _targetData?['actual_omzet'] ?? 0;
    final pctOmzet = (_targetData?['achievement_omzet_pct'] ?? 0.0).toDouble();

    // Fokus Data
    final actualFokus = _targetData?['actual_fokus_total'] ?? 0;
    final pctFokus = (_targetData?['achievement_fokus_pct'] ?? 0.0).toDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface1,
        boxShadow: [
          BoxShadow(
            color: t.shellBackground.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: _buildFooterMetric(
                'SELL OUT',
                _formatCurrency(actualOmzet),
                '${pctOmzet.toStringAsFixed(1)}%',
                t.info,
              ),
            ),
            Container(
              width: 1,
              height: 30,
              color: t.surface3,
              margin: const EdgeInsets.symmetric(horizontal: 12),
            ),
            Expanded(
              child: _buildFooterMetric(
                'FOKUS',
                '$actualFokus Unit',
                '${pctFokus.toStringAsFixed(1)}%',
                t.warning,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooterMetric(
    String label,
    String value,
    String percent,
    Color color,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyle.caption(
            t.textSecondary,
            weight: FontWeight.w800,
            letterSpacing: 1.1,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            Text(
              value,
              style: AppTextStyle.bodyMd(
                t.textPrimary,
                weight: FontWeight.w900,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                percent,
                style: AppTextStyle.label(color, weight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: t.danger),
            const SizedBox(height: 24),
            Text(
              'Terjadi Kesalahan',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? 'Unknown error',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTargetData,
              icon: Icon(Icons.refresh),
              label: const Text('Try Again'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoTargetView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.flag_outlined, size: 64, color: t.textSecondary),
            const SizedBox(height: 24),
            Text(
              'Tidak Ada Target',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Belum ada target yang ditetapkan untuk periode ini',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: t.textSecondary),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadTargetData,
              icon: Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeriodHeader() {
    final periodName = _targetData?['period_name'] ?? 'Target';
    final startDate = _targetData?['start_date'] ?? '';
    final endDate = _targetData?['end_date'] ?? '';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [t.infoSoft, t.infoSoft],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.info,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.calendar_today, color: t.textPrimary, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    periodName,
                    style: AppTextStyle.titleSm(
                      t.textPrimary,
                      weight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$startDate s/d $endDate',
                    style: AppTextStyle.bodyMd(t.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeGoneCard() {
    final timeGonePct = (_targetData?['time_gone_pct'] ?? 0.0).toDouble();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.schedule, color: t.warning, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Waktu Berjalan',
                  style: TextStyle(
                    fontSize: AppTypeScale.bodyStrong,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: timeGonePct / 100,
              backgroundColor: t.surface3,
              valueColor: AlwaysStoppedAnimation<Color>(
                timeGonePct > 75
                    ? t.danger
                    : timeGonePct > 50
                    ? t.warning
                    : t.success,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Progress Waktu',
                  style: TextStyle(
                    fontSize: AppTypeScale.body,
                    color: t.textSecondary,
                  ),
                ),
                Text(
                  '${timeGonePct.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: AppTypeScale.body,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellOutTargetCard() {
    final targetOmzet = _targetData?['target_omzet'] ?? 0;
    final actualOmzet = _targetData?['actual_omzet'] ?? 0;
    final achievementPct = (_targetData?['achievement_omzet_pct'] ?? 0.0)
        .toDouble();
    final timeGonePct = (_targetData?['time_gone_pct'] ?? 0.0).toDouble();
    final warningOmzet = _targetData?['warning_omzet'] ?? false;
    final statusOmzet = _targetData?['status_omzet'] ?? 'ON_TRACK';

    final statusColor = _getStatusColor(statusOmzet, warningOmzet);
    final statusIcon = _getStatusIcon(statusOmzet, warningOmzet);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.monetization_on, color: t.success, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Target Sell Out',
                  style: TextStyle(
                    fontSize: AppTypeScale.bodyStrong,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMetricRow(
              'Target',
              _formatCurrency(targetOmzet),
              t.textSecondary,
            ),
            const SizedBox(height: 8),
            _buildMetricRow(
              'Pencapaian',
              _formatCurrency(actualOmzet),
              statusColor,
              bold: true,
            ),
            const SizedBox(height: 8),
            _buildMetricRow(
              targetOmzet - actualOmzet >= 0 ? 'Kurang' : 'Lebih',
              _formatCurrency((targetOmzet - actualOmzet).abs()),
              targetOmzet - actualOmzet >= 0 ? t.danger : t.success,
              bold: true,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: achievementPct / 100,
              backgroundColor: t.surface3,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pencapaian',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      '${achievementPct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Waktu Berjalan',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      '${timeGonePct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, color: statusColor, size: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      statusOmzet == 'ACHIEVED'
                          ? 'Target Tercapai'
                          : warningOmzet
                          ? 'Perlu Perhatian'
                          : 'Dalam Target',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFokusTargetCard() {
    final targetFokus = _targetData?['target_fokus_total'] ?? 0;
    final actualFokus = _targetData?['actual_fokus_total'] ?? 0;
    final achievementPct = (_targetData?['achievement_fokus_pct'] ?? 0.0)
        .toDouble();
    final timeGonePct = (_targetData?['time_gone_pct'] ?? 0.0).toDouble();
    final warningFokus = _targetData?['warning_fokus'] ?? false;
    final statusFokus = _targetData?['status_fokus'] ?? 'ON_TRACK';
    final fokusDetails = _targetData?['fokus_details'] as List? ?? [];

    final statusColor = _getStatusColor(statusFokus, warningFokus);
    final statusIcon = _getStatusIcon(statusFokus, warningFokus);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.phone_android, color: t.info, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Target Produk Fokus',
                  style: TextStyle(
                    fontSize: AppTypeScale.bodyStrong,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildMetricRow('Target', '$targetFokus unit', t.textSecondary),
            const SizedBox(height: 8),
            _buildMetricRow(
              'Pencapaian',
              '$actualFokus unit',
              statusColor,
              bold: true,
            ),
            const SizedBox(height: 8),
            _buildMetricRow(
              targetFokus - actualFokus >= 0 ? 'Kurang' : 'Lebih',
              '${(targetFokus - actualFokus).abs()} unit',
              targetFokus - actualFokus >= 0 ? t.danger : t.success,
              bold: true,
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: achievementPct / 100,
              backgroundColor: t.surface3,
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Achievement',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      '${achievementPct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        fontWeight: FontWeight.bold,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Waktu Berjalan',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      '${timeGonePct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: statusColor.withValues(alpha: 0.3)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(statusIcon, color: statusColor, size: 16),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      statusFokus == 'ACHIEVED'
                          ? 'Target Tercapai'
                          : warningFokus
                          ? 'Perlu Perhatian'
                          : 'Dalam Target',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.list_alt, color: t.primaryAccent, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Detail Produk Fokus',
                  style: TextStyle(
                    fontSize: AppTypeScale.body,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (fokusDetails.isEmpty)
              Text(
                'Belum ada detail produk fokus.',
                style: TextStyle(color: t.textSecondary),
              )
            else
              ...fokusDetails.map(
                (detail) => _buildFokusDetailItem(detail, timeGonePct),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFokusDetailItem(
    Map<String, dynamic> detail,
    double timeGonePct,
  ) {
    final bundleName = detail['bundle_name'] ?? 'Unknown';
    final targetQty = detail['target_qty'] ?? 0;
    final actualQty = detail['actual_qty'] ?? 0;
    final gap = targetQty - actualQty;
    final achievementPct = targetQty > 0 ? (actualQty / targetQty * 100) : 0.0;
    final isWarning = achievementPct < timeGonePct;
    final isSpecial = _specialBundleNames.contains(bundleName);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              return Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: constraints.maxWidth),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.phone_android, color: t.info, size: 20),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            bundleName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: AppTypeScale.body,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isSpecial) _buildSpecialBadge(),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Target vs Pencapaian',
            style: TextStyle(
              fontSize: AppTypeScale.support,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Target',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      '$targetQty unit',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Pencapaian',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      '$actualQty unit',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        fontWeight: FontWeight.bold,
                        color: isWarning ? t.warning : t.success,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      gap >= 0 ? 'Lebih' : 'Kurang',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      '${gap.abs()} unit',
                      style: TextStyle(
                        fontSize: AppTypeScale.body,
                        fontWeight: FontWeight.bold,
                        color: gap >= 0 ? t.success : t.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: achievementPct / 100,
            backgroundColor: t.surface3,
            valueColor: AlwaysStoppedAnimation<Color>(
              isWarning ? t.warning : t.success,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${achievementPct.toStringAsFixed(1)}% tercapai',
            style: TextStyle(
              fontSize: AppTypeScale.body,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeeklyBreakdownCard() {
    final weeklyDataRaw = _targetData?['weekly_breakdown'] as List? ?? [];
    if (weeklyDataRaw.isEmpty) return const SizedBox.shrink();
    final deduped = <String, Map<String, dynamic>>{};
    for (final w in weeklyDataRaw) {
      if (w is Map<String, dynamic>) {
        final key = '${w['week_number']}-${w['start_date']}-${w['end_date']}';
        deduped.putIfAbsent(key, () => w);
      }
    }
    final weeklyData = deduped.values.toList();
    if (weeklyData.isEmpty) return const SizedBox.shrink();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.view_week, color: t.info, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Target Mingguan',
                  style: TextStyle(
                    fontSize: AppTypeScale.bodyStrong,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ...weeklyData.map((week) => _buildWeeklyItem(week)),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: t.warningSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.warning.withValues(alpha: 0.4)),
      ),
      child: Text(
        'Tipe Khusus',
        style: TextStyle(
          fontSize: AppTypeScale.support,
          fontWeight: FontWeight.w700,
          color: t.warning,
        ),
      ),
    );
  }

  Widget _buildWeeklyItem(Map<String, dynamic> week) {
    final weekNum = week['week_number'];
    final startDate = week['start_date'];
    final endDate = week['end_date'];
    final weight = week['percentage_of_total'] ?? 0;

    // Sell out data
    final targetOmzet = (week['target_omzet'] ?? 0).toDouble();
    final actualOmzet = (week['actual_omzet'] ?? 0).toDouble();
    final pctOmzet =
        (week['achievement_omzet_pct'] ?? week['achievement_pct'] ?? 0.0)
            .toDouble();

    // Fokus data
    final targetFokus = (week['target_fokus'] ?? 0).toInt();
    final actualFokus = (week['actual_fokus'] ?? 0).toInt();
    final pctFokus = (week['achievement_fokus_pct'] ?? 0.0).toDouble();

    final isCurrentWeek = _isDateInWeek(startDate, endDate);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentWeek ? t.infoSoft.withValues(alpha: 0.35) : t.surface2,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isCurrentWeek ? t.info.withValues(alpha: 0.2) : t.surface3,
          width: isCurrentWeek ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Minggu $weekNum ($weight%)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isCurrentWeek ? t.info : t.textPrimary,
                ),
              ),
              if (isCurrentWeek)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: t.info,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Minggu Ini',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: AppTypeScale.support,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
            ],
          ),
          Text(
            '$startDate - $endDate',
            style: TextStyle(
              fontSize: AppTypeScale.body,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 12),

          // All Type Section
          Row(
            children: [
              Icon(Icons.monetization_on, size: 16, color: t.info),
              const SizedBox(width: 4),
              const Text(
                'All Type',
                style: TextStyle(
                  fontSize: AppTypeScale.support,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Target: ${_formatCurrency(targetOmzet)}',
                  style: TextStyle(fontSize: AppTypeScale.body),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Capai: ${_formatCurrency(actualOmzet)} (${pctOmzet.toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: AppTypeScale.body,
                    fontWeight: FontWeight.bold,
                    color: pctOmzet >= 100 ? t.success : t.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pctOmzet / 100).clamp(0.0, 1.0),
              backgroundColor: t.surface3,
              valueColor: AlwaysStoppedAnimation<Color>(
                pctOmzet >= 100 ? t.success : t.info,
              ),
              minHeight: 6,
            ),
          ),

          const SizedBox(height: 10),

          // Fokus Section
          Row(
            children: [
              Icon(Icons.star, size: 16, color: t.warning),
              const SizedBox(width: 4),
              const Text(
                'Produk Fokus',
                style: TextStyle(
                  fontSize: AppTypeScale.support,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'Target: $targetFokus unit',
                  style: TextStyle(fontSize: AppTypeScale.body),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Capai: $actualFokus unit (${pctFokus.toStringAsFixed(0)}%)',
                  style: TextStyle(
                    fontSize: AppTypeScale.body,
                    fontWeight: FontWeight.bold,
                    color: pctFokus >= 100 ? t.success : t.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (pctFokus / 100).clamp(0.0, 1.0),
              backgroundColor: t.surface3,
              valueColor: AlwaysStoppedAnimation<Color>(
                pctFokus >= 100 ? t.success : t.warning,
              ),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  bool _isDateInWeek(String start, String end) {
    try {
      final now = DateTime.now();
      final startDate = DateTime.parse(start);
      final endDate = DateTime.parse(end);
      // We only care about the date part
      final today = DateTime(now.year, now.month, now.day);
      return (today.isAtSameMomentAs(startDate) || today.isAfter(startDate)) &&
          (today.isAtSameMomentAs(endDate) || today.isBefore(endDate));
    } catch (_) {
      return false;
    }
  }

  Widget _buildMetricRow(
    String label,
    String value,
    Color color, {
    bool bold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: AppTypeScale.body, color: t.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: AppTypeScale.body,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
            color: color,
          ),
        ),
      ],
    );
  }
}
