import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../chat/repository/chat_repository.dart';
import '../../../../ui/promotor/promotor.dart';

class TokoDetailPage extends StatefulWidget {
  final String storeId;

  const TokoDetailPage({super.key, required this.storeId});

  @override
  State<TokoDetailPage> createState() => _TokoDetailPageState();
}

class _TokoDetailPageState extends State<TokoDetailPage> {
  FieldThemeTokens get t => context.fieldTokens;
  static const _activityItems = [
    ('clock_in', 'Absen', Icons.access_time_rounded),
    ('sell_out', 'Jualan', Icons.point_of_sale_rounded),
    ('stock_input', 'Input Stok', Icons.inventory_2_rounded),
    ('stock_validation', 'Validasi', Icons.fact_check_rounded),
    ('promotion', 'Promo', Icons.campaign_rounded),
    ('follower', 'Follower', Icons.group_add_rounded),
    ('allbrand', 'AllBrand', Icons.analytics_rounded),
  ];

  final _supabase = Supabase.instance.client;
  final _chatRepository = ChatRepository();

  Map<String, dynamic>? _storeData;
  Map<String, dynamic>? _allbrandData;
  List<Map<String, dynamic>> _promotors = const [];
  bool _isLoading = true;
  String? _errorMessage;
  String? _warningMessage;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _warningMessage = null;
    });

    try {
      final store = await _supabase
          .from('stores')
          .select('*')
          .eq('id', widget.storeId)
          .isFilter('deleted_at', null)
          .maybeSingle();

      if (store == null) {
        throw Exception('Toko tidak ditemukan atau sudah tidak aktif.');
      }

      final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
      final checklistFuture = _supabase.rpc(
        'get_store_promotor_checklist',
        params: {'p_store_id': widget.storeId, 'p_date': dateKey},
      );
      final allbrandFuture = _chatRepository.getStorePerformanceData(
        storeId: widget.storeId,
        date: _selectedDate,
      );

      final checklistResult = await checklistFuture;
      Map<String, dynamic>? performance;

      try {
        performance = await allbrandFuture;
      } catch (_) {
        _warningMessage =
            'Ringkasan AllBrand belum berhasil dimuat. Checklist aktivitas tetap tersedia.';
      }

      if (!mounted) return;
      setState(() {
        _storeData = Map<String, dynamic>.from(store);
        _promotors = List<Map<String, dynamic>>.from(
          checklistResult ?? const [],
        );
        _allbrandData = performance?['allbrand'] as Map<String, dynamic>?;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Detail toko gagal dimuat. ${_humanizeError(e)}';
      });
    }
  }

  String _humanizeError(Object error) {
    final raw = error.toString().trim();
    if (raw.isEmpty) return 'Coba lagi beberapa saat lagi.';
    return raw.replaceFirst('Exception: ', '');
  }

  int _completedActivities(Map<String, dynamic> promotor) {
    return _activityItems.where((item) => promotor[item.$1] == true).length;
  }

  bool get _canMoveForward {
    final today = DateTime.now();
    final normalizedToday = DateTime(today.year, today.month, today.day);
    final normalizedSelected = DateTime(
      _selectedDate.year,
      _selectedDate.month,
      _selectedDate.day,
    );
    return normalizedSelected.isBefore(normalizedToday);
  }

  Color _progressColor(double progress) {
    if (progress >= 0.85) return t.success;
    if (progress >= 0.5) return t.warning;
    return t.danger;
  }

  Color _statusTone(bool complete) {
    return complete ? t.success : t.textMutedStrong;
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

  String _storeAreaLabel() {
    final area = '${_storeData?['area'] ?? '-'}'.trim();
    return area.isEmpty ? '-' : area;
  }

  String _storeGradeLabel() {
    final grade = '${_storeData?['grade'] ?? '-'}'.trim();
    return grade.isEmpty ? '-' : grade.toUpperCase();
  }

  String _storeStatusLabel() {
    final status = '${_storeData?['status'] ?? '-'}'.trim();
    return status.isEmpty ? '-' : status;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      body: SafeArea(
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
            : RefreshIndicator(
                color: t.primaryAccent,
                backgroundColor: t.surface1,
                onRefresh: _loadData,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTopBar(context),
                            const SizedBox(height: 18),
                            if (_errorMessage != null) ...[
                              _buildErrorState(),
                              const SizedBox(height: 12),
                            ] else ...[
                              _buildHeroCard(context),
                              const SizedBox(height: 12),
                              if (_warningMessage != null) ...[
                                _buildWarningCard(),
                                const SizedBox(height: 12),
                              ],
                              _buildStoreSummary(),
                              const SizedBox(height: 12),
                              _buildAllbrandSection(),
                              const SizedBox(height: 12),
                              _buildChecklistHeader(),
                              const SizedBox(height: 10),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_errorMessage == null)
                      _promotors.isEmpty
                          ? SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  0,
                                  18,
                                  24,
                                ),
                                child: _buildEmptyChecklist(),
                              ),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                              sliver: SliverList.separated(
                                itemBuilder: (context, index) =>
                                    _buildPromotorCard(_promotors[index]),
                                separatorBuilder: (context, index) =>
                                    const SizedBox(height: 12),
                                itemCount: _promotors.length,
                              ),
                            ),
                  ],
                ),
              ),
      ),
      floatingActionButton: _errorMessage == null
          ? FloatingActionButton.extended(
              backgroundColor: t.primaryAccent,
              foregroundColor: t.textOnAccent,
              onPressed: () =>
                  context.push('/sator/toko/${widget.storeId}/chat'),
              icon: const Icon(Icons.chat_bubble_rounded),
              label: Text(
                'Chat Toko',
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w700,
                  color: t.textOnAccent,
                ),
              ),
            )
          : null,
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final t = context.fieldTokens;
    return Row(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => context.pop(),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: t.surface3),
            ),
            child: Icon(Icons.arrow_back_rounded, color: t.textPrimary),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: t.surface3),
          ),
          child: Text(
            'TOKO DETAIL',
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w800,
              color: t.primaryAccentLight,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeroCard(BuildContext context) {
    final t = context.fieldTokens;
    final completedTotal = _promotors.fold<int>(
      0,
      (sum, item) => sum + _completedActivities(item),
    );
    final totalTasks = _promotors.length * _activityItems.length;
    final progress = totalTasks == 0 ? 0.0 : completedTotal / totalTasks;
    final dateLabel = DateFormat(
      'EEEE, d MMM yyyy',
      'id_ID',
    ).format(_selectedDate);
    final color = _progressColor(progress);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [t.surface2, t.background],
        ),
        border: Border.all(color: t.surface3),
        boxShadow: [
          BoxShadow(
            color: t.background.withValues(alpha: 0.32),
            blurRadius: 32,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PromotorSectionLabel('Snapshot Operasional'),
            const SizedBox(height: 10),
            Text(
              '${_storeData?['store_name'] ?? 'Toko'}',
              style: PromotorText.display(
                size: 28,
                weight: FontWeight.w800,
                color: t.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_storeData?['address'] ?? 'Alamat belum tersedia'}',
              style: PromotorText.outfit(
                size: 15,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: PromotorPill(
                    label: 'Promotor',
                    subLabel: '${_promotors.length} orang',
                    dotColor: t.info,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PromotorPill(
                    label: 'Progress',
                    subLabel: '${(progress * 100).round()}%',
                    dotColor: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            PromotorProgressBar(
              value: progress,
              useGreen: progress >= 0.85,
              useAmber: progress >= 0.5 && progress < 0.85,
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                _buildDateSwitcher(
                  icon: Icons.chevron_left_rounded,
                  onTap: () {
                    setState(() {
                      _selectedDate = _selectedDate.subtract(
                        const Duration(days: 1),
                      );
                    });
                    _loadData();
                  },
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: t.surface1,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: t.surface3),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Tanggal aktif',
                          style: PromotorText.outfit(
                            size: 15,
                            weight: FontWeight.w700,
                            color: t.textMuted,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          dateLabel,
                          textAlign: TextAlign.center,
                          style: PromotorText.outfit(
                            size: 15,
                            weight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _buildDateSwitcher(
                  icon: Icons.chevron_right_rounded,
                  enabled: _canMoveForward,
                  onTap: () {
                    if (!_canMoveForward) return;
                    setState(() {
                      _selectedDate = _selectedDate.add(
                        const Duration(days: 1),
                      );
                    });
                    _loadData();
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateSwitcher({
    required IconData icon,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: enabled ? onTap : null,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: enabled ? t.surface1 : t.surface1.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.surface3),
        ),
        child: Icon(icon, color: enabled ? t.textPrimary : t.textMutedStrong),
      ),
    );
  }

  Widget _buildWarningCard() {
    return PromotorCard(
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, color: t.warning),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _warningMessage ?? '',
              style: PromotorText.outfit(
                size: 15,
                weight: FontWeight.w600,
                color: t.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return PromotorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PromotorSectionLabel('Gagal Memuat'),
          const SizedBox(height: 10),
          Text(
            _errorMessage ?? 'Terjadi kesalahan.',
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 42,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: t.primaryAccent,
                foregroundColor: t.textOnAccent,
              ),
              onPressed: _loadData,
              child: Text(
                'Coba Lagi',
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w800,
                  color: t.textOnAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoreSummary() {
    final completedPromotors = _promotors
        .where((row) => _completedActivities(row) == _activityItems.length)
        .length;
    final attentionPromotors = _promotors
        .where((row) => _completedActivities(row) < 3)
        .length;

    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            title: 'Area',
            value: _storeAreaLabel(),
            caption: 'Grade ${_storeGradeLabel()}',
            tone: t.info,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            title: 'Status Toko',
            value: _storeStatusLabel(),
            caption: '$completedPromotors selesai penuh',
            tone: t.success,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            title: 'Perlu Atensi',
            value: '$attentionPromotors',
            caption: 'promotor progres rendah',
            tone: attentionPromotors == 0 ? t.primaryAccent : t.danger,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String caption,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w700,
              color: t.textMuted,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: PromotorText.outfit(
              size: 16,
              weight: FontWeight.w800,
              color: tone,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            caption,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllbrandSection() {
    final data = _allbrandData;
    final hasData = data != null && data['has_data'] == true;

    return PromotorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PromotorSectionLabel('AllBrand Toko'),
          const SizedBox(height: 10),
          if (!hasData)
            Text(
              'Belum ada snapshot AllBrand pada tanggal ini.',
              style: PromotorText.outfit(
                size: 15,
                weight: FontWeight.w600,
                color: t.textSecondary,
              ),
            )
          else ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildToneChip(
                  label: 'MS VIVO',
                  value:
                      '${((data['vivo_market_share'] as num?) ?? 0).toStringAsFixed(1)}%',
                  tone: t.success,
                ),
                _buildToneChip(
                  label: 'VIVO',
                  value: '${data['vivo_units'] ?? 0} unit',
                  tone: t.info,
                ),
                _buildToneChip(
                  label: 'Kompetitor',
                  value: '${data['total_units'] ?? 0} unit',
                  tone: t.warning,
                ),
                _buildToneChip(
                  label: 'Fokus',
                  value:
                      '${data['focus_store_daily'] ?? 0} / ${data['focus_store_cumulative'] ?? 0}',
                  tone: t.primaryAccent,
                ),
              ],
            ),
            const SizedBox(height: 14),
            ...List<Map<String, dynamic>>.from(
              (data['brand_share'] as List?) ?? const [],
            ).take(5).map(_buildBrandShareRow),
          ],
        ],
      ),
    );
  }

  Widget _buildToneChip({
    required String label,
    required String value,
    required Color tone,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withValues(alpha: 0.26)),
      ),
      child: Text(
        '$label: $value',
        style: PromotorText.outfit(
          size: 13,
          weight: FontWeight.w700,
          color: tone,
        ),
      ),
    );
  }

  Widget _buildBrandShareRow(Map<String, dynamic> item) {
    final share = ((item['share'] as num?) ?? 0).toDouble();
    final units = item['units'] ?? 0;
    final label = '${item['label'] ?? '-'}';
    final progress = (share / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: PromotorText.outfit(size: 15, weight: FontWeight.w700),
                ),
              ),
              Text(
                '$units unit',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w600,
                  color: t.textSecondary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${share.toStringAsFixed(1)}%',
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w800,
                  color: t.primaryAccentLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          PromotorProgressBar(
            value: progress,
            useGreen: label == 'VIVO',
            useAmber: label != 'VIVO',
          ),
        ],
      ),
    );
  }

  Widget _buildChecklistHeader() {
    final dateLabel = DateFormat('d MMM yyyy', 'id_ID').format(_selectedDate);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PromotorSectionLabel('Checklist Aktivitas'),
              const SizedBox(height: 6),
              Text(
                'Pantau progres tugas per promotor',
                style: PromotorText.outfit(
                  size: 15,
                  weight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            dateLabel,
            style: PromotorText.outfit(
              size: 13,
              weight: FontWeight.w700,
              color: t.primaryAccentLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChecklist() {
    return PromotorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PromotorSectionLabel('Belum Ada Promotor'),
          const SizedBox(height: 10),
          Text(
            'Tidak ada promotor aktif yang terhubung ke toko ini pada tanggal yang dipilih.',
            style: PromotorText.outfit(
              size: 15,
              weight: FontWeight.w600,
              color: t.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotorCard(Map<String, dynamic> promotor) {
    final completed = _completedActivities(promotor);
    final progress = completed / _activityItems.length;
    final promotorType = '${promotor['promotor_type'] ?? ''}'.toLowerCase();
    final badgeColor = promotorType == 'official' ? t.success : t.warning;
    final badgeLabel = promotorType == 'official' ? 'Official' : 'Training';
    final attendanceCategory = '${promotor['attendance_category'] ?? ''}'
        .trim();
    final attendanceLabel = promotor['clock_in'] == true
        ? (_attendanceCategoryLabel(attendanceCategory).isEmpty
              ? 'Hadir'
              : _attendanceCategoryLabel(attendanceCategory))
        : 'Belum Lapor';
    final attendanceTone = promotor['clock_in'] == true
        ? _attendanceCategoryTone(attendanceCategory)
        : t.danger;

    return PromotorCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: t.surface2,
                  border: Border.all(color: t.surface3),
                ),
                alignment: Alignment.center,
                child: Text(
                  ((promotor['name'] ?? 'P') as String)
                      .trim()
                      .characters
                      .first
                      .toUpperCase(),
                  style: PromotorText.outfit(
                    size: 17,
                    weight: FontWeight.w800,
                    color: t.primaryAccentLight,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${promotor['name'] ?? 'Promotor'}',
                      style: PromotorText.outfit(
                        size: 16,
                        weight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$completed/${_activityItems.length} tugas selesai',
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w600,
                        color: t.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: attendanceTone.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: attendanceTone.withValues(alpha: 0.28),
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
                            size: 15,
                            color: attendanceTone,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            attendanceLabel,
                            style: PromotorText.outfit(
                              size: 11,
                              weight: FontWeight.w800,
                              color: attendanceTone,
                            ),
                          ),
                        ],
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
                  color: badgeColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: badgeColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  badgeLabel,
                  style: PromotorText.outfit(
                    size: 15,
                    weight: FontWeight.w800,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          PromotorProgressBar(
            value: progress,
            useGreen: progress >= 0.85,
            useAmber: progress >= 0.5 && progress < 0.85,
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _activityItems.map((item) {
              final done = promotor[item.$1] == true;
              final tone = _statusTone(done);
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: done ? t.success.withValues(alpha: 0.12) : t.surface2,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: done
                        ? t.success.withValues(alpha: 0.32)
                        : t.surface3,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      done ? Icons.check_circle_rounded : item.$3,
                      size: 16,
                      color: tone,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      item.$2,
                      style: PromotorText.outfit(
                        size: 13,
                        weight: FontWeight.w700,
                        color: done ? t.success : t.textSecondary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
