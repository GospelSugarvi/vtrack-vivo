class ChatMessage {
  final String id;
  final String? senderId;
  final String? senderName;
  final String? senderRole;
  final String messageType;
  final String? content;
  final String? imageUrl;
  final int? imageWidth;
  final int? imageHeight;
  final List<String>? mentions;
  final String? replyToId;
  final String? replyToContent;
  final String? replyToSenderName;
  final bool isEdited;
  final DateTime? editedAt;
  final DateTime createdAt;
  final int readByCount;
  final Map<String, dynamic>? reactions;
  final bool isOwnMessage;

  const ChatMessage({
    required this.id,
    this.senderId,
    this.senderName,
    this.senderRole,
    required this.messageType,
    this.content,
    this.imageUrl,
    this.imageWidth,
    this.imageHeight,
    this.mentions,
    this.replyToId,
    this.replyToContent,
    this.replyToSenderName,
    required this.isEdited,
    this.editedAt,
    required this.createdAt,
    required this.readByCount,
    this.reactions,
    required this.isOwnMessage,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawReactions = json['reactions'];
    final reactions = rawReactions is Map<String, dynamic>
        ? Map<String, dynamic>.from(rawReactions)
        : rawReactions is Map
        ? Map<String, dynamic>.from(rawReactions)
        : null;
    return ChatMessage(
      id: (json['message_id'] as String?) ?? '',
      senderId: json['sender_id'] as String?,
      senderName: json['sender_name'] as String?,
      senderRole: json['sender_role'] as String?,
      messageType: (json['message_type'] as String?) ?? 'text',
      content: json['content'] as String?,
      imageUrl: json['image_url'] as String?,
      imageWidth: json['image_width'] as int?,
      imageHeight: json['image_height'] as int?,
      mentions: json['mentions'] != null 
          ? List<String>.from(json['mentions'] as List)
          : null,
      replyToId: json['reply_to_id'] as String?,
      replyToContent: json['reply_to_content'] as String?,
      replyToSenderName: json['reply_to_sender_name'] as String?,
      isEdited: (json['is_edited'] as bool?) ?? false,
      editedAt: json['edited_at'] != null
          ? DateTime.parse(json['edited_at'] as String)
          : null,
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
      readByCount: (json['read_by_count'] as int?) ?? 0,
      reactions: reactions,
      isOwnMessage: (json['is_own_message'] as bool?) ?? false,
    );
  }

  ChatMessage copyWith({
    String? id,
    String? senderId,
    String? senderName,
    String? senderRole,
    String? messageType,
    String? content,
    String? imageUrl,
    int? imageWidth,
    int? imageHeight,
    List<String>? mentions,
    String? replyToId,
    String? replyToContent,
    String? replyToSenderName,
    bool? isEdited,
    DateTime? editedAt,
    DateTime? createdAt,
    int? readByCount,
    Map<String, dynamic>? reactions,
    bool? isOwnMessage,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      senderRole: senderRole ?? this.senderRole,
      messageType: messageType ?? this.messageType,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      imageWidth: imageWidth ?? this.imageWidth,
      imageHeight: imageHeight ?? this.imageHeight,
      mentions: mentions ?? this.mentions,
      replyToId: replyToId ?? this.replyToId,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      isEdited: isEdited ?? this.isEdited,
      editedAt: editedAt ?? this.editedAt,
      createdAt: createdAt ?? this.createdAt,
      readByCount: readByCount ?? this.readByCount,
      reactions: reactions ?? this.reactions,
      isOwnMessage: isOwnMessage ?? this.isOwnMessage,
    );
  }
}
