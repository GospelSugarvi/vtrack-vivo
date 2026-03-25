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
  int _monthlySellOutCount = 0;
  int _monthlyValidationCount = 0;
  double _monthlyFollowerIncrease = 0;

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

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final nextDateStr = DateFormat(
        'yyyy-MM-dd',
      ).format(_selectedDate.add(const Duration(days: 1)));

      // Load Kehadiran / Laporan Masuk
      try {
        final attendance = await Supabase.instance.client
            .from('attendance')
            .select('*')
            .eq('user_id', userId)
            .eq('attendance_date', dateStr)
            .order('clock_in', ascending: false)
            .limit(1)
            .maybeSingle();
        _attendanceData = attendance;
      } catch (e) {
        debugPrint('Error loading attendance: $e');
      }

      // Load Clock Out
      try {
        final clockOut = await Supabase.instance.client
            .from('attendance')
            .select('*')
            .eq('user_id', userId)
            .eq('attendance_date', dateStr)
            .not('clock_out', 'is', null)
            .order('clock_out', ascending: false)
            .limit(1)
            .maybeSingle();
        _clockOutData = clockOut;
      } catch (e) {
        debugPrint('Error loading clock out: $e');
      }

      // Load Sell Out
      try {
        debugPrint('=== LOADING SELL OUT for date: $dateStr ===');
        final sellOut = await Supabase.instance.client
            .from('sales_sell_out')
            .select('*')
            .eq('promotor_id', userId)
            .isFilter('deleted_at', null)
            .gte('transaction_date', dateStr)
            .lt('transaction_date', nextDateStr);
        _sellOutData = List<Map<String, dynamic>>.from(sellOut);
        _sellOutVoidRequestBySaleId.clear();
        final saleIds = _sellOutData
            .map((e) => '${e['id'] ?? ''}')
            .where((e) => e.isNotEmpty)
            .toList();
        if (saleIds.isNotEmpty) {
          final requests = await Supabase.instance.client
              .from('sell_out_void_requests')
              .select('*')
              .inFilter('sale_id', saleIds)
              .order('requested_at', ascending: false);
          for (final row in List<Map<String, dynamic>>.from(requests)) {
            final saleId = '${row['sale_id'] ?? ''}';
            if (saleId.isEmpty ||
                _sellOutVoidRequestBySaleId.containsKey(saleId)) {
              continue;
            }
            _sellOutVoidRequestBySaleId[saleId] = row;
          }
        }
        debugPrint('=== SELL OUT DATA COUNT: ${_sellOutData.length} ===');
        if (_sellOutData.isNotEmpty) {
          debugPrint('=== SELL OUT SAMPLE: ${_sellOutData.first} ===');
        }
      } catch (e) {
        debugPrint('=== ERROR loading sell out: $e ===');
      }

      // Load Stock Input
      try {
        debugPrint('=== LOADING STOCK INPUT for date: $dateStr ===');
        final stockInput = await Supabase.instance.client
            .from('stock_movement_log')
            .select('*')
            .eq('moved_by', userId)
            .inFilter('movement_type', ['initial', 'transfer_in', 'adjustment'])
            .gte('moved_at', dateStr)
            .lt('moved_at', nextDateStr);
        _stockInputData = List<Map<String, dynamic>>.from(stockInput);
        debugPrint('=== STOCK INPUT DATA COUNT: ${_stockInputData.length} ===');
        if (_stockInputData.isNotEmpty) {
          debugPrint('=== STOCK INPUT SAMPLE: ${_stockInputData.first} ===');
        }
      } catch (e) {
        debugPrint('=== ERROR loading stock input: $e ===');
      }

      // Load Stock Validation
      try {
        debugPrint('=== LOADING STOCK VALIDATION for date: $dateStr ===');
        final stockValidation = await Supabase.instance.client
            .from('stock_validations')
            .select('*')
            .eq('promotor_id', userId)
            .gte('created_at', dateStr)
            .lt('created_at', nextDateStr)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();
        _stockValidationData = stockValidation;
        debugPrint(
          '=== STOCK VALIDATION: ${_stockValidationData != null ? "Found" : "Not found"} ===',
        );
      } catch (e) {
        debugPrint('=== ERROR loading stock validation: $e ===');
      }

      // Load Promotion Reports
      try {
        final promotions = await Supabase.instance.client
            .from('promotion_reports')
            .select('*')
            .eq('promotor_id', userId)
            .gte('created_at', dateStr)
            .lt('created_at', nextDateStr);
        _promotionData = List<Map<String, dynamic>>.from(promotions);
      } catch (e) {
        debugPrint('Error loading promotions: $e');
      }

      // Load Follower Reports
      try {
        final followers = await Supabase.instance.client
            .from('follower_reports')
            .select('*')
            .eq('promotor_id', userId)
            .gte('created_at', dateStr)
            .lt('created_at', nextDateStr);
        _followerData = List<Map<String, dynamic>>.from(followers);
      } catch (e) {
        debugPrint('Error loading followers: $e');
      }

      // Load AllBrand Report
      try {
        final allBrand = await Supabase.instance.client
            .from('allbrand_reports')
            .select('*')
            .eq('promotor_id', userId)
            .gte('report_date', dateStr)
            .lt('report_date', nextDateStr)
            .maybeSingle();
        _allBrandData = allBrand;
      } catch (e) {
        debugPrint('Error loading allbrand: $e');
      }

      // Load Monthly Rekap
      try {
        final monthStart = DateTime(
          _selectedDate.year,
          _selectedDate.month,
          1,
        ).toIso8601String();
        final monthEnd = DateTime(
          _selectedDate.year,
          _selectedDate.month + 1,
          1,
        ).toIso8601String();

        // 1. Attendance Count
        final attendance = await Supabase.instance.client
            .from('attendance')
            .select('id')
            .eq('user_id', userId)
            .gte('attendance_date', monthStart.substring(0, 10))
            .lt('attendance_date', monthEnd.substring(0, 10))
            .count();
        _monthlyAttendanceCount = attendance.count;

        // 2. Sell Out Count
        final sellOut = await Supabase.instance.client
            .from('sales_sell_out')
            .select('id')
            .eq('promotor_id', userId)
            .isFilter('deleted_at', null)
            .gte('transaction_date', monthStart)
            .lt('transaction_date', monthEnd)
            .count();
        _monthlySellOutCount = sellOut.count;

        // 3. Validation Count
        final validation = await Supabase.instance.client
            .from('stock_validations')
            .select('id')
            .eq('promotor_id', userId)
            .gte('validation_date', monthStart)
            .lt('validation_date', monthEnd)
            .count();
        _monthlyValidationCount = validation.count;

        // 4. Follower Increase (Total gain this month)
        final followers = await Supabase.instance.client
            .from('follower_reports')
            .select('follower_count')
            .eq('promotor_id', userId)
            .gte('created_at', monthStart)
            .lt('created_at', monthEnd);

        _monthlyFollowerIncrease = 0;
        for (var f in (followers as List)) {
          _monthlyFollowerIncrease += (f['follower_count'] ?? 0).toDouble();
        }
      } catch (e) {
        debugPrint('Error loading monthly rekap: $e');
      }

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
              border: Border.all(color: isToday ? t.primaryAccentGlow : t.surface3),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded, size: 12, color: t.textMutedStrong),
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: t.surface3),
          ),
          child: Text(
            'Rekapitulasi $monthName',
            style: PromotorText.outfit(
              size: 18,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
        ),
        const SizedBox(height: 16),
        _buildRekapItem(
          'Hari Kerja',
          _monthlyAttendanceCount,
          'Hari',
          Icons.calendar_month,
          t.info,
        ),
        _buildRekapItem(
          'Total Jual (Sell-Out)',
          _monthlySellOutCount,
          'Unit',
          Icons.shopping_bag,
          t.success,
        ),
        _buildRekapItem(
          'Stok Toko Done',
          _monthlyValidationCount,
          'Kali',
          Icons.check_circle,
          t.primaryAccent,
        ),
        _buildRekapItem(
          'Follower Baru',
          _monthlyFollowerIncrease.toInt(),
          'Follower',
          Icons.group_add,
          t.primaryAccentLight,
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildRekapItem(
    String label,
    int value,
    String unit,
    IconData icon,
    Color color,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: t.textMuted,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$value',
                      style: PromotorText.outfit(
                        size: 24,
                        weight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      unit,
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: t.textMuted,
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

  Widget _buildActivityCard({
    required String title,
    required IconData icon,
    required Color color,
    required bool isDone,
    required Widget content,
  }) {
    final panelColor = isDone
        ? color.withValues(alpha: 0.07)
        : t.surface1;
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
            child: Icon(icon, color: isDone ? color : t.textMutedStrong, size: 14),
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
                  DateFormat(
                    'HH:mm',
                  ).format(DateTime.parse(_attendanceData!['created_at']).toLocal()),
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
                      : DateFormat(
                          'HH:mm',
                        ).format(DateTime.parse(_clockOutData!['created_at']).toLocal()),
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
                      onPressed: () => _showSellOutVoidRequestDialog(latestSale),
                      icon: const Icon(Icons.cancel_schedule_send_rounded, size: 14),
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
                          side: BorderSide(color: t.warning.withValues(alpha: 0.2)),
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
                            await Supabase.instance.client.rpc(
                              'request_sell_out_void',
                              params: {
                                'p_sale_id': item['id'],
                                'p_reason': reason,
                              },
                            );
                            if (!mounted || !dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            await showSuccessDialog(
                              rootContext,
                              title: 'Berhasil',
                              message: 'Pengajuan batal berhasil dikirim.',
                            );
                            await _loadAllActivities();
                          } catch (e) {
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
                _compactMetricRow(
                  'Status',
                  'Terkirim',
                  tone: t.success,
                ),
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
                _compactMetricRow(
                  'Status',
                  'Terkirim',
                  tone: t.success,
                ),
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
                _compactMetricRow(
                  'Laporan',
                  'Sudah masuk',
                  tone: t.success,
                ),
                _compactMetricRow(
                  'Jam',
                  DateFormat(
                    'HH:mm',
                  ).format(DateTime.parse(_allBrandData!['created_at']).toLocal()),
                  tone: t.primaryAccent,
                ),
                _compactMetricRow(
                  'Status',
                  'Siap dicek',
                  tone: t.textPrimary,
                ),
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
