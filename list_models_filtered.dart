// Script to list available Gemini models (Filtered)
import 'dart:io';
import 'dart:convert';
import 'lib/core/secrets/app_secrets.dart';

void main() async {
  final apiKey = AppSecrets.geminiApiKey;
  stdout.writeln('Checking available GEMINI models...');

  final url = Uri.parse(
    'https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey',
  );
  final client = HttpClient();

  try {
    final request = await client.getUrl(url);
    final response = await request.close();

    if (response.statusCode == 200) {
      final body = await response.transform(SystemEncoding().decoder).join();
      final jsonBody = json.decode(body);
      final models = jsonBody['models'] as List;

      stdout.writeln('\n----- GEMINI MODELS -----\n');
      for (var m in models) {
        final name = m['name'].toString();
        if (name.toLowerCase().contains('gemini') &&
            name.toLowerCase().contains('flash')) {
          stdout.writeln(name);
        }
      }
      stdout.writeln('\n---------------------------\n');
    } else {
      stdout.writeln('Failed: ${response.statusCode}');
    }
  } catch (e) {
    stdout.writeln('Error: $e');
  } finally {
    client.close();
  }
}
