import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:vtrack/core/utils/success_dialog.dart';
import '../../../../ui/foundation/app_text_style.dart';
import '../../../../ui/promotor/promotor.dart';

class AktivitasHarianPage extends StatefulWidget {
  const AktivitasHarianPage({super.key});

  @override
  State<AktivitasHarianPage> createState() => _AktivitasHarianPageState();
}

class _AktivitasHarianPageState extends State<AktivitasHarianPage>
    with SingleTickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  late final TabController _tabController;

  // Activity data
  Map<String, dynamic>? _attendanceData;
  Map<String, dynamic>? _clockOutData;
  List<Map<String, dynamic>> _sellOutData = [];
  final Map<String, Map<String, dynamic>> _sellOutVoidRequestBySaleId = {};
  List<Map<String, dynamic>> _stockInputData = [];
  Map<String, dynamic>? _stockValidationData;
  List<Map<String, dynamic>> _promotionData = [];
  List<Map<String, dynamic>> _followerData = [];
  Map<String, dynamic>? _allBrandData;

  // Monthly rekap data
  int _monthlyAttendanceCount = 0;
  int _monthlyPermissionCount = 0;
  int _monthlyPromotionCount = 0;
  int _monthlyFollowerReportCount = 0;
  Map<String, int> _monthlyPermissionTypeCounts = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadAllActivities();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAllActivities() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          setState(() => _isLoading = false);
        }
        return;
      }

      final snapshot = await Supabase.instance.client.rpc(
        'get_promotor_activity_snapshot',
        params: {'p_date': DateFormat('yyyy-MM-dd').format(_selectedDate)},
      );
      final payload = Map<String, dynamic>.from(
        (snapshot as Map?) ?? const <String, dynamic>{},
      );

      _attendanceData = _asMap(payload['attendance_data']);
      _clockOutData = _asMap(payload['clock_out_data']);
      _sellOutData = _asListOfMaps(payload['sell_out_data']);
      _stockInputData = _asListOfMaps(payload['stock_input_data']);
      _stockValidationData = _asMap(payload['stock_validation_data']);
      _promotionData = _asListOfMaps(payload['promotion_data']);
      _followerData = _asListOfMaps(payload['follower_data']);
      _allBrandData = _asMap(payload['all_brand_data']);
      _monthlyAttendanceCount = _asInt(payload['monthly_attendance_count']);

      final monthStart = DateTime(
        _selectedDate.year,
        _selectedDate.month,
        1,
      );
      final monthEnd = DateTime(
        _selectedDate.year,
        _selectedDate.month + 1,
        1,
      );
      final monthStartDate = DateFormat('yyyy-MM-dd').format(monthStart);
      final monthEndDate = DateFormat('yyyy-MM-dd').format(monthEnd);
      final monthStartTs = monthStart.toIso8601String();
      final monthEndTs = monthEnd.toIso8601String();

      final monthlyRows = await Future.wait([
        Supabase.instance.client
            .from('permission_requests')
            .select('request_type')
            .eq('promotor_id', userId)
            .gte('request_date', monthStartDate)
            .lt('request_date', monthEndDate),
        Supabase.instance.client
            .from('promotion_reports')
            .select('id')
            .eq('promotor_id', userId)
            .gte('created_at', monthStartTs)
            .lt('created_at', monthEndTs),
        Supabase.instance.client
            .from('follower_reports')
            .select('id')
            .eq('promotor_id', userId)
            .gte('created_at', monthStartTs)
            .lt('created_at', monthEndTs),
      ]);

      final permissionRows = _asListOfMaps(monthlyRows[0]);
      final permissionTypeCounts = <String, int>{};
      for (final row in permissionRows) {
        final rawType = '${row['request_type'] ?? ''}'.trim();
        if (rawType.isEmpty) continue;
        final label = _permissionTypeLabel(rawType);
        permissionTypeCounts[label] = (permissionTypeCounts[label] ?? 0) + 1;
      }

      _monthlyPermissionCount = permissionRows.length;
      _monthlyPromotionCount = _asListOfMaps(monthlyRows[1]).length;
      _monthlyFollowerReportCount = _asListOfMaps(monthlyRows[2]).length;
      _monthlyPermissionTypeCounts = permissionTypeCounts;

      _sellOutVoidRequestBySaleId
        ..clear()
        ..addEntries(
          _asListOfMaps(payload['sell_out_void_requests'])
              .map((row) {
                final saleId = '${row['sale_id'] ?? ''}';
                return MapEntry(saleId, row);
              })
              .where((entry) => entry.key.isNotEmpty),
        );

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Error loading activities: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _changeDate(int days) {
    setState(() {
      _selectedDate = _selectedDate.add(Duration(days: days));
    });
    _loadAllActivities();
  }

  Future<void> _submitSellOutVoidRequest({
    required dynamic saleId,
    required String reason,
  }) async {
    final client = Supabase.instance.client;

    try {
      await client.rpc(
        'request_sell_out_void',
        params: {
          'p_sale_id': saleId,
          'p_reason': reason,
        },
      );
      return;
    } on PostgrestException catch (error) {
      debugPrint(
        '[AjukanBatal][RPC] message=${error.message} code=${error.code} details=${error.details} hint=${error.hint}',
      );
      final message = error.message.toLowerCase();
      final isRpcSignatureIssue =
          message.contains('request_sell_out_void') &&
          (message.contains('schema cache') ||
              message.contains('matches the given name') ||
              message.contains('argument types'));

      if (!isRpcSignatureIssue) rethrow;
      debugPrint(
        '[AjukanBatal][RPC] fallback insert activated for sale_id=$saleId',
      );
    }

    final userId = client.auth.currentUser?.id;
    if (userId == null) {
      throw StateError('User belum login.');
    }

    await client.from('sell_out_void_requests').insert({
      'sale_id': saleId,
      'promotor_id': userId,
      'requested_by': userId,
      'reason': reason,
      'status': 'pending',
    });
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadAllActivities();
    }
  }

  int get _completedTasks {
    int count = 0;
    if (_attendanceData != null) count++;
    if (_sellOutData.isNotEmpty) count++;
    if (_stockInputData.isNotEmpty || _stockValidationData != null) count++;
    if (_promotionData.isNotEmpty) count++;
    if (_followerData.isNotEmpty) count++;
    if (_allBrandData != null) count++;
    return count;
  }

  int get _totalTasks => 6;

  String get _headerDateLabel {
    return DateFormat('d MMM', 'id_ID').format(_selectedDate);
  }

  Map<String, dynamic>? _asMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, val) => MapEntry(key.toString(), val));
    }
    return null;
  }

  List<Map<String, dynamic>> _asListOfMaps(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => row.map((key, val) => MapEntry(key.toString(), val)))
        .toList();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('$value') ?? 0;
  }

  String _permissionTypeLabel(String rawType) {
    switch (rawType.toLowerCase()) {
      case 'sick':
        return 'Izin Sakit';
      case 'personal':
        return 'Izin Pribadi';
      case 'other':
        return 'Izin Lainnya';
      default:
        return rawType;
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final isToday =
        DateFormat('yyyy-MM-dd').format(_selectedDate) ==
        DateFormat('yyyy-MM-dd').format(DateTime.now());

    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: Container(
        color: t.background,
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                decoration: BoxDecoration(
                  color: t.background,
                  border: Border(bottom: BorderSide(color: t.surface2)),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        InkWell(
                          onTap: () => Navigator.of(context).maybePop(),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: t.surface1,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: t.surface3),
                            ),
                            child: Icon(
                              Icons.arrow_back_ios_new_rounded,
                              color: t.textSecondary,
                              size: 17,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Laporan Aktivitas',
                            style: PromotorText.display(
                              size: 17,
                              color: t.textPrimary,
                            ),
                          ),
                        ),
                        _buildHeaderDateControl(isToday),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _buildIosSegmentedTabs(),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [_buildDailyTab(isToday), _buildMonthlyTab()],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIosSegmentedTabs() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          _buildSegmentItem('Harian', 0),
          _buildSegmentItem('Rekap Bulanan', 1),
        ],
      ),
    );
  }

  Widget _buildSegmentItem(String label, int index) {
    final isSelected = _tabController.index == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tabController.index = index),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          margin: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: isSelected
                ? t.primaryAccentSoft
                : t.surface1.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isSelected
                  ? t.primaryAccent
                  : t.surface1.withValues(alpha: 0),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: PromotorText.outfit(
                size: 10,
                weight: FontWeight.w700,
                color: isSelected ? t.primaryAccent : t.textMuted,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDailyTab(bool isToday) {
    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [t.surface2, t.background]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.primaryAccentGlow),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primaryAccentSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$_completedTasks/$_totalTasks',
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w800,
                    color: t.primaryAccent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _completedTasks == _totalTasks
                      ? 'Semua tugas selesai'
                      : '$_completedTasks dari $_totalTasks tugas selesai',
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
              : RefreshIndicator(
                  onRefresh: _loadAllActivities,
                  color: t.primaryAccent,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      _buildClockInCard(),
                      const SizedBox(height: 8),
                      _buildSellOutCard(),
                      const SizedBox(height: 8),
                      _buildStockCard(),
                      const SizedBox(height: 8),
                      _buildPromotionCard(),
                      const SizedBox(height: 8),
                      _buildFollowerCard(),
                      const SizedBox(height: 8),
                      _buildAllBrandCard(),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildHeaderDateControl(bool isToday) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _changeDate(-1),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.chevron_left_rounded,
              size: 18,
              color: t.textSecondary,
            ),
          ),
        ),
        InkWell(
          onTap: _selectDate,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: isToday ? t.primaryAccentGlow : t.surface3,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.calendar_today_rounded,
                  size: 12,
                  color: t.textMutedStrong,
                ),
                const SizedBox(width: 6),
                Text(
                  _headerDateLabel,
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        InkWell(
          onTap: isToday ? null : () => _changeDate(1),
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 18,
              color: isToday ? t.textMutedStrong : t.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonthlyTab() {
    final monthName = DateFormat('MMMM yyyy', 'id_ID').format(_selectedDate);
    final permissionTypeText = _monthlyPermissionTypeCounts.isEmpty
        ? 'Belum ada izin.'
        : _monthlyPermissionTypeCounts.entries
              .map((entry) => '${entry.key} (${entry.value})')
              .join(', ');
    final monthlyDoneCount = [
      _monthlyAttendanceCount > 0,
      _monthlyPermissionCount > 0,
      _monthlyPromotionCount > 0,
      _monthlyFollowerReportCount > 0,
    ].where((done) => done).length;

    return Column(
      children: [
        Container(
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [t.surface2, t.background]),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: t.primaryAccentGlow),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: t.primaryAccentSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$monthlyDoneCount/4',
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w800,
                    color: t.primaryAccent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Rekap $monthName',
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w700,
                    color: t.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
              : RefreshIndicator(
                  onRefresh: _loadAllActivities,
                  color: t.primaryAccent,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      _buildActivityCard(
                        title: 'Absen Masuk Kerja',
                        icon: Icons.calendar_month,
                        color: t.info,
                        isDone: _monthlyAttendanceCount > 0,
                        content: _monthlyAttendanceCount > 0
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _compactMetricRow(
                                    'Jumlah',
                                    '$_monthlyAttendanceCount Hari',
                                    tone: t.info,
                                  ),
                                  _compactMetricRow(
                                    'Periode',
                                    monthName,
                                    tone: t.textPrimary,
                                  ),
                                  _compactMetricRow(
                                    'Status',
                                    'Tercatat',
                                    tone: t.success,
                                  ),
                                ],
                              )
                            : _buildCompactEmpty('Belum ada absen bulan ini'),
                      ),
                      const SizedBox(height: 8),
                      _buildActivityCard(
                        title: 'Izin',
                        icon: Icons.assignment_late_outlined,
                        color: t.warning,
                        isDone: _monthlyPermissionCount > 0,
                        content: _monthlyPermissionCount > 0
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _compactMetricRow(
                                    'Jumlah',
                                    '$_monthlyPermissionCount Kali',
                                    tone: t.warning,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    permissionTypeText,
                                    style: PromotorText.outfit(
                                      size: 11,
                                      weight: FontWeight.w700,
                                      color: t.textPrimary,
                                    ),
                                  ),
                                ],
                              )
                            : _buildCompactEmpty('Belum ada izin bulan ini'),
                      ),
                      const SizedBox(height: 8),
                      _buildActivityCard(
                        title: 'Laporan Promosi Medsos',
                        icon: Icons.campaign_outlined,
                        color: t.success,
                        isDone: _monthlyPromotionCount > 0,
                        content: _monthlyPromotionCount > 0
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _compactMetricRow(
                                    'Jumlah',
                                    '$_monthlyPromotionCount Kali',
                                    tone: t.success,
                                  ),
                                  _compactMetricRow(
                                    'Status',
                                    'Terkirim',
                                    tone: t.success,
                                  ),
                                ],
                              )
                            : _buildCompactEmpty(
                                'Belum ada laporan promosi bulan ini',
                              ),
                      ),
                      const SizedBox(height: 8),
                      _buildActivityCard(
                        title: 'Laporan Followers',
                        icon: Icons.group_add_outlined,
                        color: t.primaryAccentLight,
                        isDone: _monthlyFollowerReportCount > 0,
                        content: _monthlyFollowerReportCount > 0
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _compactMetricRow(
                                    'Jumlah',
                                    '$_monthlyFollowerReportCount Kali',
                                    tone: t.primaryAccentLight,
                                  ),
                                  _compactMetricRow(
                                    'Status',
                                    'Terkirim',
                                    tone: t.success,
                                  ),
                                ],
                              )
                            : _buildCompactEmpty(
                                'Belum ada laporan follower bulan ini',
                              ),
                      ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildActivityCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDone,
    required Widget content,
  }) {
    final panelColor = isDone ? color.withValues(alpha: 0.07) : t.surface1;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      decoration: BoxDecoration(
        color: panelColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDone ? color.withValues(alpha: 0.22) : t.surface3,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: isDone ? color.withValues(alpha: 0.14) : t.surface2,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: isDone ? color : t.textMutedStrong,
              size: 14,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PromotorText.outfit(
                          size: 12,
                          weight: FontWeight.w700,
                          color: isDone ? color : t.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isDone ? 'Selesai' : 'Belum',
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w700,
                        color: isDone ? t.success : t.danger,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Theme(
                  data: Theme.of(
                    context,
                  ).copyWith(cardColor: t.surface2, dividerColor: t.surface3),
                  child: DefaultTextStyle.merge(
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                    child: content,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClockInCard() {
    final isDone = _attendanceData != null;
    final mainStatus = '${_attendanceData?['main_attendance_status'] ?? ''}';
    final statusText = mainStatus == 'late'
        ? 'Terlambat'
        : mainStatus == 'on_time'
        ? 'Tepat Waktu'
        : 'Laporan terkirim';

    return _buildActivityCard(
      title: 'Kehadiran',
      icon: Icons.login,
      color: t.info,
      isDone: isDone,
      content: isDone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _compactMetricRow(
                  'Masuk',
                  DateFormat('HH:mm').format(
                    DateTime.parse(_attendanceData!['created_at']).toLocal(),
                  ),
                  tone: t.info,
                ),
                _compactMetricRow(
                  'Status',
                  statusText,
                  tone: mainStatus == 'late' ? t.warning : t.success,
                ),
                _compactMetricRow(
                  'Pulang',
                  _clockOutData == null
                      ? '-'
                      : DateFormat('HH:mm').format(
                          DateTime.parse(
                            _clockOutData!['created_at'],
                          ).toLocal(),
                        ),
                  tone: _clockOutData == null ? t.textMutedStrong : t.success,
                ),
              ],
            )
          : _buildCompactEmpty('Belum ada kehadiran'),
    );
  }

  Widget _buildSellOutCard() {
    final isDone = _sellOutData.isNotEmpty;
    final totalValue = _sellOutData.fold<num>(
      0,
      (sum, item) => sum + (item['price_at_transaction'] ?? 0),
    );
    final pendingVoidCount = _sellOutVoidRequestBySaleId.values
        .where((row) => '${row['status'] ?? ''}' == 'pending')
        .length;
    final latestSale = isDone ? _sellOutData.first : null;

    return _buildActivityCard(
      title: 'Penjualan (Sell Out)',
      icon: Icons.shopping_cart,
      color: t.success,
      isDone: isDone,
      content: isDone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _compactMetricRow(
                  'Unit',
                  '${_sellOutData.length}',
                  tone: t.success,
                ),
                _compactMetricRow(
                  'Nilai',
                  'Rp ${NumberFormat('#,###', 'id_ID').format(totalValue)}',
                  tone: t.textPrimary,
                ),
                _compactMetricRow(
                  'Batal',
                  pendingVoidCount == 0 ? '-' : '$pendingVoidCount pending',
                  tone: pendingVoidCount == 0 ? t.textMutedStrong : t.warning,
                ),
                if (latestSale != null)
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: () =>
                          _showSellOutVoidRequestDialog(latestSale),
                      icon: const Icon(
                        Icons.cancel_schedule_send_rounded,
                        size: 14,
                      ),
                      label: const Text('Ajukan batal'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 30),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        backgroundColor: t.warningSoft,
                        foregroundColor: t.warning,
                        textStyle: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w700,
                        ),
                        visualDensity: const VisualDensity(
                          horizontal: -3,
                          vertical: -3,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(999),
                          side: BorderSide(
                            color: t.warning.withValues(alpha: 0.2),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            )
          : _buildCompactEmpty('Belum ada penjualan'),
    );
  }

  Future<void> _showSellOutVoidRequestDialog(Map<String, dynamic> item) async {
    final rootContext = context;
    final reasonController = TextEditingController();
    var isSubmitting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (_, setDialogState) {
            return AlertDialog(
              title: const Text('Ajukan batal transaksi'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Pengajuan batal akan masuk ke antrean review SATOR atau SPV. Setelah disetujui, input ulang transaksi yang benar.',
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: reasonController,
                    enabled: !isSubmitting,
                    minLines: 3,
                    maxLines: 4,
                    cursorColor: t.textPrimary,
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                    decoration: InputDecoration(
                      labelText: 'Alasan pembatalan',
                      labelStyle: PromotorText.outfit(
                        size: 15,
                        weight: FontWeight.w700,
                        color: t.textMuted,
                      ),
                      hintStyle: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: t.textMutedStrong,
                      ),
                      filled: true,
                      fillColor: t.surface1,
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.surface3),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.primaryAccent),
                      ),
                      errorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.danger),
                      ),
                      focusedErrorBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(color: t.danger),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Tutup'),
                ),
                FilledButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          final reason = reasonController.text.trim();
                          if (reason.isEmpty) return;
                          setDialogState(() => isSubmitting = true);
                          try {
                            await _submitSellOutVoidRequest(
                              saleId: item['id'],
                              reason: reason,
                            );
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            await showSuccessDialog(
                              rootContext,
                              title: 'Berhasil',
                              message: 'Pengajuan batal berhasil dikirim.',
                            );
                            await _loadAllActivities();
                          } catch (e, stackTrace) {
                            debugPrint(
                              '[AjukanBatal][UI] sale_id=${item['id']} reason="$reason" error=$e',
                            );
                            debugPrintStack(
                              label: '[AjukanBatal][UI][STACK]',
                              stackTrace: stackTrace,
                            );
                            if (!mounted || !rootContext.mounted) return;
                            ScaffoldMessenger.of(rootContext).showSnackBar(
                              SnackBar(
                                content: Text('Gagal mengajukan batal: $e'),
                              ),
                            );
                            setDialogState(() => isSubmitting = false);
                          }
                        },
                  child: const Text('Kirim'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildStockCard() {
    final hasInput = _stockInputData.isNotEmpty;
    final hasValidation = _stockValidationData != null;
    final isDone = hasInput || hasValidation;

    return _buildActivityCard(
      title: 'Stok',
      icon: Icons.inventory,
      color: t.warning,
      isDone: isDone,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _compactMetricRow(
            'Input stok',
            hasInput ? '${_stockInputData.length} item' : 'Belum',
            tone: hasInput ? t.warning : t.textMutedStrong,
          ),
          _compactMetricRow(
            'Validasi toko',
            hasValidation ? 'Selesai' : 'Belum',
            tone: hasValidation ? t.success : t.textMutedStrong,
          ),
          _compactMetricRow(
            'Ringkas',
            hasInput && hasValidation ? 'Lengkap' : 'Perlu cek',
            tone: hasInput && hasValidation ? t.success : t.warning,
          ),
        ],
      ),
    );
  }

  Widget _buildPromotionCard() {
    final isDone = _promotionData.isNotEmpty;
    final platforms = _promotionData
        .map((item) => '${item['platform'] ?? '-'}'.toUpperCase())
        .toSet()
        .toList();

    return _buildActivityCard(
      title: 'Laporan Promosi',
      icon: Icons.campaign,
      color: t.primaryAccentLight,
      isDone: isDone,
      content: isDone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _compactMetricRow(
                  'Postingan',
                  '${_promotionData.length}',
                  tone: t.primaryAccent,
                ),
                _compactMetricRow(
                  'Platform',
                  platforms.isEmpty ? '-' : platforms.take(2).join(', '),
                  tone: t.textPrimary,
                ),
                _compactMetricRow('Status', 'Terkirim', tone: t.success),
              ],
            )
          : _buildCompactEmpty('Belum ada promosi'),
    );
  }

  Widget _buildFollowerCard() {
    final isDone = _followerData.isNotEmpty;
    final totalFollower = _followerData.fold<int>(
      0,
      (sum, item) => sum + ((item['follower_count'] ?? 0) as num).toInt(),
    );

    return _buildActivityCard(
      title: 'Laporan Follower',
      icon: Icons.person_add,
      color: t.info,
      isDone: isDone,
      content: isDone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _compactMetricRow(
                  'Laporan',
                  '${_followerData.length}',
                  tone: t.info,
                ),
                _compactMetricRow(
                  'Total follower',
                  '$totalFollower',
                  tone: t.textPrimary,
                ),
                _compactMetricRow('Status', 'Terkirim', tone: t.success),
              ],
            )
          : _buildCompactEmpty('Belum ada follower'),
    );
  }

  Widget _buildAllBrandCard() {
    final isDone = _allBrandData != null;

    return _buildActivityCard(
      title: 'Laporan AllBrand',
      icon: Icons.analytics,
      color: t.primaryAccent,
      isDone: isDone,
      content: isDone
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _compactMetricRow('Laporan', 'Sudah masuk', tone: t.success),
                _compactMetricRow(
                  'Jam',
                  DateFormat('HH:mm').format(
                    DateTime.parse(_allBrandData!['created_at']).toLocal(),
                  ),
                  tone: t.primaryAccent,
                ),
                _compactMetricRow('Status', 'Siap dicek', tone: t.textPrimary),
              ],
            )
          : _buildCompactEmpty('Belum ada allbrand'),
    );
  }

  Widget _compactMetricRow(String label, String value, {required Color tone}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyle.bodySm(
              t.textMutedStrong,
              weight: FontWeight.w700,
            ).copyWith(fontSize: 10),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: AppTextStyle.bodyMd(
              tone,
              weight: FontWeight.w800,
            ).copyWith(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactEmpty(String text) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: AppTextStyle.bodyMd(
          t.textMutedStrong,
          weight: FontWeight.w700,
        ).copyWith(fontSize: 11),
      ),
    );
  }
}
