// Script to list available Gemini models
import 'dart:io';
import 'lib/core/secrets/app_secrets.dart';

void main() async {
  final apiKey = AppSecrets.geminiApiKey;

  // Create a model client (temporary, just to access listModels if exposed,
  // but unfortunately google_generative_ai SDK doesn't expose listModels directly easily in main class)
  // We will try to fetch it via HTTP raw request because SDK might hide it.

  stdout.writeln('Checking available models for configured Gemini API key...');

  // Using raw HTTP because SDK is high-level
  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
  );
  final client = HttpClient();

  try {
    final request = await client.getUrl(url);
    final response = await request.close();

    if (response.statusCode == 200) {
      final body = await response.transform(SystemEncoding().decoder).join();
      stdout.writeln('\n----- AVAILABLE MODELS -----\n');
      stdout.writeln(body);
      stdout.writeln('\n---------------------------\n');
    } else {
      stdout.writeln('Failed to list models. Status: ${response.statusCode}');
      final body = await response.transform(SystemEncoding().decoder).join();
      stdout.writeln('Response: $body');
    }
  } catch (e) {
    stdout.writeln('Error: $e');
  } finally {
    client.close();
  }
}
