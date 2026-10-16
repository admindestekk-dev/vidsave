import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

/// Turns a social-media URL into a direct, downloadable media URL.
///
/// Implementations throw [MediaResolverException] when the link is unsupported
/// or the upstream service does not return a usable media URL.
abstract class MediaResolver {
  /// [height] pins the requested video resolution in pixels (480/720/...);
  /// null lets the backend pick its usual best quality.
  Future<ResolvedMedia> resolve(Uri source, DownloadKind kind, {int? height});

  /// Probes the link without downloading anything, so the UI can show the
  /// title and the resolutions the user may pick from.
  Future<MediaPreview> preview(Uri source, DownloadKind kind);

  /// Searches the backend for items matching [query].
  Future<List<SearchResultItem>> search(String query);
}

/// Whether we want the original video or an extracted audio track.
enum DownloadKind { video, audio }

/// One selectable resolution of a previewed link.
class VideoQuality {
  const VideoQuality({
    required this.height,
    required this.label,
    this.sizeInBytes,
  });

  /// Vertical resolution in pixels; 0 marks the "best available" entry.
  final int height;
  final String label;
  final int? sizeInBytes;

  bool get isBest => height <= 0;
}

/// Metadata for a link the user pasted, before anything is downloaded.
class MediaPreview {
  const MediaPreview({
    required this.title,
    this.duration,
    this.uploader,
    this.qualities = const [],
  });

  final String title;
  final Duration? duration;
  final String? uploader;

  /// Video resolutions offered by the source, tallest first.
  final List<VideoQuality> qualities;
}

/// A search item returned by music/video search endpoints.
class SearchResultItem {
  const SearchResultItem({
    required this.id,
    required this.baslik,
    required this.kanal,
    required this.sure,
    required this.url,
  });

  final String id;
  final String baslik;
  final String kanal;
  final String sure;
  final String url;

  factory SearchResultItem.fromJson(Map<String, dynamic> json) {
    return SearchResultItem(
      id: (json['id'] as String?) ?? '',
      baslik: (json['baslik'] as String?) ?? (json['title'] as String?) ?? 'Bilinmeyen Başlık',
      kanal: (json['kanal'] as String?) ?? (json['channel'] as String?) ?? (json['uploader'] as String?) ?? '',
      sure: (json['sure'] as String?) ?? (json['duration'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
    );
  }
}

/// A resolved media URL plus a best-effort file name and mime type.
class ResolvedMedia {
  const ResolvedMedia({
    required this.url,
    required this.fileName,
    this.mimeType,
    this.fileSizeInBytes,
    this.downloadHeaders = const {},
  });

  final Uri url;
  final String fileName;
  final String? mimeType;
  final int? fileSizeInBytes;
  final Map<String, String> downloadHeaders;
}

/// Thrown when a link cannot be resolved into a downloadable media URL.
class MediaResolverException implements Exception {
  const MediaResolverException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Thrown when the resolved media URL cannot be downloaded to disk.
class MediaDownloadException implements Exception {
  const MediaDownloadException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Progress callback fired while bytes stream to disk.
/// [totalBytes] is null when the server does not report a Content-Length.
typedef DownloadProgressCallback = void Function(
  int receivedBytes,
  int? totalBytes,
);

/// Best-effort registry of open-source downloader endpoints that expose a
/// simple JSON contract. Each entry returns a JSON body containing a direct
/// media URL, which we then download ourselves.
///
/// The contract expected from every endpoint is the same:
/// `{ "url": "https://.../video.mp4" }` (extra keys such as `title` or
/// `filename` are used as a nicer file name when present).
///
/// Note: Cobalt v10+ moved its API from `/api/json` to the server root `/`
/// (see github.com/imputnet/cobalt). The old `/api/json` path now answers with
/// 404/redirects, so we POST to the root.
///
/// IMPORTANT: the hosted instance `api.cobalt.tools` uses bot protection and
/// now requires authentication. A request without credentials is answered with
/// `{"status":"error","error":{"code":"error.api.auth.jwt.missing"}}`.
/// The upstream maintainers explicitly ask that their public instance NOT be
/// used from third-party apps — you must either self-host an instance or ask
/// the instance owner for an API key, then pass it via [RemoteMediaResolver.apiKey].
final List<Uri> _kResolverEndpoints = [
  // Self-hosted Cobalt instance — put YOUR server first for production.
  // Run one in ~2 minutes with Docker:
  //   docker run -p 9000:9000 ghcr.io/imputnet/cobalt:latest
  // then use Uri.parse('http://<your-host>:9000/') here.
  // Public instance — only works if the owner has granted you an API key.
  Uri.parse('https://api.cobalt.tools/'),
];

/// Sent on every request so the upstream does not treat us as a bot.
/// A realistic, desktop-browser UA dramatically reduces 403 responses.
const String _kDefaultUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// Default [MediaResolver]: posts the pasted link to the endpoints above and
/// reads back the first direct media URL found in the JSON response.
///
/// It intentionally fails fast with a clear Turkish message instead of
/// pretending to download when every endpoint is unreachable.
class RemoteMediaResolver implements MediaResolver {
  RemoteMediaResolver({
    http.Client? client,
    List<Uri>? endpoints,
    this.userAgent = _kDefaultUserAgent,
    this.apiKey,
  }) : _client = client ?? http.Client(),
       _endpoints = endpoints ?? _kResolverEndpoints;

  final http.Client _client;
  final List<Uri> _endpoints;

  /// Overridable so callers can swap in a custom or rotated browser UA.
  final String userAgent;

  /// Optional Cobalt `Api-Key` credential. When set it is sent as
  /// `Authorization: Api-Key <key>`, which satisfies instances that enforce
  /// API-key authentication (the error code `error.api.auth.key.missing`
  /// otherwise). Get one from the owner of the instance you point at.
  final String? apiKey;

  /// Headers that mimic a real browser tab, which is what keeps bot-protected
  /// gateways from returning 403 Forbidden.
  Map<String, String> _browserHeaders(Uri endpoint) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'User-Agent': userAgent,
    'Origin': '${endpoint.scheme}://${endpoint.host}',
    'Referer': '${endpoint.scheme}://${endpoint.host}/',
    'Accept-Language': 'tr-TR,tr;q=0.9,en;q=0.8',
    if (apiKey != null && apiKey!.isNotEmpty)
      'Authorization': 'Api-Key $apiKey',
  };

  /// Maps Cobalt's `{ "status": "error", "error": { "code": "..." } }`
  /// payload to a clear Turkish message. Returns null when the payload is a
  /// success response (or is not JSON at all).
  String? _cobaltErrorMessage(Object? payload) {
    if (payload is! Map) return null;
    final status = payload['status'];
    if (status is String && status.toLowerCase() != 'error') return null;

    final error = payload['error'];
    final code = error is Map ? (error['code'] as Object?) : null;
    final codeText = code is String ? code.toLowerCase() : '';

    if (codeText.isEmpty) {
      // No structured error but also no media URL: let the caller try anyway.
      return null;
    }

    return switch (codeText) {
      'error.api.auth.key.missing' =>
        'Bu sunucu bir Cobalt API anahtarı istiyor (Api-Key).',
      'error.api.auth.jwt.missing' =>
        'Bu Cobalt sunucusu kimlik doğrulaması istiyor. Kendi sunucunuzu '
            'çalıştırın veya sunucu sahibinden API anahtarı alın.',
      'error.api.auth.jwt.invalid' => 'Kimlik doğrulama anahtarı geçersiz.',
      'error.api.link.invalid' => 'Bu bağlantı desteklenmiyor.',
      'error.api.link.unsupported' => 'Bu servis şu anda desteklenmiyor.',
      'error.api.link.private' => 'Bu içerik gizli olduğu için indirilemiyor.',
      'error.api.link.age' => 'Yaş kısıtlaması olan içerik indirilemiyor.',
      'error.api.link.region' => 'Bu içerik bölgenizde kullanılamıyor.',
      'error.api.fetch.empty' => 'Servis boş bir yanıt döndürdü.',
      'error.api.fetch.rate' => 'Çok fazla istek gönderildi, biraz bekleyin.',
      'error.api.fetch.critical' => 'İndirme servisi şu anda yanıt vermiyor.',
      'error.api.fetch.fail' => 'İçerik sunucudan alınamadı.',
      'error.api.content.too_long' => 'İçerik izin verilen süreden daha uzun.',
      'error.api.content.video_only' =>
        'Bu içerik yalnızca video olarak indirilebiliyor.',
      'error.api.content.audio_only' =>
        'Bu içerik yalnızca ses olarak indirilebiliyor.',
      'error.api.content.video_unavailable' =>
        'Bu içerik için video akışı bulunamadı.',
      'error.api.content.audio_unavailable' =>
        'Bu içerik için ses akışı bulunamadı.',
      'error.api.youtube.login' =>
        'YouTube bu isteği engelledi (bot koruması).',
      'error.api.youtube.token' => 'YouTube kimlik doğrulaması başarısız oldu.',
      'error.api.unknown' => 'Bilinmeyen bir hata oluştu.',
      _ => 'Servis hatası: $codeText',
    };
  }

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    // Cobalt has no metadata endpoint, so there is nothing to preview here:
    // the caller falls back to downloading directly at the default quality.
    throw const MediaResolverException(
      'Bu servis önizleme desteklemiyor; indirme doğrudan başlayacak.',
    );
  }

  @override
  Future<List<SearchResultItem>> search(String query) async => const [];

  @override
  Future<ResolvedMedia> resolve(
    Uri source,
    DownloadKind kind, {
    int? height,
  }) async {
    final errors = <String>[];
    for (final endpoint in _endpoints) {
      try {
        final response = await _client
            .post(
              endpoint,
              headers: _browserHeaders(endpoint),
              body: jsonEncode({
                'url': source.toString(),
                'videoQuality':
                    '${height ?? (kind == DownloadKind.audio ? 720 : 1080)}',
                'audioFormat': 'mp3',
                'downloadMode': kind == DownloadKind.audio ? 'audio' : 'auto',
                'filenameStyle': 'basic',
              }),
            )
            .timeout(const Duration(seconds: 25));

        // Cobalt replies 200 for success, 400 for a bad request, and 403 when
        // a bot check blocks us. Parse the JSON first, because even error
        // replies carry a helpful `error.code` we want to surface.
        final payload = _decodeJson(response.body);
        final cobaltError = _cobaltErrorMessage(payload);

        if (response.statusCode < 200 || response.statusCode >= 300) {
          errors.add(
            '${endpoint.host} → ${cobaltError ?? 'HTTP ${response.statusCode}'}',
          );
          continue;
        }
        if (cobaltError != null) {
          errors.add('${endpoint.host} → $cobaltError');
          continue;
        }

        final mediaUrl = _firstMediaUrl(payload);
        if (mediaUrl == null) {
          errors.add('${endpoint.host} → medya bağlantısı bulunamadı');
          continue;
        }

        final resolvedUri = Uri.tryParse(mediaUrl);
        if (resolvedUri == null || !resolvedUri.hasScheme) {
          errors.add('${endpoint.host} → geçersiz medya bağlantısı');
          continue;
        }

        return ResolvedMedia(
          url: resolvedUri,
          fileName: _pickFileName(
            payload: payload,
            url: resolvedUri,
            source: source,
            kind: kind,
          ),
          mimeType: _findString(payload, const [
            'mimeType',
            'mimetype',
            'type',
          ]),
        );
      } on TimeoutException {
        errors.add('${endpoint.host} → zaman aşımı');
      } catch (error) {
        errors.add('${endpoint.host} → $error');
      }
    }

    throw MediaResolverException(
      'Bağlantı çözümlenemedi. Desteklenen bir video/müzik linki deneyin.\n'
      '${errors.join('\n')}',
    );
  }

  Object? _decodeJson(String body) {
    final trimmed = body.trim();
    if (trimmed.isEmpty) return null;
    try {
      return jsonDecode(trimmed);
    } on FormatException {
      // Some endpoints reply with a plain-text URL instead of JSON.
      if (trimmed.startsWith('http')) return {'url': trimmed};
      rethrow;
    }
  }

  /// Walks the decoded JSON looking for the first absolute http(s) URL, while
  /// preferring well-known keys so we do not accidentally grab a thumbnail.
  String? _firstMediaUrl(Object? payload) {
    for (final key in const [
      'url',
      'link',
      'download',
      'downloadUrl',
      'download_url',
      'video',
      'audio',
      'media',
      'file',
      'fileUrl',
    ]) {
      final value = _findString(payload, [key]);
      if (value != null && _looksLikeMediaUrl(value)) return value;
    }
    return _deepFirstMediaUrl(payload, 0);
  }

  String? _deepFirstMediaUrl(Object? node, int depth) {
    if (depth > 6 || node == null) return null;
    if (node is String) {
      return _looksLikeMediaUrl(node) ? node : null;
    }
    if (node is List) {
      for (final item in node) {
        final found = _deepFirstMediaUrl(item, depth + 1);
        if (found != null) return found;
      }
      return null;
    }
    if (node is Map) {
      for (final value in node.values) {
        final found = _deepFirstMediaUrl(value, depth + 1);
        if (found != null) return found;
      }
    }
    return null;
  }

  bool _looksLikeMediaUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      return false;
    }
    final path = uri.path.toLowerCase();
    return path.endsWith('.mp4') ||
        path.endsWith('.m4a') ||
        path.endsWith('.mp3') ||
        path.endsWith('.webm') ||
        path.endsWith('.mov') ||
        path.endsWith('.aac') ||
        path.endsWith('.opus') ||
        value.contains('googlevideo') ||
        value.contains('video') ||
        value.contains('audio');
  }

  String? _findString(Object? node, List<String> keys) {
    if (node is! Map) return null;
    for (final key in keys) {
      final value = node[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  String _pickFileName({
    required Object? payload,
    required Uri url,
    required Uri source,
    required DownloadKind kind,
  }) {
    final fromPayload = _findString(payload, const [
      'filename',
      'fileName',
      'file_name',
      'title',
      'name',
    ]);
    final base = _sanitizeFileName(
      fromPayload ?? _fileNameFromUrl(url) ?? _fileNameFromUrl(source) ?? '',
    );
    final trimmed = _stripExtension(base);
    final fallback = trimmed.isEmpty
        ? 'vidsave_${DateTime.now().millisecondsSinceEpoch}'
        : trimmed;
    final extension = _extensionFor(
      fromPayload: fromPayload,
      url: url,
      kind: kind,
    );
    return '$fallback$extension';
  }

  String _extensionFor({
    required String? fromPayload,
    required Uri url,
    required DownloadKind kind,
  }) {
    final candidates = <String?>[fromPayload, _fileNameFromUrl(url)];
    for (final candidate in candidates) {
      final extension = _extensionOf(candidate);
      if (extension != null && _allowedExtensions.contains(extension)) {
        return '.$extension';
      }
    }
    return kind == DownloadKind.audio ? '.m4a' : '.mp4';
  }

  String? _fileNameFromUrl(Uri? uri) {
    if (uri == null || uri.pathSegments.isEmpty) return null;
    final last = uri.pathSegments.last;
    return last.isEmpty ? null : last;
  }

  String _sanitizeFileName(String value) {
    final decoded = Uri.decodeComponent(value);
    return decoded.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), '_').trim();
  }

  String _stripExtension(String value) {
    final dot = value.lastIndexOf('.');
    if (dot <= 0) return value;
    final extension = value.substring(dot + 1).toLowerCase();
    if (_allowedExtensions.contains(extension)) {
      return value.substring(0, dot);
    }
    return value;
  }

  String? _extensionOf(String? value) {
    if (value == null) return null;
    final withoutQuery = value.split('?').first.split('#').first;
    final dot = withoutQuery.lastIndexOf('.');
    if (dot < 0 || dot == withoutQuery.length - 1) return null;
    return withoutQuery.substring(dot + 1).toLowerCase();
  }

  static const _allowedExtensions = {
    'mp4',
    'm4a',
    'mp3',
    'webm',
    'mov',
    'aac',
    'opus',
  };
}

/// Downloads [media] into the device's public `Download` folder while reporting
/// byte-level progress, so the UI can show "indiriliyor… %42".
class MediaDownloader {
  MediaDownloader({
    http.Client? client,
    Future<Directory> Function()? directoryProvider,
  }) : _client = client ?? http.Client(),
       _directoryProvider = directoryProvider ?? _defaultDownloadDirectory;

  final http.Client _client;
  final Future<Directory> Function() _directoryProvider;

  /// How long the server may take to accept the connection and send its
  /// response headers. The backend only starts streaming after yt-dlp has
  /// produced the file, so this has to be generous: a 30s cap made healthy
  /// downloads fail on slow links with a raw English `TimeoutException`.
  static const _connectTimeout = Duration(minutes: 2);

  /// Streams the file to disk. [onProgress] is called repeatedly with the
  /// number of received bytes and the total size when known.
  Future<File> download(
    ResolvedMedia media, {
    DownloadProgressCallback? onProgress,
    Duration timeout = const Duration(minutes: 30),
  }) async {
    final request = http.Request('GET', media.url);
    request.headers.addAll({
      'User-Agent': 'VidSave/1.0',
      'Accept': '*/*',
      ...media.downloadHeaders,
    });
    final http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(_connectTimeout);
    } on TimeoutException {
      throw const MediaDownloadException(
        'Sunucu yanıt vermedi. Backend açık mı ve bu cihazdan erişilebilir mi '
        'kontrol edin, sonra tekrar deneyin.',
      );
    } on http.ClientException catch (error) {
      throw MediaDownloadException(
        'Backend’e bağlanılamadı. Adresi ve ağ bağlantınızı kontrol edin ($error).',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final message = switch (response.statusCode) {
        401 => 'Backend API anahtarı geçersiz veya eksik.',
        403 => 'Backend indirme isteğine izin vermedi.',
        404 => 'İndirme işi bulunamadı veya süresi doldu.',
        409 => 'İndirme işi henüz hazır değil.',
        413 => 'Dosya backend boyut sınırını aşıyor.',
        _ => 'Medya indirilemedi (HTTP ${response.statusCode}).',
      };
      throw MediaDownloadException(message);
    }

    final totalBytes = response.contentLength ?? media.fileSizeInBytes;
    final directory = await _directoryProvider();
    await directory.create(recursive: true);

    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '${_uniqueFileName(directory, media.fileName)}',
    );

    var received = 0;
    final sink = file.openWrite();
    try {
      await for (final chunk in response.stream.timeout(timeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, totalBytes);
      }
      await sink.flush();
    } on TimeoutException {
      await sink.close();
      if (await file.exists()) {
        await file.delete();
      }
      throw const MediaDownloadException(
        'İndirme sırasında bağlantı zaman aşımına uğradı. Ağınızı kontrol edip '
        'tekrar deneyin.',
      );
    } catch (error) {
      await sink.close();
      if (await file.exists()) {
        await file.delete();
      }
      throw MediaDownloadException('İndirme yarıda kaldı: $error');
    } finally {
      await sink.close();
    }

    if (received == 0) {
      if (await file.exists()) {
        await file.delete();
      }
      throw const MediaDownloadException('Sunucu boş bir dosya döndürdü.');
    }

    onProgress?.call(received, totalBytes ?? received);

    // The file was written straight to disk. Android's MediaStore does not
    // notice files created that way, so the gallery/İndirilenler list would
    // never show it until a reboot or a manual media scan. Register it now so
    // the download appears immediately.
    await _publishToMediaStore(file);

    return file;
  }

  /// Registers a freshly written file with the device media store.
  ///
  /// Best-effort: on platforms without a media store (or when the user has not
  /// granted gallery access) we silently skip, because the file is already on
  /// disk and the download itself succeeded.
  Future<void> _publishToMediaStore(File file) async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    try {
      final name = file.uri.pathSegments.last;
      final extension = name.contains('.')
          ? name.split('.').last.toLowerCase()
          : '';
      if (_videoExtensions.contains(extension)) {
        await PhotoManager.editor.saveVideo(file, title: name);
      }
      // Invalidate PhotoManager's internal cache so newly created files appear.
      await PhotoManager.clearFileCache();
    } catch (_) {
      // Ignore: publishing is a convenience, not a requirement.
    }
  }

  static const _videoExtensions = {'mp4', 'mov', 'webm', 'mkv', 'avi'};

  /// Appends `_1`, `_2`, … so repeated downloads never overwrite each other.
  String _uniqueFileName(Directory directory, String fileName) {
    final separator = Platform.pathSeparator;
    var candidate = fileName;
    var index = 1;
    while (File('${directory.path}$separator$candidate').existsSync()) {
      final dot = fileName.lastIndexOf('.');
      candidate = dot > 0
          ? '${fileName.substring(0, dot)}_$index${fileName.substring(dot)}'
          : '${fileName}_$index';
      index++;
    }
    return candidate;
  }
}

/// Public "Download" folder on Android, falling back to the app documents
/// directory on desktop/unsupported platforms.
Future<Directory> _defaultDownloadDirectory() async {
  if (Platform.isAndroid) {
    for (final path in const [
      '/storage/emulated/0/Download',
      '/sdcard/Download',
    ]) {
      final directory = Directory(path);
      if (await directory.exists()) return directory;
    }
  }
  final base = await getApplicationDocumentsDirectory();
  return Directory('${base.path}${Platform.pathSeparator}Download');
}

/// Human readable size used by the download UI, e.g. `12.4 MB`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB'];
  var size = bytes / 1024;
  var unitIndex = 0;
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  final decimals = size >= 10 ? 0 : 1;
  return '${size.toStringAsFixed(decimals)} ${units[unitIndex]}';
}

/// Percentage (0-100) of a download, or null when the total size is unknown.
int? downloadPercent(int receivedBytes, int? totalBytes) {
  if (totalBytes == null || totalBytes <= 0) return null;
  final ratio = receivedBytes / totalBytes;
  return (math.min(1.0, math.max(0.0, ratio)) * 100).round();
}
