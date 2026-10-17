import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_settings.dart';
import 'media_downloader.dart';

/// Resolves links through VidSave's Flask API and polls its asynchronous jobs.
class BackendMediaResolver implements MediaResolver {
  BackendMediaResolver({
    required this.settingsStore,
    http.Client? client,
    this.pollInterval = const Duration(seconds: 1),
    this.maxWait = const Duration(minutes: 30),
    Future<void> Function(Duration)? delay,
  }) : _client = client ?? http.Client(),
       _delay = delay ?? Future<void>.delayed;

  final BackendSettingsStore settingsStore;
  final http.Client _client;
  final Duration pollInterval;
  final Duration maxWait;
  final Future<void> Function(Duration) _delay;

  @override
  Future<ResolvedMedia> resolve(
    Uri source,
    DownloadKind kind, {
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    final settings = await settingsStore.load();
    if (!settings.isConfigured) {
      throw const MediaResolverException(
        'Önce Ayarlar sekmesinden backend adresini ayarlayın.',
      );
    }

    final baseUri = settings.baseUri;
    // The text box may hold either a real URL or a plain search phrase. We only
    // reject genuinely empty input; the backend decides how to interpret it.
    final rawInput = _rawInput(source);
    if (rawInput.isEmpty) {
      throw const MediaResolverException(
        'İndirilecek bağlantı veya arama kelimesi girin.',
      );
    }

    final stopwatch = Stopwatch()..start();
    var payload = await _resolveRequest(
      baseUri: baseUri,
      settings: settings,
      rawInput: rawInput,
      kind: kind,
      height: height,
      startTime: startTime,
      endTime: endTime,
      audioEffect: audioEffect,
    );

    while (true) {
      final status = (payload['status'] as String? ?? '').toLowerCase();
      if (status == 'error') {
        throw MediaResolverException(
          _errorMessage(payload) ?? 'İndirme işi başarısız oldu.',
        );
      }
      if (status == 'ready') {
        return _resolvedMedia(payload, baseUri, settings);
      }
      if (status != 'pending' && status != 'running') {
        throw const MediaResolverException(
          'Backend beklenmeyen bir yanıt döndürdü.',
        );
      }

      final jobId = payload['job'] as String?;
      if (jobId == null || jobId.isEmpty) {
        throw const MediaResolverException(
          'Backend işi izlemek için job kimliği döndürmedi. Backend’i güncelleyin.',
        );
      }
      if (stopwatch.elapsed >= maxWait) {
        throw const MediaResolverException('İşlem zaman aşımına uğradı.');
      }

      await _delay(pollInterval);
      payload = await _resolveRequest(
        baseUri: baseUri,
        settings: settings,
        rawInput: rawInput,
        kind: kind,
        height: height,
        jobId: jobId,
        startTime: startTime,
        endTime: endTime,
        audioEffect: audioEffect,
      );
    }
  }

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    final settings = await settingsStore.load();
    if (!settings.isConfigured) {
      throw const MediaResolverException(
        'Önce Ayarlar sekmesinden backend adresini ayarlayın.',
      );
    }

    final baseUri = settings.baseUri;
    final rawInput = _rawInput(source);
    if (rawInput.isEmpty) {
      throw const MediaResolverException(
        'İndirilecek bağlantı veya arama kelimesi girin.',
      );
    }

    // info:true makes the backend probe the link and list its resolutions.
    final payload = await _resolveRequest(
      baseUri: baseUri,
      settings: settings,
      rawInput: rawInput,
      kind: kind,
      info: true,
    );

    final status = (payload['status'] as String? ?? '').toLowerCase();
    if (status == 'error') {
      throw MediaResolverException(
        _errorMessage(payload) ?? 'Bağlantı çözümlenemedi.',
      );
    }
    if (status != 'info') {
      throw const MediaResolverException(
        'Backend önizleme bilgisini döndürmedi. Backend’i güncelleyin.',
      );
    }

    final qualities = <VideoQuality>[];
    final rawQualities = payload['qualities'];
    if (rawQualities is List) {
      for (final entry in rawQualities) {
        if (entry is! Map) continue;
        final heightValue = entry['height'];
        if (heightValue is! num) continue;
        final sizeValue = entry['sizeInBytes'];
        qualities.add(
          VideoQuality(
            height: heightValue.toInt(),
            label: (entry['label'] as String?) ?? '${heightValue.toInt()}p',
            sizeInBytes: sizeValue is num ? sizeValue.toInt() : null,
          ),
        );
      }
    }

    final durationValue = payload['duration'];
    return MediaPreview(
      title: (payload['title'] as String?) ?? '',
      duration: durationValue is num && durationValue > 0
          ? Duration(seconds: durationValue.round())
          : null,
      uploader: payload['uploader'] as String?,
      qualities: qualities,
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async {
    final settings = await settingsStore.load();
    if (!settings.isConfigured) {
      throw const MediaResolverException(
        'Önce Ayarlar sekmesinden backend adresini ayarlayın.',
      );
    }

    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    final response = await _client
        .post(
          settings.baseUri.resolve('/api/ara'),
          headers: {
            ..._headers(settings),
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode({'query': trimmed}),
        )
        .timeout(const Duration(seconds: 35));

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode >= 200 && response.statusCode < 300 && decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(SearchResultItem.fromJson)
          .toList();
    }
    if (decoded is List) {
      return decoded
          .map((e) => SearchResultItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    }
    return const [];
  }

  /// The user's raw text box contents, un-encoded.
  ///
  /// A real URL keeps its scheme/host; a plain search phrase arrives as a
  /// scheme-less [Uri] (built via `Uri(path:)`) whose `path` is the phrase.
  String _rawInput(Uri source) {
    final isUrl =
        (source.isScheme('http') || source.isScheme('https')) &&
        source.host.isNotEmpty;
    return isUrl ? source.toString() : source.path.trim();
  }

  /// Verifies the saved or unsaved settings against `/api/health`.
  Future<void> testConnection({BackendSettings? settings}) async {
    final configuration = settings ?? await settingsStore.load();
    if (!configuration.isConfigured) {
      throw const MediaResolverException('Önce backend adresini girin.');
    }

    final response = await _client
        .get(
          configuration.baseUri.resolve('/api/health'),
          headers: _headers(configuration),
        )
        .timeout(const Duration(seconds: 10));
    final payload = _decodePayload(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MediaResolverException(
        _errorMessage(payload) ??
            'Backend yanıt vermedi (HTTP ${response.statusCode}).',
      );
    }
    if (payload['status'] != 'ok') {
      throw const MediaResolverException('Bu adres VidSave backend’i değil.');
    }
    if (payload['authRequired'] == true && configuration.apiKey.isEmpty) {
      throw const MediaResolverException(
        'Backend API anahtarı istiyor. Anahtarı girip tekrar deneyin.',
      );
    }
  }

  Future<Map<String, dynamic>> _resolveRequest({
    required Uri baseUri,
    required BackendSettings settings,
    required String rawInput,
    required DownloadKind kind,
    String? jobId,
    int? height,
    bool info = false,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    final body = <String, Object?>{
      'url': rawInput,
      'kind': kind == DownloadKind.audio ? 'audio' : 'video',
      'job': ?jobId,
      'height': ?height,
      if (info) 'info': true,
      'start_time': ?startTime,
      'end_time': ?endTime,
      if (audioEffect != null && audioEffect.isNotEmpty) 'audio_effect': audioEffect,
    };
    final response = await _client
        .post(
          baseUri.resolve('/api/resolve'),
          headers: {
            ..._headers(settings),
            'Content-Type': 'application/json',
            'Accept': 'application/json',
          },
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30));

    final payload = _decodePayload(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MediaResolverException(
        _errorMessage(payload) ??
            'Backend isteği başarısız oldu (HTTP ${response.statusCode}).',
      );
    }
    return payload;
  }

  ResolvedMedia _resolvedMedia(
    Map<String, dynamic> payload,
    Uri baseUri,
    BackendSettings settings,
  ) {
    final route = payload['url'];
    if (route is! String || route.isEmpty) {
      throw const MediaResolverException('Backend indirme adresi döndürmedi.');
    }
    final parsedRoute = Uri.tryParse(route);
    if (parsedRoute == null) {
      throw const MediaResolverException(
        'Backend geçersiz indirme adresi döndürdü.',
      );
    }
    final downloadUri = parsedRoute.hasScheme
        ? parsedRoute
        : baseUri.resolveUri(parsedRoute);
    if (downloadUri.origin != baseUri.origin ||
        downloadUri.path != '/download') {
      throw const MediaResolverException(
        'Backend güvenilmeyen indirme adresi döndürdü.',
      );
    }

    final fileName = payload['filename'] as String? ?? 'vidsave_media.mp4';
    final sizeValue = payload['fileSizeInBytes'];
    final fileSize = sizeValue is num ? sizeValue.toInt() : null;
    final apiKey = settings.apiKey;
    return ResolvedMedia(
      url: downloadUri,
      fileName: fileName,
      mimeType: payload['mime'] as String?,
      fileSizeInBytes: fileSize,
      downloadHeaders: apiKey.isEmpty ? const {} : {'X-Api-Key': apiKey},
    );
  }

  Map<String, String> _headers(BackendSettings settings) => {
    'Accept': 'application/json',
    'User-Agent': 'VidSave/1.0',
    if (settings.apiKey.isNotEmpty) 'X-Api-Key': settings.apiKey,
  };

  Map<String, dynamic> _decodePayload(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      // Report the HTTP status below when a server returns non-JSON errors.
    }
    return const {};
  }

  String? _errorMessage(Map<String, dynamic> payload) {
    final error = payload['error'];
    if (error is String && error.isNotEmpty) return error;
    if (error is! Map) return null;
    final code = error['code'];
    if (code is! String) return null;
    return switch (code) {
      'unauthorized' => 'Backend API anahtarı geçersiz veya eksik.',
      'url.missing' => 'İndirilecek bağlantı veya arama kelimesi girilmedi.',
      'url.invalid' => 'Backend bu bağlantı hedefine izin vermiyor.',
      'quality.invalid' => 'Seçilen çözünürlük geçersiz.',
      'search.no_results' => 'Arama için sonuç bulunamadı, başka kelimeler deneyin.',
      'job.not_found' => 'İndirme işi bulunamadı.',
      'job.not_ready' => 'İndirme işi henüz hazır değil.',
      'download.too_large' => 'Dosya backend boyut sınırını aşıyor.',
      'download.upstream_error' => 'Kaynak sunucudan indirme başarısız oldu.',
      _ => 'Backend hatası: $code',
    };
  }
}
