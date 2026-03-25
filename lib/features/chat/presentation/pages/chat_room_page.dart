import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../cubit/chat_room_cubit.dart';
import '../../models/chat_room.dart';
import '../../models/chat_message.dart';
import '../../models/chat_room_member.dart';
import '../../repository/chat_repository.dart';
import '../widgets/store_performance_panel.dart';
import '../theme/chat_theme.dart';
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
  static const String _cloudinaryCloudName = 'dkkbwu8hj';
  static const String _cloudinaryUploadPreset = 'vtrack_uploads';

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final ChatRepository _repository = ChatRepository();

  ChatMessage? _replyTarget;
  List<ChatRoomMember> _roomMembers = const [];
  bool _showMentionPanel = false;
  bool _isUploadingImage = false;
  bool _isLoadingRoomMembers = false;
  bool _showJumpToLatest = false;
  bool _showSearchBar = false;
  String? _roomMembersError;
  int _lastMessageCount = 0;

  ChatUiPalette get c => chatPaletteOf(context);
  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadRoomMembers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _messageController.dispose();
    _searchController.dispose();
    super.dispose();
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
                    if (state.room.roomType == 'toko' &&
                        state.room.tokoId != null)
                      StorePerformancePanel(
                        storeId: state.room.tokoId!,
                        storeName: state.room.name,
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
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: Color.lerp(c.s2, c.goldDim, 0.24)!,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: c.s3),
                  ),
                  child: Center(
                    child: Text(
                      _initials(room.name),
                      style: PromotorText.display(size: 13, color: c.cream),
                    ),
                  ),
                ),
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: c.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: c.bg, width: 2),
                    ),
                  ),
                ),
              ],
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
                        Text(
                          room.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: c.cream,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: c.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${room.memberCount} anggota · online',
                              style: PromotorText.outfit(
                                size: 11,
                                weight: FontWeight.w700,
                                color: c.muted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
            ),
            Row(
              children: [
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
                const SizedBox(width: 6),
                _headerIcon(Icons.more_horiz),
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
    final timeLabel = DateFormat('HH:mm').format(message.createdAt);
    final reactions = _reactionList(message.reactions);

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
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
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: c.s2,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.s3),
                ),
                child: Center(
                  child: Text(
                    showAvatar ? _initials(senderName) : '',
                    style: PromotorText.display(size: 11, color: c.cream),
                  ),
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
                    onLongPress: () => _showMessageActions(message),
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
                            message.readByCount > 0
                                ? Icons.done_all
                                : Icons.done,
                            size: 15,
                            color: message.readByCount > 0
                                ? c.goldInk
                                : c.muted,
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

  Widget _bubble(ChatMessage message, bool isOut) {
    final hasImage = message.messageType == 'image' || message.imageUrl != null;
    final hasReply = message.replyToContent != null;
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
                    message.replyToContent ?? '',
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

          if (hasImage)
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
          if (message.content != null && message.content!.isNotEmpty)
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
    final mentionStyle = PromotorText.outfit(
      size: 13,
      weight: FontWeight.w800,
      color: isOut ? c.bg : c.gold,
    );
    final baseStyle = PromotorText.outfit(
      size: 13,
      weight: FontWeight.w500,
      color: isOut ? c.cream : c.cream2,
    );
    final spans = <TextSpan>[];
    final mentionTokens = _roomMembers
        .map((member) => '@${member.displayName}')
        .where((token) => token.trim().length > 1)
        .toSet()
        .toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    var cursor = 0;
    while (cursor < normalizedText.length) {
      String? matchedToken;
      for (final token in mentionTokens) {
        final end = cursor + token.length;
        if (end > normalizedText.length) continue;
        final slice = normalizedText.substring(cursor, end);
        if (slice.toLowerCase() == token.toLowerCase()) {
          matchedToken = normalizedText.substring(cursor, end);
          break;
        }
      }

      if (matchedToken != null) {
        spans.add(TextSpan(text: matchedToken, style: mentionStyle));
        cursor += matchedToken.length;
        continue;
      }

      spans.add(
        TextSpan(text: normalizedText.substring(cursor, cursor + 1), style: baseStyle),
      );
      cursor += 1;
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

  Widget _reactionChip(ChatMessage message, _Reaction reaction) {
    return GestureDetector(
      onTap: () => _toggleReaction(message, reaction.emoji, reaction.isMine),
      onLongPress: () => _showReactionUsers(reaction),
      child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: reaction.isMine
            ? c.gold.withValues(alpha: 0.18)
            : c.surfaceRaised,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: reaction.isMine ? c.gold : c.s3),
      ),
      child: Row(
        children: [
          Text(reaction.emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 3),
          Text(
            '${reaction.count}',
            style: PromotorText.outfit(
              size: 8,
              weight: FontWeight.w700,
              color: reaction.isMine ? c.gold : c.muted,
            ),
          ),
        ],
      ),
    ));
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
                              ? _replyTarget!.content!
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  _inputActionButton(
                    label: '@',
                    onTap: () => _toggleMentionPanel(state),
                  ),
                  const SizedBox(width: 5),
                  _inputActionIcon(
                    _isUploadingImage
                        ? Icons.hourglass_top_rounded
                        : Icons.image_outlined,
                    onTap: _isUploadingImage ? null : _showImagePicker,
                  ),
                ],
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
                    minLines: 1,
                    maxLines: 4,
                    enabled: canSend && !_isUploadingImage,
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
                    style: PromotorText.outfit(
                      size: 13,
                      weight: FontWeight.w500,
                      color: c.cream2,
                    ),
                    onSubmitted: (text) {
                      if (!canSend || _isUploadingImage) return;
                      _sendTextMessage(context, text);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: canSend && !_isUploadingImage
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
                  child: _isUploadingImage
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

  Widget _inputActionButton({
    required String label,
    required VoidCallback? onTap,
  }) {
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
        child: Center(
          child: Text(
            label,
            style: PromotorText.outfit(
              size: 16,
              weight: FontWeight.w900,
              color: c.gold,
            ),
          ),
        ),
      ),
    ));
  }

  List<_Reaction> _reactionList(Map<String, dynamic>? reactions) {
    if (reactions == null || reactions.isEmpty) return [];
    final list = <_Reaction>[];
    reactions.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        final count = value['count'] is int
            ? value['count'] as int
            : int.tryParse('${value['count']}') ?? 0;
        final users = (value['users'] as List?)
                ?.whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList() ??
            const <Map<String, dynamic>>[];
        final isMine = users.any((row) => row['user_id'] == _currentUserId);
        if (count > 0) {
          list.add(_Reaction(key, count, users: users, isMine: isMine));
        }
      }
    });
    return list;
  }

  bool _canSendMessages(ChatRoomLoaded state) {
    if (state.room.roomType == 'announcement') {
      return false;
    }
    return true;
  }

  void _sendTextMessage(BuildContext context, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final normalized = _normalizeMentionText(trimmed);
    final mentions = _extractMentionIds(normalized);
    context.read<ChatRoomCubit>().sendTextMessage(
      content: normalized,
      mentions: mentions.isEmpty ? null : mentions,
      replyToId: _replyTarget?.id,
    );
    _messageController.clear();
    setState(() => _replyTarget = null);
    _scrollToBottom();
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
    final state = context.read<ChatRoomCubit>().state;
    final candidates = state is ChatRoomLoaded
        ? _mentionCandidates(state)
        : _roomMembers;
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
          ChatRoomMember(
            id: id,
            displayName: name,
            role: message.senderRole,
          ),
        );
      }
    }
    merged.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return merged;
  }

  void _toggleMentionPanel(ChatRoomLoaded state) {
    setState(() => _showMentionPanel = !_showMentionPanel);
    if (_roomMembers.isEmpty && !_isLoadingRoomMembers) {
      _loadRoomMembers();
    }
  }

  Widget _buildMentionPanel(ChatRoomLoaded state) {
    final candidates = _mentionCandidates(state);
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
          _roomMembersError ?? 'Anggota chat belum termuat',
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
              'Pilih Orang',
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
          children: candidates.map((member) {
            return InkWell(
              onTap: () {
                final text = _messageController.text;
                final prefix = text.isEmpty || text.endsWith(' ') ? '' : ' ';
                _messageController.text = '$text$prefix@${member.displayName} ';
                _messageController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _messageController.text.length),
                );
                setState(() => _showMentionPanel = false);
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
          }).toList(),
        ),
      ],
    );
  }

  void _showMessageActions(ChatMessage message) {
    final emojis = ['👍', '❤️', '😂', '🔥', '👏', '🎉'];
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
                        child: Text(emoji, style: const TextStyle(fontSize: 26)),
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
            if ((message.content ?? '').trim().isNotEmpty)
              ListTile(
                leading: Icon(Icons.copy_rounded, color: c.cream2),
                title: Text(
                  'Salin pesan',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w700,
                    color: c.cream,
                  ),
                ),
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(text: message.content!.trim()),
                  );
                  if (!sheetContext.mounted) return;
                  Navigator.pop(sheetContext);
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pesan disalin')),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleReaction(
    ChatMessage message,
    String emoji,
    bool isMine,
  ) async {
    final cubit = context.read<ChatRoomCubit>();
    if (isMine) {
      await cubit.removeReaction(messageId: message.id, emoji: emoji);
    } else {
      await cubit.addReaction(messageId: message.id, emoji: emoji);
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
                _pickAndSendImage(ImageSource.camera);
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
                _pickAndSendImage(ImageSource.gallery);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 70,
      );
      if (image == null || !mounted) return;
      final shouldSend = await _showImagePreview(image);
      if (shouldSend != true || !mounted) return;
      setState(() => _isUploadingImage = true);
      final result = await _uploadToCloudinary(image);
      if (result == null || !mounted) return;
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
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse(
          'https://api.cloudinary.com/v1_1/$_cloudinaryCloudName/image/upload',
        ),
      );
      request.fields['upload_preset'] = _cloudinaryUploadPreset;
      request.files.add(await http.MultipartFile.fromPath('file', image.path));
      final response = await request.send();
      if (response.statusCode != 200) return null;
      final responseData = await response.stream.bytesToString();
      final jsonData = json.decode(responseData) as Map<String, dynamic>;
      return <String, Object?>{
        'url': jsonData['secure_url'] as String?,
        'width': jsonData['width'] as int?,
        'height': jsonData['height'] as int?,
      };
    } catch (_) {
      return null;
    }
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

  String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts[0].substring(0, 1).toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
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
