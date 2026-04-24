import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/theme/app_theme.dart';

class AdminAiSettingsPage extends StatefulWidget {
  const AdminAiSettingsPage({super.key});

  @override
  State<AdminAiSettingsPage> createState() => _AdminAiSettingsPageState();
}

class _AdminAiSettingsPageState extends State<AdminAiSettingsPage> {
  static const _featureKey = 'live_feed_sales_comment';
  static const _defaultSalesCommentPrompt = '''
Kamu adalah rekan tim penjualan yang benar-benar terasa seperti manusia, bukan mesin.
Tugasmu menulis komentar live feed yang hangat, santai, akrab, jelas maksudnya, dan bikin suasana tim terasa hidup.

Aturan:
- Prioritaskan sapaan "Kak" kalau konteksnya cocok. Boleh juga pakai gaya obrolan ringan yang akrab.
- Tulis seperti teman satu tim di chat, bukan announcer, bukan admin resmi, bukan customer service.
- Bahasa harus luwes, ringan, spontan, dan terasa keluar dari mulut orang lapangan.
- Ambil detail yang paling relevan dari konteks, lalu olah jadi komentar yang hangat, hidup, dan jelas.
- Kalau konteksnya cocok, boleh selipkan candaan ringan, godaan tipis, atau celetukan santai. Jangan maksa lucu.
- Komentar harus terasa personal, bukan template yang bisa ditempel ke semua postingan.
- Variasikan ritme kalimat. Jangan selalu rapi, jangan terlalu textbook.
- Hindari frasa kaku seperti "berdasarkan data", "informasi menunjukkan", "selamat atas pencapaian tersebut", "izin memberi apresiasi", atau kalimat lain yang terdengar korporat.
- Hindari frasa abstrak atau menggantung seperti "jaga ritme", "next deal", "semangat tim", atau kalimat yang tidak jelas maksudnya.
- Jangan menggurui, jangan terlalu formal, jangan terlalu aman, dan jangan terlalu heboh.
- Jangan pernah menyebut diri sebagai AI, bot, sistem, atau model.
- Maksimal 1 kalimat utama atau 2 kalimat pendek.
- Emoji tidak wajib. Kalau dipakai, cukup satu dan harus terasa natural.
- Jangan menyebut data yang tidak ada di konteks.
- Jangan terdengar seperti caption promo.

Patokan rasa bahasa:
- Lebih mirip "Wah Kak, pecah juga ini jualannya" daripada "Selamat atas pencapaian penjualan hari ini".
- Lebih mirip "Kak ini lagi panas banget ritmenya" daripada "Penjualan Anda menunjukkan performa baik".

Keluarkan hanya isi komentar akhirnya.
''';

  final _supabase = Supabase.instance.client;
  final _modelController = TextEditingController();
  final _delayController = TextEditingController();
  final _promptController = TextEditingController();
  final _personaDisplayNameController = TextEditingController();
  final _personaCodeController = TextEditingController();
  final _personaTitleController = TextEditingController();
  final _personaIdentityController = TextEditingController();
  final _personaBackgroundController = TextEditingController();
  final _personaRelationshipController = TextEditingController();
  final _personaSpeakingStyleController = TextEditingController();
  final _personaToneExamplesController = TextEditingController();
  final _personaDontSayController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSavingPersona = false;
  bool _businessReviewEnabled = true;
  bool _motivatorEnabled = true;
  bool _salesCommentEnabled = false;
  bool _replyThreadsEnabled = true;
  bool _personaActive = true;

  String? _selectedPersonaId;
  String? _selectedLinkedUserId;

  List<Map<String, dynamic>> _users = const [];
  List<Map<String, dynamic>> _personas = const [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _modelController.dispose();
    _delayController.dispose();
    _promptController.dispose();
    _personaDisplayNameController.dispose();
    _personaCodeController.dispose();
    _personaTitleController.dispose();
    _personaIdentityController.dispose();
    _personaBackgroundController.dispose();
    _personaRelationshipController.dispose();
    _personaSpeakingStyleController.dispose();
    _personaToneExamplesController.dispose();
    _personaDontSayController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    try {
      final usersFuture = _supabase
          .from('users')
          .select('id, full_name, role')
          .isFilter('deleted_at', null)
          .order('full_name');
      final personasFuture = _supabase
          .from('system_personas')
          .select(
            'id, persona_code, display_name, linked_user_id, is_active, feature_key, metadata_json',
          )
          .order('display_name');
      final settingsFuture = _supabase
          .from('ai_feature_settings')
          .select('enabled, model_name, system_prompt, config_json')
          .eq('feature_key', _featureKey)
          .maybeSingle();

      final results = await Future.wait([
        usersFuture,
        personasFuture,
        settingsFuture,
      ]);

      final users = List<Map<String, dynamic>>.from(results[0] as List);
      final personas = List<Map<String, dynamic>>.from(results[1] as List);
      final row = results[2] as Map<String, dynamic>?;
      final config = row == null
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(
              row['config_json'] as Map? ?? const <String, dynamic>{},
            );
      final selectedPersonaId =
          '${config['system_persona_id'] ?? ''}'.trim().isEmpty
          ? null
          : '${config['system_persona_id']}';
      final savedPrompt = '${row?['system_prompt'] ?? ''}'.trim();

      if (!mounted) return;
      setState(() {
        _users = users;
        _personas = personas;
        _salesCommentEnabled = row?['enabled'] == true;
        _replyThreadsEnabled = config['enable_reply_threads'] != false;
        _modelController.text = '${row?['model_name'] ?? 'gemini-2.5-flash'}';
        _delayController.text = '${config['delay_seconds'] ?? 25}';
        _promptController.text = savedPrompt.isEmpty
            ? _defaultSalesCommentPrompt
            : savedPrompt;
        _selectedPersonaId = selectedPersonaId;
        _syncPersonaForm(selectedPersonaId);
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal memuat AI settings. $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    }
  }

  void _syncPersonaForm(String? personaId) {
    final persona = _personas.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['id'] == personaId,
      orElse: () => null,
    );
    if (persona == null) {
      _personaDisplayNameController.clear();
      _personaCodeController.clear();
      _personaTitleController.clear();
      _personaIdentityController.clear();
      _personaBackgroundController.clear();
      _personaRelationshipController.clear();
      _personaSpeakingStyleController.clear();
      _personaToneExamplesController.clear();
      _personaDontSayController.clear();
      _selectedLinkedUserId = null;
      _personaActive = true;
      return;
    }
    final metadata = Map<String, dynamic>.from(
      persona['metadata_json'] as Map? ?? const <String, dynamic>{},
    );
    _personaDisplayNameController.text = '${persona['display_name'] ?? ''}';
    _personaCodeController.text = '${persona['persona_code'] ?? ''}';
    _personaTitleController.text = '${metadata['persona_title'] ?? ''}';
    _personaIdentityController.text = '${metadata['identity_summary'] ?? ''}';
    _personaBackgroundController.text = '${metadata['background_story'] ?? ''}';
    _personaRelationshipController.text =
        '${metadata['relationship_to_team'] ?? ''}';
    _personaSpeakingStyleController.text =
        '${metadata['speaking_style'] ?? ''}';
    _personaToneExamplesController.text = '${metadata['tone_examples'] ?? ''}';
    _personaDontSayController.text = '${metadata['dont_say'] ?? ''}';
    _selectedLinkedUserId = '${persona['linked_user_id'] ?? ''}'.trim().isEmpty
        ? null
        : '${persona['linked_user_id']}';
    _personaActive = persona['is_active'] != false;
  }

  Future<void> _savePersona() async {
    final displayName = _personaDisplayNameController.text.trim();
    final personaCode = _personaCodeController.text.trim();
    final linkedUserId = _selectedLinkedUserId;

    if (displayName.isEmpty || personaCode.isEmpty || linkedUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nama persona, kode persona, dan linked user wajib diisi.',
          ),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    setState(() => _isSavingPersona = true);
    try {
      final payload = <String, dynamic>{
        'persona_code': personaCode,
        'display_name': displayName,
        'linked_user_id': linkedUserId,
        'feature_key': _featureKey,
        'is_active': _personaActive,
        'metadata_json': {
          'persona_title': _personaTitleController.text.trim(),
          'identity_summary': _personaIdentityController.text.trim(),
          'background_story': _personaBackgroundController.text.trim(),
          'relationship_to_team': _personaRelationshipController.text.trim(),
          'speaking_style': _personaSpeakingStyleController.text.trim(),
          'tone_examples': _personaToneExamplesController.text.trim(),
          'dont_say': _personaDontSayController.text.trim(),
        },
      };
      if (_selectedPersonaId != null && _selectedPersonaId!.isNotEmpty) {
        payload['id'] = _selectedPersonaId;
      }

      final saved = await _supabase
          .from('system_personas')
          .upsert(payload)
          .select(
            'id, persona_code, display_name, linked_user_id, is_active, feature_key, metadata_json',
          )
          .single();

      if (!mounted) return;
      final savedMap = Map<String, dynamic>.from(saved);
      setState(() {
        final next = [..._personas];
        final index = next.indexWhere((row) => row['id'] == savedMap['id']);
        if (index >= 0) {
          next[index] = savedMap;
        } else {
          next.add(savedMap);
          next.sort((a, b) {
            return '${a['display_name'] ?? ''}'.compareTo(
              '${b['display_name'] ?? ''}',
            );
          });
        }
        _personas = next;
        _selectedPersonaId = '${savedMap['id']}';
        _syncPersonaForm(_selectedPersonaId);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('System persona berhasil disimpan.'),
          backgroundColor: AppTheme.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan system persona. $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSavingPersona = false);
    }
  }

  Future<void> _saveSalesCommentSettings() async {
    final delaySeconds = int.tryParse(_delayController.text.trim()) ?? 25;
    final modelName = _modelController.text.trim().isEmpty
        ? 'gemini-2.5-flash'
        : _modelController.text.trim();
    final systemPrompt = _promptController.text.trim();

    if (systemPrompt.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('System prompt wajib diisi.'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
      return;
    }

    final selectedPersona = _personas.cast<Map<String, dynamic>?>().firstWhere(
      (row) => row?['id'] == _selectedPersonaId,
      orElse: () => null,
    );
    final personaUserId = selectedPersona == null
        ? null
        : '${selectedPersona['linked_user_id'] ?? ''}'.trim().isEmpty
        ? null
        : '${selectedPersona['linked_user_id']}';

    setState(() => _isSaving = true);
    try {
      final payload = <String, dynamic>{
        'feature_key': _featureKey,
        'enabled': _salesCommentEnabled,
        'model_name': modelName,
        'system_prompt': systemPrompt,
        'config_json': {
          'delay_seconds': delaySeconds < 0 ? 0 : delaySeconds,
          'system_persona_id': _selectedPersonaId,
          'persona_user_id': personaUserId,
          'enable_reply_threads': _replyThreadsEnabled,
          'language': 'id',
          'max_output_chars': 160,
          'temperature': 0.9,
        },
        'updated_by': _supabase.auth.currentUser?.id,
      };
      await _supabase.from('ai_feature_settings').upsert(payload);

      if (!_salesCommentEnabled) {
        final nowIso = DateTime.now().toIso8601String();
        await _supabase
            .from('ai_sales_comment_jobs')
            .update({
              'status': 'skipped',
              'last_error': 'AI Sales Comment dimatikan dari admin.',
              'processed_at': nowIso,
            })
            .inFilter('status', ['pending', 'processing']);

        await _supabase
            .from('ai_feed_comment_reply_jobs')
            .update({
              'status': 'skipped',
              'last_error': 'AI Sales Comment dimatikan dari admin.',
              'processed_at': nowIso,
            })
            .inFilter('status', ['pending', 'processing']);
      } else if (!_replyThreadsEnabled) {
        final nowIso = DateTime.now().toIso8601String();
        await _supabase
            .from('ai_feed_comment_reply_jobs')
            .update({
              'status': 'skipped',
              'last_error': 'Balasan thread persona dimatikan dari admin.',
              'processed_at': nowIso,
            })
            .inFilter('status', ['pending', 'processing']);
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('AI Sales Comment berhasil disimpan.'),
          backgroundColor: AppTheme.successGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal menyimpan AI Sales Comment. $e'),
          backgroundColor: AppTheme.errorRed,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _userLabel(Map<String, dynamic> row) {
    final name = '${row['full_name'] ?? 'User'}'.trim();
    final role = '${row['role'] ?? '-'}'.trim();
    return '$name • $role';
  }

  String _personaLabel(Map<String, dynamic> row) {
    final displayName = '${row['display_name'] ?? 'Persona'}'.trim();
    final code = '${row['persona_code'] ?? '-'}'.trim();
    return '$displayName • $code';
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 800;

    return Scaffold(
      backgroundColor: AppTheme.backgroundLight,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(isDesktop ? 24 : 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isDesktop)
                    Text(
                      'AI Settings',
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  if (isDesktop) const SizedBox(height: 8),
                  if (isDesktop)
                    Text(
                      'Kontrol semua AI features',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 24),
                  _buildStaticCard(
                    title: 'AI Business Review',
                    description: 'Review mingguan otomatis untuk SATOR',
                    isEnabled: _businessReviewEnabled,
                    onToggle: (v) => setState(() => _businessReviewEnabled = v),
                    settings: const ['Belum disambungkan ke database'],
                  ),
                  const SizedBox(height: 16),
                  _buildStaticCard(
                    title: 'AI Motivator',
                    description: 'Motivasi otomatis di leaderboard feed',
                    isEnabled: _motivatorEnabled,
                    onToggle: (v) => setState(() => _motivatorEnabled = v),
                    settings: const ['Belum disambungkan ke database'],
                  ),
                  const SizedBox(height: 16),
                  _buildSystemPersonaCard(),
                  const SizedBox(height: 16),
                  _buildSalesCommentCard(),
                ],
              ),
            ),
    );
  }

  Widget _buildStaticCard({
    required String title,
    required String description,
    required bool isEnabled,
    required ValueChanged<bool> onToggle,
    required List<String> settings,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      Text(
                        description,
                        style: const TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: isEnabled,
                  activeThumbColor: AppTheme.successGreen,
                  onChanged: onToggle,
                ),
              ],
            ),
            if (isEnabled) ...[
              const Divider(height: 24),
              ...settings.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        size: 16,
                        color: AppTheme.accentBlue,
                      ),
                      const SizedBox(width: 8),
                      Text(s),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSystemPersonaCard() {
    final uniquePersonasById = <String, Map<String, dynamic>>{};
    for (final row in _personas) {
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      uniquePersonasById[id] = row;
    }
    final personaRows = uniquePersonasById.values.toList();
    final selectedPersonaIdForForm = _selectedPersonaId != null &&
            uniquePersonasById.containsKey(_selectedPersonaId)
        ? _selectedPersonaId
        : null;

    final uniqueUsersById = <String, Map<String, dynamic>>{};
    for (final row in _users) {
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      uniqueUsersById[id] = row;
    }
    final userRows = uniqueUsersById.values.toList();
    final selectedLinkedUserIdForForm = _selectedLinkedUserId != null &&
            uniqueUsersById.containsKey(_selectedLinkedUserId)
        ? _selectedLinkedUserId
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'System Persona',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            const Text(
              'Persona khusus non-operasional untuk komentar otomatis live feed.',
              style: TextStyle(color: AppTheme.textSecondary),
            ),
            const Divider(height: 24),
            DropdownButtonFormField<String>(
              initialValue: selectedPersonaIdForForm,
              decoration: const InputDecoration(
                labelText: 'Persona Tersimpan',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Persona baru'),
                ),
                ...personaRows.map((row) {
                  final id = '${row['id'] ?? ''}';
                  return DropdownMenuItem<String>(
                    value: id,
                    child: Text(_personaLabel(row)),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedPersonaId = value;
                  _syncPersonaForm(value);
                });
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _personaDisplayNameController,
                    decoration: const InputDecoration(
                      labelText: 'Nama Persona',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _personaCodeController,
                    decoration: const InputDecoration(
                      labelText: 'Kode Persona',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: selectedLinkedUserIdForForm,
              decoration: const InputDecoration(
                labelText: 'Linked User',
                border: OutlineInputBorder(),
                helperText:
                    'Persona tetap memakai 1 akun user internal untuk menulis ke feed_comments.',
              ),
              items: userRows.map((row) {
                final id = '${row['id'] ?? ''}';
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(_userLabel(row)),
                );
              }).toList(),
              onChanged: (value) =>
                  setState(() => _selectedLinkedUserId = value),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              value: _personaActive,
              contentPadding: EdgeInsets.zero,
              title: const Text('Persona aktif'),
              onChanged: (value) => setState(() => _personaActive = value),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _personaTitleController,
              decoration: const InputDecoration(
                labelText: 'Peran Persona',
                border: OutlineInputBorder(),
                helperText:
                    'Contoh: mentor lapangan, kakak tim pusat, coach area, teman diskusi promotor.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _personaIdentityController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Identitas Singkat',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                helperText:
                    'Isi siapa persona ini sebagai manusia: nama panggilan, posisi, pembawaan, dan cara dia dikenal tim.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _personaBackgroundController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Latar Belakang',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                helperText:
                    'Cerita singkat latar belakang persona agar terasa hidup dan konsisten saat diajak ngobrol.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _personaRelationshipController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Relasi Dengan Tim',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                helperText:
                    'Jelaskan bagaimana persona memandang promotor, sator, dan tim. Misal seperti kakak, teman satu tim, mentor santai.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _personaSpeakingStyleController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Gaya Bicara',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                helperText:
                    'Tulis gaya bahasa yang diinginkan: santai, hangat, spontan, tidak formal, suka menyapa nama panggilan, dll.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _personaToneExamplesController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Contoh Nada / Frasa',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                helperText:
                    'Contoh cara ngomong yang natural untuk persona ini. Bukan hardcoded output, tapi referensi tone.',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _personaDontSayController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Yang Harus Dihindari',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                helperText:
                    'Contoh: jangan terlalu formal, jangan seperti announcer, jangan menggurui, jangan terlalu heboh.',
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isSavingPersona ? null : _savePersona,
                icon: _isSavingPersona
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  _isSavingPersona ? 'Menyimpan...' : 'Simpan Persona',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSalesCommentCard() {
    final activeUniquePersonasById = <String, Map<String, dynamic>>{};
    for (final row in _personas) {
      if (row['is_active'] == false) continue;
      final id = '${row['id'] ?? ''}'.trim();
      if (id.isEmpty) continue;
      activeUniquePersonasById[id] = row;
    }
    final activePersonaRows = activeUniquePersonasById.values.toList();
    final selectedPersonaIdForSales = _selectedPersonaId != null &&
            activeUniquePersonasById.containsKey(_selectedPersonaId)
        ? _selectedPersonaId
        : null;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI Sales Comment',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Text(
                        'Komentar otomatis untuk setiap penjualan di live feed',
                        style: TextStyle(color: AppTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _salesCommentEnabled,
                  activeThumbColor: AppTheme.successGreen,
                  onChanged: (v) => setState(() => _salesCommentEnabled = v),
                ),
              ],
            ),
            const Divider(height: 24),
            DropdownButtonFormField<String>(
              initialValue: selectedPersonaIdForSales,
              decoration: const InputDecoration(
                labelText: 'System Persona',
                border: OutlineInputBorder(),
                helperText:
                    'Pilih persona khusus yang akan tampil sebagai pemberi komentar.',
              ),
              items: activePersonaRows.map((row) {
                final id = '${row['id'] ?? ''}';
                return DropdownMenuItem<String>(
                  value: id,
                  child: Text(_personaLabel(row)),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedPersonaId = value),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _modelController,
                    decoration: const InputDecoration(
                      labelText: 'Model',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _delayController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Delay (detik)',
                      border: OutlineInputBorder(),
                      helperText:
                          'Dipakai sebagai jeda dasar komentar dan balasan. Worker akan menambah variasi acak kecil supaya tidak terlalu instan.',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              value: _replyThreadsEnabled,
              contentPadding: EdgeInsets.zero,
              activeThumbColor: AppTheme.successGreen,
              title: const Text('Aktifkan balasan thread live feed'),
              subtitle: const Text(
                'Kalau aktif, persona bisa membalas komentar user saat di-mention atau saat user membalas persona.',
                style: TextStyle(color: AppTheme.textSecondary),
              ),
              onChanged: (value) =>
                  setState(() => _replyThreadsEnabled = value),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _promptController,
              minLines: 10,
              maxLines: 18,
              decoration: const InputDecoration(
                labelText: 'System Prompt',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                helperText:
                    'Prompt dasar ini dipakai untuk komentar live feed. Mode balasan thread memakai tone persona yang sama dengan aturan reply tambahan dari worker.',
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.backgroundLight,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _replyThreadsEnabled
                    ? 'Mode komentar utama dan balasan thread aktif. Persona akan tetap menjaga gaya bicara yang sama di live feed.'
                    : 'Saat ini persona hanya kirim komentar utama. Balasan thread dimatikan sampai toggle di atas diaktifkan lagi.',
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _isSaving ? null : _saveSalesCommentSettings,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _isSaving ? 'Menyimpan...' : 'Simpan AI Sales Comment',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
