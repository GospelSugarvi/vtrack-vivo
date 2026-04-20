import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../ui/promotor/promotor.dart';

enum VisitingQuickSearchScope { sator, spv }

class VisitingQuickSearchPage extends StatefulWidget {
  const VisitingQuickSearchPage({
    super.key,
    required this.scope,
  });

  final VisitingQuickSearchScope scope;

  @override
  State<VisitingQuickSearchPage> createState() => _VisitingQuickSearchPageState();
}

class _VisitingQuickSearchPageState extends State<VisitingQuickSearchPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  List<_StoreQuickHit> _stores = const <_StoreQuickHit>[];
  List<_PromotorQuickHit> _promotors = const <_PromotorQuickHit>[];
  String _query = '';

  FieldThemeTokens get t => context.fieldTokens;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final currentUserId = _supabase.auth.currentUser?.id;
      if (currentUserId == null) {
        throw Exception('Sesi login tidak ditemukan');
      }

      final storeHits = widget.scope == VisitingQuickSearchScope.sator
          ? await _loadSatorStores(currentUserId)
          : await _loadSpvStores();
      final promotorHits = widget.scope == VisitingQuickSearchScope.sator
          ? await _loadSatorPromotors(currentUserId)
          : await _loadSpvPromotors(currentUserId);

      if (!mounted) return;
      setState(() {
        _stores = storeHits;
        _promotors = promotorHits;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _stores = const <_StoreQuickHit>[];
        _promotors = const <_PromotorQuickHit>[];
        _isLoading = false;
      });
    }
  }

  Future<List<_StoreQuickHit>> _loadSatorStores(String satorId) async {
    final response = await _supabase.rpc(
      'get_sator_visiting_stores',
      params: <String, dynamic>{'p_sator_id': satorId},
    );
    final rows = (response as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    return rows
        .map(
          (row) => _StoreQuickHit(
            storeId: '${row['store_id'] ?? ''}',
            storeName: '${row['store_name'] ?? '-'}',
            subtitle: '${row['address'] ?? ''}'.trim(),
          ),
        )
        .where((row) => row.storeId.isNotEmpty)
        .toList();
  }

  Future<List<_PromotorQuickHit>> _loadSatorPromotors(String satorId) async {
    final hierarchyRows = await _supabase
        .from('hierarchy_sator_promotor')
        .select('promotor_id')
        .eq('sator_id', satorId)
        .eq('active', true);
    final promotorIds = List<Map<String, dynamic>>.from(hierarchyRows)
        .map((row) => '${row['promotor_id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    return _loadPromotorsByIds(promotorIds);
  }

  Future<List<_StoreQuickHit>> _loadSpvStores() async {
    final snapshotRaw = await _supabase.rpc('get_spv_visiting_monitor_snapshot');
    final snapshot = Map<String, dynamic>.from(
      (snapshotRaw as Map?) ?? const <String, dynamic>{},
    );
    final rows = (snapshot['rows'] as List? ?? const [])
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final result = <_StoreQuickHit>[];
    for (final row in rows) {
      final satorId = '${row['sator_id'] ?? ''}'.trim();
      final satorName = '${row['name'] ?? 'SATOR'}'.trim();
      final stores = (row['stores'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      for (final store in stores) {
        final storeId = '${store['store_id'] ?? ''}'.trim();
        if (storeId.isEmpty) continue;
        result.add(
          _StoreQuickHit(
            storeId: storeId,
            storeName: '${store['store_name'] ?? '-'}',
            subtitle: '$satorName • ${store['address'] ?? ''}'.trim(),
            scopeSatorId: satorId,
          ),
        );
      }
    }
    return result;
  }

  Future<List<_PromotorQuickHit>> _loadSpvPromotors(String spvId) async {
    final satorRows = await _supabase
        .from('hierarchy_spv_sator')
        .select('sator_id')
        .eq('spv_id', spvId)
        .eq('active', true);
    final satorIds = List<Map<String, dynamic>>.from(satorRows)
        .map((row) => '${row['sator_id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toList();
    if (satorIds.isEmpty) return const <_PromotorQuickHit>[];
    final promotorRows = await _supabase
        .from('hierarchy_sator_promotor')
        .select('promotor_id')
        .inFilter('sator_id', satorIds)
        .eq('active', true);
    final promotorIds = List<Map<String, dynamic>>.from(promotorRows)
        .map((row) => '${row['promotor_id'] ?? ''}'.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    return _loadPromotorsByIds(promotorIds);
  }

  Future<List<_PromotorQuickHit>> _loadPromotorsByIds(List<String> promotorIds) async {
    if (promotorIds.isEmpty) return const <_PromotorQuickHit>[];

    final userRows = await _supabase
        .from('users')
        .select('id, full_name, nickname')
        .inFilter('id', promotorIds);
    final assignmentRows = await _supabase
        .from('assignments_promotor_store')
        .select('promotor_id, store_id, stores(store_name)')
        .inFilter('promotor_id', promotorIds)
        .eq('active', true)
        .order('created_at', ascending: false);
    final hierarchyRows = await _supabase
        .from('hierarchy_sator_promotor')
        .select('promotor_id, sator_id')
        .inFilter('promotor_id', promotorIds)
        .eq('active', true);

    final usersById = <String, Map<String, dynamic>>{
      for (final row in List<Map<String, dynamic>>.from(userRows))
        '${row['id'] ?? ''}': row,
    };
    final latestAssignmentByPromotor = <String, Map<String, dynamic>>{};
    for (final row in List<Map<String, dynamic>>.from(assignmentRows)) {
      final promotorId = '${row['promotor_id'] ?? ''}'.trim();
      if (promotorId.isEmpty || latestAssignmentByPromotor.containsKey(promotorId)) {
        continue;
      }
      latestAssignmentByPromotor[promotorId] = row;
    }
    final satorByPromotor = <String, String>{
      for (final row in List<Map<String, dynamic>>.from(hierarchyRows))
        '${row['promotor_id'] ?? ''}': '${row['sator_id'] ?? ''}',
    };

    final result = <_PromotorQuickHit>[];
    for (final promotorId in promotorIds) {
      final user = usersById[promotorId];
      if (user == null) continue;
      final assignment = latestAssignmentByPromotor[promotorId];
      final storeId = '${assignment?['store_id'] ?? ''}'.trim();
      if (storeId.isEmpty) continue;
      final fullName = '${user['full_name'] ?? 'Promotor'}'.trim();
      final nickname = '${user['nickname'] ?? ''}'.trim();
      result.add(
        _PromotorQuickHit(
          promotorId: promotorId,
          promotorName: fullName.isEmpty ? 'Promotor' : fullName,
          nickname: nickname,
          storeId: storeId,
          storeName: '${assignment?['stores']?['store_name'] ?? '-'}',
          scopeSatorId: satorByPromotor[promotorId],
        ),
      );
    }
    return result;
  }

  Iterable<_StoreQuickHit> get _filteredStores {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _stores.take(12);
    final exact = <_StoreQuickHit>[];
    final fuzzy = <_StoreQuickHit>[];
    for (final row in _stores) {
      final haystack = '${row.storeName} ${row.subtitle}'.toLowerCase();
      if (!haystack.contains(query)) continue;
      if (row.storeName.toLowerCase().startsWith(query)) {
        exact.add(row);
      } else {
        fuzzy.add(row);
      }
    }
    return [...exact, ...fuzzy].take(12);
  }

  Iterable<_PromotorQuickHit> get _filteredPromotors {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return _promotors.take(12);
    final exact = <_PromotorQuickHit>[];
    final fuzzy = <_PromotorQuickHit>[];
    for (final row in _promotors) {
      final haystack =
          '${row.promotorName} ${row.nickname} ${row.storeName}'.toLowerCase();
      if (!haystack.contains(query)) continue;
      final startsWithName = row.promotorName.toLowerCase().startsWith(query) ||
          row.nickname.toLowerCase().startsWith(query);
      if (startsWithName) {
        exact.add(row);
      } else {
        fuzzy.add(row);
      }
    }
    return [...exact, ...fuzzy].take(12);
  }

  void _openStore(_StoreQuickHit row) {
    if (widget.scope == VisitingQuickSearchScope.sator) {
      context.push('/sator/visiting/form/${row.storeId}');
      return;
    }
    context.pushNamed(
      'spv-visit-form',
      pathParameters: <String, String>{'storeId': row.storeId},
      queryParameters: <String, String>{
        if ((row.scopeSatorId ?? '').trim().isNotEmpty)
          'satorId': row.scopeSatorId!,
      },
    );
  }

  void _openPromotor(_PromotorQuickHit row) {
    final storeRow = _StoreQuickHit(
      storeId: row.storeId,
      storeName: row.storeName,
      subtitle: row.nickname.isEmpty ? row.promotorName : row.nickname,
      scopeSatorId: row.scopeSatorId,
    );
    _openStore(storeRow);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cari Toko / Promotor')),
      body: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              autofocus: true,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: 'Ketik nama toko atau promotor',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: <Widget>[
                      _SectionTitle(
                        title: 'Toko',
                        subtitle: 'Pilih toko lalu langsung buka visiting',
                      ),
                      const SizedBox(height: 8),
                      if (_filteredStores.isEmpty)
                        _buildEmptyTile('Belum ada toko yang cocok')
                      else
                        ..._filteredStores.map(_buildStoreTile),
                      const SizedBox(height: 18),
                      _SectionTitle(
                        title: 'Promotor',
                        subtitle: 'Cari nama lengkap atau nama panggilan',
                      ),
                      const SizedBox(height: 8),
                      if (_filteredPromotors.isEmpty)
                        _buildEmptyTile('Belum ada promotor yang cocok')
                      else
                        ..._filteredPromotors.map(_buildPromotorTile),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyTile(String text) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 12,
          weight: FontWeight.w700,
          color: t.textMutedStrong,
        ),
      ),
    );
  }

  Widget _buildStoreTile(_StoreQuickHit row) {
    return _QuickResultTile(
      icon: Icons.storefront_rounded,
      title: row.storeName,
      subtitle: row.subtitle,
      onTap: () => _openStore(row),
    );
  }

  Widget _buildPromotorTile(_PromotorQuickHit row) {
    final subtitle = [
      if (row.nickname.isNotEmpty) '@${row.nickname}',
      row.storeName,
    ].join(' • ');
    return _QuickResultTile(
      icon: Icons.person_rounded,
      title: row.promotorName,
      subtitle: subtitle,
      onTap: () => _openPromotor(row),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.subtitle,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: PromotorText.outfit(
            size: 13,
            weight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: PromotorText.outfit(
            size: 10,
            weight: FontWeight.w600,
            color: t.textMutedStrong,
          ),
        ),
      ],
    );
  }
}

class _QuickResultTile extends StatelessWidget {
  const _QuickResultTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.surface3),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: t.primaryAccent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: PromotorText.outfit(
                          size: 12,
                          weight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle.trim().isEmpty ? '-' : subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: PromotorText.outfit(
                          size: 10,
                          weight: FontWeight.w600,
                          color: t.textMutedStrong,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: t.textMutedStrong),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoreQuickHit {
  const _StoreQuickHit({
    required this.storeId,
    required this.storeName,
    required this.subtitle,
    this.scopeSatorId,
  });

  final String storeId;
  final String storeName;
  final String subtitle;
  final String? scopeSatorId;
}

class _PromotorQuickHit {
  const _PromotorQuickHit({
    required this.promotorId,
    required this.promotorName,
    required this.nickname,
    required this.storeId,
    required this.storeName,
    this.scopeSatorId,
  });

  final String promotorId;
  final String promotorName;
  final String nickname;
  final String storeId;
  final String storeName;
  final String? scopeSatorId;
}
