import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/app_type_scale.dart';

class PromotorChatTab extends StatefulWidget {
  const PromotorChatTab({super.key});

  @override
  State<PromotorChatTab> createState() => _PromotorChatTabState();
}

class _PromotorChatTabState extends State<PromotorChatTab> with SingleTickerProviderStateMixin {
  FieldThemeTokens get t => context.fieldTokens;
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(
        title: const Text('Chat'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: t.primaryAccent,
          unselectedLabelColor: t.textSecondary,
          indicatorColor: t.primaryAccent,
          tabs: const [
            Tab(text: 'Obrolan'),
            Tab(text: 'Aktivitas'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildObrolanTab(),
          _buildAktivitasTab(),
        ],
      ),
    );
  }

  Widget _buildObrolanTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Chat with SATOR
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: t.primaryAccentSoft,
              child: Icon(Icons.person, color: t.primaryAccent),
            ),
            title: const Text('SATOR Ahmad'),
            subtitle: const Text('Tap untuk chat'),
            trailing: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: t.primaryAccent,
                shape: BoxShape.circle,
              ),
              child: Text(
                '2',
                style: TextStyle(color: t.textOnAccent, fontSize: AppTypeScale.support),
              ),
            ),
            onTap: () {},
          ),
        ),
        const SizedBox(height: 8),

        // Group Chat
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: t.successSoft,
              child: Icon(Icons.group, color: t.success),
            ),
            title: const Text('Grup Transmart MTC'),
            subtitle: const Text('5 anggota'),
            onTap: () {},
          ),
        ),
      ],
    );
  }

  Widget _buildAktivitasTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ...List.generate(5, (i) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(_getActivityIcon(i), size: 20, color: t.primaryAccent),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_getActivityTitle(i), style: TextStyle(fontWeight: FontWeight.bold))),
                    Text(
                      '${i + 1}h ago',
                      style: TextStyle(fontSize: AppTypeScale.support, color: t.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_getActivityDesc(i)),
                const SizedBox(height: 8),
                if (i % 2 == 0)
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: t.successSoft,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check_circle, color: t.success, size: 16),
                        const SizedBox(width: 8),
                        const Text('SATOR: Mantap! 👍', style: TextStyle(fontSize: AppTypeScale.support)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        )),
      ],
    );
  }

  IconData _getActivityIcon(int i) {
    final icons = [Icons.access_time, Icons.shopping_cart, Icons.inventory, Icons.campaign, Icons.attach_money];
    return icons[i % icons.length];
  }

  String _getActivityTitle(int i) {
    final titles = ['Clock-in', 'Lapor Jual', 'Input Stok', 'Lapor Promosi', 'VAST Finance'];
    return titles[i % titles.length];
  }

  String _getActivityDesc(int i) {
    final descs = ['Clock-in pukul 09:00', 'Jual Y400 Purple', 'Update stok 5 unit', 'Post TikTok', 'Pengajuan VAST'];
    return descs[i % descs.length];
  }
}
