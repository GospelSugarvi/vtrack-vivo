import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/utils/chat_unread_refresh_bus.dart';
import '../models/chat_message.dart';
import '../models/chat_room.dart';
import '../models/store_daily_data.dart';
import '../repository/chat_repository.dart';

// States
abstract class ChatRoomState {}

class ChatRoomInitial extends ChatRoomState {}

class ChatRoomLoading extends ChatRoomState {}

class ChatRoomLoaded extends ChatRoomState {
  final ChatRoom room;
  final List<ChatMessage> messages;
  final StoreDailyData? storeData;
  final bool isLoadingMore;
  final bool hasMoreMessages;
  final List<String> typingUsers;

  ChatRoomLoaded({
    required this.room,
    required this.messages,
    this.storeData,
    this.isLoadingMore = false,
    this.hasMoreMessages = true,
    this.typingUsers = const [],
  });

  ChatRoomLoaded copyWith({
    ChatRoom? room,
    List<ChatMessage>? messages,
    StoreDailyData? storeData,
    bool? isLoadingMore,
    bool? hasMoreMessages,
    List<String>? typingUsers,
  }) {
    return ChatRoomLoaded(
      room: room ?? this.room,
      messages: messages ?? this.messages,
      storeData: storeData ?? this.storeData,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      hasMoreMessages: hasMoreMessages ?? this.hasMoreMessages,
      typingUsers: typingUsers ?? this.typingUsers,
    );
  }
}

class ChatRoomError extends ChatRoomState {
  final String message;
  ChatRoomError(this.message);
}

// Cubit
class ChatRoomCubit extends Cubit<ChatRoomState> {
  final ChatRepository _repository;
  final ChatRoom _room;

  RealtimeChannel? _messageSubscription;
  RealtimeChannel? _readReceiptSubscription;
  RealtimeChannel? _reactionSubscription;
  Timer? _refreshDebounce;
  Timer? _roomSyncTimer;
  bool _isRefreshing = false;

  static const int _messagesPerPage = 50;
  int _currentOffset = 0;

  ChatRoomCubit(this._repository, this._room) : super(ChatRoomInitial());

  Future<void> loadChatRoom() async {
    emit(ChatRoomLoading());

    try {
      debugPrint('Loading chat room: ${_room.id}');

      // Load initial messages
      final messages = await _repository.getChatMessages(
        roomId: _room.id,
        limit: _messagesPerPage,
        offset: 0,
      );

      debugPrint('Loaded ${messages.length} messages');
      _currentOffset = messages.length;

      // Load store data if it's a toko room
      StoreDailyData? storeData;
      if (_room.roomType == 'toko' && _room.tokoId != null) {
        debugPrint('Loading store data for toko: ${_room.tokoId}');
        try {
          storeData = await _repository.getStoreDailyData(
            tokoId: _room.tokoId!,
          );
          debugPrint('Store data loaded: ${storeData != null}');
        } catch (e) {
          debugPrint('Failed to load store data: $e');
          // Continue without store data
        }
      }

      emit(
        ChatRoomLoaded(
          room: _room,
          messages: messages.reversed
              .toList(), // Reverse to show newest at bottom
          storeData: storeData,
          hasMoreMessages: messages.length == _messagesPerPage,
        ),
      );

      // Mark messages as read
      try {
        await _repository.markMessagesRead(roomId: _room.id);
        await _repository.markRoomMentionNotificationsRead(roomId: _room.id);
        notifyChatUnreadRefresh();
      } catch (e) {
        debugPrint('Failed to mark messages as read: $e');
        // Continue without marking as read
      }

      // Subscribe to real-time updates
      try {
        _subscribeToUpdates();
        _roomSyncTimer?.cancel();
        _roomSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) {
          if (!isClosed) {
            _refreshMessages();
          }
        });
      } catch (e) {
        debugPrint('Failed to subscribe to updates: $e');
        // Continue without real-time updates
      }
    } catch (e) {
      debugPrint('Error loading chat room: $e');
      emit(ChatRoomError('Failed to load chat room: $e'));
    }
  }

  Future<void> loadMoreMessages() async {
    final currentState = state;
    if (currentState is! ChatRoomLoaded ||
        currentState.isLoadingMore ||
        !currentState.hasMoreMessages) {
      return;
    }

    emit(currentState.copyWith(isLoadingMore: true));

    try {
      final moreMessages = await _repository.getChatMessages(
        roomId: _room.id,
        limit: _messagesPerPage,
        offset: _currentOffset,
      );

      _currentOffset += moreMessages.length;

      final allMessages = [...moreMessages.reversed, ...currentState.messages];

      emit(
        currentState.copyWith(
          messages: allMessages,
          isLoadingMore: false,
          hasMoreMessages: moreMessages.length == _messagesPerPage,
        ),
      );
    } catch (e) {
      emit(currentState.copyWith(isLoadingMore: false));
      // Could emit error or show snackbar
    }
  }

  Future<void> sendTextMessage({
    required String content,
    List<String>? mentions,
    String? replyToId,
  }) async {
    try {
      await _repository.sendTextMessage(
        roomId: _room.id,
        content: content,
        mentions: mentions,
        replyToId: replyToId,
      );
      // Message will be added via real-time subscription
    } catch (e) {
      // Handle error - could emit error state or show snackbar
      rethrow;
    }
  }

  Future<void> sendImageMessage({
    required String imageUrl,
    int? imageWidth,
    int? imageHeight,
    String? caption,
    List<String>? mentions,
    String? replyToId,
  }) async {
    try {
      await _repository.sendImageMessage(
        roomId: _room.id,
        imageUrl: imageUrl,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        caption: caption,
        mentions: mentions,
        replyToId: replyToId,
      );
      // Message will be added via real-time subscription
    } catch (e) {
      // Handle error
      rethrow;
    }
  }

  Future<void> refreshNow() async {
    await _refreshMessages();
  }

  Future<Map<String, dynamic>> addReaction({
    required String messageId,
    required String emoji,
  }) async {
    try {
      return await _repository.addReaction(messageId: messageId, emoji: emoji);
    } catch (e) {
      rethrow;
    }
  }

  Future<Map<String, dynamic>> removeReaction({
    required String messageId,
    required String emoji,
  }) async {
    try {
      return await _repository.removeReaction(
        messageId: messageId,
        emoji: emoji,
      );
    } catch (e) {
      rethrow;
    }
  }

  Future<void> refreshMessagesNow() async {
    await _refreshMessages();
  }

  Future<void> deleteMyMessagesInRoom() async {
    await _repository.deleteMyMessagesInRoom(roomId: _room.id);
    await _refreshMessages();
  }

  void replaceMessageReactions({
    required String messageId,
    required Map<String, dynamic> reactions,
  }) {
    final currentState = state;
    if (currentState is! ChatRoomLoaded) return;

    final updatedMessages = currentState.messages.map((message) {
      if (message.id != messageId) return message;
      return message.copyWith(reactions: reactions);
    }).toList();

    emit(currentState.copyWith(messages: updatedMessages));
  }

  Future<void> toggleMute() async {
    final currentState = state;
    if (currentState is! ChatRoomLoaded) return;

    try {
      final newMuteState = !currentState.room.isMuted;
      await _repository.updateRoomSettings(
        roomId: _room.id,
        isMuted: newMuteState,
      );

      emit(
        currentState.copyWith(
          room: currentState.room.copyWith(isMuted: newMuteState),
        ),
      );
    } catch (e) {
      // Handle error
      rethrow;
    }
  }

  void _subscribeToUpdates() {
    try {
      // Subscribe to new messages
      _messageSubscription = _repository.subscribeToMessages(
        roomId: _room.id,
        onMessageReceived: (message) {
          if (isClosed) return;

          try {
            final currentState = state;
            if (currentState is ChatRoomLoaded) {
              // Use Future.microtask to defer state update
              Future.microtask(() {
                if (!isClosed && state is ChatRoomLoaded) {
                  final loadedState = state as ChatRoomLoaded;
                  final updatedMessages = [...loadedState.messages, message];
                  emit(loadedState.copyWith(messages: updatedMessages));

                  // Mark as read if message is not from current user
                  if (!message.isOwnMessage) {
                    _repository
                        .markMessagesRead(roomId: _room.id)
                        .then((_) async {
                          await _repository.markRoomMentionNotificationsRead(
                            roomId: _room.id,
                          );
                          notifyChatUnreadRefresh();
                        })
                        .onError((error, stackTrace) {
                          debugPrint('Failed to mark message as read: $error');
                        });
                  }
                }
              });
            }
          } catch (e) {
            debugPrint('Error handling new message: $e');
          }
        },
      );

      // Subscribe to reactions
      _reactionSubscription = _repository.subscribeToReactions(
        roomId: _room.id,
        onReactionUpdate: (messageId) {
          if (!isClosed && _hasLoadedMessage(messageId)) {
            _scheduleRefresh(const Duration(milliseconds: 180));
          }
        },
      );

      // Subscribe to read receipts
      _readReceiptSubscription = _repository.subscribeToReadReceipts(
        roomId: _room.id,
        onReadReceiptUpdate: (messageId) {
          if (!isClosed && _hasLoadedMessage(messageId)) {
            _scheduleRefresh(const Duration(milliseconds: 420));
          }
        },
      );
    } catch (e) {
      debugPrint('Error subscribing to updates: $e');
    }
  }

  Future<void> _refreshMessages() async {
    final currentState = state;
    if (currentState is! ChatRoomLoaded || _isRefreshing) return;

    try {
      _isRefreshing = true;
      final messages = await _repository.getChatMessages(
        roomId: _room.id,
        limit: currentState.messages.length,
        offset: 0,
      );

      emit(currentState.copyWith(messages: messages.reversed.toList()));
    } catch (e) {
      // Handle error silently for background refresh
    } finally {
      _isRefreshing = false;
    }
  }

  void _scheduleRefresh(Duration delay) {
    _refreshDebounce?.cancel();
    _refreshDebounce = Timer(delay, _refreshMessages);
  }

  bool _hasLoadedMessage(String messageId) {
    final currentState = state;
    if (currentState is! ChatRoomLoaded) return false;
    return currentState.messages.any((message) => message.id == messageId);
  }

  @override
  Future<void> close() {
    _refreshDebounce?.cancel();
    _roomSyncTimer?.cancel();
    _messageSubscription?.unsubscribe();
    _readReceiptSubscription?.unsubscribe();
    _reactionSubscription?.unsubscribe();
    return super.close();
  }
}
