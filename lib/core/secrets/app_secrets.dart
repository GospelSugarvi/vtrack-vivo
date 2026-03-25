class AppSecrets {
  static String get geminiApiKey {
    const value = String.fromEnvironment('GEMINI_API_KEY');
    if (value.isEmpty) {
      throw StateError(
        'GEMINI_API_KEY belum diset. Jalankan app dengan '
        '--dart-define=GEMINI_API_KEY=...',
      );
    }
    return value;
  }
}
