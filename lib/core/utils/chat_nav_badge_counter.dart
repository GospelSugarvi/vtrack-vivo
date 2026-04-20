import 'package:supabase_flutter/supabase_flutter.dart';

Future<int> loadChatNavBadgeCount(SupabaseClient client) async {
  final userId = client.auth.currentUser?.id;
  if (userId == null) return 0;

  try {
    final result = await client.rpc(
      'get_user_chat_rooms',
      params: <String, dynamic>{'p_user_id': userId},
    );
    final rows = (result as List?) ?? const <dynamic>[];

    var total = 0;
    for (final row in rows) {
      final map = row is Map<String, dynamic>
          ? row
          : row is Map
          ? Map<String, dynamic>.from(row)
          : const <String, dynamic>{};
      final unread = (map['unread_count'] as num?)?.toInt() ?? 0;
      final mentionPersonal =
          (map['mention_unread_count'] as num?)?.toInt() ?? 0;
      final mentionAll =
          (map['mention_all_unread_count'] as num?)?.toInt() ?? 0;
      final mentionTotal = mentionPersonal + mentionAll;
      total += unread > mentionTotal ? unread : mentionTotal;
    }
    return total;
  } catch (_) {
    final fallback = await client.rpc('get_my_chat_unread_count');
    final payload = Map<String, dynamic>.from(
      (fallback as Map?) ?? const <String, dynamic>{},
    );
    return (payload['unread_count'] as num?)?.toInt() ?? 0;
  }
}
