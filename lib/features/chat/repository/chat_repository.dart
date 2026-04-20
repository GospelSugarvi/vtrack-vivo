import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_room.dart';
import '../models/chat_message.dart';
import '../models/chat_room_member.dart';
import '../models/store_daily_data.dart';
import 'dart:convert';

class ChatRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

  bool _isReplyConstraintError(Object error) {
    if (error is! PostgrestException) return false;
    final message = '${error.message} ${error.details ?? ''} ${error.hint ?? ''}'
        .toLowerCase();
    return message.contains('chat_messages_reply_to_id_fkey') ||
        message.contains('reply_to_id') ||
        message.contains('foreign key constraint');
  }

  // Get all chat rooms for current user
  Future<List<ChatRoom>> getUserChatRooms() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final response = await _supabase.rpc(
      'get_user_chat_rooms',
      params: {'p_user_id': userId},
    );

    return (response as List)
        .map((json) => ChatRoom.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  Future<ChatRoom?> getStoreChatRoom({required String storeId}) async {
    dynamic row;
    try {
      final resolved = await _supabase.rpc(
        'get_store_chat_room_resolved',
        params: {'p_store_id': storeId},
      );
      if (resolved is List && resolved.isNotEmpty) {
        row = resolved.first;
      } else if (resolved is Map) {
        row = resolved;
      }
    } catch (_) {}

    row ??= await _supabase
        .from('chat_rooms')
        .select(
          'id, room_type, name, description, store_id, sator_id, user1_id, user2_id, created_at',
        )
        .eq('room_type', 'toko')
        .eq('store_id', storeId)
        .eq('is_active', true)
        .maybeSingle();

    if (row == null) return null;
    return ChatRoom.fromJson(Map<String, dynamic>.from(row));
  }

  Future<ChatRoom?> getTeamChatRoom({required String satorId}) async {
    final row = await _supabase
        .from('chat_rooms')
        .select(
          'id, room_type, name, description, store_id, sator_id, user1_id, user2_id, created_at',
        )
        .eq('room_type', 'tim')
        .eq('sator_id', satorId)
        .eq('is_active', true)
        .maybeSingle();

    if (row == null) return null;
    return ChatRoom.fromJson(Map<String, dynamic>.from(row));
  }

  // Get messages for a specific chat room
  Future<List<ChatMessage>> getChatMessages({
    required String roomId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final response = await _supabase.rpc(
        'get_chat_messages',
        params: {
          'p_room_id': roomId,
          'p_user_id': userId,
          'p_limit': limit,
          'p_offset': offset,
        },
      );

      if (response == null) return [];

      return (response as List).map((json) {
        try {
          return ChatMessage.fromJson(json as Map<String, dynamic>);
        } catch (e) {
          debugPrint('Error parsing message: $e');
          debugPrint('Message data: $json');
          rethrow;
        }
      }).toList();
    } catch (e) {
      debugPrint('Error getting chat messages: $e');
      rethrow;
    }
  }

  // Send a text message
  Future<String> sendTextMessage({
    required String roomId,
    required String content,
    List<String>? mentions,
    String? replyToId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    try {
      final response = await _supabase.rpc(
        'send_message',
        params: {
          'p_room_id': roomId,
          'p_sender_id': userId,
          'p_message_type': 'text',
          'p_content': content,
          'p_mentions': mentions,
          'p_reply_to_id': replyToId,
        },
      );

      return response as String;
    } catch (error) {
      if (replyToId == null || !_isReplyConstraintError(error)) rethrow;
      final retry = await _supabase.rpc(
        'send_message',
        params: {
          'p_room_id': roomId,
          'p_sender_id': userId,
          'p_message_type': 'text',
          'p_content': content,
          'p_mentions': mentions,
          'p_reply_to_id': null,
        },
      );
      return retry as String;
    }
  }

  // Send an image message
  Future<String> sendImageMessage({
    required String roomId,
    required String imageUrl,
    int? imageWidth,
    int? imageHeight,
    String? caption,
    List<String>? mentions,
    String? replyToId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');
    final safeCaption = (caption == null || caption.trim().isEmpty)
        ? ''
        : caption.trim();

    try {
      final response = await _supabase.rpc(
        'send_message',
        params: {
          'p_room_id': roomId,
          'p_sender_id': userId,
          'p_message_type': 'image',
          'p_content': safeCaption,
          'p_image_url': imageUrl,
          'p_image_width': imageWidth,
          'p_image_height': imageHeight,
          'p_mentions': mentions,
          'p_reply_to_id': replyToId,
        },
      );

      return response as String;
    } catch (error) {
      if (replyToId == null || !_isReplyConstraintError(error)) rethrow;
      final retry = await _supabase.rpc(
        'send_message',
        params: {
          'p_room_id': roomId,
          'p_sender_id': userId,
          'p_message_type': 'image',
          'p_content': safeCaption,
          'p_image_url': imageUrl,
          'p_image_width': imageWidth,
          'p_image_height': imageHeight,
          'p_mentions': mentions,
          'p_reply_to_id': null,
        },
      );
      return retry as String;
    }
  }

  // Mark messages as read
  Future<int> markMessagesRead({
    required String roomId,
    String? upToMessageId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final response = await _supabase.rpc(
      'mark_messages_read',
      params: {
        'p_room_id': roomId,
        'p_user_id': userId,
        'p_up_to_message_id': upToMessageId,
      },
    );

    return response as int;
  }

  Future<void> markRoomMentionNotificationsRead({
    required String roomId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    await _supabase
        .from('app_notifications')
        .update({
          'status': 'read',
          'read_at': DateTime.now().toIso8601String(),
        })
        .eq('recipient_user_id', userId)
        .inFilter('type', ['chat_mention', 'chat_mention_all'])
        .filter('payload->>room_id', 'eq', roomId)
        .eq('status', 'unread');
  }

  // Get store daily data for toko chat rooms
  Future<StoreDailyData?> getStoreDailyData({
    required String tokoId,
    DateTime? date,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_store_daily_data',
        params: {
          'p_store_id': tokoId,
          'p_date': (date ?? DateTime.now()).toIso8601String().split('T')[0],
        },
      );

      if (response == null || response.isEmpty) return null;

      return StoreDailyData.fromJson(response.first as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error getting store daily data: $e');
      // Return null instead of throwing to prevent chat room from failing
      return null;
    }
  }

  // Subscribe to real-time chat messages
  RealtimeChannel subscribeToMessages({
    required String roomId,
    required Function(ChatMessage) onMessageReceived,
  }) {
    return _supabase
        .channel('chat_messages_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'chat_messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'room_id',
            value: roomId,
          ),
          callback: (payload) {
            try {
              final messageData = payload.newRecord;
              if (messageData.isNotEmpty) {
                final messageId = messageData['id'] as String?;
                if (messageId != null) {
                  // Schedule the fetch for next frame to avoid build-time state changes
                  Future.delayed(Duration.zero, () {
                    _fetchCompleteMessage(messageId, roomId)
                        .then((message) {
                          // Double check before calling callback
                          Future.microtask(() => onMessageReceived(message));
                        })
                        .catchError((e) {
                          debugPrint('Error fetching complete message: $e');
                        });
                  });
                }
              }
            } catch (e) {
              debugPrint('Error in message subscription callback: $e');
            }
          },
        )
        .subscribe();
  }

  // Subscribe to read receipt updates
  RealtimeChannel subscribeToReadReceipts({
    required String roomId,
    required Function(String messageId) onReadReceiptUpdate,
  }) {
    return _supabase
        .channel('message_reads_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reads',
          callback: (payload) {
            final messageId = payload.newRecord['message_id'] as String?;
            if (messageId != null && messageId.isNotEmpty) {
              onReadReceiptUpdate(messageId);
            }
          },
        )
        .subscribe();
  }

  // Subscribe to reaction updates
  RealtimeChannel subscribeToReactions({
    required String roomId,
    required Function(String messageId) onReactionUpdate,
  }) {
    return _supabase
        .channel('message_reactions_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) {
            final record = payload.newRecord.isNotEmpty
                ? payload.newRecord
                : payload.oldRecord;
            final messageId = record['message_id'] as String?;
            if (messageId != null && messageId.isNotEmpty) {
              onReactionUpdate(messageId);
            }
          },
        )
        .subscribe();
  }

  // Private method to fetch complete message data
  Future<ChatMessage> _fetchCompleteMessage(
    String messageId,
    String roomId,
  ) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User not authenticated');

      final messageRow = await _supabase
          .from('chat_messages')
          .select(
            'id, room_id, sender_id, message_type, content, image_url, image_width, image_height, mentions, reply_to_id, is_edited, edited_at, created_at, is_deleted',
          )
          .eq('id', messageId)
          .eq('room_id', roomId)
          .maybeSingle();

      if (messageRow == null || messageRow['is_deleted'] == true) {
        throw Exception('Message not found: $messageId');
      }

      final senderId = messageRow['sender_id'] as String?;
      final replyToId = messageRow['reply_to_id'] as String?;

      final Future<Map<String, dynamic>?> senderFuture = senderId == null
          ? Future<Map<String, dynamic>?>.value(null)
          : _supabase
                .from('users')
                .select('full_name, role')
                .eq('id', senderId)
                .maybeSingle();
      final Future<Map<String, dynamic>?> replyFuture = replyToId == null
          ? Future<Map<String, dynamic>?>.value(null)
          : _fetchReplyPreview(replyToId);
      final Future<List<Map<String, dynamic>>> readsFuture = _supabase
          .from('message_reads')
          .select('id')
          .eq('message_id', messageId)
          .then((value) => List<Map<String, dynamic>>.from(value));
      final Future<List<Map<String, dynamic>>> reactionsFuture = _supabase
          .from('message_reactions')
          .select(
            'emoji, user_id, users!message_reactions_user_id_fkey(full_name)',
          )
          .eq('message_id', messageId)
          .then((value) => List<Map<String, dynamic>>.from(value));

      final results = await Future.wait<Object?>([
        senderFuture,
        replyFuture,
        readsFuture,
        reactionsFuture,
      ]);

      final sender = results[0] as Map<String, dynamic>?;
      final reply = results[1] as Map<String, dynamic>?;
      final reads = results[2] as List<Map<String, dynamic>>;
      final reactions = results[3] as List<Map<String, dynamic>>;

      return ChatMessage.fromJson({
        'message_id': messageRow['id'],
        'sender_id': senderId,
        'sender_name': sender?['full_name'],
        'sender_role': sender?['role'],
        'message_type': messageRow['message_type'],
        'content': messageRow['content'],
        'image_url': messageRow['image_url'],
        'image_width': messageRow['image_width'],
        'image_height': messageRow['image_height'],
        'mentions': messageRow['mentions'],
        'reply_to_id': replyToId,
        'reply_to_content': reply?['content'],
        'reply_to_sender_name': reply?['sender_name'],
        'is_edited': messageRow['is_edited'],
        'edited_at': messageRow['edited_at'],
        'created_at': messageRow['created_at'],
        'read_by_count': reads.length,
        'reactions': _groupReactions(reactions),
        'is_own_message': senderId == userId,
      });
    } catch (e) {
      debugPrint('Error fetching complete message: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>?> _fetchReplyPreview(String replyToId) async {
    final replyRow = await _supabase
        .from('chat_messages')
        .select('content, sender_id, is_deleted')
        .eq('id', replyToId)
        .maybeSingle();

    if (replyRow == null || replyRow['is_deleted'] == true) {
      return null;
    }

    final replySenderId = replyRow['sender_id'] as String?;
    String? senderName;

    if (replySenderId != null) {
      final replySender = await _supabase
          .from('users')
          .select('full_name')
          .eq('id', replySenderId)
          .maybeSingle();
      senderName = replySender?['full_name'] as String?;
    }

    return {'content': replyRow['content'], 'sender_name': senderName};
  }

  Map<String, dynamic> _groupReactions(List<Map<String, dynamic>> rows) {
    final grouped = <String, Map<String, dynamic>>{};

    for (final row in rows) {
      final emoji = row['emoji']?.toString();
      final userId = row['user_id']?.toString();
      if (emoji == null || emoji.isEmpty || userId == null || userId.isEmpty) {
        continue;
      }

      final bucket = grouped.putIfAbsent(emoji, () {
        return {'count': 0, 'users': <Map<String, dynamic>>[]};
      });

      bucket['count'] = (bucket['count'] as int) + 1;
      (bucket['users'] as List<Map<String, dynamic>>).add({
        'user_id': userId,
        'name': row['users'] is Map
            ? (row['users'] as Map)['full_name']?.toString()
            : null,
      });
    }

    return grouped;
  }

  // Add emoji reaction to message
  Future<Map<String, dynamic>> addReaction({
    required String messageId,
    required String emoji,
  }) async {
    final response = await _supabase.rpc(
      'set_message_reaction',
      params: {
        'p_message_id': messageId,
        'p_emoji': emoji,
        'p_active': true,
      },
    );
    return response is Map<String, dynamic>
        ? Map<String, dynamic>.from(response)
        : response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};
  }

  // Remove emoji reaction from message
  Future<Map<String, dynamic>> removeReaction({
    required String messageId,
    required String emoji,
  }) async {
    final response = await _supabase.rpc(
      'set_message_reaction',
      params: {
        'p_message_id': messageId,
        'p_emoji': emoji,
        'p_active': false,
      },
    );
    return response is Map<String, dynamic>
        ? Map<String, dynamic>.from(response)
        : response is Map
        ? Map<String, dynamic>.from(response)
        : const <String, dynamic>{};
  }

  // Update chat room member settings (mute/unmute)
  Future<void> updateRoomSettings({
    required String roomId,
    bool? isMuted,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final updates = <String, dynamic>{};
    if (isMuted != null) updates['is_muted'] = isMuted;

    if (updates.isNotEmpty) {
      await _supabase
          .from('chat_members')
          .update(updates)
          .eq('room_id', roomId)
          .eq('user_id', userId);
    }
  }

  Future<void> deleteMyMessagesInRoom({
    required String roomId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    await _supabase
        .from('chat_messages')
        .delete()
        .eq('room_id', roomId)
        .eq('sender_id', userId)
        .eq('is_deleted', false);
  }

  // Get store performance data for chat room
  Future<Map<String, dynamic>> getStorePerformanceData({
    required String storeId,
    DateTime? date,
  }) async {
    try {
      final targetDate = (date ?? DateTime.now()).toIso8601String().split(
        'T',
      )[0];

      debugPrint(
        '=== FETCHING STORE PERFORMANCE for store: $storeId, date: $targetDate ===',
      );

      // Get target data
      final targetData = await _getStoreTargetData(storeId, targetDate);

      // Get allbrand data
      final allbrandData = await _getStoreAllbrandData(storeId, targetDate);

      // Get activity data
      final activityData = await _getStoreActivityData(storeId, targetDate);
      final vastData = await _getStoreVastFinanceData(storeId, targetDate);

      return {
        'target': targetData,
        'allbrand': allbrandData,
        'activity': activityData,
        'vast': vastData,
      };
    } catch (e) {
      debugPrint('=== ERROR getting store performance data: $e ===');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _getStoreTargetData(
    String storeId,
    String date,
  ) async {
    try {
      // Get all promotors in this store
      final promotors = await _supabase
          .from('assignments_promotor_store')
          .select('promotor_id')
          .eq('store_id', storeId)
          .eq('active', true);

      if (promotors.isEmpty) {
        return {
          'daily_achievement': 0,
          'daily_target': 0,
          'monthly_achievement': 0,
          'monthly_target': 0,
          'fokus_achievement': 0,
          'fokus_target': 0,
          'sellout_by_promotor': <Map<String, dynamic>>[],
          'promotors': [],
        };
      }

      final promotorIds = promotors.map((p) => p['promotor_id']).toList();
      final promotorNameById = <String, String>{};
      for (final row in promotors) {
        final id = '${row['promotor_id'] ?? ''}';
        final rawUser = row['users'];
        String name = 'Promotor';
        if (rawUser is Map) {
          final user = Map<String, dynamic>.from(rawUser);
          name = user['nickname']?.toString().trim().isNotEmpty == true
              ? user['nickname'].toString().trim()
              : (user['full_name']?.toString() ?? 'Promotor');
        }
        if (id.isNotEmpty) promotorNameById[id] = name;
      }

      // Get sales data for today - use 'sales_sell_out' table
      final sales = await _supabase
          .from('sales_sell_out')
          .select(
            'promotor_id, price_at_transaction, variant_id, product_variants!inner(product_id, ram_rom, color, products!inner(model_name))',
          )
          .inFilter('promotor_id', promotorIds)
          .gte('created_at', '${date}T00:00:00')
          .lt('created_at', '${date}T23:59:59')
          .isFilter('deleted_at', null)
          .eq('is_chip_sale', false);

      int dailyAchievement = 0;
      int fokusAchievement = 0;
      final unitByPromotor = <String, int>{};
      final omzetByPromotor = <String, int>{};
      final fokusByPromotor = <String, int>{};
      final variantsByPromotor = <String, List<String>>{};

      // Get fokus product IDs - just get all active fokus products
      final fokusProducts = await _supabase
          .from('fokus_products')
          .select('product_id');

      final fokusProductIds = fokusProducts
          .map((p) => p['product_id'] as String)
          .toSet();

      for (var sale in sales) {
        final price = (sale['price_at_transaction'] as num).toInt();
        dailyAchievement += price;
        final promotorId = '${sale['promotor_id'] ?? ''}';
        if (promotorId.isNotEmpty) {
          unitByPromotor[promotorId] = (unitByPromotor[promotorId] ?? 0) + 1;
          omzetByPromotor[promotorId] =
              (omzetByPromotor[promotorId] ?? 0) + price;
          final variantRow = sale['product_variants'];
          if (variantRow is Map) {
            final variant = Map<String, dynamic>.from(variantRow);
            final modelName = variant['products'] is Map
                ? Map<String, dynamic>.from(
                    variant['products'],
                  )['model_name']?.toString()
                : null;
            final variantName = [
              variant['ram_rom']?.toString(),
              variant['color']?.toString(),
            ]
                .where((value) => value != null && value.trim().isNotEmpty)
                .map((value) => value!.trim())
                .join(' ');
            final label = (modelName != null && modelName.isNotEmpty)
                ? (variantName.isNotEmpty ? '$modelName $variantName' : modelName)
                : (variantName.isNotEmpty ? variantName : 'Produk');
            variantsByPromotor.putIfAbsent(promotorId, () => <String>[]);
            final list = variantsByPromotor[promotorId]!;
            if (!list.contains(label)) list.add(label);
          }
        }

        // Check if product is fokus
        final productId = sale['product_variants']['product_id'];
        if (fokusProductIds.contains(productId)) {
          fokusAchievement += price;
          if (promotorId.isNotEmpty) {
            fokusByPromotor[promotorId] =
                (fokusByPromotor[promotorId] ?? 0) + 1;
          }
        }
      }

      final targetRows = await Future.wait<Map<String, dynamic>>(
        promotorIds.map((rawId) async {
          final promotorId = '$rawId';
          final raw = await _supabase.rpc(
            'get_daily_target_dashboard',
            params: <String, dynamic>{
              'p_user_id': promotorId,
              'p_date': DateTime.now().toIso8601String().split('T').first,
            },
          );
          if (raw is List && raw.isNotEmpty && raw.first is Map) {
            return Map<String, dynamic>.from(raw.first as Map);
          }
          if (raw is Map) {
            return Map<String, dynamic>.from(raw);
          }
          return const <String, dynamic>{};
        }),
      );
      final monthlyTargetRows = await Future.wait<Map<String, dynamic>>(
        promotorIds.map((rawId) async {
          final promotorId = '$rawId';
          final raw = await _supabase.rpc(
            'get_target_dashboard',
            params: <String, dynamic>{
              'p_user_id': promotorId,
              'p_period_id': null,
            },
          );
          if (raw is List && raw.isNotEmpty && raw.first is Map) {
            return Map<String, dynamic>.from(raw.first as Map);
          }
          if (raw is Map) {
            return Map<String, dynamic>.from(raw);
          }
          return const <String, dynamic>{};
        }),
      );

      final dailyTarget = targetRows.fold<int>(
        0,
        (sum, row) => sum + ((row['target_daily_all_type'] as num?) ?? 0).toInt(),
      );
      final dailyFokusTarget = targetRows.fold<int>(
        0,
        (sum, row) => sum + ((row['target_daily_focus'] as num?) ?? 0).ceil(),
      );
      final monthlyTarget = monthlyTargetRows.fold<int>(
        0,
        (sum, row) => sum + ((row['target_omzet'] as num?) ?? 0).toInt(),
      );
      final selloutByPromotor =
          promotorIds.map((rawId) {
            final promotorId = '$rawId';
            return {
              'promotor_id': promotorId,
              'promotor_name': promotorNameById[promotorId] ?? 'Promotor',
              'units': unitByPromotor[promotorId] ?? 0,
              'omzet': omzetByPromotor[promotorId] ?? 0,
              'focus_units': fokusByPromotor[promotorId] ?? 0,
              'variants': variantsByPromotor[promotorId] ?? const <String>[],
            };
          }).toList()..sort(
            (a, b) => ((b['omzet'] as int).compareTo(a['omzet'] as int)),
          );

      return {
        'daily_achievement': dailyAchievement,
        'daily_target': dailyTarget,
        'monthly_achievement':
            dailyAchievement, // TODO: Calculate actual monthly
        'monthly_target': monthlyTarget,
        'fokus_achievement': fokusAchievement,
        'fokus_target': dailyFokusTarget,
        'promotor_count': promotorIds.length,
        'sellout_by_promotor': selloutByPromotor,
      };
    } catch (e) {
      debugPrint('=== ERROR getting target data: $e ===');
      return {
        'daily_achievement': 0,
        'daily_target': 0,
        'monthly_achievement': 0,
        'monthly_target': 0,
        'fokus_achievement': 0,
        'fokus_target': 0,
        'promotor_count': 0,
        'sellout_by_promotor': <Map<String, dynamic>>[],
      };
    }
  }

  Future<Map<String, dynamic>> _getStoreAllbrandData(
    String storeId,
    String date,
  ) async {
    try {
      final report = await _supabase
          .from('allbrand_reports')
          .select(
            'id,report_date,created_at,updated_at,brand_data,brand_data_daily,leasing_sales,leasing_sales_daily,daily_total_units,cumulative_total_units,vivo_auto_data,vivo_promotor_count,notes',
          )
          .eq('store_id', storeId)
          .lte('report_date', date)
          .order('report_date', ascending: false)
          .order('updated_at', ascending: false)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (report == null) {
        return {
          'has_data': false,
          'total_units': 0,
          'total_store_units': 0,
          'vivo_units': 0,
          'vivo_market_share': 0.0,
          'leasing_total_units': 0,
          'brands': {},
          'leasing_sales': {},
          'history': <Map<String, dynamic>>[],
        };
      }

      final brandsDaily = report['brand_data_daily'] ?? report['brand_data'];
      final brandsCumulative = report['brand_data'];
      final leasingDaily =
          report['leasing_sales_daily'] ?? report['leasing_sales'];
      final competitorUnits = _toInt(report['daily_total_units']) > 0
          ? _toInt(report['daily_total_units'])
          : _sumBrandUnits(brandsDaily);
      final vivoUnits = _extractVivoUnits(report['vivo_auto_data']);
      final totalStoreUnits = competitorUnits + vivoUnits;
      final marketShare = totalStoreUnits > 0
          ? (vivoUnits * 100.0 / totalStoreUnits)
          : 0.0;
      final leasingTotal = _sumLeasingUnits(leasingDaily);
      final promotorTotal =
          _toInt(report['vivo_promotor_count']) +
          _sumCompetitorPromotors(brandsDaily);
      final focusSummary = await _getStoreFocusSummary(storeId, date);
      final brandShare = _buildBrandShareRows(
        brandDataRaw: brandsCumulative,
        vivoUnits: _extractVivoUnits(report['vivo_auto_data']),
      );
      final history = await _getStoreAllbrandHistory(storeId, date);

      return {
        'has_data': true,
        'report_date': report['report_date'],
        'is_today': '${report['report_date']}' == date,
        'total_units': competitorUnits,
        'total_store_units': totalStoreUnits,
        'vivo_units': vivoUnits,
        'vivo_market_share': marketShare,
        'leasing_total_units': leasingTotal,
        'promotor_total': promotorTotal,
        'brands': brandsDaily,
        'brands_cumulative': _safeMap(brandsCumulative),
        'leasing_sales': leasingDaily,
        'vivo_auto': _safeMap(report['vivo_auto_data']),
        'notes': report['notes'],
        'focus_store_daily': focusSummary['store_daily'] ?? 0,
        'focus_store_cumulative': focusSummary['store_cumulative'] ?? 0,
        'focus_by_promotor':
            focusSummary['by_promotor'] ?? <Map<String, dynamic>>[],
        'brand_share': brandShare,
        'history': history,
      };
    } catch (e) {
      debugPrint('=== ERROR getting allbrand data: $e ===');
      return {
        'has_data': false,
        'total_units': 0,
        'total_store_units': 0,
        'vivo_units': 0,
        'vivo_market_share': 0.0,
        'leasing_total_units': 0,
        'brands': {},
        'leasing_sales': {},
        'history': <Map<String, dynamic>>[],
      };
    }
  }

  Future<Map<String, dynamic>> _getStoreFocusSummary(
    String storeId,
    String date,
  ) async {
    try {
      final salesToday = await _supabase
          .from('sales_sell_out')
          .select('promotor_id, variant_id')
          .eq('store_id', storeId)
          .eq('transaction_date', date)
          .isFilter('deleted_at', null)
          .eq('is_chip_sale', false);

      final salesCumulative = await _supabase
          .from('sales_sell_out')
          .select('promotor_id, variant_id')
          .eq('store_id', storeId)
          .lte('transaction_date', date)
          .isFilter('deleted_at', null)
          .eq('is_chip_sale', false);

      final variantRows = await _supabase
          .from('product_variants')
          .select('id, product_id');
      final productRows = await _supabase
          .from('products')
          .select('id, is_focus');
      final promotors = await _supabase
          .from('assignments_promotor_store')
          .select('promotor_id, users!inner(full_name)')
          .eq('store_id', storeId)
          .eq('active', true);

      final focusProductById = {
        for (final p in productRows) '${p['id']}': p['is_focus'] == true,
      };
      final focusVariantIds = <String>{};
      for (final row in variantRows) {
        final variantId = '${row['id']}';
        final productId = '${row['product_id']}';
        if (focusProductById[productId] == true) {
          focusVariantIds.add(variantId);
        }
      }

      final dailyByPromotor = <String, int>{};
      for (final row in salesToday) {
        final variantId = '${row['variant_id'] ?? ''}';
        final promotorId = '${row['promotor_id'] ?? ''}';
        if (!focusVariantIds.contains(variantId) || promotorId.isEmpty) {
          continue;
        }
        dailyByPromotor[promotorId] = (dailyByPromotor[promotorId] ?? 0) + 1;
      }

      final cumulativeByPromotor = <String, int>{};
      for (final row in salesCumulative) {
        final variantId = '${row['variant_id'] ?? ''}';
        final promotorId = '${row['promotor_id'] ?? ''}';
        if (!focusVariantIds.contains(variantId) || promotorId.isEmpty) {
          continue;
        }
        cumulativeByPromotor[promotorId] =
            (cumulativeByPromotor[promotorId] ?? 0) + 1;
      }

      return {
        'store_daily': dailyByPromotor.values.fold<int>(0, (sum, x) => sum + x),
        'store_cumulative': cumulativeByPromotor.values.fold<int>(
          0,
          (sum, x) => sum + x,
        ),
        'by_promotor': List<Map<String, dynamic>>.from(promotors as List).map((
          row,
        ) {
          final promotorId = '${row['promotor_id'] ?? ''}';
          return {
            'name': row['users']?['full_name']?.toString() ?? 'Promotor',
            'today': dailyByPromotor[promotorId] ?? 0,
            'cumulative': cumulativeByPromotor[promotorId] ?? 0,
          };
        }).toList(),
      };
    } catch (e) {
      debugPrint('=== ERROR getting allbrand focus summary: $e ===');
      return {
        'store_daily': 0,
        'store_cumulative': 0,
        'by_promotor': <Map<String, dynamic>>[],
      };
    }
  }

  List<Map<String, dynamic>> _buildBrandShareRows({
    required dynamic brandDataRaw,
    required int vivoUnits,
  }) {
    final brandData = _safeMap(brandDataRaw);
    final rows = <Map<String, dynamic>>[];
    final totalCompetitor = brandData.values.fold<int>(
      0,
      (sum, value) => sum + _sumBrandUnits(value),
    );
    final totalStore = totalCompetitor + vivoUnits;
    if (totalStore <= 0) return rows;

    rows.add({
      'label': 'VIVO',
      'units': vivoUnits,
      'share': (vivoUnits * 100.0) / totalStore,
    });

    for (final entry in brandData.entries) {
      final units = _sumBrandUnits(entry.value);
      rows.add({
        'label': entry.key,
        'units': units,
        'share': (units * 100.0) / totalStore,
      });
    }

    rows.sort((a, b) => (b['share'] as double).compareTo(a['share'] as double));
    return rows;
  }

  Future<List<Map<String, dynamic>>> _getStoreAllbrandHistory(
    String storeId,
    String targetDate,
  ) async {
    final endDate = DateTime.tryParse(targetDate) ?? DateTime.now();
    final startDate = endDate.subtract(const Duration(days: 6));
    final rows = await _supabase
        .from('allbrand_reports')
        .select(
          'report_date,created_at,updated_at,brand_data,brand_data_daily,daily_total_units,vivo_auto_data,leasing_sales,leasing_sales_daily',
        )
        .eq('store_id', storeId)
        .gte('report_date', startDate.toIso8601String().split('T')[0])
        .lte('report_date', targetDate)
        .order('report_date', ascending: false)
        .order('updated_at', ascending: false)
        .order('created_at', ascending: false);

    final rawRows = List<Map<String, dynamic>>.from(rows as List);
    final latestPerDay = <String, Map<String, dynamic>>{};
    for (final row in rawRows) {
      final key = '${row['report_date']}';
      latestPerDay.putIfAbsent(key, () => row);
    }

    final history = <Map<String, dynamic>>[];
    for (final row in latestPerDay.values) {
      final brandsDaily = row['brand_data_daily'] ?? row['brand_data'];
      final leasingDaily = row['leasing_sales_daily'] ?? row['leasing_sales'];
      final competitorUnits = _toInt(row['daily_total_units']) > 0
          ? _toInt(row['daily_total_units'])
          : _sumBrandUnits(brandsDaily);
      final vivoUnits = _extractVivoUnits(row['vivo_auto_data']);
      final totalStoreUnits = competitorUnits + vivoUnits;
      final marketShare = totalStoreUnits > 0
          ? (vivoUnits * 100.0 / totalStoreUnits)
          : 0.0;
      history.add({
        'report_date': row['report_date'],
        'total_units': competitorUnits,
        'vivo_units': vivoUnits,
        'total_store_units': totalStoreUnits,
        'vivo_market_share': marketShare,
        'leasing_units': _sumLeasingUnits(leasingDaily),
      });
    }

    history.sort(
      (a, b) => '${b['report_date']}'.compareTo('${a['report_date']}'),
    );
    return history;
  }

  Map<String, dynamic> _safeMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int _sumBrandUnits(dynamic brandDataRaw) {
    final brandData = _safeMap(brandDataRaw);
    var total = 0;
    for (final value in brandData.values) {
      final row = _safeMap(value);
      total += _toInt(row['under_2m']);
      total += _toInt(row['2m_4m']);
      total += _toInt(row['4m_6m']);
      total += _toInt(row['above_6m']);
    }
    return total;
  }

  int _sumLeasingUnits(dynamic leasingRaw) {
    final leasing = _safeMap(leasingRaw);
    return leasing.values.fold<int>(0, (sum, value) => sum + _toInt(value));
  }

  int _extractVivoUnits(dynamic vivoRaw) {
    final vivo = _safeMap(vivoRaw);
    return _toInt(vivo['total']);
  }

  int _sumCompetitorPromotors(dynamic brandDataRaw) {
    final brandData = _safeMap(brandDataRaw);
    var total = 0;
    for (final value in brandData.values) {
      final row = _safeMap(value);
      total += _toInt(row['promotor_count']);
    }
    return total;
  }

  RealtimeChannel subscribeToAllbrandReports({
    required String storeId,
    required VoidCallback onChanged,
  }) {
    return _supabase
        .channel('allbrand_reports_store_$storeId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'allbrand_reports',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'store_id',
            value: storeId,
          ),
          callback: (_) => onChanged(),
        )
        .subscribe();
  }

  Future<List<Map<String, dynamic>>> _getStoreActivityData(
    String storeId,
    String date,
  ) async {
    try {
      // Get all promotors in this store
      final promotors = await _supabase
          .from('assignments_promotor_store')
          .select('promotor_id, users!inner(full_name)')
          .eq('store_id', storeId)
          .eq('active', true);

      if (promotors.isEmpty) return [];

      final activities = <Map<String, dynamic>>[];

      for (var promotor in promotors) {
        final promotorId = promotor['promotor_id'];
        final promotorName = promotor['users']['full_name'];

        // Get clock in/out - use 'attendance' with user_id and attendance_date
        final attendance = await _supabase
            .from('attendance')
            .select('clock_in, clock_out')
            .eq('user_id', promotorId)
            .eq('attendance_date', date)
            .maybeSingle();

        // Get sales count - use 'sales_sell_out' table
        final salesData = await _supabase
            .from('sales_sell_out')
            .select('id')
            .eq('promotor_id', promotorId)
            .gte('created_at', '${date}T00:00:00')
            .lt('created_at', '${date}T23:59:59')
            .isFilter('deleted_at', null)
            .eq('is_chip_sale', false);

        final salesCount = salesData.length;

        // Get stock movements count
        final stockData = await _supabase
            .from('stock_movement_log')
            .select('id')
            .eq('moved_by', promotorId)
            .gte('moved_at', '${date}T00:00:00')
            .lt('moved_at', '${date}T23:59:59');

        final stockCount = stockData.length;

        activities.add({
          'promotor_id': promotorId,
          'promotor_name': promotorName,
          'clock_in': attendance?['clock_in'],
          'clock_out': attendance?['clock_out'],
          'sales_count': salesCount,
          'stock_count': stockCount,
        });
      }

      return activities;
    } catch (e) {
      debugPrint('=== ERROR getting activity data: $e ===');
      return [];
    }
  }

  Future<Map<String, dynamic>> _getStoreVastFinanceData(
    String storeId,
    String date,
  ) async {
    try {
      final promotorAssignments = List<Map<String, dynamic>>.from(
        await _supabase
          .from('assignments_promotor_store')
          .select('promotor_id, users!inner(full_name, nickname)')
          .eq('store_id', storeId)
          .eq('active', true),
      );

      final promotorById = <String, Map<String, dynamic>>{};
      for (final row in promotorAssignments) {
        final promotorId = '${row['promotor_id'] ?? ''}';
        if (promotorId.isEmpty || promotorById.containsKey(promotorId)) continue;
        promotorById[promotorId] = row;
      }

      if (promotorById.isEmpty) {
        return {
          'target_total': 0,
          'input_total': 0,
          'closing_total': 0,
          'today_total': 0,
          'month_total': 0,
          'pending_total': 0,
          'approved_total': 0,
          'reject_total': 0,
          'rejected_total': 0,
          'rows': <Map<String, dynamic>>[],
        };
      }

      final promotorIds = promotorById.keys.toList();
      final startOfMonth = '${date.substring(0, 8)}01';
      final endExclusive = DateTime.parse(date)
          .add(const Duration(days: 1))
          .toIso8601String()
          .split('T')
          .first;

      String? periodId;
      try {
        final periodRows = await _supabase
            .from('target_periods')
            .select('id')
            .lte('start_date', date)
            .gte('end_date', date)
            .isFilter('deleted_at', null)
            .order('start_date', ascending: false)
            .limit(1);
        if (periodRows.isNotEmpty) {
          periodId = '${periodRows.first['id'] ?? ''}';
        }
      } catch (_) {}

      final targetRows = periodId == null || periodId.isEmpty
          ? const <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(
              await _supabase
                  .from('user_targets')
                  .select('user_id, target_vast')
                  .eq('period_id', periodId)
                  .inFilter('user_id', promotorIds),
            );

      final targetByUser = <String, int>{};
      for (final row in targetRows) {
        final userId = '${row['user_id'] ?? ''}';
        if (userId.isEmpty || targetByUser.containsKey(userId)) continue;
        targetByUser[userId] = _toInt(row['target_vast']);
      }

      final rows = await _supabase
          .from('vast_applications')
          .select(
            'promotor_id, application_date, outcome_status, lifecycle_status',
          )
          .inFilter('promotor_id', promotorIds)
          .gte('application_date', startOfMonth)
          .lt('application_date', endExclusive)
          .isFilter('deleted_at', null);

      final todayTotal = rows.where((row) {
        final appDate = '${row['application_date'] ?? ''}';
        return appDate == date;
      }).length;
      final inputTotal = rows.length;
      final pendingTotal = rows.where((row) {
        final status = '${row['lifecycle_status'] ?? ''}'.toLowerCase();
        return status == 'approved_pending' ||
            status.contains('pending') ||
            status.contains('review');
      }).length;
      final closingTotal = rows.where((row) {
        final lifecycle = '${row['lifecycle_status'] ?? ''}'.toLowerCase();
        return lifecycle == 'closed_direct' || lifecycle == 'closed_follow_up';
      }).length;
      final rejectTotal = rows.where((row) {
        final lifecycle = '${row['lifecycle_status'] ?? ''}'.toLowerCase();
        final outcome = '${row['outcome_status'] ?? ''}'.toLowerCase();
        return lifecycle == 'rejected' ||
            lifecycle.contains('cancel') ||
            outcome.contains('reject') ||
            outcome.contains('cancel');
      }).length;

      final targetTotal = promotorIds.fold<int>(
        0,
        (sum, userId) => sum + (targetByUser[userId] ?? 0),
      );

      final rowByPromotor = <String, Map<String, dynamic>>{};
      for (final entry in promotorById.entries) {
        final promotorId = entry.key;
        final promotor = entry.value;
        final user = promotor['users'] is Map
            ? Map<String, dynamic>.from(promotor['users'] as Map)
            : const <String, dynamic>{};
        final name =
            '${user['nickname'] ?? ''}'.trim().isNotEmpty
            ? '${user['nickname']}'
            : '${user['full_name'] ?? 'Promotor'}';
        rowByPromotor[promotorId] = <String, dynamic>{
          'promotor_id': promotorId,
          'promotor_name': name,
          'target_total': targetByUser[promotorId] ?? 0,
          'input_total': 0,
          'closing_total': 0,
          'today_total': 0,
          'month_total': 0,
          'pending_total': 0,
          'approved_total': 0,
          'reject_total': 0,
          'rejected_total': 0,
        };
      }

      for (final raw in rows) {
        final row = Map<String, dynamic>.from(raw);
        final promotorId = '${row['promotor_id'] ?? ''}';
        final bucket = rowByPromotor[promotorId];
        if (bucket == null) continue;
        bucket['input_total'] = _toInt(bucket['input_total']) + 1;
        bucket['month_total'] = _toInt(bucket['month_total']) + 1;
        if ('${row['application_date'] ?? ''}' == date) {
          bucket['today_total'] = _toInt(bucket['today_total']) + 1;
        }
        final outcome = '${row['outcome_status'] ?? ''}'.toLowerCase();
        final lifecycle = '${row['lifecycle_status'] ?? ''}'.toLowerCase();
        if (lifecycle == 'closed_direct' || lifecycle == 'closed_follow_up') {
          bucket['closing_total'] = _toInt(bucket['closing_total']) + 1;
          bucket['approved_total'] = _toInt(bucket['approved_total']) + 1;
        } else if (lifecycle == 'rejected' ||
            outcome.contains('reject') ||
            lifecycle.contains('cancel') ||
            outcome.contains('cancel')) {
          bucket['reject_total'] = _toInt(bucket['reject_total']) + 1;
          bucket['rejected_total'] = _toInt(bucket['rejected_total']) + 1;
        } else if (lifecycle == 'approved_pending' ||
            lifecycle.contains('pending') ||
            lifecycle.contains('review')) {
          bucket['pending_total'] = _toInt(bucket['pending_total']) + 1;
        }
      }

      final summaryRows = rowByPromotor.values.toList()
        ..sort(
          (a, b) => _toInt(b['input_total']).compareTo(_toInt(a['input_total'])),
        );

      return {
        'target_total': targetTotal,
        'input_total': inputTotal,
        'closing_total': closingTotal,
        'today_total': todayTotal,
        'month_total': inputTotal,
        'pending_total': pendingTotal,
        'approved_total': closingTotal,
        'reject_total': rejectTotal,
        'rejected_total': rejectTotal,
        'rows': summaryRows,
      };
    } catch (e) {
      debugPrint('=== ERROR getting vast finance data: $e ===');
      return {
        'target_total': 0,
        'input_total': 0,
        'closing_total': 0,
        'today_total': 0,
        'month_total': 0,
        'pending_total': 0,
        'approved_total': 0,
        'reject_total': 0,
        'rejected_total': 0,
        'rows': <Map<String, dynamic>>[],
      };
    }
  }

  Future<List<ChatRoomMember>> getRoomMembers({required String roomId}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final response = await _supabase.rpc(
      'get_chat_room_members',
      params: {'p_room_id': roomId, 'p_user_id': userId},
    );

    final members = (response as List)
        .map((row) => ChatRoomMember.fromJson(row as Map<String, dynamic>))
        .toList();

    final memberIds = members
        .map((member) => member.id)
        .where((id) => id.isNotEmpty)
        .toList();
    final avatarById = <String, String>{};
    final whatsappById = <String, String>{};
    if (memberIds.isNotEmpty) {
      try {
        dynamic avatarRows;
        try {
          avatarRows = await _supabase
              .from('users')
              .select('id, avatar_url, whatsapp_phone')
              .inFilter('id', memberIds);
        } catch (_) {
          avatarRows = await _supabase
              .from('users')
              .select('id, avatar_url')
              .inFilter('id', memberIds);
        }
        for (final raw in List<Map<String, dynamic>>.from(avatarRows)) {
          final id = '${raw['id'] ?? ''}';
          final avatarUrl = '${raw['avatar_url'] ?? ''}'.trim();
          final whatsappPhone = '${raw['whatsapp_phone'] ?? ''}'.trim();
          if (id.isEmpty) continue;
          if (avatarUrl.isNotEmpty) {
            avatarById[id] = avatarUrl;
          }
          if (whatsappPhone.isNotEmpty) {
            whatsappById[id] = whatsappPhone;
          }
        }
      } catch (_) {}
    }

    final hydrated = members
        .map(
          (member) => ChatRoomMember(
            id: member.id,
            displayName: member.displayName,
            role: member.role,
            avatarUrl: avatarById[member.id] ?? member.avatarUrl,
            whatsappPhone: whatsappById[member.id] ?? member.whatsappPhone,
          ),
        )
        .toList();
    hydrated.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return hydrated;
  }
}
