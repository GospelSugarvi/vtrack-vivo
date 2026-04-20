import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (_) {}
}

class NotificationPushService {
  NotificationPushService._();

  static final NotificationPushService instance = NotificationPushService._();

  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<AuthState>? _authSub;
  StreamSubscription<String>? _tokenRefreshSub;

  String? _currentToken;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    _authSub = _supabase.auth.onAuthStateChange.listen((event) async {
      switch (event.event) {
        case AuthChangeEvent.signedIn:
        case AuthChangeEvent.tokenRefreshed:
        case AuthChangeEvent.userUpdated:
        case AuthChangeEvent.initialSession:
          await syncToken();
          break;
        case AuthChangeEvent.signedOut:
          await deactivateCurrentToken();
          break;
        default:
          break;
      }
    });

    _tokenRefreshSub = FirebaseMessaging.instance.onTokenRefresh.listen((token) {
      _currentToken = token;
      unawaited(_saveToken(token));
    });

    await syncToken();
  }

  Future<void> syncToken() async {
    if (kIsWeb) return;

    final currentUser = _supabase.auth.currentUser;
    if (currentUser == null) return;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission();
      final authorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!authorized) return;

      final token = await FirebaseMessaging.instance.getToken();
      if (token == null || token.trim().isEmpty) return;

      _currentToken = token;
      await _saveToken(token);
    } catch (error, stack) {
      debugPrint('FCM sync failed: $error');
      debugPrint('$stack');
    }
  }

  Future<void> deactivateCurrentToken() async {
    final token = _currentToken;
    if (token == null || token.trim().isEmpty) return;

    try {
      await _supabase
          .from('user_device_tokens')
          .update({
            'is_active': false,
            'last_seen_at': DateTime.now().toIso8601String(),
          })
          .eq('fcm_token', token);
    } catch (error, stack) {
      debugPrint('Deactivate FCM token failed: $error');
      debugPrint('$stack');
    }
  }

  Future<void> _saveToken(String token) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    final packageInfo = await PackageInfo.fromPlatform();

    await _supabase.rpc(
      'sync_user_device_token',
      params: {
        'p_fcm_token': token,
        'p_platform': defaultTargetPlatform.name,
        'p_device_label': packageInfo.appName,
        'p_app_version': packageInfo.version,
      },
    );
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _tokenRefreshSub?.cancel();
    _initialized = false;
  }
}
