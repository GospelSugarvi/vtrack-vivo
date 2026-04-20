import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/components/field_segmented_control.dart';
import '../../../../ui/promotor/promotor.dart';
import '../../../../ui/ui.dart';

enum LeaderboardActorMode { promotor, sator, spv }

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({
    super.key,
    this.title = 'Leaderboard',
    this.liveSubtitle = 'Live semua area · bonus harian promotor',
    this.scopeLabel = 'Semua Area',
    this.actorMode = LeaderboardActorMode.promotor,
  });

  final String title;
  final String liveSubtitle;
  final String scopeLabel;
  final LeaderboardActorMode actorMode;

  @override
  State<LeaderboardPage> createState() => _LeaderboardPageState();
}

class _LeaderboardPageState extends State<LeaderboardPage> {
  final _supabase = Supabase.instance.client;
  final _rupiahFormat = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final _dateFormat = DateFormat('EEE, d MMM', 'id_ID');

  bool _isLoading = true;
  int _selectedTab = 0;
  DateTime _selectedDate = DateTime.now();
  String? _currentUserId;

  List<_LeaderboardEntry> _ranking = const [];
  List<_FeedEntry> _feed = const [];
  List<_SatorCompactSummary> _satorSummaries = const [];
  bool _noSalesCollapsed = true;
  Map<String, List<_FeedComment>> _commentsBySale = const {};
  Map<String, int> _seenCommentCounts = const {};

  FieldThemeTokens get t => context.fieldTokens;
  bool get _canRequestReport =>
      widget.actorMode == LeaderboardActorMode.sator ||
      widget.actorMode == LeaderboardActorMode.spv;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      return;
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }

    try {
      final dateValue = _selectedDate.toIso8601String().split('T').first;
      final results = await Future.wait<dynamic>([
        _supabase.rpc(
          'get_daily_ranking',
          params: {'p_date': dateValue, 'p_area_id': null, 'p_limit': 300},
        ),
        _supabase.rpc(
          'get_live_feed',
          params: {
            'p_user_id': userId,
            'p_date': dateValue,
            'p_limit': 200,
            'p_offset': 0,
          },
        ),
        _supabase.rpc(
          'get_sator_compact_summary',
          params: {'p_date': dateValue},
        ),
      ]);
      final rankingResult = results[0];
      final feedResult = results[1];
      final satorSummaryResult = results[2];
      final rankingRows = _asMapList(rankingResult);
      final feedRows = _asMapList(feedResult);
      final satorSummaryRows = _asMapList(satorSummaryResult);
      final rankingEntries = rankingRows
          .map(_LeaderboardEntry.fromMap)
          .toList();
      final feedEntries = feedRows.map(_FeedEntry.fromMap).toList();
      final satorEntries = satorSummaryRows
          .map(_SatorCompactSummary.fromMap)
          .toList();

      if (!mounted) return;
      setState(() {
        _currentUserId = userId;
        _ranking = rankingEntries;
        _feed = feedEntries;
        _satorSummaries = satorEntries;
        _commentsBySale = const {};
        _seenCommentCounts = const {};
        _isLoading = false;
      });
      await _restoreSeenCommentCounts();
      await _primeFeedComments(feedEntries);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ranking = const [];
        _feed = const [];
        _satorSummaries = const [];
        _commentsBySale = const {};
        _seenCommentCounts = const {};
        _isLoading = false;
      });
    }
  }

  String _seenCommentsPrefsKey() {
    final userId = _currentUserId ?? _supabase.auth.currentUser?.id ?? 'guest';
    return 'live_feed.seen_comment_counts.$userId';
  }

  Future<void> _restoreSeenCommentCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_seenCommentsPrefsKey());
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      if (!mounted) return;
      setState(() {
        _seenCommentCounts = decoded.map(
          (key, value) => MapEntry(
            key.toString(),
            int.tryParse('$value') ?? 0,
          ),
        );
      });
    } catch (_) {}
  }

  Future<void> _persistSeenCommentCounts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _seenCommentsPrefsKey(),
        jsonEncode(_seenCommentCounts),
      );
    } catch (_) {}
  }

  int _unreadCommentCount(String saleId, int currentCount) {
    final seenCount = _seenCommentCounts[saleId] ?? 0;
    final unread = currentCount - seenCount;
    return unread > 0 ? unread : 0;
  }

  Future<void> _markCommentsSeen(String saleId, int count) async {
    final nextCounts = <String, int>{
      ..._seenCommentCounts,
      saleId: count,
    };
    if (mounted) {
      setState(() => _seenCommentCounts = nextCounts);
    } else {
      _seenCommentCounts = nextCounts;
    }
    await _persistSeenCommentCounts();
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    if (value is String && value.trim().isNotEmpty) {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded
            .whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList();
      }
    }
    return const [];
  }

  Future<void> _primeFeedComments(List<_FeedEntry> entries) async {
    final saleIds = entries
        .where((entry) => entry.commentCount > 0)
        .map((entry) => entry.saleId)
        .where((saleId) => saleId.trim().isNotEmpty)
        .toSet()
        .toList();

    if (saleIds.isEmpty) return;

    try {
      final rows = await _supabase
          .from('feed_comments')
          .select(
            'sale_id, id, user_id, comment_text, created_at, parent_comment_id, mentioned_user_ids, users!inner(full_name), system_personas!left(display_name)',
          )
          .inFilter('sale_id', saleIds)
          .isFilter('deleted_at', null)
          .order('created_at');

      final grouped = <String, List<_FeedComment>>{};
      for (final row in List<Map<String, dynamic>>.from(rows)) {
        final saleId = '${row['sale_id'] ?? ''}'.trim();
        if (saleId.isEmpty) continue;
        grouped
            .putIfAbsent(saleId, () => <_FeedComment>[])
            .add(
              _FeedComment(
                commentId: '${row['id'] ?? ''}',
                userId: '${row['user_id'] ?? ''}',
                userName:
                    '${row['system_personas']?['display_name'] ?? row['users']?['full_name'] ?? 'User'}',
                commentText: '${row['comment_text'] ?? ''}',
                createdAt: _toDateTime(row['created_at']),
                parentCommentId: row['parent_comment_id']?.toString(),
                mentionedUserIds: _toStringList(row['mentioned_user_ids']),
                isSystemPersona:
                    row['system_personas'] != null &&
                    row['system_personas'] != false,
              ),
            );
      }

      if (!mounted) return;
      setState(() => _commentsBySale = grouped);
    } catch (_) {}
  }

  String _formatMoneyTight(num value) {
    if (value <= 0) return '-';
    if (value >= 1000000) {
      final jt = value / 1000000;
      return '${jt.toStringAsFixed(jt >= 10 ? 0 : 1)}jt';
    }
    if (value >= 1000) {
      final rb = value / 1000;
      return '${rb.toStringAsFixed(rb >= 10 ? 0 : 1)}rb';
    }
    return value.toStringAsFixed(0);
  }

  String _displayName(String promotorId, String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'Promotor';
    return trimmed;
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mnt lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
  }

  String _reportTitleTemplate() {
    final day = DateFormat('dd MMM yyyy', 'id_ID').format(_selectedDate);
    final time = DateFormat('HH:mm', 'id_ID').format(DateTime.now());
    return 'Update progress penjualan $day - $time';
  }

  List<Map<String, dynamic>> _defaultSpvRequestFields({
    num? selloutTarget,
    num? focusTarget,
    int? vastTarget,
  }) {
    final selloutLabel = selloutTarget != null && selloutTarget > 0
        ? 'Target harian ${_rupiahFormat.format(selloutTarget)}'
        : 'Target harian otomatis dari dashboard SATOR';
    final focusLabel = focusTarget != null && focusTarget > 0
        ? 'Target harian ${focusTarget.toStringAsFixed(focusTarget % 1 == 0 ? 0 : 1)} unit'
        : 'Target harian otomatis dari dashboard produk fokus SATOR';
    final vastLabel = vastTarget != null && vastTarget > 0
        ? 'Target harian $vastTarget'
        : 'Target harian otomatis dari dashboard VAST Finance SATOR';
    return [
      {
        'label': 'Sellout vs target',
        'description':
            'Isi progres sellout terhadap target saat ini. $selloutLabel',
      },
      {
        'label': 'Produk fokus',
        'description':
            'Isi progres tipe fokus yang sedang berjalan. $focusLabel',
      },
      {
        'label': 'VAST finance',
        'description': 'Isi perkembangan VAST finance terbaru. $vastLabel',
      },
    ];
  }

  Future<Map<String, dynamic>> _loadLeaderRoomAutoTargets(String roomId) async {
    try {
      final memberRows = await _supabase
          .from('chat_members')
          .select('user_id, users!inner(role)')
          .eq('room_id', roomId)
          .isFilter('left_at', null);
      String? satorId;
      for (final raw in _asMapList(memberRows)) {
        final user = raw['users'] is Map
            ? Map<String, dynamic>.from(raw['users'] as Map)
            : const <String, dynamic>{};
        final role = '${user['role'] ?? ''}'.trim().toLowerCase();
        if (role == 'sator') {
          satorId = '${raw['user_id'] ?? ''}'.trim();
          if (satorId.isNotEmpty) break;
        }
      }
      if (satorId == null || satorId.isEmpty) return const <String, dynamic>{};

      final snapshotRaw = await _supabase.rpc(
        'get_sator_home_snapshot',
        params: <String, dynamic>{'p_sator_id': satorId},
      );
      final vastSnapshotRaw = await _supabase.rpc(
        'get_sator_vast_page_snapshot',
        params: {'p_date': DateFormat('yyyy-MM-dd').format(_selectedDate)},
      );
      final snapshot = snapshotRaw is Map
          ? Map<String, dynamic>.from(snapshotRaw)
          : const <String, dynamic>{};
      final vastSnapshot = vastSnapshotRaw is Map
          ? Map<String, dynamic>.from(vastSnapshotRaw)
          : const <String, dynamic>{};
      final daily = snapshot['daily'] is Map
          ? Map<String, dynamic>.from(snapshot['daily'] as Map)
          : const <String, dynamic>{};
      final vastDaily = vastSnapshot['daily'] is Map
          ? Map<String, dynamic>.from(vastSnapshot['daily'] as Map)
          : const <String, dynamic>{};

      return <String, dynamic>{
        'sellout_target': daily['target_sellout'],
        'focus_target':
            daily['target_fokus'] ??
            daily['target_focus'] ??
            daily['target_daily_focus'],
        'vast_target': vastDaily['target_submissions'],
      };
    } catch (_) {
      return const <String, dynamic>{};
    }
  }

  List<Map<String, dynamic>> _defaultStoreRequestFields() {
    return const [
      {
        'label': 'Detail penjualan per promotor',
        'description': 'Isi tipe jualan, SRP, VAST, dan catatan tiap promotor',
      },
      {
        'label': 'Pencapaian brand lain',
        'description': 'Isi unit brand lain tingkat toko',
      },
      {
        'label': 'Catatan toko',
        'description': 'Isi keterangan situasi toko saat ini',
      },
    ];
  }

  Future<void> _openRequestReportSheet() async {
    switch (widget.actorMode) {
      case LeaderboardActorMode.spv:
        await _openSpvRequestComposer();
        break;
      case LeaderboardActorMode.sator:
        await _openSatorRequestComposer();
        break;
      case LeaderboardActorMode.promotor:
        break;
    }
  }

  Future<void> _openSpvRequestComposer() async {
    final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final rows = _asMapList(
        await _supabase.rpc(
          'get_spv_leader_request_rooms',
          params: {'p_spv_id': userId},
        ),
      );
      if (!mounted) return;
      if (rows.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belum ada grup leader aktif untuk SPV ini.'),
          ),
        );
        return;
      }

      String selectedRoomId = '${rows.first['room_id']}';
      final noteController = TextEditingController();
      final customFields = <Map<String, TextEditingController>>[];
      bool isSubmitting = false;
      String? nextRoomId;
      bool requestSent = false;
      Map<String, dynamic> autoTargets = await _loadLeaderRoomAutoTargets(
        selectedRoomId,
      );
      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> submit() async {
                if (isSubmitting) return;
                setModalState(() => isSubmitting = true);
                try {
                  final fields = <Map<String, dynamic>>[
                    ..._defaultSpvRequestFields(
                      selloutTarget: (autoTargets['sellout_target'] as num?)
                          ?.toDouble(),
                      focusTarget: (autoTargets['focus_target'] as num?)
                          ?.toDouble(),
                      vastTarget: (autoTargets['vast_target'] as num?)?.toInt(),
                    ),
                    ...customFields
                        .map(
                          (item) => {
                            'label': item['label']!.text.trim(),
                            'description': item['description']!.text.trim(),
                          },
                        )
                        .where((item) => '${item['label']}'.isNotEmpty),
                  ];
                  await _supabase.rpc(
                    'create_chat_report_request',
                    params: {
                      'p_room_id': selectedRoomId,
                      'p_request_type': 'spv_to_sator',
                      'p_title': _reportTitleTemplate(),
                      'p_note': noteController.text.trim(),
                      'p_field_schema': fields,
                    },
                  );
                  requestSent = true;
                  nextRoomId = selectedRoomId;
                  if (!mounted) return;
                  Navigator.of(this.context, rootNavigator: true).pop();
                } catch (error) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal kirim permintaan laporan. $error'),
                    ),
                  );
                } finally {
                  if (context.mounted) {
                    setModalState(() => isSubmitting = false);
                  }
                }
              }

              return AlertDialog(
                title: const Text('Minta Laporan SATOR'),
                content: SizedBox(
                  width: 640,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: selectedRoomId,
                          decoration: const InputDecoration(
                            labelText: 'Pilihan grup',
                          ),
                          items: rows
                              .map(
                                (row) => DropdownMenuItem<String>(
                                  value: '${row['room_id']}',
                                  child: Text('${row['room_name'] ?? '-'}'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value == null) return;
                            setModalState(() => selectedRoomId = value);
                            _loadLeaderRoomAutoTargets(value).then((value) {
                              if (!context.mounted) return;
                              setModalState(() => autoTargets = value);
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: noteController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Catatan',
                            hintText: 'Boleh kosong',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Field custom',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () {
                                setModalState(() {
                                  customFields.add({
                                    'label': TextEditingController(),
                                    'description': TextEditingController(),
                                  });
                                });
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Tambah'),
                            ),
                          ],
                        ),
                        if (customFields.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: t.surface1,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: t.surface3),
                            ),
                            child: Text(
                              'Belum ada field custom. Field utama dikirim otomatis.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ...customFields.asMap().entries.map((entry) {
                          final index = entry.key;
                          final item = entry.value;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: t.surface1,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: t.surface3),
                              ),
                              child: Column(
                                children: [
                                  TextField(
                                    controller: item['label'],
                                    decoration: InputDecoration(
                                      labelText:
                                          'Nama field custom ${index + 1}',
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: item['description'],
                                    decoration: const InputDecoration(
                                      labelText: 'Isi / keterangan field',
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: IconButton(
                                      onPressed: () {
                                        setModalState(() {
                                          item['label']!.dispose();
                                          item['description']!.dispose();
                                          customFields.removeAt(index);
                                        });
                                      },
                                      icon: const Icon(Icons.delete_outline),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  FilledButton(
                    onPressed: isSubmitting ? null : submit,
                    child: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kirim'),
                  ),
                ],
              );
            },
          );
        },
      );

      await Future<void>.delayed(kThemeAnimationDuration);
      for (final item in customFields) {
        item['label']?.dispose();
        item['description']?.dispose();
      }
      noteController.dispose();
      if (!mounted || !requestSent) return;
      if (nextRoomId != null) {
        GoRouter.of(context).push('/chat-room/$nextRoomId');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permintaan laporan berhasil dikirim.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka composer laporan. $e')),
      );
    }
  }

  Future<void> _openSatorRequestComposer() async {
    final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final stores = _asMapList(
        await _supabase.rpc(
          'get_sator_report_request_store_scope',
          params: {'p_sator_id': userId},
        ),
      );
      if (!mounted) return;
      if (stores.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belum ada toko tim untuk SATOR ini.')),
        );
        return;
      }

      final selectedStoreIds = <String>{};
      final noteController = TextEditingController();
      bool isSubmitting = false;
      String? firstRoomIdToOpen;
      bool requestSent = false;

      await showDialog<void>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setModalState) {
              Future<void> submit() async {
                if (selectedStoreIds.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pilih minimal satu toko.')),
                  );
                  return;
                }
                setModalState(() => isSubmitting = true);
                try {
                  for (final store in stores) {
                    final storeId = '${store['store_id']}';
                    if (!selectedStoreIds.contains(storeId)) continue;
                    final roomId = '${store['room_id'] ?? ''}'.trim();
                    if (roomId.isEmpty) continue;
                    firstRoomIdToOpen ??= roomId;
                    await _supabase.rpc(
                      'create_chat_report_request',
                      params: {
                        'p_room_id': roomId,
                        'p_request_type': 'sator_to_store',
                        'p_title': _reportTitleTemplate(),
                        'p_note': noteController.text.trim(),
                        'p_field_schema': _defaultStoreRequestFields(),
                      },
                    );
                  }
                  requestSent = true;
                  if (!mounted) return;
                  Navigator.of(this.context, rootNavigator: true).pop();
                } catch (error) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text('Gagal kirim permintaan laporan. $error'),
                    ),
                  );
                } finally {
                  if (context.mounted) {
                    setModalState(() => isSubmitting = false);
                  }
                }
              }

              return AlertDialog(
                title: const Text('Minta Laporan Promotor'),
                content: SizedBox(
                  width: 680,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _reportTitleTemplate(),
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: noteController,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            labelText: 'Catatan SATOR',
                            hintText: 'Boleh kosong',
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Pilih toko tujuan',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        ...stores.map((store) {
                          final storeId = '${store['store_id']}';
                          final roomReady = '${store['room_id'] ?? ''}'
                              .trim()
                              .isNotEmpty;
                          return CheckboxListTile(
                            value: selectedStoreIds.contains(storeId),
                            onChanged: roomReady
                                ? (value) {
                                    setModalState(() {
                                      if (value == true) {
                                        selectedStoreIds.add(storeId);
                                      } else {
                                        selectedStoreIds.remove(storeId);
                                      }
                                    });
                                  }
                                : null,
                            title: Text('${store['store_name'] ?? '-'}'),
                            subtitle: Text(
                              roomReady
                                  ? '${store['promotor_count'] ?? 0} promotor'
                                  : 'Belum ada grup toko aktif',
                            ),
                            contentPadding: EdgeInsets.zero,
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Batal'),
                  ),
                  FilledButton(
                    onPressed: isSubmitting ? null : submit,
                    child: isSubmitting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kirim'),
                  ),
                ],
              );
            },
          );
        },
      );

      await Future<void>.delayed(kThemeAnimationDuration);
      noteController.dispose();
      if (!mounted || !requestSent) return;
      if (firstRoomIdToOpen != null) {
        GoRouter.of(context).push('/chat-room/$firstRoomIdToOpen');
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Permintaan laporan toko berhasil dikirim.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gagal membuka composer laporan. $e')),
      );
    }
  }

  String _reactionLabel(String type) {
    switch (type) {
      case 'fire':
        return '🔥';
      case 'clap':
        return '👏';
      case 'muscle':
        return '💪';
      default:
        return '•';
    }
  }

  Future<void> _toggleReaction(_FeedEntry entry, String reactionType) async {
    final userId = _currentUserId;
    if (userId == null) return;

    try {
      final result = await _supabase.rpc(
        'toggle_reaction',
        params: {
          'p_sale_id': entry.saleId,
          'p_user_id': userId,
          'p_reaction_type': reactionType,
        },
      );
      final added = result == true;

      if (!mounted) return;
      setState(() {
        _feed = _feed.map((item) {
          if (item.saleId != entry.saleId) return item;
          final counts = Map<String, int>.from(item.reactionCounts);
          final reactions = Set<String>.from(item.userReactions);

          if (added) {
            counts[reactionType] = (counts[reactionType] ?? 0) + 1;
            reactions.add(reactionType);
          } else {
            final next = (counts[reactionType] ?? 1) - 1;
            if (next <= 0) {
              counts.remove(reactionType);
            } else {
              counts[reactionType] = next;
            }
            reactions.remove(reactionType);
          }

          return item.copyWith(
            reactionCounts: counts,
            userReactions: reactions,
          );
        }).toList();
      });
    } catch (_) {}
  }

  Future<List<_ReactionDetail>> _loadReactionDetails(String saleId) async {
    try {
      final rows = await _supabase.rpc(
        'get_sale_reaction_details',
        params: {'p_sale_id': saleId},
      );
      return _asMapList(rows).map(_ReactionDetail.fromMap).toList();
    } catch (_) {
      try {
        final rows = await _supabase
            .from('feed_reactions')
            .select('reaction_type, created_at, users!inner(full_name)')
            .eq('sale_id', saleId)
            .order('reaction_type')
            .order('created_at');
        return List<Map<String, dynamic>>.from(rows).map((row) {
          return _ReactionDetail(
            reactionType: '${row['reaction_type'] ?? ''}',
            userName: '${row['users']?['full_name'] ?? 'User'}',
            createdAt: _toDateTime(row['created_at']),
          );
        }).toList();
      } catch (_) {
        return const [];
      }
    }
  }

  Future<void> _openReactionSummary(
    _FeedEntry entry, {
    String? initialReactionType,
  }) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          child: Container(
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: t.surface3),
            ),
            child: SafeArea(
              top: false,
              child: FutureBuilder<List<_ReactionDetail>>(
                future: _loadReactionDetails(entry.saleId),
                builder: (context, snapshot) {
                  final data = snapshot.data ?? const <_ReactionDetail>[];
                  final grouped = <String, List<_ReactionDetail>>{};
                  for (final item in data) {
                    grouped.putIfAbsent(item.reactionType, () => []).add(item);
                  }
                  final orderedTypes = <String>[
                    if (initialReactionType != null &&
                        grouped.containsKey(initialReactionType))
                      initialReactionType,
                    ...grouped.keys.where((key) => key != initialReactionType),
                  ];

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 38,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 10),
                        decoration: BoxDecoration(
                          color: t.surface4,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: CircularProgressIndicator(
                            color: t.primaryAccent,
                          ),
                        )
                      else if (data.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                          child: Text(
                            'Belum ada reaksi.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: t.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                            children: orderedTypes.map((reactionType) {
                              final users = grouped[reactionType] ?? const [];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Container(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    9,
                                    10,
                                    9,
                                  ),
                                  decoration: BoxDecoration(
                                    color: t.surface2,
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: t.surface3),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 9,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: t.primaryAccentSoft,
                                          borderRadius: BorderRadius.circular(
                                            999,
                                          ),
                                        ),
                                        child: Text(
                                          '${_reactionLabel(reactionType)} ${users.length}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelMedium
                                              ?.copyWith(
                                                color: t.primaryAccent,
                                                fontWeight: FontWeight.w900,
                                              ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...users.map((user) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 7,
                                          ),
                                          child: Row(
                                            children: [
                                              _buildAvatar(
                                                user.userName,
                                                radius: 11,
                                              ),
                                              const SizedBox(width: 7),
                                              Expanded(
                                                child: Text(
                                                  user.userName,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        color: t.textSecondary,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        fontSize: 13,
                                                      ),
                                                ),
                                              ),
                                              Text(
                                                _timeAgo(user.createdAt),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .labelSmall
                                                    ?.copyWith(
                                                      color: t.textMuted,
                                                      fontSize: 10,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _ensureCommentsLoaded(
    String saleId, {
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _commentsBySale.containsKey(saleId)) {
      return;
    }

    try {
      final rows = await _supabase.rpc(
        'get_sale_comments',
        params: {'p_sale_id': saleId},
      );
      final comments = _asMapList(rows).map(_FeedComment.fromMap).toList();

      if (!mounted) return;
      setState(() {
        _commentsBySale = {..._commentsBySale, saleId: comments};
      });
    } catch (_) {
      try {
        final rows = await _supabase
            .from('feed_comments')
            .select(
              'id, user_id, comment_text, created_at, parent_comment_id, mentioned_user_ids, users!inner(full_name), system_personas!left(display_name)',
            )
            .eq('sale_id', saleId)
            .isFilter('deleted_at', null)
            .order('created_at');
        final comments = List<Map<String, dynamic>>.from(rows).map((row) {
          return _FeedComment(
            commentId: '${row['id'] ?? ''}',
            userId: '${row['user_id'] ?? ''}',
            userName:
                '${row['system_personas']?['display_name'] ?? row['users']?['full_name'] ?? 'User'}',
            commentText: '${row['comment_text'] ?? ''}',
            createdAt: _toDateTime(row['created_at']),
            parentCommentId: row['parent_comment_id']?.toString(),
            mentionedUserIds: _toStringList(row['mentioned_user_ids']),
            isSystemPersona:
                row['system_personas'] != null &&
                row['system_personas'] != false,
          );
        }).toList();

        if (!mounted) return;
        setState(() {
          _commentsBySale = {..._commentsBySale, saleId: comments};
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _commentsBySale = Map<String, List<_FeedComment>>.from(
            _commentsBySale,
          )..remove(saleId);
        });
      }
    }
  }

  Future<void> _submitSaleComment(String saleId, String rawText) async {
    final userId = _currentUserId ?? _supabase.auth.currentUser?.id;
    final commentText = rawText.trim();
    if (userId == null || commentText.isEmpty) {
      throw Exception('Komentar tidak valid.');
    }

    try {
      await _supabase.rpc(
        'add_comment',
        params: {
          'p_sale_id': saleId,
          'p_user_id': userId,
          'p_comment_text': commentText,
          'p_parent_comment_id': null,
          'p_mentioned_user_ids': <String>[],
        },
      );
    } catch (_) {
      await _supabase.from('feed_comments').insert({
        'sale_id': saleId,
        'user_id': userId,
        'comment_text': commentText,
      });
    }

    await _ensureCommentsLoaded(saleId, forceRefresh: true);
    if (!mounted) return;

    setState(() {
      final loadedCount = _commentsBySale[saleId]?.length ?? 0;
      _feed = _feed.map((item) {
        if (item.saleId != saleId) return item;
        final nextCount = loadedCount > item.commentCount
            ? loadedCount
            : item.commentCount + 1;
        return item.copyWith(commentCount: nextCount);
      }).toList();
    });
  }

  Future<void> _openCommentsSheet(_FeedEntry entry) async {
    await _ensureCommentsLoaded(
      entry.saleId,
      forceRefresh:
          entry.commentCount > 0 &&
          (_commentsBySale[entry.saleId]?.isEmpty ?? true),
    );
    if (!mounted) return;
    final initialComments = _threadedComments(
      _commentsBySale[entry.saleId] ?? const [],
    );
    await _markCommentsSeen(entry.saleId, initialComments.length);
    if (!mounted) return;

    final commentController = TextEditingController();
    var isSubmitting = false;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            final comments = _threadedComments(
              _commentsBySale[entry.saleId] ?? const [],
            );

            return Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                MediaQuery.of(context).viewInsets.bottom + 12,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: t.surface1,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: t.surface3),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 42,
                        height: 4,
                        margin: const EdgeInsets.only(top: 10, bottom: 14),
                        decoration: BoxDecoration(
                          color: t.surface4,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Text(
                              'Komentar',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              '${comments.length} pesan',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: t.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Flexible(
                        child: comments.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  20,
                                  16,
                                  28,
                                ),
                                child: Text(
                                  'Belum ada komentar. Tulis komentar pertama kalau perlu.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: t.textMuted),
                                  textAlign: TextAlign.center,
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  0,
                                  16,
                                  16,
                                ),
                                itemBuilder: (context, index) {
                                  final comment = comments[index];
                                  return _buildCommentTile(comment);
                                },
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 10),
                                itemCount: comments.length,
                              ),
                      ),
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                        decoration: BoxDecoration(
                          color: t.surface1,
                          borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(24),
                          ),
                          border: Border(top: BorderSide(color: t.surface3)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Expanded(
                              child: TextField(
                                controller: commentController,
                                minLines: 1,
                                maxLines: 4,
                                textInputAction: TextInputAction.send,
                                decoration: InputDecoration(
                                  hintText: 'Tulis komentar di sini...',
                                  filled: true,
                                  fillColor: t.surface2,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: t.surface3),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(color: t.surface3),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide(
                                      color: t.primaryAccent,
                                    ),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                ),
                                onSubmitted: isSubmitting
                                    ? null
                                    : (_) async {
                                        final text = commentController.text;
                                        if (text.trim().isEmpty) return;
                                        setModalState(
                                          () => isSubmitting = true,
                                        );
                                        try {
                                          await _submitSaleComment(
                                            entry.saleId,
                                            text,
                                          );
                                          commentController.clear();
                                          await _markCommentsSeen(
                                            entry.saleId,
                                            _threadedComments(
                                              _commentsBySale[entry.saleId] ??
                                                  const [],
                                            ).length,
                                          );
                                          setModalState(() {});
                                        } catch (error) {
                                          if (!mounted) return;
                                          ScaffoldMessenger.of(
                                            this.context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'Gagal kirim komentar. $error',
                                              ),
                                            ),
                                          );
                                        } finally {
                                          if (context.mounted) {
                                            setModalState(
                                              () => isSubmitting = false,
                                            );
                                          }
                                        }
                                      },
                              ),
                            ),
                            const SizedBox(width: 10),
                            FilledButton(
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      final text = commentController.text;
                                      if (text.trim().isEmpty) return;
                                      setModalState(() => isSubmitting = true);
                                      try {
                                        await _submitSaleComment(
                                          entry.saleId,
                                          text,
                                        );
                                        commentController.clear();
                                        await _markCommentsSeen(
                                          entry.saleId,
                                          _threadedComments(
                                            _commentsBySale[entry.saleId] ??
                                                const [],
                                          ).length,
                                        );
                                        setModalState(() {});
                                      } catch (error) {
                                        if (!mounted) return;
                                        ScaffoldMessenger.of(
                                          this.context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Gagal kirim komentar. $error',
                                            ),
                                          ),
                                        );
                                      } finally {
                                        if (context.mounted) {
                                          setModalState(
                                            () => isSubmitting = false,
                                          );
                                        }
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                minimumSize: const Size(52, 52),
                                padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              child: isSubmitting
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    await Future<void>.delayed(kThemeAnimationDuration);
    commentController.dispose();
  }

  void _openFeedImage(_FeedEntry entry) {
    if (entry.imageUrl.trim().isEmpty) return;
    showDialog<void>(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.transparent,
          child: Stack(
            children: [
              InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.network(
                    entry.imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) =>
                        _buildNoPhotoPlaceholder(),
                  ),
                ),
              ),
              Positioned(
                right: 10,
                top: 10,
                child: IconButton.filled(
                  onPressed: () => Navigator.of(context).pop(),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.55),
                    foregroundColor: Colors.white,
                  ),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.shellBackground,
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              t.background,
              Color.lerp(t.background, t.shellBackground, 0.36)!,
            ],
          ),
        ),
        child: Column(
          children: [
            AppSafeHeader(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 2),
                child: _buildHeader(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: FieldSegmentedControl(
                labels: const ['Leaderboard', 'Live Feed'],
                selectedIndex: _selectedTab,
                onSelected: (index) {
                  setState(() => _selectedTab = index);
                },
              ),
            ),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: CircularProgressIndicator(color: t.primaryAccent),
                    )
                  : _selectedTab == 0
                  ? _buildLeaderboardTab()
                  : _buildFeedTab(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: t.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
            if (_canRequestReport) ...[
              const SizedBox(width: 12),
              Flexible(
                child: FilledButton.icon(
                  onPressed: _openRequestReportSheet,
                  icon: const Icon(Icons.assignment_outlined, size: 15),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    textStyle: Theme.of(context).textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w800, fontSize: 11),
                  ),
                  label: const Text(
                    'Minta laporan',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.surface3),
          ),
          child: Row(
            children: [
              _buildDateArrow(
                icon: Icons.chevron_left_rounded,
                compact: true,
                onTap: () {
                  setState(() {
                    _selectedDate = _selectedDate.subtract(
                      const Duration(days: 1),
                    );
                  });
                  _loadData();
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _dateFormat.format(_selectedDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _buildDateArrow(
                icon: Icons.chevron_right_rounded,
                compact: true,
                enabled: !DateUtils.isSameDay(_selectedDate, DateTime.now()),
                onTap: !DateUtils.isSameDay(_selectedDate, DateTime.now())
                    ? () {
                        setState(() {
                          _selectedDate = _selectedDate.add(
                            const Duration(days: 1),
                          );
                        });
                        _loadData();
                      }
                    : null,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDateArrow({
    required IconData icon,
    required VoidCallback? onTap,
    bool enabled = true,
    bool compact = false,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(compact ? 10 : 12),
      child: Container(
        width: compact ? 26 : 38,
        height: compact ? 26 : 38,
        decoration: BoxDecoration(
          color: enabled ? t.surface2 : t.surface2.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(compact ? 10 : 12),
          border: Border.all(color: t.surface3),
        ),
        child: Icon(
          icon,
          size: compact ? 16 : 22,
          color: enabled ? t.textSecondary : t.textMutedStrong,
        ),
      ),
    );
  }

  Widget _buildLeaderboardTab() {
    if (_ranking.isEmpty) {
      return RefreshIndicator(
        color: t.primaryAccent,
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SizedBox(height: 24)],
        ),
      );
    }

    final sold = _ranking.where((entry) => entry.hasSold).toList();
    final noSales = _ranking.where((entry) => !entry.hasSold).toList();
    final topThree = sold.take(3).toList();

    return RefreshIndicator(
      color: t.primaryAccent,
      onRefresh: _loadData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _leaderboardItemCount(sold),
        itemBuilder: (context, index) =>
            _buildLeaderboardListItem(index, sold, noSales, topThree),
      ),
    );
  }

  int _leaderboardItemCount(List<_LeaderboardEntry> sold) {
    final soldRowsCount = sold.isEmpty ? 1 : sold.length;
    return 11 + soldRowsCount;
  }

  Widget _buildLeaderboardListItem(
    int index,
    List<_LeaderboardEntry> sold,
    List<_LeaderboardEntry> noSales,
    List<_LeaderboardEntry> topThree,
  ) {
    final soldRowsCount = sold.isEmpty ? 1 : sold.length;
    if (index == 0) return _buildTopThree(topThree);
    if (index == 1) return const SizedBox(height: 14);
    if (index == 2) {
      return _buildSectionHeader('Sell Out', '${sold.length} promotor');
    }
    if (index == 3) return const SizedBox(height: 8);
    if (index == 4) return _buildRankingTableHeader();
    if (index < 5 + soldRowsCount) {
      if (sold.isEmpty) {
        return _buildEmptyCard(
          'Belum ada promotor yang mencatat penjualan hari ini.',
        );
      }
      return _buildRankingCard(sold[index - 5]);
    }

    final nextIndex = index - (5 + soldRowsCount);
    if (nextIndex == 0) return const SizedBox(height: 12);
    if (nextIndex == 1) return _buildNoSalesSectionHeader(noSales.length);
    if (nextIndex == 2) return const SizedBox(height: 8);
    if (nextIndex == 3) return _buildCollapsibleNoSales(noSales);
    if (nextIndex == 4) return const SizedBox(height: 16);
    if (_satorSummaries.isEmpty) {
      return _buildEmptyCard(
        'Belum ada data pencapaian Sator untuk tanggal ini.',
      );
    }
    return _buildSatorSummaryTable(_satorSummaries);
  }

  Widget _buildFeedTab() {
    if (_feed.isEmpty) {
      return RefreshIndicator(
        color: t.primaryAccent,
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [SizedBox(height: 24)],
        ),
      );
    }

    return RefreshIndicator(
      color: t.primaryAccent,
      onRefresh: _loadData,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _feed.length,
        itemBuilder: (context, index) => _buildFeedCard(_feed[index]),
      ),
    );
  }

  Widget _buildTopThree(List<_LeaderboardEntry> topThree) {
    return PromotorCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Top Promotor', ''),
          const SizedBox(height: 8),
          if (topThree.isEmpty)
            _buildEmptyCard('Belum ada bonus yang tercatat pada tanggal ini.')
          else
            SizedBox(
              height: 172,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(child: _buildPodium(topThree, 1)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildPodium(topThree, 0)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildPodium(topThree, 2)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPodium(List<_LeaderboardEntry> data, int index) {
    if (index >= data.length) {
      return const SizedBox.shrink();
    }

    final entry = data[index];
    final isChampion = index == 0;
    final displayRank = index + 1;
    final podiumHeight = switch (displayRank) {
      1 => 72.0,
      2 => 46.0,
      _ => 40.0,
    };
    final accent = switch (displayRank) {
      1 => t.primaryAccent,
      2 => t.textSecondary,
      _ => t.warning,
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isChampion) const SizedBox(height: 4),
        if (isChampion)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '👑',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontSize: 12),
            ),
          ),
        _buildAvatar(
          _displayName(entry.promotorId, entry.promotorName),
          radius: isChampion ? 15 : 13,
          accent: accent,
          highlighted: true,
        ),
        const SizedBox(height: 4),
        Text(
          _displayName(entry.promotorId, entry.promotorName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: t.textSecondary,
            fontWeight: FontWeight.w900,
            fontSize: isChampion ? 11 : 9.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 1),
        Text(
          _rupiahFormat.format(entry.totalBonus),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: accent,
            fontWeight: FontWeight.w900,
            fontSize: isChampion ? 11 : 9.5,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: podiumHeight,
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  accent.withValues(alpha: 0.2),
                  accent.withValues(alpha: 0.05),
                ],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border.all(color: accent.withValues(alpha: 0.3)),
            ),
            child: Center(
              child: Text(
                '$displayRank',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: accent.withValues(alpha: 0.24),
                  fontWeight: FontWeight.w900,
                  fontSize: isChampion ? 20 : 16,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRankingCard(_LeaderboardEntry entry) {
    final isMe = entry.promotorId == _currentUserId;
    final accentColor = entry.rank <= 3 ? t.primaryAccent : t.textMutedStrong;
    final soldDetails = entry.typeBreakdown;
    final typeText = soldDetails.isEmpty
        ? '-'
        : soldDetails.map((detail) => detail.label).join('\n');
    final achievementText = soldDetails.isEmpty
        ? '-'
        : soldDetails
              .map((detail) => _formatMoneyTight(detail.achievementTotal))
              .join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Column(
        children: [
          _buildRankingTableRow(
            rankText: '#${entry.rank}',
            rankColor: accentColor,
            nameText: _displayName(entry.promotorId, entry.promotorName),
            nameColor: isMe ? t.primaryAccent : t.textPrimary,
            typeText: typeText,
            targetText: _formatMoneyTight(entry.dailyTarget),
            achievementText: achievementText,
            achievementColor: t.primaryAccent,
          ),
          Container(height: 1, color: t.surface3),
        ],
      ),
    );
  }

  Widget _buildNoSalesCard(_LeaderboardEntry entry) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Column(
        children: [
          _buildRankingTableRow(
            rankText: '#${entry.rank}',
            rankColor: t.textMutedStrong,
            nameText: _displayName(entry.promotorId, entry.promotorName),
            nameColor: t.textPrimary,
            typeText: '-',
            targetText: _formatMoneyTight(entry.dailyTarget),
            achievementText: '-',
            achievementColor: t.warning,
          ),
          Container(height: 1, color: t.surface3),
        ],
      ),
    );
  }

  Widget _buildRankingTableHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final widths = _rankingColumnWidths(constraints.maxWidth);
              return Row(
                children: [
                  SizedBox(
                    width: widths.rank,
                    child: Text(
                      '#',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: t.textMutedStrong,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  SizedBox(width: widths.gap),
                  SizedBox(
                    width: widths.name,
                    child: Text(
                      'Nama',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: t.textMutedStrong,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  SizedBox(width: widths.gap),
                  SizedBox(
                    width: widths.type,
                    child: Text(
                      'Tipe',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: t.textMutedStrong,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  SizedBox(width: widths.gap),
                  SizedBox(
                    width: widths.target,
                    child: Text(
                      'Target',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: t.textMutedStrong,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  SizedBox(width: widths.gap),
                  SizedBox(
                    width: widths.achievement,
                    child: Text(
                      'Pencapaian',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: t.textMutedStrong,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Container(height: 1, color: t.surface3),
        ],
      ),
    );
  }

  Widget _buildCollapsibleNoSales(List<_LeaderboardEntry> noSales) {
    if (noSales.isEmpty) {
      return _buildEmptyCard(
        'Semua promotor sudah memiliki penjualan hari ini.',
      );
    }

    final visibleRows = _noSalesCollapsed
        ? const <_LeaderboardEntry>[]
        : noSales;
    if (_noSalesCollapsed) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildRankingTableHeader(),
          ),
          ...visibleRows.map(_buildNoSalesCard),
        ],
      ),
    );
  }

  Widget _buildNoSalesSectionHeader(int count) {
    return InkWell(
      onTap: () {
        setState(() {
          _noSalesCollapsed = !_noSalesCollapsed;
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text(
                    'No Sellout',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: t.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _noSalesCollapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 18,
                    color: t.textMutedStrong,
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: t.surface3),
              ),
              child: Text(
                '$count promotor',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: t.textMuted,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSatorSummaryTable(List<_SatorCompactSummary> rows) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          ...rows.map((row) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.satorName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '2 kategori',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: t.textMutedStrong,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 9,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _buildSatorMetricCard(
                              label: 'Sellout',
                              target: _formatMoneyTight(row.selloutTarget),
                              actual: _formatMoneyTight(row.selloutActual),
                              percent: row.selloutPct,
                              accent: t.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: _buildSatorMetricCard(
                              label: 'Produk Fokus',
                              target: _formatMoneyTight(row.focusTarget),
                              actual: row.focusActual.toStringAsFixed(
                                row.focusActual % 1 == 0 ? 0 : 1,
                              ),
                              percent: row.focusPct,
                              accent: t.primaryAccent,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (row != rows.last) Container(height: 1, color: t.surface3),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _buildSatorMetricCard({
    required String label,
    required String target,
    required String actual,
    required num percent,
    required Color accent,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w800,
                    fontSize: 9,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${percent.toStringAsFixed(percent % 1 == 0 ? 0 : 1)}%',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 9,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '$target / $actual',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  ({
    double rank,
    double name,
    double type,
    double target,
    double achievement,
    double gap,
  })
  _rankingColumnWidths(double maxWidth) {
    const rank = 34.0;
    const gap = 8.0;
    final remaining = (maxWidth - rank - (gap * 4)).clamp(0.0, double.infinity);
    final name = remaining * 0.24;
    final type = remaining * 0.32;
    final target = remaining * 0.16;
    final achievement = remaining * 0.28;
    return (
      rank: rank,
      name: name,
      type: type,
      target: target,
      achievement: achievement,
      gap: gap,
    );
  }

  Widget _buildRankingTableRow({
    required String rankText,
    required Color rankColor,
    required String nameText,
    required Color nameColor,
    required String typeText,
    required String targetText,
    required String achievementText,
    required Color achievementColor,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 7, 2, 7),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final widths = _rankingColumnWidths(constraints.maxWidth);
          final textStyle = Theme.of(context).textTheme.labelMedium;
          return Row(
            children: [
              SizedBox(
                width: widths.rank,
                child: Text(
                  rankText,
                  textAlign: TextAlign.center,
                  style: textStyle?.copyWith(
                    color: rankColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(width: widths.gap),
              SizedBox(
                width: widths.name,
                child: Text(
                  nameText,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle?.copyWith(
                    color: nameColor,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ),
              SizedBox(width: widths.gap),
              SizedBox(
                width: widths.type,
                child: Text(
                  typeText,
                  maxLines: 4,
                  softWrap: true,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle?.copyWith(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w700,
                    height: 1.15,
                    fontSize: 11,
                  ),
                ),
              ),
              SizedBox(width: widths.gap),
              SizedBox(
                width: widths.target,
                child: Text(
                  targetText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: textStyle?.copyWith(
                    color: t.textMutedStrong,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(width: widths.gap),
              SizedBox(
                width: widths.achievement,
                child: Text(
                  achievementText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: textStyle?.copyWith(
                    color: achievementColor,
                    fontWeight: FontWeight.w900,
                    height: 1.0,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildFeedCard(_FeedEntry entry) {
    final comments = _threadedComments(
      _commentsBySale[entry.saleId] ?? const <_FeedComment>[],
    );
    final latestComment = comments.isEmpty ? null : comments.last;
    final unreadCommentCount = _unreadCommentCount(entry.saleId, comments.length);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.surface3),
          boxShadow: [
            BoxShadow(
              color: t.shellBackground.withValues(alpha: 0.18),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 9, 9, 7),
              child: Row(
                children: [
                  _buildAvatar(
                    _displayName(entry.promotorId, entry.promotorName),
                    radius: 15,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      _displayName(entry.promotorId, entry.promotorName),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: t.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _timeAgo(entry.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: t.textMutedStrong,
                      fontWeight: FontWeight.w700,
                      fontSize: 9,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 0, 9, 7),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: t.surface3),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: t.surface3,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(
                        Icons.phone_android_rounded,
                        color: t.textMuted,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Produk terjual',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: t.textMutedStrong,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 9,
                                  letterSpacing: 0.2,
                                ),
                          ),
                          const SizedBox(height: 1),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.productName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleSmall
                                      ?.copyWith(
                                        color: t.textSecondary,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 10.5,
                                        height: 1.0,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: t.surface1,
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: t.surface3),
                                ),
                                child: ConstrainedBox(
                                  constraints: const BoxConstraints(
                                    minWidth: 34,
                                    maxWidth: 68,
                                  ),
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      entry.variantName
                                          .replaceAll('\n', ' ')
                                          .replaceAll(RegExp(r'\s+'), ' ')
                                          .trim(),
                                      maxLines: 1,
                                      softWrap: false,
                                      overflow: TextOverflow.fade,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: t.textMutedStrong,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 9,
                                            height: 1.0,
                                          ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 0, 9, 7),
              child: Align(
                alignment: Alignment.center,
                child: FractionallySizedBox(
                  widthFactor: 0.74,
                  child: entry.imageUrl.trim().isEmpty
                      ? _buildNoPhotoPlaceholder()
                      : InkWell(
                          onTap: () => _openFeedImage(entry),
                          borderRadius: BorderRadius.circular(12),
                          child: Stack(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: AspectRatio(
                                  aspectRatio: 4 / 5,
                                  child: Image.network(
                                    entry.imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            _buildNoPhotoPlaceholder(),
                                  ),
                                ),
                              ),
                              Positioned(
                                right: 7,
                                bottom: 7,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 7,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.52),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.open_in_full_rounded,
                                        size: 11,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 3),
                                      Text(
                                        'Lihat foto',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w800,
                                              fontSize: 9,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 0, 9, 7),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: t.surface3),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _buildFeedMeta(entry),
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: t.textMuted,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 9,
                                ),
                          ),
                          if (entry.notes.trim().isNotEmpty) ...[
                            const SizedBox(height: 3),
                            Text(
                              entry.notes.trim(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: t.textMuted,
                                    fontSize: 10,
                                    height: 1.15,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 7),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _rupiahFormat.format(entry.price),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: t.textSecondary,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '+${_rupiahFormat.format(entry.bonus)}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: t.primaryAccent,
                                fontWeight: FontWeight.w900,
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(9, 0, 9, 5),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final reactionType in const ['fire', 'clap', 'muscle'])
                      Padding(
                        padding: const EdgeInsets.only(right: 5),
                        child: _buildReactionChip(entry, reactionType),
                      ),
                    InkWell(
                      onTap: () => _openCommentsSheet(entry),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 5,
                        ),
                        decoration: BoxDecoration(
                          color: t.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: t.surface3),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (unreadCommentCount > 0) ...[
                              Container(
                                constraints: const BoxConstraints(
                                  minWidth: 16,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: t.danger,
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  '$unreadCommentCount',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.labelSmall
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 8.5,
                                      ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Icon(
                              Icons.chat_bubble_outline_rounded,
                              size: 12,
                              color: t.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              comments.isEmpty
                                  ? 'Tulis komentar'
                                  : 'Komentar ${comments.length}',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: t.textMuted,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 9,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (latestComment != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(9, 0, 9, 7),
                child: InkWell(
                  onTap: () => _openCommentsSheet(entry),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                    decoration: BoxDecoration(
                      color: t.surface2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: t.surface3),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          latestComment.userName,
                          style: Theme.of(context).textTheme.labelMedium
                              ?.copyWith(
                                color: t.primaryAccent,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          latestComment.commentText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: t.textSecondary, height: 1.2),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _buildFeedMeta(_FeedEntry entry) {
    final parts = <String>[
      entry.paymentMethod,
      if (entry.leasingProvider.trim().isNotEmpty) entry.leasingProvider.trim(),
      if (entry.customerType.trim().isNotEmpty) entry.customerType.trim(),
    ];
    return parts.join(' · ');
  }

  Widget _buildNoPhotoPlaceholder() {
    return Container(
      height: 126,
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, color: t.textMutedStrong),
            const SizedBox(height: 6),
            Text(
              'Foto bukti penjualan tidak tersedia',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: t.textMutedStrong,
                fontWeight: FontWeight.w700,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReactionChip(_FeedEntry entry, String reactionType) {
    final count = entry.reactionCounts[reactionType] ?? 0;
    final active = entry.userReactions.contains(reactionType);

    return InkWell(
      onTap: () => _toggleReaction(entry, reactionType),
      onLongPress: count > 0
          ? () => _openReactionSummary(entry, initialReactionType: reactionType)
          : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: active ? t.primaryAccentSoft : t.surface2,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? t.primaryAccentGlow : t.surface3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_reactionLabel(reactionType)),
            if (count > 0) ...[
              const SizedBox(width: 3),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openReactionSummary(
                  entry,
                  initialReactionType: reactionType,
                ),
                child: Text(
                  '$count',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: active ? t.primaryAccent : t.textMuted,
                    fontWeight: FontWeight.w900,
                    fontSize: 9,
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 2),
            ],
            if (active) ...[
              const SizedBox(width: 2),
              Icon(Icons.check_rounded, size: 10, color: t.primaryAccent),
            ],
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 10,
                  color: t.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  List<_FeedComment> _threadedComments(List<_FeedComment> comments) {
    if (comments.isEmpty) return const [];

    final byParent = <String?, List<_FeedComment>>{};
    for (final comment in comments) {
      byParent.putIfAbsent(comment.parentCommentId, () => []).add(comment);
    }

    final ordered = <_FeedComment>[];
    void appendTree(String? parentId, int depth) {
      final children = byParent[parentId] ?? const [];
      for (final child in children) {
        ordered.add(child.copyWith(threadDepth: depth));
        appendTree(child.commentId, depth + 1);
      }
    }

    appendTree(null, 0);
    return ordered;
  }

  Widget _buildCommentTile(_FeedComment comment) {
    return Padding(
      padding: EdgeInsets.only(
        left: comment.threadDepth > 0 ? 20 : 0,
        bottom: 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(comment.userName, radius: 12),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.surface3),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    comment.userName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: t.primaryAccent,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    comment.commentText,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: t.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _timeAgo(comment.createdAt),
                    style: Theme.of(
                      context,
                    ).textTheme.labelSmall?.copyWith(color: t.textMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return const SizedBox.shrink();
  }

  Widget _buildSectionHeader(String title, String badgeLabel) {
    return Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: t.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        if (badgeLabel.trim().isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: t.surface3),
            ),
            child: Text(
              badgeLabel,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: t.textMuted,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatar(
    String name, {
    required double radius,
    bool highlighted = false,
    Color? accent,
  }) {
    final avatarAccent = accent ?? t.primaryAccent;
    final bg = highlighted ? t.primaryAccentSoft : t.surface2;
    final border = highlighted ? avatarAccent : t.surface3;
    final fg = highlighted ? avatarAccent : t.textSecondary;
    final initial = _initials(name);

    return Container(
      width: radius * 2,
      height: radius * 2,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: border, width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          color: fg,
          fontWeight: FontWeight.w900,
          fontSize: radius * 0.72,
        ),
      ),
    );
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return '${parts.first.characters.first}${parts.last.characters.first}'
        .toUpperCase();
  }
}

class _LeaderboardEntry {
  const _LeaderboardEntry({
    required this.rank,
    required this.promotorId,
    required this.promotorName,
    required this.totalSales,
    required this.totalBonus,
    required this.dailyTarget,
    required this.hasSold,
    required this.primaryType,
    required this.extraTypeCount,
    required this.typeBreakdown,
  });

  factory _LeaderboardEntry.fromMap(Map<String, dynamic> map) {
    return _LeaderboardEntry(
      rank: _toInt(map['rank']),
      promotorId: '${map['promotor_id'] ?? ''}',
      promotorName: '${map['promotor_name'] ?? 'Promotor'}',
      totalSales: _toInt(map['total_sales']),
      totalBonus: _toNum(map['total_bonus']),
      dailyTarget: _toNum(map['daily_target']),
      hasSold: map['has_sold'] == true,
      primaryType: '${map['primary_type'] ?? ''}',
      extraTypeCount: _toInt(map['extra_type_count']),
      typeBreakdown: _toSoldTypeDetails(map['type_breakdown']),
    );
  }

  final int rank;
  final String promotorId;
  final String promotorName;
  final int totalSales;
  final num totalBonus;
  final num dailyTarget;
  final bool hasSold;
  final String primaryType;
  final int extraTypeCount;
  final List<_SoldTypeDetail> typeBreakdown;
}

class _FeedEntry {
  const _FeedEntry({
    required this.saleId,
    required this.promotorId,
    required this.promotorName,
    required this.storeName,
    required this.productName,
    required this.variantName,
    required this.price,
    required this.bonus,
    required this.paymentMethod,
    required this.leasingProvider,
    required this.customerType,
    required this.notes,
    required this.imageUrl,
    required this.reactionCounts,
    required this.userReactions,
    required this.commentCount,
    required this.createdAt,
  });

  factory _FeedEntry.fromMap(Map<String, dynamic> map) {
    return _FeedEntry(
      saleId: '${map['sale_id'] ?? map['feed_id'] ?? ''}',
      promotorId: '${map['promotor_id'] ?? ''}',
      promotorName: '${map['promotor_name'] ?? 'Promotor'}',
      storeName: '${map['store_name'] ?? '-'}',
      productName: '${map['product_name'] ?? 'Produk'}',
      variantName: '${map['variant_name'] ?? '-'}',
      price: _toNum(map['price']),
      bonus: _toNum(map['bonus']),
      paymentMethod: '${map['payment_method'] ?? '-'}',
      leasingProvider: '${map['leasing_provider'] ?? ''}',
      customerType: '${map['customer_type'] ?? ''}',
      notes: '${map['notes'] ?? ''}',
      imageUrl: '${map['image_url'] ?? ''}',
      reactionCounts: _toReactionCounts(map['reaction_counts']),
      userReactions: _toReactionSet(map['user_reactions']),
      commentCount: _toInt(map['comment_count']),
      createdAt: _toDateTime(map['created_at']),
    );
  }

  final String saleId;
  final String promotorId;
  final String promotorName;
  final String storeName;
  final String productName;
  final String variantName;
  final num price;
  final num bonus;
  final String paymentMethod;
  final String leasingProvider;
  final String customerType;
  final String notes;
  final String imageUrl;
  final Map<String, int> reactionCounts;
  final Set<String> userReactions;
  final int commentCount;
  final DateTime createdAt;

  _FeedEntry copyWith({
    Map<String, int>? reactionCounts,
    Set<String>? userReactions,
    int? commentCount,
  }) {
    return _FeedEntry(
      saleId: saleId,
      promotorId: promotorId,
      promotorName: promotorName,
      storeName: storeName,
      productName: productName,
      variantName: variantName,
      price: price,
      bonus: bonus,
      paymentMethod: paymentMethod,
      leasingProvider: leasingProvider,
      customerType: customerType,
      notes: notes,
      imageUrl: imageUrl,
      reactionCounts: reactionCounts ?? this.reactionCounts,
      userReactions: userReactions ?? this.userReactions,
      commentCount: commentCount ?? this.commentCount,
      createdAt: createdAt,
    );
  }
}

class _FeedComment {
  const _FeedComment({
    required this.commentId,
    required this.userId,
    required this.userName,
    required this.commentText,
    required this.createdAt,
    this.parentCommentId,
    this.mentionedUserIds = const [],
    this.isSystemPersona = false,
    this.threadDepth = 0,
  });

  factory _FeedComment.fromMap(Map<String, dynamic> map) {
    return _FeedComment(
      commentId: '${map['comment_id'] ?? map['id'] ?? ''}',
      userId: '${map['user_id'] ?? ''}',
      userName: '${map['user_name'] ?? 'User'}',
      commentText: '${map['comment_text'] ?? ''}',
      createdAt: _toDateTime(map['created_at']),
      parentCommentId: map['parent_comment_id']?.toString(),
      mentionedUserIds: _toStringList(map['mentioned_user_ids']),
      isSystemPersona: map['is_system_persona'] == true,
    );
  }

  final String commentId;
  final String userId;
  final String userName;
  final String commentText;
  final DateTime createdAt;
  final String? parentCommentId;
  final List<String> mentionedUserIds;
  final bool isSystemPersona;
  final int threadDepth;

  _FeedComment copyWith({int? threadDepth}) {
    return _FeedComment(
      commentId: commentId,
      userId: userId,
      userName: userName,
      commentText: commentText,
      createdAt: createdAt,
      parentCommentId: parentCommentId,
      mentionedUserIds: mentionedUserIds,
      isSystemPersona: isSystemPersona,
      threadDepth: threadDepth ?? this.threadDepth,
    );
  }
}

class _ReactionDetail {
  const _ReactionDetail({
    required this.reactionType,
    required this.userName,
    required this.createdAt,
  });

  factory _ReactionDetail.fromMap(Map<String, dynamic> map) {
    return _ReactionDetail(
      reactionType: '${map['reaction_type'] ?? ''}',
      userName: '${map['user_name'] ?? 'User'}',
      createdAt: _toDateTime(map['created_at']),
    );
  }

  final String reactionType;
  final String userName;
  final DateTime createdAt;
}

class _SatorCompactSummary {
  const _SatorCompactSummary({
    required this.satorId,
    required this.satorName,
    required this.selloutTarget,
    required this.selloutActual,
    required this.selloutPct,
    required this.focusTarget,
    required this.focusActual,
    required this.focusPct,
  });

  factory _SatorCompactSummary.fromMap(Map<String, dynamic> map) {
    return _SatorCompactSummary(
      satorId: '${map['sator_id'] ?? ''}',
      satorName: '${map['sator_name'] ?? 'Tanpa SATOR'}',
      selloutTarget: _toNum(map['sellout_target']),
      selloutActual: _toNum(map['sellout_actual']),
      selloutPct: _toNum(map['sellout_pct']),
      focusTarget: _toNum(map['focus_target']),
      focusActual: _toNum(map['focus_actual']),
      focusPct: _toNum(map['focus_pct']),
    );
  }

  final String satorId;
  final String satorName;
  final num selloutTarget;
  final num selloutActual;
  final num selloutPct;
  final num focusTarget;
  final num focusActual;
  final num focusPct;
}

class _SoldTypeDetail {
  const _SoldTypeDetail({
    required this.label,
    required this.unitCount,
    required this.achievementTotal,
  });

  factory _SoldTypeDetail.fromMap(Map<String, dynamic> map) {
    return _SoldTypeDetail(
      label: '${map['type_label'] ?? map['label'] ?? ''}',
      unitCount: _toInt(map['unit_count'] ?? map['count']),
      achievementTotal: _toNum(
        map['srp_total'] ??
            map['omzet_total'] ??
            map['price_total'] ??
            map['bonus_total'] ??
            map['bonus'],
      ),
    );
  }

  final String label;
  final int unitCount;
  final num achievementTotal;
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse('$value') ?? 0;
}

num _toNum(dynamic value) {
  if (value is num) return value;
  return num.tryParse('$value') ?? 0;
}

DateTime _toDateTime(dynamic value) {
  if (value is DateTime) return value;
  return DateTime.tryParse('$value') ?? DateTime.now();
}

Map<String, int> _toReactionCounts(dynamic value) {
  if (value is Map) {
    return value.map(
      (key, dynamic rawValue) => MapEntry('$key', _toInt(rawValue)),
    );
  }
  if (value is String && value.trim().isNotEmpty) {
    final decoded = jsonDecode(value);
    if (decoded is Map) {
      return decoded.map(
        (key, dynamic rawValue) => MapEntry('$key', _toInt(rawValue)),
      );
    }
  }
  return const {};
}

Set<String> _toReactionSet(dynamic value) {
  if (value is List) {
    return value.map((item) => '$item').toSet();
  }
  if (value is String && value.trim().isNotEmpty) {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded.map((item) => '$item').toSet();
    }
  }
  return <String>{};
}

List<String> _toStringList(dynamic value) {
  if (value is List) {
    return value
        .map((item) => '$item')
        .where((item) => item.isNotEmpty)
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded
          .map((item) => '$item')
          .where((item) => item.isNotEmpty)
          .toList();
    }
  }
  return const <String>[];
}

List<_SoldTypeDetail> _toSoldTypeDetails(dynamic value) {
  if (value is List) {
    return value
        .whereType<Map>()
        .map((item) => _SoldTypeDetail.fromMap(Map<String, dynamic>.from(item)))
        .toList();
  }
  if (value is String && value.trim().isNotEmpty) {
    final decoded = jsonDecode(value);
    if (decoded is List) {
      return decoded
          .whereType<Map>()
          .map(
            (item) => _SoldTypeDetail.fromMap(Map<String, dynamic>.from(item)),
          )
          .toList();
    }
  }
  return const [];
}
