import 'package:flutter_bloc/flutter_bloc.dart';

import '../models/chat_room.dart';
import '../repository/chat_repository.dart';

abstract class ChatListState {}

class ChatListInitial extends ChatListState {}

class ChatListLoading extends ChatListState {}

class ChatListLoaded extends ChatListState {
  final List<ChatRoom> rooms;
  final Map<String, List<ChatRoom>> groupedRooms;

  ChatListLoaded({
    required this.rooms,
    required this.groupedRooms,
  });

  ChatListLoaded copyWith({
    List<ChatRoom>? rooms,
    Map<String, List<ChatRoom>>? groupedRooms,
  }) {
    return ChatListLoaded(
      rooms: rooms ?? this.rooms,
      groupedRooms: groupedRooms ?? this.groupedRooms,
    );
  }
}

class ChatListError extends ChatListState {
  final String message;

  ChatListError(this.message);
}

class ChatListCubit extends Cubit<ChatListState> {
  final ChatRepository _repository;

  ChatListCubit(this._repository) : super(ChatListInitial());

  Future<void> loadChatRooms() async {
    emit(ChatListLoading());
    try {
      final rooms = await _repository.getUserChatRooms();
      emit(ChatListLoaded(
        rooms: rooms,
        groupedRooms: _groupRoomsByType(rooms),
      ));
    } catch (e) {
      emit(ChatListError('Failed to load chat rooms: $e'));
    }
  }

  Future<void> refreshChatRooms() async {
    try {
      final rooms = await _repository.getUserChatRooms();
      emit(ChatListLoaded(
        rooms: rooms,
        groupedRooms: _groupRoomsByType(rooms),
      ));
    } catch (e) {
      emit(ChatListError('Failed to refresh chat rooms: $e'));
    }
  }

  Map<String, List<ChatRoom>> _groupRoomsByType(List<ChatRoom> rooms) {
    final grouped = <String, List<ChatRoom>>{};
    for (final room in rooms) {
      final key = _getRoomGroupKey(room.roomType);
      grouped.putIfAbsent(key, () => <ChatRoom>[]).add(room);
    }

    grouped.forEach((key, roomList) {
      roomList.sort((a, b) {
        if (a.unreadCount > 0 && b.unreadCount == 0) return -1;
        if (a.unreadCount == 0 && b.unreadCount > 0) return 1;
        if (a.lastMessageTime != null && b.lastMessageTime != null) {
          return b.lastMessageTime!.compareTo(a.lastMessageTime!);
        }
        if (a.lastMessageTime != null) return -1;
        if (b.lastMessageTime != null) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });
    });

    return grouped;
  }

  String _getRoomGroupKey(String roomType) {
    switch (roomType) {
      case 'announcement':
        return 'Announcements';
      case 'toko':
        return 'Store Chats';
      case 'tim':
        return 'Team Chats';
      case 'global':
        return 'Global';
      case 'private':
        return 'Private Messages';
      default:
        return 'Other';
    }
  }

  int getTotalUnreadCount() {
    final currentState = state;
    if (currentState is ChatListLoaded) {
      return currentState.rooms.fold<int>(
        0,
        (sum, room) => sum + room.unreadCount,
      );
    }
    return 0;
  }

  void markRoomAsRead(String roomId) {
    final currentState = state;
    if (currentState is! ChatListLoaded) return;

    final updatedRooms = currentState.rooms.map((room) {
      if (room.id == roomId) {
        return room.copyWith(unreadCount: 0);
      }
      return room;
    }).toList();

    emit(
      currentState.copyWith(
        rooms: updatedRooms,
        groupedRooms: _groupRoomsByType(updatedRooms),
      ),
    );
  }

  void markAllAsRead() {
    final currentState = state;
    if (currentState is! ChatListLoaded) return;

    final updatedRooms = currentState.rooms
        .map((room) => room.copyWith(unreadCount: 0))
        .toList();

    emit(
      currentState.copyWith(
        rooms: updatedRooms,
        groupedRooms: _groupRoomsByType(updatedRooms),
      ),
    );
  }
}
