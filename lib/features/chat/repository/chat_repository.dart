import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart';
import '../models/chat_room.dart';
import '../models/chat_message.dart';
import '../models/chat_room_member.dart';
import '../models/store_daily_data.dart';
import 'dart:convert';

class ChatRepository {
  final SupabaseClient _supabase = Supabase.instance.client;

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

    final response = await _supabase.rpc(
      'send_message',
      params: {
        'p_room_id': roomId,
        'p_sender_id': userId,
        'p_message_type': 'image',
        'p_content': caption,
        'p_image_url': imageUrl,
        'p_image_width': imageWidth,
        'p_image_height': imageHeight,
        'p_mentions': mentions,
        'p_reply_to_id': replyToId,
      },
    );

    return response as String;
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
    required Function() onReadReceiptUpdate,
  }) {
    return _supabase
        .channel('message_reads_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'message_reads',
          callback: (payload) => onReadReceiptUpdate(),
        )
        .subscribe();
  }

  // Subscribe to reaction updates
  RealtimeChannel subscribeToReactions({
    required String roomId,
    required Function() onReactionUpdate,
  }) {
    return _supabase
        .channel('message_reactions_$roomId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'message_reactions',
          callback: (payload) => onReactionUpdate(),
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

      final response = await _supabase.rpc(
        'get_chat_messages',
        params: {
          'p_room_id': roomId,
          'p_user_id': userId,
          'p_limit': 50, // Get more messages to find the specific one
          'p_offset': 0,
        },
      );

      if (response == null) {
        throw Exception('No response from get_chat_messages');
      }

      final messages = (response as List)
          .map((json) => ChatMessage.fromJson(json as Map<String, dynamic>))
          .where((msg) => msg.id == messageId)
          .toList();

      if (messages.isEmpty) {
        throw Exception('Message not found: $messageId');
      }

      return messages.first;
    } catch (e) {
      debugPrint('Error fetching complete message: $e');
      rethrow;
    }
  }

  // Add emoji reaction to message
  Future<void> addReaction({
    required String messageId,
    required String emoji,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    await _supabase.from('message_reactions').insert({
      'message_id': messageId,
      'user_id': userId,
      'emoji': emoji,
    });
  }

  // Remove emoji reaction from message
  Future<void> removeReaction({
    required String messageId,
    required String emoji,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    await _supabase
        .from('message_reactions')
        .delete()
        .eq('message_id', messageId)
        .eq('user_id', userId)
        .eq('emoji', emoji);
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

      return {
        'target': targetData,
        'allbrand': allbrandData,
        'activity': activityData,
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
          name =
              user['nickname']?.toString().trim().isNotEmpty == true
              ? user['nickname'].toString().trim()
              : (user['full_name']?.toString() ?? 'Promotor');
        }
        if (id.isNotEmpty) promotorNameById[id] = name;
      }

      // Get sales data for today - use 'sales_sell_out' table
      final sales = await _supabase
          .from('sales_sell_out')
          .select(
            'promotor_id, price_at_transaction, variant_id, product_variants!inner(product_id, variant_name, products!inner(model_name))',
          )
          .inFilter('promotor_id', promotorIds)
          .gte('created_at', '${date}T00:00:00')
          .lt('created_at', '${date}T23:59:59');

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
            final modelName =
                variant['products'] is Map
                ? Map<String, dynamic>.from(variant['products'])['model_name']
                      ?.toString()
                : null;
            final variantName = variant['variant_name']?.toString();
            final label = (modelName != null && modelName.isNotEmpty)
                ? (variantName != null && variantName.isNotEmpty
                      ? '$modelName $variantName'
                      : modelName)
                : (variantName ?? 'Produk');
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
            fokusByPromotor[promotorId] = (fokusByPromotor[promotorId] ?? 0) + 1;
          }
        }
      }

      // Get targets for this month - use period_id instead of month_year
      // For now, just get all targets for these users (we'll improve period filtering later)
      final targets = await _supabase
          .from('user_targets')
          .select('user_id, target_omzet, target_fokus_total')
          .inFilter('user_id', promotorIds);

      int totalDailyTarget = 0;
      int totalFokusTarget = 0;

      for (var target in targets) {
        totalDailyTarget += ((target['target_omzet'] as num?) ?? 0).toInt();
        totalFokusTarget += ((target['target_fokus_total'] as num?) ?? 0)
            .toInt();
      }

      // Calculate daily target (monthly / 30)
      final dailyTarget = (totalDailyTarget / 30).round();
      final dailyFokusTarget = (totalFokusTarget / 30).round();
      final selloutByPromotor = promotorIds.map((rawId) {
        final promotorId = '$rawId';
        return {
          'promotor_id': promotorId,
          'promotor_name': promotorNameById[promotorId] ?? 'Promotor',
          'units': unitByPromotor[promotorId] ?? 0,
          'omzet': omzetByPromotor[promotorId] ?? 0,
          'focus_units': fokusByPromotor[promotorId] ?? 0,
          'variants': variantsByPromotor[promotorId] ?? const <String>[],
        };
      }).toList()
        ..sort(
          (a, b) => ((b['omzet'] as int).compareTo(a['omzet'] as int)),
        );

      return {
        'daily_achievement': dailyAchievement,
        'daily_target': dailyTarget,
        'monthly_achievement':
            dailyAchievement, // TODO: Calculate actual monthly
        'monthly_target': totalDailyTarget,
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
          .eq('transaction_date', date);

      final salesCumulative = await _supabase
          .from('sales_sell_out')
          .select('promotor_id, variant_id')
          .eq('store_id', storeId)
          .lte('transaction_date', date);

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
            .lt('created_at', '${date}T23:59:59');

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

  Future<List<ChatRoomMember>> getRoomMembers({required String roomId}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('User not authenticated');

    final response = await _supabase.rpc(
      'get_chat_room_members',
      params: {
        'p_room_id': roomId,
        'p_user_id': userId,
      },
    );

    final members = (response as List)
        .map((row) => ChatRoomMember.fromJson(row as Map<String, dynamic>))
        .toList();
    members.sort(
      (a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );
    return members;
  }
}
