class ChatRoomMember {
  final String id;
  final String displayName;
  final String? role;

  const ChatRoomMember({
    required this.id,
    required this.displayName,
    this.role,
  });

  factory ChatRoomMember.fromJson(Map<String, dynamic> json) {
    final nickname = (json['nickname'] as String?)?.trim();
    final fullName = (json['full_name'] as String?)?.trim();
    return ChatRoomMember(
      id: (json['id'] as String?) ?? '',
      displayName: nickname != null && nickname.isNotEmpty
          ? nickname
          : (fullName != null && fullName.isNotEmpty ? fullName : 'User'),
      role: json['role'] as String?,
    );
  }
}
