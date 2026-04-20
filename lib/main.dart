import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'dart:async';
import 'dart:ui';

import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/app_font_preference_provider.dart';
import 'core/theme/theme_mode_provider.dart';
import 'core/router/app_router.dart';
import 'features/notifications/data/notification_push_service.dart';
import 'ui/foundation/app_font_tokens.dart';

Future<void> _initializeDeferredServices() async {
  try {
    await Firebase.initializeApp();
    await NotificationPushService.instance.initialize();
  } catch (error, stack) {
    debugPrint('Firebase init skipped: $error');
    debugPrint('$stack');
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize date formatting for Indonesian locale
  await initializeDateFormatting('id_ID', null);

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://ytslgrlieofvvfstwqfk.supabase.co',
    anonKey:
        'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inl0c2xncmxpZW9mdnZmc3R3cWZrIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg0NTcxMTEsImV4cCI6MjA4NDAzMzExMX0.mBXSav9eGhsQxcoq_wHzvy40GKe5Patns-fZcoF8-x0',
  );

  // Catch Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
    debugPrint('Stack trace: ${details.stack}');
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('Unhandled async error: $error');
    debugPrint('Unhandled async stack: $stack');
    return true;
  };

  runApp(const ProviderScope(child: VTrackApp()));
  unawaited(_initializeDeferredServices());
}

// Global Supabase client accessor - SAFE: only accessed after Supabase.initialize()
SupabaseClient get supabase => Supabase.instance.client;

class VTrackApp extends ConsumerStatefulWidget {
  const VTrackApp({super.key});

  @override
  ConsumerState<VTrackApp> createState() => _VTrackAppState();
}

class _VTrackAppState extends ConsumerState<VTrackApp> {
  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final fontPreference = ref.watch(appFontPreferenceProvider);
    AppFontTokens.setPreference(fontPreference);

    return MaterialApp.router(
      title: 'VTrack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeMode,

      // Localization Setup
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('id', 'ID'), Locale('en', 'US')],

      routerConfig: router,
    );
  }
}
