import 'package:flutter/material.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';

class AdminActivityPage extends StatefulWidget {
  const AdminActivityPage({super.key});

  @override
  State<AdminActivityPage> createState() => _AdminActivityPageState();
}

class _AdminActivityPageState extends State<AdminActivityPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  List<Map<String, dynamic>> _activities = [];
  List<Map<String, dynamic>> _todayRecords = [];
  List<Map<String, dynamic>> _promotors = [];
  
  bool _isLoading = true;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // Load activity types
      final activities = await supabase.from('activity_types')
          .select('*')
          .order('display_order');
      if (!mounted) return;
      _activities = List<Map<String, dynamic>>.from(activities);
      
      // Load promotors for tracking
      final promotors = await supabase.from('users')
          .select('id, full_name')
          .eq('role', 'promotor')
          .isFilter('deleted_at', null);
      if (!mounted) return;
      _promotors = List<Map<String, dynamic>>.from(promotors);
      
      await _loadDailyRecords();
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadDailyRecords() async {
    final dateStr = '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';
    final records = await supabase.from('activity_records')
        .select(
          '*, activity_types(name), users!activity_records_user_id_fkey(full_name)',
        )
        .eq('activity_date', dateStr);
    if (!mounted) return;
    _todayRecords = List<Map<String, dynamic>>.from(records);
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddActivityDialog,
        icon: const Icon(Icons.add),
        label: const Text('Tambah Aktivitas'),
      ),
      body: Column(
        children: [
          if (isDesktop) Padding(
            padding: const EdgeInsets.all(24),
            child: Text('📋 Activity Management', style: Theme.of(context).textTheme.headlineMedium),
          ),
          TabBar(
            controller: _tabController,
            tabs: const [
              Tab(icon: Icon(Icons.settings), text: 'Kelola Aktivitas'),
              Tab(icon: Icon(Icons.people), text: 'Monitor Harian'),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : TabBarView(
                    controller: _tabController,
                    children: [
                      _buildManageTab(),
                      _buildMonitorTab(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  // ============ MANAGE TAB ============
  Widget _buildManageTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Daftar Aktivitas', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              if (_activities.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: Text('Belum ada aktivitas')),
                )
              else
                ..._activities.map((a) => _buildActivityTile(a)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildActivityTile(Map<String, dynamic> activity) {
    final isActive = activity['is_active'] == true;
    final isRequired = activity['is_required'] == true;
    
    return ListTile(
      leading: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: (isActive ? AppTheme.successGreen : AppColors.textSecondary).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(_getIcon(activity['icon_name']), color: isActive ? AppTheme.successGreen : AppColors.textSecondary),
      ),
      title: Text(activity['name'] ?? 'Unknown'),
      subtitle: Row(
        children: [
          if (isRequired)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('Wajib', style: TextStyle(fontSize: 12, color: AppTheme.primaryBlue)),
            ),
          Text(activity['schedule'] ?? 'daily', style: const TextStyle(fontSize: 12)),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: isActive,
            activeThumbColor: AppTheme.successGreen,
            onChanged: (v) => _toggleActivity(activity, v),
          ),
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => _showEditActivityDialog(activity),
          ),
        ],
      ),
    );
  }

  IconData _getIcon(String? iconName) {
    switch (iconName) {
      case 'access_time': return Icons.access_time;
      case 'shopping_cart': return Icons.shopping_cart;
      case 'inventory': return Icons.inventory;
      case 'campaign': return Icons.campaign;
      case 'attach_money': return Icons.attach_money;
      case 'all_inclusive': return Icons.all_inclusive;
      case 'fact_check': return Icons.fact_check;
      case 'logout': return Icons.logout;
      default: return Icons.check_circle;
    }
  }

  Future<void> _toggleActivity(Map<String, dynamic> activity, bool value) async {
    await supabase.from('activity_types').update({'is_active': value}).eq('id', activity['id']);
    _loadData();
  }

  // ============ MONITOR TAB ============
  Widget _buildMonitorTab() {
    // Build completion matrix
    Map<String, Map<String, bool>> completionMap = {};
    for (var r in _todayRecords) {
      final userId = r['user_id'] as String?;
      final activityId = r['activity_type_id'] as String?;
      if (userId != null && activityId != null) {
        completionMap.putIfAbsent(userId, () => {});
        completionMap[userId]![activityId] = true;
      }
    }
    
    return Column(
      children: [
        // Date selector
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Tanggal: ', style: TextStyle(fontWeight: FontWeight.bold)),
              TextButton.icon(
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text('${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'),
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2025),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                    await _loadDailyRecords();
                    setState(() {});
                  }
                },
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {
                  _loadDailyRecords();
                  setState(() {});
                },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
        Expanded(
          child: _promotors.isEmpty
              ? const Center(child: Text('Tidak ada promotor'))
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    columns: [
                      const DataColumn(label: Text('Promotor')),
                      ..._activities.where((a) => a['is_active'] == true).map((a) => 
                        DataColumn(label: Text(a['name'] ?? '', style: const TextStyle(fontSize: 13)))),
                    ],
                    rows: _promotors.map((p) {
                      final userId = p['id'] as String;
                      return DataRow(cells: [
                        DataCell(Text(p['full_name'] ?? 'Unknown')),
                        ..._activities.where((a) => a['is_active'] == true).map((a) {
                          final activityId = a['id'] as String;
                          final completed = completionMap[userId]?[activityId] == true;
                          return DataCell(
                            Icon(
                              completed ? Icons.check_circle : Icons.radio_button_unchecked,
                              color: completed ? AppColors.success : AppColors.border,
                              size: 20,
                            ),
                          );
                        }),
                      ]);
                    }).toList(),
                  ),
                ),
        ),
      ],
    );
  }

  // ============ DIALOGS ============
  void _showAddActivityDialog() {
    final nameC = TextEditingController();
    final descC = TextEditingController();
    String schedule = 'daily';
    bool isRequired = false;
    String iconName = 'check_circle';
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Tambah Aktivitas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Nama Aktivitas')),
                const SizedBox(height: 12),
                TextField(controller: descC, decoration: const InputDecoration(labelText: 'Deskripsi')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: schedule,
                  decoration: const InputDecoration(labelText: 'Jadwal'),
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Pagi')),
                    DropdownMenuItem(value: 'daily', child: Text('Harian')),
                    DropdownMenuItem(value: 'evening', child: Text('Malam')),
                    DropdownMenuItem(value: 'on_demand', child: Text('Jika ada')),
                  ],
                  onChanged: (v) => setDialogState(() => schedule = v ?? 'daily'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Wajib'),
                  value: isRequired,
                  onChanged: (v) => setDialogState(() => isRequired = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                if (nameC.text.isEmpty) return;
                await supabase.from('activity_types').insert({
                  'name': nameC.text,
                  'description': descC.text,
                  'icon_name': iconName,
                  'schedule': schedule,
                  'is_required': isRequired,
                  'is_active': true,
                  'display_order': _activities.length + 1,
                });
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditActivityDialog(Map<String, dynamic> activity) {
    final nameC = TextEditingController(text: activity['name']);
    final descC = TextEditingController(text: activity['description'] ?? '');
    String schedule = activity['schedule'] ?? 'daily';
    bool isRequired = activity['is_required'] == true;
    
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Edit Aktivitas'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Nama')),
                const SizedBox(height: 12),
                TextField(controller: descC, decoration: const InputDecoration(labelText: 'Deskripsi')),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: schedule,
                  decoration: const InputDecoration(labelText: 'Jadwal'),
                  items: const [
                    DropdownMenuItem(value: 'morning', child: Text('Pagi')),
                    DropdownMenuItem(value: 'daily', child: Text('Harian')),
                    DropdownMenuItem(value: 'evening', child: Text('Malam')),
                    DropdownMenuItem(value: 'on_demand', child: Text('Jika ada')),
                  ],
                  onChanged: (v) => setDialogState(() => schedule = v ?? 'daily'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Wajib'),
                  value: isRequired,
                  onChanged: (v) => setDialogState(() => isRequired = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await supabase.from('activity_types').delete().eq('id', activity['id']);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('Hapus', style: TextStyle(color: AppColors.danger)),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Batal')),
            ElevatedButton(
              onPressed: () async {
                await supabase.from('activity_types').update({
                  'name': nameC.text,
                  'description': descC.text,
                  'schedule': schedule,
                  'is_required': isRequired,
                }).eq('id', activity['id']);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                _loadData();
              },
              child: const Text('Update'),
            ),
          ],
        ),
      ),
    );
  }
}
