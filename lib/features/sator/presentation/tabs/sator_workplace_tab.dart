// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../ui/promotor/promotor.dart';

class SatorWorkplaceTab extends StatefulWidget {
  const SatorWorkplaceTab({super.key});

  @override
  State<SatorWorkplaceTab> createState() => _SatorWorkplaceTabState();
}

class _SatorWorkplaceTabState extends State<SatorWorkplaceTab> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profile;
  bool _isLoading = true;

  int _attendanceMissing = 0;
  int _attendanceTotal = 0;
  int _schedulePendingCount = 0;
  List<Map<String, String>> _schedulePending = [];

  bool _visitingDone = false;

  int _sellInPendingCount = 0;

  int _imeiPendingCount = 0;
  int _imeiPromotorCount = 0;

  final int _chipReviewCount = 0;
  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<List<dynamic>> _safeList(Future<dynamic> Function() loader) async {
    try {
      final result = await loader();
      if (result is List) return result;
      return [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final profile = await _supabase
          .from('users')
          .select('*')
          .eq('id', userId)
          .single();

      final hierarchyRows = await _safeList(
        () => _supabase
            .from('hierarchy_sator_promotor')
            .select('promotor_id')
            .eq('sator_id', userId)
            .eq('active', true),
      );
      final promotorIds = hierarchyRows
          .map((e) => '${e['promotor_id']}')
          .where((e) => e.isNotEmpty && e != 'null')
          .toList();

      _attendanceTotal = promotorIds.length;
      if (promotorIds.isNotEmpty) {
        final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
        final attendanceRows = await _safeList(
          () => _supabase
              .from('attendance')
              .select('user_id')
              .inFilter('user_id', promotorIds)
              .eq('attendance_date', today),
        );
        final presentIds = attendanceRows.map((e) => '${e['user_id']}').toSet();
        final missingIds = promotorIds
            .where((id) => !presentIds.contains(id))
            .toList();
        _attendanceMissing = missingIds.length;
      }

      final monthStart = DateTime(DateTime.now().year, DateTime.now().month, 1);
      if (promotorIds.isNotEmpty) {
        final scheduleRows = await _safeList(
          () => _supabase
              .from('schedules')
              .select(
                'promotor_id, status, created_at, month_year, users(full_name)',
              )
              .inFilter('promotor_id', promotorIds)
              .eq('status', 'submitted')
              .eq('month_year', DateFormat('yyyy-MM').format(monthStart))
              .order('created_at', ascending: false),
        );
        final latestByPromotor = <String, Map<String, dynamic>>{};
        for (final row in List<Map<String, dynamic>>.from(scheduleRows)) {
          final promotorId = row['promotor_id']?.toString() ?? '';
          if (promotorId.isEmpty || latestByPromotor.containsKey(promotorId)) {
            continue;
          }
          latestByPromotor[promotorId] = row;
        }
        final latestRows = latestByPromotor.values.toList();
        _schedulePendingCount = latestRows.length;
        _schedulePending = latestRows.take(3).map((row) {
          final name = row['users']?['full_name']?.toString() ?? 'Promotor';
          final created = DateTime.tryParse('${row['created_at'] ?? ''}');
          final label = _relativeDay(created);
          final monthYear = row['month_year']?.toString() ?? '';
          final monthLabel = monthYear.isEmpty
              ? DateFormat('MMM yyyy', 'id_ID').format(DateTime.now())
              : DateFormat(
                  'MMM yyyy',
                  'id_ID',
                ).format(DateTime.parse('$monthYear-01'));
          return {'name': '$name — $monthLabel', 'meta': label};
        }).toList();
      }

      final visitRows = await _safeList(
        () => _supabase
            .from('store_visits')
            .select('id, store_id, stores(store_name), visit_date')
            .eq('sator_id', userId)
            .eq('visit_date', DateFormat('yyyy-MM-dd').format(DateTime.now()))
            .order('created_at', ascending: false)
            .limit(1),
      );
      if (visitRows.isNotEmpty) {
        _visitingDone = true;
      } else {
        _visitingDone = false;
      }

      final pendingSellIn = await _supabase.rpc(
        'get_pending_orders',
        params: {'p_sator_id': userId},
      );
      _sellInPendingCount = pendingSellIn is List ? pendingSellIn.length : 0;

      if (promotorIds.isNotEmpty) {
        final imeiRows = await _safeList(
          () => _supabase
              .from('imei_normalizations')
              .select('id, promotor_id')
              .inFilter('promotor_id', promotorIds)
              .neq('status', 'scanned'),
        );
        _imeiPendingCount = imeiRows.length;
        _imeiPromotorCount = imeiRows
            .map((e) => '${e['promotor_id']}')
            .toSet()
            .length;
      }

      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _relativeDay(DateTime? date) {
    if (date == null) return 'Submit hari ini';
    final now = DateTime.now();
    final diff = now.difference(date).inDays;
    if (diff <= 0) return 'Submit hari ini';
    if (diff == 1) return 'Submit kemarin';
    return 'Submit $diff hari lalu';
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final completedTasks = _calculateCompletedTasks();
    final totalTasks = _calculateTotalTasks();
    final pct = totalTasks > 0 ? (completedTasks * 100 / totalTasks) : 0.0;

    return RefreshIndicator(
      onRefresh: _loadData,
      color: t.primaryAccent,
      child: Container(
        color: t.textOnAccent,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 120),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              _buildProgressCard(completedTasks, totalTasks, pct),
              _buildTimeline(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final fullNameRaw = '${_profile?['full_name'] ?? ''}'.trim();
    final fullName = fullNameRaw.isEmpty ? 'Sator' : fullNameRaw;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: t.primaryAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Ruang Kerja',
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: t.primaryAccent,
                      letterSpacing: 1.4,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                fullName,
                style: PromotorText.display(size: 24, color: t.textPrimary),
              ),
            ],
          ),
          _buildHeaderIconButton(),
        ],
      ),
    );
  }

  Widget _buildHeaderIconButton() {
    return Stack(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: t.surface3),
          ),
          child: Icon(
            Icons.notifications_none_rounded,
            color: t.textMuted,
            size: 16,
          ),
        ),
        Positioned(
          top: 7,
          right: 7,
          child: Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: t.danger, shape: BoxShape.circle),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressCard(int done, int total, double pct) {
    return Container(
      margin: EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [t.surface2, t.background],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.primaryAccentGlow),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Progress tugas hari ini',
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: t.textMuted,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$done dari $total selesai',
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${pct.toStringAsFixed(0)}%',
                    style: PromotorText.display(
                      size: 30,
                      color: t.textMutedStrong,
                    ),
                  ),
                  Text(
                    'Selesai',
                    style: PromotorText.outfit(
                      size: 8,
                      weight: FontWeight.w700,
                      color: t.textMuted,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildThinProgress(pct / 100, t.primaryAccent),
        ],
      ),
    );
  }

  Widget _buildThinProgress(double value, Color color) {
    return Container(
      height: 4,
      decoration: BoxDecoration(
        color: t.surface3,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Container(
          width: 280 * value.clamp(0.0, 1.0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            gradient: LinearGradient(colors: [color, t.primaryAccentLight]),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeline() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildGroupTitle('Pengawasan Tim'),
          _buildTimelineItem(
            title: 'Aktivitas Tim',
            badge: _attendanceMissing > 0
                ? '$_attendanceMissing belum absen'
                : '✓ Lengkap',
            badgeColor: _attendanceMissing > 0 ? t.danger : t.success,
            dotColor: _attendanceMissing > 0 ? t.danger : t.success,
            icon: Icons.people_outline,
            onTap: () => context.push('/sator/aktivitas-tim'),
          ),
          _buildTimelineItem(
            title: 'Approve Jadwal',
            badge: _schedulePendingCount > 0
                ? '$_schedulePendingCount pending'
                : '✓ Aman',
            badgeColor: _schedulePendingCount > 0 ? t.primaryAccent : t.success,
            dotColor: _schedulePendingCount > 0 ? t.primaryAccent : t.success,
            icon: Icons.calendar_month,
            pendingList: _schedulePending,
            onTap: () => context.push('/sator/jadwal'),
          ),
          _buildTimelineItem(
            title: 'Visiting',
            badge: _visitingDone ? '✓ Selesai' : 'Pending',
            badgeColor: _visitingDone ? t.success : t.danger,
            dotColor: _visitingDone ? t.success : t.danger,
            icon: _visitingDone ? Icons.check : Icons.location_on_outlined,
            chips: _visitingDone
                ? ['Cek stok ✓', 'Coaching ✓']
                : ['Belum dilakukan'],
            onTap: () => context.push('/sator/visiting'),
          ),
          const SizedBox(height: 8),
          _buildGroupTitle('Stok & Order'),
          _buildTimelineItem(
            title: 'Sell In',
            badge: _sellInPendingCount > 0
                ? '$_sellInPendingCount pending'
                : '✓ Aman',
            badgeColor: _sellInPendingCount > 0 ? t.primaryAccent : t.success,
            dotColor: _sellInPendingCount > 0 ? t.primaryAccent : t.success,
            icon: Icons.inventory_2_outlined,
            chips: ['Stok Gudang · Stok Toko · Finalisasi'],
            onTap: () => context.push('/sator/sell-in'),
          ),
          const SizedBox(height: 8),
          _buildGroupTitle('Laporan & Data'),
          _buildTimelineItem(
            title: 'AllBrand',
            badge: 'Rekap tim',
            badgeColor: t.textMuted,
            dotColor: Color.lerp(t.info, t.primaryAccentLight, 0.55)!,
            icon: Icons.bar_chart,
            chips: ['Samsung · OPPO · Xiaomi'],
            onTap: () => context.push('/sator/allbrand'),
          ),
          _buildTimelineItem(
            title: 'VAST Finance',
            badge: 'Monitor tim',
            badgeColor: t.primaryAccent,
            dotColor: t.primaryAccent,
            icon: Icons.account_balance_wallet_outlined,
            chips: ['Harian', 'Alert', 'Export'],
            onTap: () => context.pushNamed('sator-vast'),
          ),
          _buildTimelineItem(
            title: 'Penormalan IMEI',
            badge: _imeiPendingCount > 0
                ? '$_imeiPendingCount pending'
                : '✓ Aman',
            badgeColor: _imeiPendingCount > 0 ? t.warning : t.success,
            dotColor: Color.lerp(t.info, t.primaryAccentLight, 0.55)!,
            icon: Icons.qr_code_2,
            chips: [
              _imeiPendingCount > 0
                  ? '$_imeiPromotorCount promotor · $_imeiPendingCount unit'
                  : 'Tidak ada pending',
            ],
            onTap: () => context.push('/sator/imei-normalisasi'),
          ),
          _buildTimelineItem(
            title: 'Stock Management',
            badge: 'Terpadu',
            badgeColor: t.textMuted,
            dotColor: t.primaryAccent,
            icon: Icons.memory,
            chips: [
              _chipReviewCount > 0
                  ? '$_chipReviewCount request chip pending'
                  : 'Tidak ada chip pending',
              'Validasi harian',
              'Pindah stok',
            ],
            onTap: () => context.push('/sator/stock-management'),
          ),
          _buildTimelineItem(
            title: 'Export',
            badge: 'Download',
            badgeColor: t.textMuted,
            dotColor: t.info,
            icon: Icons.file_download,
            chips: ['PDF', 'Excel'],
            onTap: () => context.push('/sator/export'),
            showLine: false,
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 32, bottom: 10, top: 4),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: PromotorText.outfit(
              size: 8,
              weight: FontWeight.w800,
              color: t.textMutedStrong,
              letterSpacing: 1.6,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1, color: t.surface2)),
        ],
      ),
    );
  }

  Widget _buildTimelineItem({
    required String title,
    required String badge,
    required Color badgeColor,
    required Color dotColor,
    required IconData icon,
    List<String>? chips,
    List<Map<String, String>>? pendingList,
    VoidCallback? onTap,
    bool showLine = true,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: dotColor.withValues(alpha: 0.08),
        highlightColor: dotColor.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: dotColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: dotColor.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(icon, color: dotColor, size: 15),
                  ),
                  if (showLine)
                    Container(
                      width: 1,
                      height: 16,
                      margin: const EdgeInsets.symmetric(vertical: 3),
                      color: t.surface3.withValues(alpha: 0.6),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w700,
                                color: badgeColor == t.success
                                    ? t.success
                                    : t.textSecondary,
                              ),
                            ),
                          ),
                          _buildBadge(badge, badgeColor),
                        ],
                      ),
                      if (chips != null && chips.isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Wrap(
                          spacing: 5,
                          runSpacing: 4,
                          children: chips
                              .map((chip) => _buildChip(chip))
                              .toList(),
                        ),
                      ],
                      if (pendingList != null && pendingList.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        _buildPendingList(pendingList),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 8,
          weight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 8,
          weight: FontWeight.w600,
          color: t.textMutedStrong,
        ),
      ),
    );
  }

  Widget _buildPendingList(List<Map<String, String>> rows) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: rows.map((row) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: t.surface3.withValues(alpha: 0.2)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row['name'] ?? '-',
                      style: PromotorText.outfit(
                        size: 15,
                        weight: FontWeight.w600,
                        color: t.textSecondary,
                      ),
                    ),
                    Text(
                      row['meta'] ?? '-',
                      style: PromotorText.outfit(
                        size: 8,
                        weight: FontWeight.w700,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
                Text(
                  row['action'] ?? 'Lihat →',
                  style: PromotorText.outfit(
                    size: 8,
                    weight: FontWeight.w700,
                    color: t.primaryAccent,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  int _calculateCompletedTasks() {
    int done = 0;
    if (_attendanceMissing == 0 && _attendanceTotal > 0) done += 1;
    if (_schedulePendingCount == 0) done += 1;
    if (_visitingDone) done += 1;
    if (_sellInPendingCount == 0) done += 1;
    if (_imeiPendingCount == 0) done += 1;
    if (_chipReviewCount == 0) done += 1;
    return done;
  }

  int _calculateTotalTasks() {
    return 6;
  }
}
