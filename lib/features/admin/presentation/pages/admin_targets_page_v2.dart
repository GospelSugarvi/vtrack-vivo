import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';
import 'package:vtrack/core/utils/success_dialog.dart';
import '../../data/target_excel_import_parser.dart';
import '../widgets/admin_dialog_sync.dart';

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
    final formatted = formatter
        .format(int.parse(digitsOnly))
        .replaceAll(',', '.');
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
  bool _isParsingPromotorImport = false;
  bool _isApplyingPromotorImport = false;
  bool _isPromotorImportAppliedToForm = false;

  final List<Map<String, dynamic>> _promotorData = [];
  final List<Map<String, dynamic>> _satorData = [];
  final List<Map<String, dynamic>> _spvData = [];
  final List<Map<String, dynamic>> _specialBundles = [];
  final List<Map<String, dynamic>> _stores = [];
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
  final Map<String, Map<String, TextEditingController>> _spvSpecialDetailCtrls =
      {};
  TargetExcelImportPreview? _promotorImportPreview;
  Uint8List? _promotorImportBytes;
  String? _promotorImportFileName;

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

  String _formatIsoDateLabel(String? isoDate) {
    if (isoDate == null || isoDate.trim().isEmpty) return '-';
    final parsed = DateTime.tryParse(isoDate);
    if (parsed == null) return isoDate;
    return DateFormat('dd MMM yyyy', 'id_ID').format(parsed);
  }

  void _showSnackMessage(String message, {Color background = AppColors.info}) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.showSnackBar(
      SnackBar(content: Text(message), backgroundColor: background),
    );
  }

  Future<Uint8List> _resolveBytes(PlatformFile file) async {
    if (file.bytes != null) {
      return file.bytes!;
    }
    final path = file.path;
    if (path == null || path.isEmpty) {
      throw const FormatException('File Excel tidak bisa dibaca');
    }
    return File(path).readAsBytes();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _loadSpecialBundles(),
        _loadStores(),
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

  Future<void> _loadStores() async {
    final rows = await supabase
        .from('stores')
        .select('id, store_name')
        .isFilter('deleted_at', null)
        .order('store_name');
    _stores
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

    final userById = {for (final row in users) '${row['id']}': row};
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
          final satorName = satorId == null
              ? '-'
              : '${userById[satorId]?['full_name'] ?? '-'}';
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
            'target_special_detail':
                target['target_special_detail'] ?? <String, dynamic>{},
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
          final spvName = spvId == null
              ? '-'
              : '${userById[spvId]?['full_name'] ?? '-'}';
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
            'target_special_detail':
                target['target_special_detail'] ?? <String, dynamic>{},
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
            'target_special_detail':
                target['target_special_detail'] ?? <String, dynamic>{},
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
      _promotorOmzetCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_omzet']),
      );
      _promotorFokusTotalCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_fokus_total']),
      );
      _promotorTiktokCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_tiktok']),
      );
      _promotorFollowerCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_follower']),
      );
      _promotorVastCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_vast']),
      );

      final detail = _jsonMap(user['target_special_detail']);
      final detailCtrls = <String, TextEditingController>{};
      for (final bundle in _specialBundles) {
        final bundleId = '${bundle['id']}';
        detailCtrls[bundleId] = TextEditingController(
          text: _formatInputNumber(detail[bundleId]),
        );
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
      _satorSellInCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_sell_in']),
      );
      _satorSellOutCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_sell_out']),
      );
      _satorFokusCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_fokus']),
      );
      _satorAspCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_sellout_asp']),
      );
      _satorVastCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_vast']),
      );
      _satorSpecialTotalCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_special']),
      );

      final detail = _jsonMap(user['target_special_detail']);
      final detailCtrls = <String, TextEditingController>{};
      for (final bundle in _specialBundles) {
        final bundleId = '${bundle['id']}';
        detailCtrls[bundleId] = TextEditingController(
          text: _formatInputNumber(detail[bundleId]),
        );
      }
      _satorSpecialDetailCtrls[userId] = detailCtrls;
      _recalcSpecialTotal(
        userId,
        _satorSpecialDetailCtrls,
        _satorSpecialTotalCtrls,
      );
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
      _spvSellInCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_sell_in']),
      );
      _spvSellOutCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_sell_out']),
      );
      _spvFokusCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_fokus']),
      );
      _spvAspCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_sellout_asp']),
      );
      _spvVastCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_vast']),
      );
      _spvSpecialTotalCtrls[userId] = TextEditingController(
        text: _formatInputNumber(user['target_special']),
      );

      final detail = _jsonMap(user['target_special_detail']);
      final detailCtrls = <String, TextEditingController>{};
      for (final bundle in _specialBundles) {
        final bundleId = '${bundle['id']}';
        detailCtrls[bundleId] = TextEditingController(
          text: _formatInputNumber(detail[bundleId]),
        );
      }
      _spvSpecialDetailCtrls[userId] = detailCtrls;
      _recalcSpecialTotal(
        userId,
        _spvSpecialDetailCtrls,
        _spvSpecialTotalCtrls,
      );
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
      if (_promotorImportPreview != null && !_isPromotorImportAppliedToForm) {
        await _applyPromotorImportToForm(showResultMessage: false);
      }

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
          'target_fokus_total': _parseNumber(
            _promotorFokusTotalCtrls[userId]?.text ?? '',
          ),
          'target_tiktok': _parseNumber(
            _promotorTiktokCtrls[userId]?.text ?? '',
          ),
          'target_follower': _parseNumber(
            _promotorFollowerCtrls[userId]?.text ?? '',
          ),
          'target_vast': _parseNumber(_promotorVastCtrls[userId]?.text ?? ''),
          'target_special_detail': detail,
          'target_special': detail.values.fold<int>(0, (a, b) => a + b),
          'updated_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      await supabase
          .from('user_targets')
          .upsert(rows, onConflict: 'user_id,period_id');
      await _loadUsersData();
      if (!mounted) return;
      final nonZeroCount = rows.where((row) {
        return (row['target_omzet'] as int? ?? 0) > 0 ||
            (row['target_fokus_total'] as int? ?? 0) > 0 ||
            (row['target_tiktok'] as int? ?? 0) > 0 ||
            (row['target_follower'] as int? ?? 0) > 0 ||
            (row['target_vast'] as int? ?? 0) > 0 ||
            (row['target_special'] as int? ?? 0) > 0;
      }).length;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message:
            'Semua target promotor tersimpan. Non-zero: $nonZeroCount/${rows.length}.',
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
          'target_sell_out': _parseNumber(
            _satorSellOutCtrls[userId]?.text ?? '',
          ),
          'target_fokus': _parseNumber(_satorFokusCtrls[userId]?.text ?? ''),
          'target_sellout_asp': _parseNumber(
            _satorAspCtrls[userId]?.text ?? '',
          ),
          'target_vast': _parseNumber(_satorVastCtrls[userId]?.text ?? ''),
          'target_special': _parseNumber(
            _satorSpecialTotalCtrls[userId]?.text ?? '',
          ),
          'target_special_detail': detail,
          'updated_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      await supabase
          .from('user_targets')
          .upsert(rows, onConflict: 'user_id,period_id');
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
          'target_special': _parseNumber(
            _spvSpecialTotalCtrls[userId]?.text ?? '',
          ),
          'target_special_detail': detail,
          'updated_at': DateTime.now().toIso8601String(),
        };
      }).toList();

      await supabase
          .from('user_targets')
          .upsert(rows, onConflict: 'user_id,period_id');
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

  Future<void> _pickPromotorTargetExcel() async {
    if (_isParsingPromotorImport || _isApplyingPromotorImport) return;
    setState(() => _isParsingPromotorImport = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['xlsx'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) {
        if (!mounted) return;
        setState(() => _isParsingPromotorImport = false);
        return;
      }

      final file = result.files.single;
      final bytes = await _resolveBytes(file);
      final preview = TargetExcelImportParser.parse(
        bytes: bytes,
        fileName: file.name,
        role: TargetImportRole.promotor,
        users: _promotorData,
        specialBundles: _specialBundles,
      );

      if (!mounted) return;
      setState(() {
        _promotorImportBytes = bytes;
        _promotorImportFileName = file.name;
        _promotorImportPreview = preview;
        _isPromotorImportAppliedToForm = false;
        _isParsingPromotorImport = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isParsingPromotorImport = false);
      await showErrorDialog(
        context,
        title: 'Import Gagal',
        message: 'Gagal membaca Excel target promotor: $e',
      );
    }
  }

  Future<void> _reparsePromotorImportPreview() async {
    final bytes = _promotorImportBytes;
    final fileName = _promotorImportFileName;
    if (bytes == null || fileName == null) return;
    final preview = TargetExcelImportParser.parse(
      bytes: bytes,
      fileName: fileName,
      role: TargetImportRole.promotor,
      users: _promotorData,
      specialBundles: _specialBundles,
    );
    if (!mounted) return;
    setState(() {
      _promotorImportPreview = preview;
      _isPromotorImportAppliedToForm = false;
    });
  }

  void _resetPromotorImportPreview() {
    setState(() {
      _promotorImportPreview = null;
      _promotorImportBytes = null;
      _promotorImportFileName = null;
      _isParsingPromotorImport = false;
      _isApplyingPromotorImport = false;
      _isPromotorImportAppliedToForm = false;
    });
  }

  Future<void> _applyPromotorImportToForm({
    bool showResultMessage = true,
  }) async {
    final preview = _promotorImportPreview;
    if (preview == null || _isApplyingPromotorImport) return;

    final readyRows = preview.rows
        .where(
          (row) =>
              row.status == 'ready' && (row.matchedUserId?.isNotEmpty ?? false),
        )
        .toList();
    if (readyRows.isEmpty) {
      if (!mounted) return;
      await showErrorDialog(
        context,
        title: 'Tidak Ada Data',
        message: 'Belum ada baris Excel yang siap diproses ke form.',
      );
      return;
    }

    setState(() => _isApplyingPromotorImport = true);
    try {
      final hireDateRows = <Map<String, dynamic>>[];
      for (final row in readyRows) {
        final userId = row.matchedUserId!;
        if (row.hireDateIso != null && row.hireDateIso!.isNotEmpty) {
          hireDateRows.add({'id': userId, 'hire_date': row.hireDateIso});
        }
        if (row.values.containsKey('target_omzet')) {
          _promotorOmzetCtrls[userId]?.text = _formatInputNumber(
            row.values['target_omzet'],
          );
        }
        if (row.values.containsKey('target_tiktok')) {
          _promotorTiktokCtrls[userId]?.text = _formatInputNumber(
            row.values['target_tiktok'],
          );
        }
        if (row.values.containsKey('target_follower')) {
          _promotorFollowerCtrls[userId]?.text = _formatInputNumber(
            row.values['target_follower'],
          );
        }
        if (row.values.containsKey('target_vast')) {
          _promotorVastCtrls[userId]?.text = _formatInputNumber(
            row.values['target_vast'],
          );
        }

        final bundleCtrls = _promotorFokusDetailCtrls[userId];
        if (bundleCtrls != null) {
          for (final entry in row.bundleValues.entries) {
            final ctrl = bundleCtrls[entry.key];
            if (ctrl != null) {
              ctrl.text = _formatInputNumber(entry.value);
            }
          }
          _recalcPromotorFokusTotal(userId);
        }
      }

      for (final row in hireDateRows) {
        await supabase
            .from('users')
            .update({'hire_date': row['hire_date']})
            .eq('id', row['id']);
      }

      if (!mounted) return;
      setState(() {
        _isApplyingPromotorImport = false;
        _isPromotorImportAppliedToForm = true;
      });
      if (showResultMessage) {
        _showSnackMessage(
          '${readyRows.length} target promotor dimasukkan ke form. Lanjutkan review lalu klik simpan.',
          background: AppColors.success,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isApplyingPromotorImport = false);
      await showErrorDialog(
        context,
        title: 'Apply Gagal',
        message: 'Gagal memasukkan hasil preview ke form: $e',
      );
    }
  }

  List<Map<String, dynamic>> _promotorUsersMissingFromExcel() {
    final preview = _promotorImportPreview;
    if (preview == null) return const [];
    final matchedUserIds = preview.rows
        .where((row) => row.matchedUserId != null)
        .map((row) => row.matchedUserId!)
        .toSet();
    return _promotorData
        .where((user) => !matchedUserIds.contains('${user['user_id']}'))
        .toList()
      ..sort((a, b) => '${a['full_name']}'.compareTo('${b['full_name']}'));
  }

  Future<void> _showCreatePromotorDialog({
    String initialName = '',
    String? initialHireDateIso,
  }) async {
    if (!mounted) return;
    final formKey = GlobalKey<FormState>(
      debugLabel: 'admin_targets_dialog_form',
    );
    final fullNameC = TextEditingController(text: initialName);
    final nickNameC = TextEditingController();
    final emailC = TextEditingController();
    final passwordC = TextEditingController();
    final areaC = TextEditingController();

    String promotorStatus = 'training';
    String? satorId;
    String? storeId;
    DateTime? hireDate = initialHireDateIso == null
        ? null
        : DateTime.tryParse(initialHireDateIso);
    bool isSubmitting = false;

    await showAdminChangedDialog(
      context: context,
      onChanged: () async {
        await _loadUsersData();
        await _reparsePromotorImportPreview();
      },
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            title: const Text('Buat User Promotor'),
            content: SizedBox(
              width: 420,
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: fullNameC,
                        decoration: const InputDecoration(
                          labelText: 'Nama lengkap',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: nickNameC,
                        decoration: const InputDecoration(
                          labelText: 'Nama panggilan',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: emailC,
                        decoration: const InputDecoration(labelText: 'Email'),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: passwordC,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                        ),
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Wajib diisi'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: areaC,
                        decoration: const InputDecoration(labelText: 'Area'),
                      ),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: hireDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => hireDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Tanggal masuk',
                            suffixIcon: Icon(Icons.calendar_today_outlined),
                          ),
                          child: Text(
                            _formatIsoDateLabel(hireDate?.toIso8601String()),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: promotorStatus,
                        decoration: const InputDecoration(
                          labelText: 'Status promotor',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'training',
                            child: Text('Training'),
                          ),
                          DropdownMenuItem(
                            value: 'official',
                            child: Text('Official'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() => promotorStatus = value);
                        },
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: satorId,
                        decoration: const InputDecoration(labelText: 'SATOR'),
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'Pilih SATOR'
                            : null,
                        items: _satorData
                            .map(
                              (row) => DropdownMenuItem(
                                value: '${row['user_id']}',
                                child: Text('${row['full_name'] ?? '-'}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => satorId = value),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: storeId,
                        decoration: const InputDecoration(labelText: 'Toko'),
                        validator: (value) => (value == null || value.isEmpty)
                            ? 'Pilih toko'
                            : null,
                        items: _stores
                            .map(
                              (row) => DropdownMenuItem(
                                value: '${row['id']}',
                                child: Text('${row['store_name'] ?? '-'}'),
                              ),
                            )
                            .toList(),
                        onChanged: (value) =>
                            setDialogState(() => storeId = value),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSubmitting
                    ? null
                    : () => closeAdminDialog(dialogContext),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () async {
                        if (!formKey.currentState!.validate()) return;
                        setDialogState(() => isSubmitting = true);
                        try {
                          final res = await supabase.functions.invoke(
                            'create-user',
                            body: {
                              'email': emailC.text.trim(),
                              'password': passwordC.text.trim(),
                              'full_name': fullNameC.text.trim(),
                              'nickname': nickNameC.text.trim().isEmpty
                                  ? null
                                  : nickNameC.text.trim(),
                              'role': 'promotor',
                              'area': areaC.text.trim().isEmpty
                                  ? null
                                  : areaC.text.trim(),
                              'hire_date': hireDate
                                  ?.toIso8601String()
                                  .split('T')
                                  .first,
                              'supervisor_id': satorId,
                              'store_id': storeId,
                              'promotor_status': promotorStatus,
                            },
                          );
                          if (res.status >= 400) {
                            throw Exception(res.data.toString());
                          }
                          if (!dialogContext.mounted) return;
                          closeAdminDialog(dialogContext, changed: true);
                          _showSnackMessage(
                            'User promotor berhasil dibuat',
                            background: AppColors.success,
                          );
                        } catch (e) {
                          if (!dialogContext.mounted) return;
                          setDialogState(() => isSubmitting = false);
                          _showSnackMessage(
                            'Gagal membuat user: $e',
                            background: AppColors.danger,
                          );
                        }
                      },
                child: Text(isSubmitting ? 'Membuat...' : 'Buat User'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _softDeletePromotorUser(Map<String, dynamic> user) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Nonaktifkan User'),
        content: Text(
          'Promotor ${user['full_name'] ?? '-'} akan dinonaktifkan dari sistem. Lanjut?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Nonaktifkan'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final userId = '${user['user_id']}';
    try {
      await supabase
          .from('hierarchy_sator_promotor')
          .update({'active': false})
          .eq('promotor_id', userId);
      await supabase
          .from('assignments_promotor_store')
          .update({'active': false})
          .eq('promotor_id', userId);
      await supabase
          .from('users')
          .update({
            'status': 'inactive',
            'deleted_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);
      await _loadUsersData();
      await _reparsePromotorImportPreview();
      if (!mounted) return;
      _showSnackMessage(
        'User promotor dinonaktifkan',
        background: AppColors.success,
      );
    } catch (e) {
      if (!mounted) return;
      _showSnackMessage(
        'Gagal menonaktifkan user: $e',
        background: AppColors.danger,
      );
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

  Widget _buildImportStatCard(String label, int value, Color color) {
    return Card(
      child: SizedBox(
        width: 132,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$value',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImportStatusChip(String status) {
    final (label, color) = switch (status) {
      'ready' => ('Siap', AppColors.success),
      'unknown_user' => ('Belum Cocok', Colors.deepOrange),
      'duplicate_user' => ('Duplikat Nama', Colors.brown),
      _ => (status, AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  Widget _buildPromotorImportActionCard() {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import Target Promotor dari Excel',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Upload Excel target promotor, review preview, lalu apply ke form sebelum simpan semua.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed:
                      _isParsingPromotorImport || _isApplyingPromotorImport
                      ? null
                      : _pickPromotorTargetExcel,
                  icon: _isParsingPromotorImport
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.upload_file),
                  label: Text(
                    _isParsingPromotorImport
                        ? 'Membaca Excel...'
                        : 'Import Excel',
                  ),
                ),
                if (_promotorImportPreview != null)
                  ElevatedButton.icon(
                    onPressed: _isApplyingPromotorImport
                        ? null
                        : () => _applyPromotorImportToForm(),
                    icon: _isApplyingPromotorImport
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.playlist_add_check_circle_outlined),
                    label: Text(
                      _isApplyingPromotorImport
                          ? 'Mengisi Form...'
                          : 'Apply ke Form',
                    ),
                  ),
                if (_promotorImportPreview != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: (_isPromotorImportAppliedToForm
                              ? AppColors.success
                              : AppColors.warning)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _isPromotorImportAppliedToForm
                          ? 'Status: Sudah Apply ke Form'
                          : 'Status: Belum Apply ke Form',
                      style: TextStyle(
                        color: _isPromotorImportAppliedToForm
                            ? AppColors.success
                            : AppColors.warning,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                if (_promotorImportPreview != null)
                  OutlinedButton.icon(
                    onPressed:
                        _isParsingPromotorImport || _isApplyingPromotorImport
                        ? null
                        : _pickPromotorTargetExcel,
                    icon: const Icon(Icons.swap_horiz),
                    label: const Text('Ganti File'),
                  ),
                if (_promotorImportPreview != null)
                  OutlinedButton.icon(
                    onPressed:
                        _isParsingPromotorImport || _isApplyingPromotorImport
                        ? null
                        : _resetPromotorImportPreview,
                    icon: const Icon(Icons.close),
                    label: const Text('Reset'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromotorImportSummary(TargetExcelImportPreview preview) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${preview.fileName} • ${preview.sheetName}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildImportStatCard(
                  'Total',
                  preview.summary.totalRows,
                  AppColors.info,
                ),
                _buildImportStatCard(
                  'Siap',
                  preview.summary.readyRows,
                  AppColors.success,
                ),
                _buildImportStatCard(
                  'Issue',
                  preview.summary.issueRows,
                  AppColors.danger,
                ),
                _buildImportStatCard(
                  'Skip',
                  preview.summary.skippedRows,
                  AppColors.warning,
                ),
                _buildImportStatCard(
                  'Nama Belum Cocok',
                  preview.summary.unknownUserRows,
                  Colors.deepOrange,
                ),
                _buildImportStatCard(
                  'Duplikat Nama',
                  preview.summary.duplicateUserRows,
                  Colors.brown,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnknownExcelNamesCard(TargetExcelImportPreview preview) {
    final unknownRows = preview.rows
        .where((row) => row.status == 'unknown_user')
        .toList();
    if (unknownRows.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Nama Excel Belum Ada di Sistem',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Baris ini tidak memblokir import. Buat user baru dulu, lalu upload ulang atau apply ulang nanti.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...unknownRows.map((row) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            row.sourceName,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Row ${row.rowNumber}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _showCreatePromotorDialog(
                        initialName: row.sourceName,
                        initialHireDateIso: row.hireDateIso,
                      ),
                      icon: const Icon(Icons.person_add_alt_1),
                      label: const Text('Buat User Baru'),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildUsersMissingFromExcelCard() {
    final users = _promotorUsersMissingFromExcel();
    if (users.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'User Sistem Belum Ada di File Excel',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Review manual dulu. Bisa jadi resign, pindah area, atau memang belum dimasukkan ke file.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 12),
            ...users.map((user) {
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${user['full_name'] ?? '-'}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${user['store_name'] ?? '-'} • ${user['sator_name'] ?? '-'}',
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _softDeletePromotorUser(user),
                      icon: const Icon(Icons.person_off_outlined),
                      label: const Text('Nonaktifkan'),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPromotorImportPreviewTable(TargetExcelImportPreview preview) {
    final rows = preview.rows.take(200).toList();
    final bundleIds = preview.bundleNamesById.keys.toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Preview Hasil Baca Excel',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  const DataColumn(label: Text('Row')),
                  const DataColumn(label: Text('Nama Excel')),
                  const DataColumn(label: Text('User Sistem')),
                  const DataColumn(label: Text('Hire Date')),
                  const DataColumn(label: Text('Omzet')),
                  ...bundleIds.map(
                    (bundleId) => DataColumn(
                      label: Text(
                        preview.bundleNamesById[bundleId] ?? 'Bundle',
                      ),
                    ),
                  ),
                  const DataColumn(label: Text('Status')),
                  const DataColumn(label: Text('Catatan')),
                ],
                rows: rows.map((row) {
                  return DataRow(
                    cells: [
                      DataCell(Text('${row.rowNumber}')),
                      DataCell(
                        SizedBox(width: 220, child: Text(row.sourceName)),
                      ),
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(row.matchedUserName ?? '-'),
                        ),
                      ),
                      DataCell(Text(_formatIsoDateLabel(row.hireDateIso))),
                      DataCell(
                        Text(
                          row.values.containsKey('target_omzet')
                              ? _formatInputNumber(row.values['target_omzet'])
                              : '-',
                        ),
                      ),
                      ...bundleIds.map(
                        (bundleId) => DataCell(
                          Text('${row.bundleValues[bundleId] ?? '-'}'),
                        ),
                      ),
                      DataCell(_buildImportStatusChip(row.status)),
                      DataCell(
                        SizedBox(
                          width: 220,
                          child: Text(
                            row.notes.isEmpty ? '-' : row.notes.join(' • '),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
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
        _buildPromotorImportActionCard(),
        if (_promotorImportPreview != null) ...[
          _buildPromotorImportSummary(_promotorImportPreview!),
          _buildUnknownExcelNamesCard(_promotorImportPreview!),
          _buildUsersMissingFromExcelCard(),
          _buildPromotorImportPreviewTable(_promotorImportPreview!),
        ],
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _isSavingPromotorTargets
                ? null
                : _saveAllPromotorTargets,
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
                              onTap: () =>
                                  _clearZero(_promotorOmzetCtrls[userId]!),
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
                                onChanged: (_) =>
                                    _recalcPromotorFokusTotal(userId),
                              ),
                            );
                          }),
                          DataCell(
                            _tableField(
                              controller: _promotorTiktokCtrls[userId],
                              width: 90,
                              onTap: () =>
                                  _clearZero(_promotorTiktokCtrls[userId]!),
                            ),
                          ),
                          DataCell(
                            _tableField(
                              controller: _promotorFollowerCtrls[userId],
                              width: 90,
                              onTap: () =>
                                  _clearZero(_promotorFollowerCtrls[userId]!),
                            ),
                          ),
                          DataCell(
                            _tableField(
                              controller: _promotorVastCtrls[userId],
                              width: 90,
                              onTap: () =>
                                  _clearZero(_promotorVastCtrls[userId]!),
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
