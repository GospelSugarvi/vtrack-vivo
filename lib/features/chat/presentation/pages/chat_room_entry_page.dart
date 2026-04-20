import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/chat_room.dart';
import 'chat_room_page.dart';

class ChatRoomEntryPage extends StatelessWidget {
  const ChatRoomEntryPage({super.key, required this.roomId});

  final String roomId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: Supabase.instance.client
          .from('chat_rooms')
          .select(
            'id, room_type, name, description, store_id, sator_id, user1_id, user2_id, created_at',
          )
          .eq('id', roomId)
          .eq('is_active', true)
          .maybeSingle(),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final row = snapshot.data;
        if (row == null) {
          return const Scaffold(
            body: Center(child: Text('Room chat tidak ditemukan')),
          );
        }

        return ChatRoomPage(room: ChatRoom.fromJson(row));
      },
    );
  }
}
