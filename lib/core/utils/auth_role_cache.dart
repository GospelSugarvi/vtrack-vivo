import 'package:shared_preferences/shared_preferences.dart';

class AuthRoleCache {
  static const String _rolePrefix = 'auth_role_cache.role.';
  static const String _timePrefix = 'auth_role_cache.time.';
  static const Duration _maxAge = Duration(hours: 12);

  static Future<void> saveRole({
    required String userId,
    required String role,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_rolePrefix$userId', role);
    await prefs.setInt(
      '$_timePrefix$userId',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<String?> getFreshRole(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString('$_rolePrefix$userId');
    final timestamp = prefs.getInt('$_timePrefix$userId');
    if (role == null || timestamp == null) return null;

    final cachedAt = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final age = DateTime.now().difference(cachedAt);
    if (age > _maxAge) {
      await prefs.remove('$_rolePrefix$userId');
      await prefs.remove('$_timePrefix$userId');
      return null;
    }

    return role;
  }

  static Future<void> clearRole(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_rolePrefix$userId');
    await prefs.remove('$_timePrefix$userId');
  }
}
