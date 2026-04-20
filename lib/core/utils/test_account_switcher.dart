import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class TestAccountSwitcher {
  static const String _lastLoginKey = 'dev_last_login_v1';

  static Future<void> show(BuildContext context) async {
    if (!kDebugMode) return;
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _TestAccountSwitcherSheet(),
    );
  }

  static Future<Map<String, String>?> getLastLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_lastLoginKey);
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        final email = (decoded['email'] ?? '').toString();
        final password = (decoded['password'] ?? '').toString();
        if (email.isNotEmpty && password.isNotEmpty) {
          return {'email': email, 'password': password};
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> saveLastLogin({
    required String email,
    required String password,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _lastLoginKey,
      jsonEncode({'email': email, 'password': password}),
    );
  }

  static Future<void> clearLastLogin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastLoginKey);
  }
}

class TestAccountSwitcherFab extends StatelessWidget {
  const TestAccountSwitcherFab({super.key});

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    return Positioned(
      right: 12,
      bottom: 86,
      child: FloatingActionButton.small(
        heroTag: 'quick_switch_fab',
        onPressed: () => TestAccountSwitcher.show(context),
        tooltip: 'Switch Account',
        child: const Icon(Icons.switch_account),
      ),
    );
  }
}

class _TestAccountSwitcherSheet extends StatefulWidget {
  const _TestAccountSwitcherSheet();

  @override
  State<_TestAccountSwitcherSheet> createState() =>
      _TestAccountSwitcherSheetState();
}

class _TestAccountSwitcherSheetState extends State<_TestAccountSwitcherSheet> {
  static const String _storageKey = 'test_switcher_accounts_v1';

  final _supabase = Supabase.instance.client;

  bool _isLoading = true;
  String? _busySlotId;
  Map<String, Map<String, String>> _saved = {};

  static const List<_TestSlot> _slots = [
    _TestSlot(id: 'sator_1', label: 'SATOR 1', expectedRole: 'sator'),
    _TestSlot(id: 'sator_2', label: 'SATOR 2', expectedRole: 'sator'),
    _TestSlot(
      id: 'promotor_1',
      label: 'PROMOTOR 1 (SATOR 1)',
      expectedRole: 'promotor',
    ),
    _TestSlot(
      id: 'promotor_2',
      label: 'PROMOTOR 2 (SATOR 1)',
      expectedRole: 'promotor',
    ),
    _TestSlot(
      id: 'promotor_3',
      label: 'PROMOTOR 3 (SATOR 2)',
      expectedRole: 'promotor',
    ),
    _TestSlot(
      id: 'promotor_4',
      label: 'PROMOTOR 4 (SATOR 2)',
      expectedRole: 'promotor',
    ),
    _TestSlot(id: 'spv_1', label: 'SPV 1', expectedRole: 'spv'),
  ];

  @override
  void initState() {
    super.initState();
    _loadSaved();
  }

  Future<void> _loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);

    final map = <String, Map<String, String>>{};
    if (raw != null && raw.isNotEmpty) {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        for (final entry in decoded.entries) {
          final val = entry.value;
          if (val is Map<String, dynamic>) {
            final email = (val['email'] ?? '').toString();
            final password = (val['password'] ?? '').toString();
            if (email.isNotEmpty && password.isNotEmpty) {
              map[entry.key] = {'email': email, 'password': password};
            }
          }
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _saved = map;
      _isLoading = false;
    });
  }

  Future<void> _persistSaved() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(_saved));
  }

  Future<void> _editSlot(_TestSlot slot) async {
    final current = _saved[slot.id];
    final emailCtrl = TextEditingController(text: current?['email'] ?? '');
    final passCtrl = TextEditingController(text: current?['password'] ?? '');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Set Akun ${slot.label}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailCtrl,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: passCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          if (current != null)
            TextButton(
              onPressed: () {
                setState(() => _saved.remove(slot.id));
                _persistSaved();
                Navigator.pop(ctx, false);
              },
              child: const Text('Hapus Slot'),
            ),
          ElevatedButton(
            onPressed: () {
              if (emailCtrl.text.trim().isEmpty || passCtrl.text.isEmpty) {
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Simpan'),
          ),
        ],
      ),
    );

    if (result == true) {
      final trimmedEmail = emailCtrl.text.trim();
      final password = passCtrl.text;
      final resolvedIdentity = await _resolveIdentityByEmail(trimmedEmail);

      setState(() {
        _saved[slot.id] = {
          'email': trimmedEmail,
          'password': password,
          if (resolvedIdentity case {'user_id': final String userId})
            'user_id': userId,
          if (resolvedIdentity case {'full_name': final String fullName})
            'full_name': fullName,
          if (resolvedIdentity case {'role': final String role}) 'role': role,
        };
      });
      await _persistSaved();
    }

    emailCtrl.dispose();
    passCtrl.dispose();
  }

  Future<void> _switchTo(_TestSlot slot) async {
    final account = _saved[slot.id];
    if (account == null) return;

    setState(() => _busySlotId = slot.id);

    try {
      final latestEmail = await _resolveLatestEmail(account);
      final response = await _supabase.auth.signInWithPassword(
        email: latestEmail,
        password: account['password']!,
      );

      final user = response.user;
      if (user == null) {
        throw Exception('Login gagal');
      }

      final profile = await _supabase
          .from('users')
          .select('role')
          .eq('id', user.id)
          .single();

      final role = (profile['role'] ?? '').toString();
      if (!mounted) return;

      Navigator.pop(context);
      if (!mounted) return;
      await TestAccountSwitcher.saveLastLogin(
        email: latestEmail,
        password: account['password']!,
      );
      if (latestEmail != account['email']) {
        _saved[slot.id] = {...account, 'email': latestEmail};
        await _persistSaved();
      }
      _goByRole(role);

      if (role != slot.expectedRole) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Berhasil switch ke role "$role" (slot ${slot.expectedRole}).',
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Gagal switch akun: $e')));
    } finally {
      if (mounted) setState(() => _busySlotId = null);
    }
  }

  Future<Map<String, String>?> _resolveIdentityByEmail(String email) async {
    try {
      final user = await _supabase
          .from('users')
          .select('id, full_name, role')
          .eq('email', email)
          .maybeSingle();
      if (user == null) return null;
      return {
        'user_id': (user['id'] ?? '').toString(),
        'full_name': (user['full_name'] ?? '').toString(),
        'role': (user['role'] ?? '').toString(),
      };
    } catch (_) {
      return null;
    }
  }

  Future<String> _resolveLatestEmail(Map<String, String> account) async {
    final userId = (account['user_id'] ?? '').trim();
    if (userId.isEmpty) {
      return account['email']!;
    }

    try {
      final user = await _supabase
          .from('users')
          .select('email')
          .eq('id', userId)
          .maybeSingle();
      final latestEmail = (user?['email'] ?? '').toString().trim();
      if (latestEmail.isNotEmpty) {
        return latestEmail;
      }
    } catch (_) {}

    return account['email']!;
  }

  void _goByRole(String role) {
    switch (role) {
      case 'admin':
        context.go('/admin');
        break;
      case 'manager':
      case 'spv':
        context.go('/spv');
        break;
      case 'sator':
        context.go('/sator');
        break;
      case 'promotor':
      default:
        context.go('/promotor');
        break;
    }
  }

  Future<void> _clearAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Semua Slot?'),
        content: const Text(
          'Semua email/password test yang tersimpan akan dihapus.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _saved = {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.74,
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.switch_account),
              title: const Text(
                'Account Switcher',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('Pindah akun dengan cepat'),
              trailing: TextButton(
                onPressed: _saved.isEmpty ? null : _clearAll,
                child: const Text('Hapus Semua'),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.separated(
                      itemCount: _slots.length,
                      separatorBuilder: (_, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final slot = _slots[index];
                        final account = _saved[slot.id];
                        final hasAccount = account != null;
                        final isBusy = _busySlotId == slot.id;

                        return ListTile(
                          leading: CircleAvatar(
                            radius: 14,
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          title: Text(slot.label),
                          subtitle: Text(
                            hasAccount
                                ? '${account['email']} (${slot.expectedRole})'
                                : 'Belum diisi (${slot.expectedRole})',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit slot',
                                onPressed: isBusy
                                    ? null
                                    : () => _editSlot(slot),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              FilledButton(
                                onPressed: (!hasAccount || isBusy)
                                    ? null
                                    : () => _switchTo(slot),
                                style: FilledButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 8,
                                  ),
                                ),
                                child: isBusy
                                    ? const SizedBox(
                                        width: 14,
                                        height: 14,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('Masuk'),
                              ),
                            ],
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

class _TestSlot {
  final String id;
  final String label;
  final String expectedRole;

  const _TestSlot({
    required this.id,
    required this.label,
    required this.expectedRole,
  });
}
