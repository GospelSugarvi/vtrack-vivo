import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/core/utils/success_dialog.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class LaporanAllbrandInputPage extends StatefulWidget {
  const LaporanAllbrandInputPage({super.key});

  @override
  State<LaporanAllbrandInputPage> createState() =>
      _LaporanAllbrandInputPageState();
}

class _LaporanAllbrandInputPageState extends State<LaporanAllbrandInputPage> {
  static const List<String> _brands = <String>[
    'Samsung',
    'OPPO',
    'Realme',
    'Xiaomi',
    'Infinix',
    'Tecno',
  ];

  static const List<String> _priceRanges = <String>[
    'under_2m',
    '2m_4m',
    '4m_6m',
    'above_6m',
  ];

  static const Map<String, String> _priceLabels = <String, String>{
    'under_2m': '< 2 Jt',
    '2m_4m': '2-4 Jt',
    '4m_6m': '4-6 Jt',
    'above_6m': '> 6 Jt',
  };

  static const List<String> _leasingProviders = <String>[
    'HCI',
    'Kredivo',
    'FIF',
    'Indodana',
    'Kredit Plus',
    'Home Credit',
    'VAST Finance',
  ];

  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;
  final _formKey = GlobalKey<FormState>(
    debugLabel: 'laporan_allbrand_input_form',
  );
  final _notesController = TextEditingController();

  late final Map<String, Map<String, TextEditingController>> _brandControllers;
  late final Map<String, TextEditingController> _leasingControllers;

  bool _isLoading = true;
  bool _isSaving = false;
  String? _storeId;
  String _storeName = '-';
  String? _existingReportId;
  String? _reportOwnerId;
  Map<String, dynamic> _vivoAutoData = const <String, dynamic>{};
  int _vivoPromotorCount = 0;
  final Set<String> _expandedBrands = <String>{};

  @override
  void initState() {
    super.initState();
    _brandControllers = {
      for (final brand in _brands)
        brand: {
          for (final key in <String>[..._priceRanges, 'promotor_count'])
            key: TextEditingController(text: '0'),
        },
    };
    _leasingControllers = {
      for (final provider in _leasingProviders)
        provider: TextEditingController(text: '0'),
    };
    _loadStore();
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final brandMap in _brandControllers.values) {
      for (final controller in brandMap.values) {
        controller.dispose();
      }
    }
    for (final controller in _leasingControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadStore() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User tidak ditemukan');

      final assignmentRows = await _supabase
          .from('assignments_promotor_store')
          .select('store_id, stores(store_name)')
          .eq('promotor_id', userId)
          .eq('active', true)
          .order('created_at', ascending: false)
          .limit(1);

      final assignments = List<Map<String, dynamic>>.from(assignmentRows);
      final assignment = assignments.isNotEmpty ? assignments.first : null;
      final storeId = assignment?['store_id']?.toString();

      Map<String, dynamic>? todayReport;
      Map<String, dynamic> vivoAuto = const <String, dynamic>{};
      var vivoPromotorCount = 0;
      if (storeId != null && storeId.isNotEmpty) {
        final today = DateTime.now().toIso8601String().split('T').first;
        todayReport = await _supabase
            .from('allbrand_reports')
            .select(
              'id, promotor_id, brand_data, brand_data_daily, leasing_sales, leasing_sales_daily, '
              'vivo_auto_data, vivo_promotor_count, notes',
            )
            .eq('store_id', storeId)
            .eq('report_date', today)
            .order('updated_at', ascending: false)
            .order('created_at', ascending: false)
            .limit(1)
            .maybeSingle();

        final vivoRaw = await _supabase.rpc(
          'get_vivo_auto_data',
          params: {
            'p_store_id': storeId,
            'p_date': today,
          },
        );
        if (vivoRaw is Map) {
          vivoAuto = Map<String, dynamic>.from(vivoRaw);
        }

        final teamRows = await _supabase
            .from('assignments_promotor_store')
            .select('promotor_id')
            .eq('store_id', storeId)
            .eq('active', true)
            .order('created_at', ascending: false);
        final promotorIds = List<Map<String, dynamic>>.from(teamRows)
            .map((row) => row['promotor_id']?.toString() ?? '')
            .where((id) => id.isNotEmpty)
            .toSet();
        vivoPromotorCount = promotorIds.length;
      }

      _prefillForm(todayReport);

      if (!mounted) return;
      setState(() {
        _storeId = storeId;
        _storeName = '${assignment?['stores']?['store_name'] ?? '-'}';
        _existingReportId = todayReport?['id']?.toString();
        _reportOwnerId = todayReport?['promotor_id']?.toString();
        _vivoAutoData = vivoAuto;
        _vivoPromotorCount = vivoPromotorCount;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  void _prefillForm(Map<String, dynamic>? report) {
    final brandData = _safeMap(report?['brand_data_daily'] ?? report?['brand_data']);
    final leasingData = _safeMap(
      report?['leasing_sales_daily'] ?? report?['leasing_sales'],
    );

    for (final brand in _brands) {
      final values = _safeMap(brandData[brand]);
      final brandControllers = _brandControllers[brand]!;
      for (final key in brandControllers.keys) {
        brandControllers[key]!.text = '${_toInt(values[key])}';
      }
    }

    for (final provider in _leasingProviders) {
      _leasingControllers[provider]!.text = '${_toInt(leasingData[provider])}';
    }
    _notesController.text = '${report?['notes'] ?? ''}';
  }

  Map<String, dynamic> _safeMap(dynamic value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  int _controllerInt(TextEditingController controller) {
    return int.tryParse(controller.text.trim()) ?? 0;
  }

  Map<String, dynamic> _buildBrandPayload() {
    final payload = <String, dynamic>{};
    for (final brand in _brands) {
      final controllers = _brandControllers[brand]!;
      payload[brand] = <String, dynamic>{
        for (final entry in controllers.entries)
          entry.key: _controllerInt(entry.value),
      };
    }
    return payload;
  }

  Map<String, dynamic> _buildLeasingPayload() {
    return <String, dynamic>{
      for (final entry in _leasingControllers.entries)
        entry.key: _controllerInt(entry.value),
    };
  }

  int _brandSectionTotal(String brand) {
    final controllers = _brandControllers[brand]!;
    var total = 0;
    for (final key in _priceRanges) {
      total += _controllerInt(controllers[key]!);
    }
    return total;
  }

  Widget _buildSectionShell({
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: t.surface3),
      ),
      child: child,
    );
  }

  Widget _buildMiniStat(String label, int value, {Color? tone}) {
    final color = tone ?? t.textPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: (tone ?? t.surface2).withValues(alpha: tone == null ? 1 : 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: tone == null ? t.surface3 : color.withValues(alpha: 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: t.textMutedStrong,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$value',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    double width = 84,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 2, bottom: 4),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: t.textMutedStrong,
              ),
            ),
          ),
          TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            onTap: () {
              final text = controller.text.trim();
              if (text == '0') {
                controller.selection = TextSelection(
                  baseOffset: 0,
                  extentOffset: controller.text.length,
                );
              }
            },
            decoration: InputDecoration(
              isDense: true,
              hintText: '0',
              filled: true,
              fillColor: t.surface2,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 10,
              ),
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

  Widget _buildBrandSection(String brand) {
    final controllers = _brandControllers[brand]!;
    final isExpanded = _expandedBrands.contains(brand);
    return _buildSectionShell(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () {
              setState(() {
                if (isExpanded) {
                  _expandedBrands.remove(brand);
                } else {
                  _expandedBrands.add(brand);
                }
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      brand,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: t.textPrimary,
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
                      '${_brandSectionTotal(brand)} unit',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: t.textMutedStrong,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: t.textMutedStrong,
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 160),
            crossFadeState: isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final key in _priceRanges)
                    _buildNumberField(
                      controller: controllers[key]!,
                      label: _priceLabels[key]!,
                      width: 78,
                    ),
                  _buildNumberField(
                    controller: controllers['promotor_count']!,
                    label: 'Promotor',
                    width: 86,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeasingSection() {
    return _buildSectionShell(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Leasing',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final provider in _leasingProviders)
                _buildNumberField(
                  controller: _leasingControllers[provider]!,
                  label: provider,
                  width: 100,
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVivoAutoCard() {
    final total = _toInt(_vivoAutoData['total']);
    return _buildSectionShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'VIVO',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: t.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: t.primaryAccentSoft,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$total unit',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: t.primaryAccent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final key in _priceRanges)
                SizedBox(
                  width: 86,
                  child: _buildMiniStat(
                    _priceLabels[key]!,
                    _toInt(_vivoAutoData[key]),
                    tone: t.primaryAccent,
                  ),
                ),
              SizedBox(
                width: 86,
                child: _buildMiniStat(
                  'Promotor',
                  _vivoPromotorCount,
                  tone: t.primaryAccent,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_storeId == null) return;
    if (!mounted) return;

    setState(() => _isSaving = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('User tidak ditemukan');
      final ownerId = _reportOwnerId ?? userId;

      final reportDate = DateTime.now().toIso8601String().split('T').first;
      final brandPayload = _buildBrandPayload();
      final leasingPayload = _buildLeasingPayload();
      await _supabase.rpc(
        'upsert_allbrand_report_store_daily',
        params: {
          'p_existing_id': _existingReportId,
          'p_promotor_id': ownerId,
          'p_store_id': _storeId,
          'p_report_date': reportDate,
          'p_brand_data_daily': brandPayload,
          'p_leasing_sales_daily': leasingPayload,
          'p_vivo_auto_data': _vivoAutoData,
          'p_vivo_promotor_count': _vivoPromotorCount,
          'p_notes': _notesController.text.trim(),
        },
      );

      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: _existingReportId == null
            ? 'Laporan all brand berhasil dikirim.'
            : 'Laporan all brand berhasil diperbarui.',
      );
      if (!mounted) return;
      context.pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal kirim laporan: $e')));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: const Text('Input All Brand')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionShell(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Toko Aktif',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: t.textMutedStrong,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _storeName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: t.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildVivoAutoCard(),
                  const SizedBox(height: 16),
                  for (final brand in _brands) _buildBrandSection(brand),
                  const SizedBox(height: 4),
                  _buildLeasingSection(),
                  const SizedBox(height: 12),
                  _buildSectionShell(
                    child: TextFormField(
                      controller: _notesController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Catatan tambahan',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: _isSaving ? null : _submit,
                    child: Text(
                      _isSaving
                          ? 'Sedang mengirim...'
                          : 'Kirim',
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
