import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/test_account_switcher.dart';
import '../../../ui/components/app_dashboard_shell.dart';
import '../../chat/presentation/pages/chat_list_page.dart';
import 'tabs/promotor_home_tab.dart';
import 'tabs/promotor_laporan_tab.dart';
import 'tabs/promotor_profil_tab.dart';
import 'pages/leaderboard_page.dart';

class PromotorDashboard extends StatefulWidget {
  const PromotorDashboard({super.key});

  @override
  State<PromotorDashboard> createState() => _PromotorDashboardState();
}

class _PromotorDashboardState extends State<PromotorDashboard> {
  FieldThemeTokens get t => context.fieldTokens;
  int _currentIndex = 0;
  bool _isLoading = true;
  int _unreadCount = 0;
  RealtimeChannel? _unreadChannel;
  RealtimeChannel? _messagesChannel;

  @override
  void initState() {
    super.initState();
    _loadProfile();
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

    // Listen to changes in chat_room_members for unread count updates
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

    // Also listen to new messages
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

  Future<void> _loadProfile() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      debugPrint('=== DEBUG _loadProfile ===');
      debugPrint('userId: $userId');
      if (userId == null) {
        debugPrint('userId is NULL, returning');
        return;
      }

      // Get user profile - HANYA select field yang ada, TANPA stores
      debugPrint('Step 1: Fetching user data...');
      final userData = await Supabase.instance.client
          .from('users')
          .select('full_name, role, area')
          .eq('id', userId)
          .single();
      debugPrint('Step 1 OK: userData = $userData');

      // Get store assignment through junction table
      debugPrint('Step 2: Fetching store assignment...');
      String? storeName;
      try {
        final storeRows = await Supabase.instance.client
            .from('assignments_promotor_store')
            .select('store_id, stores(store_name)')
            .eq('promotor_id', userId)
            .eq('active', true)
            .order('created_at', ascending: false)
            .limit(1);
        final assignments = List<Map<String, dynamic>>.from(storeRows);
        final storeData = assignments.isNotEmpty ? assignments.first : null;
        debugPrint('Step 2 OK: storeData = $storeData');
        storeName = storeData?['stores']?['store_name'];
      } catch (storeError) {
        debugPrint('Step 2 ERROR (assignments): $storeError');
        // Fallback: try to get store_id directly from users table if exists
        storeName = null;
      }

      debugPrint('Step 3: store_name = $storeName, user_data = $userData');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      debugPrint('=== DEBUG END - SUCCESS ===');
    } catch (e, stackTrace) {
      debugPrint('=== DEBUG ERROR ===');
      debugPrint('Error loading profile: $e');
      debugPrint('Stack trace: $stackTrace');
      debugPrint('===================');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  final List<Widget> _tabs = [
    const PromotorHomeTab(),
    const PromotorLaporanTab(),
    const LeaderboardPage(),
    const ChatListPage(),
    const PromotorProfilTab(),
  ];

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const AppLoadingScaffold();
    }

    return AppDashboardShell(
      currentIndex: _currentIndex,
      body: IndexedStack(index: _currentIndex, children: _tabs),
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
