import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class SatorTimTab extends StatefulWidget {
  const SatorTimTab({super.key});

  @override
  State<SatorTimTab> createState() => _SatorTimTabState();
}

class _SatorTimTabState extends State<SatorTimTab> with SingleTickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  late TabController _tabController;
  final _supabase = Supabase.instance.client;
  
  List<Map<String, dynamic>> _promotors = [];
  List<Map<String, dynamic>> _stores = [];
  bool _isLoading = true;

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
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final snapshotRaw = await _supabase.rpc(
        'get_sator_team_snapshot',
        params: {
          'p_sator_id': userId,
          'p_date': DateTime.now().toIso8601String().split('T').first,
        },
      );
      final snapshot = snapshotRaw is Map
          ? Map<String, dynamic>.from(snapshotRaw)
          : <String, dynamic>{};
      final promotors = _parseMapList(snapshot['promotors']);
      final stores = _parseMapList(snapshot['stores']);

      if (mounted) {
        setState(() {
          _promotors = promotors;
          _stores = stores;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading tim data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: t.primaryAccent,
          child: TabBar(
            controller: _tabController,
            indicatorColor: t.textOnAccent,
            labelColor: t.textOnAccent,
            unselectedLabelColor: t.textOnAccent.withValues(alpha: 0.7),
            tabs: const [
              Tab(icon: Icon(Icons.chat), text: 'Obrolan Tim'),
              Tab(icon: Icon(Icons.store), text: 'Toko'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildChatSection(),
              _buildStoreSection(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChatSection() {
    return Column(
      children: [
        // Team Chat Header
        Container(
          padding: const EdgeInsets.all(16),
          color: t.surface2,
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: t.infoSoft,
                child: Icon(Icons.groups, color: t.primaryAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Obrolan Tim',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppTypeScale.bodyStrong,
                      ),
                    ),
                    Text(
                      '${_promotors.length} anggota',
                      style: TextStyle(
                        color: t.textSecondary,
                        fontSize: AppTypeScale.body,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () {
                  // TODO: Open team chat
                },
                icon: const Icon(Icons.open_in_new),
              ),
            ],
          ),
        ),
        
        // Promotor List for Quick Chat
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _promotors.length,
                  itemBuilder: (context, index) {
                    final promotor = _promotors[index];
                    final storeName = promotor['store_name'] ?? '-';
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: t.infoSoft,
                        child: Text(
                          (promotor['full_name'] ?? 'P')[0].toUpperCase(),
                          style: TextStyle(color: t.info),
                        ),
                      ),
                      title: Text(promotor['full_name'] ?? ''),
                      subtitle: Text(storeName),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: promotor['promotor_type'] == 'official'
                                  ? t.successSoft
                                  : t.warningSoft,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              promotor['promotor_type'] == 'official' ? 'Official' : 'Training',
                              style: TextStyle(
                                fontSize: AppTypeScale.body,
                                color: promotor['promotor_type'] == 'official'
                                    ? t.success
                                    : t.warning,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () {
                              // TODO: Open direct chat
                            },
                            icon: const Icon(Icons.chat_bubble_outline, size: 20),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStoreSection() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _stores.length,
        itemBuilder: (context, index) {
          final store = _stores[index];
          final promotors = List<Map<String, dynamic>>.from(
            store['promotors'] as List? ?? const [],
          );
          final completionPercent =
              (_toNum(store['completion_percent'])).toDouble();

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: InkWell(
              onTap: () {
                context.push('/sator/toko/${store['store_id']}');
              },
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: t.infoSoft,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(Icons.store, color: t.primaryAccent),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${store['store_name'] ?? ''}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: AppTypeScale.bodyStrong,
                                ),
                              ),
                              if (store['address'] != null)
                                Text(
                                  '${store['address']}',
                                  style: TextStyle(
                                    fontSize: AppTypeScale.support,
                                    color: t.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: _getCompletionColor(
                              completionPercent,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${completionPercent.toStringAsFixed(0)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: _getCompletionColor(completionPercent),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Promotors in this store
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: promotors.take(4).map<Widget>((p) {
                        final fullName = '${p['full_name'] ?? 'P'}';
                        return Chip(
                          avatar: CircleAvatar(
                            backgroundColor: t.infoSoft,
                            child: Text(
                              fullName[0],
                              style: TextStyle(fontSize: AppTypeScale.support, color: t.info),
                            ),
                          ),
                          label: Text(
                            fullName,
                            style: const TextStyle(fontSize: AppTypeScale.support),
                          ),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        );
                      }).toList(),
                    ),
                    if (promotors.length > 4)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          '+${promotors.length - 4} lainnya',
                          style: TextStyle(
                            fontSize: AppTypeScale.support,
                            color: t.textSecondary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Color _getCompletionColor(double percent) {
    if (percent >= 80) return t.success;
    if (percent >= 60) return t.warning;
    return t.danger;
  }

  List<Map<String, dynamic>> _parseMapList(dynamic value) {
    if (value is! List) return <Map<String, dynamic>>[];
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }
}
