class ChatRoom {
  final String id;
  final String roomType;
  final String name;
  final String? description;
  final String? tokoId;
  final String? satorId;
  final String? user1Id;
  final String? user2Id;
  final bool isMuted;
  final DateTime? lastReadAt;
  final int unreadCount;
  final int mentionUnreadCount;
  final int mentionAllUnreadCount;
  final String? chatTab;
  final String? lastMessageContent;
  final DateTime? lastMessageTime;
  final String? lastMessageSenderName;
  final int memberCount;
  final DateTime createdAt;

  const ChatRoom({
    required this.id,
    required this.roomType,
    required this.name,
    this.description,
    this.tokoId,
    this.satorId,
    this.user1Id,
    this.user2Id,
    required this.isMuted,
    this.lastReadAt,
    required this.unreadCount,
    this.mentionUnreadCount = 0,
    this.mentionAllUnreadCount = 0,
    this.chatTab,
    this.lastMessageContent,
    this.lastMessageTime,
    this.lastMessageSenderName,
    required this.memberCount,
    required this.createdAt,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    return ChatRoom(
      id: (json['room_id'] as String?) ?? (json['id'] as String?) ?? '',
      roomType: (json['room_type'] as String?) ?? 'general',
      name:
          (json['room_name'] as String?) ??
          (json['name'] as String?) ??
          'Unknown Room',
      description:
          (json['room_description'] as String?) ??
          (json['description'] as String?),
      tokoId: json['store_id'] as String?,
      satorId: json['sator_id'] as String?,
      user1Id: json['user1_id'] as String?,
      user2Id: json['user2_id'] as String?,
      isMuted: (json['is_muted'] as bool?) ?? false,
      lastReadAt: json['last_read_at'] != null
          ? DateTime.parse(json['last_read_at'] as String)
          : null,
      unreadCount: (json['unread_count'] as int?) ?? 0,
      mentionUnreadCount: (json['mention_unread_count'] as int?) ?? 0,
      mentionAllUnreadCount: (json['mention_all_unread_count'] as int?) ?? 0,
      chatTab: json['chat_tab'] as String?,
      lastMessageContent: json['last_message_content'] as String?,
      lastMessageTime: json['last_message_time'] != null
          ? DateTime.parse(json['last_message_time'] as String)
          : null,
      lastMessageSenderName: json['last_message_sender_name'] as String?,
      memberCount: (json['member_count'] as int?) ?? 0,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  ChatRoom copyWith({
    String? id,
    String? roomType,
    String? name,
    String? description,
    String? tokoId,
    String? satorId,
    String? user1Id,
    String? user2Id,
    bool? isMuted,
    DateTime? lastReadAt,
    int? unreadCount,
    int? mentionUnreadCount,
    int? mentionAllUnreadCount,
    String? chatTab,
    String? lastMessageContent,
    DateTime? lastMessageTime,
    String? lastMessageSenderName,
    int? memberCount,
    DateTime? createdAt,
  }) {
    return ChatRoom(
      id: id ?? this.id,
      roomType: roomType ?? this.roomType,
      name: name ?? this.name,
      description: description ?? this.description,
      tokoId: tokoId ?? this.tokoId,
      satorId: satorId ?? this.satorId,
      user1Id: user1Id ?? this.user1Id,
      user2Id: user2Id ?? this.user2Id,
      isMuted: isMuted ?? this.isMuted,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      unreadCount: unreadCount ?? this.unreadCount,
      mentionUnreadCount: mentionUnreadCount ?? this.mentionUnreadCount,
      mentionAllUnreadCount:
          mentionAllUnreadCount ?? this.mentionAllUnreadCount,
      chatTab: chatTab ?? this.chatTab,
      lastMessageContent: lastMessageContent ?? this.lastMessageContent,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageSenderName:
          lastMessageSenderName ?? this.lastMessageSenderName,
      memberCount: memberCount ?? this.memberCount,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
