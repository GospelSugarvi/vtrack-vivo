import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../main.dart';
import '../../../core/utils/auth_role_cache.dart';
import '../../../core/utils/success_dialog.dart';
import '../../../ui/foundation/app_colors.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>(debugLabel: 'login_form');
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _versionLabel;
  bool _navigationScheduled = false;

  void _logLinkError({
    required String flow,
    required Object error,
    StackTrace? stackTrace,
  }) {
    debugPrint('[Auth/$flow] $error');
    if (stackTrace != null) {
      debugPrint('[Auth/$flow][stacktrace]\n$stackTrace');
    }
  }

  String _normalizeIndonesianPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return '';
    if (digits.startsWith('62')) return digits;
    if (digits.startsWith('0')) return '62${digits.substring(1)}';
    if (digits.startsWith('8')) return '62$digits';
    return digits;
  }

  @override
  void initState() {
    super.initState();
    _loadAppInfo();
  }

  Future<void> _loadAppInfo() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      final version = info.version.trim();
      final build = info.buildNumber.trim();
      final label = build.isEmpty ? 'v$version' : 'v$version+$build';
      setState(() => _versionLabel = label);
    } catch (_) {
      if (!mounted) return;
      setState(() => _versionLabel = null);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;

      // Login with Supabase Auth (proper way)
      final response = await supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user == null) {
        throw Exception('Login gagal');
      }

      // After successful auth, fetch user profile
      final userId = response.user!.id;
      final userProfile = await supabase
          .from('users')
          .select('role')
          .eq('id', userId)
          .single();

      if (!mounted) return;

      // Navigate based on role
      final role = userProfile['role'] as String;
      await AuthRoleCache.saveRole(userId: userId, role: role);
      _navigateByRole(role);
    } catch (e) {
      String errorMsg = 'Terjadi kesalahan';

      if (e.toString().contains('Invalid login credentials')) {
        errorMsg = 'Email atau password salah';
      } else if (e.toString().contains('Email not confirmed')) {
        errorMsg = 'Email belum dikonfirmasi';
      } else if (e.toString().contains('No rows returned')) {
        errorMsg = 'Akun tidak terdaftar di sistem';
      }

      setState(() => _errorMessage = errorMsg);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _supervisorRoleFor(String role) {
    switch (role) {
      case 'promotor':
        return 'sator';
      case 'sator':
        return 'spv';
      case 'spv':
        return 'manager';
      default:
        return null;
    }
  }

  String _roleLabel(String role) {
    switch (role) {
      case 'promotor':
        return 'Promotor';
      case 'sator':
        return 'SATOR';
      case 'spv':
        return 'SPV';
      case 'manager':
        return 'Manager';
      case 'admin':
        return 'Admin';
      default:
        return role;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchSignupSupervisors(
    String role,
  ) async {
    final raw = await supabase.rpc(
      'get_signup_supervisor_options',
      params: {'p_role': role},
    );
    return List<Map<String, dynamic>>.from(raw as List? ?? const []);
  }

  Future<List<Map<String, dynamic>>> _fetchRegisteredUsersForRole(
    String role,
  ) async {
    final raw = await supabase.rpc(
      'get_signup_registered_users',
      params: {'p_role': role},
    );
    return List<Map<String, dynamic>>.from(raw as List? ?? const []);
  }

  Future<void> _showForgotPasswordDialog() async {
    final emailController = TextEditingController(
      text: _emailController.text.trim(),
    );
    var isSending = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            return AlertDialog(
              title: const Text('Reset Password'),
              content: TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Email',
                  hintText: 'Masukkan email akun',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSending
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSending
                      ? null
                      : () async {
                          var dialogClosed = false;
                          final email = emailController.text.trim();
                          if (email.isEmpty || !email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Format email tidak valid'),
                              ),
                            );
                            return;
                          }
                          setInnerState(() => isSending = true);
                          try {
                            await supabase.auth.resetPasswordForEmail(email);
                            if (!dialogContext.mounted) return;
                            dialogClosed = true;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            await showSuccessDialog(
                              this.context,
                              title: 'OTP Terkirim',
                              message:
                                  'Kode OTP reset password sudah dikirim ke email.',
                            );
                            if (!mounted) return;
                            this.context.push(
                              '/reset-password-otp?email=${Uri.encodeComponent(email)}',
                            );
                          } on AuthRetryableFetchException catch (e, st) {
                            _logLinkError(
                              flow: 'reset-password-link',
                              error: 'email=$email; $e',
                              stackTrace: st,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Server email gagal mengirim. Cek konfigurasi SMTP Supabase.',
                                ),
                              ),
                            );
                          } on AuthException catch (e, st) {
                            _logLinkError(
                              flow: 'reset-password-link',
                              error: e,
                              stackTrace: st,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  'Gagal kirim email: ${e.message}',
                                ),
                              ),
                            );
                          } catch (e, st) {
                            _logLinkError(
                              flow: 'reset-password-link',
                              error: e,
                              stackTrace: st,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Terjadi kesalahan: $e')),
                            );
                          } finally {
                            if (dialogContext.mounted && !dialogClosed) {
                              setInnerState(() => isSending = false);
                            }
                          }
                        },
                  child: isSending
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kirim OTP'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showRegisterDialog() async {
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    var selectedRole = 'promotor';
    var userRows = <Map<String, dynamic>>[];
    String? selectedUserId;
    var supervisorRows = <Map<String, dynamic>>[];
    String? selectedSupervisorId;
    var isSubmitting = false;
    var isLoadingUsers = false;
    var isLoadingSupervisors = false;

    try {
      userRows = await _fetchRegisteredUsersForRole(selectedRole);
      selectedUserId = userRows.isEmpty
          ? null
          : userRows.first['user_id']?.toString();
      if (selectedUserId != null) {
        final picked = userRows.firstWhere(
          (e) => e['user_id']?.toString() == selectedUserId,
          orElse: () => userRows.first,
        );
        emailController.text = (picked['email'] ?? '').toString().trim();
        phoneController.text = _normalizeIndonesianPhone(
          (picked['whatsapp_phone'] ?? '').toString().trim(),
        );
      }
      supervisorRows = await _fetchSignupSupervisors(selectedRole);
      selectedSupervisorId = supervisorRows.isEmpty
          ? null
          : supervisorRows.first['supervisor_id']?.toString();
    } catch (_) {
      supervisorRows = <Map<String, dynamic>>[];
      selectedSupervisorId = null;
    }

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setInnerState) {
            InputDecoration buildFieldDecoration(
              String label, {
              String? hint,
            }) {
              return InputDecoration(
                labelText: label,
                hintText: hint,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              );
            }

            return AlertDialog(
              title: const Text('Aktivasi Akun'),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      isExpanded: true,
                      decoration: buildFieldDecoration('Role'),
                      items: const [
                        DropdownMenuItem(
                          value: 'promotor',
                          child: Text(
                            'Promotor',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'sator',
                          child: Text(
                            'SATOR',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'spv',
                          child: Text(
                            'SPV',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      selectedItemBuilder: (context) => const [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'Promotor',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'SATOR',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            'SPV',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                      onChanged: isSubmitting
                          ? null
                          : (value) async {
                              if (value == null || value == selectedRole) {
                                return;
                              }
                              setInnerState(() {
                                selectedRole = value;
                                selectedUserId = null;
                                userRows = <Map<String, dynamic>>[];
                                emailController.clear();
                                phoneController.clear();
                                selectedSupervisorId = null;
                                supervisorRows = <Map<String, dynamic>>[];
                                isLoadingUsers = true;
                                isLoadingSupervisors = true;
                              });
                              try {
                                final users =
                                    await _fetchRegisteredUsersForRole(value);
                                final rows = await _fetchSignupSupervisors(
                                  value,
                                );
                                if (!dialogContext.mounted) return;
                                setInnerState(() {
                                  userRows = users;
                                  selectedUserId = users.isEmpty
                                      ? null
                                      : users.first['user_id']?.toString();
                                  if (selectedUserId != null) {
                                    final picked = users.firstWhere(
                                      (e) =>
                                          e['user_id']?.toString() ==
                                          selectedUserId,
                                      orElse: () => users.first,
                                    );
                                    emailController.text =
                                        (picked['email'] ?? '')
                                            .toString()
                                            .trim();
                                    phoneController.text =
                                        _normalizeIndonesianPhone(
                                          (picked['whatsapp_phone'] ?? '')
                                              .toString()
                                              .trim(),
                                        );
                                  }
                                  supervisorRows = rows;
                                  selectedSupervisorId = rows.isEmpty
                                      ? null
                                      : rows.first['supervisor_id']?.toString();
                                  isLoadingUsers = false;
                                  isLoadingSupervisors = false;
                                });
                              } catch (_) {
                                if (!dialogContext.mounted) return;
                                setInnerState(() {
                                  userRows = <Map<String, dynamic>>[];
                                  selectedUserId = null;
                                  supervisorRows = <Map<String, dynamic>>[];
                                  selectedSupervisorId = null;
                                  isLoadingUsers = false;
                                  isLoadingSupervisors = false;
                                });
                              }
                            },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedUserId,
                      isExpanded: true,
                      decoration: buildFieldDecoration(
                        'Nama User',
                        hint: 'Pilih user terdaftar',
                      ),
                      items: userRows.map((row) {
                        final id = row['user_id']?.toString() ?? '';
                        final fullName = (row['full_name'] ?? '-')
                            .toString()
                            .trim();
                        final nickname = (row['nickname'] ?? '')
                            .toString()
                            .trim();
                        final label = nickname.isEmpty || nickname == fullName
                            ? fullName
                            : '$fullName ($nickname)';
                        return DropdownMenuItem<String>(
                          value: id,
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }).toList(),
                      onChanged: (isSubmitting || isLoadingUsers)
                          ? null
                          : (value) {
                              setInnerState(() => selectedUserId = value);
                              final picked = userRows.firstWhere(
                                (e) => e['user_id']?.toString() == value,
                                orElse: () => <String, dynamic>{},
                              );
                              emailController.text = (picked['email'] ?? '')
                                  .toString()
                                  .trim();
                              phoneController.text = _normalizeIndonesianPhone(
                                (picked['whatsapp_phone'] ?? '')
                                    .toString()
                                    .trim(),
                              );
                            },
                    ),
                    if (isLoadingUsers)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (!isLoadingUsers && userRows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          'Tidak ada user terdaftar untuk role ini.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.danger),
                        ),
                      ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      keyboardType: TextInputType.emailAddress,
                      decoration: buildFieldDecoration(
                        'Email',
                        hint: 'emailuser@contoh.com',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      keyboardType: TextInputType.phone,
                      onChanged: (value) {
                        final normalized = _normalizeIndonesianPhone(value);
                        if (normalized.isEmpty) return;
                        if (normalized == value) return;
                        phoneController.value = TextEditingValue(
                          text: normalized,
                          selection: TextSelection.collapsed(
                            offset: normalized.length,
                          ),
                        );
                      },
                      decoration: buildFieldDecoration(
                        'No. WhatsApp',
                        hint: '628xxxxxxxxxx',
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_supervisorRoleFor(selectedRole) != null)
                      DropdownButtonFormField<String>(
                        initialValue: selectedSupervisorId,
                        isExpanded: true,
                        decoration: buildFieldDecoration(
                          'Atasan ${_roleLabel(_supervisorRoleFor(selectedRole)!)}',
                        ),
                        items: supervisorRows.map((row) {
                          final id = row['supervisor_id']?.toString() ?? '';
                          final name = (row['full_name'] ?? '-')
                              .toString()
                              .trim();
                          final nickname = (row['nickname'] ?? '')
                              .toString()
                              .trim();
                          final label = nickname.isEmpty || nickname == name
                              ? name
                              : '$name ($nickname)';
                          return DropdownMenuItem<String>(
                            value: id,
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          );
                        }).toList(),
                        selectedItemBuilder: (context) =>
                            supervisorRows.map((row) {
                              final name = (row['full_name'] ?? '-')
                                  .toString()
                                  .trim();
                              final nickname = (row['nickname'] ?? '')
                                  .toString()
                                  .trim();
                              final label = nickname.isEmpty || nickname == name
                                  ? name
                                  : '$name ($nickname)';
                              return Align(
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                        onChanged: (isSubmitting || isLoadingSupervisors)
                            ? null
                            : (value) => setInnerState(
                                () => selectedSupervisorId = value,
                              ),
                      ),
                    if (isLoadingSupervisors)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (!isLoadingSupervisors &&
                        _supervisorRoleFor(selectedRole) != null &&
                        supervisorRows.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Data atasan tidak tersedia untuk role ini.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppColors.danger),
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Batal'),
                ),
                ElevatedButton(
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          var dialogClosed = false;
                          final email = emailController.text.trim();
                          final picked = userRows.firstWhere(
                            (e) => e['user_id']?.toString() == selectedUserId,
                            orElse: () => <String, dynamic>{},
                          );
                          final registeredPhone = (picked['whatsapp_phone'] ??
                                  '')
                              .toString()
                              .trim();
                          final inputPhone = phoneController.text.trim();
                          final normalizedInputPhone =
                              _normalizeIndonesianPhone(inputPhone);
                          final phoneForClaim = registeredPhone.isNotEmpty
                              ? registeredPhone
                              : normalizedInputPhone;

                          if (selectedUserId == null ||
                              selectedUserId!.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Pilih nama user terdaftar'),
                              ),
                            );
                            return;
                          }
                          if (email.isEmpty || !email.contains('@')) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'User ini belum punya email valid di sistem',
                                ),
                              ),
                            );
                            return;
                          }
                          if (_supervisorRoleFor(selectedRole) != null &&
                              (selectedSupervisorId == null ||
                                  selectedSupervisorId!.isEmpty)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Atasan wajib dipilih'),
                              ),
                            );
                            return;
                          }

                          setInnerState(() => isSubmitting = true);
                          try {
                            Future<void> runClaim(String phone) async {
                              await supabase.rpc(
                                'claim_registered_user_email',
                                params: {
                                  'p_user_id': selectedUserId,
                                  'p_role': selectedRole,
                                  'p_email': email,
                                  'p_whatsapp_phone': phone,
                                },
                              );
                            }

                            try {
                              await runClaim(phoneForClaim);
                            } catch (claimError, claimStackTrace) {
                              _logLinkError(
                                flow: 'signup-activation-link-claim',
                                error: claimError,
                                stackTrace: claimStackTrace,
                              );
                              final isPhoneMismatch = claimError
                                  .toString()
                                  .contains(
                                    'Nomor telepon tidak sesuai data sistem',
                                  );
                              if (!isPhoneMismatch) rethrow;
                              await runClaim('');
                              _logLinkError(
                                flow: 'signup-activation-link-claim',
                                error:
                                    'Phone mismatch bypassed with empty phone param',
                              );
                            }
                            await supabase.auth.resetPasswordForEmail(email);
                            if (!dialogContext.mounted) return;
                            dialogClosed = true;
                            Navigator.of(dialogContext).pop();
                            if (!mounted) return;
                            await showSuccessDialog(
                              this.context,
                              title: 'OTP Aktivasi Terkirim',
                              message:
                                  'Kode OTP aktivasi akun sudah dikirim ke email user.',
                            );
                            if (!mounted) return;
                            this.context.push(
                              '/reset-password-otp?email=${Uri.encodeComponent(email)}',
                            );
                          } on AuthRetryableFetchException catch (e, st) {
                            _logLinkError(
                              flow: 'signup-activation-link',
                              error: 'email=$email; $e',
                              stackTrace: st,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Email OTP aktivasi gagal terkirim. Periksa SMTP Supabase.',
                                ),
                              ),
                            );
                          } on AuthException catch (e, st) {
                            _logLinkError(
                              flow: 'signup-activation-link',
                              error: e,
                              stackTrace: st,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(
                                content: Text('Aktivasi gagal: ${e.message}'),
                              ),
                            );
                          } catch (e, st) {
                            _logLinkError(
                              flow: 'signup-activation-link',
                              error: e,
                              stackTrace: st,
                            );
                            if (!mounted) return;
                            ScaffoldMessenger.of(this.context).showSnackBar(
                              SnackBar(content: Text('Terjadi kesalahan: $e')),
                            );
                          } finally {
                            if (dialogContext.mounted && !dialogClosed) {
                              setInnerState(() => isSubmitting = false);
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Kirim OTP Aktivasi'),
                ),
              ],
            );
          },
        );
      },
    );

  }

  void _navigateByRole(String role) {
    switch (role) {
      case 'admin':
        _goWhenReady('/admin');
        break;
      case 'manager':
      case 'spv':
        _goWhenReady('/spv');
        break;
      case 'sator':
        _goWhenReady('/sator');
        break;
      case 'promotor':
      default:
        _goWhenReady('/promotor');
        break;
    }
  }

  void _goWhenReady(String location) {
    if (!mounted || _navigationScheduled) return;
    _navigationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.go(location);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final baseBackground = isDark
        ? AppColors.darkBackground
        : AppColors.background;
    final surface = isDark ? AppColors.darkSurface : AppColors.surface;
    final border = isDark ? AppColors.darkBorder : AppColors.border;
    final textPrimary = isDark ? AppColors.darkTextPrimary : AppColors.textPrimary;
    final textSecondary = isDark
        ? AppColors.darkTextSecondary
        : AppColors.textSecondary;

    InputDecoration buildInputDecoration({
      required String label,
      required String hint,
      required IconData icon,
      Widget? suffixIcon,
    }) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: textSecondary),
        suffixIcon: suffixIcon,
        labelStyle: TextStyle(color: textSecondary),
        hintStyle: TextStyle(color: textSecondary.withValues(alpha: 0.85)),
        floatingLabelStyle: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w600,
        ),
        filled: true,
        fillColor: isDark ? AppColors.darkSurfaceVariant : AppColors.surfaceVariant,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.8),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: Container(
          decoration: BoxDecoration(color: baseBackground),
          child: Stack(
            children: [
              Positioned(
                left: -80,
                top: -60,
                child: Container(
                  width: 220,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.primary.withValues(alpha: isDark ? 0.18 : 0.12),
                  ),
                ),
              ),
              Positioned(
                right: -90,
                bottom: 80,
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.success.withValues(alpha: isDark ? 0.12 : 0.08),
                  ),
                ),
              ),
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: constraints.maxHeight - 48),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'VTrack',
                                textAlign: TextAlign.center,
                                style: textTheme.headlineMedium?.copyWith(
                                  color: textPrimary,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.3,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Sales Performance Workspace',
                                textAlign: TextAlign.center,
                                style: textTheme.bodyMedium?.copyWith(color: textSecondary),
                              ),
                              const SizedBox(height: 18),
                              Container(
                                padding: const EdgeInsets.all(22),
                                decoration: BoxDecoration(
                                  color: surface.withValues(alpha: isDark ? 0.95 : 0.98),
                                  borderRadius: BorderRadius.circular(22),
                                  border: Border.all(color: border),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.08),
                                      blurRadius: 26,
                                      offset: const Offset(0, 12),
                                    ),
                                  ],
                                ),
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color: AppColors.primary.withValues(alpha: 0.14),
                                              borderRadius: BorderRadius.circular(12),
                                            ),
                                            child: const Icon(
                                              Icons.shield_outlined,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  'Masuk Akun',
                                                  style: textTheme.titleLarge?.copyWith(
                                                    color: textPrimary,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                                Text(
                                                  'Gunakan email terdaftar untuk lanjut.',
                                                  style: textTheme.bodySmall?.copyWith(
                                                    color: textSecondary,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      if (_errorMessage != null)
                                        Container(
                                          padding: const EdgeInsets.all(12),
                                          margin: const EdgeInsets.only(bottom: 14),
                                          decoration: BoxDecoration(
                                            color: AppColors.dangerSurface,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: AppColors.danger.withValues(alpha: 0.3),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              const Icon(
                                                Icons.error_outline,
                                                color: AppColors.danger,
                                                size: 18,
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _errorMessage!,
                                                  style: textTheme.bodySmall?.copyWith(
                                                    color: AppColors.danger,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      TextFormField(
                                        controller: _emailController,
                                        keyboardType: TextInputType.emailAddress,
                                        textInputAction: TextInputAction.next,
                                        style: TextStyle(color: textPrimary),
                                        cursorColor: AppColors.primary,
                                        decoration: buildInputDecoration(
                                          label: 'Email',
                                          hint: 'nama@email.com',
                                          icon: Icons.alternate_email_rounded,
                                        ),
                                        validator: (value) {
                                          if (value == null || value.trim().isEmpty) {
                                            return 'Email tidak boleh kosong';
                                          }
                                          if (!value.contains('@')) {
                                            return 'Format email tidak valid';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _passwordController,
                                        obscureText: _obscurePassword,
                                        textInputAction: TextInputAction.done,
                                        onFieldSubmitted: (_) => _handleLogin(),
                                        style: TextStyle(color: textPrimary),
                                        cursorColor: AppColors.primary,
                                        decoration: buildInputDecoration(
                                          label: 'Password',
                                          hint: 'Masukkan password',
                                          icon: Icons.lock_outline_rounded,
                                          suffixIcon: IconButton(
                                            icon: Icon(
                                              _obscurePassword
                                                  ? Icons.visibility_off_rounded
                                                  : Icons.visibility_rounded,
                                              color: textSecondary,
                                            ),
                                            onPressed: () => setState(
                                              () => _obscurePassword = !_obscurePassword,
                                            ),
                                          ),
                                        ),
                                        validator: (value) {
                                          if (value == null || value.isEmpty) {
                                            return 'Password tidak boleh kosong';
                                          }
                                          return null;
                                        },
                                      ),
                                      const SizedBox(height: 18),
                                      SizedBox(
                                        height: 48,
                                        child: ElevatedButton(
                                          onPressed: _isLoading ? null : _handleLogin,
                                          child: _isLoading
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: CircularProgressIndicator(
                                                    strokeWidth: 2.2,
                                                    valueColor:
                                                        AlwaysStoppedAnimation<Color>(
                                                      Colors.white,
                                                    ),
                                                  ),
                                                )
                                              : const Text('Masuk'),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextButton(
                                              onPressed: _isLoading
                                                  ? null
                                                  : _showForgotPasswordDialog,
                                              child: const Text('Reset via OTP'),
                                            ),
                                          ),
                                          Expanded(
                                            child: TextButton(
                                              onPressed: _isLoading
                                                  ? null
                                                  : _showRegisterDialog,
                                              child: const Text('Aktivasi Akun'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _versionLabel == null
                                    ? 'VTrack'
                                    : 'VTrack ${_versionLabel!}',
                                textAlign: TextAlign.center,
                                style: textTheme.bodySmall?.copyWith(color: textSecondary),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
