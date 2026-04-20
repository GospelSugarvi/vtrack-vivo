class ChatRoomMember {
  final String id;
  final String displayName;
  final String? role;
  final String? avatarUrl;
  final String? whatsappPhone;

  const ChatRoomMember({
    required this.id,
    required this.displayName,
    this.role,
    this.avatarUrl,
    this.whatsappPhone,
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
      avatarUrl: (json['avatar_url'] as String?)?.trim(),
      whatsappPhone: (json['whatsapp_phone'] as String?)?.trim(),
    );
  }
}
