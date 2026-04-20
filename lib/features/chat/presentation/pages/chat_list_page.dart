import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/chat_unread_refresh_bus.dart';
import '../../cubit/chat_list_cubit.dart';
import '../../repository/chat_repository.dart';
import '../../models/chat_room.dart';
import '../theme/chat_theme.dart';
import 'chat_room_page.dart';
import '../../../../ui/promotor/promotor_theme.dart';

class ChatListPage extends StatelessWidget {
  const ChatListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatListCubit(ChatRepository())..loadChatRooms(),
      child: const ChatListView(),
    );
  }
}

class ChatListView extends StatefulWidget {
  const ChatListView({super.key});

  @override
  State<ChatListView> createState() => _ChatListViewState();
}

class _ChatListViewState extends State<ChatListView> {
  ChatUiPalette get c => chatPaletteOf(context);
  bool _showSearchBar = false;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    chatUnreadRefreshTick.addListener(_handleUnreadRefresh);
  }

  @override
  void dispose() {
    chatUnreadRefreshTick.removeListener(_handleUnreadRefresh);
    _searchController.dispose();
    super.dispose();
  }

  void _handleUnreadRefresh() {
    if (!mounted) return;
    final cubit = context.read<ChatListCubit>();
    cubit.refreshChatRooms();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: BlocBuilder<ChatListCubit, ChatListState>(
          builder: (context, state) {
            if (state is ChatListLoading) {
              return Center(child: CircularProgressIndicator(color: c.gold));
            }

            if (state is ChatListError) {
              return _buildError(state.message);
            }

            if (state is ChatListLoaded) {
              if (state.rooms.isEmpty) {
                return _buildEmpty();
              }

              final rooms = _sortRooms(state.rooms);
              return DefaultTabController(
                length: 5,
                child: Column(
                  children: [
                    _buildHeader(),
                    _buildTabBar(rooms),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildRoomTabList(_roomsForTab(rooms, _ChatTab.all)),
                          _buildRoomTabList(
                            _roomsForTab(rooms, _ChatTab.store),
                            compactStore: true,
                          ),
                          _buildRoomTabList(_roomsForTab(rooms, _ChatTab.team)),
                          _buildRoomTabList(
                            _roomsForTab(rooms, _ChatTab.global),
                          ),
                          _buildRoomTabList(
                            _roomsForTab(rooms, _ChatTab.announcement),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(bottom: BorderSide(color: c.s3)),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: _showSearchBar
                ? Container(
                    height: 38,
                    decoration: BoxDecoration(
                      color: c.s1,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: c.s3),
                    ),
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      cursorColor: c.gold,
                      decoration: InputDecoration(
                        hintText: 'Cari percakapan...',
                        hintStyle: PromotorText.outfit(
                          size: 12,
                          weight: FontWeight.w700,
                          color: c.muted,
                        ),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        isDense: true,
                      ),
                      style: PromotorText.outfit(
                        size: 12,
                        weight: FontWeight.w700,
                        color: c.cream2,
                      ),
                    ),
                  )
                : Text(
                    'Chat',
                    style: PromotorText.display(size: 24, color: c.cream),
                  ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: () {
              setState(() {
                _showSearchBar = !_showSearchBar;
                if (!_showSearchBar) {
                  _searchController.clear();
                }
              });
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: c.s3),
              ),
              child: Icon(
                _showSearchBar ? Icons.close_rounded : Icons.search,
                size: 16,
                color: c.muted,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar(List<ChatRoom> rooms) {
    final unreadAll = rooms.fold<int>(0, (sum, room) => sum + room.unreadCount);
    final unreadAnnouncement = _roomsForTab(
      rooms,
      _ChatTab.announcement,
    ).fold<int>(0, (sum, room) => sum + room.unreadCount);
    final unreadGlobal = _roomsForTab(
      rooms,
      _ChatTab.global,
    ).fold<int>(0, (sum, room) => sum + room.unreadCount);
    final unreadTeam = _roomsForTab(
      rooms,
      _ChatTab.team,
    ).fold<int>(0, (sum, room) => sum + room.unreadCount);
    final unreadStore = _roomsForTab(
      rooms,
      _ChatTab.store,
    ).fold<int>(0, (sum, room) => sum + room.unreadCount);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 6),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.s3),
      ),
      child: Builder(
        builder: (tabContext) => TabBar(
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          splashFactory: NoSplash.splashFactory,
          labelColor: c.onAccent,
          unselectedLabelColor: c.cream,
          labelStyle: PromotorText.outfit(size: 11, weight: FontWeight.w800),
          unselectedLabelStyle: PromotorText.outfit(
            size: 11,
            weight: FontWeight.w800,
          ),
          overlayColor: WidgetStatePropertyAll(c.gold.withValues(alpha: 0.08)),
          indicator: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          dividerColor: Colors.transparent,
          indicatorSize: TabBarIndicatorSize.tab,
          padding: const EdgeInsets.symmetric(horizontal: 2),
          labelPadding: const EdgeInsets.symmetric(horizontal: 4),
          tabs: [
            _buildTab(tabContext, 'Semua', unreadAll),
            _buildTab(tabContext, 'Toko', unreadStore),
            _buildTab(tabContext, 'Tim', unreadTeam),
            _buildTab(tabContext, 'Global', unreadGlobal),
            _buildTab(tabContext, 'Info', unreadAnnouncement),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(BuildContext tabContext, String label, int unread) {
    final controller = DefaultTabController.of(tabContext);
    final tabIndex = switch (label) {
      'Semua' => 0,
      'Toko' => 1,
      'Tim' => 2,
      'Global' => 3,
      'Info' => 4,
      _ => 0,
    };
    final animation = controller.animation;

    return AnimatedBuilder(
      animation: animation ?? controller,
      builder: (context, _) {
        final animationValue = animation?.value ?? controller.index.toDouble();
        final isSelected = (animationValue - tabIndex).abs() < 0.5;

        return Tab(
          height: 38,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected ? c.gold : c.s1,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: isSelected ? c.gold : c.s3),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: c.gold.withValues(alpha: 0.18),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w800,
                    color: isSelected ? c.bg : c.cream,
                  ),
                ),
                if (unread > 0) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? c.onAccent.withValues(alpha: 0.16)
                          : c.gold.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$unread',
                      style: PromotorText.outfit(
                        size: 9,
                        weight: FontWeight.w800,
                        color: isSelected ? c.bg : c.gold,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildChatRow({required ChatRoom room, required _ChatType type}) {
    final hasUnread = room.unreadCount > 0;
    final timeLabel = _formatTimeLabel(room.lastMessageTime);
    final preview = _buildPreview(room);
    final meta = (room.description ?? '').trim();
    final accent = _chatAccent(type);
    final avatarLetter = _avatarLetter(type, room.name);
    final isStore = type == _ChatType.store;
    final hasMentionPersonal = room.mentionUnreadCount > 0;
    final hasMentionAll = room.mentionAllUnreadCount > 0;
    final borderColor = isStore && hasUnread
        ? c.gold.withValues(alpha: 0.3)
        : accent.border;
    final avatarTextColor = isStore && hasUnread ? c.gold : accent.text;
    final showUnreadDot = hasUnread && !isStore;

    return GestureDetector(
      onTap: () => _navigateToRoom(context, room),
      child: Container(
        color: Colors.transparent,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.bg,
                    shape: BoxShape.circle,
                    border: Border.all(color: borderColor),
                  ),
                  child: Center(
                    child: Text(
                      avatarLetter,
                      style: PromotorText.display(
                        size: isStore ? 12 : 15,
                        color: avatarTextColor,
                      ),
                    ),
                  ),
                ),
                if (showUnreadDot)
                  Positioned(
                    right: 1,
                    bottom: 1,
                    child: Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: accent.dot,
                        shape: BoxShape.circle,
                        border: Border.all(color: c.bg, width: 2),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: isStore
                                  ? c.gold.withValues(alpha: 0.1)
                                  : c.s1,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: isStore
                                    ? c.gold.withValues(alpha: 0.22)
                                    : c.s3,
                              ),
                            ),
                            child: Text(
                              _displayRoomName(room),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PromotorText.outfit(
                                size: 12,
                                weight: FontWeight.w700,
                                color: isStore ? c.gold : c.cream,
                              ),
                            ),
                          ),
                        ),
                      ),
                      Text(
                        timeLabel,
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w700,
                          color: hasUnread ? accent.text : c.muted,
                        ),
                      ),
                    ],
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w700,
                        color: c.muted2,
                      ),
                    ),
                  ],
                  const SizedBox(height: 2),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PromotorText.outfit(
                      size: 11,
                      weight: hasUnread ? FontWeight.w700 : FontWeight.w600,
                      color: hasUnread ? c.cream2 : c.muted,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Row(
                    children: [
                      if (hasMentionPersonal) ...[
                        _buildMentionBadge(
                          label: '@ ${room.mentionUnreadCount}',
                          backgroundColor: c.gold.withValues(alpha: 0.14),
                          textColor: c.gold,
                        ),
                      ],
                      if (hasMentionAll) ...[
                        if (hasMentionPersonal) const SizedBox(width: 6),
                        _buildMentionBadge(
                          label: '@all ${room.mentionAllUnreadCount}',
                          backgroundColor: c.muted2.withValues(alpha: 0.18),
                          textColor: c.cream2,
                        ),
                      ],
                      const Spacer(),
                      if (hasUnread)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          constraints: const BoxConstraints(minHeight: 18),
                          decoration: BoxDecoration(
                            color: accent.countBg,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: accent.countBg.withValues(alpha: 0.22),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              '${room.unreadCount}',
                              style: PromotorText.outfit(
                                size: 11,
                                weight: FontWeight.w800,
                                color: accent.countText,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMentionBadge({
    required String label,
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 9,
          weight: FontWeight.w800,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildStoreRow(ChatRoom room) {
    final hasUnread = room.unreadCount > 0;
    final timeLabel = _formatTimeLabel(room.lastMessageTime);
    final preview = room.lastMessageContent ?? '';
    final memberLabel = '${room.memberCount} org';

    return GestureDetector(
      onTap: () => _navigateToRoom(context, room),
      child: Container(
        color: Colors.transparent,
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: hasUnread ? c.gold.withValues(alpha: 0.35) : c.s3,
                ),
              ),
              child: Icon(
                Icons.storefront_rounded,
                size: 17,
                color: hasUnread ? c.gold : c.cream2,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PromotorText.outfit(
                            size: 13,
                            weight: hasUnread
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: c.cream,
                          ),
                        ),
                      ),
                      if (timeLabel.isNotEmpty)
                        Text(
                          timeLabel,
                          style: PromotorText.outfit(
                            size: 10,
                            weight: FontWeight.w700,
                            color: hasUnread ? c.gold : c.muted,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        memberLabel,
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w700,
                          color: c.muted2,
                        ),
                      ),
                      if (preview.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PromotorText.outfit(
                              size: 10,
                              weight: FontWeight.w600,
                              color: hasUnread ? c.cream2 : c.muted,
                            ),
                          ),
                        ),
                      ],
                      if (hasUnread) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          constraints: const BoxConstraints(minHeight: 16),
                          decoration: BoxDecoration(
                            color: c.gold,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Center(
                            child: Text(
                              '${room.unreadCount}',
                              style: PromotorText.outfit(
                                size: 9,
                                weight: FontWeight.w800,
                                color: c.bg,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoomTabList(List<ChatRoom> rooms, {bool compactStore = false}) {
    return RefreshIndicator(
      onRefresh: () => context.read<ChatListCubit>().refreshChatRooms(),
      color: c.gold,
      child: rooms.isEmpty
          ? ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [const SizedBox(height: 80), _buildEmptyTabState()],
            )
          : ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 88),
              itemCount: rooms.length,
              separatorBuilder: (_, index) =>
                  Divider(height: 1, color: c.s3.withValues(alpha: 0.8)),
              itemBuilder: (context, index) {
                final room = rooms[index];
                return Padding(
                  padding: EdgeInsets.symmetric(vertical: compactStore ? 6 : 8),
                  child: compactStore
                      ? _buildStoreRow(room)
                      : _buildChatRow(room: room, type: _roomType(room)),
                );
              },
            ),
    );
  }

  Widget _buildEmptyTabState() {
    return Center(
      child: Text(
        'Belum ada percakapan di tab ini',
        style: PromotorText.outfit(
          size: 14,
          weight: FontWeight.w700,
          color: c.muted,
        ),
      ),
    );
  }

  Widget _buildError(String message) {
    return Center(
      child: Text(
        message,
        style: PromotorText.outfit(
          size: 15,
          weight: FontWeight.w700,
          color: c.muted,
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Text(
        'Belum ada chat',
        style: PromotorText.outfit(
          size: 15,
          weight: FontWeight.w700,
          color: c.muted,
        ),
      ),
    );
  }

  bool _matchType(ChatRoom room, String type) {
    final explicitTab = _normalizeChatTab(room.chatTab);
    if (explicitTab != null) {
      return switch (type) {
        'announcement' => explicitTab == _ChatTab.announcement,
        'global' => explicitTab == _ChatTab.global,
        'team' => explicitTab == _ChatTab.team,
        _ => false,
      };
    }

    final rt = room.roomType.toLowerCase();
    if (type == 'announcement') {
      return rt.contains('announce') ||
          room.name.toLowerCase().contains('announce');
    }
    if (type == 'global') {
      return rt.contains('global') ||
          room.name.toLowerCase().contains('global');
    }
    if (type == 'team') {
      return rt.contains('team') ||
          rt.contains('tim') ||
          rt.contains('leader') ||
          room.name.toLowerCase().contains('tim');
    }
    return false;
  }

  bool _isStoreRoom(ChatRoom room) {
    final explicitTab = _normalizeChatTab(room.chatTab);
    if (explicitTab != null) {
      return explicitTab == _ChatTab.store;
    }

    final rt = room.roomType.toLowerCase();
    return rt.contains('toko') || rt.contains('store') || room.tokoId != null;
  }

  _ChatTab? _normalizeChatTab(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    switch (value) {
      case 'team':
      case 'tim':
        return _ChatTab.team;
      case 'global':
        return _ChatTab.global;
      case 'announcement':
      case 'info':
        return _ChatTab.announcement;
      case 'store':
      case 'toko':
        return _ChatTab.store;
      default:
        return null;
    }
  }

  List<ChatRoom> _roomsForTab(List<ChatRoom> rooms, _ChatTab tab) {
    switch (tab) {
      case _ChatTab.all:
        return rooms;
      case _ChatTab.announcement:
        return rooms.where((room) => _matchType(room, 'announcement')).toList();
      case _ChatTab.global:
        return rooms.where((room) => _matchType(room, 'global')).toList();
      case _ChatTab.team:
        return rooms.where((room) => _matchType(room, 'team')).toList();
      case _ChatTab.store:
        return rooms.where(_isStoreRoom).toList();
    }
  }

  _ChatType _roomType(ChatRoom room) {
    if (_matchType(room, 'announcement')) return _ChatType.announce;
    if (_matchType(room, 'global')) return _ChatType.global;
    if (_matchType(room, 'team')) return _ChatType.team;
    if (_isStoreRoom(room)) return _ChatType.store;
    return _ChatType.global;
  }

  _ChatAccent _chatAccent(_ChatType type) {
    switch (type) {
      case _ChatType.announce:
        return _ChatAccent(
          bg: c.amberSoft,
          border: c.gold.withValues(alpha: 0.25),
          text: c.gold,
          dot: c.gold,
          countBg: c.gold,
          countText: c.onAccent,
        );
      case _ChatType.global:
        return _ChatAccent(
          bg: c.goldDim,
          border: c.gold.withValues(alpha: 0.18),
          text: c.gold,
          dot: c.gold,
          countBg: c.gold,
          countText: c.onAccent,
        );
      case _ChatType.team:
        return _ChatAccent(
          bg: c.greenSoft,
          border: c.green.withValues(alpha: 0.2),
          text: c.green,
          dot: c.green,
          countBg: c.gold,
          countText: c.onAccent,
        );
      case _ChatType.store:
        return _ChatAccent(
          bg: c.s2,
          border: c.s3,
          text: c.cream2,
          dot: c.gold,
          countBg: c.gold,
          countText: c.onAccent,
        );
    }
  }

  String _avatarLetter(_ChatType type, String name) {
    if (type == _ChatType.announce) return 'A';
    if (type == _ChatType.global) return 'G';
    if (type == _ChatType.team) return 'T';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name.substring(0, 1).toUpperCase() : '?';
  }

  String _buildPreview(ChatRoom room) {
    final sender = room.lastMessageSenderName ?? 'Administrator';
    final msg = room.lastMessageContent ?? '';
    if (msg.isEmpty) return '';
    if (msg.startsWith('report_request_card::')) {
      return 'Permintaan laporan progress';
    }
    if (msg.startsWith('clock_in_success::')) {
      final parts = msg.split('::');
      final promotorName = parts.length > 1 && parts[1].trim().isNotEmpty
          ? parts[1].trim()
          : sender;
      return '$promotorName berhasil absen masuk';
    }
    return '$sender: $msg';
  }

  String _displayRoomName(ChatRoom room) {
    final raw = room.name.trim();
    if (raw.isEmpty) {
      if (_matchType(room, 'announcement')) return 'Info';
      if (_matchType(room, 'global')) return 'Global';
      if (_matchType(room, 'team')) return 'Tim';
      return '';
    }
    if (_matchType(room, 'announcement')) {
      return 'Info';
    }
    if (_matchType(room, 'global')) {
      return 'Global';
    }
    if (!_matchType(room, 'team')) {
      return raw
          .replaceFirst(RegExp(r'^chat\s+', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s+chat$', caseSensitive: false), '')
          .trim();
    }
    final cleaned = raw
        .replaceFirst(RegExp(r'^grup\s+tim\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^team\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^tim\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'^chat\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+chat$', caseSensitive: false), '')
        .trim();
    if (cleaned.isEmpty) return 'Tim';
    return 'Tim $cleaned';
  }

  String _formatTimeLabel(DateTime? time) {
    if (time == null) return '';
    final now = DateTime.now();
    final date = DateTime(time.year, time.month, time.day);
    final today = DateTime(now.year, now.month, now.day);
    if (date == today) {
      return DateFormat('HH:mm').format(time);
    }
    if (date == today.subtract(const Duration(days: 1))) {
      return 'Kemarin';
    }
    return DateFormat('EEE', 'id_ID').format(time);
  }

  List<ChatRoom> _sortRooms(List<ChatRoom> rooms) {
    final sorted = List.of(rooms);
    sorted.sort((a, b) {
      if (a.unreadCount > 0 && b.unreadCount == 0) return -1;
      if (a.unreadCount == 0 && b.unreadCount > 0) return 1;
      if (a.lastMessageTime != null && b.lastMessageTime != null) {
        return b.lastMessageTime!.compareTo(a.lastMessageTime!);
      }
      if (a.lastMessageTime != null) return -1;
      if (b.lastMessageTime != null) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
    return sorted;
  }

  void _navigateToRoom(BuildContext context, ChatRoom room) async {
    context.read<ChatListCubit>().markRoomAsRead(room.id);
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => ChatRoomPage(room: room)));
    if (context.mounted) {
      context.read<ChatListCubit>().refreshChatRooms();
    }
  }
}

enum _ChatType { announce, global, team, store }

enum _ChatTab { all, announcement, global, team, store }

class _ChatAccent {
  final Color bg;
  final Color border;
  final Color text;
  final Color dot;
  final Color countBg;
  final Color countText;

  _ChatAccent({
    required this.bg,
    required this.border,
    required this.text,
    required this.dot,
    required this.countBg,
    required this.countText,
  });
}
