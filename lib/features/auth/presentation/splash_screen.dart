import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/auth_role_cache.dart';
import '../../../main.dart';
import '../../../ui/foundation/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _navigationScheduled = false;

  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    if (!mounted) return;

    final session = supabase.auth.currentSession;

    if (session != null) {
      final userId = session.user.id;
      final cachedRole = await AuthRoleCache.getFreshRole(userId);

      if (!mounted) return;

      if (cachedRole != null) {
        _navigateByRole(cachedRole);
        return;
      }

      try {
        final response = await supabase
            .from('users')
            .select('role')
            .eq('id', userId)
            .single();

        if (!mounted) return;

        final role = response['role'] as String;
        await AuthRoleCache.saveRole(userId: userId, role: role);
        _navigateByRole(role);
      } catch (e) {
        await AuthRoleCache.clearRole(userId);
        _goWhenReady('/login');
      }
    } else {
      _goWhenReady('/login');
    }
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
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Logo placeholder
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Center(
                child: Text(
                  'V',
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryStrong,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'VTrack',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.surface,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Sales Performance Tracker',
              style: TextStyle(fontSize: 16, color: AppColors.textInverse),
            ),
            const SizedBox(height: 48),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.surface),
            ),
          ],
        ),
      ),
    );
  }
}
