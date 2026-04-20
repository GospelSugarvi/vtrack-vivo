import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/chat_nav_badge_counter.dart';
import '../../../core/utils/chat_unread_refresh_bus.dart';
import '../../../core/utils/test_account_switcher.dart';
import '../../../ui/components/app_dashboard_shell.dart';
import '../../chat/presentation/pages/chat_list_page.dart';
import 'tabs/promotor_home_tab.dart';
import 'tabs/promotor_laporan_tab.dart';
import 'tabs/promotor_profil_tab.dart';
import 'pages/leaderboard_page.dart';

class PromotorDashboard extends StatefulWidget {
  final int initialIndex;

  const PromotorDashboard({super.key, this.initialIndex = 0});

  @override
  State<PromotorDashboard> createState() => _PromotorDashboardState();
}

class _PromotorDashboardState extends State<PromotorDashboard> {
  FieldThemeTokens get t => context.fieldTokens;
  int _currentIndex = 0;
  int _unreadCount = 0;
  final Set<int> _loadedTabs = <int>{};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, 4);
    _loadedTabs.add(_currentIndex);
    _loadUnreadCount();
    chatUnreadRefreshTick.addListener(_handleUnreadRefresh);
  }

  void _handleUnreadRefresh() {
    if (!mounted) return;
    _loadUnreadCount();
  }

  @override
  void dispose() {
    chatUnreadRefreshTick.removeListener(_handleUnreadRefresh);
    super.dispose();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final total = await loadChatNavBadgeCount(Supabase.instance.client);
      if (mounted) {
        setState(() => _unreadCount = total);
      }
    } catch (e) {
      debugPrint('Error loading unread count: $e');
    }
  }

  Widget _buildTab(int index) {
    switch (index) {
      case 0:
        return const PromotorHomeTab();
      case 1:
        return const PromotorLaporanTab();
      case 2:
        return const LeaderboardPage();
      case 3:
        return const ChatListPage();
      case 4:
      default:
        return const PromotorProfilTab();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppDashboardShell(
      currentIndex: _currentIndex,
      body: IndexedStack(
        index: _currentIndex,
        children: List<Widget>.generate(
          5,
          (index) => _loadedTabs.contains(index)
              ? _buildTab(index)
              : const SizedBox.shrink(),
        ),
      ),
      overlay: kDebugMode ? const TestAccountSwitcherFab() : null,
      onTap: (index) {
        setState(() {
          _currentIndex = index;
          _loadedTabs.add(index);
        });
        if (index == 3) {
          _loadUnreadCount();
        }
      },
      items: [
        const BottomNavigationBarItem(
          icon: Icon(Icons.home_outlined),
          activeIcon: Icon(Icons.home),
          label: 'Home',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.assignment_outlined),
          activeIcon: Icon(Icons.assignment),
          label: 'Workplace',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.leaderboard_outlined),
          activeIcon: Icon(Icons.leaderboard),
          label: 'Ranking',
        ),
        BottomNavigationBarItem(
          icon: AppUnreadBadgeIcon(unreadCount: _unreadCount, selected: false),
          activeIcon: AppUnreadBadgeIcon(
            unreadCount: _unreadCount,
            selected: true,
          ),
          label: 'Chat',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.person_outline),
          activeIcon: Icon(Icons.person),
          label: 'Profil',
        ),
      ],
    );
  }
}
