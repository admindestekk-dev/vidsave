import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_settings.dart';
import 'media_downloader.dart';

/// Toplu indirme işlemlerini ve URL ayrıştırma algoritmasını yöneten servis.
class BulkDownloadService {
  BulkDownloadService._();

  /// Çok satırlı metni satır satır bölerek (`split('\n')`), boşlukları temizleyen (`trim()`)
  /// ve sadece geçerli HTTP/HTTPS bağlantılarını içeren temiz bir URL listesi döndüren algoritma.
  static List<String> parseBulkUrls(String text) {
    if (text.trim().isEmpty) return [];

    return text
        .split(RegExp(r'\r?\n'))
        .map((line) => evrenselTemizUrl(line.trim()))
        .where(
          (line) =>
              line.isNotEmpty &&
              (line.startsWith('http://') || line.startsWith('https://')),
        )
        .toSet() // Mükerrer bağlantıları teke indir
        .toList();
  }

  /// Temizlenmiş URL listesini backend'deki `/api/toplu-indir` endpoint'ine
  /// POST isteği ile gönderen HTTP fonksiyonu.
  static Future<Map<String, dynamic>> sendBulkDownloadRequest({
    required List<String> urls,
    required DownloadKind kind,
    required BackendSettings settings,
    http.Client? client,
  }) async {
    final httpClient = client ?? http.Client();
    final uri = settings.baseUri.replace(path: '/api/toplu-indir');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (settings.apiKey.isNotEmpty) 'X-Api-Key': settings.apiKey,
    };

    final body = jsonEncode({
      'urls': urls,
      'kind': kind == DownloadKind.audio ? 'audio' : 'video',
    });

    try {
      final response = await httpClient.post(uri, headers: headers, body: body);
      if (response.statusCode != 200) {
        throw Exception(
          'Backend yanıt vermedi (${response.statusCode}): ${response.body}',
        );
      }
      return jsonDecode(response.body) as Map<String, dynamic>;
    } finally {
      if (client == null) {
        httpClient.close();
      }
    }
  }
}
