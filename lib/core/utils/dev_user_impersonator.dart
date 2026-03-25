import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Development tool untuk "login as" user lain
/// HANYA UNTUK TESTING - JANGAN DIPAKAI DI PRODUCTION!
class DevUserImpersonator extends StatefulWidget {
  const DevUserImpersonator({super.key});

  @override
  State<DevUserImpersonator> createState() => _DevUserImpersonatorState();
}

class _DevUserImpersonatorState extends State<DevUserImpersonator> {
  List<Map<String, dynamic>> _users = [];
  bool _loading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final response = await Supabase.instance.client
          .from('users')
          .select('id, email, full_name, role')
          .order('full_name');
      
      setState(() {
        _users = List<Map<String, dynamic>>.from(response);
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    if (_searchQuery.isEmpty) return _users;
    return _users.where((user) {
      final name = user['full_name']?.toString().toLowerCase() ?? '';
      final email = user['email']?.toString().toLowerCase() ?? '';
      final role = user['role']?.toString().toLowerCase() ?? '';
      final query = _searchQuery.toLowerCase();
      return name.contains(query) || email.contains(query) || role.contains(query);
    }).toList();
  }

  Future<void> _impersonateUser(Map<String, dynamic> user) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('⚠️ DEV: Impersonate User'),
        content: Text(
          'This will change your current session to:\n\n'
          'Name: ${user['full_name']}\n'
          'Email: ${user['email']}\n'
          'Role: ${user['role']}\n\n'
          'You will need to refresh the page.\n'
          'Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Impersonate'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      // Note: This is a simplified version
      // In production, you'd need a proper backend endpoint to handle this securely
      
      // For now, show instructions
      if (mounted) {
        Navigator.pop(context);
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Manual Login Required'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('To test as this user, please:'),
                const SizedBox(height: 16),
                Text('1. Logout from current session'),
                Text('2. Login with:'),
                const SizedBox(height: 8),
                SelectableText('   Email: ${user['email']}'),
                const Text('   Password: (ask admin)'),
                const SizedBox(height: 16),
                const Text(
                  'Or open in Incognito/Private window',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  await Supabase.instance.client.auth.signOut();
                  if (context.mounted) {
                    context.go('/login');
                  }
                },
                child: const Text('Logout Now'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_search, color: Colors.orange),
              const SizedBox(width: 8),
              const Text(
                'DEV: Login As User',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadUsers,
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Select a user to see their credentials',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const Divider(height: 24),
          TextField(
            decoration: const InputDecoration(
              hintText: 'Search by name, email, or role...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Expanded(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: _filteredUsers.length,
                itemBuilder: (context, index) {
                  final user = _filteredUsers[index];
                  final role = user['role'] ?? '';
                  Color roleColor = Colors.grey;
                  IconData roleIcon = Icons.person;
                  
                  switch (role) {
                    case 'admin':
                      roleColor = Colors.blue;
                      roleIcon = Icons.admin_panel_settings;
                      break;
                    case 'promotor':
                      roleColor = Colors.green;
                      roleIcon = Icons.person;
                      break;
                    case 'sator':
                      roleColor = Colors.orange;
                      roleIcon = Icons.supervisor_account;
                      break;
                    case 'spv':
                      roleColor = Colors.red;
                      roleIcon = Icons.manage_accounts;
                      break;
                  }

                  return ListTile(
                    dense: true,
                    leading: Icon(roleIcon, color: roleColor),
                    title: Text(user['full_name'] ?? 'No name'),
                    subtitle: Text(user['email'] ?? 'No email'),
                    trailing: Chip(
                      label: Text(
                        role.toUpperCase(),
                        style: const TextStyle(fontSize: 10),
                      ),
                      backgroundColor: roleColor.withValues(alpha: 0.2),
                    ),
                    onTap: () => _impersonateUser(user),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}
