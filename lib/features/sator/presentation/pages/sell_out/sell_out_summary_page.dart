// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:vtrack/ui/foundation/foundation.dart';

class SellOutSummaryPage extends StatefulWidget {
  const SellOutSummaryPage({super.key});

  @override
  State<SellOutSummaryPage> createState() => _SellOutSummaryPageState();
}

class _SellOutSummaryPageState extends State<SellOutSummaryPage> with SingleTickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  late TabController _tabController;
  final _supabase = Supabase.instance.client;
  
  DateTime _selectedDate = DateTime.now();
  Map<String, dynamic>? _summaryData;
  List<Map<String, dynamic>> _salesList = [];
  List<Map<String, dynamic>> _perTokoData = [];
  List<Map<String, dynamic>> _perPromotorData = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);

      final results = await Future.wait([
        _supabase.rpc('get_sator_sellout_summary', params: {
          'p_sator_id': userId,
          'p_date': dateStr,
        }).catchError((e) => null),
        _supabase.rpc('get_sator_live_sales', params: {
          'p_sator_id': userId,
          'p_date': dateStr,
        }).catchError((e) => []),
        _supabase.rpc('get_sator_sales_per_toko', params: {
          'p_sator_id': userId,
          'p_date': dateStr,
        }).catchError((e) => []),
        _supabase.rpc('get_sator_sales_per_promotor', params: {
          'p_sator_id': userId,
          'p_date': dateStr,
        }).catchError((e) => []),
      ]);

      final summary = results[0];
      final sales = results[1];
      final perToko = results[2];
      final perPromotor = results[3];

      if (mounted) {
        setState(() {
          _summaryData = summary;
          _salesList = List<Map<String, dynamic>>.from(sales ?? []);
          _perTokoData = List<Map<String, dynamic>>.from(perToko ?? []);
          _perPromotorData = List<Map<String, dynamic>>.from(perPromotor ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading sell out data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sell Out'),
        backgroundColor: t.success,
        foregroundColor: t.textOnAccent,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: t.textOnAccent,
          labelColor: t.textOnAccent,
          unselectedLabelColor: t.textOnAccent.withValues(alpha: 0.7),
          tabs: const [
            Tab(text: 'Summary'),
            Tab(text: 'Live'),
            Tab(text: 'Per Toko'),
            Tab(text: 'Per PC'),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildDateSelector(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSummaryTab(),
                _buildLiveTab(),
                _buildPerTokoTab(),
                _buildPerPromotorTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: t.surface2,
      child: Row(
        children: [
          IconButton(
            onPressed: () {
              setState(() {
                _selectedDate = _selectedDate.subtract(const Duration(days: 1));
              });
              _loadData();
            },
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _selectedDate,
                  firstDate: DateTime.now().subtract(const Duration(days: 90)),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() => _selectedDate = picked);
                  _loadData();
                }
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: t.surface1,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.calendar_today, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('EEEE, d MMM yyyy', 'id_ID').format(_selectedDate),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ),
          IconButton(
            onPressed: _selectedDate.isBefore(DateTime.now().subtract(const Duration(days: 1)))
                ? () {
                    setState(() {
                      _selectedDate = _selectedDate.add(const Duration(days: 1));
                    });
                    _loadData();
                  }
                : null,
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final totalUnits = _summaryData?['total_units'] ?? 0;
    final totalRevenue = _summaryData?['total_revenue'] ?? 0;
    final targetRevenue = _summaryData?['target_revenue'] ?? 0;
    final targetUnits = _summaryData?['target_units'] ?? 0;
    final revenuePercent = targetRevenue > 0 ? (totalRevenue / targetRevenue * 100) : 0.0;
    final unitsPercent = targetUnits > 0 ? (totalUnits / targetUnits * 100) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Main Stats
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  title: 'Total Penjualan',
                  value: formatter.format(totalRevenue),
                  target: 'Target: ${formatter.format(targetRevenue)}',
                  percent: revenuePercent,
                  color: t.success,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildSummaryCard(
                  title: 'Total Unit',
                  value: '$totalUnits Unit',
                  target: 'Target: $targetUnits Unit',
                  percent: unitsPercent,
                  color: t.info,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Weekly breakdown
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Target Mingguan',
                    style: AppTextStyle.bodyLg(t.textPrimary, weight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  _buildWeeklyRow('Minggu 1 (1-7)', 30, _summaryData?['week1_percent'] ?? 0),
                  _buildWeeklyRow('Minggu 2 (8-14)', 25, _summaryData?['week2_percent'] ?? 0),
                  _buildWeeklyRow('Minggu 3 (15-22)', 20, _summaryData?['week3_percent'] ?? 0),
                  _buildWeeklyRow('Minggu 4 (23-31)', 25, _summaryData?['week4_percent'] ?? 0),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Payment breakdown
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Metode Pembayaran',
                    style: AppTextStyle.bodyLg(t.textPrimary, weight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _buildPaymentStat(
                          'Cash',
                          Icons.money,
                          _summaryData?['cash_count'] ?? 0,
                          t.success,
                        ),
                      ),
                      Expanded(
                        child: _buildPaymentStat(
                          'Kredit',
                          Icons.credit_card,
                          _summaryData?['credit_count'] ?? 0,
                          t.info,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard({
    required String title,
    required String value,
    required String target,
    required double percent,
    required Color color,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppTextStyle.bodySm(t.textSecondary)),
            const SizedBox(height: 8),
            Text(
              value,
              style: AppTextStyle.titleSm(
                color,
                weight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(target, style: AppTextStyle.bodyMd(t.textSecondary)),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (percent / 100).clamp(0.0, 1.0),
                backgroundColor: t.surface3,
                valueColor: AlwaysStoppedAnimation(color),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${percent.toStringAsFixed(0)}%',
              style: AppTextStyle.bodySm(color, weight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeeklyRow(String week, int target, num actual) {
    final achieved = actual >= target;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(week, style: AppTextStyle.bodyMd(t.textPrimary)),
          ),
          Expanded(
            flex: 3,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (actual / target).clamp(0.0, 1.5),
                backgroundColor: t.surface3,
                valueColor: AlwaysStoppedAnimation(achieved ? t.success : t.warning),
                minHeight: 8,
              ),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 60,
            child: Text(
              '${actual.toStringAsFixed(0)}/$target%',
              style: AppTextStyle.bodySm(
                achieved ? t.success : t.warning,
                weight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentStat(String label, IconData icon, int count, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count',
                style: AppTextStyle.bodyMd(color, weight: FontWeight.bold),
              ),
              Text(label, style: AppTextStyle.bodyMd(t.textSecondary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLiveTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    if (_salesList.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: t.surface4),
            const SizedBox(height: 16),
            Text(
              'Belum ada penjualan',
              style: AppTextStyle.bodyMd(t.textSecondary),
            ),
          ],
        ),
      );
    }

    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final timeFormat = DateFormat('HH:mm');

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _salesList.length,
        itemBuilder: (context, index) {
          final sale = _salesList[index];
          final createdAt = DateTime.parse(sale['created_at'] ?? DateTime.now().toIso8601String());

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 20,
                        backgroundColor: t.successSoft,
                        child: Text(
                          (sale['promotor_name'] ?? 'P')[0].toUpperCase(),
                          style: AppTextStyle.bodyMd(t.success),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sale['promotor_name'] ?? '',
                              style: AppTextStyle.bodyMd(t.textPrimary, weight: FontWeight.bold),
                            ),
                            Text(
                              sale['store_name'] ?? '',
                              style: AppTextStyle.bodySm(t.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        timeFormat.format(createdAt),
                        style: AppTextStyle.bodySm(t.textSecondary),
                      ),
                    ],
                  ),
                  const Divider(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              sale['product_name'] ?? '',
                              style: AppTextStyle.bodyMd(t.textPrimary, weight: FontWeight.w600),
                            ),
                            Text(
                              sale['variant_name'] ?? '',
                              style: AppTextStyle.bodySm(t.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            formatter.format(sale['price'] ?? 0),
                            style: AppTextStyle.bodyMd(
                              t.success,
                              weight: FontWeight.bold,
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: t.warningSoft,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '+${formatter.format(sale['bonus'] ?? 0)}',
                              style: AppTextStyle.bodyMd(t.warning),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPerTokoTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _perTokoData.length,
      itemBuilder: (context, index) {
        final toko = _perTokoData[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: t.infoSoft,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.store, color: t.info),
            ),
            title: Text(
              toko['store_name'] ?? '',
              style: AppTextStyle.bodyMd(t.textPrimary, weight: FontWeight.bold),
            ),
            subtitle: Text('${toko['total_units'] ?? 0} unit • ${formatter.format(toko['total_revenue'] ?? 0)}'),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: t.successSoft,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${toko['total_units'] ?? 0}',
                style: AppTextStyle.bodyMd(t.success, weight: FontWeight.bold),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPerPromotorTab() {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    
    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _perPromotorData.length,
      itemBuilder: (context, index) {
        final promotor = _perPromotorData[index];
        final achievementPercent = promotor['achievement_percent'] ?? 0;
        
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: t.infoSoft,
                  child: Text(
                    (promotor['promotor_name'] ?? 'P')[0].toUpperCase(),
                    style: AppTextStyle.bodyMd(t.info, weight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        promotor['promotor_name'] ?? '',
                        style: AppTextStyle.bodyMd(t.textPrimary, weight: FontWeight.bold),
                      ),
                      Text(
                        promotor['store_name'] ?? '',
                        style: AppTextStyle.bodySm(t.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${promotor['total_units'] ?? 0} unit • ${formatter.format(promotor['total_revenue'] ?? 0)}',
                        style: AppTextStyle.bodySm(t.textSecondary),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getAchievementColor(achievementPercent.toDouble()).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${achievementPercent.toStringAsFixed(0)}%',
                    style: AppTextStyle.bodyMd(
                      _getAchievementColor(achievementPercent.toDouble()),
                      weight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Color _getAchievementColor(double percent) {
    if (percent >= 100) return t.success;
    if (percent >= 80) return t.info;
    if (percent >= 60) return t.warning;
    return t.danger;
  }
}
