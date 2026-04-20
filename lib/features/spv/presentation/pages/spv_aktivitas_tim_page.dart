import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

import '../../../sator/presentation/pages/aktivitas_tim_page.dart';
import '../../../../ui/promotor/promotor.dart';

class SpvAktivitasTimPage extends StatefulWidget {
  const SpvAktivitasTimPage({super.key});

  @override
  State<SpvAktivitasTimPage> createState() => _SpvAktivitasTimPageState();
}

class _SpvAktivitasTimPageState extends State<SpvAktivitasTimPage> {
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _sators = const [];

  @override
  void initState() {
    super.initState();
    _loadSators();
  }

  Future<void> _loadSators() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final raw = await _supabase.rpc('get_spv_sator_tabs');
      final rows = raw is List
          ? raw
                .whereType<Map>()
                .map((item) => Map<String, dynamic>.from(item))
                .toList()
          : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        _sators = rows;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage =
            'Daftar SATOR tidak bisa dimuat. Tarik ke bawah atau coba lagi beberapa saat lagi.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.fieldTokens;

    return DefaultTabController(
      length: _sators.isEmpty ? 1 : _sators.length,
      child: Scaffold(
        backgroundColor: t.textOnAccent,
        appBar: AppBar(title: const Text('Aktivitas Tim')),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null
            ? RefreshIndicator(
                onRefresh: _loadSators,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w700,
                          color: t.textMutedStrong,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : _sators.isEmpty
            ? RefreshIndicator(
                onRefresh: _loadSators,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(16),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: t.surface1,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: t.surface3),
                      ),
                      child: Text(
                        'Belum ada SATOR aktif di bawah SPV ini.',
                        style: PromotorText.outfit(
                          size: 11,
                          weight: FontWeight.w700,
                          color: t.textMutedStrong,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  Container(
                    color: t.textOnAccent,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelColor: t.textOnAccent,
                      unselectedLabelColor: t.textSecondary,
                      labelStyle: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w800,
                        color: t.textOnAccent,
                      ),
                      unselectedLabelStyle: PromotorText.outfit(
                        size: 10,
                        weight: FontWeight.w800,
                        color: t.textSecondary,
                      ),
                      indicator: BoxDecoration(
                        color: t.primaryAccent,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      dividerColor: Colors.transparent,
                      indicatorSize: TabBarIndicatorSize.tab,
                      tabs: _sators
                          .map(
                            (sator) => Tab(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                ),
                                child: Text('${sator['name'] ?? 'SATOR'}'),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                  Expanded(
                    child: TabBarView(
                      children: _sators
                          .map(
                            (sator) => AktivitasTimPage(
                              scopeSatorId: '${sator['sator_id'] ?? ''}',
                              embedded: true,
                              showBackButton: false,
                              title: '${sator['name'] ?? 'Aktivitas Tim'}',
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
