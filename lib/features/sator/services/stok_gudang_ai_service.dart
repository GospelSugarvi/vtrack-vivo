import 'dart:convert';
import 'dart:typed_data';

import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:vtrack/core/secrets/app_secrets.dart';

class StokGudangAIService {
  static const String _modelName = 'gemini-2.5-flash';

  Future<List<Map<String, dynamic>>> parseStockImage(
    List<int> imageBytes,
    String mimeType, {
    required List<Map<String, dynamic>> catalog,
  }) async {
    final bytes = Uint8List.fromList(imageBytes);
    if (bytes.isEmpty) {
      return <Map<String, dynamic>>[];
    }
    if (catalog.isEmpty) {
      throw Exception('Katalog produk aktif tidak tersedia.');
    }

    final model = GenerativeModel(
      model: _modelName,
      apiKey: AppSecrets.geminiApiKey,
      generationConfig: GenerationConfig(
        temperature: 0.1,
        responseMimeType: 'application/json',
      ),
    );

    final prompt =
        '''
Kamu membaca foto stok gudang handphone vivo.

Tugas:
1. Baca isi gambar dan identifikasi produk/varian/warna beserta jumlah stok.
2. Gunakan HANYA katalog berikut untuk memilih varian yang paling cocok.
3. Jika baris pada gambar tidak jelas atau tidak yakin, abaikan.
4. Jumlah stok harus integer >= 0.
5. Jangan mengarang item yang tidak terlihat pada gambar.

Katalog varian aktif:
${jsonEncode(catalog)}

Kembalikan JSON dengan format:
{
  "items": [
    {
      "variant_id": "uuid dari katalog",
      "qty": 12,
      "product_name": "V60",
      "network_type": "5G",
      "variant": "8/256",
      "color": "BLUE",
      "confidence": 0.92
    }
  ]
}
''';

    final response = await model.generateContent([
      Content.multi([TextPart(prompt), DataPart(mimeType, bytes)]),
    ]);

    final rawText = response.text?.trim() ?? '';
    if (rawText.isEmpty) {
      return <Map<String, dynamic>>[];
    }

    final decoded = jsonDecode(_extractJson(rawText));
    final items = decoded is Map<String, dynamic>
        ? decoded['items']
        : (decoded is List ? decoded : null);

    if (items is! List) {
      return <Map<String, dynamic>>[];
    }

    return items
        .whereType<dynamic>()
        .map<Map<String, dynamic>>((item) {
          final map = item is Map<String, dynamic>
              ? item
              : Map<String, dynamic>.from(item as Map);
          return {
            'variant_id': '${map['variant_id'] ?? ''}',
            'qty': _toInt(map['qty']),
            'product_name': '${map['product_name'] ?? ''}',
            'network_type': '${map['network_type'] ?? ''}',
            'variant': '${map['variant'] ?? ''}',
            'color': '${map['color'] ?? ''}',
            'confidence': _toDouble(map['confidence']),
          };
        })
        .where((item) => item['variant_id'].toString().isNotEmpty)
        .toList();
  }

  String _extractJson(String raw) {
    final fenced = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      multiLine: true,
    ).firstMatch(raw);
    if (fenced != null) {
      return fenced.group(1)?.trim() ?? raw;
    }
    return raw;
  }

  int _toInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  double _toDouble(dynamic value) {
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? 0;
  }
}
