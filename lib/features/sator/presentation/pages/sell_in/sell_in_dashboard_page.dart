// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import '../../../../../ui/promotor/promotor.dart';

class SellInDashboardPage extends StatefulWidget {
  const SellInDashboardPage({super.key});

  @override
  State<SellInDashboardPage> createState() => _SellInDashboardPageState();
}

class _SellInDashboardPageState extends State<SellInDashboardPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  Map<String, dynamic>? _summaryData;
  String _areaName = 'Area';
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0.0;
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;

      final profile = await _supabase
          .from('users')
          .select('area')
          .eq('id', userId)
          .single();
      _areaName = profile['area']?.toString() ?? 'Area';

      final summary = await _supabase
          .rpc('get_sator_sellin_summary', params: {'p_sator_id': userId})
          .catchError((_) => null);

      if (mounted) {
        setState(() {
          _summaryData = summary;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.background,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              color: t.primaryAccent,
              onRefresh: _loadData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(),
                    _buildAchievementCard(),
                    _buildQuickActions(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader() {
    final periodLabel = DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now());
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: t.surface1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: t.surface3),
              ),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 18,
                color: t.textMuted,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (_areaName.trim().isEmpty
                          ? 'Sator · Area'
                          : 'Sator · Area $_areaName')
                      .toUpperCase(),
                  style: PromotorText.outfit(
                    size: 8,
                    weight: FontWeight.w700,
                    color: t.primaryAccent,
                    letterSpacing: 1.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Sell In',
                  style: PromotorText.display(size: 20, color: t.textPrimary),
                ),
                Text(
                  periodLabel,
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementCard() {
    final formatter = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    );
    final achievement = _toDouble(_summaryData?['total_sellin']);
    final target = _toDouble(_summaryData?['target_sellin']);
    final percent = target > 0 ? (achievement * 100 / target) : 0.0;
    final remaining = target - achievement;
    final periodLabel = DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now());

    return Container(
      margin: EdgeInsets.fromLTRB(16, 0, 16, 0),
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.surface1, t.surface2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.primaryAccentGlow),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Achievement Bulan Ini'.toUpperCase(),
                      style: PromotorText.outfit(
                        size: 9,
                        weight: FontWeight.w700,
                        color: t.textMuted,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text(
                            'Rp',
                            style: PromotorText.outfit(
                              size: 14,
                              weight: FontWeight.w800,
                              color: t.primaryAccent,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            NumberFormat.decimalPattern(
                              'id_ID',
                            ).format(achievement),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PromotorText.display(
                              size: 26,
                              color: t.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _buildAchievementMeta(
                            label: 'Target',
                            value: formatter.format(target),
                            emphasized: true,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _buildAchievementMeta(
                            label: 'Sisa',
                            value: formatter.format(
                              remaining > 0 ? remaining : 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildRing(percent, 'Achieve'),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text(
                'Progress $periodLabel',
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w700,
                  color: t.textMuted,
                ),
              ),
              const Spacer(),
              Text(
                '${percent.clamp(0, 100).toStringAsFixed(1)}%',
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w800,
                  color: t.primaryAccent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _buildThinProgress(percent / 100, t.warning),
        ],
      ),
    );
  }

  Widget _buildAchievementMeta({
    required String label,
    required String value,
    bool emphasized = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: emphasized ? t.primaryAccentSoft : t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: emphasized
              ? t.primaryAccent.withValues(alpha: 0.2)
              : t.surface3,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: PromotorText.outfit(
              size: 9,
              weight: FontWeight.w800,
              color: emphasized ? t.primaryAccent : t.textMuted,
              letterSpacing: 0.9,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRing(double pct, String label) {
    return SizedBox(
      width: 68,
      height: 68,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 68,
            height: 68,
            child: CustomPaint(
              painter: _RingPainter(
                pct: pct,
                color: t.warning,
                backgroundColor: t.surface3,
                radius: 28,
                stroke: 5,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${pct.clamp(0, 100).toStringAsFixed(0)}%',
                style: PromotorText.display(size: 16, color: t.warning),
              ),
              Text(
                label,
                style: PromotorText.outfit(
                  size: 7,
                  weight: FontWeight.w700,
                  color: t.textMuted,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThinProgress(double value, Color color) {
    return Container(
      height: 6,
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 260 * value.clamp(0.0, 1.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(colors: [color, t.primaryAccentLight]),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 10),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    final actions = [
      _QuickAction(
        icon: Icons.warehouse,
        label: 'Stok Gudang',
        color: t.primaryAccent,
        route: '/sator/sell-in/gudang',
      ),
      _QuickAction(
        icon: Icons.inventory_2,
        label: 'Stok Toko',
        color: t.warning,
        route: '/sator/sell-in/toko',
      ),
      _QuickAction(
        icon: Icons.task_alt,
        label: 'Finalisasi',
        color: t.warning,
        route: '/sator/sell-in/finalisasi',
      ),
      _QuickAction(
        icon: Icons.analytics,
        label: 'Achievement',
        color: t.primaryAccentLight,
        route: '/sator/sell-in/achievement',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Menu Utama'.toUpperCase(),
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: actions
                .map(
                  (item) =>
                      Expanded(child: _buildQuickActionIcon(item, context)),
                )
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionIcon(_QuickAction item, BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(item.route),
      child: SizedBox(
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: item.color.withValues(alpha: 0.18)),
              ),
              child: Icon(item.icon, size: 22, color: item.color),
            ),
            const SizedBox(height: 8),
            Text(
              item.label,
              textAlign: TextAlign.center,
              style: PromotorText.outfit(
                size: 9,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;
  final String route;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.route,
  });
}

class _RingPainter extends CustomPainter {
  final double pct;
  final Color color;
  final Color backgroundColor;
  final double radius;
  final double stroke;

  const _RingPainter({
    required this.pct,
    required this.color,
    required this.backgroundColor,
    required this.radius,
    required this.stroke,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final bgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = backgroundColor
      ..strokeCap = StrokeCap.round;
    final fgPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = color
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);
    final sweep = (pct.clamp(0, 100) / 100) * 2 * 3.141592653589793;
    final rect = Rect.fromCircle(center: center, radius: radius);
    canvas.drawArc(rect, -3.141592653589793 / 2, sweep, false, fgPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.pct != pct || oldDelegate.color != color;
  }
}
