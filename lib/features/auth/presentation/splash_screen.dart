import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../main.dart';
import '../../../ui/foundation/app_colors.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _checkAuthAndNavigate();
  }

  Future<void> _checkAuthAndNavigate() async {
    await Future.delayed(const Duration(seconds: 2));

    if (!mounted) return;

    final session = supabase.auth.currentSession;

    if (session != null) {
      // User is logged in, fetch their role and navigate
      try {
        final userId = session.user.id;
        final response = await supabase
            .from('users')
            .select('role')
            .eq('id', userId)
            .single();

        if (!mounted) return;

        final role = response['role'] as String;
        _navigateByRole(role);
      } catch (e) {
        // Error fetching role, go to login
        if (mounted) context.go('/login');
      }
    } else {
      // Not logged in
      if (mounted) context.go('/login');
    }
  }

  void _navigateByRole(String role) {
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
              style: TextStyle(
                fontSize: 16,
                color: AppColors.textInverse,
              ),
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
