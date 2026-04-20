import '../../../../../../../ui/promotor/promotor_theme.dart';
// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../ui/promotor/promotor.dart';

class AktivitasTimPage extends StatefulWidget {
  final String? scopeSatorId;
  final bool embedded;
  final String title;
  final bool showBackButton;

  const AktivitasTimPage({
    super.key,
    this.scopeSatorId,
    this.embedded = false,
    this.title = 'Aktivitas Tim',
    this.showBackButton = true,
  });

  @override
  State<AktivitasTimPage> createState() => _AktivitasTimPageState();
}

class _AktivitasTimPageState extends State<AktivitasTimPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  static const _taskKeys = [
    'clock_in',
    'sell_out',
    'stock_input',
    'stock_validation',
    'promotion',
    'follower',
    'allbrand',
    'vast',
  ];
  static const _taskMeta = [
    ('clock_in', 'Absen', Icons.access_time_rounded),
    ('sell_out', 'Jualan', Icons.shopping_bag_rounded),
    ('stock_input', 'Input Stok', Icons.inventory_2_rounded),
    ('stock_validation', 'Validasi', Icons.fact_check_rounded),
    ('promotion', 'Promo', Icons.campaign_rounded),
    ('follower', 'Follower', Icons.group_add_rounded),
    ('allbrand', 'AllBrand', Icons.analytics_rounded),
    ('vast', 'VAST', Icons.account_balance_wallet_rounded),
  ];

  DateTime _selectedDate = DateTime.now();
  List<Map<String, dynamic>> _storeData = [];
  Set<String> _expandedStoreIds = {};
  bool _isLoading = true;
  String? _errorMessage;
  String _viewFilter = 'all';

  String? get _targetSatorId {
    final scoped = widget.scopeSatorId?.trim();
    if (scoped != null && scoped.isNotEmpty) return scoped;
    return _supabase.auth.currentUser?.id;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final userId = _targetSatorId;
      if (userId == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _errorMessage =
              'Sesi login tidak ditemukan. Silakan masuk ulang untuk melihat aktivitas tim.';
          _storeData = [];
        });
        return;
      }

      final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final data = await _supabase.rpc(
        'get_sator_aktivitas_tim',
        params: {'p_sator_id': userId, 'p_date': dateStr},
      );

      if (!mounted) return;
      final response = data is Map<String, dynamic>
          ? data
          : <String, dynamic>{
              'summary': const <String, dynamic>{},
              'stores': data ?? const [],
            };
      final storeList = List<Map<String, dynamic>>.from(
        response['stores'] ?? const [],
      );
      setState(() {
        _storeData = storeList;
        _expandedStoreIds = <String>{};
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading aktivitas tim: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _storeData = [];
        _errorMessage =
            'Aktivitas tim gagal dimuat. Tarik ke bawah atau coba lagi beberapa saat lagi.';
      });
    }
  }

  List<Map<String, dynamic>> _promotorsOf(Map<String, dynamic> store) {
    return List<Map<String, dynamic>>.from(store['promotors'] ?? const []);
  }

  String _storeIdOf(Map<String, dynamic> store) =>
      (store['store_id'] ?? '').toString();

  int _completedCount(Map<String, dynamic> promotor) {
    return int.tryParse('${promotor['completed_tasks'] ?? ''}') ?? 0;
  }

  String _attendanceCategoryLabel(String value) {
    switch (value) {
      case 'late':
        return 'Terlambat';
      case 'travel':
        return 'Perjalanan Dinas';
      case 'special_permission':
        return 'Izin Atasan';
      case 'system_issue':
        return 'Kendala Sistem';
      case 'sick':
        return 'Sakit';
      case 'leave':
        return 'Izin';
      case 'management_holiday':
        return 'Libur Management';
      case 'normal':
        return 'Masuk Kerja';
      default:
        return '';
    }
  }

  Color _attendanceCategoryTone(String value) {
    switch (value) {
      case 'late':
        return t.warning;
      case 'travel':
        return t.info;
      case 'special_permission':
        return t.primaryAccent;
      case 'system_issue':
        return t.danger;
      case 'sick':
        return t.danger;
      case 'leave':
        return t.warning;
      case 'management_holiday':
        return t.textMutedStrong;
      case 'normal':
        return t.success;
      default:
        return t.success;
    }
  }

  IconData _attendanceCategoryIcon(String value, {required bool reported}) {
    if (!reported) return Icons.error_outline_rounded;
    switch (value) {
      case 'late':
        return Icons.watch_later_rounded;
      case 'travel':
        return Icons.route_rounded;
      case 'special_permission':
        return Icons.verified_user_rounded;
      case 'system_issue':
        return Icons.warning_amber_rounded;
      case 'sick':
        return Icons.local_hospital_rounded;
      case 'leave':
        return Icons.event_busy_rounded;
      case 'management_holiday':
        return Icons.beach_access_rounded;
      case 'normal':
        return Icons.storefront_rounded;
      default:
        return Icons.check_circle_rounded;
    }
  }

  bool _matchesFilter(Map<String, dynamic> store) {
    final totalPromotors =
        int.tryParse('${store['total_promotors'] ?? ''}') ?? 0;
    final activePromotors =
        int.tryParse('${store['active_promotors'] ?? ''}') ?? 0;
    final attentionPromotors =
        int.tryParse('${store['attention_promotors'] ?? ''}') ?? 0;
    final completedTasks =
        int.tryParse('${store['completed_tasks'] ?? ''}') ?? 0;
    final totalTasks = int.tryParse('${store['total_tasks'] ?? ''}') ?? 0;
    switch (_viewFilter) {
      case 'attention':
        return attentionPromotors > 0;
      case 'active':
        return activePromotors > 0;
      case 'done':
        return totalPromotors > 0 &&
            totalTasks > 0 &&
            completedTasks == totalTasks;
      default:
        return true;
    }
  }

  List<Map<String, dynamic>> _filteredStores() {
    final stores = _storeData.where(_matchesFilter).toList();
    stores.sort((a, b) {
      final aPct = _storeCompletionPct(a);
      final bPct = _storeCompletionPct(b);
      return _viewFilter == 'done'
          ? bPct.compareTo(aPct)
          : aPct.compareTo(bPct);
    });
    return stores;
  }

  int _storeCompletionPct(Map<String, dynamic> store) {
    return int.tryParse('${store['completion_percent'] ?? ''}') ?? 0;
  }

  Color _progressColor(int percent) {
    if (percent >= 100) return t.success;
    if (percent >= 70) return t.primaryAccent;
    if (percent >= 40) return t.warning;
    return t.danger;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now().subtract(const Duration(days: 90)),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
      _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final filteredStores = _filteredStores();

    if (widget.embedded) {
      return _buildBody(filteredStores);
    }

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: _buildBody(filteredStores),
      ),
    );
  }

  Widget _buildBody(List<Map<String, dynamic>> filteredStores) {
    return RefreshIndicator(
      onRefresh: _loadData,
      color: t.primaryAccent,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(0, widget.embedded ? 10 : 18, 0, 120),
        children: [
          if (!widget.embedded) ...[
            _buildHeader(),
            const SizedBox(height: 8),
          ],
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.only(top: 96),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_errorMessage != null)
            _buildStateCard(
              title: 'Aktivitas Tim Belum Bisa Dimuat',
              message: _errorMessage!,
              icon: Icons.error_outline_rounded,
              accent: t.danger,
              showRetry: true,
            )
          else if (filteredStores.isEmpty)
            _buildStateCard(
              title: 'Belum Ada Aktivitas',
              message: _storeData.isEmpty
                  ? 'Tidak ada aktivitas tim pada tanggal ini.'
                  : 'Tidak ada toko yang cocok dengan filter saat ini.',
              icon: Icons.inbox_outlined,
              accent: t.warning,
            )
          else ...[
            _buildFilterBar(filteredStores.length),
            const SizedBox(height: 10),
            ...filteredStores.map(_buildStoreCard),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final today = DateTime.now();
    final selected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    final todayDate = DateTime(today.year, today.month, today.day);
    final isToday = selected == todayDate;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (widget.showBackButton) ...[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.surface3),
                  ),
                  child: IconButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: Icon(
                      Icons.arrow_back_ios_new_rounded,
                      size: 16,
                      color: t.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: PromotorText.outfit(
                        size: 18,
                        weight: FontWeight.w800,
                        color: t.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: t.surface1,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.surface3),
                ),
                child: Text(
                  '${_storeData.length} toko',
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w700,
                    color: t.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: t.surface3),
            ),
            child: Row(
              children: [
                _dateControl(
                  icon: Icons.chevron_left_rounded,
                  onTap: () {
                    setState(
                      () => _selectedDate = _selectedDate.subtract(
                        const Duration(days: 1),
                      ),
                    );
                    _loadData();
                  },
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: _pickDate,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            t.warningSoft,
                            t.warning.withValues(alpha: 0.06),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.primaryAccentGlow),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.event_rounded,
                            color: t.primaryAccent,
                            size: 15,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              DateFormat(
                                'EEE, d MMM yyyy',
                                'id_ID',
                              ).format(_selectedDate),
                              overflow: TextOverflow.ellipsis,
                              style: PromotorText.outfit(
                                size: 13,
                                weight: FontWeight.w700,
                                color: t.textPrimary,
                              ),
                            ),
                          ),
                          if (isToday) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: t.primaryAccent,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                'Hari Ini',
                                style: PromotorText.outfit(
                                  size: 8,
                                  weight: FontWeight.w800,
                                  color: t.textOnAccent,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _dateControl(
                  icon: Icons.chevron_right_rounded,
                  onTap: selected.isBefore(todayDate)
                      ? () {
                          setState(
                            () => _selectedDate = _selectedDate.add(
                              const Duration(days: 1),
                            ),
                          );
                          _loadData();
                        }
                      : null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateControl({required IconData icon, VoidCallback? onTap}) {
    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: t.surface2,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: t.surface3),
          ),
          child: Icon(icon, color: t.textSecondary, size: 18),
        ),
      ),
    );
  }

  Widget _buildFilterBar(int visibleCount) {
    final filters = [
      ('all', 'Semua'),
      ('attention', 'Perlu Perhatian'),
      ('active', 'Aktif'),
      ('done', 'Selesai'),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: filters.map((entry) {
                  final isActive = _viewFilter == entry.$1;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () => setState(() => _viewFilter = entry.$1),
                      borderRadius: BorderRadius.circular(999),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: isActive ? t.primaryAccent : t.surface1,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: isActive ? t.primaryAccent : t.surface3,
                          ),
                        ),
                        child: Text(
                          entry.$2,
                          style: PromotorText.outfit(
                            size: 10,
                            weight: FontWeight.w700,
                            color: isActive ? t.textOnAccent : t.textSecondary,
                          ),
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$visibleCount toko',
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreCard(Map<String, dynamic> store) {
    final storeId = _storeIdOf(store);
    final promotors = _promotorsOf(store);
    final percent = _storeCompletionPct(store);
    final accent = _progressColor(percent);
    final isExpanded = _expandedStoreIds.contains(storeId);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedStoreIds.remove(storeId);
                } else {
                  _expandedStoreIds.add(storeId);
                }
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: accent.withValues(alpha: 0.2)),
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      color: accent,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          (store['store_name'] ?? '-').toString(),
                          style: PromotorText.outfit(
                            size: 13,
                            weight: FontWeight.w700,
                            color: t.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        const SizedBox(height: 6),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            minHeight: 5,
                            value: percent / 100,
                            backgroundColor: t.surface3,
                            valueColor: AlwaysStoppedAnimation<Color>(accent),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '$percent%',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w800,
                          color: accent,
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: t.textMuted,
                        size: 18,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            Divider(height: 1, color: t.surface3),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                children: promotors.map(_buildPromotorPanel).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPromotorPanel(Map<String, dynamic> promotor) {
    final completed = _completedCount(promotor);
    final percent =
        int.tryParse('${promotor['completion_percent'] ?? ''}') ??
        ((completed / _taskKeys.length) * 100).round();
    final accent = _progressColor(percent);
    final attendanceCategory = (promotor['attendance_category'] ?? '')
        .toString()
        .trim();
    final attendanceLabel = promotor['clock_in'] == true
        ? (_attendanceCategoryLabel(attendanceCategory).isEmpty
              ? 'Hadir'
              : _attendanceCategoryLabel(attendanceCategory))
        : 'Belum Lapor';
    final attendanceTone = promotor['clock_in'] == true
        ? _attendanceCategoryTone(attendanceCategory)
        : t.danger;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.18)),
                ),
                child: Center(
                  child: Text(
                    _initials((promotor['name'] ?? 'P').toString()),
                    style: PromotorText.outfit(
                      size: 11,
                      weight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      (promotor['name'] ?? 'Promotor').toString(),
                      style: PromotorText.outfit(
                        size: 12,
                        weight: FontWeight.w700,
                        color: t.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _miniTag('$completed/${_taskKeys.length} tugas', accent),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: attendanceTone.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: attendanceTone.withValues(alpha: 0.24),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _attendanceCategoryIcon(
                                  attendanceCategory,
                                  reported: promotor['clock_in'] == true,
                                ),
                                size: 11,
                                color: attendanceTone,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                attendanceLabel,
                                style: PromotorText.outfit(
                                  size: 8.5,
                                  weight: FontWeight.w800,
                                  color: attendanceTone,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$percent%',
                  style: PromotorText.outfit(
                    size: 10,
                    weight: FontWeight.w800,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _taskMeta.map((meta) {
              final done = promotor[meta.$1] == true;
              return _buildTaskChip(label: meta.$2, icon: meta.$3, done: done);
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTaskChip({
    required String label,
    required IconData icon,
    required bool done,
  }) {
    final color = done ? t.success : t.textMutedStrong;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: done ? t.success.withValues(alpha: 0.12) : t.textOnAccent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: done ? t.success.withValues(alpha: 0.25) : t.surface3,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: PromotorText.outfit(
              size: 7.5,
              weight: FontWeight.w700,
              color: color,
            ),
          ),
          if (done) ...[
            const SizedBox(width: 3),
            Icon(Icons.check_circle_rounded, size: 12, color: t.success),
          ],
        ],
      ),
    );
  }

  Widget _miniTag(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: PromotorText.outfit(
          size: 8.5,
          weight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Widget _buildStateCard({
    required String title,
    required String message,
    required IconData icon,
    required Color accent,
    bool showRetry = false,
  }) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 48, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 54, color: accent),
          const SizedBox(height: 14),
          Text(
            title,
            style: PromotorText.display(size: 18, color: t.textPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w700,
              color: t.textMuted,
            ),
          ),
          if (showRetry) ...[
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _loadData,
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: accent.withValues(alpha: 0.4)),
              ),
              child: const Text('Coba Lagi'),
            ),
          ],
        ],
      ),
    );
  }

  String _initials(String name) {
    final parts = name
        .split(' ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .take(2)
        .toList();
    if (parts.isEmpty) return 'P';
    return parts.map((part) => part[0].toUpperCase()).join();
  }
}
