import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../main.dart';

class AdminWeeklyTargetPage extends StatefulWidget {
  const AdminWeeklyTargetPage({super.key});

  @override
  State<AdminWeeklyTargetPage> createState() => _AdminWeeklyTargetPageState();
}

class _AdminWeeklyTargetPageState extends State<AdminWeeklyTargetPage> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _periods = <Map<String, dynamic>>[];
  List<Map<String, dynamic>> _weeklyTargets = <Map<String, dynamic>>[];
  String? _selectedPeriodId;
  Map<String, dynamic>? _selectedPeriodData;
  final Map<int, TextEditingController> _startDayCtrls = {};
  final Map<int, TextEditingController> _endDayCtrls = {};
  final Map<int, TextEditingController> _percentageCtrls = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      final periods = await supabase
          .from('target_periods')
          .select('id, start_date, end_date, target_month, target_year')
          .isFilter('deleted_at', null)
          .order('start_date', ascending: false);
      _periods = List<Map<String, dynamic>>.from(periods);
      _selectedPeriodId ??= _periods.isEmpty ? null : '${_periods.first['id']}';
      _selectedPeriodData = _periods.firstWhere(
        (period) => '${period['id']}' == _selectedPeriodId,
        orElse: () => <String, dynamic>{},
      );
      if (_selectedPeriodId != null) {
        final rows = await supabase
            .from('weekly_targets')
            .select('*')
            .eq('period_id', _selectedPeriodId!)
            .order('week_number');
        _weeklyTargets = List<Map<String, dynamic>>.from(rows);
      }
      if (_weeklyTargets.isEmpty && _selectedPeriodData != null) {
        _weeklyTargets = _buildDefaultWeeklyTargets(_selectedPeriodData!);
      }
      _syncControllers();
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    for (final ctrl in _startDayCtrls.values) {
      ctrl.dispose();
    }
    for (final ctrl in _endDayCtrls.values) {
      ctrl.dispose();
    }
    for (final ctrl in _percentageCtrls.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  List<Map<String, dynamic>> _buildDefaultWeeklyTargets(
    Map<String, dynamic> period,
  ) {
    final start = DateTime.tryParse('${period['start_date']}');
    final end = DateTime.tryParse('${period['end_date']}');
    final endDay = end?.day ?? 30;
    final defaultRows = <Map<String, dynamic>>[
      {'week_number': 1, 'start_day': 1, 'end_day': 7, 'percentage': 25},
      {'week_number': 2, 'start_day': 8, 'end_day': 14, 'percentage': 25},
      {'week_number': 3, 'start_day': 15, 'end_day': 22, 'percentage': 25},
      {'week_number': 4, 'start_day': 23, 'end_day': endDay, 'percentage': 25},
    ];
    if (start == null || end == null) {
      return defaultRows;
    }
    return defaultRows;
  }

  void _syncControllers() {
    for (final ctrl in _startDayCtrls.values) {
      ctrl.dispose();
    }
    for (final ctrl in _endDayCtrls.values) {
      ctrl.dispose();
    }
    for (final ctrl in _percentageCtrls.values) {
      ctrl.dispose();
    }
    _startDayCtrls.clear();
    _endDayCtrls.clear();
    _percentageCtrls.clear();

    for (final row in _weeklyTargets) {
      final weekNumber = (row['week_number'] as num?)?.toInt() ?? 0;
      if (weekNumber <= 0) continue;
      _startDayCtrls[weekNumber] = TextEditingController(
        text: '${row['start_day'] ?? ''}',
      );
      _endDayCtrls[weekNumber] = TextEditingController(
        text: '${row['end_day'] ?? ''}',
      );
      _percentageCtrls[weekNumber] = TextEditingController(
        text: '${row['percentage'] ?? ''}',
      );
    }
  }

  int _parseInt(String text) => int.tryParse(text.replaceAll(RegExp(r'[^\d]'), '')) ?? 0;

  Future<void> _saveWeeklyTargets() async {
    if (_selectedPeriodId == null) return;
    final rows = <Map<String, dynamic>>[];
    for (final week in [1, 2, 3, 4]) {
      final startDay = _parseInt(_startDayCtrls[week]?.text ?? '');
      final endDay = _parseInt(_endDayCtrls[week]?.text ?? '');
      final percentage = _parseInt(_percentageCtrls[week]?.text ?? '');
      rows.add({
        'period_id': _selectedPeriodId,
        'week_number': week,
        'start_day': startDay,
        'end_day': endDay,
        'percentage': percentage,
      });
    }

    if (mounted) {
      setState(() => _isLoading = true);
    }
    try {
      await supabase
          .from('weekly_targets')
          .delete()
          .eq('period_id', _selectedPeriodId!);
      await supabase.from('weekly_targets').insert(rows);
      await _loadData();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Weekly target berhasil disimpan')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e'), backgroundColor: AppTheme.errorRed),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      appBar: AppBar(
        title: const Text('Weekly Target'),
        actions: [
          IconButton(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedPeriodId,
                  decoration: const InputDecoration(
                    labelText: 'Periode',
                    border: OutlineInputBorder(),
                  ),
                  items: _periods
                      .map(
                        (period) => DropdownMenuItem<String>(
                          value: '${period['id']}',
                          child: Text(
                            '${period['start_date'] ?? '-'}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    setState(() => _selectedPeriodId = value);
                    await _loadData();
                  },
                ),
                const SizedBox(height: 16),
                Card(
                  child: ListTile(
                    title: const Text('Total Minggu Tersimpan'),
                    subtitle: Text('${_weeklyTargets.length} minggu'),
                    trailing: ElevatedButton.icon(
                      onPressed: _weeklyTargets.isEmpty ? null : _saveWeeklyTargets,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Simpan'),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                if (_weeklyTargets.isEmpty)
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'Belum ada weekly target untuk periode ini.',
                      ),
                    ),
                  )
                else
                  ...[1, 2, 3, 4].map(
                    (week) => Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Minggu $week',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _startDayCtrls[week],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Start Day',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _endDayCtrls[week],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'End Day',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: TextField(
                                    controller: _percentageCtrls[week],
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: '%',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
