// ignore_for_file: unused_field, unused_element
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../main.dart';
import '../../../../ui/foundation/app_colors.dart';
import '../widgets/admin_dialog_sync.dart';
import 'package:vtrack/core/utils/success_dialog.dart';

// Rupiah Input Formatter - auto formats as: 1.000.000
class RupiahInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;

    // Remove non-digits
    final numericOnly = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    if (numericOnly.isEmpty) return const TextEditingValue(text: '');

    // Format with thousand separators
    final number = int.parse(numericOnly);
    final formatted = number.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m.group(1)}.',
    );

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

// Parse Rupiah string back to int
int parseRupiah(String? text) {
  if (text == null || text.isEmpty) return 0;
  return int.tryParse(text.replaceAll('.', '')) ?? 0;
}

// Clean InputDecoration helper - prevents label overlap
InputDecoration inputDeco(
  String label, {
  String? prefix,
  String? suffix,
  String? hint,
}) {
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixText: prefix,
    suffixText: suffix,
    border: const OutlineInputBorder(),
    filled: true,
    fillColor: AppColors.background,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
    floatingLabelBehavior: FloatingLabelBehavior.always,
  );
}

class AdminBonusPage extends StatefulWidget {
  const AdminBonusPage({super.key});

  @override
  State<AdminBonusPage> createState() => _AdminBonusPageState();
}

class _AdminBonusPageState extends State<AdminBonusPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Promotor data
  List<Map<String, dynamic>> _rangeRules = [];
  List<Map<String, dynamic>> _flatRules = [];
  List<Map<String, dynamic>> _ratioProducts = [];

  // Sator/SPV data
  List<Map<String, dynamic>> _satorKpi = [];
  List<Map<String, dynamic>> _spvKpi = [];
  List<Map<String, dynamic>> _satorKpiTemplates = [];
  List<Map<String, dynamic>> _spvKpiTemplates = [];
  List<Map<String, dynamic>> _satorPointRanges = [];
  List<Map<String, dynamic>> _spvPointRanges = [];
  List<Map<String, dynamic>> _satorRewards = [];
  List<Map<String, dynamic>> _spvRewards = [];
  List<Map<String, dynamic>> _specialBundles = [];

  // Reward period selector (tipe khusus per bulan)
  List<Map<String, dynamic>> _rewardPeriods = [];
  String? _selectedRewardPeriodId;

  List<Map<String, dynamic>> _products = [];
  bool _isLoading = true;
  String? _lastErrorText;
  final Map<String, Map<String, _PointRangeEdit>> _pointRangeEdits = {
    'sator': {},
    'spv': {},
  };
  final Map<String, bool> _isEditingPointRanges = {
    'sator': false,
    'spv': false,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() => setState(() {}));
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final roleEntries in _pointRangeEdits.values) {
      for (final edit in roleEntries.values) {
        edit.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      _clearError();
      await _loadRewardPeriods();
      await _loadKpiConfigs();

      // Promotor Range Bonus
      final rangeRes = await supabase
          .from('bonus_rules')
          .select('*')
          .eq('bonus_type', 'range')
          .order('min_price');
      _rangeRules = List<Map<String, dynamic>>.from(rangeRes);

      // Promotor Flat Bonus
      final flatRes = await supabase
          .from('bonus_rules')
          .select('*, products(model_name, network_type)')
          .eq('bonus_type', 'flat');
      _flatRules = List<Map<String, dynamic>>.from(flatRes);

      // Promotor Ratio Products
      final ratioRes = await supabase
          .from('bonus_rules')
          .select('*, products(model_name, network_type)')
          .eq('bonus_type', 'ratio');
      _ratioProducts = List<Map<String, dynamic>>.from(ratioRes);

      // Point Ranges
      final satorPtRes = await supabase
          .from('point_ranges')
          .select('*')
          .eq('role', 'sator')
          .order('min_price');
      _satorPointRanges = List<Map<String, dynamic>>.from(satorPtRes);
      _syncPointRangeEdits('sator', _satorPointRanges);

      final spvPtRes = await supabase
          .from('point_ranges')
          .select('*')
          .eq('role', 'spv')
          .order('min_price');
      _spvPointRanges = List<Map<String, dynamic>>.from(spvPtRes);
      _syncPointRangeEdits('spv', _spvPointRanges);

      // Load special bundles + rewards for selected period
      await _loadSpecialBundles();
      await _loadSpecialRewards();

      // Products for dropdowns
      final productsRes = await supabase
          .from('products')
          .select('id, model_name, network_type')
          .isFilter('deleted_at', null)
          .order('model_name');
      _products = List<Map<String, dynamic>>.from(productsRes);

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e, stack) {
      _reportError('Admin reward load failed', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
    }
  }

  void _clearError() {
    _lastErrorText = null;
  }

  void _reportError(String contextLabel, Object error, StackTrace stack) {
    final text = [
      contextLabel,
      'Time: ${DateTime.now().toIso8601String()}',
      'Error: $error',
      'Stack:',
      '$stack',
    ].join('\n');
    debugPrint(text);
    _lastErrorText = text;
  }

  Future<void> _copyLastError() async {
    final text = _lastErrorText;
    if (text == null || text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Error berhasil dicopy')));
  }

  Future<void> _loadRewardPeriods() async {
    final res = await supabase
        .from('target_periods')
        .select('*')
        .order('start_date', ascending: false);
    _rewardPeriods = List<Map<String, dynamic>>.from(res);
    if (_selectedRewardPeriodId == null && _rewardPeriods.isNotEmpty) {
      _selectedRewardPeriodId = _rewardPeriods[0]['id'].toString();
    }
  }

  Future<void> _loadSpecialBundles() async {
    if (_selectedRewardPeriodId == null) return;
    final res = await supabase
        .from('special_focus_bundles')
        .select('id, bundle_name, period_id, special_focus_bundle_products(*)')
        .eq('period_id', _selectedRewardPeriodId!);
    _specialBundles = List<Map<String, dynamic>>.from(res);
  }

  Future<void> _loadSpecialRewards() async {
    if (_selectedRewardPeriodId == null) return;
    final res = await supabase
        .from('special_reward_configs')
        .select(
          '*, special_focus_bundles!special_reward_configs_special_bundle_id_fkey(id, bundle_name, period_id)',
        )
        .eq('period_id', _selectedRewardPeriodId!)
        .order('role')
        .order('special_bundle_id');
    final rows = List<Map<String, dynamic>>.from(res);
    _satorRewards = rows.where((r) => r['role'] == 'sator').toList();
    _spvRewards = rows.where((r) => r['role'] == 'spv').toList();
  }

  Future<void> _loadKpiConfigs() async {
    if (_selectedRewardPeriodId == null) {
      _satorKpi = [];
      _spvKpi = [];
      _satorKpiTemplates = [];
      _spvKpiTemplates = [];
      return;
    }

    await supabase.rpc(
      'ensure_kpi_period_settings',
      params: {'p_period_id': _selectedRewardPeriodId, 'p_role': 'sator'},
    );
    await supabase.rpc(
      'ensure_kpi_period_settings',
      params: {'p_period_id': _selectedRewardPeriodId, 'p_role': 'spv'},
    );

    final templateRes = await supabase
        .from('kpi_metric_templates')
        .select('*')
        .order('role')
        .order('sort_order')
        .order('display_name');
    final templates = List<Map<String, dynamic>>.from(templateRes);
    _satorKpiTemplates = templates.where((row) => row['role'] == 'sator').toList();
    _spvKpiTemplates = templates.where((row) => row['role'] == 'spv').toList();

    final periodRes = await supabase
        .from('kpi_period_settings')
        .select('*')
        .eq('period_id', _selectedRewardPeriodId!)
        .eq('is_active', true)
        .order('role')
        .order('sort_order')
        .order('display_name');
    final settings = List<Map<String, dynamic>>.from(periodRes);
    _satorKpi = settings.where((row) => row['role'] == 'sator').toList();
    _spvKpi = settings.where((row) => row['role'] == 'spv').toList();
  }

  void _syncPointRangeEdits(String role, List<Map<String, dynamic>> data) {
    _pointRangeEdits[role]!.clear();
    for (var r in data) {
      final id = r['id'].toString();
      _pointRangeEdits[role]![id] = _PointRangeEdit(
        dataSource: r['data_source'] ?? 'sell_out',
        minC: TextEditingController(text: _formatPrice(r['min_price'])),
        maxC: TextEditingController(text: _formatPrice(r['max_price'])),
        pointsC: TextEditingController(text: r['points_per_unit'].toString()),
      );
    }
  }

  void _showEditRangeDialog(Map<String, dynamic> r) {
    final minC = TextEditingController(text: _formatPrice(r['min_price']));
    final maxC = TextEditingController(text: _formatPrice(r['max_price']));
    final officialC = TextEditingController(
      text: _formatPrice(r['bonus_official'] ?? r['bonus_amount']),
    );
    final trainingC = TextEditingController(
      text: _formatPrice(r['bonus_training']),
    );
    _showFormDialog(
      'Edit Range Bonus',
      [
        TextField(
          controller: minC,
          decoration: inputDeco('Min Harga', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: maxC,
          decoration: inputDeco('Max Harga', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: officialC,
          decoration: inputDeco('Bonus Official', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: trainingC,
          decoration: inputDeco('Bonus Training', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
      ],
      () async {
        await supabase
            .from('bonus_rules')
            .update({
              'min_price': parseRupiah(minC.text),
              'max_price': parseRupiah(maxC.text),
              'bonus_official': parseRupiah(officialC.text),
              'bonus_training': parseRupiah(trainingC.text),
            })
            .eq('id', r['id']);
      },
    );
  }

  void _showAddRangeDialog() {
    final minC = TextEditingController();
    final maxC = TextEditingController();
    final officialC = TextEditingController();
    final trainingC = TextEditingController();
    _showFormDialog(
      'Tambah Range Bonus',
      [
        TextField(
          controller: minC,
          decoration: inputDeco('Min Harga', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: maxC,
          decoration: inputDeco('Max Harga', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: officialC,
          decoration: inputDeco('Bonus Official', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: trainingC,
          decoration: inputDeco('Bonus Training', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
      ],
      () async {
        await supabase.from('bonus_rules').insert({
          'bonus_type': 'range',
          'min_price': parseRupiah(minC.text),
          'max_price': parseRupiah(maxC.text),
          'bonus_official': parseRupiah(officialC.text),
          'bonus_training': parseRupiah(trainingC.text),
        });
      },
    );
  }

  // ---- Flat Dialogs ----
  void _showAddFlatDialog() {
    String? selectedProductId;
    int? selectedRam;
    int? selectedStorage;
    List<Map<String, dynamic>> variantGroups = [];
    final officialC = TextEditingController();
    final trainingC = TextEditingController();

    Future<void> loadVariants(String productId, StateSetter setState) async {
      final result = await supabase
          .from('product_variants')
          .select('ram, storage, srp')
          .eq('product_id', productId)
          .isFilter('deleted_at', null)
          .order('ram')
          .order('storage');

      // Group by RAM/Storage (ignore color)
      final Map<String, Map<String, dynamic>> grouped = {};
      for (var v in result) {
        final key = '${v['ram']}_${v['storage']}';
        if (!grouped.containsKey(key)) {
          grouped[key] = {
            'ram': v['ram'],
            'storage': v['storage'],
            'srp': v['srp'],
          };
        }
      }

      setState(() {
        variantGroups = grouped.values.toList();
        selectedRam = null;
        selectedStorage = null;
      });
    }

    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Tambah Flat Bonus'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Product dropdown
                DropdownButtonFormField<String>(
                  initialValue: selectedProductId,
                  decoration: const InputDecoration(labelText: 'Produk'),
                  items: _products
                      .map(
                        (p) => DropdownMenuItem(
                          value: p['id'] as String,
                          child: Text(
                            '${p['model_name']} (${p['network_type'] ?? '4G'})',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() => selectedProductId = v);
                    if (v != null) loadVariants(v, setState);
                  },
                ),
                const SizedBox(height: 12),
                // Variant dropdown (RAM/Storage only)
                if (selectedProductId != null) ...[
                  if (variantGroups.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text(
                        'Loading varian...',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  else
                    DropdownButtonFormField<String>(
                      initialValue:
                          selectedRam != null && selectedStorage != null
                          ? '${selectedRam}_$selectedStorage'
                          : null,
                      decoration: const InputDecoration(
                        labelText:
                            'Varian (RAM/Storage) - Berlaku semua warna *',
                      ),
                      items: variantGroups
                          .map(
                            (v) => DropdownMenuItem(
                              value: '${v['ram']}_${v['storage']}',
                              child: Text(
                                '${v['ram']}GB/${v['storage']}GB (Rp ${_formatPrice(v['srp'])})',
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          final parts = v.split('_');
                          setState(() {
                            selectedRam = int.parse(parts[0]);
                            selectedStorage = int.parse(parts[1]);
                          });
                        }
                      },
                    ),
                  const SizedBox(height: 12),
                ],
                TextField(
                  controller: officialC,
                  decoration: inputDeco('Bonus Official', prefix: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: trainingC,
                  decoration: inputDeco('Bonus Training', prefix: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: selectedRam == null
                  ? null
                  : () async {
                      try {
                        await supabase.from('bonus_rules').insert({
                          'bonus_type': 'flat',
                          'product_id': selectedProductId,
                          'ram': selectedRam,
                          'storage': selectedStorage,
                          'bonus_official': parseRupiah(officialC.text),
                          'bonus_training': parseRupiah(trainingC.text),
                        });
                        if (!c.mounted) return;
                        closeAdminDialog(c, changed: true);
                      } catch (e) {
                        debugPrint('Error: $e');
                        if (!c.mounted) return;
                        _reportError(
                          'Admin reward add flat failed',
                          e,
                          StackTrace.current,
                        );
                        showErrorDialog(
                          c,
                          title: 'Gagal',
                          message: 'Error: $e',
                        );
                      }
                    },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditFlatDialog(Map<String, dynamic> rule) {
    final officialC = TextEditingController(
      text: _formatPrice(rule['bonus_official']),
    );
    final trainingC = TextEditingController(
      text: _formatPrice(rule['bonus_training']),
    );
    _showFormDialog(
      'Edit Flat Bonus',
      [
        Text(
          _formatProductVariantLabel(rule),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: officialC,
          decoration: inputDeco('Bonus Official', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: trainingC,
          decoration: inputDeco('Bonus Training', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
      ],
      () async {
        await supabase
            .from('bonus_rules')
            .update({
              'bonus_official': parseRupiah(officialC.text),
              'bonus_training': parseRupiah(trainingC.text),
            })
            .eq('id', rule['id']);
      },
    );
  }

  void _showAddRatioDialog() {
    String? selectedProductId;
    final ratioC = TextEditingController(text: '2');

    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Tambah Ratio Bonus'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedProductId,
                decoration: inputDeco('Produk'),
                items: _products
                    .map(
                      (p) => DropdownMenuItem(
                        value: '${p['id']}',
                        child: Text(
                          '${p['model_name']} (${p['network_type'] ?? '4G'})',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (v) => setState(() => selectedProductId = v),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ratioC,
                decoration: inputDeco('Nilai Ratio'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: selectedProductId == null
                  ? null
                  : () async {
                      try {
                        await supabase.from('bonus_rules').insert({
                          'bonus_type': 'ratio',
                          'product_id': selectedProductId,
                          'ratio_value': int.tryParse(ratioC.text) ?? 0,
                        });
                        if (!c.mounted) return;
                        closeAdminDialog(c, changed: true);
                      } catch (e, stack) {
                        _reportError('Admin reward add ratio failed', e, stack);
                        if (!c.mounted) return;
                        showErrorDialog(
                          c,
                          title: 'Gagal',
                          message: 'Error: $e',
                        );
                      }
                    },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRatioDialog(Map<String, dynamic> rule) {
    final ratioC = TextEditingController(text: '${rule['ratio_value'] ?? 0}');
    _showFormDialog(
      'Edit Ratio Bonus',
      [
        Text(
          _formatProductTitle(rule),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: ratioC,
          decoration: inputDeco('Nilai Ratio'),
          keyboardType: TextInputType.number,
        ),
      ],
      () async {
        await supabase
            .from('bonus_rules')
            .update({'ratio_value': int.tryParse(ratioC.text) ?? 0})
            .eq('id', rule['id']);
      },
    );
  }

  void _showEditKpiDialog(Map<String, dynamic> k) {
    final nameC = TextEditingController(
      text: '${k['display_name'] ?? k['kpi_name'] ?? ''}',
    );
    final weightC = TextEditingController(text: k['weight']?.toString());
    final descC = TextEditingController(text: '${k['description'] ?? ''}');
    _showFormDialog(
      'Edit KPI',
      [
        TextField(
          controller: nameC,
          decoration: inputDeco('Nama KPI'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: weightC,
          decoration: inputDeco('Bobot', suffix: '%'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(controller: descC, decoration: inputDeco('Deskripsi')),
      ],
      () async {
        await supabase
            .from('kpi_period_settings')
            .update({
              'display_name': nameC.text.trim(),
              'weight': int.tryParse(weightC.text) ?? 0,
              'description': descC.text.trim(),
            })
            .eq('id', k['id']);
      },
    );
  }

  void _showEditKpiTemplateDialog(Map<String, dynamic> template) {
    final nameC = TextEditingController(
      text: '${template['display_name'] ?? ''}',
    );
    final descC = TextEditingController(
      text: '${template['description'] ?? ''}',
    );
    final weightC = TextEditingController(
      text: '${template['default_weight'] ?? 0}',
    );
    final orderC = TextEditingController(text: '${template['sort_order'] ?? 0}');

    _showFormDialog(
      'Edit Template KPI',
      [
        Text(
          'Kode: ${template['metric_code'] ?? '-'}',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: nameC,
          decoration: inputDeco('Nama Template'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: weightC,
          decoration: inputDeco('Bobot Default', suffix: '%'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: orderC,
          decoration: inputDeco('Urutan'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: descC,
          decoration: inputDeco('Deskripsi'),
          minLines: 2,
          maxLines: 4,
        ),
      ],
      () async {
        await supabase
            .from('kpi_metric_templates')
            .update({
              'display_name': nameC.text.trim(),
              'default_weight': int.tryParse(weightC.text) ?? 0,
              'sort_order': int.tryParse(orderC.text) ?? 0,
              'description': descC.text.trim(),
            })
            .eq('id', template['id']);
      },
    );
  }

  Future<void> _showManageKpiDialog(String role) async {
    if (_selectedRewardPeriodId == null) return;
    final templates = role == 'sator' ? _satorKpiTemplates : _spvKpiTemplates;
    final currentRows = role == 'sator' ? _satorKpi : _spvKpi;
    final selectedCodes = {
      for (final row in currentRows) '${row['metric_code']}': true,
    };
    final weightCtrls = <String, TextEditingController>{};
    for (final template in templates) {
      final code = '${template['metric_code']}';
      final current = currentRows.cast<Map<String, dynamic>?>().firstWhere(
            (row) => row?['metric_code'] == code,
            orElse: () => null,
          );
      weightCtrls[code] = TextEditingController(
        text: '${current?['weight'] ?? template['default_weight'] ?? 0}',
      );
    }

    await showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocalState) {
          int totalSelectedWeight() {
            var total = 0;
            for (final template in templates) {
              final code = '${template['metric_code']}';
              if (selectedCodes[code] == true) {
                total += int.tryParse(weightCtrls[code]?.text ?? '0') ?? 0;
              }
            }
            return total;
          }

          return AlertDialog(
            title: Text('Atur KPI ${role.toUpperCase()}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Pilih kategori KPI untuk periode ini. Total bobot harus 100%.',
                      style: Theme.of(c).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    ...templates.map((template) {
                      final code = '${template['metric_code']}';
                      final ctrl = weightCtrls[code]!;
                      final checked = selectedCodes[code] == true;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Checkbox(
                              value: checked,
                              onChanged: (value) => setLocalState(() {
                                selectedCodes[code] = value == true;
                              }),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${template['display_name'] ?? code}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if ('${template['description'] ?? ''}'
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      '${template['description']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 90,
                              child: TextField(
                                controller: ctrl,
                                enabled: checked,
                                keyboardType: TextInputType.number,
                                decoration: inputDeco('Bobot', suffix: '%'),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    Text(
                      'Total bobot aktif: ${totalSelectedWeight()}%',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => closeAdminDialog(c),
                child: const Text('Batal'),
              ),
              ElevatedButton(
                onPressed: () async {
                  final total = totalSelectedWeight();
                  if (total != 100) {
                    if (!c.mounted) return;
                    showErrorDialog(
                      c,
                      title: 'Bobot Belum Valid',
                      message: 'Total bobot KPI aktif harus tepat 100%.',
                    );
                    return;
                  }

                  for (final template in templates) {
                    final code = '${template['metric_code']}';
                    final isActive = selectedCodes[code] == true;
                    await supabase.from('kpi_period_settings').upsert({
                      'period_id': _selectedRewardPeriodId,
                      'role': role,
                      'template_id': template['id'],
                      'metric_code': code,
                      'display_name': template['display_name'],
                      'description': template['description'],
                      'score_source': template['score_source'],
                      'score_config': template['score_config'],
                      'weight': int.tryParse(weightCtrls[code]?.text ?? '0') ?? 0,
                      'sort_order': template['sort_order'] ?? 0,
                      'is_active': isActive,
                    }, onConflict: 'period_id,role,metric_code');
                  }
                  if (!c.mounted) return;
                  closeAdminDialog(c, changed: true);
                },
                child: const Text('Simpan'),
              ),
            ],
          );
        },
      ),
    );

    for (final ctrl in weightCtrls.values) {
      ctrl.dispose();
    }
  }

  // ---- Point Range Dialogs ----
  void _showAddPointRangeDialog(String role) {
    String dataSource = 'sell_out';
    final minC = TextEditingController();
    final maxC = TextEditingController();
    final pointsC = TextEditingController();

    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Tambah Point Range'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: dataSource,
                  decoration: inputDeco('Sumber Data'),
                  items: const [
                    DropdownMenuItem(
                      value: 'sell_out',
                      child: Text('Sell Out (Penjualan Promotor)'),
                    ),
                    DropdownMenuItem(
                      value: 'sell_in',
                      child: Text('Sell In (Orderan)'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => dataSource = v ?? 'sell_out'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minC,
                  decoration: inputDeco('Min Harga', prefix: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxC,
                  decoration: inputDeco('Max Harga', prefix: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pointsC,
                  decoration: inputDeco('Poin per Unit'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await supabase.from('point_ranges').insert({
                    'role': role,
                    'data_source': dataSource,
                    'min_price': int.tryParse(minC.text) ?? 0,
                    'max_price': int.tryParse(maxC.text) ?? 0,
                    'points_per_unit': double.tryParse(pointsC.text) ?? 0,
                  });
                  if (!c.mounted) return;
                  closeAdminDialog(c, changed: true);
                } catch (e, stack) {
                  _reportError('Admin reward add point range failed', e, stack);
                  if (!c.mounted) return;
                  showErrorDialog(c, title: 'Gagal', message: 'Error: $e');
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditPointRangeDialog(String role, Map<String, dynamic> row) {
    String dataSource = '${row['data_source'] ?? 'sell_out'}';
    final minC = TextEditingController(text: _formatPrice(row['min_price']));
    final maxC = TextEditingController(text: _formatPrice(row['max_price']));
    final pointsC = TextEditingController(
      text: '${row['points_per_unit'] ?? 0}',
    );

    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: Text('Edit Point Range ${role.toUpperCase()}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: dataSource,
                  decoration: inputDeco('Sumber Data'),
                  items: const [
                    DropdownMenuItem(
                      value: 'sell_out',
                      child: Text('Sell Out (Penjualan Promotor)'),
                    ),
                    DropdownMenuItem(
                      value: 'sell_in',
                      child: Text('Sell In (Orderan)'),
                    ),
                  ],
                  onChanged: (v) =>
                      setState(() => dataSource = v ?? 'sell_out'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minC,
                  decoration: inputDeco('Min Harga', prefix: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: maxC,
                  decoration: inputDeco('Max Harga', prefix: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: pointsC,
                  decoration: inputDeco('Poin per Unit'),
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                try {
                  await supabase
                      .from('point_ranges')
                      .update({
                        'role': role,
                        'data_source': dataSource,
                        'min_price': parseRupiah(minC.text),
                        'max_price': parseRupiah(maxC.text),
                        'points_per_unit': double.tryParse(pointsC.text) ?? 0,
                      })
                      .eq('id', row['id']);
                  if (!c.mounted) return;
                  closeAdminDialog(c, changed: true);
                } catch (e, stack) {
                  _reportError(
                    'Admin reward edit point range failed',
                    e,
                    stack,
                  );
                  if (!c.mounted) return;
                  showErrorDialog(c, title: 'Gagal', message: 'Error: $e');
                }
              },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  // ---- Reward Dialogs ----
  void _showAddRewardDialog(String role) {
    String? selectedBundleId;
    final rewardC = TextEditingController();
    final penaltyThreshC = TextEditingController(text: '80');
    final penaltyAmtC = TextEditingController(text: '0');

    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (c) => StatefulBuilder(
        builder: (c, setState) => AlertDialog(
          title: const Text('Tambah Reward Tipe Khusus'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedBundleId,
                  decoration: inputDeco('Bundle Tipe Khusus'),
                  items: _specialBundles.map((b) {
                    final products = List<Map<String, dynamic>>.from(
                      b['special_focus_bundle_products'] ?? [],
                    );
                    final prodCount = products.length;
                    return DropdownMenuItem(
                      value: b['id'] as String,
                      child: Text('${b['bundle_name']} ($prodCount tipe)'),
                    );
                  }).toList(),
                  onChanged: (v) => setState(() => selectedBundleId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: rewardC,
                  decoration: inputDeco('Reward', prefix: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: penaltyThreshC,
                  decoration: inputDeco('Threshold Denda', suffix: '%'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: penaltyAmtC,
                  decoration: inputDeco('Denda', prefix: 'Rp '),
                  keyboardType: TextInputType.number,
                  inputFormatters: [RupiahInputFormatter()],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: selectedBundleId == null
                  ? null
                  : () async {
                      try {
                        await supabase.from('special_reward_configs').upsert({
                          'period_id': _selectedRewardPeriodId,
                          'role': role,
                          'special_bundle_id': selectedBundleId,
                          'reward_amount': parseRupiah(rewardC.text),
                          'penalty_threshold':
                              int.tryParse(penaltyThreshC.text) ?? 80,
                          'penalty_amount': parseRupiah(penaltyAmtC.text),
                        }, onConflict: 'period_id,role,special_bundle_id');
                        if (!c.mounted) return;
                        closeAdminDialog(c, changed: true);
                      } catch (e, stack) {
                        _reportError(
                          'Admin reward add special reward failed',
                          e,
                          stack,
                        );
                        if (!c.mounted) return;
                        showErrorDialog(
                          c,
                          title: 'Gagal',
                          message: 'Error: $e',
                        );
                      }
                    },
              child: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditRewardDialog(Map<String, dynamic> r) {
    final displayName =
        r['special_focus_bundles']?['bundle_name'] ?? 'Unknown Bundle';
    final rewardC = TextEditingController(
      text: _formatPrice(r['reward_amount']),
    );
    final penaltyThreshC = TextEditingController(
      text: r['penalty_threshold']?.toString(),
    );
    final penaltyAmtC = TextEditingController(
      text: _formatPrice(r['penalty_amount']),
    );
    _showFormDialog(
      'Edit Reward Tipe Khusus',
      [
        Text(
          'Target: $displayName',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: rewardC,
          decoration: inputDeco('Reward', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: penaltyThreshC,
          decoration: inputDeco('Threshold Denda', suffix: '%'),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        TextField(
          controller: penaltyAmtC,
          decoration: inputDeco('Denda', prefix: 'Rp '),
          keyboardType: TextInputType.number,
          inputFormatters: [RupiahInputFormatter()],
        ),
      ],
      () async {
        await supabase
            .from('special_reward_configs')
            .update({
              'reward_amount': parseRupiah(rewardC.text),
              'penalty_threshold': int.tryParse(penaltyThreshC.text) ?? 80,
              'penalty_amount': parseRupiah(penaltyAmtC.text),
            })
            .eq('id', r['id']);
      },
    );
  }

  // ---- Helper ----
  void _showFormDialog(
    String title,
    List<Widget> fields,
    Future<void> Function() onSave,
  ) {
    showAdminChangedDialog(
      context: context,
      onChanged: _loadData,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: fields),
        ),
        actions: [
          TextButton(
            onPressed: () => closeAdminDialog(c),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                await onSave();
                if (!c.mounted) return;
                closeAdminDialog(c, changed: true);
              } catch (e, stack) {
                _reportError('Admin reward save dialog failed', e, stack);
                if (!c.mounted) return;
                showErrorDialog(c, title: 'Gagal', message: 'Error: $e');
              }
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteItem({
    required String title,
    required String message,
    required Future<void> Function() onDelete,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Batal'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      await onDelete();
      await _loadData();
      if (!mounted) return;
      await showSuccessDialog(
        context,
        title: 'Berhasil',
        message: 'Pengaturan bonus berhasil dihapus',
      );
    } catch (e, stack) {
      _reportError('Admin reward delete failed', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
      await showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
    }
  }

  String _formatPrice(dynamic value) {
    final n = value is int ? value : int.tryParse(value?.toString() ?? '') ?? 0;
    return n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m.group(1)}.',
    );
  }

  String _formatNetworkType(Map<String, dynamic> row) {
    final networkType = row['products']?['network_type']?.toString().trim();
    if (networkType == null || networkType.isEmpty) return '4G';
    return networkType.toUpperCase();
  }

  String _formatProductTitle(Map<String, dynamic> row) {
    final modelName = row['products']?['model_name']?.toString().trim();
    final safeName = (modelName == null || modelName.isEmpty) ? '-' : modelName;
    return '$safeName (${_formatNetworkType(row)})';
  }

  String _formatProductVariantLabel(Map<String, dynamic> row) {
    return '${_formatProductTitle(row)} · ${row['ram'] ?? '-'}GB/${row['storage'] ?? '-'}GB';
  }

  Widget _buildEditDeleteActions({
    required VoidCallback onEdit,
    required VoidCallback onDelete,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Edit',
          icon: const Icon(Icons.edit_rounded),
          onPressed: onEdit,
        ),
        IconButton(
          tooltip: 'Hapus',
          icon: const Icon(Icons.delete_outline_rounded),
          color: AppColors.danger,
          onPressed: onDelete,
        ),
      ],
    );
  }

  String _formatPeriodLabel(Map<String, dynamic> period) {
    final name = '${period['period_name'] ?? ''}'.trim();
    if (name.isNotEmpty) return name;
    final month = period['target_month'];
    final year = period['target_year'];
    if (month is int && year is int) {
      final months = const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'Mei',
        'Jun',
        'Jul',
        'Agu',
        'Sep',
        'Okt',
        'Nov',
        'Des',
      ];
      return '${months[month]} $year';
    }
    return '-';
  }

  Future<void> _onRewardPeriodChanged(String? value) async {
    if (value == null || value == _selectedRewardPeriodId) return;
    setState(() {
      _selectedRewardPeriodId = value;
      _isLoading = true;
    });
    try {
      await _loadKpiConfigs();
      await _loadSpecialBundles();
      await _loadSpecialRewards();
      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e, stack) {
      _reportError('Admin reward period change failed', e, stack);
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorDialog(context, title: 'Gagal', message: 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan Bonus'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Promotor'),
            Tab(text: 'Sator'),
            Tab(text: 'SPV'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_lastErrorText != null) _buildErrorPanel(),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildPromotorTab(),
                      _buildSatorTab(),
                      _buildSpvTab(),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildErrorPanel() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: AppColors.danger),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Terjadi error di menu reward',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.danger,
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _copyLastError,
                icon: const Icon(Icons.copy_all_rounded, size: 16),
                label: const Text('Copy error'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            _lastErrorText!,
            maxLines: 6,
            style: const TextStyle(
              fontSize: 12,
              height: 1.35,
              color: AppColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromotorTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOverviewCard(
          title: 'Bonus Promotor',
          subtitle:
              'Atur range bonus, flat bonus per varian, dan ratio product.',
          metrics: [
            _MetricData('Range', '${_rangeRules.length}'),
            _MetricData('Flat', '${_flatRules.length}'),
            _MetricData('Ratio', '${_ratioProducts.length}'),
          ],
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'Range Bonus',
          actionLabel: 'Tambah',
          onAction: _showAddRangeDialog,
          children: _rangeRules.isEmpty
              ? [_buildEmptyTile('Belum ada range bonus')]
              : _rangeRules
                    .map(
                      (r) => _buildConfigTile(
                        title:
                            'Rp ${_formatPrice(r['min_price'])} - Rp ${_formatPrice(r['max_price'])}',
                        subtitle:
                            'Official Rp ${_formatPrice(r['bonus_official'])} · Training Rp ${_formatPrice(r['bonus_training'])}',
                        trailing: _buildEditDeleteActions(
                          onEdit: () => _showEditRangeDialog(r),
                          onDelete: () => _confirmDeleteItem(
                            title: 'Hapus Range Bonus',
                            message:
                                'Range bonus ini akan dihapus dari pengaturan. Lanjutkan?',
                            onDelete: () => supabase
                                .from('bonus_rules')
                                .delete()
                                .eq('id', r['id']),
                          ),
                        ),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Flat Bonus',
          actionLabel: 'Tambah',
          onAction: _showAddFlatDialog,
          children: _flatRules.isEmpty
              ? [_buildEmptyTile('Belum ada flat bonus')]
              : _flatRules
                    .map(
                      (r) => _buildConfigTile(
                        title: _formatProductVariantLabel(r),
                        subtitle:
                            'Official Rp ${_formatPrice(r['bonus_official'])} · Training Rp ${_formatPrice(r['bonus_training'])}',
                        trailing: _buildEditDeleteActions(
                          onEdit: () => _showEditFlatDialog(r),
                          onDelete: () => _confirmDeleteItem(
                            title: 'Hapus Flat Bonus',
                            message:
                                'Flat bonus untuk ${_formatProductVariantLabel(r)} akan dihapus. Lanjutkan?',
                            onDelete: () => supabase
                                .from('bonus_rules')
                                .delete()
                                .eq('id', r['id']),
                          ),
                        ),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Ratio Product',
          actionLabel: 'Tambah',
          onAction: _showAddRatioDialog,
          children: _ratioProducts.isEmpty
              ? [_buildEmptyTile('Belum ada ratio bonus')]
              : _ratioProducts
                    .map(
                      (r) => _buildConfigTile(
                        title: _formatProductTitle(r),
                        subtitle: 'Ratio ${r['ratio_value'] ?? 0}:1',
                        trailing: _buildEditDeleteActions(
                          onEdit: () => _showEditRatioDialog(r),
                          onDelete: () => _confirmDeleteItem(
                            title: 'Hapus Ratio Bonus',
                            message:
                                'Ratio bonus untuk ${_formatProductTitle(r)} akan dihapus. Lanjutkan?',
                            onDelete: () => supabase
                                .from('bonus_rules')
                                .delete()
                                .eq('id', r['id']),
                          ),
                        ),
                      ),
                    )
                    .toList(),
        ),
      ],
    );
  }

  Widget _buildSatorTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOverviewCard(
          title: 'Bonus Sator',
          subtitle:
              'Kelola bobot KPI, point range, dan reward tipe khusus per periode.',
          metrics: [
            _MetricData('KPI', '${_satorKpi.length}'),
            _MetricData('Point', '${_satorPointRanges.length}'),
            _MetricData('Reward', '${_satorRewards.length}'),
          ],
          trailing: _buildPeriodSelector(),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'KPI Settings',
          actionLabel: 'Atur Bulan',
          onAction: () => _showManageKpiDialog('sator'),
          children: _satorKpi.isEmpty
              ? [_buildEmptyTile('Belum ada KPI sator')]
              : _satorKpi
                    .map(
                      (k) => _buildConfigTile(
                        title: '${k['display_name'] ?? k['kpi_name'] ?? '-'}',
                        subtitle:
                            'Bobot ${k['weight'] ?? 0}% · ${k['description'] ?? '-'}',
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_rounded),
                          onPressed: () => _showEditKpiDialog(k),
                        ),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Template KPI',
          children: _satorKpiTemplates.isEmpty
              ? [_buildEmptyTile('Belum ada template KPI sator')]
              : _satorKpiTemplates
                    .map(
                      (k) => _buildConfigTile(
                        title: '${k['display_name'] ?? '-'}',
                        subtitle:
                            'Default ${k['default_weight'] ?? 0}% · ${k['metric_code'] ?? '-'}',
                        trailing: IconButton(
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: () => _showEditKpiTemplateDialog(k),
                        ),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Point Range',
          actionLabel: 'Tambah',
          onAction: () => _showAddPointRangeDialog('sator'),
          children: _satorPointRanges.isEmpty
              ? [_buildEmptyTile('Belum ada point range sator')]
              : _satorPointRanges
                    .map(
                      (row) => _buildConfigTile(
                        title:
                            '${(row['data_source'] ?? 'sell_out').toString().toUpperCase()} · Rp ${_formatPrice(row['min_price'])} - Rp ${_formatPrice(row['max_price'])}',
                        subtitle:
                            'Poin per unit ${row['points_per_unit'] ?? 0}',
                        trailing: _buildEditDeleteActions(
                          onEdit: () => _showEditPointRangeDialog('sator', row),
                          onDelete: () => _confirmDeleteItem(
                            title: 'Hapus Point Range',
                            message:
                                'Point range Sator ini akan dihapus dari pengaturan. Lanjutkan?',
                            onDelete: () => supabase
                                .from('point_ranges')
                                .delete()
                                .eq('id', row['id']),
                          ),
                        ),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Special Reward',
          actionLabel: 'Tambah',
          onAction: () => _showAddRewardDialog('sator'),
          children: _satorRewards.isEmpty
              ? [_buildEmptyTile('Belum ada reward tipe khusus sator')]
              : _satorRewards
                    .map(
                      (r) => _buildConfigTile(
                        title:
                            '${r['special_focus_bundles']?['bundle_name'] ?? 'Bundle tidak ditemukan'}',
                        subtitle:
                            'Target ikut target user · Reward Rp ${_formatPrice(r['reward_amount'])}',
                        trailing: _buildEditDeleteActions(
                          onEdit: () => _showEditRewardDialog(r),
                          onDelete: () => _confirmDeleteItem(
                            title: 'Hapus Special Reward',
                            message:
                                'Reward tipe khusus ini akan dihapus dari pengaturan. Lanjutkan?',
                            onDelete: () => supabase
                                .from('special_reward_configs')
                                .delete()
                                .eq('id', r['id']),
                          ),
                        ),
                      ),
                    )
                    .toList(),
        ),
      ],
    );
  }

  Widget _buildSpvTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOverviewCard(
          title: 'Bonus SPV',
          subtitle:
              'Kelola KPI, point range, dan reward SPV dalam periode yang sama.',
          metrics: [
            _MetricData('KPI', '${_spvKpi.length}'),
            _MetricData('Point', '${_spvPointRanges.length}'),
            _MetricData('Reward', '${_spvRewards.length}'),
          ],
          trailing: _buildPeriodSelector(),
        ),
        const SizedBox(height: 16),
        _buildSectionCard(
          title: 'KPI Settings',
          actionLabel: 'Atur Bulan',
          onAction: () => _showManageKpiDialog('spv'),
          children: _spvKpi.isEmpty
              ? [_buildEmptyTile('Belum ada KPI spv')]
              : _spvKpi
                    .map(
                      (k) => _buildConfigTile(
                        title: '${k['display_name'] ?? k['kpi_name'] ?? '-'}',
                        subtitle:
                            'Bobot ${k['weight'] ?? 0}% · ${k['description'] ?? '-'}',
                        trailing: IconButton(
                          icon: const Icon(Icons.edit_rounded),
                          onPressed: () => _showEditKpiDialog(k),
                        ),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Template KPI',
          children: _spvKpiTemplates.isEmpty
              ? [_buildEmptyTile('Belum ada template KPI spv')]
              : _spvKpiTemplates
                    .map(
                      (k) => _buildConfigTile(
                        title: '${k['display_name'] ?? '-'}',
                        subtitle:
                            'Default ${k['default_weight'] ?? 0}% · ${k['metric_code'] ?? '-'}',
                        trailing: IconButton(
                          icon: const Icon(Icons.tune_rounded),
                          onPressed: () => _showEditKpiTemplateDialog(k),
                        ),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Point Range',
          actionLabel: 'Tambah',
          onAction: () => _showAddPointRangeDialog('spv'),
          children: _spvPointRanges.isEmpty
              ? [_buildEmptyTile('Belum ada point range spv')]
              : _spvPointRanges
                    .map(
                      (row) => _buildConfigTile(
                        title:
                            '${(row['data_source'] ?? 'sell_out').toString().toUpperCase()} · Rp ${_formatPrice(row['min_price'])} - Rp ${_formatPrice(row['max_price'])}',
                        subtitle:
                            'Poin per unit ${row['points_per_unit'] ?? 0}',
                        trailing: _buildEditDeleteActions(
                          onEdit: () => _showEditPointRangeDialog('spv', row),
                          onDelete: () => _confirmDeleteItem(
                            title: 'Hapus Point Range',
                            message:
                                'Point range SPV ini akan dihapus dari pengaturan. Lanjutkan?',
                            onDelete: () => supabase
                                .from('point_ranges')
                                .delete()
                                .eq('id', row['id']),
                          ),
                        ),
                      ),
                    )
                    .toList(),
        ),
        const SizedBox(height: 12),
        _buildSectionCard(
          title: 'Special Reward',
          actionLabel: 'Tambah',
          onAction: () => _showAddRewardDialog('spv'),
          children: _spvRewards.isEmpty
              ? [_buildEmptyTile('Belum ada reward tipe khusus spv')]
              : _spvRewards
                    .map(
                      (r) => _buildConfigTile(
                        title:
                            '${r['special_focus_bundles']?['bundle_name'] ?? 'Bundle tidak ditemukan'}',
                        subtitle:
                            'Target ikut target user · Reward Rp ${_formatPrice(r['reward_amount'])}',
                        trailing: _buildEditDeleteActions(
                          onEdit: () => _showEditRewardDialog(r),
                          onDelete: () => _confirmDeleteItem(
                            title: 'Hapus Special Reward',
                            message:
                                'Reward tipe khusus ini akan dihapus dari pengaturan. Lanjutkan?',
                            onDelete: () => supabase
                                .from('special_reward_configs')
                                .delete()
                                .eq('id', r['id']),
                          ),
                        ),
                      ),
                    )
                    .toList(),
        ),
      ],
    );
  }

  Widget _buildPeriodSelector() {
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _selectedRewardPeriodId,
        borderRadius: BorderRadius.circular(12),
        items: _rewardPeriods
            .map(
              (period) => DropdownMenuItem(
                value: '${period['id']}',
                child: Text(_formatPeriodLabel(period)),
              ),
            )
            .toList(),
        onChanged: _onRewardPeriodChanged,
      ),
    );
  }

  Widget _buildOverviewCard({
    required String title,
    required String subtitle,
    required List<_MetricData> metrics,
    Widget? trailing,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: const TextStyle(color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                if (trailing case final Widget trailingWidget) trailingWidget,
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: metrics
                  .map(
                    (metric) => Container(
                      constraints: const BoxConstraints(minWidth: 88),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.value,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            metric.label,
                            style: const TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
    required List<Widget> children,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            ListTile(
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: actionLabel == null
                  ? null
                  : FilledButton.tonal(
                      onPressed: onAction,
                      child: Text(actionLabel),
                    ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildConfigTile({
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: trailing,
    );
  }

  Widget _buildEmptyTile(String text) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      leading: const Icon(Icons.inbox_outlined, color: AppColors.textSecondary),
      title: Text(text),
    );
  }
}

class _PointRangeEdit {
  _PointRangeEdit({
    required this.dataSource,
    required this.minC,
    required this.maxC,
    required this.pointsC,
  });

  String dataSource;
  final TextEditingController minC;
  final TextEditingController maxC;
  final TextEditingController pointsC;

  void dispose() {
    minC.dispose();
    maxC.dispose();
    pointsC.dispose();
  }
}

class _MetricData {
  const _MetricData(this.label, this.value);

  final String label;
  final String value;
}
