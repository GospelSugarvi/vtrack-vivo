import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:vtrack/ui/foundation/field_theme_extensions.dart';

class NotificationPreferencesPage extends StatefulWidget {
  const NotificationPreferencesPage({super.key});

  @override
  State<NotificationPreferencesPage> createState() =>
      _NotificationPreferencesPageState();
}

class _NotificationPreferencesPageState
    extends State<NotificationPreferencesPage> {
  FieldThemeTokens get t => context.fieldTokens;
  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  bool _isSaving = false;

  bool _approvalEnabled = true;
  bool _stockEnabled = true;
  bool _salesEnabled = true;
  bool _scheduleEnabled = true;
  bool _systemEnabled = true;
  bool _pushEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Sesi login tidak ditemukan');
      }

      final rows = await _supabase
          .from('notification_preferences')
          .select(
            'approval_enabled, stock_enabled, sales_enabled, schedule_enabled, system_enabled, push_enabled',
          )
          .eq('user_id', userId)
          .limit(1);

      Map<String, dynamic> row;
      if (rows.isEmpty) {
        row = await _upsertPreferences(const {});
      } else {
        row = Map<String, dynamic>.from(rows.first);
      }

      if (!mounted) return;
      setState(() {
        _approvalEnabled = row['approval_enabled'] != false;
        _stockEnabled = row['stock_enabled'] != false;
        _salesEnabled = row['sales_enabled'] != false;
        _scheduleEnabled = row['schedule_enabled'] != false;
        _systemEnabled = row['system_enabled'] != false;
        _pushEnabled = row['push_enabled'] != false;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>> _upsertPreferences(
    Map<String, dynamic> values,
  ) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('Sesi login tidak ditemukan');

    final payload = <String, dynamic>{
      'user_id': userId,
      'approval_enabled': values['approval_enabled'] ?? _approvalEnabled,
      'stock_enabled': values['stock_enabled'] ?? _stockEnabled,
      'sales_enabled': values['sales_enabled'] ?? _salesEnabled,
      'schedule_enabled': values['schedule_enabled'] ?? _scheduleEnabled,
      'system_enabled': values['system_enabled'] ?? _systemEnabled,
      'push_enabled': values['push_enabled'] ?? _pushEnabled,
      'inbox_enabled': true,
    };

    final rows = await _supabase
        .from('notification_preferences')
        .upsert(payload)
        .select(
          'approval_enabled, stock_enabled, sales_enabled, schedule_enabled, system_enabled, push_enabled',
        )
        .limit(1);

    return Map<String, dynamic>.from(rows.first);
  }

  Future<void> _saveToggle(String column, bool value) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      final row = await _upsertPreferences({column: value});
      if (!mounted) return;
      setState(() {
        _approvalEnabled = row['approval_enabled'] != false;
        _stockEnabled = row['stock_enabled'] != false;
        _salesEnabled = row['sales_enabled'] != false;
        _scheduleEnabled = row['schedule_enabled'] != false;
        _systemEnabled = row['system_enabled'] != false;
        _pushEnabled = row['push_enabled'] != false;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Gagal simpan pengaturan: $e'),
          backgroundColor: t.danger,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: t.textOnAccent,
      appBar: AppBar(title: const Text('Pengaturan Notifikasi')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _sectionCard(
                  title: 'Kanal',
                  subtitle:
                      'Inbox aplikasi selalu aktif sebagai sumber utama. Push dipakai saat pengiriman ke device sudah diaktifkan.',
                  children: [
                    _toggleTile(
                      title: 'Push ke Perangkat',
                      subtitle:
                          'Siapkan izin push saat integrasi FCM diaktifkan.',
                      value: _pushEnabled,
                      onChanged: (value) => _saveToggle('push_enabled', value),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _sectionCard(
                  title: 'Kategori',
                  subtitle:
                      'Kategori yang dimatikan tidak akan dibuatkan notifikasi baru di inbox.',
                  children: [
                    _toggleTile(
                      title: 'Approval',
                      subtitle: 'Pengajuan, review, approve, reject.',
                      value: _approvalEnabled,
                      onChanged: (value) =>
                          _saveToggle('approval_enabled', value),
                    ),
                    _toggleTile(
                      title: 'Stok',
                      subtitle: 'Chip, stok toko, dan pergerakan stok.',
                      value: _stockEnabled,
                      onChanged: (value) => _saveToggle('stock_enabled', value),
                    ),
                    _toggleTile(
                      title: 'Penjualan',
                      subtitle: 'Void, koreksi transaksi, dan hasil review.',
                      value: _salesEnabled,
                      onChanged: (value) => _saveToggle('sales_enabled', value),
                    ),
                    _toggleTile(
                      title: 'Jadwal',
                      subtitle: 'Perubahan jadwal dan approval terkait.',
                      value: _scheduleEnabled,
                      onChanged: (value) =>
                          _saveToggle('schedule_enabled', value),
                    ),
                    _toggleTile(
                      title: 'Sistem',
                      subtitle:
                          'Informasi umum aplikasi dan pengumuman sistem.',
                      value: _systemEnabled,
                      onChanged: (value) =>
                          _saveToggle('system_enabled', value),
                    ),
                  ],
                ),
              ],
            ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: t.surface1,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: t.surface3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: t.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: t.textMutedStrong,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _toggleTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: t.textOnAccent,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.surface3),
      ),
      child: SwitchListTile.adaptive(
        value: value,
        onChanged: _isSaving ? null : onChanged,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: t.textPrimary,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: t.textMutedStrong,
          ),
        ),
      ),
    );
  }
}
