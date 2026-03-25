import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

class ThousandsSeparatorInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    final digitsOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (digitsOnly.isEmpty) return const TextEditingValue();
    final formatter = NumberFormat('#,###', 'id_ID');
    final formatted = formatter.format(int.parse(digitsOnly)).replaceAll(',', '.');
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class AdminTargetsPageV2 extends StatefulWidget {
  final String periodId;
  final String monthName;
  final int year;

  const AdminTargetsPageV2({
    super.key,
    required this.periodId,
    required this.monthName,
    required this.year,
  });

  @override
  State<AdminTargetsPageV2> createState() => _AdminTargetsPageV2State();
}

class _AdminTargetsPageV2State extends State<AdminTargetsPageV2>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  bool _isLoading = true;
  bool _isSavingPromotorTargets = false;
  bool _isSavingSatorTargets = false;
  bool _isSavingSpvTargets = false;

  final List<Map<String, dynamic>> _promotorData = [];
  final List<Map<String, dynamic>> _satorData = [];
  final List<Map<String, dynamic>> _spvData = [];
  final List<Map<String, dynamic>> _specialBundles = [];
  final Map<String, DateTime> _metricsUpdatedByUser = {};
  final Set<String> _selectedUserIds = {};

  final Map<String, TextEditingController> _promotorOmzetCtrls = {};
  final Map<String, TextEditingController> _promotorFokusTotalCtrls = {};
  final Map<String, Map<String, TextEditingController>>
      _promotorFokusDetailCtrls = {};
  final Map<String, TextEditingController> _promotorTiktokCtrls = {};
  final Map<String, TextEditingController> _promotorFollowerCtrls = {};
  final Map<String, TextEditingController> _promotorVastCtrls = {};

  final Map<String, TextEditingController> _satorSellInCtrls = {};
  final Map<String, TextEditingController> _satorSellOutCtrls = {};
  final Map<String, TextEditingController> _satorFokusCtrls = {};
  final Map<String, TextEditingController> _satorAspCtrls = {};
  final Map<String, TextEditingController> _satorVastCtrls = {};
  final Map<String, TextEditingController> _satorSpecialTotalCtrls = {};
  final Map<String, Map<String, TextEditingController>>
      _satorSpecialDetailCtrls = {};

  final Map<String, TextEditingController> _spvSellInCtrls = {};
  final Map<String, TextEditingController> _spvSellOutCtrls = {};
  final Map<String, TextEditingController> _spvFokusCtrls = {};
  final Map<String, TextEditingController> _spvAspCtrls = {};
  final Map<String, TextEditingController> _spvVastCtrls = {};
  final Map<String, TextEditingController> _spvSpecialTotalCtrls = {};
  final Map<String, Map<String, TextEditingController>>
      _spvSpecialDetailCtrls = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging && mounted) {
        setState(_selectedUserIds.clear);
      }
    });
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _disposeControllerMap(_promotorOmzetCtrls);
    _disposeControllerMap(_promotorFokusTotalCtrls);
    _disposeNestedControllerMap(_promotorFokusDetailCtrls);
    _disposeControllerMap(_promotorTiktokCtrls);
    _disposeControllerMap(_promotorFollowerCtrls);
    _disposeControllerMap(_promotorVastCtrls);
    _disposeControllerMap(_satorSellInCtrls);
    _disposeControllerMap(_satorSellOutCtrls);
    _disposeControllerMap(_satorFokusCtrls);
    _disposeControllerMap(_satorAspCtrls);
    _disposeControllerMap(_satorVastCtrls);
    _disposeControllerMap(_satorSpecialTotalCtrls);
    _disposeNestedControllerMap(_satorSpecialDetailCtrls);
    _disposeControllerMap(_spvSellInCtrls);
    _disposeControllerMap(_spvSellOutCtrls);
    _disposeControllerMap(_spvFokusCtrls);
    _disposeControllerMap(_spvAspCtrls);
    _disposeControllerMap(_spvVastCtrls);
    _disposeControllerMap(_spvSpecialTotalCtrls);
    _disposeNestedControllerMap(_spvSpecialDetailCtrls);
    super.dispose();
  }

  void _disposeControllerMap(Map<String, TextEditingController> map) {
    for (final controller in map.values) {
      controller.dispose();
    }
    map.clear();
  }

  void _disposeNestedControllerMap(
    Map<String, Map<String, TextEditingController>> map,
  ) {
    for (final child in map.values) {
      for (final controller in child.values) {
        controller.dispose();
      }
    }
    map.clear();
  }

  int _parseNumber(String text) {
    return int.tryParse(text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;
  }

  String _formatInputNumber(dynamic value) {
    final number = value is num ? value.toInt() : _parseNumber('$value');
    if (number == 0) return '';
    return NumberFormat('#,###', 'id_ID').format(number).replaceAll(',', '.');
  }

  void _clearZero(TextEditingController controller) {
    if (_parseNumber(controller.text) != 0) return;
    controller.clear();
  }

  String _formatSyncTime(String userId) {
    final updatedAt = _metricsUpdatedByUser[userId];
    if (updatedAt == null) return '-';
    return DateFormat('dd MMM HH:mm', 'id_ID').format(updatedAt.toLocal());
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadSpecialBundles(),
        _loadUsersData(),
      ]);
    } catch (e) {
      if (mounted) {
        await showErrorDialog(
          context,
          title: 'Gagal',
          message: 'Gagal memuat target: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadSpecialBundles() async {
    final rows = await supabase
        .from('special_focus_bundles')
        .select('id, bundle_name')
        .eq('period_id', widget.periodId)
        .order('bundle_name');
    _specialBundles
      ..clear()
      ..addAll(List<Map<String, dynamic>>.from(rows));
  }

  Future<void> _loadUsersData() async {
    final usersRows = await supabase
        .from('users')
        .select('id, full_name, role')
        .isFilter('deleted_at', null)
        .inFilter('role', ['promotor', 'sator', 'spv'])
        .order('full_name');

    final targetsRows = await supabase
        .from('user_targets')
        .select(
          'user_id, updated_at, '
          'target_omzet, target_fokus_total, target_tiktok, target_follower, '
          'target_vast, target_sell_in, target_sell_out, target_fokus, '
          'target_sellout_asp, target_special, target_special_detail',
        )
        .eq('period_id', widget.periodId);

    final storeRows = await supabase
        .from('assignments_promotor_store')
        .select('promotor_id, stores(store_name)')
        .eq('active', true)
        .order('created_at', ascending: false);

    final satorPromotorRows = await supabase
        .from('hierarchy_sator_promotor')
        .select('promotor_id, sator_id')
        .eq('active', true);

    final spvSatorRows = await supabase
        .from('hierarchy_spv_sator')
        .select('sator_id, spv_id')
        .eq('active', true);

    final users = List<Map<String, dynamic>>.from(usersRows);
    final targets = List<Map<String, dynamic>>.from(targetsRows);

    final userById = {
      for (final row in users) '${row['id']}': row,
    };
    final targetByUserId = {
      for (final row in targets) '${row['user_id']}': row,
    };

    final storeNameByPromotor = <String, String>{};
    for (final row in List<Map<String, dynamic>>.from(storeRows)) {
      final promotorId = '${row['promotor_id'] ?? ''}';
      if (promotorId.isEmpty || storeNameByPromotor.containsKey(promotorId)) {
        continue;
      }
      storeNameByPromotor[promotorId] =
          '${row['stores']?['store_name'] ?? '-'}';
    }

    final satorIdByPromotor = {
      for (final row in List<Map<String, dynamic>>.from(satorPromotorRows))
        '${row['promotor_id']}': '${row['sator_id']}',
    };
    final spvIdBySator = {
      for (final row in List<Map<String, dynamic>>.from(spvSatorRows))
        '${row['sator_id']}': '${row['spv_id']}',
    };

    _metricsUpdatedByUser.clear();
    for (final row in targets) {
      final updatedAt = DateTime.tryParse('${row['updated_at'] ?? ''}');
      if (updatedAt != null) {
        _metricsUpdatedByUser['${row['user_id']}'] = updatedAt;
      }
    }

    _promotorData
      ..clear()
      ..addAll(
        users.where((row) => row['role'] == 'promotor').map((row) {
          final userId = '${row['id']}';
          final target = targetByUserId[userId] ?? const <String, dynamic>{};
          final satorId = satorIdByPromotor[userId];
          final satorName =
              satorId == null ? '-' : '${userById[satorId]?['full_name'] ?? '-'}';
          return {
            'user_id': userId,
            'full_name': row['full_name'] ?? '-',
            'store_name': storeNameByPromotor[userId] ?? '-',
            'sator_name': satorName,
            'has_target': target.isNotEmpty,
            'target_omzet': target['target_omzet'] ?? 0,
            'target_fokus_total': target['target_fokus_total'] ?? 0,
            'target_tiktok': target['target_tiktok'] ?? 0,
            'target_follower': target['target_follower'] ?? 0,
            'target_vast': target['target_vast'] ?? 0,
            'target_special_detail': target['target_special_detail'] ?? <String, dynamic>{},
          };
        }),
      );

    _satorData
      ..clear()
      ..addAll(
        users.where((row) => row['role'] == 'sator').map((row) {
          final userId = '${row['id']}';
          final target = targetByUserId[userId] ?? const <String, dynamic>{};
          final spvId = spvIdBySator[userId];
          final spvName =
              spvId == null ? '-' : '${userById[spvId]?['full_name'] ?? '-'}';
          return {
            'user_id': userId,
            'full_name': row['full_name'] ?? '-',
            'spv_name': spvName,
            'has_target': target.isNotEmpty,
            'target_sell_in': target['target_sell_in'] ?? 0,
            'target_sell_out': target['target_sell_out'] ?? 0,
            'target_fokus': target['target_fokus'] ?? 0,
            'target_sellout_asp': target['target_sellout_asp'] ?? 0,
            'target_vast': target['target_vast'] ?? 0,
            'target_special': target['target_special'] ?? 0,
            'target_special_detail': target['target_special_detail'] ?? <String, dynamic>{},
          };
        }),
      );

    _spvData
      ..clear()
      ..addAll(
        users.where((row) => row['role'] == 'spv').map((row) {
          final userId = '${row['id']}';
          final target = targetByUserId[userId] ?? const <String, dynamic>{};
          return {
            'user_id': userId,
            'full_name': row['full_name'] ?? '-',
            'has_target': target.isNotEmpty,
            'target_sell_in': target['target_sell_in'] ?? 0,
            'target_sell_out': target['target_sell_out'] ?? 0,
            'target_fokus': target['target_fokus'] ?? 0,
            'target_sellout_asp': target['target_sellout_asp'] ?? 0,
            'target_vast': target['target_vast'] ?? 0,
            'target_special': target['target_special'] ?? 0,
            'target_special_detail': target['target_special_detail'] ?? <String, dynamic>{},
          };
        }),
      );

    _syncPromotorControllers();
    _syncSatorControllers();
    _syncSpvControllers();
  }

  void _syncPromotorControllers() {
    _disposeControllerMap(_promotorOmzetCtrls);
    _disposeControllerMap(_promotorFokusTotalCtrls);
    _disposeNestedControllerMap(_promotorFokusDetailCtrls);
    _disposeControllerMap(_promotorTiktokCtrls);
    _disposeControllerMap(_promotorFollowerCtrls);
    _disposeControllerMap(_promotorVastCtrls);

    for (final user in _promotorData) {
      final userId = user['user_id'] as String;
      _promotorOmzetCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_omzet']));
      _promotorFokusTotalCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_fokus_total']),
      );
      _promotorTiktokCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_tiktok']));
      _promotorFollowerCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_follower']));
      _promotorVastCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_vast']));

      final detail = _jsonMap(user['target_special_detail']);
      final detailCtrls = <String, TextEditingController>{};
      for (final bundle in _specialBundles) {
        final bundleId = '${bundle['id']}';
        detailCtrls[bundleId] =
            TextEditingController(text: _formatInputNumber(detail[bundleId]));
      }
      _promotorFokusDetailCtrls[userId] = detailCtrls;
    }
  }

  void _syncSatorControllers() {
    _disposeControllerMap(_satorSellInCtrls);
    _disposeControllerMap(_satorSellOutCtrls);
    _disposeControllerMap(_satorFokusCtrls);
    _disposeControllerMap(_satorAspCtrls);
    _disposeControllerMap(_satorVastCtrls);
    _disposeControllerMap(_satorSpecialTotalCtrls);
    _disposeNestedControllerMap(_satorSpecialDetailCtrls);

    for (final user in _satorData) {
      final userId = user['user_id'] as String;
      _satorSellInCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_sell_in']));
      _satorSellOutCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_sell_out']));
      _satorFokusCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_fokus']));
      _satorAspCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_sellout_asp']),
      );
      _satorVastCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_vast']));
      _satorSpecialTotalCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_special']));

      final detail = _jsonMap(user['target_special_detail']);
      final detailCtrls = <String, TextEditingController>{};
      for (final bundle in _specialBundles) {
        final bundleId = '${bundle['id']}';
        detailCtrls[bundleId] =
            TextEditingController(text: _formatInputNumber(detail[bundleId]));
      }
      _satorSpecialDetailCtrls[userId] = detailCtrls;
      _recalcSpecialTotal(userId, _satorSpecialDetailCtrls, _satorSpecialTotalCtrls);
    }
  }

  void _syncSpvControllers() {
    _disposeControllerMap(_spvSellInCtrls);
    _disposeControllerMap(_spvSellOutCtrls);
    _disposeControllerMap(_spvFokusCtrls);
    _disposeControllerMap(_spvAspCtrls);
    _disposeControllerMap(_spvVastCtrls);
    _disposeControllerMap(_spvSpecialTotalCtrls);
    _disposeNestedControllerMap(_spvSpecialDetailCtrls);

    for (final user in _spvData) {
      final userId = user['user_id'] as String;
      _spvSellInCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_sell_in']));
      _spvSellOutCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_sell_out']));
      _spvFokusCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_fokus']));
      _spvAspCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_sellout_asp']),
      );
      _spvVastCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_vast']));
      _spvSpecialTotalCtrls[userId] =
          TextEditingController(text: _formatInputNumber(user['target_special']));

      final detail = _jsonMap(user['target_special_detail']);
      final detailCtrls = <String, TextEditingController>{};
      for (final bundle in _specialBundles) {
        final bundleId = '${bundle['id']}';
        detailCtrls[bundleId] =
            TextEditingController(text: _formatInputNumber(detail[bundleId]));
      }
      _spvSpecialDetailCtrls[userId] = detailCtrls;
      _recalcSpecialTotal(userId, _spvSpecialDetailCtrls, _spvSpecialTotalCtrls);
    }
  }

  Map<String, dynamic> _jsonMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  void _recalcPromotorFokusTotal(String userId) {
    final ctrls = _promotorFokusDetailCtrls[userId];
    if (ctrls == null) return;
    var total = 0;
    for (final controller in ctrls.values) {
      total += _parseNumber(controller.text);
    }
    _promotorFokusTotalCtrls[userId]?.text = _formatInputNumber(total);
  }

  void _recalcSpecialTotal(
    String userId,
    Map<String, Map<String, TextEditingController>> detailCtrls,
    Map<String, TextEditingController> totalCtrls,
  ) {
    final ctrls = detailCtrls[userId];
    if (ctrls == null) return;
    var total = 0;
    for (final controller in ctrls.values) {
      total += _parseNumber(controller.text);
    }
    totalCtrls[userId]?.text = _formatInputNumber(total);
  }

  Future<void> _saveAllPromotorTargets() async {
    if (_promotorData.isEmpty) return;
    setState(() => _isSavingPromotorTargets = true);
    try {
      final rows = _promotorData.map((user) {
        final userId = user['user_id'] as String;
        final detailCtrls = _promotorFokusDetailCtrls[userId] ?? const {};
        final detail = <String, int>{};
        for (final entry in detailCtrls.entries) {
          final value = _parseNumber(entry.value.text);
          if (value > 0) detail[entry.key] = value;
        }
        return {
          'user_id': userId,
          'period_id': widget.periodId,
          'target_omzet': _parseNumber(_promotorOmzetCtrls[userId]?.text ?? ''),
          'target_fokus_total':
              _parseNumber(_promotorFokusTotalCtrls[userId]?.text ?? ''),
          'target_tiktok': _parseNumber(_promotorTiktokCtrls[userId]?.text ?? ''),
          'target_follower':
              _parseNumber(_promotorFollowerCtrls[userId]?.text ?? ''),
          'target_vast': _parseNumber(_promotorVastCtrls[userId]?.text ?? ''),
          'target_special_detail': detail,
          'target_special': detail.values.fold<int>(0, (a, b) => a + b),
          'updated_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      await supabase.from('user_targets').upsert(
            rows,
            onConflict: 'user_id,period_id',
          );
      await _loadUsersData();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: 'Semua target promotor tersimpan.',
      );
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Gagal menyimpan target promotor: $e',
      );
    } finally {
      if (mounted) setState(() => _isSavingPromotorTargets = false);
    }
  }

  Future<void> _saveAllSatorTargets() async {
    if (_satorData.isEmpty) return;
    setState(() => _isSavingSatorTargets = true);
    try {
      final rows = _satorData.map((user) {
        final userId = user['user_id'] as String;
        final detailCtrls = _satorSpecialDetailCtrls[userId] ?? const {};
        final detail = <String, int>{};
        for (final entry in detailCtrls.entries) {
          final value = _parseNumber(entry.value.text);
          if (value > 0) detail[entry.key] = value;
        }
        return {
          'user_id': userId,
          'period_id': widget.periodId,
          'target_sell_in': _parseNumber(_satorSellInCtrls[userId]?.text ?? ''),
          'target_sell_out': _parseNumber(_satorSellOutCtrls[userId]?.text ?? ''),
          'target_fokus': _parseNumber(_satorFokusCtrls[userId]?.text ?? ''),
          'target_sellout_asp': _parseNumber(_satorAspCtrls[userId]?.text ?? ''),
          'target_vast': _parseNumber(_satorVastCtrls[userId]?.text ?? ''),
          'target_special': _parseNumber(_satorSpecialTotalCtrls[userId]?.text ?? ''),
          'target_special_detail': detail,
          'updated_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      await supabase.from('user_targets').upsert(
            rows,
            onConflict: 'user_id,period_id',
          );
      await _loadUsersData();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: 'Semua target SATOR tersimpan.',
      );
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Gagal menyimpan target SATOR: $e',
      );
    } finally {
      if (mounted) setState(() => _isSavingSatorTargets = false);
    }
  }

  Future<void> _saveAllSpvTargets() async {
    if (_spvData.isEmpty) return;
    setState(() => _isSavingSpvTargets = true);
    try {
      final rows = _spvData.map((user) {
        final userId = user['user_id'] as String;
        final detailCtrls = _spvSpecialDetailCtrls[userId] ?? const {};
        final detail = <String, int>{};
        for (final entry in detailCtrls.entries) {
          final value = _parseNumber(entry.value.text);
          if (value > 0) detail[entry.key] = value;
        }
        return {
          'user_id': userId,
          'period_id': widget.periodId,
          'target_sell_in': _parseNumber(_spvSellInCtrls[userId]?.text ?? ''),
          'target_sell_out': _parseNumber(_spvSellOutCtrls[userId]?.text ?? ''),
          'target_fokus': _parseNumber(_spvFokusCtrls[userId]?.text ?? ''),
          'target_sellout_asp': _parseNumber(_spvAspCtrls[userId]?.text ?? ''),
          'target_vast': _parseNumber(_spvVastCtrls[userId]?.text ?? ''),
          'target_special': _parseNumber(_spvSpecialTotalCtrls[userId]?.text ?? ''),
          'target_special_detail': detail,
          'updated_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      await supabase.from('user_targets').upsert(
            rows,
            onConflict: 'user_id,period_id',
          );
      await _loadUsersData();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: 'Semua target SPV tersimpan.',
      );
    } catch (e) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Gagal',
        message: 'Gagal menyimpan target SPV: $e',
      );
    } finally {
      if (mounted) setState(() => _isSavingSpvTargets = false);
    }
  }

  Widget _tableField({
    required TextEditingController? controller,
    required double width,
    bool readOnly = false,
    VoidCallback? onTap,
    ValueChanged<String>? onChanged,
  }) {
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        decoration: const InputDecoration(
          isDense: true,
          border: OutlineInputBorder(),
          hintText: '0',
        ),
        keyboardType: TextInputType.number,
        inputFormatters: readOnly ? null : [ThousandsSeparatorInputFormatter()],
        onTap: onTap,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildPromotorTable() {
    if (_promotorData.isEmpty) {
      return const Center(child: Text('Tidak ada data promotor'));
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final user in _promotorData) {
      final satorName = '${user['sator_name'] ?? '-'}';
      grouped.putIfAbsent(satorName, () => []).add(user);
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _isSavingPromotorTargets ? null : _saveAllPromotorTargets,
            icon: _isSavingPromotorTargets
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Simpan Semua Target Promotor'),
          ),
        ),
        const SizedBox(height: 16),
        ...grouped.entries.map((entry) {
          final satorName = entry.key;
          final users = entry.value;
          return Card(
            margin: const EdgeInsets.only(bottom: 16),
            child: ExpansionTile(
              initiallyExpanded: true,
              title: Text(
                'SATOR: $satorName',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text('${users.length} promotor'),
              children: [
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    dataRowMinHeight: 56,
                    dataRowMaxHeight: 90,
                    columns: [
                      const DataColumn(label: Text('Nama')),
                      const DataColumn(label: Text('Toko')),
                      const DataColumn(label: Text('Sell Out')),
                      const DataColumn(label: Text('Fokus Total')),
                      ..._specialBundles.map(
                        (bundle) => DataColumn(
                          label: Text('${bundle['bundle_name'] ?? 'Bundle'}'),
                        ),
                      ),
                      const DataColumn(label: Text('TikTok')),
                      const DataColumn(label: Text('Follower')),
                      const DataColumn(label: Text('VAST')),
                      const DataColumn(label: Text('Sync')),
                      const DataColumn(label: Text('Status')),
                    ],
                    rows: users.map((user) {
                      final userId = user['user_id'] as String;
                      final hasTarget = user['has_target'] == true;
                      return DataRow(
                        cells: [
                          DataCell(Text('${user['full_name'] ?? '-'}')),
                          DataCell(Text('${user['store_name'] ?? '-'}')),
                          DataCell(
                            _tableField(
                              controller: _promotorOmzetCtrls[userId],
                              width: 140,
                              onTap: () => _clearZero(_promotorOmzetCtrls[userId]!),
                            ),
                          ),
                          DataCell(
                            _tableField(
                              controller: _promotorFokusTotalCtrls[userId],
                              width: 110,
                              readOnly: true,
                            ),
                          ),
                          ..._specialBundles.map((bundle) {
                            final bundleId = '${bundle['id']}';
                            final ctrl =
                                _promotorFokusDetailCtrls[userId]?[bundleId];
                            return DataCell(
                              _tableField(
                                controller: ctrl,
                                width: 90,
                                onTap: () {
                                  if (ctrl != null) _clearZero(ctrl);
                                },
                                onChanged: (_) => _recalcPromotorFokusTotal(userId),
                              ),
                            );
                          }),
                          DataCell(
                            _tableField(
                              controller: _promotorTiktokCtrls[userId],
                              width: 90,
                              onTap: () => _clearZero(_promotorTiktokCtrls[userId]!),
                            ),
                          ),
                          DataCell(
                            _tableField(
                              controller: _promotorFollowerCtrls[userId],
                              width: 90,
                              onTap: () => _clearZero(_promotorFollowerCtrls[userId]!),
                            ),
                          ),
                          DataCell(
                            _tableField(
                              controller: _promotorVastCtrls[userId],
                              width: 90,
                              onTap: () => _clearZero(_promotorVastCtrls[userId]!),
                            ),
                          ),
                          DataCell(Text(_formatSyncTime(userId))),
                          DataCell(
                            hasTarget
                                ? const Icon(
                                    Icons.check_circle,
                                    color: AppColors.success,
                                    size: 20,
                                  )
                                : const Icon(
                                    Icons.radio_button_unchecked,
                                    color: AppColors.textSecondary,
                                    size: 20,
                                  ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildSatorTable() {
    if (_satorData.isEmpty) {
      return const Center(child: Text('Tidak ada data SATOR'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _isSavingSatorTargets ? null : _saveAllSatorTargets,
            icon: _isSavingSatorTargets
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Simpan Semua Target SATOR'),
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            dataRowMinHeight: 56,
            dataRowMaxHeight: 90,
            columns: [
              const DataColumn(label: Text('Nama')),
              const DataColumn(label: Text('SPV')),
              const DataColumn(label: Text('Sell In')),
              const DataColumn(label: Text('Sell Out')),
              const DataColumn(label: Text('Fokus')),
              const DataColumn(label: Text('ASP')),
              const DataColumn(label: Text('VAST')),
              const DataColumn(label: Text('Tipe Khusus Total')),
              ..._specialBundles.map(
                (bundle) => DataColumn(
                  label: Text('${bundle['bundle_name'] ?? 'Bundle'}'),
                ),
              ),
              const DataColumn(label: Text('Sync')),
              const DataColumn(label: Text('Status')),
            ],
            rows: _satorData.map((user) {
              final userId = user['user_id'] as String;
              final hasTarget = user['has_target'] == true;
              return DataRow(
                cells: [
                  DataCell(Text('${user['full_name'] ?? '-'}')),
                  DataCell(Text('${user['spv_name'] ?? '-'}')),
                  DataCell(
                    _tableField(
                      controller: _satorSellInCtrls[userId],
                      width: 160,
                      onTap: () => _clearZero(_satorSellInCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _satorSellOutCtrls[userId],
                      width: 160,
                      onTap: () => _clearZero(_satorSellOutCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _satorFokusCtrls[userId],
                      width: 80,
                      onTap: () => _clearZero(_satorFokusCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _satorAspCtrls[userId],
                      width: 140,
                      onTap: () => _clearZero(_satorAspCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _satorVastCtrls[userId],
                      width: 80,
                      onTap: () => _clearZero(_satorVastCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _satorSpecialTotalCtrls[userId],
                      width: 90,
                      readOnly: true,
                    ),
                  ),
                  ..._specialBundles.map((bundle) {
                    final bundleId = '${bundle['id']}';
                    final ctrl = _satorSpecialDetailCtrls[userId]?[bundleId];
                    return DataCell(
                      _tableField(
                        controller: ctrl,
                        width: 90,
                        onTap: () {
                          if (ctrl != null) _clearZero(ctrl);
                        },
                        onChanged: (_) => _recalcSpecialTotal(
                          userId,
                          _satorSpecialDetailCtrls,
                          _satorSpecialTotalCtrls,
                        ),
                      ),
                    );
                  }),
                  DataCell(Text(_formatSyncTime(userId))),
                  DataCell(
                    hasTarget
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                            size: 20,
                          )
                        : const Icon(
                            Icons.radio_button_unchecked,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSpvTable() {
    if (_spvData.isEmpty) {
      return const Center(child: Text('Tidak ada data SPV'));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _isSavingSpvTargets ? null : _saveAllSpvTargets,
            icon: _isSavingSpvTargets
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: const Text('Simpan Semua Target SPV'),
          ),
        ),
        const SizedBox(height: 16),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            dataRowMinHeight: 56,
            dataRowMaxHeight: 90,
            columns: [
              const DataColumn(label: Text('Nama')),
              const DataColumn(label: Text('Sell In')),
              const DataColumn(label: Text('Sell Out')),
              const DataColumn(label: Text('Fokus')),
              const DataColumn(label: Text('ASP')),
              const DataColumn(label: Text('VAST')),
              const DataColumn(label: Text('Tipe Khusus Total')),
              ..._specialBundles.map(
                (bundle) => DataColumn(
                  label: Text('${bundle['bundle_name'] ?? 'Bundle'}'),
                ),
              ),
              const DataColumn(label: Text('Sync')),
              const DataColumn(label: Text('Status')),
            ],
            rows: _spvData.map((user) {
              final userId = user['user_id'] as String;
              final hasTarget = user['has_target'] == true;
              return DataRow(
                cells: [
                  DataCell(Text('${user['full_name'] ?? '-'}')),
                  DataCell(
                    _tableField(
                      controller: _spvSellInCtrls[userId],
                      width: 160,
                      onTap: () => _clearZero(_spvSellInCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _spvSellOutCtrls[userId],
                      width: 160,
                      onTap: () => _clearZero(_spvSellOutCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _spvFokusCtrls[userId],
                      width: 80,
                      onTap: () => _clearZero(_spvFokusCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _spvAspCtrls[userId],
                      width: 140,
                      onTap: () => _clearZero(_spvAspCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _spvVastCtrls[userId],
                      width: 80,
                      onTap: () => _clearZero(_spvVastCtrls[userId]!),
                    ),
                  ),
                  DataCell(
                    _tableField(
                      controller: _spvSpecialTotalCtrls[userId],
                      width: 90,
                      readOnly: true,
                    ),
                  ),
                  ..._specialBundles.map((bundle) {
                    final bundleId = '${bundle['id']}';
                    final ctrl = _spvSpecialDetailCtrls[userId]?[bundleId];
                    return DataCell(
                      _tableField(
                        controller: ctrl,
                        width: 90,
                        onTap: () {
                          if (ctrl != null) _clearZero(ctrl);
                        },
                        onChanged: (_) => _recalcSpecialTotal(
                          userId,
                          _spvSpecialDetailCtrls,
                          _spvSpecialTotalCtrls,
                        ),
                      ),
                    );
                  }),
                  DataCell(Text(_formatSyncTime(userId))),
                  DataCell(
                    hasTarget
                        ? const Icon(
                            Icons.check_circle,
                            color: AppColors.success,
                            size: 20,
                          )
                        : const Icon(
                            Icons.radio_button_unchecked,
                            color: AppColors.textSecondary,
                            size: 20,
                          ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Target ${widget.monthName} ${widget.year}'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Promotor'),
            Tab(text: 'SATOR'),
            Tab(text: 'SPV'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  color: AppColors.surfaceVariant,
                  child: Text(
                    'Target VAST sudah tersedia di semua tab role dan tersimpan ke user_targets.period ${widget.periodId}.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPromotorTable(),
                      _buildSatorTable(),
                      _buildSpvTable(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
