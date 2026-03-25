import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  RealtimeChannel? _unreadChannel;
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _loadUnreadCount();
    _setupRealtimeListener();
  }

  Future<void> _loadUnreadCount() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final result = await Supabase.instance.client.rpc(
        'get_user_chat_rooms',
        params: {'p_user_id': userId},
      );

      int total = 0;
      for (var member in result) {
        total += (member['unread_count'] as int?) ?? 0;
      }

      if (mounted) {
        setState(() => _unreadCount = total);
      }
    } catch (e) {
      debugPrint('Error loading unread count: $e');
    }
  }

  void _setupRealtimeListener() {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    _unreadChannel = Supabase.instance.client
        .channel('unread_count_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'chat_room_members',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _loadUnreadCount();
          },
        )
        .subscribe();

    _messagesChannel = Supabase.instance.client
        .channel('new_messages_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          callback: (payload) {
            _loadUnreadCount();
          },
        )
        .subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final tabs = [
      SatorHomeTab(onOpenLaporan: () => setState(() => _currentIndex = 2)),
      const SatorWorkplaceTab(),
      const SatorLeaderboardPage(),
      const ChatListPage(),
      const SatorProfilTab(),
    ];

    return AppDashboardShell(
      currentIndex: _currentIndex,
      body: IndexedStack(index: _currentIndex, children: tabs),
      overlay: const TestAccountSwitcherFab(),
      onTap: (index) {
        setState(() => _currentIndex = index);
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

  @override
  void dispose() {
    if (_unreadChannel != null) {
      Supabase.instance.client.removeChannel(_unreadChannel!);
    }
    if (_messagesChannel != null) {
      Supabase.instance.client.removeChannel(_messagesChannel!);
    }
    super.dispose();
  }
}
