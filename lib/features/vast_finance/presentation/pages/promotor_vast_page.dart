import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/utils/success_dialog.dart';
import '../../../../ui/promotor/promotor.dart';
import '../vast_finance_utils.dart';

class PromotorVastPage extends StatefulWidget {
  const PromotorVastPage({super.key, this.inputOnly = false});

  final bool inputOnly;

  @override
  State<PromotorVastPage> createState() => _PromotorVastPageState();
}

class _PromotorVastPageState extends State<PromotorVastPage> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final ImagePicker _picker = ImagePicker();
  FieldThemeTokens get t => context.fieldTokens;
  final NumberFormat _currency = NumberFormat.currency(
    locale: 'id_ID',
    symbol: 'Rp ',
    decimalDigits: 0,
  );
  final DateFormat _dateFormat = DateFormat('dd MMM yyyy', 'id_ID');

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final TextEditingController _customerNameCtrl = TextEditingController();
  final TextEditingController _customerPhoneCtrl = TextEditingController();
  final TextEditingController _incomeCtrl = TextEditingController();
  final TextEditingController _limitCtrl = TextEditingController();
  final TextEditingController _dpCtrl = TextEditingController();
  final TextEditingController _notesCtrl = TextEditingController();

  bool _isLoading = true;
  bool _isSubmitting = false;
  bool _isFormattingPhone = false;
  bool _isFormattingIncome = false;
  bool _isFormattingLimit = false;
  bool _isFormattingDp = false;
  String _activeSection = 'pending';
  String _selectedPeriodTab = 'harian';

  Map<String, dynamic>? _store;
  String _promotorName = 'Promotor';
  int _monthlyTargetVast = 0;
  Map<String, dynamic>? _monthlySummary;
  _VastPeriodStats? _dailyPeriodStats;
  _VastPeriodStats? _weeklyPeriodStats;
  _VastPeriodStats? _monthlyPeriodStats;
  List<_VastWeekSplit> _weeklyBreakdown = <_VastWeekSplit>[];
  List<Map<String, dynamic>> _pendingItems = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _historyItems = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _reminders = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _products = <Map<String, dynamic>>[];
  List<XFile> _initialImages = <XFile>[];

  String _selectedPekerjaan = VastFinanceUtils.pekerjaanOptions.first;
  String _selectedOutcome = 'pending';
  String _selectedTenor = '12';
  String? _selectedProductId;
  String? _selectedProductLabel;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _customerPhoneCtrl.text = '+62';
    _incomeCtrl.text = _currency.format(0);
    _limitCtrl.text = _currency.format(0);
    _dpCtrl.text = _currency.format(0);
    _customerPhoneCtrl.addListener(_handlePhoneFormatting);
    _incomeCtrl.addListener(
      () => _formatCurrencyController(
        _incomeCtrl,
        () => _isFormattingIncome = true,
        () => _isFormattingIncome = false,
        _isFormattingIncome,
      ),
    );
    _limitCtrl.addListener(
      () => _formatCurrencyController(
        _limitCtrl,
        () => _isFormattingLimit = true,
        () => _isFormattingLimit = false,
        _isFormattingLimit,
      ),
    );
    _dpCtrl.addListener(
      () => _formatCurrencyController(
        _dpCtrl,
        () => _isFormattingDp = true,
        () => _isFormattingDp = false,
        _isFormattingDp,
      ),
    );
    _refresh();
  }

  @override
  void dispose() {
    _customerNameCtrl.dispose();
    _customerPhoneCtrl.dispose();
    _incomeCtrl.dispose();
    _limitCtrl.dispose();
    _dpCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      await _loadSummaries();
      await Future.wait([
        _loadStore(),
        _loadUserProfile(),
        _loadProducts(),
        _loadPeriodStats(),
        _loadPending(),
        _loadHistory(),
        _loadReminders(),
      ]);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _loadStore() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final rows = await _supabase
        .from('assignments_promotor_store')
        .select('store_id, stores(store_name, area)')
        .eq('promotor_id', userId)
        .eq('active', true)
        .order('created_at', ascending: false)
        .limit(1);
    final list = List<Map<String, dynamic>>.from(rows);
    _store = list.isEmpty ? null : list.first;
  }

  Future<void> _loadUserProfile() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final row = await _supabase
        .from('users')
        .select('full_name, nickname')
        .eq('id', userId)
        .maybeSingle();
    final nickname = '${row?['nickname'] ?? ''}'.trim();
    final fullName = '${row?['full_name'] ?? ''}'.trim();
    _promotorName = nickname.isNotEmpty
        ? nickname
        : (fullName.isNotEmpty ? fullName : 'Promotor');
  }

  Future<void> _loadProducts() async {
    final rows = await _supabase
        .from('products')
        .select('id, model_name')
        .order('model_name');
    _products = List<Map<String, dynamic>>.from(
      rows,
    ).where((row) => '${row['model_name'] ?? ''}'.trim().isNotEmpty).toList();
  }

  Future<int> _fetchCurrentMonthlyTarget(String userId) async {
    final activePeriods = List<Map<String, dynamic>>.from(
      await _supabase
          .from('target_periods')
          .select('id')
          .eq('status', 'active')
          .isFilter('deleted_at', null)
          .order('target_year', ascending: false)
          .order('target_month', ascending: false)
          .order('created_at', ascending: false)
          .limit(1),
    );
    final activePeriodId = activePeriods.isEmpty
        ? null
        : activePeriods.first['id']?.toString();
    if (activePeriodId == null || activePeriodId.isEmpty) {
      return 0;
    }
    final targetRow = await _supabase
        .from('user_targets')
        .select('target_vast')
        .eq('user_id', userId)
        .eq('period_id', activePeriodId)
        .maybeSingle();
    return _toInt(targetRow?['target_vast']);
  }

  Future<void> _loadSummaries() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final now = DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}-01';
    final monthly = await _supabase
        .from('vast_agg_monthly_promotor')
        .select()
        .eq('promotor_id', userId)
        .eq('month_key', monthKey)
        .maybeSingle();

    _monthlySummary = monthly == null
        ? null
        : Map<String, dynamic>.from(monthly);
    _monthlyTargetVast = await _fetchCurrentMonthlyTarget(userId);
  }

  Future<void> _loadPeriodStats() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    if (_monthlyTargetVast <= 0) {
      _monthlyTargetVast = await _fetchCurrentMonthlyTarget(userId);
    }

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final todayEnd = todayStart;
    final weekStart = todayStart.subtract(
      Duration(days: todayStart.weekday - 1),
    );
    final weekEnd = weekStart.add(const Duration(days: 6));
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);

    final results = await Future.wait([
      _fetchPeriodStats(
        userId: userId,
        start: todayStart,
        end: todayEnd,
        target: _resolveDailyTarget(now),
      ),
      _fetchPeriodStats(
        userId: userId,
        start: weekStart,
        end: weekEnd,
        target: _resolveWeeklyTarget(now, weekStart, weekEnd),
      ),
      _fetchPeriodStats(
        userId: userId,
        start: monthStart,
        end: monthEnd,
        target: _resolveMonthlyTarget(),
      ),
      _loadWeeklyBreakdown(userId: userId, now: now),
    ]);

    _dailyPeriodStats = results[0] as _VastPeriodStats;
    _weeklyPeriodStats = results[1] as _VastPeriodStats;
    _monthlyPeriodStats = results[2] as _VastPeriodStats;
    _weeklyBreakdown = results[3] as List<_VastWeekSplit>;
  }

  Future<_VastPeriodStats> _fetchPeriodStats({
    required String userId,
    required DateTime start,
    required DateTime end,
    required int target,
  }) async {
    final rows = await _supabase
        .from('vast_applications')
        .select('id, outcome_status, lifecycle_status, application_date')
        .eq('promotor_id', userId)
        .isFilter('deleted_at', null)
        .gte('application_date', DateFormat('yyyy-MM-dd').format(start))
        .lte('application_date', DateFormat('yyyy-MM-dd').format(end));

    final items = List<Map<String, dynamic>>.from(rows);
    var acc = 0;
    var reject = 0;

    for (final item in items) {
      final outcome = '${item['outcome_status'] ?? ''}'.toLowerCase();
      final lifecycle = '${item['lifecycle_status'] ?? ''}'.toLowerCase();
      if (outcome == 'acc' ||
          lifecycle == 'closed_direct' ||
          lifecycle == 'closed_follow_up') {
        acc++;
      } else if (outcome == 'reject' || lifecycle == 'rejected') {
        reject++;
      }
    }

    return _VastPeriodStats(
      start: start,
      end: end,
      target: target,
      submissions: items.length,
      acc: acc,
      reject: reject,
    );
  }

  Future<List<_VastWeekSplit>> _loadWeeklyBreakdown({
    required String userId,
    required DateTime now,
  }) async {
    final monthStart = DateTime(now.year, now.month, 1);
    final monthEnd = DateTime(now.year, now.month + 1, 0);
    final rows = await _supabase
        .from('vast_applications')
        .select('outcome_status, lifecycle_status, application_date')
        .eq('promotor_id', userId)
        .isFilter('deleted_at', null)
        .gte('application_date', DateFormat('yyyy-MM-dd').format(monthStart))
        .lte('application_date', DateFormat('yyyy-MM-dd').format(monthEnd));

    final items = List<Map<String, dynamic>>.from(rows);
    final targets = _buildWeeklyTargets(_resolveMonthlyTarget());
    final splits = List<_VastWeekSplit>.generate(4, (index) {
      return _VastWeekSplit(
        label: 'Week ${index + 1}',
        target: targets[index],
        submissions: 0,
        acc: 0,
        reject: 0,
      );
    });

    for (final item in items) {
      final date = DateTime.tryParse('${item['application_date']}');
      if (date == null) continue;
      final weekIndex = _weekIndexForDay(date.day);
      final current = splits[weekIndex];
      final outcome = '${item['outcome_status'] ?? ''}'.toLowerCase();
      final lifecycle = '${item['lifecycle_status'] ?? ''}'.toLowerCase();
      splits[weekIndex] = _VastWeekSplit(
        label: current.label,
        target: current.target,
        submissions: current.submissions + 1,
        acc:
            current.acc +
            ((outcome == 'acc' ||
                    lifecycle == 'closed_direct' ||
                    lifecycle == 'closed_follow_up')
                ? 1
                : 0),
        reject:
            current.reject +
            ((outcome == 'reject' || lifecycle == 'rejected') ? 1 : 0),
      );
    }

    return splits;
  }

  int _resolveMonthlyTarget() {
    if (_monthlyTargetVast > 0) return _monthlyTargetVast;
    return _toInt(_monthlySummary?['target_submissions']);
  }

  int _resolveDailyTarget(DateTime now) {
    final monthTarget = _resolveMonthlyTarget();
    if (monthTarget <= 0) return 0;
    final daysInMonth = DateUtils.getDaysInMonth(now.year, now.month);
    return (monthTarget / daysInMonth).ceil();
  }

  int _resolveWeeklyTarget(DateTime now, DateTime weekStart, DateTime weekEnd) {
    final monthTarget = _resolveMonthlyTarget();
    if (monthTarget <= 0) return 0;
    return _buildWeeklyTargets(monthTarget)[_weekIndexForDay(now.day)];
  }

  List<int> _buildWeeklyTargets(int monthlyTarget) {
    if (monthlyTarget <= 0) return const <int>[0, 0, 0, 0];
    final base = monthlyTarget ~/ 4;
    final remainder = monthlyTarget % 4;
    return List<int>.generate(4, (index) => base + (index < remainder ? 1 : 0));
  }

  int _weekIndexForDay(int day) {
    if (day <= 7) return 0;
    if (day <= 14) return 1;
    if (day <= 21) return 2;
    return 3;
  }

  int _currentWeekIndex() => _weekIndexForDay(DateTime.now().day);

  int _currentPeriodPercent(_VastPeriodStats? stats) {
    if (stats == null || stats.target <= 0) return 0;
    return ((stats.submissions / stats.target) * 100).round();
  }

  _VastPeriodStats? _currentPeriodStats() {
    switch (_selectedPeriodTab) {
      case 'harian':
        return _dailyPeriodStats;
      case 'mingguan':
        return _weeklyPeriodStats;
      case 'bulanan':
        return _monthlyPeriodStats;
      default:
        return _dailyPeriodStats;
    }
  }

  String _periodSubtitle(_VastPeriodStats? stats) {
    if (stats == null) return 'Periode berjalan';
    if (_selectedPeriodTab == 'harian') {
      return _dateFormat.format(stats.start);
    }
    if (_selectedPeriodTab == 'mingguan') {
      return '${_dateFormat.format(stats.start)} - ${_dateFormat.format(stats.end)}';
    }
    return DateFormat('MMMM yyyy', 'id_ID').format(stats.start);
  }

  Future<void> _loadPending() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final rows = await _supabase
        .from('vast_applications')
        .select(
          'id, customer_name, customer_phone, product_label, limit_amount, '
          'dp_amount, tenor_months, application_date, notes',
        )
        .eq('promotor_id', userId)
        .eq('lifecycle_status', 'approved_pending')
        .isFilter('deleted_at', null)
        .order('application_date', ascending: false);
    _pendingItems = List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _loadHistory() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final rows = await _supabase
        .from('vast_applications')
        .select(
          'id, customer_name, customer_phone, pekerjaan, monthly_income, '
          'product_label, outcome_status, lifecycle_status, '
          'application_date, created_at, '
          'limit_amount, dp_amount, tenor_months, notes',
        )
        .eq('promotor_id', userId)
        .isFilter('deleted_at', null)
        .order('created_at', ascending: false)
        .limit(100);
    _historyItems = List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _loadReminders() async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final rows = await _supabase
        .from('vast_reminders')
        .select(
          'id, reminder_type, scheduled_date, reminder_title, reminder_body, status',
        )
        .eq('promotor_id', userId)
        .order('scheduled_date');
    _reminders = List<Map<String, dynamic>>.from(rows);
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  num _toNum(dynamic value) {
    if (value is num) return value;
    return num.tryParse('${value ?? ''}') ?? 0;
  }

  int _digitsToInt(String value) {
    final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(digits) ?? 0;
  }

  void _handlePhoneFormatting() {
    if (_isFormattingPhone) return;
    _isFormattingPhone = true;
    final formatted = _normalizePhone(_customerPhoneCtrl.text);
    _customerPhoneCtrl.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    _isFormattingPhone = false;
  }

  String _normalizePhone(String input) {
    var digits = input.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('62')) {
      digits = digits.substring(2);
    } else if (digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return '+62$digits';
  }

  String _formatRupiahInput(String value) {
    return _currency.format(_digitsToInt(value));
  }

  void _formatCurrencyController(
    TextEditingController controller,
    VoidCallback startFlag,
    VoidCallback endFlag,
    bool isBusy,
  ) {
    if (isBusy) return;
    startFlag();
    final formatted = _formatRupiahInput(controller.text);
    controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
    endFlag();
  }

  void _logVastSubmitError({
    required Object error,
    required StackTrace stackTrace,
    required Map<String, dynamic> payload,
  }) {
    final prettyPayload = const JsonEncoder.withIndent('  ').convert(payload);
    debugPrint('================ VAST SUBMIT ERROR ================');
    debugPrint('Error      : $error');
    debugPrint('StackTrace : $stackTrace');
    debugPrint('Payload    :');
    debugPrint(prettyPayload);
    debugPrint('===================================================');
  }

  Future<void> _pickImages({
    required void Function(List<XFile> images) onChanged,
    required List<XFile> currentImages,
    bool useMountedGuard = true,
  }) async {
    final source = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: t.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: Icon(
                    Icons.camera_alt_outlined,
                    color: t.primaryAccent,
                  ),
                  title: Text(
                    'Ambil Foto',
                    style: PromotorText.outfit(
                      size: 15,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop('camera'),
                ),
                ListTile(
                  leading: Icon(
                    Icons.photo_library_outlined,
                    color: t.primaryAccent,
                  ),
                  title: Text(
                    'Pilih dari Galeri',
                    style: PromotorText.outfit(
                      size: 15,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  onTap: () => Navigator.of(context).pop('gallery'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (source == null) return;

    if (source == 'camera') {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
      );
      if (image == null) return;
      if (useMountedGuard && !mounted) return;
      onChanged(<XFile>[...currentImages, image]);
      return;
    }

    final images = await _picker.pickMultiImage(imageQuality: 88);
    if (images.isEmpty) return;
    if (useMountedGuard && !mounted) return;
    onChanged(<XFile>[...currentImages, ...images]);
  }

  Future<void> _submitApplication() async {
    if (!_formKey.currentState!.validate()) return;
    if (_store == null) {
      _showSnack('Toko promotor belum terpasang.');
      return;
    }
    if (_selectedProductId == null || _selectedProductLabel == null) {
      _showSnack('Model HP wajib dipilih.');
      return;
    }
    if (_initialImages.isEmpty) {
      _showSnack('Foto bukti wajib diisi minimal 1.');
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Sesi login tidak ditemukan.');
      }

      final productVariant = await _supabase
          .from('product_variants')
          .select('id')
          .eq('product_id', _selectedProductId as Object)
          .limit(1)
          .maybeSingle();
      final productVariantId = productVariant?['id']?.toString();
      if (productVariantId == null || productVariantId.isEmpty) {
        throw Exception('Varian produk untuk model ini belum tersedia.');
      }

      final lifecycleStatus = switch (_selectedOutcome) {
        'acc' => 'closed_direct',
        'reject' => 'rejected',
        _ => 'approved_pending',
      };

      final payload = <String, dynamic>{
        'created_by_user_id': userId,
        'promotor_id': userId,
        'store_id': _store!['store_id'],
        'application_date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'customer_name': _customerNameCtrl.text.trim(),
        'customer_phone': _normalizePhone(_customerPhoneCtrl.text),
        'pekerjaan': _selectedPekerjaan,
        'monthly_income': _digitsToInt(_incomeCtrl.text),
        'has_npwp': false,
        'product_variant_id': productVariantId,
        'product_label': _selectedProductLabel,
        'limit_amount': _digitsToInt(_limitCtrl.text),
        'dp_amount': _digitsToInt(_dpCtrl.text),
        'tenor_months': _toInt(_selectedTenor),
        'outcome_status': _selectedOutcome,
        'lifecycle_status': lifecycleStatus,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      };

      final inserted = await _supabase
          .from('vast_applications')
          .insert(payload)
          .select('id')
          .single();

      final applicationId = inserted['id'] as String;
      for (final image in _initialImages) {
        await _uploadEvidence(
          applicationId: applicationId,
          image: image,
          stage: 'initial',
          evidenceType: 'application_proof',
        );
      }

      _clearForm();
      await _refresh();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: 'Pengajuan VAST berhasil dikirim.',
      );
    } catch (e, stackTrace) {
      _logVastSubmitError(
        error: e,
        stackTrace: stackTrace,
        payload: {
          'store': _store,
          'selected_product_id': _selectedProductId,
          'selected_product_label': _selectedProductLabel,
          'selected_pekerjaan': _selectedPekerjaan,
          'selected_tenor': _selectedTenor,
          'selected_outcome': _selectedOutcome,
          'images_count': _initialImages.length,
          'customer_name': _customerNameCtrl.text.trim(),
          'customer_phone': _normalizePhone(_customerPhoneCtrl.text),
          'monthly_income': _digitsToInt(_incomeCtrl.text),
          'limit_amount': _digitsToInt(_limitCtrl.text),
          'dp_amount': _digitsToInt(_dpCtrl.text),
        },
      );
      _showSnack('Gagal menyimpan pengajuan: $e');
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  Future<void> _uploadEvidence({
    required String applicationId,
    required XFile image,
    required String stage,
    required String evidenceType,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;
    final compressed = await VastFinanceUtils.compressForUpload(image);
    final uploadedUrl = await VastFinanceUtils.uploadImage(
      compressed,
      folder: 'vtrack/vast_finance',
      fileName: image.name,
    );
    if (uploadedUrl == null) {
      throw Exception('Upload gambar gagal.');
    }

    await _supabase.from('vast_application_evidences').insert({
      'application_id': applicationId,
      'source_stage': stage,
      'evidence_type': evidenceType,
      'file_url': uploadedUrl,
      'file_name': image.name,
      'mime_type': image.mimeType,
      'file_size_bytes': compressed.length,
      'sha256_hex': VastFinanceUtils.exactHashHex(compressed),
      'perceptual_hash': VastFinanceUtils.perceptualHash(compressed),
      'created_by_user_id': userId,
    });
  }

  void _clearForm() {
    _customerNameCtrl.clear();
    _customerPhoneCtrl.text = '+62';
    _incomeCtrl.text = _currency.format(0);
    _limitCtrl.text = _currency.format(0);
    _dpCtrl.text = _currency.format(0);
    _notesCtrl.clear();
    _selectedPekerjaan = VastFinanceUtils.pekerjaanOptions.first;
    _selectedOutcome = 'pending';
    _selectedTenor = '12';
    _selectedProductId = null;
    _selectedProductLabel = null;
    _selectedDate = DateTime.now();
    _initialImages = <XFile>[];
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showClosingSheet(Map<String, dynamic> item) async {
    final closingDate = ValueNotifier<DateTime>(DateTime.now());
    final installmentDate = ValueNotifier<DateTime>(DateTime.now());
    final monthlyInstallmentCtrl = TextEditingController(
      text: _currency.format(0),
    );
    final finalDpCtrl = TextEditingController(
      text: _currency.format(_toNum(item['dp_amount'])),
    );
    final finalLimitCtrl = TextEditingController(
      text: _currency.format(_toNum(item['limit_amount'])),
    );
    final notesCtrl = TextEditingController();
    var selectedFinalTenor = '${_toInt(item['tenor_months'])}';
    var closingProofs = <XFile>[];
    final formKey = GlobalKey<FormState>();
    var formattingMonthly = false;
    var formattingDp = false;
    var formattingLimit = false;

    monthlyInstallmentCtrl.addListener(() {
      _formatCurrencyController(
        monthlyInstallmentCtrl,
        () => formattingMonthly = true,
        () => formattingMonthly = false,
        formattingMonthly,
      );
    });
    finalDpCtrl.addListener(() {
      _formatCurrencyController(
        finalDpCtrl,
        () => formattingDp = true,
        () => formattingDp = false,
        formattingDp,
      );
    });
    finalLimitCtrl.addListener(() {
      _formatCurrencyController(
        finalLimitCtrl,
        () => formattingLimit = true,
        () => formattingLimit = false,
        formattingLimit,
      );
    });

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  MediaQuery.of(context).viewInsets.bottom + 24,
                ),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Final Closing',
                          style: PromotorText.display(
                            size: 24,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item['customer_name']?.toString() ?? '-',
                          style: PromotorText.outfit(
                            size: 12,
                            color: t.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 18),
                        _buildDateField(
                          label: 'Tanggal Closing',
                          value: closingDate,
                          onChanged: (value) =>
                              setModalState(() => closingDate.value = value),
                        ),
                        const SizedBox(height: 12),
                        _buildDateField(
                          label: 'Tanggal Mulai Cicilan',
                          value: installmentDate,
                          onChanged: (value) => setModalState(
                            () => installmentDate.value = value,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: monthlyInstallmentCtrl,
                          label: 'Cicilan per Bulan',
                          keyboardType: TextInputType.number,
                          validator: _requiredCurrencyValidator,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: finalDpCtrl,
                          label: 'DP Final',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: finalLimitCtrl,
                          label: 'Limit Final',
                          keyboardType: TextInputType.number,
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          initialValue: selectedFinalTenor,
                          dropdownColor: t.surface2,
                          style: PromotorText.outfit(
                            size: 15,
                            weight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                          decoration: _inputDecoration('Tenor Final'),
                          items: const ['3', '6', '9', '12', '24']
                              .map(
                                (item) => DropdownMenuItem<String>(
                                  value: item,
                                  child: Text('$item bulan'),
                                ),
                              )
                              .toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setModalState(() => selectedFinalTenor = value);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: notesCtrl,
                          label: 'Catatan Closing',
                          maxLines: 3,
                        ),
                        const SizedBox(height: 14),
                        _buildMultiPickerCard(
                          title: 'Foto Bukti Final',
                          images: closingProofs,
                          onAddTap: () async {
                            await _pickImages(
                              currentImages: closingProofs,
                              useMountedGuard: false,
                              onChanged: (images) =>
                                  setModalState(() => closingProofs = images),
                            );
                          },
                          onRemoveAt: (index) {
                            setModalState(() => closingProofs.removeAt(index));
                          },
                        ),
                        const SizedBox(height: 18),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: t.primaryAccent,
                              foregroundColor: t.shellBackground,
                            ),
                            onPressed: () async {
                              if (!formKey.currentState!.validate()) return;
                              Navigator.of(context).pop();
                              await _submitClosing(
                                applicationId: item['id'] as String,
                                closingDate: closingDate.value,
                                installmentDate: installmentDate.value,
                                monthlyInstallment: monthlyInstallmentCtrl.text,
                                finalDp: finalDpCtrl.text,
                                finalLimit: finalLimitCtrl.text,
                                finalTenor: selectedFinalTenor,
                                notes: notesCtrl.text.trim(),
                                closingProofs: closingProofs,
                              );
                            },
                            child: const Text('Kirim Closing'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    monthlyInstallmentCtrl.dispose();
    finalDpCtrl.dispose();
    finalLimitCtrl.dispose();
    notesCtrl.dispose();
  }

  Future<void> _submitClosing({
    required String applicationId,
    required DateTime closingDate,
    required DateTime installmentDate,
    required String monthlyInstallment,
    required String finalDp,
    required String finalLimit,
    required String finalTenor,
    required String notes,
    List<XFile> closingProofs = const <XFile>[],
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;
      await _supabase.from('vast_closings').insert({
        'application_id': applicationId,
        'closing_date': DateFormat('yyyy-MM-dd').format(closingDate),
        'pickup_date': DateFormat('yyyy-MM-dd').format(closingDate),
        'installment_start_date': DateFormat(
          'yyyy-MM-dd',
        ).format(installmentDate),
        'monthly_installment_amount': _digitsToInt(monthlyInstallment),
        'final_dp_amount': _digitsToInt(finalDp),
        'final_limit_amount': _digitsToInt(finalLimit),
        'final_tenor_months': _toInt(finalTenor),
        'notes': notes.isEmpty ? null : notes,
        'created_by_user_id': userId,
      });
      await _supabase
          .from('vast_applications')
          .update({
            'lifecycle_status': 'closed_follow_up',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', applicationId);

      for (final image in closingProofs) {
        await _uploadEvidence(
          applicationId: applicationId,
          image: image,
          stage: 'closing',
          evidenceType: 'closing_proof',
        );
      }

      await _refresh();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: 'Closing follow-up berhasil dikirim.',
      );
    } catch (e) {
      _showSnack('Gagal menyimpan closing: $e');
    }
  }

  Future<void> _markReminderDone(String reminderId) async {
    await _supabase
        .from('vast_reminders')
        .update({'status': 'done', 'read_at': DateTime.now().toIso8601String()})
        .eq('id', reminderId);
    await _loadReminders();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showHistoryDetail(Map<String, dynamic> item) async {
    final applicationId = item['id']?.toString();
    if (applicationId == null || applicationId.isEmpty) return;

    final evidences = await _supabase
        .from('vast_application_evidences')
        .select('file_url, evidence_type, source_stage, created_at')
        .eq('application_id', applicationId)
        .order('created_at', ascending: true);

    final closing = await _supabase
        .from('vast_closings')
        .select(
          'closing_date, installment_start_date, monthly_installment_amount, '
          'final_dp_amount, final_limit_amount, final_tenor_months, notes',
        )
        .eq('application_id', applicationId)
        .maybeSingle();

    if (!mounted) return;

    final evidenceItems = List<Map<String, dynamic>>.from(evidences);
    final closingData = closing is Map<String, dynamic>
        ? Map<String, dynamic>.from(closing)
        : null;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: t.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.82,
          maxChildSize: 0.94,
          minChildSize: 0.55,
          builder: (context, scrollController) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: t.surface3,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item['customer_name']?.toString() ?? '-',
                          style: PromotorText.outfit(
                            size: 16,
                            weight: FontWeight.w700,
                            color: t.textPrimary,
                          ),
                        ),
                      ),
                      _statusChip(item['lifecycle_status']?.toString() ?? '-'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDetailGrid(item),
                  if ((item['notes']?.toString() ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      'Catatan',
                      style: PromotorText.outfit(
                        size: 12,
                        weight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Text(
                        item['notes']?.toString() ?? '-',
                        style: PromotorText.outfit(
                          size: 13,
                          weight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                  ],
                  if (closingData != null) ...[
                    const SizedBox(height: 18),
                    Text(
                      'Data Closing',
                      style: PromotorText.outfit(
                        size: 12,
                        weight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    _buildClosingGrid(closingData),
                  ],
                  const SizedBox(height: 18),
                  Text(
                    'Bukti Foto',
                    style: PromotorText.outfit(
                      size: 12,
                      weight: FontWeight.w700,
                      color: t.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (evidenceItems.isEmpty)
                    Text(
                      'Belum ada bukti foto.',
                      style: PromotorText.outfit(
                        size: 12,
                        color: t.textPrimary,
                      ),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: evidenceItems.map((evidence) {
                        final imageUrl = evidence['file_url']?.toString() ?? '';
                        final label =
                            evidence['evidence_type'] == 'closing_proof'
                            ? 'Closing'
                            : 'Pengajuan';
                        return SizedBox(
                          width: 132,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: AspectRatio(
                                  aspectRatio: 1,
                                  child: imageUrl.isEmpty
                                      ? Container(
                                          color: t.surface2,
                                          alignment: Alignment.center,
                                          child: Icon(
                                            Icons.broken_image_outlined,
                                            color: t.textSecondary,
                                          ),
                                        )
                                      : Image.network(
                                          imageUrl,
                                          fit: BoxFit.cover,
                                          errorBuilder:
                                              (context, error, stackTrace) {
                                                return Container(
                                                  color: t.surface2,
                                                  alignment: Alignment.center,
                                                  child: Icon(
                                                    Icons.broken_image_outlined,
                                                    color: t.textSecondary,
                                                  ),
                                                );
                                              },
                                        ),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                label,
                                style: PromotorText.outfit(
                                  size: 11,
                                  weight: FontWeight.w700,
                                  color: t.textPrimary,
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
          },
        );
      },
    );
  }

  Widget _buildDetailGrid(Map<String, dynamic> item) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _detailTile(
          'Tanggal',
          _dateFormat.format(
            DateTime.tryParse('${item['application_date']}') ?? DateTime.now(),
          ),
        ),
        _detailTile('Produk', item['product_label']?.toString() ?? '-'),
        _detailTile('No. HP', item['customer_phone']?.toString() ?? '-'),
        _detailTile('Pekerjaan', item['pekerjaan']?.toString() ?? '-'),
        _detailTile(
          'Penghasilan',
          _currency.format(_toNum(item['monthly_income'])),
        ),
        _detailTile('Limit', _currency.format(_toNum(item['limit_amount']))),
        _detailTile('DP', _currency.format(_toNum(item['dp_amount']))),
        _detailTile('Tenor', '${_toInt(item['tenor_months'])} bulan'),
        _detailTile(
          'Hasil',
          (item['outcome_status']?.toString() ?? '-').toUpperCase(),
        ),
      ],
    );
  }

  Widget _buildClosingGrid(Map<String, dynamic> item) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _detailTile(
          'Tgl Closing',
          _dateFormat.format(
            DateTime.tryParse('${item['closing_date']}') ?? DateTime.now(),
          ),
        ),
        _detailTile(
          'Mulai Cicilan',
          _dateFormat.format(
            DateTime.tryParse('${item['installment_start_date']}') ??
                DateTime.now(),
          ),
        ),
        _detailTile(
          'Angsuran',
          _currency.format(_toNum(item['monthly_installment_amount'])),
        ),
        _detailTile(
          'DP Final',
          _currency.format(_toNum(item['final_dp_amount'])),
        ),
        _detailTile(
          'Limit Final',
          _currency.format(_toNum(item['final_limit_amount'])),
        ),
        _detailTile(
          'Tenor Final',
          '${_toInt(item['final_tenor_months'])} bulan',
        ),
      ],
    );
  }

  Widget _detailTile(String label, String value) {
    return Container(
      width: 150,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w700,
              color: t.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'Wajib diisi';
    }
    return null;
  }

  String? _requiredCurrencyValidator(String? value) {
    if (_digitsToInt(value ?? '') <= 0) {
      return 'Wajib diisi';
    }
    return null;
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: PromotorText.outfit(
        size: 13,
        weight: FontWeight.w700,
        color: t.textSecondary,
      ),
      floatingLabelStyle: PromotorText.outfit(
        size: 13,
        weight: FontWeight.w800,
        color: t.primaryAccent,
      ),
      filled: true,
      fillColor: t.surface1,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.surface3),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.surface3),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.primaryAccent),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: t.danger),
      ),
    );
  }

  Future<String?> _showOptionPickerSheet({
    required String title,
    required List<String> options,
    String? selectedValue,
    String? searchHint,
    String Function(String value)? labelBuilder,
  }) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      backgroundColor: t.surface1,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _OptionPickerSheet(
        title: title,
        options: options,
        selectedValue: selectedValue,
        searchHint: searchHint,
        labelBuilder: labelBuilder,
      ),
    );
  }

  Future<void> _pickPekerjaan() async {
    final result = await _showOptionPickerSheet(
      title: 'Pilih Pekerjaan',
      options: VastFinanceUtils.pekerjaanOptions,
      selectedValue: _selectedPekerjaan,
      searchHint: 'Cari pekerjaan',
    );
    if (!mounted || result == null) return;
    setState(() => _selectedPekerjaan = result);
  }

  Future<void> _pickProduct() async {
    final options = _products
        .map((item) => '${item['id']}|${item['model_name']}')
        .toList();
    final result = await _showOptionPickerSheet(
      title: 'Pilih Model HP',
      options: options,
      selectedValue: _selectedProductId == null
          ? null
          : '$_selectedProductId|${_selectedProductLabel ?? ''}',
      searchHint: 'Cari model HP',
      labelBuilder: (value) => value.split('|').last,
    );
    if (!mounted || result == null) return;
    final parts = result.split('|');
    if (parts.length < 2) return;
    setState(() {
      _selectedProductId = parts.first;
      _selectedProductLabel = parts.sublist(1).join('|');
    });
  }

  Future<void> _pickTenor() async {
    final result = await _showOptionPickerSheet(
      title: 'Pilih Tenor',
      options: const ['3', '6', '9', '12', '24'],
      selectedValue: _selectedTenor,
      searchHint: 'Cari tenor',
      labelBuilder: (value) => '$value bulan',
    );
    if (!mounted || result == null) return;
    setState(() => _selectedTenor = result);
  }

  Future<void> _pickOutcome() async {
    const outcomeOptions = ['acc', 'pending', 'reject'];
    final result = await _showOptionPickerSheet(
      title: 'Pilih Status Hasil',
      options: outcomeOptions,
      selectedValue: _selectedOutcome,
      searchHint: 'Cari status',
      labelBuilder: (value) => switch (value) {
        'acc' => 'ACC',
        'pending' => 'PENDING',
        'reject' => 'REJECT',
        _ => value.toUpperCase(),
      },
    );
    if (!mounted || result == null) return;
    setState(() => _selectedOutcome = result);
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: PromotorText.outfit(
        size: 15,
        weight: FontWeight.w700,
        color: t.textPrimary,
      ),
      decoration: _inputDecoration(label),
      validator: validator,
      inputFormatters: inputFormatters,
    );
  }

  Widget _buildDateField({
    required String label,
    required ValueNotifier<DateTime> value,
    required ValueChanged<DateTime> onChanged,
  }) {
    return ValueListenableBuilder<DateTime>(
      valueListenable: value,
      builder: (context, current, _) {
        return InkWell(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: current,
              firstDate: DateTime(2024),
              lastDate: DateTime(2100),
            );
            if (picked != null) {
              onChanged(picked);
            }
          },
          child: InputDecorator(
            decoration: _inputDecoration(label),
            child: Text(
              _dateFormat.format(current),
              style: PromotorText.outfit(
                size: 15,
                weight: FontWeight.w700,
                color: t.textPrimary,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMultiPickerCard({
    required String title,
    required List<XFile> images,
    required VoidCallback onAddTap,
    required ValueChanged<int> onRemoveAt,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: PromotorText.outfit(
                  size: 13,
                  weight: FontWeight.w700,
                  color: t.textPrimary,
                ),
              ),
              TextButton.icon(
                onPressed: onAddTap,
                style: TextButton.styleFrom(
                  foregroundColor: t.primaryAccent,
                  textStyle: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w800,
                    color: t.primaryAccent,
                  ),
                ),
                icon: Icon(
                  Icons.add_a_photo_outlined,
                  size: 16,
                  color: t.primaryAccent,
                ),
                label: Text(
                  'Tambah',
                  style: PromotorText.outfit(
                    size: 13,
                    weight: FontWeight.w800,
                    color: t.primaryAccent,
                  ),
                ),
              ),
            ],
          ),
          if (images.isEmpty)
            Text(
              'Belum ada foto dipilih',
              style: PromotorText.outfit(
                size: 13,
                weight: FontWeight.w700,
                color: t.textSecondary,
              ),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: List<Widget>.generate(images.length, (index) {
                final image = images[index];
                return Container(
                  width: 110,
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(11),
                        ),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Image.file(
                            File(image.path),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: t.surface2,
                                alignment: Alignment.center,
                                child: Icon(
                                  Icons.broken_image_outlined,
                                  color: t.textSecondary,
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 8, 6, 2),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                image.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: PromotorText.outfit(
                                  size: 10,
                                  color: t.textSecondary,
                                ),
                              ),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              onPressed: () => onRemoveAt(index),
                              icon: const Icon(Icons.close, size: 16),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _summaryMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: t.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: PromotorText.display(size: 16, color: t.textPrimary),
          ),
        ],
      ),
    );
  }

  Widget _buildInputTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateField(
              label: 'Tanggal Pengajuan',
              value: ValueNotifier<DateTime>(_selectedDate),
              onChanged: (value) => setState(() => _selectedDate = value),
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _customerNameCtrl,
              label: 'Nama Customer',
              validator: _requiredValidator,
              inputFormatters: <TextInputFormatter>[UpperCaseTextFormatter()],
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _customerPhoneCtrl,
              label: 'Nomor HP',
              validator: (value) {
                if ((value ?? '').trim().length < 6) {
                  return 'Nomor HP tidak valid';
                }
                return null;
              },
              keyboardType: TextInputType.phone,
            ),
            const SizedBox(height: 12),
            _buildPickerField(
              label: 'Pekerjaan',
              value: _selectedPekerjaan,
              onTap: _pickPekerjaan,
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _incomeCtrl,
              label: 'Penghasilan',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildPickerField(
              label: 'Model HP',
              value: _selectedProductLabel ?? 'Tap untuk pilih model',
              onTap: _pickProduct,
              hasError: _selectedProductId == null,
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _limitCtrl,
              label: 'Limit Kredit',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _dpCtrl,
              label: 'DP',
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _buildPickerField(
              label: 'Tenor',
              value: '$_selectedTenor bulan',
              onTap: _pickTenor,
            ),
            const SizedBox(height: 12),
            _buildPickerField(
              label: 'Status Hasil',
              value: switch (_selectedOutcome) {
                'acc' => 'ACC',
                'pending' => 'PENDING',
                'reject' => 'REJECT',
                _ => _selectedOutcome.toUpperCase(),
              },
              onTap: _pickOutcome,
            ),
            const SizedBox(height: 12),
            _buildInputField(
              controller: _notesCtrl,
              label: 'Catatan',
              maxLines: 3,
            ),
            const SizedBox(height: 14),
            _buildMultiPickerCard(
              title: 'Foto Bukti',
              images: _initialImages,
              onAddTap: () async {
                await _pickImages(
                  currentImages: _initialImages,
                  onChanged: (images) =>
                      setState(() => _initialImages = images),
                );
              },
              onRemoveAt: (index) =>
                  setState(() => _initialImages.removeAt(index)),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: t.primaryAccent,
                  foregroundColor: t.shellBackground,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _isSubmitting ? null : _submitApplication,
                child: Text(_isSubmitting ? 'Mengirim...' : 'Kirim'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPendingTab() {
    if (_pendingItems.isEmpty) {
      return _buildEmptyState('Belum ada pending aktif.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _pendingItems.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _pendingItems[index];
        return InkWell(
          onTap: () => _showHistoryDetail(item),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.surface3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item['customer_name']?.toString() ?? '-',
                        style: PromotorText.outfit(
                          size: 14,
                          weight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    FilledButton.tonal(
                      onPressed: () => _showClosingSheet(item),
                      child: const Text('Follow-up'),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '${item['product_label'] ?? '-'} · ${_toInt(item['tenor_months'])} bulan',
                  style: PromotorText.outfit(size: 12, color: t.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  'Limit ${_currency.format(_toNum(item['limit_amount']))} · DP ${_currency.format(_toNum(item['dp_amount']))}',
                  style: PromotorText.outfit(size: 12, color: t.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap card untuk lihat detail',
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w700,
                    color: t.primaryAccent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildHistoryTab() {
    if (_historyItems.isEmpty) {
      return _buildEmptyState('Belum ada history pengajuan.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _historyItems.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _historyItems[index];
        return InkWell(
          onTap: () => _showHistoryDetail(item),
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: t.surface1,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: t.surface3),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item['customer_name']?.toString() ?? '-',
                        style: PromotorText.outfit(
                          size: 14,
                          weight: FontWeight.w700,
                          color: t.textPrimary,
                        ),
                      ),
                    ),
                    _statusChip(item['lifecycle_status']?.toString() ?? '-'),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '${item['product_label'] ?? '-'} · ${item['customer_phone'] ?? '-'}',
                  style: PromotorText.outfit(size: 12, color: t.textPrimary),
                ),
                const SizedBox(height: 4),
                Text(
                  _dateFormat.format(
                    DateTime.tryParse('${item['application_date']}') ??
                        DateTime.now(),
                  ),
                  style: PromotorText.outfit(size: 12, color: t.textPrimary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap untuk lihat detail',
                  style: PromotorText.outfit(
                    size: 11,
                    weight: FontWeight.w700,
                    color: t.primaryAccent,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReminderTab() {
    if (_reminders.isEmpty) {
      return _buildEmptyState('Belum ada reminder follow-up.');
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: _reminders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final item = _reminders[index];
        final isDone = item['status'] == 'done';
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: t.surface1,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: isDone ? t.success : t.surface3),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item['reminder_title']?.toString() ?? '-',
                      style: PromotorText.outfit(
                        size: 14,
                        weight: FontWeight.w700,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item['reminder_body']?.toString() ?? '-',
                      style: PromotorText.outfit(
                        size: 12,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _dateFormat.format(
                        DateTime.tryParse('${item['scheduled_date']}') ??
                            DateTime.now(),
                      ),
                      style: PromotorText.outfit(
                        size: 12,
                        color: t.primaryAccent,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              IconButton.filledTonal(
                onPressed: isDone
                    ? null
                    : () => _markReminderDone(item['id'] as String),
                icon: Icon(isDone ? Icons.check_circle : Icons.task_alt),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusChip(String status) {
    late final Color color;
    late final String label;
    switch (status) {
      case 'closed_direct':
        color = t.success;
        label = 'Closing Direct';
        break;
      case 'closed_follow_up':
        color = t.success.withValues(alpha: 0.8);
        label = 'Closing Follow-up';
        break;
      case 'approved_pending':
        color = t.warning;
        label = 'Pending';
        break;
      case 'rejected':
        color = t.danger;
        label = 'Reject';
        break;
      default:
        color = t.textSecondary;
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Text(
        label,
        style: PromotorText.outfit(
          size: 11,
          color: color,
          weight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEmptyState(String text) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          text,
          style: PromotorText.outfit(size: 13, color: t.textSecondary),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    if (widget.inputOnly) {
      return Scaffold(
        backgroundColor: t.shellBackground,
        body: _isLoading
            ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(0, 16, 0, 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(
                        title: 'Input VAST',
                        subtitle: 'Form pengajuan VAST Finance',
                      ),
                      _buildSectionCard('Input Pengajuan', _buildInputTab()),
                    ],
                  ),
                ),
              ),
      );
    }

    return Scaffold(
      backgroundColor: t.shellBackground,
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: t.primaryAccent))
          : RefreshIndicator(
              onRefresh: _refresh,
              color: t.primaryAccent,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(0, 16, 0, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(showPeriodTabs: true),
                    _buildHeroCard(),
                    _buildQuickActions(),
                    const SizedBox(height: 14),
                    _buildActiveSection(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildHeader({
    String title = 'VAST Finance',
    String? subtitle,
    bool showPeriodTabs = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: t.surface1,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: t.surface3),
                  ),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: t.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _promotorName.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 9,
                        weight: FontWeight.w700,
                        color: t.primaryAccent,
                        letterSpacing: 1.4,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      style: PromotorText.display(
                        size: 20,
                        color: t.textPrimary,
                      ),
                    ),
                    Text(
                      subtitle ??
                          (_store?['stores']?['store_name']?.toString() ??
                              DateFormat(
                                'MMMM yyyy',
                                'id_ID',
                              ).format(DateTime.now())),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PromotorText.outfit(
                        size: 11,
                        weight: FontWeight.w700,
                        color: t.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (showPeriodTabs) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _periodSubtitle(_currentPeriodStats()),
                    style: PromotorText.outfit(
                      size: 12,
                      weight: FontWeight.w700,
                      color: t.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: MediaQuery.of(context).size.width * 0.48,
                  child: _buildPeriodTabs(compact: true),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildHeroCard() {
    final stats = _currentPeriodStats();
    final percent = _currentPeriodPercent(stats);
    return PromotorCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ringkasan Pengajuan',
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.primaryAccent,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Status kerja ${_selectedPeriodTab == 'harian'
                ? 'hari ini'
                : _selectedPeriodTab == 'mingguan'
                ? 'minggu ini'
                : 'bulan ini'}',
            style: PromotorText.outfit(size: 11, color: t.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            'Pencapaian $percent%',
            style: PromotorText.outfit(
              size: 12,
              weight: FontWeight.w700,
              color: t.primaryAccent,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _summaryMetric('Target', '${stats?.target ?? 0}'),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryMetric(
                  'Pengajuan',
                  '${stats?.submissions ?? 0}',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _summaryMetric('Reject', '${stats?.reject ?? 0}'),
              ),
              const SizedBox(width: 8),
              Expanded(child: _summaryMetric('ACC', '${stats?.acc ?? 0}')),
            ],
          ),
          if (_selectedPeriodTab == 'mingguan' &&
              _weeklyBreakdown.isNotEmpty) ...[
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List<Widget>.generate(_weeklyBreakdown.length, (
                  index,
                ) {
                  final week = _weeklyBreakdown[index];
                  final active = index == _currentWeekIndex();
                  return Padding(
                    padding: EdgeInsets.only(
                      right: index == _weeklyBreakdown.length - 1 ? 0 : 8,
                    ),
                    child: _buildWeekStatCard(week, active: active),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWeekStatCard(_VastWeekSplit week, {required bool active}) {
    final percent = week.target <= 0
        ? 0
        : ((week.submissions / week.target) * 100).round();
    return Container(
      width: 116,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: active ? t.primaryAccent.withValues(alpha: 0.12) : t.surface2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: active ? t.primaryAccent : t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            week.label,
            style: PromotorText.outfit(
              size: 10,
              weight: FontWeight.w700,
              color: active ? t.primaryAccent : t.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${week.submissions}/${week.target}',
            style: PromotorText.display(size: 16, color: t.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            '$percent%',
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.primaryAccent,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodTabs({bool compact = false}) {
    final tabs = const [
      ('harian', 'Harian'),
      ('mingguan', 'Mingguan'),
      ('bulanan', 'Bulanan'),
    ];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: t.surface3),
      ),
      child: Row(
        children: tabs.map((tab) {
          final active = _selectedPeriodTab == tab.$1;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _selectedPeriodTab = tab.$1),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  color: active ? t.primaryAccent : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  tab.$2,
                  textAlign: TextAlign.center,
                  style: PromotorText.outfit(
                    size: compact ? 10 : 11,
                    weight: FontWeight.w700,
                    color: active ? t.textOnAccent : t.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildQuickActions() {
    final items = <_PromotorAction>[
      const _PromotorAction(
        keyName: 'input',
        icon: Icons.add_card_outlined,
        label: 'Input',
      ),
      const _PromotorAction(
        keyName: 'pending',
        icon: Icons.hourglass_top_outlined,
        label: 'Pending',
      ),
      const _PromotorAction(
        keyName: 'history',
        icon: Icons.history_outlined,
        label: 'History',
      ),
      const _PromotorAction(
        keyName: 'reminder',
        icon: Icons.notifications_active_outlined,
        label: 'Reminder',
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tahapan VAST'.toUpperCase(),
            style: PromotorText.outfit(
              size: 11,
              weight: FontWeight.w700,
              color: t.textMuted,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: items.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 1.08,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
            ),
            itemBuilder: (context, index) {
              final item = items[index];
              final active = _activeSection == item.keyName;
              return GestureDetector(
                onTap: () {
                  if (item.keyName == 'input') {
                    context.push('/promotor/vast/input');
                    return;
                  }
                  setState(() => _activeSection = item.keyName);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 6,
                  ),
                  decoration: BoxDecoration(
                    color: active
                        ? t.primaryAccent.withValues(alpha: 0.14)
                        : t.surface1,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: active && item.keyName != 'input'
                          ? t.primaryAccent
                          : t.surface3,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: t.primaryAccent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          item.icon,
                          size: 15,
                          color: t.primaryAccent,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        item.label,
                        textAlign: TextAlign.center,
                        style: PromotorText.outfit(
                          size: 8,
                          weight: FontWeight.w700,
                          color: active && item.keyName != 'input'
                              ? t.primaryAccent
                              : t.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildActiveSection() {
    switch (_activeSection) {
      case 'input':
        return _buildSectionCard('Input Pengajuan', _buildInputTab());
      case 'pending':
        return _buildSectionCard('Pending Follow-up', _buildPendingTab());
      case 'history':
        return _buildSectionCard('History Pengajuan', _buildHistoryTab());
      case 'reminder':
        return _buildSectionCard('Reminder Cicilan', _buildReminderTab());
      default:
        return _buildSectionCard('Input Pengajuan', _buildInputTab());
    }
  }

  Widget _buildSectionCard(String title, Widget child) {
    return PromotorCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                style: PromotorText.outfit(
                  size: 14,
                  weight: FontWeight.w700,
                  color: t.textSecondary,
                ),
              ),
            ),
          ),
          Divider(height: 1, color: t.surface3),
          child,
        ],
      ),
    );
  }

  Widget _buildPickerField({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool hasError = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: InputDecorator(
        decoration: _inputDecoration(label).copyWith(
          errorText: hasError ? 'Wajib dipilih' : null,
          suffixIcon: Icon(
            Icons.keyboard_arrow_down_rounded,
            color: t.textMuted,
          ),
        ),
        child: Text(
          value,
          style: PromotorText.outfit(
            size: 15,
            weight: FontWeight.w700,
            color: value.startsWith('Tap untuk')
                ? t.textSecondary
                : t.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _PromotorAction {
  const _PromotorAction({
    required this.keyName,
    required this.icon,
    required this.label,
  });

  final String keyName;
  final IconData icon;
  final String label;
}

class _VastPeriodStats {
  const _VastPeriodStats({
    required this.start,
    required this.end,
    required this.target,
    required this.submissions,
    required this.acc,
    required this.reject,
  });

  final DateTime start;
  final DateTime end;
  final int target;
  final int submissions;
  final int acc;
  final int reject;
}

class _VastWeekSplit {
  const _VastWeekSplit({
    required this.label,
    required this.target,
    required this.submissions,
    required this.acc,
    required this.reject,
  });

  final String label;
  final int target;
  final int submissions;
  final int acc;
  final int reject;
}

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class _OptionPickerSheet extends StatefulWidget {
  const _OptionPickerSheet({
    required this.title,
    required this.options,
    required this.selectedValue,
    this.searchHint,
    this.labelBuilder,
  });

  final String title;
  final List<String> options;
  final String? selectedValue;
  final String? searchHint;
  final String Function(String value)? labelBuilder;

  @override
  State<_OptionPickerSheet> createState() => _OptionPickerSheetState();
}

class _OptionPickerSheetState extends State<_OptionPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    final options = widget.options.where((option) {
      final label = (widget.labelBuilder?.call(option) ?? option).toLowerCase();
      return _query.trim().isEmpty ||
          label.contains(_query.trim().toLowerCase());
    }).toList();

    return FractionallySizedBox(
      heightFactor: 0.86,
      child: Container(
        decoration: BoxDecoration(
          color: t.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: PromotorText.display(
                        size: 18,
                        color: t.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _searchController,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: widget.searchHint ?? 'Cari opsi',
                  prefixIcon: Icon(Icons.search, color: t.textMuted),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _query = '');
                          },
                          icon: Icon(Icons.close, color: t.textMuted),
                        ),
                  filled: true,
                  fillColor: t.surface1,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: t.surface3),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: t.surface3),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                itemCount: options.length,
                separatorBuilder: (context, index) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final option = options[index];
                  final selected = option == widget.selectedValue;
                  final label = widget.labelBuilder?.call(option) ?? option;
                  return InkWell(
                    onTap: () => Navigator.of(context).pop(option),
                    borderRadius: BorderRadius.circular(14),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: selected ? t.primaryAccentSoft : t.surface1,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? t.primaryAccent : t.surface3,
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              label,
                              style: PromotorText.outfit(
                                size: 14,
                                weight: FontWeight.w700,
                                color: selected
                                    ? t.primaryAccent
                                    : t.textPrimary,
                              ),
                            ),
                          ),
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            color: selected ? t.primaryAccent : t.textMuted,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
