import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/constants/app_strings.dart';

class SatorSalesTab extends StatefulWidget {
  final bool reportsOnly;
  final int initialReportTab;

  const SatorSalesTab({
    super.key,
    this.reportsOnly = false,
    this.initialReportTab = 0,
  });

  @override
  State<SatorSalesTab> createState() => _SatorSalesTabState();
}

class _SatorSalesTabState extends State<SatorSalesTab>
    with TickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  final SupabaseClient _supabase = Supabase.instance.client;

  late final TabController _mainTabController;
  late final TabController _reportTabController;

  bool _isLoading = true;
  String _satorName = 'SATOR';
  String _satorArea = '-';
  String _spvName = '-';

  List<Map<String, dynamic>> _stores = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _teamMembers = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _dailyFeed = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _monthlyFeed = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 3, vsync: this);
    _reportTabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialReportTab.clamp(0, 2),
    );
    _loadData();
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    _reportTabController.dispose();
    super.dispose();
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final now = DateTime.now();
      final today = DateFormat('yyyy-MM-dd').format(now);
      final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
      final results = await Future.wait([
        _supabase.from('users').select('full_name, area').eq('id', userId).maybeSingle(),
        _supabase
            .from('hierarchy_spv_sator')
            .select('users!hierarchy_spv_sator_spv_id_fkey(full_name)')
            .eq('sator_id', userId)
            .eq('active', true)
            .limit(1),
        _supabase
            .from('assignments_sator_store')
            .select('store_id, stores(store_name, area)')
            .eq('sator_id', userId)
            .eq('active', true),
        _supabase.rpc(
          'get_users_with_hierarchy',
          params: {'p_user_id': userId, 'p_role': 'sator'},
        ),
        _supabase
            .from('vast_agg_daily_promotor')
            .select()
            .eq('metric_date', today),
        _supabase
            .from('vast_agg_monthly_promotor')
            .select()
            .eq('month_key', monthKey),
      ]);

      final profile = results[0] as Map<String, dynamic>?;
      final spvRows = List<Map<String, dynamic>>.from(results[1] as List);
      final stores = List<Map<String, dynamic>>.from(results[2] as List);
      final teamMembers = List<Map<String, dynamic>>.from(results[3] as List? ?? const []);

      if (!mounted) return;
      setState(() {
        _satorName = '${profile?['full_name'] ?? 'SATOR'}';
        _satorArea = '${profile?['area'] ?? '-'}';
        _spvName = spvRows.isEmpty
            ? '-'
            : '${spvRows.first['users']?['full_name'] ?? '-'}';
        _stores = stores;
        _teamMembers = teamMembers.where((row) => '${row['role'] ?? ''}' == 'promotor').toList();
        _dailyFeed = List<Map<String, dynamic>>.from(results[4] as List);
        _monthlyFeed = List<Map<String, dynamic>>.from(results[5] as List);
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (widget.reportsOnly) {
      return _buildReports();
    }

    return Column(
      children: [
        Material(
          color: t.surface1.withValues(alpha: 0),
          child: TabBar(
            controller: _mainTabController,
            tabs: const [
              Tab(text: 'Overview'),
              Tab(text: 'Reports'),
              Tab(text: 'Tools'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _mainTabController,
            children: [
              _buildOverview(),
              _buildReports(),
              _buildTools(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverview() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              title: Text(_satorName),
              subtitle: Text('Area $_satorArea · SPV $_spvName'),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _metric('Toko Aktif', '${_stores.length}')),
              const SizedBox(width: 10),
              Expanded(child: _metric('Promotor', '${_teamMembers.length}')),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _metric('Feed Hari Ini', '${_dailyFeed.length}')),
              const SizedBox(width: 10),
              Expanded(child: _metric('Feed Bulanan Ini', '${_monthlyFeed.length}')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildReports() {
    return Column(
      children: [
        Material(
          color: t.surface1.withValues(alpha: 0),
          child: TabBar(
            controller: _reportTabController,
            tabs: const [
              Tab(text: 'Harian'),
              Tab(text: 'Mingguan'),
              Tab(text: 'Bulanan'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _reportTabController,
            children: [
              _reportList('Laporan Harian', _dailyFeed),
              _reportList('Laporan Mingguan', _monthlyFeed.take(10).toList()),
              _reportList('Laporan Bulanan', _monthlyFeed),
            ],
          ),
        ),
      ],
    );
  }

  Widget _reportList(String title, List<Map<String, dynamic>> rows) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        if (rows.isEmpty)
          const Card(child: ListTile(title: Text('Belum ada data')))
        else
          ...rows.take(20).map(
            (row) => Card(
              child: ListTile(
                title: Text('${row['promotor_name'] ?? row['promotor_id'] ?? 'Promotor'}'),
                subtitle: Text(
                  'Input ${_toInt(row['total_submissions'])} · Pending ${_toInt(row['total_active_pending'])}',
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTools() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: ListTile(
            leading: Icon(Icons.account_balance_wallet_outlined, color: t.info),
            title: const Text('VAST Finance'),
            subtitle: const Text('Buka monitoring Vast SATOR'),
            onTap: () => context.pushNamed('sator-vast'),
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.storefront_outlined, color: t.primaryAccent),
            title: const Text(AppStrings.laporanTitle),
            subtitle: const Text('Masuk ke alur laporan utama'),
            onTap: () => context.go('/sator/workplace'),
          ),
        ),
      ],
    );
  }

  Widget _metric(String label, String value) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: AppTypeScale.support,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(value, style: Theme.of(context).textTheme.titleLarge),
          ],
        ),
      ),
    );
  }
}
