import 'dart:async';
import 'package:dio/dio.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_exp;

import 'media_downloader.dart';

/// Client-side media resolver that completely eliminates Python backend dependency.
///
/// Features:
/// 1. YouTube: Resolves streams (video-only, audio-only, muxed) and metadata using `youtube_explode_dart`.
/// 2. Social Scraper (Instagram, TikTok, Facebook, Pinterest): Uses Dio HTTP client + regex scrapers
///    to extract direct media URLs directly on the user's phone.
class ClientMediaResolver implements MediaResolver {
  ClientMediaResolver({
    Dio? dioClient,
    yt_exp.YoutubeExplode? youtubeExplode,
  })  : _dio = dioClient ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 15),
                receiveTimeout: const Duration(seconds: 25),
                followRedirects: true,
                maxRedirects: 5,
                headers: {
                  'User-Agent':
                      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
                  'Accept':
                      'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
                  'Accept-Language': 'en-US,en;q=0.9,tr;q=0.8',
                },
              ),
            ),
        _yt = youtubeExplode ?? yt_exp.YoutubeExplode();

  final Dio _dio;
  final yt_exp.YoutubeExplode _yt;

  void dispose() {
    _yt.close();
    _dio.close();
  }

  // ---------------------------------------------------------------------------
  // URL Classification
  // ---------------------------------------------------------------------------

  bool _isYouTube(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('youtube.com') || host.contains('youtu.be');
  }

  bool _isTikTok(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('tiktok.com');
  }

  bool _isInstagram(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('instagram.com');
  }

  bool _isFacebook(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('facebook.com') ||
        host.contains('fb.watch') ||
        host.contains('fb.com');
  }

  bool _isPinterest(Uri uri) {
    final host = uri.host.toLowerCase();
    return host.contains('pinterest.com') || host.contains('pin.it');
  }

  // ---------------------------------------------------------------------------
  // SEARCH IMPLEMENTATION (Client-side via YoutubeExplode)
  // ---------------------------------------------------------------------------

  @override
  Future<List<SearchResultItem>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return const [];

    try {
      final searchList = await _yt.search.search(trimmed);
      final results = <SearchResultItem>[];

      for (final video in searchList.take(20)) {
        final duration = video.duration != null
            ? '${video.duration!.inMinutes}:${(video.duration!.inSeconds % 60).toString().padLeft(2, '0')}'
            : '';
        results.add(
          SearchResultItem(
            id: video.id.value,
            baslik: video.title,
            kanal: video.author,
            sure: duration,
            url: video.url,
          ),
        );
      }
      return results;
    } catch (e) {
      // Fallback: return empty list on search error
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // PREVIEW IMPLEMENTATION
  // ---------------------------------------------------------------------------

  @override
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    if (_isYouTube(source)) {
      return _previewYouTube(source, kind);
    }
    if (_isTikTok(source)) {
      return _previewTikTok(source);
    }
    if (_isInstagram(source)) {
      return _previewInstagram(source);
    }
    if (_isFacebook(source)) {
      return _previewFacebook(source);
    }
    if (_isPinterest(source)) {
      return _previewPinterest(source);
    }

    // Generic fallback preview
    final urlStr = source.toString();
    return MediaPreview(
      title: _extractGenericTitle(urlStr),
      qualities: _defaultQualities(kind),
    );
  }

  Future<MediaPreview> _previewYouTube(Uri source, DownloadKind kind) async {
    try {
      final videoId = _extractYouTubeVideoId(source);
      if (videoId == null) {
        throw const MediaResolverException('Geçersiz YouTube bağlantısı.');
      }

      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streams.getManifest(videoId);

      final qualities = <VideoQuality>[];
      if (kind == DownloadKind.video) {
        final seenHeights = <int>{};
        for (final stream in manifest.video) {
          final qualityLabel = stream.qualityLabel;
          final match = RegExp(r'(\d+)p').firstMatch(qualityLabel);
          final numericHeight = match != null
              ? int.tryParse(match.group(1)!) ?? stream.videoResolution.height
              : stream.videoResolution.height;

          if (numericHeight > 0 && seenHeights.add(numericHeight)) {
            qualities.add(
              VideoQuality(
                height: numericHeight,
                label: '${numericHeight}p HD (${stream.container.name.toUpperCase()})',
                sizeInBytes: stream.size.totalBytes,
              ),
            );
          }
        }
        qualities.sort((a, b) => b.height.compareTo(a.height));
      } else {
        qualities.addAll(const [
          VideoQuality(
            height: 0,
            label: 'MP3 Ses Dosyası (320 kbps - En Yüksek Kalite)',
          ),
          VideoQuality(height: 192, label: 'MP3 Standart Kalite (192 kbps)'),
          VideoQuality(height: 128, label: 'MP3 Hızlı İndir (128 kbps)'),
        ]);
      }

      return MediaPreview(
        title: video.title,
        duration: video.duration,
        uploader: video.author,
        qualities: qualities,
      );
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('YouTube videosu çözülemedi: $e');
    }
  }

  Future<MediaPreview> _previewTikTok(Uri source) async {
    try {
      final resolved = await _scrapeTikTok(source);
      return MediaPreview(
        title: resolved.fileName,
        qualities: const [
          VideoQuality(height: 0, label: 'TikTok HD Video (Filigransız)'),
        ],
      );
    } catch (_) {
      return MediaPreview(
        title: 'TikTok Videosu',
        qualities: const [
          VideoQuality(height: 0, label: 'TikTok HD Video (Filigransız)'),
        ],
      );
    }
  }

  Future<MediaPreview> _previewInstagram(Uri source) async {
    try {
      final resolved = await _scrapeInstagram(source);
      return MediaPreview(
        title: resolved.fileName,
        qualities: const [
          VideoQuality(height: 0, label: 'Instagram HD Medya'),
        ],
      );
    } catch (_) {
      return MediaPreview(
        title: 'Instagram Medyası',
        qualities: const [
          VideoQuality(height: 0, label: 'Instagram HD Medya'),
        ],
      );
    }
  }

  Future<MediaPreview> _previewFacebook(Uri source) async {
    try {
      final resolved = await _scrapeFacebook(source);
      return MediaPreview(
        title: resolved.fileName,
        qualities: const [
          VideoQuality(height: 0, label: 'Facebook HD Video'),
        ],
      );
    } catch (_) {
      return MediaPreview(
        title: 'Facebook Videosu',
        qualities: const [
          VideoQuality(height: 0, label: 'Facebook HD Video'),
        ],
      );
    }
  }

  Future<MediaPreview> _previewPinterest(Uri source) async {
    try {
      final resolved = await _scrapePinterest(source);
      return MediaPreview(
        title: resolved.fileName,
        qualities: const [
          VideoQuality(height: 0, label: 'Pinterest Orijinal Medya'),
        ],
      );
    } catch (_) {
      return MediaPreview(
        title: 'Pinterest Medyası',
        qualities: const [
          VideoQuality(height: 0, label: 'Pinterest Orijinal Medya'),
        ],
      );
    }
  }

  // ---------------------------------------------------------------------------
  // RESOLVE IMPLEMENTATION (The core offline / client-side resolver)
  // ---------------------------------------------------------------------------

  @override
  Future<ResolvedMedia> resolve(
    Uri source,
    DownloadKind kind, {
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    if (_isYouTube(source)) {
      return _resolveYouTube(
        source,
        kind,
        height: height,
        startTime: startTime,
        endTime: endTime,
        audioEffect: audioEffect,
      );
    }
    if (_isTikTok(source)) {
      return _scrapeTikTok(source);
    }
    if (_isInstagram(source)) {
      return _scrapeInstagram(source);
    }
    if (_isFacebook(source)) {
      return _scrapeFacebook(source);
    }
    if (_isPinterest(source)) {
      return _scrapePinterest(source);
    }

    // Direct media link or generic fallback
    final ext = kind == DownloadKind.audio ? '.mp3' : '.mp4';
    return ResolvedMedia(
      url: source,
      fileName: 'vidsave_${DateTime.now().millisecondsSinceEpoch}$ext',
    );
  }

  // ---------------------------------------------------------------------------
  // 1. YouTube Client-Side Engine (youtube_explode_dart)
  // ---------------------------------------------------------------------------

  Future<ResolvedMedia> _resolveYouTube(
    Uri source,
    DownloadKind kind, {
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    final videoId = _extractYouTubeVideoId(source);
    if (videoId == null) {
      throw const MediaResolverException('Geçersiz YouTube bağlantısı.');
    }

    try {
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streams.getManifest(videoId);
      final sanitizedTitle = _sanitizeFileName(video.title);

      if (kind == DownloadKind.audio) {
        // Find highest bitrate audio-only stream
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isEmpty) {
          // Fallback to muxed stream
          final muxed = manifest.muxed.withHighestBitrate();
          return ResolvedMedia(
            url: muxed.url,
            fileName: '$sanitizedTitle.mp3',
            fileSizeInBytes: muxed.size.totalBytes,
            startTime: startTime,
            endTime: endTime,
            audioEffect: audioEffect,
          );
        }
        final bestAudio = audioStreams.withHighestBitrate();
        return ResolvedMedia(
          url: bestAudio.url,
          fileName: '$sanitizedTitle.mp3',
          fileSizeInBytes: bestAudio.size.totalBytes,
          startTime: startTime,
          endTime: endTime,
          audioEffect: audioEffect,
        );
      }

      // Video download
      if (height != null && height > 0) {
        // Look for matching video-only stream, or muxed stream
        final matching = manifest.videoOnly.where(
          (s) => s.videoResolution.height == height,
        );
        if (matching.isNotEmpty) {
          final videoStream = matching.first;
          final audioStream = manifest.audioOnly.isNotEmpty
              ? manifest.audioOnly.withHighestBitrate()
              : null;

          return ResolvedMedia(
            url: videoStream.url,
            fileName: '$sanitizedTitle.mp4',
            fileSizeInBytes: videoStream.size.totalBytes,
            audioUrl: audioStream?.url,
            audioFileSizeInBytes: audioStream?.size.totalBytes,
          );
        }
      }

      // Default: Check muxed stream first or best video-only + best audio-only
      if (manifest.muxed.isNotEmpty) {
        final bestMuxed = manifest.muxed.withHighestBitrate();
        // If muxed resolution is at least 720p or no video-only available
        if (bestMuxed.videoResolution.height >= 720 ||
            manifest.videoOnly.isEmpty) {
          return ResolvedMedia(
            url: bestMuxed.url,
            fileName: '$sanitizedTitle.mp4',
            fileSizeInBytes: bestMuxed.size.totalBytes,
          );
        }
      }

      // Highest video-only + audio-only pair for FFmpeg merging
      final bestVideo = manifest.videoOnly.isNotEmpty
          ? manifest.videoOnly.first
          : (manifest.video.isNotEmpty ? manifest.video.first : null);

      if (bestVideo == null) {
        throw const MediaResolverException('İndirilebilir video akışı bulunamadı.');
      }

      final bestAudio = manifest.audioOnly.isNotEmpty
          ? manifest.audioOnly.withHighestBitrate()
          : null;

      return ResolvedMedia(
        url: bestVideo.url,
        fileName: '$sanitizedTitle.mp4',
        fileSizeInBytes: bestVideo.size.totalBytes,
        audioUrl: bestAudio?.url,
        audioFileSizeInBytes: bestAudio?.size.totalBytes,
      );
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('YouTube videosu çözülemedi: $e');
    }
  }

  String? _extractYouTubeVideoId(Uri uri) {
    if (uri.host.contains('youtu.be')) {
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      return segments.isNotEmpty ? segments.first : null;
    }
    if (uri.queryParameters.containsKey('v')) {
      return uri.queryParameters['v'];
    }
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    if (segments.contains('shorts') || segments.contains('embed')) {
      final idx = segments.contains('shorts')
          ? segments.indexOf('shorts')
          : segments.indexOf('embed');
      if (idx + 1 < segments.length) {
        return segments[idx + 1];
      }
    }
    return segments.isNotEmpty ? segments.last : null;
  }

  // ---------------------------------------------------------------------------
  // 2. TikTok Client-Side Scraper
  // ---------------------------------------------------------------------------

  Future<ResolvedMedia> _scrapeTikTok(Uri source) async {
    try {
      final res = await _dio.get<String>(
        source.toString(),
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 '
                '(KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
          },
        ),
      );

      final html = res.data ?? '';

      // 1. Look for playAddr or downloadAddr in SIGI_STATE or __UNIVERSAL_DATA_FOR_REHYDRATION__
      final playAddrMatch = RegExp(r'"playAddr":\s*"([^"]+)"').firstMatch(html) ??
          RegExp(r'"downloadAddr":\s*"([^"]+)"').firstMatch(html) ??
          RegExp(r'"play_addr":\s*\{\s*"url_list":\s*\["([^"]+)"').firstMatch(html);

      if (playAddrMatch != null) {
        var videoUrl = playAddrMatch.group(1)!;
        videoUrl = videoUrl.replaceAll(r'\u0026', '&').replaceAll(r'\/', '/');
        return ResolvedMedia(
          url: Uri.parse(videoUrl),
          fileName: 'tiktok_${DateTime.now().millisecondsSinceEpoch}.mp4',
          downloadHeaders: {
            'Referer': 'https://www.tiktok.com/',
            'User-Agent':
                'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15',
          },
        );
      }

      // 2. Fallback: Search for video tag src
      final videoTagMatch = RegExp(r'<video[^>]+src="([^"]+)"').firstMatch(html);
      if (videoTagMatch != null) {
        final videoUrl = videoTagMatch.group(1)!.replaceAll('&amp;', '&');
        return ResolvedMedia(
          url: Uri.parse(videoUrl),
          fileName: 'tiktok_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
      }

      // 3. Fallback: TikWM public client-side free API
      final tikwmRes = await _dio.post<Map<String, dynamic>>(
        'https://www.tikwm.com/api/',
        data: {'url': source.toString(), 'count': 12, 'cursor': 0, 'web': 1},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
        ),
      );

      final tikData = tikwmRes.data?['data'];
      if (tikData != null && tikData is Map) {
        final playUrl = tikData['play'] ?? tikData['wmplay'];
        final title = tikData['title'] as String? ?? 'tiktok_video';
        if (playUrl != null) {
          final uriStr = playUrl.toString().startsWith('http')
              ? playUrl.toString()
              : 'https://www.tikwm.com$playUrl';
          return ResolvedMedia(
            url: Uri.parse(uriStr),
            fileName: '${_sanitizeFileName(title)}.mp4',
          );
        }
      }

      throw const MediaResolverException('TikTok videosunun kaynak URL\'si ayıklanamadı.');
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('TikTok kazıma hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 3. Instagram Client-Side Scraper
  // ---------------------------------------------------------------------------

  Future<ResolvedMedia> _scrapeInstagram(Uri source) async {
    try {
      final res = await _dio.get<String>(
        source.toString(),
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ),
      );

      final html = res.data ?? '';

      // Try OpenGraph meta tags
      final ogVideo = RegExp(r'<meta\s+property="og:video"\s+content="([^"]+)"')
              .firstMatch(html) ??
          RegExp(r'<meta\s+content="([^"]+)"\s+property="og:video"')
              .firstMatch(html);
      if (ogVideo != null) {
        final videoUrl = ogVideo.group(1)!.replaceAll('&amp;', '&');
        return ResolvedMedia(
          url: Uri.parse(videoUrl),
          fileName: 'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
      }

      // Try video_url inside script JSON
      final videoUrlMatch = RegExp(r'"video_url":\s*"([^"]+)"').firstMatch(html);
      if (videoUrlMatch != null) {
        var videoUrl = videoUrlMatch.group(1)!;
        videoUrl = videoUrl.replaceAll(r'\u0026', '&').replaceAll(r'\/', '/');
        return ResolvedMedia(
          url: Uri.parse(videoUrl),
          fileName: 'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
      }

      // Try og:image for Instagram photo
      final ogImage = RegExp(r'<meta\s+property="og:image"\s+content="([^"]+)"')
          .firstMatch(html);
      if (ogImage != null) {
        final imgUrl = ogImage.group(1)!.replaceAll('&amp;', '&');
        return ResolvedMedia(
          url: Uri.parse(imgUrl),
          fileName: 'instagram_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
      }

      throw const MediaResolverException(
        'Instagram medya URL\'si korumalı veya gizli hesap.',
      );
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('Instagram çözme hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 4. Facebook Client-Side Scraper
  // ---------------------------------------------------------------------------

  Future<ResolvedMedia> _scrapeFacebook(Uri source) async {
    try {
      final res = await _dio.get<String>(
        source.toString(),
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ),
      );

      final html = res.data ?? '';

      // HD or SD video URL pattern
      final hdMatch = RegExp(r'"playable_url_quality_hd":\s*"([^"]+)"').firstMatch(html) ??
          RegExp(r'"hd_src":\s*"([^"]+)"').firstMatch(html);
      final sdMatch = RegExp(r'"playable_url":\s*"([^"]+)"').firstMatch(html) ??
          RegExp(r'"sd_src":\s*"([^"]+)"').firstMatch(html);

      final targetMatch = hdMatch ?? sdMatch;
      if (targetMatch != null) {
        var videoUrl = targetMatch.group(1)!;
        videoUrl = videoUrl.replaceAll(r'\u0026', '&').replaceAll(r'\/', '/');
        return ResolvedMedia(
          url: Uri.parse(videoUrl),
          fileName: 'facebook_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
      }

      final ogVideo = RegExp(r'<meta\s+property="og:video"\s+content="([^"]+)"')
              .firstMatch(html) ??
          RegExp(r'<meta\s+property="og:video:url"\s+content="([^"]+)"')
              .firstMatch(html);
      if (ogVideo != null) {
        final videoUrl = ogVideo.group(1)!.replaceAll('&amp;', '&');
        return ResolvedMedia(
          url: Uri.parse(videoUrl),
          fileName: 'facebook_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
      }

      throw const MediaResolverException('Facebook videosunun kaynak URL\'si bulunamadı.');
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('Facebook kazıma hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // 5. Pinterest Client-Side Scraper
  // ---------------------------------------------------------------------------

  Future<ResolvedMedia> _scrapePinterest(Uri source) async {
    try {
      final res = await _dio.get<String>(
        source.toString(),
        options: Options(
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          },
        ),
      );

      final html = res.data ?? '';

      // 1. Check for video in JSON/html
      final videoMatch = RegExp(r'"url":\s*"(https://[^"]+\.mp4[^"]*)"').firstMatch(html) ??
          RegExp(r'<video[^>]+src="([^"]+)"').firstMatch(html);
      if (videoMatch != null) {
        var videoUrl = videoMatch.group(1)!;
        videoUrl = videoUrl.replaceAll(r'\u0026', '&').replaceAll(r'\/', '/');
        return ResolvedMedia(
          url: Uri.parse(videoUrl),
          fileName: 'pinterest_${DateTime.now().millisecondsSinceEpoch}.mp4',
        );
      }

      // 2. Check for high-res images (originals / 736x)
      final imgMatch = RegExp(r'"url":\s*"(https://i\.pinimg\.com/originals/[^"]+)"').firstMatch(html) ??
          RegExp(r'"url":\s*"(https://i\.pinimg\.com/[^"]+)"').firstMatch(html) ??
          RegExp(r'<meta\s+property="og:image"\s+content="([^"]+)"').firstMatch(html);

      if (imgMatch != null) {
        final imgUrl = imgMatch.group(1)!.replaceAll('&amp;', '&');
        return ResolvedMedia(
          url: Uri.parse(imgUrl),
          fileName: 'pinterest_${DateTime.now().millisecondsSinceEpoch}.jpg',
        );
      }

      throw const MediaResolverException('Pinterest medyası bulunamadı.');
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('Pinterest kazıma hatası: $e');
    }
  }

  // ---------------------------------------------------------------------------
  // Helper Methods
  // ---------------------------------------------------------------------------

  String _sanitizeFileName(String value) {
    final sanitized = value.replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), '_').trim();
    return sanitized.isEmpty ? 'vidsave_media' : sanitized;
  }

  String _extractGenericTitle(String url) {
    try {
      final u = Uri.parse(url);
      final last = u.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
      return last != null && last.isNotEmpty ? last : 'Medya İndirme';
    } catch (_) {
      return 'Medya İndirme';
    }
  }

  List<VideoQuality> _defaultQualities(DownloadKind kind) {
    if (kind == DownloadKind.audio) {
      return const [
        VideoQuality(
          height: 0,
          label: 'MP3 Ses Dosyası (320 kbps - En Yüksek Kalite)',
        ),
        VideoQuality(height: 192, label: 'MP3 Standart Kalite (192 kbps)'),
        VideoQuality(height: 128, label: 'MP3 Hızlı İndir (128 kbps)'),
      ];
    }
    return const [
      VideoQuality(height: 0, label: 'En İyi Kalite (Önerilen)'),
      VideoQuality(height: 1080, label: '1080p Full HD'),
      VideoQuality(height: 720, label: '720p HD'),
      VideoQuality(height: 480, label: '480p Standart'),
    ];
  }
}
