import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../../allbrand/presentation/widgets/allbrand_report_detail_panel.dart';
import '../../../../../ui/promotor/promotor.dart';

class PreVisitPage extends StatefulWidget {
  final String storeId;
  final String? scopeSatorId;
  final String? scopeDate;

  const PreVisitPage({
    super.key,
    required this.storeId,
    this.scopeSatorId,
    this.scopeDate,
  });

  @override
  State<PreVisitPage> createState() => _PreVisitPageState();
}

class _PreVisitPageState extends State<PreVisitPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _commentController = TextEditingController();
  final _photos = <File>[];

  bool _isLoading = true;
  bool _isSubmittingVisit = false;
  int _tabIndex = 0;
  int _promotorRangeIndex = 1;
  int _activityRangeIndex = 1;
  final Map<String, String> _selectedWeeklyKeys = {};
  Map<String, dynamic>? _store;
  List<Map<String, dynamic>> _comments = const [];
  Map<String, dynamic>? _performance;
  int _visitCount = 0;
  DateTime? _lastVisitAt;

  String? get _scopeSatorId {
    final candidate = widget.scopeSatorId?.trim();
    if (candidate != null && candidate.isNotEmpty) return candidate;
    return _supabase.auth.currentUser?.id;
  }

  DateTime get _snapshotDate {
    final raw = widget.scopeDate?.trim();
    if (raw != null && raw.isNotEmpty) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
    }
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _scopeSatorId;
      if (userId == null) throw Exception('Sesi login tidak ditemukan');
      final snapshotRaw = await _supabase.rpc(
        'get_sator_pre_visit_snapshot',
        params: {
          'p_sator_id': userId,
          'p_store_id': widget.storeId,
          'p_date': DateFormat('yyyy-MM-dd').format(_snapshotDate),
        },
      );
      final snapshot = snapshotRaw is Map
          ? Map<String, dynamic>.from(snapshotRaw)
          : <String, dynamic>{};
      final store = Map<String, dynamic>.from(
        snapshot['store'] as Map? ?? const {},
      );
      final comments = List<Map<String, dynamic>>.from(
        snapshot['comments'] as List? ?? const [],
      );
      final performance = Map<String, dynamic>.from(
        snapshot['performance'] as Map? ?? const {},
      );
      final visiting = Map<String, dynamic>.from(
        performance['visiting'] as Map? ?? const {},
      );

      if (!mounted) return;
      setState(() {
        _store = store;
        _comments = comments;
        _performance = performance;
        _visitCount = _toInt(visiting['visit_count']);
        _lastVisitAt = DateTime.tryParse(
          '${visiting['last_visit_at'] ?? ''}',
        )?.toLocal();
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickPhoto(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: source, imageQuality: 70);
    if (picked == null || !mounted) return;
    setState(() {
      if (_photos.length < 2) {
        _photos.add(File(picked.path));
      }
    });
  }

  Future<void> _showPhotoSourcePicker() async {
    if (_photos.length >= 2) return;
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Kamera'),
                onTap: () => Navigator.of(context).pop(ImageSource.camera),
              ),
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Galeri'),
                onTap: () => Navigator.of(context).pop(ImageSource.gallery),
              ),
            ],
          ),
        );
      },
    );
    if (source == null) return;
    await _pickPhoto(source);
  }

  Future<void> _submitVisit() async {
    if (_commentController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Catatan visit wajib diisi.'),
          backgroundColor: t.danger,
        ),
      );
      return;
    }
    if (_photos.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Minimal 1 foto visit diperlukan.'),
          backgroundColor: t.danger,
        ),
      );
      return;
    }
    setState(() => _isSubmittingVisit = true);
    try {
      final photosPayload = <Map<String, dynamic>>[];
      for (var i = 0; i < _photos.length; i++) {
        final file = _photos[i];
        final bytes = await file.readAsBytes();
        photosPayload.add({
          'file_name': file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'visit_$i.jpg',
          'content_type': _contentTypeForPath(file.path),
          'base64_data': base64Encode(bytes),
        });
      }

      final response = await _supabase.functions.invoke(
        'submit-sator-visit',
        body: {
          'store_id': widget.storeId,
          'target_sator_id': _scopeSatorId,
          'photos': photosPayload,
          'notes': _commentController.text.trim(),
          'visit_at': DateTime.now().toIso8601String(),
        },
      );
      final payload = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : <String, dynamic>{};
      if (response.status < 200 || response.status >= 300) {
        throw Exception('${payload['message'] ?? 'Visit gagal disimpan.'}');
      }
      if (payload['success'] != true) {
        throw Exception('${payload['message'] ?? 'Visit gagal disimpan.'}');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Visit berhasil disimpan.'),
          backgroundColor: t.success,
        ),
      );
      _photos.clear();
      final currentUserId = _supabase.auth.currentUser?.id;
      final isSpvFlow =
          _scopeSatorId != null &&
          currentUserId != null &&
          _scopeSatorId != currentUserId;
      final queryParameters = {
        'tab': 'visited',
        'month': DateFormat('yyyy-MM-dd').format(_snapshotDate),
        'date': DateFormat('yyyy-MM-dd').format(_snapshotDate),
        'storeId': widget.storeId,
      };
      if (isSpvFlow) {
        context.goNamed(
          'spv-visiting-monitor',
          queryParameters: {
            ...queryParameters,
            'satorId': _scopeSatorId,
          },
        );
      } else {
        context.goNamed(
          'sator-visiting',
          queryParameters: queryParameters,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Visit gagal disimpan. $e'),
          backgroundColor: t.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmittingVisit = false);
    }
  }

  String _contentTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }

  String _formatCommentDate(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    final date = raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '-';
    return DateFormat('dd MMM yyyy, HH:mm', 'id_ID').format(date);
  }

  String _formatCompactDate(dynamic value) {
    if (value is DateTime) {
      return DateFormat('dd MMM yy', 'id_ID').format(value);
    }
    final raw = '${value ?? ''}'.trim();
    final date = raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '-';
    return DateFormat('dd MMM yy', 'id_ID').format(date);
  }

  String _fullCurrency(int value) {
    return NumberFormat.currency(
      locale: 'id_ID',
      symbol: 'Rp',
      decimalDigits: 0,
    ).format(value);
  }

  List<Map<String, dynamic>> _asMapList(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }
    return const [];
  }

  String _formatDateLabel(dynamic value) {
    final raw = '${value ?? ''}'.trim();
    final date = raw.isEmpty ? null : DateTime.tryParse(raw)?.toLocal();
    if (date == null) return '-';
    return DateFormat('dd MMM', 'id_ID').format(date);
  }

  String _formatRangeLabel(dynamic start, dynamic end) {
    final startLabel = _formatDateLabel(start);
    final endLabel = _formatDateLabel(end);
    if (startLabel == '-' && endLabel == '-') return '-';
    if (startLabel == endLabel) return startLabel;
    return '$startLabel - $endLabel';
  }

  List<Map<String, dynamic>> _weeklySnapshots(Map<String, dynamic> row) {
    return _asMapList((row['home_snapshot'] as Map?)?['weekly_snapshots']);
  }

  String _weeklySnapshotKey(Map<String, dynamic> snapshot) {
    return [
      '${snapshot['week_number'] ?? ''}',
      '${snapshot['start_date'] ?? ''}',
      '${snapshot['end_date'] ?? ''}',
    ].join('|');
  }

  Map<String, dynamic>? _selectedWeeklySnapshot(Map<String, dynamic> row) {
    final snapshots = _weeklySnapshots(row);
    if (snapshots.isEmpty) return null;
    final promotorId = '${row['promotor_id'] ?? ''}';
    final savedKey = _selectedWeeklyKeys[promotorId];
    if (savedKey != null) {
      for (final snapshot in snapshots) {
        if (_weeklySnapshotKey(snapshot) == savedKey) return snapshot;
      }
    }
    for (final snapshot in snapshots) {
      if (snapshot['is_active'] == true) return snapshot;
    }
    return snapshots.first;
  }

  @override
  Widget build(BuildContext context) {
    final storeName = '${_store?['store_name'] ?? '-'}';
    final address = '${_store?['address'] ?? '-'}';
    final area = '${_store?['area'] ?? '-'}';
    final allbrand = _performance?['allbrand'] as Map<String, dynamic>?;
    final promotors = List<Map<String, dynamic>>.from(
      _performance?['promotors'] ?? const [],
    );

    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: const Text('Pre Visit')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        storeName,
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w800,
                          color: t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$area · $address',
                        style: PromotorText.outfit(
                          size: 9.5,
                          weight: FontWeight.w700,
                          color: t.textMutedStrong,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _tinyPill('Visit ${_visitCount}x', t.primaryAccent),
                          _tinyPill(
                            _lastVisitAt == null
                                ? '-'
                                : _formatCompactDate(_lastVisitAt),
                            t.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                _buildVisitPhotoSection(),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Row(
                    children: [
                      Expanded(child: _tabButton(0, 'Promotor')),
                      Expanded(child: _tabButton(1, 'AllBrand')),
                      Expanded(child: _tabButton(2, 'Aktivitas')),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                IndexedStack(
                  index: _tabIndex,
                  children: [
                    _buildPromotorTab(promotors),
                    _buildAllBrandTab(allbrand),
                    _buildPromotorActivityTab(promotors),
                  ],
                ),
                const SizedBox(height: 10),
                _buildNotesSection(),
                const SizedBox(height: 10),
                _buildCommentHistory(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: _isSubmittingVisit ? null : _submitVisit,
              child: _isSubmittingVisit
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      'Simpan Visit',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w800,
                        color: t.textOnAccent,
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVisitPhotoSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Foto Visit',
            style: PromotorText.outfit(
              size: 12.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ..._photos.asMap().entries.map((entry) {
                return Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.file(
                        entry.value,
                        width: 72,
                        height: 68,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -2,
                      right: -2,
                      child: InkWell(
                        onTap: () =>
                            setState(() => _photos.removeAt(entry.key)),
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: t.danger,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: t.textOnAccent,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              }),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: _photos.length >= 2 ? null : _showPhotoSourcePicker,
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: t.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.add_photo_alternate_outlined,
                        color: t.textMuted,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _photos.length >= 2 ? 'Maks 2' : 'Tambah',
                        style: PromotorText.outfit(
                          size: 7.5,
                          weight: FontWeight.w700,
                          color: t.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPromotorTab(List<Map<String, dynamic>> promotors) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: promotors.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Belum ada data promotor.',
                style: PromotorText.outfit(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: _buildMiniRangeSwitch(
                    value: _promotorRangeIndex,
                    labels: const ['Hari Ini', 'Minggu', 'Bulan'],
                    onChanged: (value) =>
                        setState(() => _promotorRangeIndex = value),
                  ),
                ),
                ...promotors.asMap().entries.map((entry) {
                  final row = entry.value;
                  final dailyTarget = _toInt(
                    row['daily_target_all_type'] ?? row['daily_target'],
                  );
                  final dailyActual = _toInt(
                    row['actual_daily_all_type'] ?? row['daily_omzet'],
                  );
                  final weeklyTarget = _toInt(row['weekly_target_all_type']);
                  final weeklyActual = _toInt(row['actual_weekly_all_type']);
                  final monthlyTarget = _toInt(
                    row['monthly_target_all_type'] ??
                        row['monthly_target_omzet'],
                  );
                  final monthlyActual = _toInt(row['actual_monthly_all_type']);

                  final dailyFocusTarget = _toInt(
                    row['daily_focus_target'] ?? row['focus_target'],
                  );
                  final dailyFocusActual = _toInt(
                    row['actual_daily_focus'] ?? row['focus_units'],
                  );
                  final weeklyFocusTarget = _toInt(row['weekly_focus_target']);
                  final weeklyFocusActual = _toInt(row['actual_weekly_focus']);
                  final monthlyFocusTarget = _toInt(
                    row['monthly_focus_target'],
                  );
                  final monthlyFocusActual = _toInt(
                    row['actual_monthly_focus'],
                  );

                  final vastTarget = _toInt(row['vast_target']);
                  final vastActual = _toInt(row['vast_month_submissions']);
                  final vastPct = vastTarget > 0
                      ? (vastActual / vastTarget) * 100
                      : 0.0;
                  final dailySpecialRows = _asMapList(
                    row['daily_special_rows'],
                  );
                  final weeklySpecialRows = _asMapList(
                    row['weekly_special_rows'],
                  );
                  final monthlySpecialRows = _asMapList(
                    row['monthly_special_rows'],
                  );
                  final selectedWeeklySnapshot = _selectedWeeklySnapshot(row);
                  final selectedWeeklyKey = selectedWeeklySnapshot == null
                      ? null
                      : _weeklySnapshotKey(selectedWeeklySnapshot);
                  final selectedWeeklyLabel = _formatRangeLabel(
                    selectedWeeklySnapshot?['start_date'],
                    selectedWeeklySnapshot?['end_date'],
                  );
                  final weeklyResolvedTarget = _toInt(
                    selectedWeeklySnapshot?['target_weekly_all_type'] ??
                        weeklyTarget,
                  );
                  final weeklyResolvedActual = _toInt(
                    selectedWeeklySnapshot?['actual_weekly_all_type'] ??
                        weeklyActual,
                  );
                  final weeklyResolvedFocusTarget = _toInt(
                    selectedWeeklySnapshot?['target_weekly_focus'] ??
                        weeklyFocusTarget,
                  );
                  final weeklyResolvedFocusActual = _toInt(
                    selectedWeeklySnapshot?['actual_weekly_focus'] ??
                        weeklyFocusActual,
                  );
                  final weeklyResolvedAchievement = _toDouble(
                    selectedWeeklySnapshot?['achievement_weekly_all_type_pct'] ??
                        row['achievement_weekly_all_type_pct'],
                  ).toStringAsFixed(0);
                  final weekLabel = _formatRangeLabel(
                    row['week_start'] ?? row['active_week_start'],
                    row['week_end'] ?? row['active_week_end'],
                  );
                  final monthLabel = _formatRangeLabel(
                    row['month_start'] ?? row['period_start'],
                    row['month_end'] ?? row['period_end'],
                  );

                  final selectedTitle = switch (_promotorRangeIndex) {
                    0 => '',
                    1 => 'Minggu',
                    _ => 'Bulanan',
                  };
                  final selectedSubtitle = switch (_promotorRangeIndex) {
                    0 => '',
                    1 =>
                      selectedWeeklySnapshot == null
                          ? weekLabel
                          : selectedWeeklyLabel,
                    _ => monthLabel,
                  };
                  final selectedOmzetTarget = switch (_promotorRangeIndex) {
                    0 => _fullCurrency(dailyTarget),
                    1 => _fullCurrency(weeklyResolvedTarget),
                    _ => _fullCurrency(monthlyTarget),
                  };
                  final selectedOmzetActual = switch (_promotorRangeIndex) {
                    0 => _fullCurrency(dailyActual),
                    1 => _fullCurrency(weeklyResolvedActual),
                    _ => _fullCurrency(monthlyActual),
                  };
                  final selectedFocusTarget = switch (_promotorRangeIndex) {
                    0 => '$dailyFocusTarget',
                    1 => '$weeklyResolvedFocusTarget',
                    _ => '$monthlyFocusTarget',
                  };
                  final selectedFocusActual = switch (_promotorRangeIndex) {
                    0 => '$dailyFocusActual',
                    1 => '$weeklyResolvedFocusActual',
                    _ => '$monthlyFocusActual',
                  };
                  final selectedAchievement = switch (_promotorRangeIndex) {
                    0 => _toDouble(
                      row['achievement_daily_all_type_pct'],
                    ).toStringAsFixed(0),
                    1 => weeklyResolvedAchievement,
                    _ => _toDouble(
                      row['achievement_monthly_all_type_pct'],
                    ).toStringAsFixed(0),
                  };
                  final selectedSpecialRows = switch (_promotorRangeIndex) {
                    0 => dailySpecialRows,
                    1 => weeklySpecialRows,
                    _ => monthlySpecialRows,
                  };
                  final selectedSpecialTitle = switch (_promotorRangeIndex) {
                    0 => 'Tipe Khusus Harian',
                    1 => 'Tipe Khusus Mingguan',
                    _ => 'Tipe Khusus Bulanan',
                  };

                  return Container(
                    padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                    decoration: BoxDecoration(
                      border: entry.key == promotors.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: t.surface3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['promotor_name'] ?? 'Promotor'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: PromotorText.outfit(
                            size: 12,
                            weight: FontWeight.w800,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildRangeMetricCard(
                          title: selectedTitle,
                          subtitle: selectedSubtitle,
                          primaryValue: selectedOmzetActual,
                          primaryTarget: selectedOmzetTarget,
                          achievement: selectedAchievement,
                          secondaryValue: selectedFocusActual,
                          secondaryTarget: selectedFocusTarget,
                          showHeader: _promotorRangeIndex != 0,
                          primaryLabel: _promotorRangeIndex == 0
                              ? 'Pencapaian'
                              : 'Omzet',
                          targetLabel: _promotorRangeIndex == 0
                              ? 'Target'
                              : 'Target',
                          showSecondaryMetric: _promotorRangeIndex != 0,
                        ),
                        if (_promotorRangeIndex == 1 &&
                            _weeklySnapshots(row).length > 1) ...[
                          const SizedBox(height: 8),
                          _buildWeeklySelectorStrip(
                            snapshots: _weeklySnapshots(row),
                            selectedKey: selectedWeeklyKey,
                            onSelected: (key) {
                              setState(() {
                                _selectedWeeklyKeys['${row['promotor_id'] ?? ''}'] =
                                    key;
                              });
                            },
                          ),
                        ],
                        if (selectedSpecialRows.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _buildSpecialRowsSection(
                            title: selectedSpecialTitle,
                            rows: selectedSpecialRows,
                            rangeLabel: selectedSubtitle,
                          ),
                        ],
                        const SizedBox(height: 6),
                        _buildRangeMetricCard(
                          title: 'VAST Finance',
                          subtitle: monthLabel,
                          primaryValue: '$vastActual',
                          primaryTarget: '$vastTarget',
                          achievement: vastPct.toStringAsFixed(0),
                          primaryLabel: 'Pencapaian',
                          targetLabel: 'Target',
                          secondaryValue: '${_toInt(row['vast_month_acc'])}',
                          secondaryTarget:
                              '${_toInt(row['vast_month_pending'])}',
                          secondaryLabel: 'ACC / Pending',
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _buildAllBrandTab(Map<String, dynamic>? allbrand) {
    final targetDate = DateTime.tryParse('${allbrand?['report_date'] ?? ''}');
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: AllbrandReportDetailPanel(
        reportId: '${allbrand?['report_id'] ?? ''}'.trim().isEmpty
            ? null
            : '${allbrand?['report_id']}',
        storeId: widget.storeId,
        initialStoreName: '${_store?['store_name'] ?? '-'}',
        targetDate: targetDate,
        padding: const EdgeInsets.all(10),
      ),
    );
  }

  Widget _buildPromotorActivityTab(List<Map<String, dynamic>> promotors) {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: promotors.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Belum ada data aktivitas promotor.',
                style: PromotorText.outfit(
                  size: 10.5,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                  child: _buildMiniRangeSwitch(
                    value: _activityRangeIndex,
                    labels: const ['Minggu', 'Bulan'],
                    onChanged: (value) =>
                        setState(() => _activityRangeIndex = value),
                  ),
                ),
                ...promotors.asMap().entries.map((entry) {
                  final row = entry.value;
                  final weekLabel = _formatRangeLabel(
                    row['week_start'] ?? row['active_week_start'],
                    row['week_end'] ?? row['active_week_end'],
                  );
                  final monthLabel = _formatRangeLabel(
                    row['month_start'] ?? row['period_start'],
                    row['month_end'] ?? row['period_end'],
                  );
                  final weekAttendanceDays = _toInt(
                    row['week_attendance_days'],
                  );
                  final weekPromotionCount = _toInt(
                    row['week_promotion_count'],
                  );
                  final weekFollowerCount = _toInt(row['week_follower_count']);
                  final attendanceDays =
                      _toInt(row['month_attendance_days']) > 0
                      ? _toInt(row['month_attendance_days'])
                      : (row['clock_in'] == true ? 1 : 0);
                  final promotionCount = _toInt(row['month_promotion_count']);
                  final followerCount = _toInt(row['month_follower_count']);
                  final weekPermissionCount = _toInt(
                    row['week_permission_count'],
                  );
                  final monthPermissionCount = _toInt(
                    row['month_permission_count'],
                  );
                  final weekAbsenceCount = _toInt(row['week_absence_count']);
                  final monthAbsenceCount = _toInt(row['month_absence_count']);

                  final selectedRangeLabel = _activityRangeIndex == 0
                      ? 'Minggu aktif • $weekLabel'
                      : 'Bulanan • $monthLabel';
                  final selectedAttendance = _activityRangeIndex == 0
                      ? weekAttendanceDays
                      : attendanceDays;
                  final selectedAbsence = _activityRangeIndex == 0
                      ? weekAbsenceCount
                      : monthAbsenceCount;
                  final selectedPermission = _activityRangeIndex == 0
                      ? weekPermissionCount
                      : monthPermissionCount;
                  final selectedPromo = _activityRangeIndex == 0
                      ? weekPromotionCount
                      : promotionCount;
                  final selectedFollower = _activityRangeIndex == 0
                      ? weekFollowerCount
                      : followerCount;

                  return Container(
                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                    decoration: BoxDecoration(
                      border: entry.key == promotors.length - 1
                          ? null
                          : Border(bottom: BorderSide(color: t.surface3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${row['promotor_name'] ?? 'Promotor'}',
                          style: PromotorText.outfit(
                            size: 11.5,
                            weight: FontWeight.w800,
                            color: t.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          selectedRangeLabel,
                          style: PromotorText.outfit(
                            size: 9.2,
                            weight: FontWeight.w800,
                            color: t.textMutedStrong,
                          ),
                        ),
                        const SizedBox(height: 4),
                        const SizedBox(height: 2),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _activityStatCard(
                              'Hadir',
                              '$selectedAttendance',
                              t.primaryAccent,
                            ),
                            _activityStatCard(
                              'Tidak Absen',
                              '$selectedAbsence',
                              t.danger,
                            ),
                            _activityStatCard(
                              'Izin',
                              '$selectedPermission',
                              t.warning,
                            ),
                            _activityStatCard(
                              'Promo',
                              '$selectedPromo',
                              t.info,
                            ),
                            _activityStatCard(
                              'Follower',
                              '$selectedFollower',
                              t.success,
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
    );
  }

  Widget _buildMiniRangeSwitch({
    required int value,
    required List<String> labels,
    required ValueChanged<int> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final active = value == index;
          return Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => onChanged(index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                decoration: BoxDecoration(
                  color: active
                      ? t.primaryAccent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  labels[index],
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: 9.6,
                    weight: FontWeight.w800,
                    color: active ? t.primaryAccent : t.textMutedStrong,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildNotesSection() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Catatan Visit',
            style: PromotorText.outfit(
              size: 12.5,
              weight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _commentController,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'Tulis catatan hasil visit',
              filled: true,
              fillColor: t.surface2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.surface3),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.surface3),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: t.primaryAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRangeMetricCard({
    required String title,
    required String subtitle,
    required String primaryValue,
    required String primaryTarget,
    required String achievement,
    String primaryLabel = 'Pencapaian',
    String targetLabel = 'Target',
    String secondaryLabel = 'Fokus',
    String? secondaryValue,
    String? secondaryTarget,
    bool showHeader = true,
    bool showSecondaryMetric = true,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: PromotorText.outfit(
                      size: 10.5,
                      weight: FontWeight.w800,
                      color: t.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: t.primaryAccent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '$achievement%',
                    style: PromotorText.outfit(
                      size: 8.5,
                      weight: FontWeight.w800,
                      color: t.primaryAccent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: PromotorText.outfit(
                size: 8.8,
                weight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
            const SizedBox(height: 7),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _metricPair(primaryLabel, primaryValue)),
              const SizedBox(width: 8),
              Expanded(child: _metricPair(targetLabel, primaryTarget)),
            ],
          ),
          if (showSecondaryMetric) ...[
            const SizedBox(height: 8),
            _metricPair(
              secondaryLabel,
              secondaryTarget == null
                  ? (secondaryValue ?? '-')
                  : '${secondaryValue ?? '-'} / $secondaryTarget',
            ),
          ],
        ],
      ),
    );
  }

  Widget _metricPair(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: PromotorText.outfit(
            size: 8.6,
            weight: FontWeight.w700,
            color: t.textMutedStrong,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: PromotorText.outfit(
            size: 9.5,
            weight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildWeeklySelectorStrip({
    required List<Map<String, dynamic>> snapshots,
    required String? selectedKey,
    required ValueChanged<String> onSelected,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: List<Widget>.generate(snapshots.length, (index) {
          final snapshot = snapshots[index];
          final weekKey = _weeklySnapshotKey(snapshot);
          final isSelected = weekKey == selectedKey;
          final isActive = snapshot['is_active'] == true;
          final isFuture = snapshot['is_future'] == true;
          final weekNumber = _toInt(snapshot['week_number']);
          final rangeLabel = _formatRangeLabel(
            snapshot['start_date'],
            snapshot['end_date'],
          );
          final stateLabel = isActive
              ? 'Aktif'
              : isFuture
              ? 'Next'
              : 'Selesai';

          return Padding(
            padding: EdgeInsets.only(
              right: index == snapshots.length - 1 ? 0 : 8,
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => onSelected(weekKey),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: 118,
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                decoration: BoxDecoration(
                  color: isSelected ? t.primaryAccentSoft : t.surface1,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? t.primaryAccent
                        : isActive
                        ? t.warning.withValues(alpha: 0.4)
                        : t.surface3,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Minggu $weekNumber',
                            style: PromotorText.outfit(
                              size: 9.2,
                              weight: FontWeight.w800,
                              color: t.textPrimary,
                            ),
                          ),
                        ),
                        Text(
                          stateLabel,
                          style: PromotorText.outfit(
                            size: 7.8,
                            weight: FontWeight.w800,
                            color: isSelected
                                ? t.primaryAccent
                                : isActive
                                ? t.warning
                                : t.textMutedStrong,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      rangeLabel,
                      style: PromotorText.outfit(
                        size: 8.2,
                        weight: FontWeight.w700,
                        color: t.textMutedStrong,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _activityStatCard(String label, String value, Color tone) {
    return Container(
      width: 94,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: PromotorText.outfit(
              size: 8.2,
              weight: FontWeight.w700,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpecialRowsSection({
    required String title,
    required List<Map<String, dynamic>> rows,
    required String rangeLabel,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: t.surface1,
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
                  title,
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              Text(
                rangeLabel,
                style: PromotorText.outfit(
                  size: 8.8,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ...rows.take(6).map((detail) {
            final bundleName = (detail['bundle_name'] ?? 'Tipe Khusus')
                .toString();
            final targetQty = _toInt(detail['target_qty']);
            final actualQty = _toInt(detail['actual_qty']);
            final pct = _toDouble(
              detail['pct'] ?? detail['achievement_pct'],
            ).toStringAsFixed(0);
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      bundleName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 9.4,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$actualQty / $targetQty',
                    style: PromotorText.outfit(
                      size: 8.8,
                      weight: FontWeight.w700,
                      color: t.textMutedStrong,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _tinyPill('$pct%', t.warning),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildCommentHistory() {
    return Container(
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Text(
              'Riwayat Catatan',
              style: PromotorText.outfit(
                size: 12.5,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
          ),
          if (_comments.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Text(
                'Belum ada catatan.',
                style: PromotorText.outfit(
                  size: 11,
                  weight: FontWeight.w700,
                  color: t.textMutedStrong,
                ),
              ),
            )
          else
            ..._comments.asMap().entries.map((entry) {
              final row = entry.value;
              final author = row['users']?['full_name']?.toString() ?? 'User';
              return Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  border: entry.key == _comments.length - 1
                      ? null
                      : Border(bottom: BorderSide(color: t.surface3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${row['comment_text'] ?? '-'}',
                      style: PromotorText.outfit(
                        size: 11.5,
                        weight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$author · ${_formatCommentDate(row['created_at'])}',
                      style: PromotorText.outfit(
                        size: 9,
                        weight: FontWeight.w700,
                        color: t.textMutedStrong,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _tabButton(int index, String label) {
    final active = _tabIndex == index;
    final tone = active ? t.primaryAccent : t.textMutedStrong;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () => setState(() => _tabIndex = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(
          color: active
              ? t.primaryAccent.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: PromotorText.outfit(
            size: 10,
            weight: FontWeight.w800,
            color: tone,
          ),
        ),
      ),
    );
  }

  Widget _tinyPill(String text, Color tone, {Color? foreground}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 8,
          weight: FontWeight.w800,
          color: foreground ?? tone,
        ),
      ),
    );
  }
}
