import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../cubit/chat_room_cubit.dart';
import '../../models/chat_room.dart';
import '../../models/chat_message.dart';
import '../../models/chat_room_member.dart';
import '../../repository/chat_repository.dart';
import '../widgets/store_performance_panel.dart';
import '../theme/chat_theme.dart';
import '../../../../core/widgets/user_avatar.dart';
import '../../../../core/utils/cloudinary_upload_helper.dart';
import '../../../../ui/promotor/promotor_theme.dart';

class ChatRoomPage extends StatelessWidget {
  final ChatRoom room;

  const ChatRoomPage({super.key, required this.room});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          ChatRoomCubit(ChatRepository(), room)..loadChatRoom(),
      child: ChatRoomView(room: room),
    );
  }
}

class ChatRoomView extends StatefulWidget {
  final ChatRoom room;

  const ChatRoomView({super.key, required this.room});

  @override
  State<ChatRoomView> createState() => _ChatRoomViewState();
}

class _ChatRoomViewState extends State<ChatRoomView> {
  static const List<String> _quickEmojis = <String>[
    '😀',
    '😁',
    '😂',
    '🤣',
    '😊',
    '😍',
    '😘',
    '🥰',
    '😎',
    '🤔',
    '🥹',
    '😭',
    '😡',
    '👍',
    '👎',
    '👏',
    '🙌',
    '🙏',
    '🔥',
    '❤️',
    '💯',
    '🎉',
    '🤝',
    '👌',
  ];
  static const List<String> _allBrandLabels = <String>[
    'Samsung',
    'OPPO',
    'Realme',
    'Xiaomi',
    'Infinix',
    'Tecno',
  ];

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _messageFocusNode = FocusNode();
  final ImagePicker _imagePicker = ImagePicker();
  final ChatRepository _repository = ChatRepository();

  ChatMessage? _replyTarget;
  List<ChatRoomMember> _roomMembers = const [];
  bool _showMentionPanel = false;
  bool _showEmojiPanel = false;
  bool _isUploadingImage = false;
  bool _isSendingMessage = false;
  bool _isLoadingRoomMembers = false;
  bool _isLoadingTeamLeaderboard = false;
  bool _isTeamLeaderboardExpanded = false;
  bool _showJumpToLatest = false;
  bool _showSearchBar = false;
  String? _roomMembersError;
  String _mentionSearchQuery = '';
  String _currentUserRole = '';
  int _lastMessageCount = 0;
  Timer? _teamLeaderboardTimer;
  List<Map<String, dynamic>> _teamLeaderboardRows =
      const <Map<String, dynamic>>[];
  final Map<String, String> _pendingMentionIds = <String, String>{};
  String? _lastSentDraftKey;
  DateTime? _lastSentDraftAt;

  ChatUiPalette get c => chatPaletteOf(context);
  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;
  List<ChatRoomMember> get _waTargetMembers {
    final currentUserId = _currentUserId;
    final targets = <ChatRoomMember>[];
    for (final member in _roomMembers) {
      if (member.id == currentUserId) continue;
      final phone = (member.whatsappPhone ?? '').trim();
      if (phone.isNotEmpty) {
        targets.add(member);
      }
    }
    return targets;
  }

  TextStyle _withEmojiFallback(TextStyle style) {
    return style.copyWith(
      fontFamilyFallback: const <String>[
        'Noto Color Emoji',
        'Apple Color Emoji',
        'Segoe UI Emoji',
        'Segoe UI Symbol',
        'sans-serif',
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _messageController.addListener(_handleComposerChanged);
    _loadRoomMembers();
    unawaited(_loadCurrentUserRole());
    unawaited(_loadTeamLeaderboard());
    if (widget.room.roomType == 'tim') {
      _teamLeaderboardTimer = Timer.periodic(
        const Duration(seconds: 20),
        (_) => _loadTeamLeaderboard(),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    _messageFocusNode.dispose();
    _teamLeaderboardTimer?.cancel();
    super.dispose();
  }

  void _handleComposerChanged() {
    final contextData = _activeMentionContext();
    final shouldShow = contextData != null;
    final nextQuery = contextData?.$3 ?? '';
    if (_showMentionPanel == shouldShow && _mentionSearchQuery == nextQuery) {
      return;
    }
    if (shouldShow && _roomMembers.isEmpty && !_isLoadingRoomMembers) {
      _loadRoomMembers();
    }
    if (!mounted) return;
    setState(() {
      _showMentionPanel = shouldShow;
      _mentionSearchQuery = nextQuery;
      if (shouldShow) {
        _showEmojiPanel = false;
      }
    });
  }

  Future<void> _loadCurrentUserRole() async {
    final userId = _currentUserId;
    if (userId == null) return;
    final metadataRole =
        '${Supabase.instance.client.auth.currentUser?.userMetadata?['role'] ?? ''}'
            .trim()
            .toLowerCase();
    if (metadataRole.isNotEmpty) {
      if (mounted) {
        setState(() => _currentUserRole = metadataRole);
      }
      return;
    }
    try {
      final row = await Supabase.instance.client
          .from('users')
          .select('role')
          .eq('id', userId)
          .maybeSingle();
      if (!mounted || row == null) return;
      setState(
        () => _currentUserRole = '${row['role'] ?? ''}'.trim().toLowerCase(),
      );
    } catch (_) {}
  }

  Future<void> _loadTeamLeaderboard() async {
    if (widget.room.roomType != 'tim' || widget.room.satorId == null) return;
    if (!mounted) return;
    setState(() => _isLoadingTeamLeaderboard = true);
    try {
      final raw = await Supabase.instance.client.rpc(
        'get_team_daily_leaderboard',
        params: <String, dynamic>{
          'p_sator_id': widget.room.satorId,
          'p_date': DateTime.now().toIso8601String().split('T').first,
        },
      );
      final rows = (raw as List? ?? const [])
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
      if (!mounted) return;
      setState(() {
        _teamLeaderboardRows = rows;
        _isLoadingTeamLeaderboard = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _teamLeaderboardRows = const <Map<String, dynamic>>[];
        _isLoadingTeamLeaderboard = false;
      });
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels == 0) {
      context.read<ChatRoomCubit>().loadMoreMessages();
    }
    if (_scrollController.hasClients) {
      final distanceToBottom =
          _scrollController.position.maxScrollExtent -
          _scrollController.position.pixels;
      final shouldShow = distanceToBottom > 220;
      if (shouldShow != _showJumpToLatest && mounted) {
        setState(() => _showJumpToLatest = shouldShow);
      }
    }
  }

  Future<void> _loadRoomMembers() async {
    if (_isLoadingRoomMembers) return;
    if (mounted) {
      setState(() {
        _isLoadingRoomMembers = true;
        _roomMembersError = null;
      });
    }
    try {
      final members = await _repository.getRoomMembers(roomId: widget.room.id);
      if (!mounted) return;
      setState(() {
        _roomMembers = members;
        _isLoadingRoomMembers = false;
      });
    } catch (e) {
      debugPrint('Failed to load room members for mention: $e');
      if (!mounted) return;
      setState(() {
        _isLoadingRoomMembers = false;
        _roomMembersError = '$e';
      });
    }
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      } else {
        _scrollController.jumpTo(target);
      }
      if (_showJumpToLatest && mounted) {
        setState(() => _showJumpToLatest = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: c.bg,
      body: BlocConsumer<ChatRoomCubit, ChatRoomState>(
        listener: (context, state) {
          if (state is ChatRoomLoaded) {
            final nextCount = state.messages.length;
            final hasNewMessage = nextCount > _lastMessageCount;
            final isFirstLoad = _lastMessageCount == 0 && nextCount > 0;
            _lastMessageCount = nextCount;
            if (isFirstLoad) {
              _scrollToBottom(animated: false);
            } else if (hasNewMessage) {
              _scrollToBottom();
            }
          }
        },
        builder: (context, state) {
          if (state is ChatRoomLoading) {
            return Center(child: CircularProgressIndicator(color: c.gold));
          }

          if (state is ChatRoomError) {
            return Center(
              child: Text(
                state.message,
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w700,
                  color: c.muted,
                ),
              ),
            );
          }

          if (state is ChatRoomLoaded) {
            final messages = _sortedMessages(_visibleMessages(state.messages));
            final messageWidgets = _buildMessageWidgets(messages);
            return Stack(
              children: [
                Column(
                  children: [
                    _buildHeader(state.room),
                    if (state.room.roomType == 'tim')
                      _buildTeamLeaderboardPanel(),
                    if (state.room.roomType == 'toko' &&
                        state.room.tokoId != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: StorePerformancePanel(
                          storeId: state.room.tokoId!,
                          storeName: state.room.name,
                        ),
                      ),
                    Expanded(
                      child: Stack(
                        children: [
                          ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 84),
                            itemCount: messageWidgets.length,
                            itemBuilder: (context, index) =>
                                messageWidgets[index],
                          ),
                          if (state.isLoadingMore)
                            Positioned(
                              top: 8,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.surfaceRaised,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(color: c.s3),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                c.gold,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Memuat pesan lama',
                                        style: PromotorText.outfit(
                                          size: 10,
                                          weight: FontWeight.w700,
                                          color: c.muted2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (_showJumpToLatest)
                  Positioned(
                    right: 14,
                    bottom: 96,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => _scrollToBottom(),
                        borderRadius: BorderRadius.circular(999),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: c.surfaceRaised,
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: c.s3),
                            boxShadow: [
                              BoxShadow(
                                color: c.shadow.withValues(alpha: 0.12),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.arrow_downward_rounded,
                                size: 15,
                                color: c.gold,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Terbaru',
                                style: PromotorText.outfit(
                                  size: 10,
                                  weight: FontWeight.w800,
                                  color: c.cream,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _buildInputArea(state),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Widget _buildHeader(ChatRoom room) {
    final displayRoomName = _displayRoomName(room);
    final roomMetaLabel = _roomMetaLabel(room);
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
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
            GestureDetector(
              onTap: () => Navigator.of(context).pop(),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: c.s1,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: c.s3),
                ),
                child: Icon(
                  Icons.chevron_left_rounded,
                  size: 18,
                  color: c.muted,
                ),
              ),
            ),
            const SizedBox(width: 10),
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
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: 'Cari pesan...',
                          hintStyle: PromotorText.outfit(
                            size: 12,
                            weight: FontWeight.w600,
                            color: c.muted,
                          ),
                          border: InputBorder.none,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        style: PromotorText.outfit(
                          size: 12,
                          weight: FontWeight.w600,
                          color: c.cream,
                        ),
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: c.s1,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: c.s3),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: c.green,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      displayRoomName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: PromotorText.outfit(
                                        size: 13,
                                        weight: FontWeight.w700,
                                        color: c.cream,
                                      ),
                                    ),
                                    if (roomMetaLabel.isNotEmpty) ...[
                                      const SizedBox(height: 1),
                                      Text(
                                        roomMetaLabel,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: PromotorText.outfit(
                                          size: 10,
                                          weight: FontWeight.w700,
                                          color: c.muted,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
            const SizedBox(width: 10),
            Row(
              children: [
                if (_waTargetMembers.isNotEmpty) ...[
                  _headerIcon(
                    Icons.phone_in_talk_rounded,
                    onTap: _onWhatsAppPressed,
                  ),
                  const SizedBox(width: 8),
                ],
                _headerIcon(
                  _showSearchBar ? Icons.close_rounded : Icons.search,
                  onTap: () {
                    setState(() {
                      _showSearchBar = !_showSearchBar;
                      if (!_showSearchBar) {
                        _searchController.clear();
                      }
                    });
                  },
                ),
                const SizedBox(width: 8),
                _headerIcon(
                  Icons.more_horiz,
                  onTap: () => _showHeaderMenu(room),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerIcon(IconData icon, {VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: c.s3),
        ),
        child: Icon(icon, size: 16, color: c.muted),
      ),
    );
  }

  Future<void> _onWhatsAppPressed() async {
    final targets = _waTargetMembers;
    if (targets.isEmpty) return;
    if (targets.length == 1) {
      await _openWhatsApp(targets.first);
      return;
    }
    await _showWhatsAppPicker(targets);
  }

  Future<void> _showWhatsAppPicker(List<ChatRoomMember> members) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surfaceRaised,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Pilih kontak WhatsApp',
                      style: PromotorText.outfit(
                        size: 14,
                        weight: FontWeight.w800,
                        color: c.cream,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: members.length,
                separatorBuilder: (_, _) => Divider(height: 1, color: c.s3),
                itemBuilder: (context, index) {
                  final member = members[index];
                  return ListTile(
                    title: Text(
                      member.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: c.cream,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      unawaited(_openWhatsApp(member));
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openWhatsApp(ChatRoomMember member) async {
    final normalized = _normalizeWhatsAppNumber(member.whatsappPhone);
    if (normalized.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nomor WhatsApp belum tersedia')),
      );
      return;
    }

    final uri = Uri.parse('https://wa.me/$normalized');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('WhatsApp tidak bisa dibuka')),
      );
    }
  }

  String _normalizeWhatsAppNumber(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('62')) return digits;
    if (digits.startsWith('0')) return '62${digits.substring(1)}';
    return digits;
  }

  bool _canPostAnnouncement() =>
      _currentUserRole == 'spv' || _currentUserRole == 'admin';

  Future<void> _showHeaderMenu(ChatRoom room) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surfaceRaised,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.search_rounded, color: c.cream2),
              title: Text(
                _showSearchBar ? 'Tutup pencarian' : 'Cari pesan',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: c.cream,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() {
                  _showSearchBar = !_showSearchBar;
                  if (!_showSearchBar) {
                    _searchController.clear();
                  }
                });
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_outline_rounded, color: c.red),
              title: Text(
                'Hapus pesan',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: c.red,
                ),
              ),
              onTap: () async {
                Navigator.pop(sheetContext);
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialogContext) => AlertDialog(
                    backgroundColor: c.surfaceRaised,
                    title: Text(
                      'Hapus pesan?',
                      style: PromotorText.outfit(
                        size: 16,
                        weight: FontWeight.w800,
                        color: c.cream,
                      ),
                    ),
                    content: Text(
                      'Semua pesan Anda di room ini akan disembunyikan.',
                      style: PromotorText.outfit(
                        size: 12,
                        weight: FontWeight.w600,
                        color: c.muted2,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: Text(
                          'Batal',
                          style: PromotorText.outfit(
                            size: 12,
                            weight: FontWeight.w700,
                            color: c.muted2,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: Text(
                          'Hapus',
                          style: PromotorText.outfit(
                            size: 12,
                            weight: FontWeight.w800,
                            color: c.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !mounted) return;
                await context.read<ChatRoomCubit>().deleteMyMessagesInRoom();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Pesan Anda di room ini dihapus'),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  String _displayRoomName(ChatRoom room) {
    final raw = room.name.trim();
    final lower = raw.toLowerCase();
    if (room.roomType == 'tim' || lower.contains('tim')) {
      final cleaned = raw
          .replaceFirst(RegExp(r'^grup\s+tim\s+', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^team\s+', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^tim\s+', caseSensitive: false), '')
          .replaceFirst(RegExp(r'^chat\s+', caseSensitive: false), '')
          .replaceFirst(RegExp(r'\s+chat$', caseSensitive: false), '')
          .trim();
      return cleaned.isEmpty ? 'Tim' : 'Tim $cleaned';
    }
    if (room.roomType == 'global' || lower.contains('global')) {
      return 'Global';
    }
    if (room.roomType == 'announcement' || lower.contains('announce')) {
      return 'Info';
    }
    return raw
        .replaceFirst(RegExp(r'^chat\s+', caseSensitive: false), '')
        .replaceFirst(RegExp(r'\s+chat$', caseSensitive: false), '')
        .trim();
  }

  String _roomMetaLabel(ChatRoom room) {
    if (room.roomType == 'tim') return 'Grup tim';
    if (room.roomType == 'leader') return 'Grup leader';
    if (room.roomType == 'global') return 'Chat global';
    if (room.roomType == 'announcement') return 'Announcement';
    if (room.roomType == 'toko') return 'Chat toko';
    return '';
  }

  bool _canMentionAll(ChatRoomLoaded state) {
    final roomType = state.room.roomType;
    if (roomType == 'tim') {
      return _currentUserRole == 'sator' &&
          state.room.satorId == _currentUserId;
    }
    if (roomType == 'global') {
      return _currentUserRole == 'spv' || _currentUserRole == 'admin';
    }
    return false;
  }

  Widget _buildTeamLeaderboardPanel() {
    final hasOverflow = _teamLeaderboardRows.length > 3;
    final visibleRows = _isTeamLeaderboardExpanded || !hasOverflow
        ? _teamLeaderboardRows
        : _teamLeaderboardRows.take(3).toList();
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.leaderboard_rounded, size: 16, color: c.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Leaderboard Tim Hari Ini',
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w800,
                    color: c.cream,
                  ),
                ),
              ),
              if (hasOverflow)
                TextButton(
                  onPressed: () => setState(
                    () => _isTeamLeaderboardExpanded =
                        !_isTeamLeaderboardExpanded,
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: const Size(0, 28),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    _isTeamLeaderboardExpanded ? 'Ringkas' : 'Lihat semua',
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w800,
                      color: c.gold,
                    ),
                  ),
                ),
              if (_isLoadingTeamLeaderboard)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(c.gold),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_teamLeaderboardRows.isEmpty)
            Text(
              'Belum ada penjualan hari ini.',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: c.muted2,
              ),
            )
          else
            ...visibleRows.map((row) {
              final rank = '${row['rank'] ?? '-'}';
              final name = '${row['promotor_name'] ?? 'Promotor'}';
              final target = _compactCurrency(row['daily_target']);
              final omzet = _compactCurrency(row['total_revenue']);
              final soldLabel = '${row['variants_sold'] ?? '-'}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 24,
                      child: Text(
                        '#$rank',
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w800,
                          color: c.gold,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      flex: 4,
                      child: Row(
                        children: [
                          Flexible(
                            flex: 2,
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: PromotorText.outfit(
                                size: 11,
                                weight: FontWeight.w800,
                                color: c.cream,
                              ),
                            ),
                          ),
                          if (soldLabel.trim().isNotEmpty &&
                              soldLabel.trim() != '-') ...[
                            const SizedBox(width: 6),
                            Flexible(
                              flex: 3,
                              child: Text(
                                soldLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PromotorText.outfit(
                                  size: 9,
                                  weight: FontWeight.w700,
                                  color: c.muted2,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(
                        minWidth: 88,
                        maxWidth: 108,
                      ),
                      child: Text(
                        '$omzet / $target',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                        style: PromotorText.outfit(
                          size: 9,
                          weight: FontWeight.w700,
                          color: c.muted2,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  String _compactCurrency(dynamic value) {
    final amount = value is num ? value : num.tryParse('${value ?? ''}') ?? 0;
    if (amount >= 1000000) {
      return 'Rp ${(amount / 1000000).toStringAsFixed(amount >= 10000000 ? 0 : 1)}jt';
    }
    if (amount >= 1000) {
      return 'Rp ${(amount / 1000).toStringAsFixed(amount >= 100000 ? 0 : 1)}rb';
    }
    return 'Rp ${amount.toStringAsFixed(0)}';
  }

  List<ChatMessage> _visibleMessages(List<ChatMessage> messages) {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return messages;
    return messages.where((message) {
      final content = (message.content ?? '').toLowerCase();
      final sender = (message.senderName ?? '').toLowerCase();
      return content.contains(query) || sender.contains(query);
    }).toList();
  }

  List<ChatMessage> _sortedMessages(List<ChatMessage> messages) {
    final list = List<ChatMessage>.from(messages);
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  List<Widget> _buildMessageWidgets(List<ChatMessage> messages) {
    final widgets = <Widget>[];
    DateTime? currentDate;
    ChatMessage? prev;
    final unreadIndex = _firstUnreadIndex(messages);

    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      final msgDate = DateTime(
        msg.createdAt.year,
        msg.createdAt.month,
        msg.createdAt.day,
      );

      if (currentDate == null || msgDate != currentDate) {
        currentDate = msgDate;
        widgets.add(_dateDivider(msgDate));
      }

      if (unreadIndex != null && i == unreadIndex) {
        widgets.add(_unreadDivider());
      }

      if (msg.messageType == 'system') {
        widgets.add(_systemMessage(msg.content ?? ''));
        prev = msg;
        continue;
      }

      final sameSender =
          prev != null &&
          prev.senderId == msg.senderId &&
          prev.isOwnMessage == msg.isOwnMessage &&
          prev.messageType != 'system' &&
          _isSameDay(prev.createdAt, msg.createdAt);

      widgets.add(_messageRow(msg, showAvatar: !sameSender));
      prev = msg;
    }

    return widgets;
  }

  int? _firstUnreadIndex(List<ChatMessage> messages) {
    for (var i = 0; i < messages.length; i++) {
      final msg = messages[i];
      if (!msg.isOwnMessage && msg.readByCount == 0) return i;
    }
    return null;
  }

  Widget _dateDivider(DateTime date) {
    final label = _dateLabel(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: c.s3)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.s3),
            ),
            child: Text(
              label,
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: c.muted2,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: c.s3)),
        ],
      ),
    );
  }

  Widget _unreadDivider() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: c.s3)),
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Color.lerp(c.goldDim, c.surfaceRaised, 0.3)!,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: c.gold.withValues(alpha: 0.16)),
            ),
            child: Text(
              '1 pesan baru',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: c.gold,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: c.s3)),
        ],
      ),
    );
  }

  Widget _systemMessage(String text) {
    return Align(
      alignment: Alignment.center,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: c.surfaceRaised,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: c.s3),
        ),
        child: Text(
          text,
          style: PromotorText.outfit(
            size: 11,
            weight: FontWeight.w700,
            color: c.muted,
          ),
        ),
      ),
    );
  }

  Widget _messageRow(ChatMessage message, {required bool showAvatar}) {
    final isOut = message.isOwnMessage;
    final senderName = message.senderName ?? 'User';
    final senderAvatarUrl = _senderAvatarUrl(message.senderId);
    final timeLabel = DateFormat('HH:mm').format(message.createdAt);
    final reactions = _reactionList(message.reactions);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: isOut
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisAlignment: isOut
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        children: [
          if (!isOut)
            Visibility(
              visible: showAvatar,
              maintainSize: true,
              maintainAnimation: true,
              maintainState: true,
              child: Container(
                width: 26,
                height: 26,
                margin: const EdgeInsets.only(right: 6, top: 1),
                decoration: BoxDecoration(
                  color: c.s2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.s3),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: showAvatar
                      ? UserAvatar(
                          avatarUrl: senderAvatarUrl,
                          fullName: senderName,
                          radius: 13,
                          backgroundColor: c.s2,
                          textColor: c.cream,
                          fontSize: 11,
                        )
                      : const SizedBox.shrink(),
                ),
              ),
            )
          else
            const SizedBox(width: 32),
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              child: Column(
                crossAxisAlignment: isOut
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                children: [
                  if (!isOut && showAvatar)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3, left: 2),
                      child: Text(
                        senderName,
                        style: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w700,
                          color: Color.lerp(c.gold, c.cream2, 0.18)!,
                        ),
                      ),
                    ),
                  GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onLongPressStart: (_) => _showMessageActions(message),
                    child: _bubble(message, isOut),
                  ),
                  if (reactions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: reactions
                            .map((r) => _reactionChip(message, r))
                            .toList(),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          timeLabel,
                          style: PromotorText.outfit(
                            size: 8,
                            weight: FontWeight.w700,
                            color: c.muted,
                          ),
                        ),
                        if (isOut) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.done_all,
                            size: 15,
                            color: message.readByCount > 0 ? c.green : c.muted,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String? _senderAvatarUrl(String? senderId) {
    if (senderId == null || senderId.isEmpty) return null;
    for (final member in _roomMembers) {
      if (member.id == senderId) {
        final avatarUrl = member.avatarUrl?.trim();
        return avatarUrl != null && avatarUrl.isNotEmpty ? avatarUrl : null;
      }
    }
    return null;
  }

  Widget _bubble(ChatMessage message, bool isOut) {
    final hasImage = message.messageType == 'image' || message.imageUrl != null;
    final hasReply = message.replyToContent != null;
    final isTargetCard = !hasImage && _isTargetCardMessage(message);
    final isImeiNormalizationCard =
        !hasImage && _isImeiNormalizationCardMessage(message);
    final isReportRequestCard =
        !hasImage && _isReportRequestCardMessage(message);
    final isAnnouncementCard =
        !hasImage &&
        widget.room.roomType == 'announcement' &&
        (message.content ?? '').trim().isNotEmpty;
    final borderColor = isOut ? c.gold.withValues(alpha: 0.14) : c.s3;
    final radius = BorderRadius.only(
      topLeft: const Radius.circular(16),
      topRight: const Radius.circular(16),
      bottomLeft: Radius.circular(isOut ? 16 : 4),
      bottomRight: Radius.circular(isOut ? 4 : 16),
    );

    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(color: borderColor),
        gradient: isOut
            ? LinearGradient(
                colors: [
                  Color.lerp(c.gold, c.s2, 0.8)!,
                  Color.lerp(c.goldInk, c.s1, 0.88)!,
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: isOut ? null : c.s1,
      ),
      padding: EdgeInsets.all(hasImage ? 6 : 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasReply)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              margin: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                color: c.s2,
                borderRadius: BorderRadius.circular(6),
                border: Border(left: BorderSide(color: c.gold, width: 2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.replyToSenderName ?? 'Kamu',
                    style: PromotorText.outfit(
                      size: 8,
                      weight: FontWeight.w700,
                      color: c.gold,
                    ),
                  ),
                  Text(
                    _replyPreviewText(message.replyToContent),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: c.muted,
                    ),
                  ),
                ],
              ),
            ),

          if (isTargetCard)
            _buildTargetCard(message)
          else if (isImeiNormalizationCard)
            _buildImeiNormalizationCard(message)
          else if (isReportRequestCard)
            _buildReportRequestCard(message)
          else if (isAnnouncementCard)
            _buildAnnouncementCard(message)
          else if (hasImage)
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onTap: message.imageUrl == null
                    ? null
                    : () => _openImageViewer(message.imageUrl!),
                child: Container(
                  width: double.infinity,
                  height: 120,
                  color: c.s2,
                  child: message.imageUrl != null
                      ? Image.network(
                          message.imageUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              _imagePlaceholder(),
                        )
                      : _imagePlaceholder(),
                ),
              ),
            ),
          if (hasImage && message.content != null) const SizedBox(height: 6),
          if (!isTargetCard &&
              !isImeiNormalizationCard &&
              !isReportRequestCard &&
              !isAnnouncementCard &&
              message.content != null &&
              message.content!.isNotEmpty)
            _messageContentText(message.content!, isOut),
        ],
      ),
    );
  }

  Widget _messageContentText(String text, bool isOut) {
    final normalizedText = text.replaceAllMapped(
      RegExp(r'@\{([^}]+)\}'),
      (match) => '@${match.group(1)}',
    );
    final mentionStyle =
        PromotorText.outfit(
          size: 13,
          weight: FontWeight.w900,
          color: isOut ? c.cream : c.blue,
        ).copyWith(
          decoration: TextDecoration.underline,
          decorationColor: isOut ? c.gold : c.blue,
          decorationThickness: 1.6,
        );
    final mentionRichStyle = _withEmojiFallback(mentionStyle);
    final baseStyle = _withEmojiFallback(
      PromotorText.outfit(
        size: 13,
        weight: FontWeight.w500,
        color: isOut ? c.cream : c.cream2,
      ),
    );
    final mentionTokens =
        _roomMembers
            .map((member) => '@${member.displayName}')
            .where((token) => token.trim().length > 1)
            .toSet()
            .toList()
          ..add('@all')
          ..sort((a, b) => b.length.compareTo(a.length));
    final escapedTokens = mentionTokens.map(RegExp.escape).toList();
    final mentionPattern = escapedTokens.isEmpty
        ? RegExp(r'@\S+', caseSensitive: false)
        : RegExp('(${escapedTokens.join('|')}|@\\S+)', caseSensitive: false);
    final spans = <TextSpan>[];
    var cursor = 0;
    for (final match in mentionPattern.allMatches(normalizedText)) {
      if (match.start > cursor) {
        spans.add(
          TextSpan(
            text: normalizedText.substring(cursor, match.start),
            style: baseStyle,
          ),
        );
      }
      final mentionText = match.group(0);
      if (mentionText != null && mentionText.isNotEmpty) {
        spans.add(TextSpan(text: mentionText, style: mentionRichStyle));
      }
      cursor = match.end;
    }
    if (cursor < normalizedText.length) {
      spans.add(
        TextSpan(text: normalizedText.substring(cursor), style: baseStyle),
      );
    }

    return RichText(
      text: TextSpan(
        children: spans.isEmpty
            ? [TextSpan(text: normalizedText, style: baseStyle)]
            : spans,
      ),
    );
  }

  Widget _imagePlaceholder() {
    return Container(
      alignment: Alignment.center,
      child: Icon(Icons.image_outlined, size: 22, color: c.muted2),
    );
  }

  bool _isTargetCardMessage(ChatMessage message) =>
      (message.content ?? '').startsWith('target_card::');

  bool _isImeiNormalizationCardMessage(ChatMessage message) =>
      (message.content ?? '').startsWith('imei_normalization_card::');

  bool _isReportRequestCardMessage(ChatMessage message) =>
      (message.content ?? '').startsWith('report_request_card::');

  String _replyPreviewText(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return '';
    if (text.startsWith('target_card::')) return 'Card target harian';
    if (text.startsWith('imei_normalization_card::')) {
      try {
        final payload = Map<String, dynamic>.from(
          jsonDecode(text.replaceFirst('imei_normalization_card::', '')),
        );
        final imei = '${payload['imei'] ?? ''}'.trim();
        return imei.isEmpty ? 'Card IMEI siap scan' : 'IMEI $imei siap scan';
      } catch (_) {
        return 'Card IMEI siap scan';
      }
    }
    if (text.startsWith('report_request_card::')) {
      return 'Card permintaan laporan';
    }
    return text;
  }

  Map<String, dynamic> _parseReportRequestPayload(ChatMessage message) {
    try {
      return Map<String, dynamic>.from(
        jsonDecode(
          (message.content ?? '').replaceFirst('report_request_card::', ''),
        ),
      );
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  bool _canSubmitReportCard(Map<String, dynamic> payload) {
    final requestType = '${payload['request_type'] ?? ''}'.trim();
    final effectiveRole = _effectiveCurrentUserRole();
    if (requestType == 'spv_to_sator') {
      return effectiveRole == 'sator';
    }
    if (requestType == 'sator_to_store') {
      return effectiveRole == 'promotor';
    }
    return false;
  }

  String _effectiveCurrentUserRole() {
    final direct = _currentUserRole.trim().toLowerCase();
    if (direct.isNotEmpty) return direct;
    final currentUserId = _currentUserId;
    if (currentUserId == null || currentUserId.isEmpty) return '';
    for (final member in _roomMembers) {
      if (member.id != currentUserId) continue;
      final role = (member.role ?? '').trim().toLowerCase();
      if (role.isNotEmpty) return role;
    }
    return '';
  }

  Map<String, dynamic>? _currentReportResponse(Map<String, dynamic> payload) {
    final responses = (payload['responses'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final requestType = '${payload['request_type'] ?? ''}'.trim();
    if (requestType == 'spv_to_sator') {
      for (final row in responses) {
        if ('${row['responder_user_id'] ?? ''}' == _currentUserId) {
          return row;
        }
      }
      return null;
    }
    return responses.isEmpty ? null : responses.first;
  }

  List<String> _reportSummaryLines(dynamic responsesRaw) {
    final responses = responsesRaw is Map
        ? Map<String, dynamic>.from(responsesRaw)
        : const <String, dynamic>{};
    final lines = <String>[];

    final answers = (responses['answers'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    for (final answer in answers) {
      final label = '${answer['label'] ?? ''}'.trim();
      final value = '${answer['value'] ?? ''}'.trim();
      if (label.isEmpty || value.isEmpty) continue;
      lines.add('$label: $value');
    }

    final promotors = (responses['promotors'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    for (final row in promotors) {
      final name = '${row['promotor_name'] ?? 'Promotor'}'.trim();
      final variant = '${row['variant_label'] ?? ''}'.trim();
      final vast = '${row['vast'] ?? ''}'.trim();
      final note = '${row['note'] ?? ''}'.trim();
      final parts = <String>[];
      if (variant.isNotEmpty) {
        final srp = _toInt(row['srp']);
        parts.add(
          srp > 0 ? '$variant • SRP ${_compactCurrency(srp)}' : variant,
        );
      }
      if (vast.isNotEmpty) parts.add('VAST $vast');
      if (note.isNotEmpty) parts.add(note);
      lines.add(parts.isEmpty ? name : '$name: ${parts.join(' • ')}');
    }

    final brands = (responses['brand_lain'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    for (final row in brands) {
      final brand = '${row['brand'] ?? ''}'.trim();
      final units = '${row['units'] ?? ''}'.trim();
      if (brand.isEmpty || units.isEmpty) continue;
      lines.add('$brand: $units unit');
    }

    final note = '${responses['note'] ?? responses['catatan_toko'] ?? ''}'
        .trim();
    if (note.isNotEmpty) {
      lines.add('Catatan: $note');
    }

    return lines;
  }

  Map<String, dynamic> _reportResponseMap(dynamic responsesRaw) {
    if (responsesRaw is Map<String, dynamic>) {
      return Map<String, dynamic>.from(responsesRaw);
    }
    if (responsesRaw is Map) return Map<String, dynamic>.from(responsesRaw);
    return const <String, dynamic>{};
  }

  Widget _buildStoreReportFrontSummary(Map<String, dynamic> response) {
    final responses = _reportResponseMap(response['responses']);
    final promotors = (responses['promotors'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final brands = (responses['brand_lain'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) {
          final brand = '${row['brand'] ?? ''}'.trim();
          final units = '${row['units'] ?? ''}'.trim();
          return brand.isNotEmpty && units.isNotEmpty;
        })
        .toList();
    final note = '${responses['note'] ?? responses['catatan_toko'] ?? ''}'
        .trim();
    final responder = '${response['responder_name'] ?? 'Promotor'}'.trim();
    final updatedAt = DateTime.tryParse('${response['updated_at'] ?? ''}');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: c.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'HASIL LAPORAN',
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w900,
                    color: c.green,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                updatedAt == null
                    ? responder
                    : '$responder • ${DateFormat('HH:mm', 'id_ID').format(updatedAt)}',
                style: PromotorText.outfit(
                  size: 9,
                  weight: FontWeight.w700,
                  color: c.muted2,
                ),
              ),
            ],
          ),
          if (promotors.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...promotors.map((row) {
              final name = '${row['promotor_name'] ?? 'Promotor'}'.trim();
              final variant = '${row['variant_label'] ?? ''}'.trim();
              final srp = _toInt(row['srp']);
              final vast = '${row['vast'] ?? ''}'.trim();
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.s1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.s3),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name.isEmpty ? 'Promotor' : name,
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w900,
                        color: c.cream,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (variant.isNotEmpty)
                          _buildStoreReportChip(
                            'Sellout',
                            srp > 0
                                ? '$variant • ${_formatFullCurrency(srp)}'
                                : variant,
                            c.gold,
                          ),
                        if (vast.isNotEmpty)
                          _buildStoreReportChip('VAST', vast, c.blue),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
          if (brands.isNotEmpty) ...[
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.s3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Brand Lain',
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w900,
                      color: c.gold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: brands
                        .map(
                          (row) => _buildStoreReportChip(
                            '${row['brand'] ?? '-'}',
                            '${row['units'] ?? '0'} unit',
                            c.purple,
                          ),
                        )
                        .toList(),
                  ),
                ],
              ),
            ),
          ],
          if (note.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.s3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Catatan Toko',
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w900,
                      color: c.gold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    note,
                    style: PromotorText.outfit(
                      size: 10,
                      weight: FontWeight.w700,
                      color: c.cream2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStoreReportChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 9,
              weight: FontWeight.w900,
              color: color,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w800,
              color: c.cream,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSatorProgressFrontSummary(Map<String, dynamic> response) {
    final responses = _reportResponseMap(response['responses']);
    final answers = (responses['answers'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final responder = '${response['responder_name'] ?? 'SATOR'}'.trim();
    final updatedAt = DateTime.tryParse('${response['updated_at'] ?? ''}');

    Map<String, dynamic>? findAnswer(bool Function(String label) match) {
      for (final answer in answers) {
        final label = '${answer['label'] ?? ''}'.trim();
        if (match(label)) return answer;
      }
      return null;
    }

    final sellout = findAnswer(_isSelloutReportField);
    final focus = findAnswer(_isFocusReportField);
    final vast = findAnswer(_isVastReportField);
    final extras = answers.where((answer) {
      final label = '${answer['label'] ?? ''}'.trim();
      return !_isSelloutReportField(label) &&
          !_isFocusReportField(label) &&
          !_isVastReportField(label);
    }).toList();

    Widget metricCard(String title, String value, Color color) {
      return Expanded(
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.22)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: PromotorText.outfit(
                  size: 9,
                  weight: FontWeight.w900,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value.isEmpty ? '-' : value,
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w800,
                  color: c.cream,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.s3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: c.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'HASIL LAPORAN',
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w900,
                    color: c.green,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                updatedAt == null
                    ? responder
                    : '$responder • ${DateFormat('HH:mm', 'id_ID').format(updatedAt)}',
                style: PromotorText.outfit(
                  size: 9,
                  weight: FontWeight.w700,
                  color: c.muted2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              metricCard(
                'Sellout',
                '${sellout?['value'] ?? ''}'.trim(),
                c.gold,
              ),
              const SizedBox(width: 8),
              metricCard(
                'Produk Fokus',
                '${focus?['value'] ?? ''}'.trim(),
                c.green,
              ),
              const SizedBox(width: 8),
              metricCard(
                'VAST Finance',
                '${vast?['value'] ?? ''}'.trim(),
                c.blue,
              ),
            ],
          ),
          if (extras.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.s3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: extras.map((answer) {
                  final label = '${answer['label'] ?? ''}'.trim();
                  final value = '${answer['value'] ?? ''}'.trim();
                  if (label.isEmpty || value.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      '$label: $value',
                      style: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w700,
                        color: c.cream2,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _loadStorePromotorRoster(
    String storeId,
  ) async {
    final rows = await Supabase.instance.client
        .from('assignments_promotor_store')
        .select('promotor_id, users!inner(full_name, nickname)')
        .eq('store_id', storeId)
        .eq('active', true);
    final items = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final raw in List<Map<String, dynamic>>.from(rows)) {
      final promotorId = '${raw['promotor_id'] ?? ''}'.trim();
      if (promotorId.isEmpty || !seen.add(promotorId)) continue;
      final user = raw['users'] is Map
          ? Map<String, dynamic>.from(raw['users'] as Map)
          : const <String, dynamic>{};
      final name = '${user['nickname'] ?? ''}'.trim().isNotEmpty
          ? '${user['nickname']}'
          : '${user['full_name'] ?? 'Promotor'}';
      items.add({'promotor_id': promotorId, 'promotor_name': name});
    }
    items.sort(
      (a, b) => '${a['promotor_name']}'.compareTo('${b['promotor_name']}'),
    );
    return items;
  }

  Future<List<String>> _loadStoreBrandOptions(String storeId) async {
    return List<String>.from(_allBrandLabels);
  }

  Future<List<Map<String, dynamic>>> _loadVariantOptions() async {
    final rows = await Supabase.instance.client
        .from('product_variants')
        .select(
          'id, ram_rom, color, srp, products!inner(model_name, network_type)',
        )
        .eq('active', true)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false);

    final items = <Map<String, dynamic>>[];
    for (final raw in List<Map<String, dynamic>>.from(rows)) {
      final product = raw['products'] is Map
          ? Map<String, dynamic>.from(raw['products'] as Map)
          : const <String, dynamic>{};
      final model = '${product['model_name'] ?? ''}'.trim();
      final network = '${product['network_type'] ?? ''}'.trim();
      final ramRom = '${raw['ram_rom'] ?? ''}'.trim();
      final color = '${raw['color'] ?? ''}'.trim();
      final labelParts = <String>[
        if (model.isNotEmpty) model,
        if (network.isNotEmpty) network,
        if (ramRom.isNotEmpty) ramRom,
        if (color.isNotEmpty) color,
      ];
      final label = labelParts.join(' • ');
      if (label.isEmpty) continue;
      items.add({
        'id': '${raw['id'] ?? ''}',
        'label': label,
        'srp': _toInt(raw['srp']),
      });
    }
    items.sort((a, b) {
      final srpCompare = _toInt(a['srp']).compareTo(_toInt(b['srp']));
      if (srpCompare != 0) return srpCompare;
      return '${a['label'] ?? ''}'.compareTo('${b['label'] ?? ''}');
    });
    return items;
  }

  Future<int> _loadCurrentPromotorDailyVastTarget() async {
    try {
      final snapshot = await Supabase.instance.client.rpc(
        'get_promotor_vast_page_snapshot',
        params: {'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now())},
      );
      final map = snapshot is Map
          ? Map<String, dynamic>.from(snapshot)
          : const <String, dynamic>{};
      return _toInt(_safeMap(map['daily_period_stats'])['target']);
    } catch (_) {
      return 0;
    }
  }

  Widget _buildReportRequestCard(ChatMessage message) {
    final payload = _parseReportRequestPayload(message);
    final requestType = '${payload['request_type'] ?? ''}'.trim();
    final title = '${payload['title'] ?? 'Permintaan laporan'}'.trim();
    final note = '${payload['note'] ?? ''}'.trim();
    final createdBy =
        '${payload['created_by'] ?? message.senderName ?? 'User'}';
    final createdAt = DateTime.tryParse('${payload['created_at'] ?? ''}');
    final fields = (payload['fields'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final responses = (payload['responses'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final currentResponse = _currentReportResponse(payload);
    final canRespond = _canSubmitReportCard(payload);
    final isStoreReport = requestType == 'sator_to_store';
    final isSatorProgressReport = requestType == 'spv_to_sator';

    return InkWell(
      onTap: canRespond && isStoreReport
          ? () => _openReportResponseSheet(payload)
          : null,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.s1,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.gold.withValues(alpha: 0.22)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.gold.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    requestType == 'sator_to_store'
                        ? 'LAPORAN TOKO'
                        : 'LAPORAN PROGRESS',
                    style: PromotorText.outfit(
                      size: 9,
                      weight: FontWeight.w900,
                      color: c.gold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  createdAt == null
                      ? ''
                      : DateFormat('HH:mm, dd MMM', 'id_ID').format(createdAt),
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w700,
                    color: c.muted2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w900,
                color: c.cream,
              ),
            ),
            if (!isSatorProgressReport) ...[
              const SizedBox(height: 4),
              Text(
                'Dikirim oleh $createdBy',
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w700,
                  color: c.muted2,
                ),
              ),
              if (note.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  note,
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w700,
                    color: c.cream2,
                  ),
                ),
              ],
            ] else if (note.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                note,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w700,
                  color: c.muted2,
                ),
              ),
            ],
            if (isStoreReport) ...[
              const SizedBox(height: 12),
              if (responses.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.s3),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.touch_app_rounded, size: 18, color: c.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentResponse == null
                              ? 'Ketuk card ini untuk isi laporan toko.'
                              : 'Ketuk card ini untuk lihat atau revisi isi laporan.',
                          style: PromotorText.outfit(
                            size: 10,
                            weight: FontWeight.w700,
                            color: c.cream2,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...responses.map(_buildStoreReportFrontSummary),
            ] else if (isSatorProgressReport) ...[
              const SizedBox(height: 12),
              if (responses.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.s3),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.insights_rounded, size: 18, color: c.gold),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          currentResponse == null
                              ? 'Isi laporan progress dari target harian SATOR.'
                              : 'Ketuk tombol di bawah untuk revisi laporan.',
                          style: PromotorText.outfit(
                            size: 10,
                            weight: FontWeight.w700,
                            color: c.cream2,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ...responses.map(_buildSatorProgressFrontSummary),
            ] else ...[
              const SizedBox(height: 10),
              Text(
                'Field laporan',
                style: PromotorText.outfit(
                  size: 10,
                  weight: FontWeight.w800,
                  color: c.gold,
                ),
              ),
              const SizedBox(height: 6),
              ...fields.map((field) {
                final label = '${field['label'] ?? ''}'.trim();
                final description = '${field['description'] ?? ''}'.trim();
                if (label.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: c.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.s3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: PromotorText.outfit(
                            size: 10,
                            weight: FontWeight.w800,
                            color: c.cream,
                          ),
                        ),
                        if (description.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            description,
                            style: PromotorText.outfit(
                              size: 9,
                              weight: FontWeight.w700,
                              color: c.muted2,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              if (responses.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  'Update tim',
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: c.gold,
                  ),
                ),
                const SizedBox(height: 6),
                ...responses.map((response) {
                  final responder = '${response['responder_name'] ?? 'User'}';
                  final updatedAt = DateTime.tryParse(
                    '${response['updated_at'] ?? ''}',
                  );
                  final lines = _reportSummaryLines(response['responses']);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: c.surfaceRaised,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: c.s3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                responder,
                                style: PromotorText.outfit(
                                  size: 10,
                                  weight: FontWeight.w800,
                                  color: c.cream,
                                ),
                              ),
                            ),
                            if (updatedAt != null)
                              Text(
                                DateFormat('HH:mm', 'id_ID').format(updatedAt),
                                style: PromotorText.outfit(
                                  size: 9,
                                  weight: FontWeight.w700,
                                  color: c.muted2,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        if (lines.isEmpty)
                          Text(
                            'Belum ada isi laporan.',
                            style: PromotorText.outfit(
                              size: 10,
                              weight: FontWeight.w700,
                              color: c.muted2,
                            ),
                          )
                        else
                          ...lines
                              .take(8)
                              .map(
                                (line) => Padding(
                                  padding: const EdgeInsets.only(bottom: 2),
                                  child: Text(
                                    line,
                                    style: PromotorText.outfit(
                                      size: 10,
                                      weight: FontWeight.w700,
                                      color: c.cream2,
                                    ),
                                  ),
                                ),
                              ),
                      ],
                    ),
                  );
                }),
              ],
            ],
            if (canRespond) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _openReportResponseSheet(payload),
                  icon: Icon(
                    currentResponse == null ? Icons.edit_note : Icons.refresh,
                    size: 18,
                  ),
                  label: Text(
                    currentResponse == null ? 'Isi laporan' : 'Revisi laporan',
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openReportResponseSheet(Map<String, dynamic> payload) async {
    final requestType = '${payload['request_type'] ?? ''}'.trim();
    if (requestType == 'sator_to_store') {
      await _openStoreReportResponseSheet(payload);
      return;
    }
    if (requestType == 'spv_to_sator') {
      await _openSatorProgressResponseSheet(payload);
      return;
    }
    await _openGenericReportResponseSheet(payload);
  }

  Future<void> _openSatorProgressResponseSheet(
    Map<String, dynamic> payload,
  ) async {
    final requestId = '${payload['request_id'] ?? ''}'.trim();
    if (requestId.isEmpty) {
      _showSnackBarMessage('Card laporan ini belum punya request yang valid.');
      return;
    }
    final userId =
        _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || userId.isEmpty) {
      _showSnackBarMessage('User SATOR tidak ditemukan.');
      return;
    }

    final fields = (payload['fields'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final currentResponse = _currentReportResponse(payload);
    final currentResponseMap =
        currentResponse != null && currentResponse['responses'] is Map
        ? Map<String, dynamic>.from(currentResponse['responses'] as Map)
        : const <String, dynamic>{};
    final existing =
        currentResponseMap['answers'] as List? ??
        const <Map<String, dynamic>>[];
    final existingMap = <String, String>{};
    for (final raw in existing.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final label = '${row['label'] ?? ''}'.trim();
      if (label.isEmpty) continue;
      existingMap[label] = '${row['value'] ?? ''}';
    }

    final snapshotRaw = await Supabase.instance.client.rpc(
      'get_sator_home_snapshot',
      params: <String, dynamic>{'p_sator_id': userId},
    );
    final vastSnapshotRaw = await Supabase.instance.client.rpc(
      'get_sator_vast_page_snapshot',
      params: {'p_date': DateFormat('yyyy-MM-dd').format(DateTime.now())},
    );
    final snapshot = snapshotRaw is Map
        ? Map<String, dynamic>.from(snapshotRaw)
        : const <String, dynamic>{};
    final vastSnapshot = vastSnapshotRaw is Map
        ? Map<String, dynamic>.from(vastSnapshotRaw)
        : const <String, dynamic>{};
    final dailySummary = _safeMap(snapshot['daily']);
    final dailyTarget = _safeMap(snapshot['daily_target']);
    final vastDaily = _safeMap(vastSnapshot['daily']);
    final targetNominal = _toInt(dailySummary['target_sellout']);
    final targetFocus = _toInt(
      dailySummary['target_fokus'] ??
          dailySummary['target_focus'] ??
          dailyTarget['target_daily_focus'],
    );
    final targetVast = _toInt(vastDaily['target_submissions']);

    final selloutField = fields.cast<Map<String, dynamic>?>().firstWhere(
      (field) => _isSelloutReportField('${field?['label'] ?? ''}'),
      orElse: () => null,
    );
    final focusField = fields.cast<Map<String, dynamic>?>().firstWhere(
      (field) => _isFocusReportField('${field?['label'] ?? ''}'),
      orElse: () => null,
    );
    final vastField = fields.cast<Map<String, dynamic>?>().firstWhere(
      (field) => _isVastReportField('${field?['label'] ?? ''}'),
      orElse: () => null,
    );

    final selloutController = TextEditingController(
      text: _formatFullCurrency(
        _extractFirstNumber(existingMap['${selloutField?['label'] ?? ''}']),
      ),
    );
    final focusController = TextEditingController(
      text: _extractFirstNumber(
        existingMap['${focusField?['label'] ?? ''}'],
      ).toString(),
    );
    final vastController = TextEditingController(
      text: _extractFirstNumber(
        existingMap['${vastField?['label'] ?? ''}'],
      ).toString(),
    );
    final targetNominalController = TextEditingController(
      text: _formatFullCurrency(targetNominal),
    );
    final targetFocusController = TextEditingController(text: '$targetFocus');
    final targetVastController = TextEditingController(text: '$targetVast');

    bool isSubmitting = false;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surfaceRaised,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              if (isSubmitting) return;
              final answers = <Map<String, dynamic>>[];
              for (final field in fields) {
                final label = '${field['label'] ?? ''}'.trim();
                if (label.isEmpty) continue;
                String value = '';
                if (_isSelloutReportField(label)) {
                  value =
                      '${selloutController.text.trim()} / ${_formatFullCurrency(targetNominal)}';
                } else if (_isVastReportField(label)) {
                  final vastActual = _toInt(vastController.text.trim());
                  value = '$vastActual / $targetVast';
                } else if (_isFocusReportField(label)) {
                  final focusActual = _toInt(focusController.text.trim());
                  value = '$focusActual / $targetFocus';
                }
                answers.add({
                  'label': label,
                  'description': '${field['description'] ?? ''}'.trim(),
                  'value': value,
                });
              }
              setModalState(() => isSubmitting = true);
              try {
                await Supabase.instance.client.rpc(
                  'submit_chat_report_response',
                  params: {
                    'p_request_id': requestId,
                    'p_responses': {'answers': answers},
                  },
                );
                if (!mounted || !sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                await this.context.read<ChatRoomCubit>().refreshNow();
                _showSnackBarMessage('Laporan berhasil dikirim.');
              } catch (e) {
                _showSnackBarMessage('Gagal kirim laporan. $e');
              } finally {
                if (sheetContext.mounted) {
                  setModalState(() => isSubmitting = false);
                }
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${payload['title'] ?? 'Isi laporan'}',
                        style: PromotorText.outfit(
                          size: 14,
                          weight: FontWeight.w900,
                          color: c.cream,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (selloutField != null) ...[
                        TextField(
                          controller: selloutController,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                            _RupiahInputFormatter(),
                          ],
                          decoration: InputDecoration(
                            labelText: '${selloutField['label']}',
                            hintText: '${selloutField['description'] ?? ''}'
                                .trim(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: targetNominalController,
                          readOnly: true,
                          enableInteractiveSelection: false,
                          decoration: const InputDecoration(
                            labelText: 'Target harian SATOR',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (focusField != null) ...[
                        TextField(
                          controller: focusController,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: '${focusField['label']}',
                            hintText: '${focusField['description'] ?? ''}'
                                .trim(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: targetFocusController,
                          readOnly: true,
                          enableInteractiveSelection: false,
                          decoration: const InputDecoration(
                            labelText: 'Target harian produk fokus SATOR',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      if (vastField != null) ...[
                        TextField(
                          controller: vastController,
                          keyboardType: TextInputType.number,
                          inputFormatters: <TextInputFormatter>[
                            FilteringTextInputFormatter.digitsOnly,
                          ],
                          decoration: InputDecoration(
                            labelText: '${vastField['label']}',
                            hintText: '${vastField['description'] ?? ''}'
                                .trim(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: targetVastController,
                          readOnly: true,
                          enableInteractiveSelection: false,
                          decoration: const InputDecoration(
                            labelText: 'Target VAST SATOR',
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isSubmitting ? null : submit,
                          child: Text(isSubmitting ? 'Mengirim...' : 'Kirim'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    await Future<void>.delayed(kThemeAnimationDuration);
    selloutController.dispose();
    focusController.dispose();
    vastController.dispose();
    targetNominalController.dispose();
    targetFocusController.dispose();
    targetVastController.dispose();
  }

  Future<void> _openGenericReportResponseSheet(
    Map<String, dynamic> payload,
  ) async {
    final requestId = '${payload['request_id'] ?? ''}'.trim();
    if (requestId.isEmpty) {
      _showSnackBarMessage('Card laporan ini belum punya request yang valid.');
      return;
    }
    final fields = (payload['fields'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final currentResponse = _currentReportResponse(payload);
    final currentResponseMap =
        currentResponse != null && currentResponse['responses'] is Map
        ? Map<String, dynamic>.from(currentResponse['responses'] as Map)
        : const <String, dynamic>{};
    final existing =
        currentResponseMap['answers'] as List? ??
        const <Map<String, dynamic>>[];
    final existingMap = <String, String>{};
    for (final raw in existing.whereType<Map>()) {
      final row = Map<String, dynamic>.from(raw);
      final label = '${row['label'] ?? ''}'.trim();
      if (label.isEmpty) continue;
      existingMap[label] = '${row['value'] ?? ''}';
    }

    final controllers = <String, TextEditingController>{};
    for (final field in fields) {
      final label = '${field['label'] ?? ''}'.trim();
      if (label.isEmpty) continue;
      controllers[label] = TextEditingController(
        text: existingMap[label] ?? '',
      );
    }

    bool isSubmitting = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: c.surfaceRaised,
      builder: (sheetContext) {
        final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> submit() async {
              if (isSubmitting) return;
              final answers = <Map<String, dynamic>>[];
              for (final field in fields) {
                final label = '${field['label'] ?? ''}'.trim();
                if (label.isEmpty) continue;
                answers.add({
                  'label': label,
                  'description': '${field['description'] ?? ''}'.trim(),
                  'value': controllers[label]?.text.trim() ?? '',
                });
              }
              setModalState(() => isSubmitting = true);
              try {
                await Supabase.instance.client.rpc(
                  'submit_chat_report_response',
                  params: {
                    'p_request_id': requestId,
                    'p_responses': {'answers': answers},
                  },
                );
                if (!mounted || !sheetContext.mounted) return;
                Navigator.of(sheetContext).pop();
                await this.context.read<ChatRoomCubit>().refreshNow();
                _showSnackBarMessage('Laporan berhasil dikirim.');
              } catch (e) {
                _showSnackBarMessage('Gagal kirim laporan. $e');
              } finally {
                if (sheetContext.mounted) {
                  setModalState(() => isSubmitting = false);
                }
              }
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${payload['title'] ?? 'Isi laporan'}',
                        style: PromotorText.outfit(
                          size: 14,
                          weight: FontWeight.w900,
                          color: c.cream,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...fields.map((field) {
                        final label = '${field['label'] ?? ''}'.trim();
                        if (label.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: TextField(
                            controller: controllers[label],
                            maxLines: label.toLowerCase().contains('catatan')
                                ? 3
                                : 1,
                            decoration: InputDecoration(
                              labelText: label,
                              hintText:
                                  '${field['description'] ?? ''}'.trim().isEmpty
                                  ? null
                                  : '${field['description'] ?? ''}',
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 8),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: isSubmitting ? null : submit,
                          child: Text(isSubmitting ? 'Mengirim...' : 'Kirim'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    await Future<void>.delayed(kThemeAnimationDuration);
    for (final controller in controllers.values) {
      controller.dispose();
    }
  }

  Future<void> _openStoreReportResponseSheet(
    Map<String, dynamic> payload,
  ) async {
    final requestId = '${payload['request_id'] ?? ''}'.trim();
    final storeId = '${payload['store_id'] ?? widget.room.tokoId ?? ''}'.trim();
    if (requestId.isEmpty) {
      _showSnackBarMessage(
        'Card laporan toko ini belum punya request yang valid.',
      );
      return;
    }
    if (storeId.isEmpty) {
      _showSnackBarMessage('Store untuk laporan ini tidak ditemukan.');
      return;
    }

    final currentResponse = _currentReportResponse(payload);
    final existingResponses = currentResponse == null
        ? const <String, dynamic>{}
        : currentResponse['responses'] is Map
        ? Map<String, dynamic>.from(currentResponse['responses'] as Map)
        : const <String, dynamic>{};

    try {
      final promotors = await _loadStorePromotorRoster(storeId);
      final brandOptions = await _loadStoreBrandOptions(storeId);
      final variantOptions = await _loadVariantOptions();
      final currentUser = Supabase.instance.client.auth.currentUser;
      final currentPromotorId = (currentUser?.id ?? '').trim();
      final fallbackPromotorName =
          '${currentUser?.userMetadata?['nickname'] ?? currentUser?.userMetadata?['full_name'] ?? currentUser?.userMetadata?['name'] ?? 'Promotor'}'
              .trim();
      final selectedPromotors = promotors
          .where(
            (promotor) =>
                '${promotor['promotor_id'] ?? ''}' == currentPromotorId,
          )
          .toList();
      if (selectedPromotors.isEmpty) {
        selectedPromotors.add({
          'promotor_id': currentPromotorId,
          'promotor_name': fallbackPromotorName.isEmpty
              ? 'Promotor'
              : fallbackPromotorName,
        });
      }
      final dailyVastTarget = await _loadCurrentPromotorDailyVastTarget();

      final existingPromotors = <String, Map<String, dynamic>>{};
      for (final raw
          in (existingResponses['promotors'] as List? ?? const [])
              .whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        final promotorId = '${row['promotor_id'] ?? ''}'.trim();
        if (promotorId.isEmpty) continue;
        existingPromotors[promotorId] = row;
      }
      final existingBrands = <String, String>{};
      for (final raw
          in (existingResponses['brand_lain'] as List? ?? const [])
              .whereType<Map>()) {
        final row = Map<String, dynamic>.from(raw);
        final brand = '${row['brand'] ?? ''}'.trim();
        if (brand.isEmpty) continue;
        existingBrands[brand] = '${row['units'] ?? ''}';
      }

      final variantById = <String, Map<String, dynamic>>{
        for (final item in variantOptions) '${item['id'] ?? ''}': item,
      };
      final promotorDrafts = selectedPromotors.map((promotor) {
        final promotorId = '${promotor['promotor_id'] ?? ''}';
        final existing =
            existingPromotors[promotorId] ?? const <String, dynamic>{};
        return {
          'promotor_id': promotorId,
          'promotor_name': '${promotor['promotor_name'] ?? 'Promotor'}',
          'variant_id': '${existing['variant_id'] ?? ''}',
          'variant_label': '${existing['variant_label'] ?? ''}',
          'srp': _toInt(existing['srp']),
          'vast_target': dailyVastTarget,
          'vast_controller': TextEditingController(
            text: '${existing['vast'] ?? ''}',
          ),
        };
      }).toList();
      final brandControllers = <String, TextEditingController>{
        for (final brand in brandOptions)
          brand: TextEditingController(text: existingBrands[brand] ?? ''),
      };
      final storeNoteController = TextEditingController(
        text:
            '${existingResponses['catatan_toko'] ?? existingResponses['note'] ?? ''}',
      );
      bool isSubmitting = false;
      bool brandSectionExpanded = existingBrands.isNotEmpty;

      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: c.surfaceRaised,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (sheetContext) {
          final bottomInset = MediaQuery.of(sheetContext).viewInsets.bottom;
          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> chooseVariant(int index) async {
                final selected = await showModalBottomSheet<Map<String, dynamic>>(
                  context: sheetContext,
                  backgroundColor: c.surfaceRaised,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(24),
                    ),
                  ),
                  builder: (pickerContext) {
                    return SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Pilih tipe terjual',
                                        style: PromotorText.outfit(
                                          size: 13,
                                          weight: FontWeight.w900,
                                          color: c.cream,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Diurutkan dari harga termurah ke termahal.',
                                        style: PromotorText.outfit(
                                          size: 10,
                                          weight: FontWeight.w700,
                                          color: c.muted2,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  decoration: BoxDecoration(
                                    color: c.s1,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: c.s3),
                                  ),
                                  child: IconButton(
                                    onPressed: () =>
                                        Navigator.of(pickerContext).pop(),
                                    icon: Icon(
                                      Icons.close_rounded,
                                      color: c.cream2,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              height: 420,
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: variantOptions.length,
                                itemBuilder: (context, itemIndex) {
                                  final item = variantOptions[itemIndex];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    decoration: BoxDecoration(
                                      color: c.s1,
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(color: c.s3),
                                    ),
                                    child: ListTile(
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 6,
                                          ),
                                      title: Text(
                                        '${item['label'] ?? '-'}',
                                        style: PromotorText.outfit(
                                          size: 11,
                                          weight: FontWeight.w800,
                                          color: c.cream,
                                        ),
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          _formatFullCurrency(item['srp']),
                                          style: PromotorText.outfit(
                                            size: 10,
                                            weight: FontWeight.w800,
                                            color: c.gold,
                                          ),
                                        ),
                                      ),
                                      trailing: Icon(
                                        Icons.chevron_right_rounded,
                                        color: c.muted2,
                                      ),
                                      onTap: () =>
                                          Navigator.of(pickerContext).pop(item),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
                if (selected == null || !sheetContext.mounted) return;
                setModalState(() {
                  promotorDrafts[index]['variant_id'] =
                      '${selected['id'] ?? ''}';
                  promotorDrafts[index]['variant_label'] =
                      '${selected['label'] ?? ''}';
                  promotorDrafts[index]['srp'] = _toInt(selected['srp']);
                });
              }

              Future<void> submit() async {
                if (isSubmitting) return;
                final promotorRows = promotorDrafts.map((draft) {
                  final variantId = '${draft['variant_id'] ?? ''}'.trim();
                  final variant = variantById[variantId];
                  return {
                    'promotor_id': draft['promotor_id'],
                    'promotor_name': draft['promotor_name'],
                    'variant_id': variantId,
                    'variant_label':
                        '${draft['variant_label'] ?? variant?['label'] ?? ''}',
                    'srp': _toInt(draft['srp'] ?? variant?['srp']),
                    'vast': (draft['vast_controller'] as TextEditingController)
                        .text
                        .trim(),
                  };
                }).toList();
                final brandRows = brandControllers.entries
                    .map(
                      (entry) => {
                        'brand': entry.key,
                        'units': entry.value.text.trim(),
                      },
                    )
                    .where((row) => '${row['units']}'.isNotEmpty)
                    .toList();
                setModalState(() => isSubmitting = true);
                try {
                  await Supabase.instance.client.rpc(
                    'submit_chat_report_response',
                    params: {
                      'p_request_id': requestId,
                      'p_responses': {
                        'promotors': promotorRows,
                        'brand_lain': brandRows,
                        'catatan_toko': storeNoteController.text.trim(),
                      },
                    },
                  );
                  if (!mounted || !sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop();
                  await this.context.read<ChatRoomCubit>().refreshNow();
                  _showSnackBarMessage('Laporan toko berhasil dikirim.');
                } catch (e) {
                  _showSnackBarMessage('Gagal kirim laporan toko. $e');
                } finally {
                  if (sheetContext.mounted) {
                    setModalState(() => isSubmitting = false);
                  }
                }
              }

              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      c.gold.withValues(alpha: 0.16),
                                      c.surfaceRaised,
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: c.gold.withValues(alpha: 0.18),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${payload['title'] ?? 'Laporan toko'}',
                                      style: PromotorText.outfit(
                                        size: 14,
                                        weight: FontWeight.w900,
                                        color: c.cream,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Isi laporan dibagi per section agar lebih rapi.',
                                      style: PromotorText.outfit(
                                        size: 10,
                                        weight: FontWeight.w700,
                                        color: c.cream2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Container(
                              decoration: BoxDecoration(
                                color: c.s1,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: c.s3),
                              ),
                              child: IconButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: Icon(
                                  Icons.close_rounded,
                                  color: c.cream2,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        ...promotorDrafts.asMap().entries.map((entry) {
                          final index = entry.key;
                          final draft = entry.value;
                          return Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: c.s1,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: c.s3),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: c.gold.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Text(
                                    '${draft['promotor_name'] ?? 'Promotor'}',
                                    style: PromotorText.outfit(
                                      size: 10,
                                      weight: FontWeight.w900,
                                      color: c.gold,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: c.surfaceRaised,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: c.gold.withValues(alpha: 0.14),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '1. Sellout',
                                        style: PromotorText.outfit(
                                          size: 11,
                                          weight: FontWeight.w900,
                                          color: c.gold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Pilih tipe vivo yang terjual.',
                                        style: PromotorText.outfit(
                                          size: 10,
                                          weight: FontWeight.w700,
                                          color: c.muted2,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      OutlinedButton.icon(
                                        onPressed: () => chooseVariant(index),
                                        style: OutlinedButton.styleFrom(
                                          minimumSize: const Size.fromHeight(
                                            46,
                                          ),
                                          side: BorderSide(color: c.goldDim),
                                        ),
                                        icon: const Icon(Icons.devices_rounded),
                                        label: Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            '${draft['variant_label'] ?? ''}'
                                                    .trim()
                                                    .isEmpty
                                                ? 'Pilih tipe terjual'
                                                : '${draft['variant_label']}',
                                          ),
                                        ),
                                      ),
                                      if (_toInt(draft['srp']) > 0) ...[
                                        const SizedBox(height: 10),
                                        Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: c.s1,
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                            border: Border.all(color: c.s3),
                                          ),
                                          child: Text(
                                            'SRP ${_formatFullCurrency(draft['srp'])}',
                                            style: PromotorText.outfit(
                                              size: 10,
                                              weight: FontWeight.w800,
                                              color: c.cream,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                Container(
                                  width: double.infinity,
                                  margin: const EdgeInsets.only(top: 12),
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: c.surfaceRaised,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: c.blue.withValues(alpha: 0.14),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '2. VAST Finance',
                                        style: PromotorText.outfit(
                                          size: 11,
                                          weight: FontWeight.w900,
                                          color: c.blue,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.blue.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              'Target ${_toInt(draft['vast_target'])}',
                                              style: PromotorText.outfit(
                                                size: 10,
                                                weight: FontWeight.w800,
                                                color: c.blue,
                                              ),
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: c.green.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(999),
                                            ),
                                            child: Text(
                                              'Isi pencapaian hari ini',
                                              style: PromotorText.outfit(
                                                size: 10,
                                                weight: FontWeight.w800,
                                                color: c.green,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      TextField(
                                        controller:
                                            draft['vast_controller']
                                                as TextEditingController,
                                        keyboardType: TextInputType.number,
                                        decoration: const InputDecoration(
                                          labelText: 'Pencapaian VAST',
                                          hintText:
                                              'Masukkan jumlah pencapaian',
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            color: c.s1,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: c.s3),
                          ),
                          child: Theme(
                            data: Theme.of(
                              context,
                            ).copyWith(dividerColor: Colors.transparent),
                            child: ExpansionTile(
                              initiallyExpanded: brandSectionExpanded,
                              onExpansionChanged: (value) {
                                setModalState(() {
                                  brandSectionExpanded = value;
                                });
                              },
                              tilePadding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 2,
                              ),
                              childrenPadding: const EdgeInsets.fromLTRB(
                                14,
                                0,
                                14,
                                14,
                              ),
                              title: Text(
                                '3. Brand Lain',
                                style: PromotorText.outfit(
                                  size: 11,
                                  weight: FontWeight.w900,
                                  color: c.gold,
                                ),
                              ),
                              subtitle: Text(
                                brandSectionExpanded
                                    ? 'Tutup jika sudah selesai.'
                                    : 'Tap untuk buka input brand lain.',
                                style: PromotorText.outfit(
                                  size: 10,
                                  weight: FontWeight.w700,
                                  color: c.muted2,
                                ),
                              ),
                              children: [
                                ...brandControllers.entries.map(
                                  (entry) => Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: TextField(
                                      controller: entry.value,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: '${entry.key} (unit)',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: c.s1,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: c.s3),
                          ),
                          child: TextField(
                            controller: storeNoteController,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Catatan toko',
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: isSubmitting ? null : submit,
                            child: Text(isSubmitting ? 'Mengirim...' : 'Kirim'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      );

      await Future<void>.delayed(kThemeAnimationDuration);
      for (final draft in promotorDrafts) {
        (draft['vast_controller'] as TextEditingController).dispose();
      }
      for (final controller in brandControllers.values) {
        controller.dispose();
      }
      storeNoteController.dispose();
    } catch (e) {
      _showSnackBarMessage('Gagal membuka form laporan toko. $e');
    }
  }

  Map<String, dynamic> _safeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return const <String, dynamic>{};
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  bool _isSelloutReportField(String label) {
    final normalized = label.trim().toLowerCase();
    return normalized.contains('sellout') || normalized.contains('target');
  }

  bool _isFocusReportField(String label) {
    return label.trim().toLowerCase().contains('fokus');
  }

  bool _isVastReportField(String label) {
    return label.trim().toLowerCase().contains('vast');
  }

  int _extractFirstNumber(String? raw) {
    final digits = (raw ?? '').replaceAll(RegExp(r'[^0-9]'), ' ').trim();
    if (digits.isEmpty) return 0;
    return int.tryParse(digits.split(RegExp(r'\s+')).first) ?? 0;
  }

  String _formatFullCurrency(dynamic value) {
    final amount = value is num ? value.toInt() : _toInt(value);
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(amount);
  }

  void _showSnackBarMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildAnnouncementCard(ChatMessage message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gold.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.gold.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'ANNOUNCEMENT',
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w900,
                    color: c.gold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            message.content ?? '',
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: c.cream,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetCard(ChatMessage message) {
    Map<String, dynamic> payload = const <String, dynamic>{};
    try {
      payload = Map<String, dynamic>.from(
        jsonDecode((message.content ?? '').replaceFirst('target_card::', '')),
      );
    } catch (_) {}
    final rows = (payload['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final dateLabel = '${payload['date'] ?? '-'}';
    final satorName =
        '${payload['sator_name'] ?? message.senderName ?? 'SATOR'}';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.gold.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Target Harian',
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w900,
              color: c.gold,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$dateLabel • $satorName',
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: c.muted2,
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(
              'Belum ada data target.',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w700,
                color: c.muted,
              ),
            )
          else
            ...rows.map((row) {
              final displayName = '${row['nickname'] ?? ''}'.trim().isNotEmpty
                  ? '${row['nickname']}'
                  : '${row['name'] ?? 'Promotor'}';
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: PromotorText.outfit(
                              size: 11,
                              weight: FontWeight.w800,
                              color: c.cream,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _compactCurrency(row['target_nominal']),
                          style: PromotorText.outfit(
                            size: 10,
                            weight: FontWeight.w900,
                            color: c.gold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _buildTargetCardChip(
                          'Vast ${num.tryParse('${row['target_vast'] ?? 0}')?.toInt() ?? 0}',
                          c.blue,
                        ),
                        _buildTargetCardChip(
                          'Tipe Fokus ${num.tryParse('${row['target_focus_units'] ?? 0}')?.toInt() ?? 0}',
                          c.green,
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildTargetCardChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 9,
          weight: FontWeight.w800,
          color: color,
        ),
      ),
    );
  }

  Widget _buildImeiNormalizationCard(ChatMessage message) {
    Map<String, dynamic> payload = const <String, dynamic>{};
    try {
      payload = Map<String, dynamic>.from(
        jsonDecode(
          (message.content ?? '').replaceFirst('imei_normalization_card::', ''),
        ),
      );
    } catch (_) {}
    final promotorName =
        '${payload['promotor_name'] ?? message.senderName ?? 'Promotor'}';
    final productName = '${payload['product_name'] ?? 'Produk'}';
    final storeName = '${payload['store_name'] ?? widget.room.name}';
    final imei = '${payload['imei'] ?? '-'}';
    final note =
        '${payload['message'] ?? 'IMEI sudah berhasil dinormalkan. Promotor bisa scan di APK utama.'}';
    final proofImageUrl = '${payload['proof_image_url'] ?? ''}'.trim();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.s1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.blue.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: c.blue.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'IMEI SIAP SCAN',
                  style: PromotorText.outfit(
                    size: 9,
                    weight: FontWeight.w900,
                    color: c.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            promotorName,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w900,
              color: c.cream,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$productName • $storeName',
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: c.muted2,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: c.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: c.s3),
            ),
            child: Text(
              imei,
              style: _withEmojiFallback(
                PromotorText.outfit(
                  size: 12,
                  weight: FontWeight.w900,
                  color: c.gold,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: c.cream2,
            ),
          ),
          if (proofImageUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: GestureDetector(
                onTap: () => _openImageViewer(proofImageUrl),
                child: Image.network(
                  proofImageUrl,
                  width: double.infinity,
                  height: 130,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      _imagePlaceholder(),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _reactionChip(ChatMessage message, _Reaction reaction) {
    return GestureDetector(
      onTap: () => _toggleReaction(message, reaction.emoji, reaction.isMine),
      onLongPress: () => _showReactionUsers(reaction),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          color: reaction.isMine ? c.s1 : c.bg.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: reaction.isMine
                ? c.gold.withValues(alpha: 0.38)
                : c.s3.withValues(alpha: 0.9),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(reaction.emoji, style: const TextStyle(fontSize: 11)),
            if (reaction.count > 1) ...[
              const SizedBox(width: 2),
              Text(
                '${reaction.count}',
                style: PromotorText.outfit(
                  size: 8,
                  weight: FontWeight.w700,
                  color: reaction.isMine ? c.gold : c.muted2,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildInputArea(ChatRoomLoaded state) {
    final canSend = _canSendMessages(state);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 20),
      decoration: BoxDecoration(
        color: c.surfaceRaised,
        border: Border(top: BorderSide(color: c.s3)),
        boxShadow: [
          BoxShadow(
            color: c.shadow.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_replyTarget != null)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.s3),
              ),
              child: Row(
                children: [
                  Container(width: 3, height: 28, color: c.gold),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _replyTarget!.senderName ?? 'Pesan',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PromotorText.outfit(
                            size: 10,
                            weight: FontWeight.w800,
                            color: c.gold,
                          ),
                        ),
                        Text(
                          _replyTarget!.content?.isNotEmpty == true
                              ? _replyPreviewText(_replyTarget!.content)
                              : (_replyTarget!.imageUrl != null
                                    ? 'Gambar'
                                    : 'Pesan'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PromotorText.outfit(
                            size: 11,
                            weight: FontWeight.w600,
                            color: c.muted2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () => setState(() => _replyTarget = null),
                    child: Icon(Icons.close_rounded, size: 18, color: c.muted),
                  ),
                ],
              ),
            ),
          if (_showMentionPanel)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.s3),
              ),
              child: _buildMentionPanel(state),
            ),
          if (_showEmojiPanel)
            Container(
              height: 188,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
              decoration: BoxDecoration(
                color: c.s1,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.s3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Emoji',
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w800,
                      color: c.gold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: GridView.builder(
                      itemCount: _quickEmojis.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 6,
                            mainAxisSpacing: 6,
                            crossAxisSpacing: 6,
                            childAspectRatio: 1.1,
                          ),
                      itemBuilder: (context, index) {
                        final emoji = _quickEmojis[index];
                        return InkWell(
                          onTap: () => _insertEmoji(emoji),
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: c.surfaceRaised,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: c.s3),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 23),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _inputActionIcon(
                _showEmojiPanel
                    ? Icons.keyboard_rounded
                    : Icons.emoji_emotions_outlined,
                onTap: !canSend || _isUploadingImage || _isSendingMessage
                    ? null
                    : _toggleEmojiPanel,
              ),
              const SizedBox(width: 8),
              _inputActionIcon(
                _isUploadingImage
                    ? Icons.hourglass_top_rounded
                    : Icons.image_outlined,
                onTap: _isUploadingImage ? null : _showImagePicker,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Theme(
                  data: Theme.of(context).copyWith(
                    textSelectionTheme: TextSelectionThemeData(
                      cursorColor: c.gold,
                      selectionColor: c.gold.withValues(alpha: 0.2),
                      selectionHandleColor: c.gold,
                    ),
                  ),
                  child: TextField(
                    controller: _messageController,
                    focusNode: _messageFocusNode,
                    minLines: 1,
                    maxLines: 4,
                    enabled:
                        canSend && !_isUploadingImage && !_isSendingMessage,
                    cursorColor: c.gold,
                    decoration: InputDecoration(
                      hintText: _replyTarget != null
                          ? 'Balas pesan...'
                          : 'Tulis pesan...',
                      hintStyle: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w500,
                        color: c.muted,
                      ),
                      filled: true,
                      fillColor: c.s1,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.s3),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.s3),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: c.gold.withValues(alpha: 0.55),
                        ),
                      ),
                      disabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: c.s3),
                      ),
                    ),
                    style:
                        PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w500,
                          color: c.cream2,
                        ).copyWith(
                          fontFamilyFallback: const <String>[
                            'Noto Color Emoji',
                            'Apple Color Emoji',
                            'Segoe UI Emoji',
                            'Segoe UI Symbol',
                            'sans-serif',
                          ],
                        ),
                    onSubmitted: (text) {
                      if (!canSend || _isUploadingImage || _isSendingMessage) {
                        return;
                      }
                      _sendTextMessage(context, text);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: canSend && !_isUploadingImage && !_isSendingMessage
                    ? () => _sendTextMessage(context, _messageController.text)
                    : null,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [c.gold, Color.lerp(c.gold, c.goldInk, 0.65)!],
                    ),
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: [
                      BoxShadow(
                        color: c.goldGlow,
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: _isUploadingImage || _isSendingMessage
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: Center(
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  c.onAccent,
                                ),
                              ),
                            ),
                          ),
                        )
                      : Icon(Icons.send, size: 16, color: c.onAccent),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _inputActionIcon(IconData icon, {VoidCallback? onTap}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: c.s1,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: c.s3),
          ),
          child: Icon(icon, size: 18, color: c.muted),
        ),
      ),
    );
  }

  void _toggleEmojiPanel() {
    setState(() {
      _showEmojiPanel = !_showEmojiPanel;
      if (_showEmojiPanel) {
        _showMentionPanel = false;
        _messageFocusNode.unfocus();
      } else {
        _messageFocusNode.requestFocus();
      }
    });
  }

  void _insertEmoji(String emoji) {
    final value = _messageController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, emoji);
    final nextOffset = start + emoji.length;
    _messageController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }

  List<_Reaction> _reactionList(Map<String, dynamic>? reactions) {
    if (reactions == null || reactions.isEmpty) return [];
    final list = <_Reaction>[];
    reactions.forEach((key, value) {
      final payload = value is Map<String, dynamic>
          ? Map<String, dynamic>.from(value)
          : value is Map
          ? Map<String, dynamic>.from(value)
          : null;
      if (payload == null) return;
      final count = payload['count'] is int
          ? payload['count'] as int
          : int.tryParse('${payload['count']}') ?? 0;
      final users =
          (payload['users'] as List?)
              ?.whereType<Map>()
              .map((row) => Map<String, dynamic>.from(row))
              .toList() ??
          const <Map<String, dynamic>>[];
      final isMine = users.any((row) => row['user_id'] == _currentUserId);
      if (count > 0) {
        list.add(_Reaction(key, count, users: users, isMine: isMine));
      }
    });
    return list;
  }

  bool _canSendMessages(ChatRoomLoaded state) {
    if (state.room.roomType == 'announcement') {
      return _canPostAnnouncement();
    }
    return true;
  }

  Future<void> _sendTextMessage(BuildContext context, String text) async {
    if (_isSendingMessage) return;
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final normalized = _normalizeMentionText(trimmed);
    final draftKey =
        '${widget.room.id}|${_replyTarget?.id ?? ''}|${normalized.toLowerCase()}';
    final now = DateTime.now();
    final lastSentAt = _lastSentDraftAt;
    if (_lastSentDraftKey == draftKey &&
        lastSentAt != null &&
        now.difference(lastSentAt).inMilliseconds < 1800) {
      return;
    }
    final mentions = _extractMentionIds(normalized);
    final replyTargetId = _replyTarget?.id;
    setState(() => _isSendingMessage = true);
    try {
      await context.read<ChatRoomCubit>().sendTextMessage(
        content: normalized,
        mentions: mentions.isEmpty ? null : mentions,
        replyToId: replyTargetId,
      );
      _lastSentDraftKey = draftKey;
      _lastSentDraftAt = now;
      _messageController.clear();
      _pendingMentionIds.clear();
      if (!mounted) return;
      setState(() => _replyTarget = null);
      _scrollToBottom();
    } finally {
      if (mounted) {
        setState(() => _isSendingMessage = false);
      } else {
        _isSendingMessage = false;
      }
    }
  }

  String _normalizeMentionText(String text) {
    return text.replaceAllMapped(
      RegExp(r'@\{([^}]+)\}'),
      (match) => '@${match.group(1)}',
    );
  }

  List<String> _extractMentionIds(String text) {
    final ids = <String>{};
    final normalized = _normalizeMentionText(text).toLowerCase();
    for (final entry in _pendingMentionIds.entries) {
      if (normalized.contains(entry.key) && entry.value != _currentUserId) {
        ids.add(entry.value);
      }
    }
    final state = context.read<ChatRoomCubit>().state;
    final candidates = state is ChatRoomLoaded
        ? _mentionCandidates(state)
        : _roomMembers;
    if (state is ChatRoomLoaded &&
        normalized.contains('@all') &&
        _canMentionAll(state)) {
      for (final member in candidates) {
        if (member.id.isNotEmpty && member.id != _currentUserId) {
          ids.add(member.id);
        }
      }
      return ids.toList();
    }
    for (final member in candidates) {
      final name = member.displayName.trim().toLowerCase();
      final mentionToken = '@$name';
      if (normalized.contains(mentionToken)) {
        ids.add(member.id);
      }
    }
    return ids.toList();
  }

  List<ChatRoomMember> _mentionCandidates(ChatRoomLoaded state) {
    final seen = <String>{};
    final merged = <ChatRoomMember>[];

    for (final member in _roomMembers) {
      if (member.id.isEmpty) continue;
      if (seen.add(member.id)) {
        merged.add(member);
      }
    }

    for (final message in state.messages) {
      final id = message.senderId;
      final name = message.senderName?.trim();
      if (id == null || id.isEmpty || name == null || name.isEmpty) continue;
      if (seen.add(id)) {
        merged.add(
          ChatRoomMember(id: id, displayName: name, role: message.senderRole),
        );
      }
    }
    merged.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return merged;
  }

  (int, int, String)? _activeMentionContext() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    final cursor = selection.isValid ? selection.baseOffset : text.length;
    if (cursor < 0 || cursor > text.length) return null;

    var start = cursor - 1;
    while (start >= 0) {
      final char = text[start];
      if (char == '@') {
        final isStartBoundary =
            start == 0 || RegExp(r'\s').hasMatch(text[start - 1]);
        if (!isStartBoundary) return null;
        final query = text.substring(start + 1, cursor);
        if (query.contains(RegExp(r'\s'))) return null;
        return (start, cursor, query);
      }
      if (RegExp(r'\s').hasMatch(char)) break;
      start -= 1;
    }
    return null;
  }

  void _replaceActiveMention(String replacement) {
    final contextData = _activeMentionContext();
    final text = _messageController.text;
    if (contextData == null) {
      final prefix = text.isEmpty || text.endsWith(' ') ? '' : ' ';
      final nextText = '$text$prefix$replacement ';
      _messageController.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
      return;
    }
    final start = contextData.$1;
    final end = contextData.$2;
    final nextText =
        '${text.substring(0, start)}$replacement ${text.substring(end)}';
    final nextCursor = (start + replacement.length + 1).clamp(
      0,
      nextText.length,
    );
    _messageController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextCursor),
    );
  }

  Widget _buildMentionPanel(ChatRoomLoaded state) {
    final query = _mentionSearchQuery.trim().toLowerCase();
    final candidates = _mentionCandidates(state).where((member) {
      if (query.isEmpty) return true;
      return member.displayName.toLowerCase().contains(query);
    }).toList();
    final canMentionAll = _canMentionAll(state);
    final showMentionAll =
        canMentionAll &&
        (query.isEmpty || '@all'.contains('@$query') || 'all'.contains(query));
    if (_isLoadingRoomMembers && candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Center(child: CircularProgressIndicator(color: c.gold)),
      );
    }
    if (candidates.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Text(
          _roomMembersError ?? 'Mention tidak ditemukan',
          style: PromotorText.outfit(
            size: 11,
            weight: FontWeight.w600,
            color: c.muted,
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Mention',
              style: PromotorText.outfit(
                size: 11,
                weight: FontWeight.w800,
                color: c.gold,
              ),
            ),
            const Spacer(),
            InkWell(
              onTap: () => setState(() => _showMentionPanel = false),
              child: Icon(Icons.close_rounded, size: 16, color: c.muted),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            if (showMentionAll)
              InkWell(
                onTap: () {
                  _replaceActiveMention('@all');
                },
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: c.gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.gold.withValues(alpha: 0.28)),
                  ),
                  child: Text(
                    '@all',
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w800,
                      color: c.gold,
                    ),
                  ),
                ),
              ),
            ...candidates.map((member) {
              return InkWell(
                onTap: () {
                  _pendingMentionIds['@${member.displayName.toLowerCase()}'] =
                      member.id;
                  _replaceActiveMention('@${member.displayName}');
                },
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: c.surfaceRaised,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: c.s3),
                  ),
                  child: Text(
                    member.displayName,
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w700,
                      color: c.cream,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ],
    );
  }

  void _showMessageActions(ChatMessage message) {
    final emojis = ['👍', '❤️', '😂', '🔥', '👏', '🎉'];
    final isImeiCard = _isImeiNormalizationCardMessage(message);
    final copiedText = isImeiCard
        ? _imeiFromNormalizationCard(message)
        : (message.content ?? '').trim();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surfaceRaised,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Wrap(
                spacing: 10,
                children: emojis
                    .map(
                      (emoji) => InkWell(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          final current = _reactionList(message.reactions);
                          final mine = current
                              .where((r) => r.emoji == emoji)
                              .any((r) => r.isMine);
                          _toggleReaction(message, emoji, mine);
                        },
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 26),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            ListTile(
              leading: Icon(Icons.reply_rounded, color: c.cream2),
              title: Text(
                'Balas pesan',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: c.cream,
                ),
              ),
              onTap: () {
                Navigator.pop(sheetContext);
                setState(() => _replyTarget = message);
              },
            ),
            if (copiedText.isNotEmpty)
              ListTile(
                leading: Icon(Icons.copy_rounded, color: c.cream2),
                title: Text(
                  isImeiCard ? 'Salin IMEI' : 'Salin pesan',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: c.cream,
                  ),
                ),
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: copiedText));
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        isImeiCard ? 'IMEI disalin' : 'Pesan disalin',
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  String _imeiFromNormalizationCard(ChatMessage message) {
    try {
      final payload = Map<String, dynamic>.from(
        jsonDecode(
          (message.content ?? '').replaceFirst('imei_normalization_card::', ''),
        ),
      );
      return '${payload['imei'] ?? ''}'.trim();
    } catch (_) {
      return '';
    }
  }

  Future<void> _toggleReaction(
    ChatMessage message,
    String emoji,
    bool isMine,
  ) async {
    final cubit = context.read<ChatRoomCubit>();
    try {
      final reactions = isMine
          ? await cubit.removeReaction(messageId: message.id, emoji: emoji)
          : await cubit.addReaction(messageId: message.id, emoji: emoji);
      cubit.replaceMessageReactions(
        messageId: message.id,
        reactions: reactions,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reaction gagal disimpan: $e')));
    }
  }

  void _showReactionUsers(_Reaction reaction) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surfaceRaised,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                '${reaction.emoji} ${reaction.count} reaksi',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w800,
                  color: c.cream,
                ),
              ),
            ),
            ...reaction.users.map(
              (user) => ListTile(
                dense: true,
                title: Text(
                  (user['name'] as String?) ?? 'User',
                  style: PromotorText.outfit(
                    size: 12,
                    weight: FontWeight.w700,
                    color: c.cream2,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showImagePicker() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: c.surfaceRaised,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.camera_alt_rounded, color: c.cream2),
              title: Text(
                'Ambil Foto',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: c.cream,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Future<void>.delayed(
                  const Duration(milliseconds: 180),
                  () => _pickAndSendImage(ImageSource.camera),
                );
              },
            ),
            ListTile(
              leading: Icon(Icons.photo_library_rounded, color: c.cream2),
              title: Text(
                'Pilih dari Galeri',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: c.cream,
                ),
              ),
              onTap: () {
                Navigator.pop(context);
                Future<void>.delayed(
                  const Duration(milliseconds: 180),
                  () => _pickAndSendImage(ImageSource.gallery),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _ensureMediaPermission(ImageSource source) async {
    final status = source == ImageSource.camera
        ? await Permission.camera.request()
        : await (() async {
            final photos = await Permission.photos.request();
            if (photos.isGranted || photos.isLimited) return photos;
            return Permission.storage.request();
          })();

    if (status.isGranted || status.isLimited) {
      return true;
    }
    if (!mounted) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          source == ImageSource.camera
              ? 'Izin kamera diperlukan untuk ambil foto'
              : 'Izin galeri diperlukan untuk pilih gambar',
        ),
        action: status.isPermanentlyDenied
            ? SnackBarAction(label: 'Buka', onPressed: openAppSettings)
            : null,
      ),
    );
    return false;
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final hasPermission = await _ensureMediaPermission(source);
      if (!hasPermission || !mounted) return;
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 60,
      );
      if (image == null || !mounted) {
        if (mounted && source == ImageSource.gallery) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak ada gambar yang dipilih')),
          );
        }
        return;
      }
      final shouldSend = await _showImagePreview(image);
      if (shouldSend != true || !mounted) return;
      setState(() => _isUploadingImage = true);
      final result = await _uploadToCloudinary(image);
      if (result == null || !mounted) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Upload gambar gagal')));
        }
        return;
      }
      await context.read<ChatRoomCubit>().sendImageMessage(
        imageUrl: result['url'] as String,
        imageWidth: result['width'] as int?,
        imageHeight: result['height'] as int?,
        caption: _messageController.text.trim().isEmpty
            ? null
            : _messageController.text.trim(),
        mentions: _extractMentionIds(_messageController.text),
        replyToId: _replyTarget?.id,
      );
      _messageController.clear();
      setState(() => _replyTarget = null);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal pilih gambar: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUploadingImage = false);
    }
  }

  Future<bool?> _showImagePreview(XFile image) {
    return showDialog<bool>(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: c.surfaceRaised,
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.file(
                  File(image.path),
                  height: 320,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Kirim'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Map<String, Object?>?> _uploadToCloudinary(XFile image) async {
    final result = await CloudinaryUploadHelper.uploadXFile(
      image,
      folder: 'vtrack/chat',
      fileName: 'chat_${DateTime.now().millisecondsSinceEpoch}.jpg',
      maxWidth: 1280,
      quality: 80,
    );
    if (result == null) return null;
    return <String, Object?>{
      'url': result.url,
      'width': result.width,
      'height': result.height,
    };
  }

  void _openImageViewer(String imageUrl) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.network(imageUrl, fit: BoxFit.contain),
                  ),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dateLabel(DateTime date) {
    final today = DateTime.now();
    final todayDate = DateTime(today.year, today.month, today.day);
    if (date == todayDate) return 'Hari ini';
    return DateFormat('EEEE, d MMM yyyy', 'id_ID').format(date);
  }
}

class _Reaction {
  final String emoji;
  final int count;
  final List<Map<String, dynamic>> users;
  final bool isMine;

  _Reaction(
    this.emoji,
    this.count, {
    this.users = const [],
    this.isMine = false,
  });
}

final class _RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '',
        selection: TextSelection.collapsed(offset: 0),
      );
    }
    final amount = int.tryParse(digits) ?? 0;
    final formatted = NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp ',
      decimalDigits: 0,
    ).format(amount);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
