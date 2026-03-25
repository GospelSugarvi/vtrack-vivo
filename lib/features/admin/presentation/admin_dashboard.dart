import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../main.dart';
import '../../../core/utils/test_account_switcher.dart';
import '../../chat/presentation/pages/chat_list_page.dart';
import 'widgets/admin_drawer.dart';
import 'pages/admin_overview_page.dart';
import 'pages/admin_users_page.dart';
import 'pages/admin_areas_page.dart';
import 'pages/admin_stores_page.dart';
import 'pages/admin_products_page.dart';
import 'pages/admin_targets_month_selector.dart';
import 'pages/admin_bonus_page.dart';
import 'pages/admin_hierarchy_page.dart';
import 'pages/admin_stock_page.dart';
import 'pages/admin_activity_page.dart';
import 'pages/admin_reports_page.dart';
import 'pages/admin_chat_management_page.dart';
import 'pages/admin_ai_settings_page.dart';
import 'pages/admin_weekly_target_page.dart';
import 'pages/admin_fokus_page.dart';
import 'pages/admin_settings_page.dart';
import 'pages/shift_settings_page.dart';
import 'pages/admin_store_groups_page.dart';
import 'pages/stock_rules_page.dart';

class AdminDashboard extends StatefulWidget {
  const AdminDashboard({super.key});

  @override
  State<AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<AdminDashboard> {
  int _selectedIndex = 0;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  final List<AdminMenuItem> _menuItems = [
    AdminMenuItem(
      icon: Icons.dashboard,
      label: 'Overview',
      page: const AdminOverviewPage(),
    ),
    AdminMenuItem(
      icon: Icons.people,
      label: 'User',
      page: const AdminUsersPage(),
    ),
    AdminMenuItem(icon: Icons.map, label: 'Area', page: const AdminAreasPage()),
    AdminMenuItem(
      icon: Icons.store,
      label: 'Toko',
      page: const AdminStoresPage(),
    ),
    AdminMenuItem(
      icon: Icons.group_work,
      label: 'Grup Toko',
      page: const AdminStoreGroupsPage(),
    ),
    AdminMenuItem(
      icon: Icons.phone_android,
      label: 'Produk',
      page: const AdminProductsPage(),
    ),
    AdminMenuItem(
      icon: Icons.track_changes,
      label: 'Target',
      page: const AdminTargetsMonthSelector(),
    ),
    AdminMenuItem(
      icon: Icons.star,
      label: 'Produk Fokus',
      page: const AdminFokusPage(),
    ),
    AdminMenuItem(
      icon: Icons.date_range,
      label: 'Weekly Target',
      page: const AdminWeeklyTargetPage(),
    ),
    AdminMenuItem(
      icon: Icons.attach_money,
      label: 'Bonus & Reward',
      page: const AdminBonusPage(),
    ),
    AdminMenuItem(
      icon: Icons.account_tree,
      label: 'Hierarchy',
      page: const AdminHierarchyPage(),
    ),

    // ...
    AdminMenuItem(
      icon: Icons.inventory_2,
      label: 'Stock',
      page: const AdminStockPage(),
    ),
    AdminMenuItem(
      icon: Icons.rule,
      label: 'Aturan Stok',
      page: const StockRulesPage(),
    ), // <-- New Menu
    AdminMenuItem(
      icon: Icons.checklist,
      label: 'Aktivitas',
      page: const AdminActivityPage(),
    ),
    AdminMenuItem(
      icon: Icons.bar_chart,
      label: 'Reports',
      page: const AdminReportsPage(),
    ),
    AdminMenuItem(
      icon: Icons.chat_bubble,
      label: 'Chat',
      page: const ChatListPage(),
    ),
    AdminMenuItem(
      icon: Icons.campaign,
      label: 'Pengumuman',
      page: const AdminChatManagementPage(),
    ),
    AdminMenuItem(
      icon: Icons.smart_toy,
      label: 'AI Settings',
      page: const AdminAiSettingsPage(),
    ),
    AdminMenuItem(
      icon: Icons.access_time,
      label: 'Jam Kerja',
      page: const ShiftSettingsPage(),
    ),
    AdminMenuItem(
      icon: Icons.settings,
      label: 'Settings',
      page: const AdminSettingsPage(),
    ),
  ];

  void _onMenuSelected(int index) {
    setState(() => _selectedIndex = index);
    // Check if mobile layout by checking if drawer is open
    if (_scaffoldKey.currentState?.isDrawerOpen ?? false) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Apakah Anda yakin ingin keluar?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.errorRed),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await supabase.auth.signOut();
      if (mounted) context.go('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;
    return isDesktop ? _buildDesktopLayout() : _buildMobileLayout();
  }

  Widget _buildDesktopLayout() {
    return Scaffold(
      body: Stack(
        children: [
          Row(
            children: [
              Container(
                width: 220,
                color: AppTheme.primaryBlue,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      child: const Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: Colors.white,
                            radius: 16,
                            child: Text(
                              'V',
                              style: TextStyle(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          SizedBox(width: 8),
                          Text(
                            'VTrack Admin',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(color: Colors.white24, height: 1),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _menuItems.length,
                        itemBuilder: (context, index) {
                          final item = _menuItems[index];
                          final isSelected = _selectedIndex == index;
                          return ListTile(
                            dense: true,
                            leading: Icon(
                              item.icon,
                              color: isSelected ? Colors.white : Colors.white70,
                              size: 20,
                            ),
                            title: Text(
                              item.label,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            selected: isSelected,
                            selectedTileColor: Colors.white.withValues(
                              alpha: 0.1,
                            ),
                            onTap: () => _onMenuSelected(index),
                          );
                        },
                      ),
                    ),
                    ListTile(
                      dense: true,
                      leading: const Icon(
                        Icons.logout,
                        color: Colors.white70,
                        size: 20,
                      ),
                      title: const Text(
                        'Logout',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      onTap: _handleLogout,
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
              Expanded(child: _menuItems[_selectedIndex].page),
            ],
          ),
          const TestAccountSwitcherFab(),
        ],
      ),
    );
  }

  Widget _buildMobileLayout() {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(_menuItems[_selectedIndex].label),
        leading: IconButton(
          icon: const Icon(Icons.menu),
          onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        ),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _handleLogout),
        ],
      ),
      drawer: AdminDrawer(
        menuItems: _menuItems,
        selectedIndex: _selectedIndex,
        onMenuSelected: _onMenuSelected,
      ),
      body: Stack(
        children: [_menuItems[_selectedIndex].page, const TestAccountSwitcherFab()],
      ),
    );
  }
}

class AdminMenuItem {
  final IconData icon;
  final String label;
  final Widget page;

  AdminMenuItem({required this.icon, required this.label, required this.page});
}
