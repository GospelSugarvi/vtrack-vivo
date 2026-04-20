import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/chat_nav_badge_counter.dart';
import '../../../core/utils/chat_unread_refresh_bus.dart';
import '../../../core/utils/test_account_switcher.dart';
import '../../../ui/components/app_dashboard_shell.dart';
import 'tabs/sator_home_tab.dart';
import 'pages/leaderboard/sator_leaderboard_page.dart';
import 'tabs/sator_workplace_tab.dart';
import 'tabs/sator_profil_tab.dart';
import '../../chat/presentation/pages/chat_list_page.dart';

class SatorDashboard extends StatefulWidget {
  const SatorDashboard({super.key});

  @override
  State<SatorDashboard> createState() => _SatorDashboardState();
}

class _SatorDashboardState extends State<SatorDashboard> {
  FieldThemeTokens get t => context.fieldTokens;
  int _currentIndex = 0;
  int _unreadCount = 0;
  final Set<int> _loadedTabs = <int>{0};

  @override
  void initState() {
    super.initState();
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

  @override
  Widget build(BuildContext context) {
    return AppDashboardShell(
      currentIndex: _currentIndex,
      body: IndexedStack(
        index: _currentIndex,
        children: List<Widget>.generate(
          5,
          (index) => _loadedTabs.contains(index)
              ? _buildTabSlot(index)
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
          icon: Icon(Icons.task_alt_outlined),
          activeIcon: Icon(Icons.task_alt),
          label: 'Workplace',
        ),
        const BottomNavigationBarItem(
          icon: Icon(Icons.trending_up_outlined),
          activeIcon: Icon(Icons.trending_up),
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

  Widget _buildTabSlot(int index) {
    switch (index) {
      case 0:
        return SatorHomeTab(
          onOpenLaporan: () => setState(() => _currentIndex = 2),
        );
      case 1:
        return const SatorWorkplaceTab();
      case 2:
        return const SatorLeaderboardPage();
      case 3:
        return const ChatListPage();
      case 4:
      default:
        return const SatorProfilTab();
    }
  }
}
