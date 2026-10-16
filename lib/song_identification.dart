import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'backend_settings.dart';

class SongIdentificationResult {
  const SongIdentificationResult({
    required this.title,
    required this.artist,
    this.album,
  });

  final String title;
  final String artist;
  final String? album;
}

class SongIdentificationException implements Exception {
  const SongIdentificationException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract interface class SongIdentificationService {
  Future<SongIdentificationResult?> identify(Uint8List wavSample);
}

/// Sends a short WAV sample to VidSave's backend; provider credentials remain
/// on the Flask server and are never sent by the app.
class BackendSongIdentificationService implements SongIdentificationService {
  BackendSongIdentificationService({
    required this.settingsStore,
    http.Client? client,
  }) : _client = client ?? http.Client();

  static const maxSampleBytes = 5 * 1024 * 1024;

  final BackendSettingsStore settingsStore;
  final http.Client _client;

  @override
  Future<SongIdentificationResult?> identify(Uint8List wavSample) async {
    if (wavSample.length < 44 ||
        wavSample.length > maxSampleBytes ||
        !_isWaveFile(wavSample)) {
      throw const SongIdentificationException(
        'Ses örneği geçersiz veya izin verilen boyutu aşıyor.',
      );
    }

    final settings = await settingsStore.load();
    if (!settings.isConfigured) {
      throw const SongIdentificationException(
        'Önce Ayarlar sekmesinden backend adresini ayarlayın.',
      );
    }

    final request = http.MultipartRequest(
      'POST',
      settings.baseUri.resolve('/api/identify'),
    )
      ..headers.addAll({
        'Accept': 'application/json',
        'User-Agent': 'VidSave/1.0',
        if (settings.apiKey.isNotEmpty) 'X-Api-Key': settings.apiKey,
      })
      ..files.add(
        http.MultipartFile.fromBytes(
          'sample',
          wavSample,
          filename: 'vidsave-sample.wav',
        ),
      );

    final streamed = await _client.send(request).timeout(
      const Duration(seconds: 30),
    );
    final response = await http.Response.fromStream(streamed);
    final payload = _decodePayload(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SongIdentificationException(
        _errorFor(payload, response.statusCode),
      );
    }

    if (payload['status'] == 'no_match') return null;
    if (payload['status'] != 'matched') {
      throw const SongIdentificationException(
        'Backend beklenmeyen bir yanıt döndürdü.',
      );
    }

    final result = payload['result'];
    if (result is! Map) {
      throw const SongIdentificationException(
        'Backend eşleşme bilgisi döndürmedi.',
      );
    }
    final title = result['title'];
    final artist = result['artist'];
    if (title is! String || title.isEmpty || artist is! String || artist.isEmpty) {
      throw const SongIdentificationException(
        'Backend eksik şarkı bilgisi döndürdü.',
      );
    }

    return SongIdentificationResult(
      title: title,
      artist: artist,
      album: result['album'] as String?,
    );
  }

  bool _isWaveFile(Uint8List sample) =>
      sample[0] == 0x52 &&
      sample[1] == 0x49 &&
      sample[2] == 0x46 &&
      sample[3] == 0x46 &&
      sample[8] == 0x57 &&
      sample[9] == 0x41 &&
      sample[10] == 0x56 &&
      sample[11] == 0x45;

  Map<String, dynamic> _decodePayload(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // The generic HTTP error below is sufficient for non-JSON responses.
    }
    return const {};
  }

  String _errorFor(Map<String, dynamic> payload, int statusCode) {
    final error = payload['error'];
    final code = error is Map ? error['code'] : null;
    return switch (code) {
      'unauthorized' => 'Backend API anahtarı geçersiz veya eksik.',
      'recognition.not_configured' =>
        'Şarkı tanıma servisi backend üzerinde yapılandırılmalı.',
      'recognition.too_large' => 'Ses örneği izin verilen boyutu aşıyor.',
      'recognition.invalid_audio' => 'Ses örneği geçerli WAV biçiminde değil.',
      'recognition.upstream_error' =>
        'Şarkı tanıma servisi şu anda yanıt vermiyor.',
      _ => 'Şarkı tanıma isteği başarısız oldu (HTTP $statusCode).',
    };
  }
}
