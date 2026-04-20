import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../admin_dashboard.dart';

class AdminDrawer extends StatelessWidget {
  final List<AdminMenuItem> menuItems;
  final int selectedIndex;
  final Function(int) onMenuSelected;

  const AdminDrawer({
    super.key,
    required this.menuItems,
    required this.selectedIndex,
    required this.onMenuSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
            color: AppTheme.primaryBlue,
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.white,
                  child: Text('V', style: TextStyle(
                    color: AppTheme.primaryBlue,
                    fontWeight: FontWeight.bold,
                    fontSize: 28,
                  )),
                ),
                SizedBox(height: 12),
                Text(
                  'VTrack Admin',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Panel Kontrol',
                  style: TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
          // Menu
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: menuItems.length,
              itemBuilder: (context, index) {
                final item = menuItems[index];
                final isSelected = selectedIndex == index;
                return ListTile(
                  leading: Icon(
                    item.icon,
                    color: isSelected ? AppTheme.primaryBlue : AppTheme.textSecondary,
                  ),
                  title: Text(
                    item.label,
                    style: TextStyle(
                      color: isSelected ? AppTheme.primaryBlue : AppTheme.textPrimary,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  selected: isSelected,
                  selectedTileColor: AppTheme.primaryBlue.withValues(alpha: 0.1),
                  onTap: () {
                    Navigator.of(context).pop();
                    onMenuSelected(index);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
