import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/components/field_segmented_control.dart';
import '../../../../ui/promotor/promotor.dart';
import '../../../../ui/ui.dart';

class LeaderboardPage extends StatefulWidget {
  const LeaderboardPage({
    super.key,
    this.title = 'Leaderboard',
    this.liveSubtitle = 'Live semua area · bonus harian promotor',
    this.scopeLabel = 'Semua Area',
  });

  final String title;
  final String liveSubtitle;
  final String scopeLabel;

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
  String _currentUserName = 'Kamu';

  List<_LeaderboardEntry> _ranking = const [];
  List<_FeedEntry> _feed = const [];
  List<_SatorCompactSummary> _satorSummaries = const [];
  Map<String, String> _promotorAreas = const {};
  Map<String, String> _promotorNicknames = const {};
  bool _noSalesCollapsed = true;
  Map<String, List<_FeedComment>> _commentsBySale = const {};
  Set<String> _loadingCommentSaleIds = <String>{};
  Set<String> _submittingCommentSaleIds = <String>{};
  Set<String> _expandedCommentSaleIds = <String>{};

  FieldThemeTokens get t => context.fieldTokens;

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
      final profileResult = await _supabase
          .from('users')
          .select('full_name, nickname')
          .eq('id', userId)
          .maybeSingle();
      final rankingResult = await _supabase.rpc(
        'get_daily_ranking',
        params: {'p_date': dateValue, 'p_area_id': null, 'p_limit': 300},
      );
      final feedResult = await _supabase.rpc(
        'get_live_feed',
        params: {
          'p_user_id': userId,
          'p_date': dateValue,
          'p_limit': 200,
          'p_offset': 0,
        },
      );
      final leaderboardFeedResult = await _supabase.rpc(
        'get_leaderboard_feed',
        params: {'p_user_id': userId, 'p_date': dateValue},
      );
      final satorSummaryResult = await _supabase.rpc(
        'get_sator_compact_summary',
        params: {'p_date': dateValue},
      );

      final profile = Map<String, dynamic>.from(
        (profileResult as Map?) ?? const <String, dynamic>{},
      );
      final rankingRows = _asMapList(rankingResult);
      final feedRows = _asMapList(feedResult);
      final leaderboardFeed = _asMapList(leaderboardFeedResult);
      final satorSummaryRows = _asMapList(satorSummaryResult);
      final promotorIds = <String>{
        for (final row in rankingRows) '${row['promotor_id'] ?? ''}'.trim(),
        for (final row in feedRows) '${row['promotor_id'] ?? ''}'.trim(),
      }..removeWhere((id) => id.isEmpty);

      final nicknameMap = <String, String>{};
      if (promotorIds.isNotEmpty) {
        final userRows = await _supabase
            .from('users')
            .select('id, full_name, nickname')
            .inFilter('id', promotorIds.toList());
        for (final row in _asMapList(userRows)) {
          final promotorId = '${row['id'] ?? ''}'.trim();
          if (promotorId.isEmpty) continue;
          final nickname = '${row['nickname'] ?? ''}'.trim();
          final fullName = '${row['full_name'] ?? ''}'.trim();
          nicknameMap[promotorId] = nickname.isNotEmpty ? nickname : fullName;
        }
      }

      final areaMap = <String, String>{};
      for (final item in leaderboardFeed) {
        final feedType = '${item['feed_type'] ?? ''}';
        final areaName = '${item['area_name'] ?? ''}'.trim();
        if (areaName.isEmpty) continue;

        if (feedType == 'sales_list') {
          for (final promotor in _asMapList(item['sales_list'])) {
            final promotorId = '${promotor['promotor_id'] ?? ''}'.trim();
            if (promotorId.isNotEmpty) {
              areaMap[promotorId] = areaName;
            }
          }
        }

        if (feedType == 'no_sales') {
          for (final promotor in _asMapList(item['no_sales_list'])) {
            final promotorId = '${promotor['promotor_id'] ?? ''}'.trim();
            if (promotorId.isNotEmpty) {
              areaMap[promotorId] = areaName;
            }
          }
        }
      }

      if (!mounted) return;
      setState(() {
        _currentUserId = userId;
        _currentUserName = '${profile['nickname'] ?? ''}'.trim().isNotEmpty
            ? '${profile['nickname']}'
            : '${profile['full_name'] ?? 'Kamu'}';
        _ranking = rankingRows.map(_LeaderboardEntry.fromMap).toList();
        _feed = feedRows.map(_FeedEntry.fromMap).toList();
        _satorSummaries = satorSummaryRows
            .map(_SatorCompactSummary.fromMap)
            .toList();
        _promotorAreas = areaMap;
        _promotorNicknames = nicknameMap;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _ranking = const [];
        _feed = const [];
        _satorSummaries = const [];
        _promotorAreas = const {};
        _promotorNicknames = const {};
        _isLoading = false;
      });
    }
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

  String _formatBonusCompact(num value) {
    if (value >= 1000000) {
      final jt = value / 1000000;
      final digits = jt >= 10 ? 0 : 1;
      return 'Rp ${jt.toStringAsFixed(digits)}jt';
    }
    if (value >= 1000) {
      final rb = value / 1000;
      final digits = rb >= 100 ? 0 : 1;
      return 'Rp ${rb.toStringAsFixed(digits)}rb';
    }
    return _rupiahFormat.format(value);
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

  String _shortSoldType(_FeedEntry? sale) {
    if (sale == null) return '-';
    final product = sale.productName.trim();
    final variant = sale.variantName.trim();
    final productParts = product
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final variantParts = variant
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    final shortProduct = productParts.isEmpty
        ? '-'
        : (productParts.length >= 2
              ? '${productParts[productParts.length - 2]} ${productParts.last}'
              : productParts.last);
    final shortVariant = variantParts.isEmpty
        ? ''
        : variantParts.take(2).join(' ');
    return shortVariant.isEmpty ? shortProduct : '$shortProduct $shortVariant';
  }

  String _displayName(String promotorId, String fullName) {
    final nickname = (_promotorNicknames[promotorId] ?? '').trim();
    if (nickname.isNotEmpty) return nickname;
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'Promotor';
    return trimmed;
  }

  List<_FeedEntry> _salesForPromotor(String promotorId) {
    return _feed.where((item) => item.promotorId == promotorId).toList();
  }

  String _soldSummary(String promotorId) {
    final sales = _salesForPromotor(promotorId);
    if (sales.isEmpty) return '-';
    final labels = <String>[];
    for (final sale in sales) {
      final short = _shortSoldType(sale);
      if (short == '-' || labels.contains(short)) continue;
      labels.add(short);
    }
    if (labels.isEmpty) return '${sales.length} item';
    if (labels.length == 1) return labels.first;
    if (labels.length == 2) return '${labels[0]}, ${labels[1]}';
    return '${labels[0]}, ${labels[1]} +${labels.length - 2}';
  }

  String _timeAgo(DateTime dateTime) {
    final diff = DateTime.now().difference(dateTime);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inMinutes < 60) return '${diff.inMinutes} mnt lalu';
    if (diff.inHours < 24) return '${diff.inHours} jam lalu';
    return '${diff.inDays} hari lalu';
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
                              'Pemberi Reaksi',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    color: t.textPrimary,
                                    fontWeight: FontWeight.w900,
                                  ),
                            ),
                            const Spacer(),
                            Text(
                              '${data.length} reaksi',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: t.textMuted),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (snapshot.connectionState == ConnectionState.waiting)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: CircularProgressIndicator(
                            color: t.primaryAccent,
                          ),
                        )
                      else if (data.isEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                          child: Text(
                            'Belum ada user yang memberi reaksi di penjualan ini.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: t.textMuted),
                            textAlign: TextAlign.center,
                          ),
                        )
                      else
                        Flexible(
                          child: ListView(
                            shrinkWrap: true,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            children: orderedTypes.map((reactionType) {
                              final users = grouped[reactionType] ?? const [];
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: t.surface2,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: t.surface3),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${_reactionLabel(reactionType)} ${users.length} orang',
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              color: t.primaryAccent,
                                              fontWeight: FontWeight.w900,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      ...users.map((user) {
                                        return Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: Row(
                                            children: [
                                              _buildAvatar(
                                                user.userName,
                                                radius: 12,
                                              ),
                                              const SizedBox(width: 8),
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
    if (!forceRefresh &&
        (_commentsBySale.containsKey(saleId) ||
            _loadingCommentSaleIds.contains(saleId))) {
      return;
    }

    setState(() {
      _loadingCommentSaleIds = {..._loadingCommentSaleIds, saleId};
    });

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
            .select('comment_text, created_at, users!inner(full_name)')
            .eq('sale_id', saleId)
            .isFilter('deleted_at', null)
            .order('created_at');
        final comments = List<Map<String, dynamic>>.from(rows).map((row) {
          return _FeedComment(
            userName: '${row['users']?['full_name'] ?? 'User'}',
            commentText: '${row['comment_text'] ?? ''}',
            createdAt: _toDateTime(row['created_at']),
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
    } finally {
      if (mounted) {
        setState(() {
          final next = {..._loadingCommentSaleIds};
          next.remove(saleId);
          _loadingCommentSaleIds = next;
        });
      }
    }
  }

  Future<void> _openCommentsSheet(_FeedEntry entry) async {
    await _ensureCommentsLoaded(
      entry.saleId,
      forceRefresh:
          entry.commentCount > 0 &&
          (_commentsBySale[entry.saleId]?.isEmpty ?? true),
    );
    if (!mounted) return;

    final controller = TextEditingController();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, sheetSetState) {
            final comments = _commentsBySale[entry.saleId] ?? const [];
            final isSubmitting = _submittingCommentSaleIds.contains(
              entry.saleId,
            );

            Future<void> submitComment() async {
              final text = controller.text.trim();
              if (text.isEmpty || _currentUserId == null) return;

              sheetSetState(() {});
              setState(() {
                _submittingCommentSaleIds = {
                  ..._submittingCommentSaleIds,
                  entry.saleId,
                };
              });

              try {
                await _supabase.rpc(
                  'add_comment',
                  params: {
                    'p_sale_id': entry.saleId,
                    'p_user_id': _currentUserId,
                    'p_comment_text': text,
                  },
                );
                controller.clear();
                await _forceReloadComments(entry.saleId);

                if (!mounted) return;
                setState(() {
                  _feed = _feed.map((item) {
                    if (item.saleId != entry.saleId) return item;
                    return item.copyWith(commentCount: item.commentCount + 1);
                  }).toList();
                });
                sheetSetState(() {});
              } catch (_) {
              } finally {
                if (mounted) {
                  setState(() {
                    final next = {..._submittingCommentSaleIds};
                    next.remove(entry.saleId);
                    _submittingCommentSaleIds = next;
                  });
                }
              }
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                top: 12,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
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
                              '${comments.length} balasan',
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
                                  'Belum ada komentar untuk penjualan ini.',
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
                                  12,
                                ),
                                itemBuilder: (context, index) {
                                  final comment = comments[index];
                                  return _buildCommentBubble(comment);
                                },
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 10),
                                itemCount: comments.length,
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                        child: Row(
                          children: [
                            _buildAvatar(
                              _currentUserName,
                              radius: 18,
                              highlighted: true,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: TextField(
                                controller: controller,
                                minLines: 1,
                                maxLines: 3,
                                style: TextStyle(color: t.textPrimary),
                                decoration: InputDecoration(
                                  hintText: 'Tulis komentar...',
                                  hintStyle: TextStyle(color: t.textMuted),
                                  filled: true,
                                  fillColor: t.surface2,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 12,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    borderSide: BorderSide(color: t.surface3),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    borderSide: BorderSide(color: t.surface3),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(999),
                                    borderSide: BorderSide(
                                      color: t.primaryAccent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton.filled(
                              onPressed: isSubmitting ? null : submitComment,
                              style: IconButton.styleFrom(
                                backgroundColor: t.primaryAccent,
                                foregroundColor: t.textOnAccent,
                              ),
                              icon: isSubmitting
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: t.textOnAccent,
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
  }

  Future<void> _forceReloadComments(String saleId) async {
    setState(() {
      _commentsBySale = Map<String, List<_FeedComment>>.from(_commentsBySale)
        ..remove(saleId);
    });
    await _ensureCommentsLoaded(saleId);
  }

  Future<void> _toggleCommentsInline(_FeedEntry entry) async {
    final expanded = _expandedCommentSaleIds.contains(entry.saleId);
    if (expanded) {
      setState(() {
        final next = {..._expandedCommentSaleIds};
        next.remove(entry.saleId);
        _expandedCommentSaleIds = next;
      });
      return;
    }

    await _ensureCommentsLoaded(
      entry.saleId,
      forceRefresh:
          entry.commentCount > 0 &&
          (_commentsBySale[entry.saleId]?.isEmpty ?? true),
    );
    if (!mounted) return;
    setState(() {
      _expandedCommentSaleIds = {..._expandedCommentSaleIds, entry.saleId};
    });
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
    return Row(
      children: [
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Leaderboard',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: t.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.40,
          ),
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
          children: const [
            SizedBox(height: 120),
            AppEmptyState(
              title: 'Belum ada data ranking',
              message:
                  'Data penjualan harian belum tersedia untuk tanggal ini.',
              icon: Icons.leaderboard_outlined,
            ),
          ],
        ),
      );
    }

    final sold = _ranking.where((entry) => entry.hasSold).toList();
    final noSales = _ranking.where((entry) => !entry.hasSold).toList();
    final topThree = sold.take(3).toList();

    return RefreshIndicator(
      color: t.primaryAccent,
      onRefresh: _loadData,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _buildTopThree(topThree),
          const SizedBox(height: 14),
          _buildSectionHeader(
            'Sell Out',
            '${sold.length} promotor',
          ),
          const SizedBox(height: 8),
          _buildRankingTableHeader(),
          if (sold.isEmpty)
            _buildEmptyCard(
              'Belum ada promotor yang mencatat penjualan hari ini.',
            )
          else
            ...sold.map(_buildRankingCard),
          const SizedBox(height: 12),
          _buildSectionHeader(
            'No Sellout',
            '${noSales.length} promotor',
          ),
          const SizedBox(height: 8),
          _buildCollapsibleNoSales(noSales),
          const SizedBox(height: 16),
          _buildSectionHeader(
            'Pencapaian Sator',
            '${_satorSummaries.length} sator',
          ),
          const SizedBox(height: 8),
          if (_satorSummaries.isEmpty)
            _buildEmptyCard('Belum ada data pencapaian Sator untuk tanggal ini.')
          else
            _buildSatorSummaryTable(_satorSummaries),
        ],
      ),
    );
  }

  Widget _buildFeedTab() {
    if (_feed.isEmpty) {
      return RefreshIndicator(
        color: t.primaryAccent,
        onRefresh: _loadData,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 120),
            AppEmptyState(
              title: 'Live feed kosong',
              message: 'Belum ada penjualan yang masuk pada tanggal ini.',
              icon: Icons.dynamic_feed_outlined,
            ),
          ],
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
              height: 70,
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
      return Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 68,
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            border: Border.all(color: t.surface3),
          ),
        ),
      );
    }

    final entry = data[index];
    final isChampion = index == 0;
    final displayRank = index + 1;
    final podiumHeight = switch (displayRank) {
      1 => 24.0,
      2 => 16.0,
      _ => 12.0,
    };
    final accent = switch (displayRank) {
      1 => t.primaryAccent,
      2 => t.textSecondary,
      _ => t.warning,
    };

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (isChampion)
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Text(
              '👑',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontSize: 7),
            ),
          ),
        _buildAvatar(
          _displayName(entry.promotorId, entry.promotorName),
          radius: isChampion ? 8 : 7,
          accent: accent,
          highlighted: true,
        ),
        const SizedBox(height: 1),
        Text(
          _displayName(entry.promotorId, entry.promotorName),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: t.textSecondary,
            fontWeight: FontWeight.w800,
            fontSize: 6,
          ),
          textAlign: TextAlign.center,
        ),
        Text(
          _formatBonusCompact(entry.totalBonus),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: accent,
            fontWeight: FontWeight.w900,
            fontSize: 6,
          ),
        ),
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
                  fontSize: 10,
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
    final sales = _salesForPromotor(entry.promotorId);
    final soldType = _soldSummary(entry.promotorId);

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Column(
        children: [
          _buildRankingTableRow(
            rankText: '#${entry.rank}',
            rankColor: accentColor,
            nameText: isMe
                ? '${_displayName(entry.promotorId, entry.promotorName)} · kamu'
                : _displayName(entry.promotorId, entry.promotorName),
            nameColor: isMe ? t.primaryAccent : t.textPrimary,
            typeText: soldType,
            targetText: _formatMoneyTight(entry.dailyTarget),
            achievementText: sales.isEmpty
                ? '-'
                : '${entry.totalSales}u • ${_formatMoneyTight(entry.totalBonus)}',
            achievementColor: t.primaryAccent,
          ),
          Container(height: 1, color: t.surface3),
        ],
      ),
    );
  }

  Widget _buildNoSalesCard(_LeaderboardEntry entry) {
    final isMe = entry.promotorId == _currentUserId;

    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Column(
        children: [
          _buildRankingTableRow(
            rankText: '#${entry.rank}',
            rankColor: t.textMutedStrong,
            nameText: isMe
                ? '${_displayName(entry.promotorId, entry.promotorName)} · kamu'
                : _displayName(entry.promotorId, entry.promotorName),
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
      return _buildEmptyCard('Semua promotor sudah memiliki penjualan hari ini.');
    }

    final visibleRows = _noSalesCollapsed ? noSales.take(5).toList() : noSales;
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _noSalesCollapsed = !_noSalesCollapsed;
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: t.surface2,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                border: Border(bottom: BorderSide(color: t.surface3)),
              ),
              child: Row(
                children: [
                  Text(
                    _noSalesCollapsed
                        ? 'Menampilkan 5 teratas'
                        : 'Menampilkan semua',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: t.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    _noSalesCollapsed
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    color: t.textMutedStrong,
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _buildRankingTableHeader(),
          ),
          ...visibleRows.map(_buildNoSalesCard),
        ],
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
    final remaining = (maxWidth - rank - (gap * 4)).clamp(
      180.0,
      double.infinity,
    );
    final name = remaining * 0.26;
    final type = remaining * 0.28;
    final target = remaining * 0.18;
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle?.copyWith(
                    color: nameColor,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(width: widths.gap),
              SizedBox(
                width: widths.type,
                child: Text(
                  typeText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle?.copyWith(
                    color: t.textSecondary,
                    fontWeight: FontWeight.w700,
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
    final area = _promotorAreas[entry.promotorId] ?? 'Tanpa area';
    final comments = _commentsBySale[entry.saleId] ?? const <_FeedComment>[];
    final commentsExpanded = _expandedCommentSaleIds.contains(entry.saleId);
    final isLoadingComments = _loadingCommentSaleIds.contains(entry.saleId);
    final visibleComments = commentsExpanded
        ? comments
        : comments.take(2).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        decoration: BoxDecoration(
          color: t.surface1,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: t.surface3),
          boxShadow: [
            BoxShadow(
              color: t.shellBackground.withValues(alpha: 0.18),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
              child: Row(
                children: [
                  _buildAvatar(
                    _displayName(entry.promotorId, entry.promotorName),
                    radius: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _displayName(entry.promotorId, entry.promotorName),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: t.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${entry.storeName} · $area',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: t.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    _timeAgo(entry.createdAt),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: t.textMutedStrong,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: t.surface3),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: t.surface3,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.phone_android_rounded,
                        color: t.textMuted,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Produk terjual',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: t.textMutedStrong,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0.6,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${entry.productName} · ${entry.variantName}',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  color: t.textSecondary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: entry.imageUrl.trim().isEmpty
                  ? _buildNoPhotoPlaceholder()
                  : InkWell(
                      onTap: () => _openFeedImage(entry),
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: AspectRatio(
                              aspectRatio: 4 / 5,
                              child: Image.network(
                                entry.imageUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    _buildNoPhotoPlaceholder(),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 10,
                            bottom: 10,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
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
                                    size: 14,
                                    color: Colors.white,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Lihat foto',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
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
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: BorderRadius.circular(16),
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
                                ),
                          ),
                          if (entry.notes.trim().isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              entry.notes.trim(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: t.textMuted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _rupiahFormat.format(entry.price),
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: t.textSecondary,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '+${_rupiahFormat.format(entry.bonus)}',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: t.primaryAccent,
                                fontWeight: FontWeight.w900,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final reactionType in const ['fire', 'clap', 'muscle'])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _buildReactionChip(entry, reactionType),
                      ),
                    InkWell(
                      onTap: () => _toggleCommentsInline(entry),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: commentsExpanded
                              ? t.primaryAccentSoft
                              : t.surface2,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: commentsExpanded
                                ? t.primaryAccentGlow
                                : t.surface3,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              commentsExpanded
                                  ? Icons.expand_less_rounded
                                  : Icons.chat_bubble_outline_rounded,
                              size: 14,
                              color: commentsExpanded
                                  ? t.primaryAccent
                                  : t.textMuted,
                            ),
                            if (entry.commentCount > 0) ...[
                              const SizedBox(width: 6),
                              Text(
                                '${entry.commentCount}',
                                style: Theme.of(context).textTheme.labelSmall
                                    ?.copyWith(
                                      color: commentsExpanded
                                          ? t.primaryAccent
                                          : t.textMuted,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (entry.commentCount > 0 && commentsExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Komentar',
                            style: Theme.of(context).textTheme.labelMedium
                                ?.copyWith(
                                  color: t.textSecondary,
                                  fontWeight: FontWeight.w900,
                                ),
                          ),
                          const Spacer(),
                          if (comments.length > 2)
                            IconButton(
                              onPressed: () => _toggleCommentsInline(entry),
                              visualDensity: VisualDensity.compact,
                              icon: Icon(
                                commentsExpanded
                                    ? Icons.unfold_less_rounded
                                    : Icons.unfold_more_rounded,
                                size: 18,
                                color: t.primaryAccent,
                              ),
                            ),
                        ],
                      ),
                      if (isLoadingComments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: t.primaryAccent,
                            ),
                          ),
                        )
                      else if (visibleComments.isEmpty)
                        Text(
                          'Belum ada komentar yang dimuat.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: t.textMuted),
                        )
                      else
                        Column(
                          children: visibleComments
                              .map(_buildCommentBubble)
                              .toList(),
                        ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: InkWell(
                onTap: () => _openCommentsSheet(entry),
                borderRadius: BorderRadius.circular(999),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Row(
                    children: [
                      _buildAvatar(
                        _currentUserName,
                        radius: 14,
                        highlighted: true,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Tulis komentar...',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(color: t.textMuted),
                        ),
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
      height: 160,
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, color: t.textMutedStrong),
            const SizedBox(height: 8),
            Text(
              'Foto bukti penjualan tidak tersedia',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: t.textMutedStrong,
                fontWeight: FontWeight.w700,
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
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
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
              const SizedBox(width: 6),
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
                  ),
                ),
              ),
            ] else ...[
              const SizedBox(width: 2),
            ],
            if (active) ...[
              const SizedBox(width: 4),
              Icon(Icons.check_rounded, size: 12, color: t.primaryAccent),
            ],
            if (count > 0)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  Icons.expand_more_rounded,
                  size: 12,
                  color: t.textMuted,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommentBubble(_FeedComment comment) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        message,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: t.textMuted),
      ),
    );
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
    required this.storeName,
    required this.totalSales,
    required this.totalBonus,
    required this.dailyTarget,
    required this.hasSold,
  });

  factory _LeaderboardEntry.fromMap(Map<String, dynamic> map) {
    return _LeaderboardEntry(
      rank: _toInt(map['rank']),
      promotorId: '${map['promotor_id'] ?? ''}',
      promotorName: '${map['promotor_name'] ?? 'Promotor'}',
      storeName: '${map['store_name'] ?? '-'}',
      totalSales: _toInt(map['total_sales']),
      totalBonus: _toNum(map['total_bonus']),
      dailyTarget: _toNum(map['daily_target']),
      hasSold: map['has_sold'] == true,
    );
  }

  final int rank;
  final String promotorId;
  final String promotorName;
  final String storeName;
  final int totalSales;
  final num totalBonus;
  final num dailyTarget;
  final bool hasSold;
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
    required this.userName,
    required this.commentText,
    required this.createdAt,
  });

  factory _FeedComment.fromMap(Map<String, dynamic> map) {
    return _FeedComment(
      userName: '${map['user_name'] ?? 'User'}',
      commentText: '${map['comment_text'] ?? ''}',
      createdAt: _toDateTime(map['created_at']),
    );
  }

  final String userName;
  final String commentText;
  final DateTime createdAt;
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
