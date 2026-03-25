import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dev_user_impersonator.dart';

/// Development tool untuk switch role tanpa logout
/// Hanya untuk testing, jangan dipakai di production!
class DevRoleSwitcher extends StatelessWidget {
  const DevRoleSwitcher({super.key});

  Future<void> _switchRole(BuildContext context, String targetRole) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      // Update role di database
      await Supabase.instance.client
          .from('users')
          .update({'role': targetRole})
          .eq('id', userId);

      if (context.mounted) {
        // Navigate ke dashboard yang sesuai
        if (targetRole == 'admin') {
          context.go('/admin');
        } else if (targetRole == 'promotor') {
          context.go('/promotor');
        } else if (targetRole == 'sator') {
          context.go('/sator');
        } else if (targetRole == 'spv') {
          context.go('/spv');
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Role switched to: $targetRole'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      bottom: 80,
      child: FloatingActionButton(
        heroTag: 'dev_role_switcher',
        mini: true,
        backgroundColor: Colors.purple,
        onPressed: () {
          showModalBottomSheet(
            context: context,
            builder: (context) => Container(
              padding: const EdgeInsets.all(16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.swap_horiz, color: Colors.purple),
                        SizedBox(width: 8),
                        Text('DEV Tools', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text('Development & Testing Tools', style: TextStyle(fontSize: 12, color: Colors.grey)),
                    const Divider(height: 24),
                    const Text('SWITCH ROLE (same user)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.admin_panel_settings, color: Colors.blue),
                      title: const Text('Admin'),
                      subtitle: const Text('Full system access'),
                      onTap: () {
                        Navigator.pop(context);
                        _switchRole(context, 'admin');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.person, color: Colors.green),
                      title: const Text('Promotor'),
                      subtitle: const Text('Field sales representative'),
                      onTap: () {
                        Navigator.pop(context);
                        _switchRole(context, 'promotor');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.supervisor_account, color: Colors.orange),
                      title: const Text('Sator'),
                      subtitle: const Text('Area supervisor'),
                      onTap: () {
                        Navigator.pop(context);
                        _switchRole(context, 'sator');
                      },
                    ),
                    ListTile(
                      leading: const Icon(Icons.manage_accounts, color: Colors.red),
                      title: const Text('SPV'),
                      subtitle: const Text('Regional manager'),
                      onTap: () {
                        Navigator.pop(context);
                        _switchRole(context, 'spv');
                      },
                    ),
                    const Divider(height: 24),
                    const Text('LOGIN AS USER (different user)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 8),
                    ListTile(
                      leading: const Icon(Icons.person_search, color: Colors.orange),
                      title: const Text('Login As...'),
                      subtitle: const Text('Test as a different user'),
                      trailing: const Icon(Icons.arrow_forward),
                      onTap: () {
                        Navigator.pop(context);
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          builder: (context) => SizedBox(
                            height: MediaQuery.of(context).size.height * 0.8,
                            child: const DevUserImpersonator(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          );
        },
        child: const Icon(Icons.swap_horiz, size: 20),
      ),
    );
  }
}
