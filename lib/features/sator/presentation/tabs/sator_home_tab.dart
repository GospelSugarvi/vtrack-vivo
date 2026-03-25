import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/router/app_route_names.dart';
import '../../../../ui/components/field_segmented_control.dart';
import '../../../../ui/foundation/field_theme_extensions.dart';
import '../../../../ui/promotor/promotor.dart';

class SatorHomeTab extends StatefulWidget {
  final VoidCallback? onOpenLaporan;

  const SatorHomeTab({super.key, this.onOpenLaporan});

  @override
  State<SatorHomeTab> createState() => _SatorHomeTabState();
}

class _SatorHomeTabState extends State<SatorHomeTab> {
  FieldThemeTokens get t => context.fieldTokens;
  final SupabaseClient _supabase = Supabase.instance.client;
  final NumberFormat _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );

  bool _isLoading = true;
  int _frameIndex = 0;

  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _homeSummary;
  Map<String, dynamic>? _dailySummary;
  Map<String, dynamic>? _weeklySummary;
  Map<String, dynamic>? _monthlySummary;
  List<Map<String, dynamic>> _dailyPromotors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _weeklyPromotors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _monthlyPromotors = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _weeklySnapshots = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _agendaItems = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _focusProducts = <Map<String, dynamic>>[];
  String? _selectedWeeklyKey;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  FieldThemeTokens get _t => context.fieldTokens;
  Color get _bg => _t.background;
  Color get _s1 => _t.surface1;
  Color get _s2 => _t.surface2;
  Color get _s3 => _t.surface3;
  Color get _gold => _t.primaryAccent;
  Color get _goldSoft => _t.primaryAccentSoft;
  Color get _goldGlow => _t.primaryAccentGlow;
  Color get _goldLt => _t.primaryAccentLight;
  Color get _cream => _t.textPrimary;
  Color get _cream2 => _t.textSecondary;
  Color get _muted => _t.textMuted;
  Color get _green => _t.success;
  Color get _greenSoft => _t.successSoft;
  Color get _amber => _t.warning;
  Color get _red => _t.danger;
  Color get _redSoft => _t.dangerSoft;
  Color get _heroStart => _t.heroGradientStart;
  Color get _heroEnd => _t.heroGradientEnd;
  Color get _heroHighlight => _t.heroHighlight;

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

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    final raw = '${value ?? ''}'.trim();
    if (raw.isEmpty) return 0;
    return int.tryParse(raw) ?? num.tryParse(raw)?.toInt() ?? 0;
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  String _initialOf(dynamic value, {String fallback = 'P'}) {
    final text = '${value ?? ''}'.trim();
    if (text.isEmpty) return fallback;
    return text.characters.first.toUpperCase();
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> _refresh() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final results = await Future.wait([
        _supabase.rpc(
          'get_sator_home_snapshot',
          params: <String, dynamic>{'p_sator_id': userId},
        ),
        _supabase.rpc(
          'get_sator_home_weekly_snapshots',
          params: <String, dynamic>{
            'p_sator_id': userId,
            'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
          },
        ),
      ]);
      final snapshotRaw = results[0];
      final weeklyRaw = results[1];
      final snapshot = snapshotRaw is Map
          ? Map<String, dynamic>.from(snapshotRaw)
          : <String, dynamic>{};
      final weeklyPayload = weeklyRaw is Map
          ? Map<String, dynamic>.from(weeklyRaw)
          : <String, dynamic>{};
      final profile = Map<String, dynamic>.from(
        snapshot['profile'] as Map? ?? const <String, dynamic>{},
      );
      final dailySummary = Map<String, dynamic>.from(
        snapshot['daily'] as Map? ?? const <String, dynamic>{},
      );
      final weeklySummary = Map<String, dynamic>.from(
        snapshot['weekly'] as Map? ?? const <String, dynamic>{},
      );
      final monthlySummary = Map<String, dynamic>.from(
        snapshot['monthly'] as Map? ?? const <String, dynamic>{},
      );
      final dailyPromotors = _parseMapList(snapshot['daily_promotors']);
      final weeklyPromotors = _parseMapList(snapshot['weekly_promotors']);
      final monthlyPromotors = _parseMapList(snapshot['monthly_promotors']);
      final focusProducts = _parseMapList(snapshot['focus_products']);
      final weeklySnapshots = _parseMapList(weeklyPayload['weekly_snapshots']);
      final resolvedSelectedWeeklyKey = _resolveInitialWeeklyKey(
        weeklySnapshots,
        preferredKey: _selectedWeeklyKey,
        activeWeekNumber: _toInt(weeklyPayload['active_week_number']),
      );

      final agendaItems = List<dynamic>.from(snapshot['agenda'] ?? const [])
          .map((item) {
            final row = Map<String, dynamic>.from(item as Map);
            final status = '${row['status'] ?? ''}';
            final tone = switch (status) {
              'pending' => _amber,
              'process' => _red,
              'review' => _red,
              'done' => _green,
              'ok' => _green,
              _ => _gold,
            };
            final soft = switch (status) {
              'pending' => _goldSoft,
              'process' => _redSoft,
              'review' => _redSoft,
              'done' => _greenSoft,
              'ok' => _greenSoft,
              _ => _goldSoft,
            };
            return <String, dynamic>{
              'title': row['title'] ?? '-',
              'subtitle': row['sub'] ?? '-',
              'badge': status.isEmpty ? 'Monitor' : status,
              'tone': tone,
              'soft': soft,
            };
          })
          .toList();

      if (!mounted) return;
      setState(() {
        _profile = profile;
        _homeSummary = snapshot;
        _dailySummary = dailySummary;
        _weeklySummary = weeklySummary;
        _monthlySummary = monthlySummary;
        _dailyPromotors = dailyPromotors;
        _weeklyPromotors = weeklyPromotors;
        _monthlyPromotors = monthlyPromotors;
        _weeklySnapshots = weeklySnapshots;
        _selectedWeeklyKey = resolvedSelectedWeeklyKey;
        _agendaItems = agendaItems;
        _focusProducts = focusProducts;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('SATOR home refresh failed: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic> get _summary {
    switch (_frameIndex) {
      case 1:
        final selectedSnapshot = _selectedWeeklySnapshot();
        if (selectedSnapshot != null) {
          return Map<String, dynamic>.from(
            selectedSnapshot['summary'] ?? const <String, dynamic>{},
          );
        }
        return Map<String, dynamic>.from(
          _weeklySummary ?? const <String, dynamic>{},
        );
      case 2:
        return Map<String, dynamic>.from(
          _monthlySummary ?? const <String, dynamic>{},
        );
      default:
        return Map<String, dynamic>.from(
          _dailySummary ?? const <String, dynamic>{},
        );
    }
  }

  List<Map<String, dynamic>> get _promotorRows {
    switch (_frameIndex) {
      case 1:
        final selectedSnapshot = _selectedWeeklySnapshot();
        if (selectedSnapshot != null) {
          return _parseMapList(selectedSnapshot['promotors']);
        }
        return _weeklyPromotors;
      case 2:
        return _monthlyPromotors;
      default:
        return _dailyPromotors;
    }
  }

  String get _profileName {
    final nickname = '${_profile?['nickname'] ?? ''}'.trim();
    if (nickname.isNotEmpty) return nickname;
    return '${_profile?['full_name'] ?? 'SATOR'}';
  }
  String get _profileArea => '${_profile?['area'] ?? '-'}';
  String get _profileRole => '${_profile?['role'] ?? 'SATOR'}';

  String _weeklySnapshotKey(Map<String, dynamic> snapshot) {
    final weekNumber = _toInt(snapshot['week_number']);
    final startDate = '${snapshot['start_date'] ?? ''}';
    final endDate = '${snapshot['end_date'] ?? ''}';
    return '$weekNumber|$startDate|$endDate';
  }

  String? _resolveInitialWeeklyKey(
    List<Map<String, dynamic>> snapshots, {
    String? preferredKey,
    int activeWeekNumber = 0,
  }) {
    if (snapshots.isEmpty) return null;

    if (preferredKey != null) {
      for (final snapshot in snapshots) {
        if (_weeklySnapshotKey(snapshot) == preferredKey) {
          return preferredKey;
        }
      }
    }

    for (final snapshot in snapshots) {
      if (_toInt(snapshot['week_number']) == activeWeekNumber) {
        return _weeklySnapshotKey(snapshot);
      }
    }

    return _weeklySnapshotKey(snapshots.first);
  }

  Map<String, dynamic>? _selectedWeeklySnapshot() {
    if (_weeklySnapshots.isEmpty) return null;
    final selectedKey = _selectedWeeklyKey;
    if (selectedKey != null) {
      for (final snapshot in _weeklySnapshots) {
        if (_weeklySnapshotKey(snapshot) == selectedKey) {
          return snapshot;
        }
      }
    }
    return _weeklySnapshots.first;
  }

  num _sumPromotorField(List<Map<String, dynamic>> rows, String key) {
    num total = 0;
    for (final row in rows) {
      total += _toNum(row[key]);
    }
    return total;
  }

  String _formatCompactCurrency(num value) {
    return _currency.format(value).replaceAll(',00', '');
  }

  Widget _buildHeroAmount(num value, {double size = 22}) {
    final formatted = _formatCompactCurrency(value);
    final raw = formatted.replaceFirst('Rp ', '').trim();
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: RichText(
        text: TextSpan(
          children: [
            TextSpan(
              text: 'Rp ',
              style: _outfit(
                size: size * 0.52,
                weight: FontWeight.w800,
                color: _cream2,
              ),
            ),
            TextSpan(
              text: raw,
              style: _display(size: size, weight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFocusTitleBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _goldSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _goldGlow),
      ),
      child: Text(
        label,
        style: _outfit(size: 11, weight: FontWeight.w800, color: _gold),
      ),
    );
  }

  Widget _buildFocusChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: _s2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _s3),
      ),
      child: Text(label, style: _outfit(size: 8, weight: FontWeight.w700, color: _cream2)),
    );
  }

  Widget _buildFocusSummaryMetric(String label, String value, Color? valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: _outfit(size: 9, color: _muted)),
          const SizedBox(height: 3),
          Text(
            value,
            style: _outfit(
              size: 12,
              weight: FontWeight.w800,
              color: valueColor ?? _cream,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildFocusProductRow(Map<String, dynamic> product) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: _s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Row(
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: _goldSoft,
              borderRadius: BorderRadius.circular(999),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.flag_rounded, size: 12, color: _gold),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${product['model_name'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _outfit(size: 11, weight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  '${product['series'] ?? '-'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _outfit(size: 8, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (product['is_detail_target'] == true) _buildFocusChip('Detail'),
              if (product['is_special'] == true) _buildFocusChip('Khusus'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFocusInsightBlock({
    required String title,
    required num target,
    required num actual,
    required String progressNote,
  }) {
    final targetUnits = target.ceil();
    final actualUnits = actual.toInt();
    final remaining = math.max(0, targetUnits - actualUnits);
    final progress = target > 0 ? (actual * 100 / target) : 0.0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(_t.radiusMd),
        border: Border.all(color: _s3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _buildFocusTitleBadge(title),
                const Spacer(),
                Text(
                  '${progress.toStringAsFixed(0)}%',
                  style: _display(size: 16, weight: FontWeight.w800, color: _gold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildFocusSummaryMetric('Target', '$targetUnits', null),
                _buildFocusSummaryMetric('Terjual', '$actualUnits', _green),
                _buildFocusSummaryMetric('Sisa', '$remaining', _amber),
                _buildFocusSummaryMetric('Progress', '${progress.toStringAsFixed(0)}%', _gold),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    progressNote,
                    style: _outfit(size: 9, color: _muted),
                  ),
                ),
                Text(
                  '${_focusProducts.length} tipe',
                  style: _outfit(size: 9, weight: FontWeight.w700, color: _cream2),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: (progress / 100).clamp(0, 1),
                minHeight: 4,
                backgroundColor: _s3,
                valueColor: AlwaysStoppedAnimation<Color>(_gold),
              ),
            ),
            if (_focusProducts.isNotEmpty) ...[
              const SizedBox(height: 10),
              ..._focusProducts.take(3).map(_buildFocusProductRow),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() {
    final summary = _summary;
    final selectedWeeklySnapshot = _selectedWeeklySnapshot();
    final target = switch (_frameIndex) {
      1 => _toInt(summary['target_omzet']),
      2 => _toInt(summary['target_omzet']),
      _ => _toInt(summary['target_sellout']),
    };
    final actual = switch (_frameIndex) {
      1 => _toInt(summary['actual_omzet']),
      2 => _toInt(summary['actual_omzet']),
      _ => _toInt(summary['actual_sellout']),
    };
    final pct = target > 0 ? actual / target : 0.0;
    final title = switch (_frameIndex) {
      1 => 'Target Mingguan Tim',
      2 => 'Target Bulanan Tim',
      _ => 'Target Harian Tim',
    };
    final progressLabel = switch (_frameIndex) {
      1 => selectedWeeklySnapshot != null
          ? 'Minggu ke-${_toInt(selectedWeeklySnapshot['week_number'])} • ${selectedWeeklySnapshot['status_label'] ?? 'Minggu aktif'}'
          : 'Minggu ke-${((DateTime.now().day - 1) / 7).floor() + 1} • Hari ke-${DateTime.now().weekday}',
      2 => 'Progress bulan ini',
      _ => 'Progress hari ini',
    };

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [_heroStart, _heroEnd],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(_t.radiusLg),
        border: Border.all(color: _goldGlow),
        boxShadow: [
          BoxShadow(
            color: _gold.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned(
            top: -28,
            right: -24,
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  colors: [_heroHighlight, _heroHighlight.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: _outfit(
                              size: 12,
                              weight: FontWeight.w700,
                              color: _cream2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          _buildHeroAmount(target, size: 22),
                          const SizedBox(height: 4),
                          Text(
                            'Realisasi ${_formatCompactCurrency(actual)}',
                            style: _outfit(size: 12, color: _cream2),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      width: 58,
                      height: 58,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularProgressIndicator(
                            value: 1,
                            strokeWidth: 5,
                            backgroundColor: _s3,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              _s1.withValues(alpha: 0),
                            ),
                          ),
                          CircularProgressIndicator(
                            value: pct.clamp(0, 1),
                            strokeWidth: 5,
                            strokeCap: StrokeCap.round,
                            backgroundColor: _s1.withValues(alpha: 0),
                            valueColor: AlwaysStoppedAnimation<Color>(
                              pct < 0.6 ? _red : (pct < 0.85 ? _amber : _gold),
                            ),
                          ),
                          Text(
                            '${(pct * 100).toStringAsFixed(0)}%',
                            style: _display(
                              size: 12,
                              weight: FontWeight.w800,
                              color: pct < 0.6
                                  ? _red
                                  : (pct < 0.85 ? _amber : _gold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        progressLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _outfit(size: 11, color: _muted),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Sisa ${_formatCompactCurrency(math.max(0, target - actual))}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: _outfit(
                          size: 11,
                          weight: FontWeight.w700,
                          color: _goldLt,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0, 1),
                    minHeight: 5,
                    backgroundColor: _s3,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      pct < 0.6 ? _red : (pct < 0.85 ? _amber : _gold),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildHeroStat(
                        label: _frameIndex == 2
                            ? 'Hari Kerja'
                            : _frameIndex == 1
                            ? 'Rentang'
                            : 'Hari Ini',
                        value: _frameIndex == 2
                            ? '${DateTime.now().day}'
                            : _frameIndex == 1
                            ? _formatWeekRange(
                                _parseDate(selectedWeeklySnapshot?['start_date']),
                                _parseDate(selectedWeeklySnapshot?['end_date']),
                              )
                            : DateFormat('dd MMM').format(DateTime.now()),
                        note: _frameIndex == 2
                            ? 'Bulanan berjalan'
                            : _frameIndex == 1
                            ? '${_toInt(selectedWeeklySnapshot?['elapsed_working_days'])}/${_toInt(selectedWeeklySnapshot?['working_days'])} hari kerja'
                            : 'Periode aktif',
                      ),
                    ),
                    Expanded(
                      child: _buildHeroStat(
                        label: 'Promotor',
                        value:
                            '${_toInt(_homeSummary?['counts']?['promotors'])}',
                        note: 'Tim aktif',
                      ),
                    ),
                    Expanded(
                      child: _buildHeroStat(
                        label: 'Pending',
                        value:
                            '${_toInt(summary['reports_pending'] ?? summary['total_active_pending'])}',
                        note: 'Butuh follow-up',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyHeroCard() {
    final target = _toNum(_dailySummary?['target_sellout']);
    final actual = _toNum(_dailySummary?['actual_sellout']);
    final pct = target > 0 ? ((actual / target) * 100).clamp(0, 100) : 0.0;
    final remaining = math.max(0, target - actual);

    return GestureDetector(
      onTap: () => context.pushNamed(AppRouteNames.targetDetail),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_heroStart, _heroEnd],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(_t.radiusLg),
          border: Border.all(color: _goldGlow),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              height: 1,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _bg.withValues(alpha: 0),
                    _gold.withValues(alpha: 0.65),
                    _bg.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: _goldSoft,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: _goldGlow),
                          ),
                          child: Text(
                            'Target Harian Tim',
                            style: _outfit(
                              size: 11,
                              weight: FontWeight.w800,
                              color: _gold,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildHeroAmount(target, size: 19),
                        const SizedBox(height: 4),
                        Text(
                          'Pencapaian ${_formatCompactCurrency(actual)}',
                          style: _outfit(
                            size: 12,
                            weight: FontWeight.w700,
                            color: _green,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 54,
                    height: 54,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          width: 54,
                          height: 54,
                          child: CircularProgressIndicator(
                            value: (pct / 100).clamp(0, 1),
                            strokeWidth: 4.5,
                            backgroundColor: _s3,
                            valueColor: AlwaysStoppedAnimation<Color>(_gold),
                          ),
                        ),
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${pct.toStringAsFixed(0)}%',
                              style: _display(
                                size: 11,
                                weight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'hari ini',
                              style: _outfit(size: 8, color: _cream2),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Progress target sell out hari ini',
                      style: _outfit(size: 11, color: _cream2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Sisa ${_formatCompactCurrency(remaining)}',
                    style: _outfit(
                      size: 11,
                      weight: FontWeight.w800,
                      color: _goldLt,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (pct / 100).clamp(0, 1),
                  minHeight: 5,
                  backgroundColor: _s3,
                  valueColor: AlwaysStoppedAnimation<Color>(_gold),
                ),
              ),
            ),
            _buildDailyFocusContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroStat({
    required String label,
    required String value,
    required String note,
  }) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: _outfit(
              size: 8,
              weight: FontWeight.w700,
              color: _muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(value, style: _display(size: 13, weight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(
            note,
            style: _outfit(size: 8, color: _muted),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHead(String title, String note) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: Row(
        children: [
          // Accent dot + garis
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              color: _gold,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _goldGlow, blurRadius: 6, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Container(width: 8, height: 1.5, color: _gold),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title,
              style: _outfit(size: 13, weight: FontWeight.w700, color: _cream2),
            ),
          ),
          Text(note, style: _outfit(size: 11, color: _muted)),
        ],
      ),
    );
  }

  String _weeklySectionNote({bool lowercase = false}) {
    final selectedSnapshot = _selectedWeeklySnapshot();
    final weekNumber = _toInt(selectedSnapshot?['week_number']);
    final label = weekNumber > 0 ? 'Minggu $weekNumber' : 'Mingguan';
    return lowercase ? label.toLowerCase() : label;
  }

  Widget _buildWeeklySelectorCard() {
    if (_weeklySnapshots.isEmpty) return const SizedBox(height: 8);
    final selectedSnapshot = _selectedWeeklySnapshot();
    final rangeLabel = _formatWeekRange(
      _parseDate(selectedSnapshot?['start_date']),
      _parseDate(selectedSnapshot?['end_date']),
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(_t.radiusMd),
        border: Border.all(color: _s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Pilih Minggu',
                style: _outfit(size: 12, weight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                rangeLabel,
                style: _outfit(size: 9, color: _muted),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List<Widget>.generate(_weeklySnapshots.length, (index) {
                final snapshot = _weeklySnapshots[index];
                final weekKey = _weeklySnapshotKey(snapshot);
                final isSelected = weekKey == _selectedWeeklyKey;
                final isActive = snapshot['is_active'] == true;
                final isFuture = snapshot['is_future'] == true;
                final weekNumber = _toInt(snapshot['week_number']);
                final chipTone = isSelected
                    ? _gold
                    : isActive
                    ? _amber
                    : _cream2;

                return Padding(
                  padding: EdgeInsets.only(
                    right: index == _weeklySnapshots.length - 1 ? 0 : 8,
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => setState(() => _selectedWeeklyKey = weekKey),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 122,
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        color: isSelected ? _goldSoft : _s2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? _goldGlow
                              : isActive
                              ? _amber.withValues(alpha: 0.35)
                              : _s3,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Mg $weekNumber',
                                  style: _outfit(
                                    size: 12,
                                    weight: FontWeight.w800,
                                    color: chipTone,
                                  ),
                                ),
                              ),
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: chipTone,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatWeekRange(
                              _parseDate(snapshot['start_date']),
                              _parseDate(snapshot['end_date']),
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _outfit(size: 9, color: _muted),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            isFuture
                                ? 'Belum berjalan'
                                : (snapshot['status_label'] ?? 'Riwayat minggu')
                                      .toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: _outfit(size: 9, weight: FontWeight.w700, color: _cream2),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotorCard(Map<String, dynamic> row) {
    final targetNominal = _toNum(row['target_nominal']);
    final actualNominal = _toNum(row['actual_nominal']);
    final targetFocus = _toNum(row['target_focus_units']);
    final actualFocus = _toNum(row['actual_focus_units']);
    final pct = _toDouble(row['achievement_pct']) / 100;
    final tone = row['underperform'] == true
        ? _red
        : (pct < 0.6 ? _red : (pct < 0.85 ? _amber : _gold));

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(_t.radiusMd),
        border: Border.all(color: _s3),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: _s2,
                    shape: BoxShape.circle,
                    border: Border.all(color: _s3),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _initialOf(row['name']),
                    style: _display(
                      size: 11,
                      weight: FontWeight.w800,
                      color: _cream2,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row['name']}',
                        style: _outfit(size: 13, weight: FontWeight.w700),
                      ),
                      Text(
                        '${row['store_name']}',
                        style: _outfit(size: 9, color: _muted),
                      ),
                    ],
                  ),
                ),
                Text(
                  _frameIndex == 2
                      ? '${_toDouble(row['achievement_pct']).toStringAsFixed(0)}%'
                      : _formatCompactCurrency(actualNominal),
                  style: _outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: tone,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: pct.clamp(0, 1),
                      minHeight: 4,
                      backgroundColor: _s3,
                      valueColor: AlwaysStoppedAnimation<Color>(tone),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 56,
                  child: Text(
                    '${_toDouble(row['achievement_pct']).toStringAsFixed(0)}%',
                    style: _outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: tone,
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Target ${_formatCompactCurrency(targetNominal)} • Produk Fokus ${actualFocus.toInt()}/${targetFocus.ceil()} unit',
                style: _outfit(size: 8, color: _muted),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyPromotorDetailCard(Map<String, dynamic> row) {
    final targetNominal = _toNum(row['target_nominal']);
    final actualNominal = _toNum(row['actual_nominal']);
    final targetFocus = _toNum(row['target_focus_units']);
    final actualFocus = _toNum(row['actual_focus_units']);
    final achievementPct = _toDouble(row['achievement_pct']);
    final progress = (achievementPct / 100).clamp(0, 1).toDouble();
    final tone = achievementPct >= 100
        ? _green
        : (achievementPct > 0 ? _amber : _red);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(_t.radiusMd),
        border: Border.all(color: _s3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: _s2,
              shape: BoxShape.circle,
              border: Border.all(color: _s3),
            ),
            alignment: Alignment.center,
            child: Text(
              _initialOf(row['name']),
              style: _display(size: 9, weight: FontWeight.w800, color: _cream2),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${row['name']}',
                            style: _outfit(size: 12, weight: FontWeight.w700),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${row['store_name'] ?? '-'}',
                            style: _outfit(size: 8, color: _cream2),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Produk Fokus ${targetFocus.ceil()} unit',
                            style: _outfit(size: 8, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Target ${_formatCompactCurrency(targetNominal)}',
                          style: _outfit(
                            size: 10,
                            weight: FontWeight.w800,
                            color: tone,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          actualNominal > 0
                              ? 'Realisasi ${_formatCompactCurrency(actualNominal)}'
                              : 'Realisasi Rp 0',
                          style: _outfit(
                            size: 7,
                            color: _muted,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          value: progress,
                          minHeight: 3,
                          backgroundColor: _s3,
                          valueColor: AlwaysStoppedAnimation<Color>(tone),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 44,
                      child: Text(
                        '${achievementPct.toStringAsFixed(0)}%',
                        style: _outfit(
                          size: 9,
                          weight: FontWeight.w700,
                          color: tone,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Fokus terjual ${actualFocus.toInt()} unit',
                  style: _outfit(size: 7, color: _muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDailyPromotorPreviewCard() {
    final totalTarget = _sumPromotorField(_dailyPromotors, 'target_nominal');
    final totalActual = _sumPromotorField(_dailyPromotors, 'actual_nominal');
    final previewRows = _dailyPromotors.take(3).toList();

    return GestureDetector(
      onTap: _dailyPromotorRowsAvailable ? _openDailyPromotorDetail : null,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        decoration: BoxDecoration(
          color: _s1,
          borderRadius: BorderRadius.circular(_t.radiusMd),
          border: Border.all(color: _s3),
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Target Harian Promotor',
                          style: _outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: _cream2,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_dailyPromotors.length} promotor',
                          style: _outfit(size: 9, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: _gold, size: 18),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildPreviewMetric(
                      'Target',
                      _formatCompactCurrency(totalTarget),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildPreviewMetric(
                      'Realisasi',
                      _formatCompactCurrency(totalActual),
                    ),
                  ),
                ],
              ),
              if (previewRows.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...previewRows.map((row) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${row['name']}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _outfit(
                                  size: 10,
                                  weight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '${row['store_name'] ?? '-'}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: _outfit(size: 7, color: _muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _formatCompactCurrency(_toNum(row['target_nominal'])),
                          style: _outfit(
                            size: 9,
                            weight: FontWeight.w700,
                            color: _gold,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPreviewMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        color: _s2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _outfit(size: 8, color: _muted)),
          const SizedBox(height: 3),
          Text(
            value,
            style: _outfit(size: 11, weight: FontWeight.w800, color: _cream),
          ),
        ],
      ),
    );
  }

  void _openDailyPromotorDetail() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: _bg.withValues(alpha: 0),
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.88,
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: _s3),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: _s3,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatCompactCurrency(
                              _sumPromotorField(
                                _dailyPromotors,
                                'target_nominal',
                              ),
                            ),
                            style: _display(
                              size: 24,
                              weight: FontWeight.w800,
                              color: _cream,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Semua Target Harian Promotor',
                            style: _outfit(
                              size: 14,
                              weight: FontWeight.w700,
                              color: _cream,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_dailyPromotors.length} promotor',
                            style: _outfit(size: 10, color: _muted),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      icon: Icon(Icons.close, color: _cream2, size: 18),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 20),
                  itemCount: _dailyPromotors.length,
                  itemBuilder: (context, index) {
                    return _buildDailyPromotorDetailCard(
                      _dailyPromotors[index],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAgendaCard(Map<String, dynamic> item) {
    final Color tone = item['tone'] as Color;
    final Color soft = item['soft'] as Color;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(_t.radiusMd),
        border: Border.all(color: _s3),
      ),
      child: ListTile(
        leading: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: soft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.circle, size: 10, color: tone),
        ),
        title: Text(
          '${item['title']}',
          style: _outfit(size: 12, weight: FontWeight.w700),
        ),
        subtitle: Text(
          '${item['subtitle']}',
          style: _outfit(size: 9, color: _muted),
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: soft,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            '${item['badge']}',
            style: _outfit(size: 8, weight: FontWeight.w700, color: tone),
          ),
        ),
      ),
    );
  }

  Widget _buildKpiRow(String label, String value, Color color) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(_t.radiusMd),
        border: Border.all(color: _s3),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: _outfit(size: 13, weight: FontWeight.w700),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              value,
              style: _outfit(size: 13, weight: FontWeight.w800, color: color),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRankingState() {
    if (_monthlyPromotors.isEmpty) {
      return Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _s1,
          borderRadius: BorderRadius.circular(_t.radiusMd),
          border: Border.all(color: _s3),
        ),
        child: Text(
          'Belum ada data ranking',
          style: _outfit(size: 11, color: _muted),
        ),
      );
    }

    return Column(
      children: _monthlyPromotors.take(3).map((row) {
        final index = _monthlyPromotors.indexOf(row) + 1;
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _s1,
            borderRadius: BorderRadius.circular(_t.radiusMd),
            border: Border.all(color: _s3),
          ),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: _goldSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                alignment: Alignment.center,
                child: Text(
                  '$index',
                  style: _outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: _gold,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${row['name']}',
                  style: _outfit(size: 12, weight: FontWeight.w700),
                ),
              ),
              Text(
                _formatCompactCurrency(_toNum(row['actual_nominal'])),
                style: _outfit(size: 10, color: _cream2),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBody() {
    final note = DateFormat('MMMM yyyy', 'id_ID').format(DateTime.now());
    if (_frameIndex == 1) {
      final weekly = _weeklySummary ?? <String, dynamic>{};
      final omzetPct = _toNum(weekly['target_omzet']) > 0
          ? (_toNum(weekly['actual_omzet']) *
                100 /
                _toNum(weekly['target_omzet']))
          : 0.0;
      final fokusPct = _toNum(weekly['target_fokus']) > 0
          ? (_toNum(weekly['actual_fokus']) *
                100 /
                _toNum(weekly['target_fokus']))
          : 0.0;
      final activeCount = _weeklyPromotors
          .where((row) => _toNum(row['actual_nominal']) > 0)
          .length;
      final activePct = _weeklyPromotors.isEmpty
          ? 0.0
          : (activeCount * 100 / _weeklyPromotors.length);
      return Column(
        children: [
          _buildHeroCard(),
          _buildWeeklySelectorCard(),
          _buildSectionHead('Pencapaian Mingguan', _weeklySectionNote()),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(
                  child: _buildMiniMetric(
                    'Sell Out',
                    omzetPct,
                    _amber,
                    _formatCompactCurrency(_toNum(weekly['actual_omzet'])),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMiniMetric(
                    'Fokus',
                    fokusPct,
                    _gold,
                    '${_toInt(weekly['actual_fokus'])} unit',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMiniMetric(
                    'Aktivitas',
                    activePct,
                    _green,
                    '$activeCount aktif',
                  ),
                ),
              ],
            ),
          ),
          _buildSectionHead('Target Produk Fokus', _weeklySectionNote()),
          _buildFocusInsightBlock(
            title: 'Produk Fokus',
            target: _toNum(weekly['target_fokus']),
            actual: _toNum(weekly['actual_fokus']),
            progressNote: 'Progress produk fokus ${_weeklySectionNote(lowercase: true)}',
          ),
          _buildSectionHead('Performa Promotor', _weeklySectionNote()),
          ..._promotorRows.take(5).map(_buildPromotorCard),
          Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _s1,
              borderRadius: BorderRadius.circular(_t.radiusMd),
              border: Border.all(color: _s3),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Laporan Mingguan Lengkap',
                      style: _outfit(size: 12, weight: FontWeight.w700),
                    ),
                    Text(
                      'AllType • Produk Fokus • Aktivitas • Vast Finance',
                      style: _outfit(size: 9, color: _muted),
                    ),
                  ],
                ),
                GestureDetector(
                  onTap: widget.onOpenLaporan,
                  child: Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: _gold,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (_frameIndex == 2) {
      final monthly = _monthlySummary ?? <String, dynamic>{};
      final monthlyPct = _toNum(monthly['target_omzet']) > 0
          ? (_toNum(monthly['actual_omzet']) *
                100 /
                _toNum(monthly['target_omzet']))
          : 0.0;
      return Column(
        children: [
          _buildHeroCard(),
          _buildSectionHead(
            'KPI Bulanan Tim',
            '${monthlyPct.toStringAsFixed(1)}%',
          ),
          _buildKpiRow(
            'Sell Out Tim',
            '${_formatCompactCurrency(_toNum(monthly['actual_omzet']))} / ${_formatCompactCurrency(_toNum(monthly['target_omzet']))}',
            _gold,
          ),
          _buildKpiRow(
            'Produk Fokus',
            '${_toInt(monthly['actual_fokus'])}/${_toInt(monthly['target_fokus'])} unit',
            _amber,
          ),
          _buildKpiRow(
            'Sell In',
            '${_formatCompactCurrency(_toNum(monthly['actual_sellin']))} / ${_formatCompactCurrency(_toNum(monthly['target_sellin']))}',
            _green,
          ),
          _buildSectionHead('Target Produk Fokus', note),
          _buildFocusInsightBlock(
            title: 'Produk Fokus',
            target: _toNum(monthly['target_fokus']),
            actual: _toNum(monthly['actual_fokus']),
            progressNote: 'Progress produk fokus bulan ini',
          ),
          _buildSectionHead('Ranking Promotor', note),
          _buildRankingState(),
          const SizedBox(height: 20),
        ],
      );
    }

    return Column(
      children: [
        _buildDailyHeroCard(),
        const SizedBox(height: 14),
        _buildDailyPromotorPreviewCard(),
        _buildSectionHead('Agenda Hari Ini', '${_agendaItems.length} item'),
        ..._agendaItems.map(_buildAgendaCard),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildDailyFocusContent() {
    final focusTarget = _toNum(_dailySummary?['target_fokus']);
    final focusActual = _toNum(
      _dailySummary?['actual_fokus'] ??
          _dailySummary?['actual_focus'] ??
          _dailySummary?['actual_daily_focus'],
    );
    return Container(
      margin: const EdgeInsets.only(top: 12),
      decoration: BoxDecoration(border: Border(top: BorderSide(color: _s3))),
      child: _buildFocusInsightBlock(
        title: 'Produk Fokus',
        target: focusTarget,
        actual: focusActual,
        progressNote: 'Progress produk fokus hari ini',
      ),
    );
  }

  Widget _buildMiniMetric(String label, double pct, Color color, String sub) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _s1,
        borderRadius: BorderRadius.circular(_t.radiusMd),
        border: Border.all(color: _s3),
      ),
      child: Column(
        children: [
          Text(
            label.toUpperCase(),
            style: _outfit(
              size: 7,
              weight: FontWeight.w700,
              color: _muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: 48,
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 4,
                  backgroundColor: _s3,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _s1.withValues(alpha: 0),
                  ),
                ),
                CircularProgressIndicator(
                  value: pct.clamp(0, 1),
                  strokeWidth: 4,
                  strokeCap: StrokeCap.round,
                  backgroundColor: _s1.withValues(alpha: 0),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
                Text(
                  '${pct.clamp(0, 100).toStringAsFixed(0)}%',
                  style: _display(
                    size: 12,
                    weight: FontWeight.w800,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(sub, style: _outfit(size: 8, color: color)),
        ],
      ),
    );
  }

  String _formatWeekRange(DateTime? start, DateTime? end) {
    if (start == null || end == null) return '-';
    final formatter = DateFormat('d MMM', 'id_ID');
    return '${formatter.format(start)} - ${formatter.format(end)}';
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  bool get _dailyPromotorRowsAvailable => _dailyPromotors.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      color: _gold,
      backgroundColor: _s1,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [_heroStart, _bg],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
              border: Border(bottom: BorderSide(color: _t.divider, width: 1.5)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Role label dengan dot glow
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _gold,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: _goldGlow,
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _profileRole,
                      style: _outfit(
                        size: 11,
                        weight: FontWeight.w700,
                        color: _gold,
                        letterSpacing: 1.4,
                      ),
                    ),
                    if (_profileArea.isNotEmpty && _profileArea != '-') ...[
                      const SizedBox(width: 6),
                      Container(
                        width: 1,
                        height: 10,
                        color: _gold.withValues(alpha: 0.3),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _profileArea,
                        style: _outfit(
                          size: 11,
                          weight: FontWeight.w600,
                          color: _cream2,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _profileName.toUpperCase(),
                  style: _display(size: 26, weight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat(
                        'EEEE, d MMM yyyy',
                        'id_ID',
                      ).format(DateTime.now()),
                      style: _outfit(size: 11, color: _muted),
                    ),
                    FieldSegmentedControl(
                      labels: const ['Harian', 'Mingguan', 'Bulanan'],
                      selectedIndex: _frameIndex,
                      onSelected: (index) =>
                          setState(() => _frameIndex = index),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _buildBody(),
        ],
      ),
    );
  }
}
