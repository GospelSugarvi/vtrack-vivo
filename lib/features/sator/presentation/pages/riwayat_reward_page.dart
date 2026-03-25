import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

class RiwayatRewardPage extends StatefulWidget {
  const RiwayatRewardPage({super.key});

  @override
  State<RiwayatRewardPage> createState() => _RiwayatRewardPageState();
}

class _RiwayatRewardPageState extends State<RiwayatRewardPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _rewards = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser!.id;
      final data = await _supabase.rpc('get_sator_reward_history', params: {'p_sator_id': userId});
      if (mounted) {
        setState(() {
          _rewards = List<Map<String, dynamic>>.from(data ?? []);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Reward'),
        backgroundColor: t.warning,
        foregroundColor: t.textOnAccent,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _rewards.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _rewards.length,
                    itemBuilder: (context, index) => _buildRewardCard(_rewards[index]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.card_giftcard, size: 64, color: t.surface4),
          const SizedBox(height: 16),
          Text('Belum ada reward', style: TextStyle(color: t.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildRewardCard(Map<String, dynamic> reward) {
    final formatter = NumberFormat.currency(locale: 'id_ID', symbol: 'Rp ', decimalDigits: 0);
    final dateFormat = DateFormat('d MMM yyyy');
    final status = reward['status'] ?? 'pending';
    final statusColors = {'pending': t.warning, 'paid': t.success, 'cancelled': t.danger};
    final statusLabels = {'pending': 'Pending', 'paid': 'Sudah Cair', 'cancelled': 'Dibatalkan'};
    final color = statusColors[status] ?? t.textSecondary;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                    color: t.warningSoft,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.card_giftcard, color: t.warning),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(reward['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      Text(reward['period'] ?? '', style: TextStyle(fontSize: AppTypeScale.support, color: t.textSecondary)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
                  child: Text(statusLabels[status] ?? '', style: TextStyle(fontSize: AppTypeScale.body, color: color)),
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Nilai Reward', style: TextStyle(color: t.textSecondary)),
                Text(
                  formatter.format(reward['amount'] ?? 0),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: t.warning,
                  ),
                ),
              ],
            ),
            if (reward['paid_date'] != null) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Tanggal Cair', style: TextStyle(color: t.textSecondary)),
                  Text(dateFormat.format(DateTime.parse(reward['paid_date'])), style: const TextStyle(fontWeight: FontWeight.w700)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
