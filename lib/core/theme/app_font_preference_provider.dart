import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../ui/foundation/app_font_tokens.dart';

final appFontPreferenceProvider =
    NotifierProvider<AppFontPreferenceNotifier, AppFontPreference>(
      AppFontPreferenceNotifier.new,
    );

class AppFontPreferenceNotifier extends Notifier<AppFontPreference> {
  static const _storageKey = 'app_font_preference';

  @override
  AppFontPreference build() {
    _load();
    AppFontTokens.setPreference(AppFontPreference.outfit);
    return AppFontPreference.outfit;
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    if (raw == null) return;
    final preference = _fromString(raw);
    AppFontTokens.setPreference(preference);
    state = preference;
  }

  Future<void> setPreference(AppFontPreference preference) async {
    AppFontTokens.setPreference(preference);
    state = preference;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, _toString(preference));
  }

  static String _toString(AppFontPreference preference) {
    switch (preference) {
      case AppFontPreference.outfit:
        return 'outfit';
      case AppFontPreference.inter:
        return 'inter';
      case AppFontPreference.manrope:
        return 'manrope';
      case AppFontPreference.playfair:
        return 'playfair';
      case AppFontPreference.jetbrainsMono:
        return 'jetbrains_mono';
    }
  }

  static AppFontPreference _fromString(String value) {
    switch (value) {
      case 'inter':
        return AppFontPreference.inter;
      case 'manrope':
        return AppFontPreference.manrope;
      case 'playfair':
        return AppFontPreference.playfair;
      case 'jetbrains_mono':
        return AppFontPreference.jetbrainsMono;
      default:
        return AppFontPreference.outfit;
    }
  }
}
