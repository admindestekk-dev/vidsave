import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt_exp;

import 'app_dio.dart';
import 'download_exception_handler.dart';
import 'media_downloader.dart';
import 'remote_config_service.dart';

/// Tarayıcı çerezlerini ve kimliğini simüle eden güncel User-Agent dizeleri.
const String kUniversalDesktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

const String kUniversalMobileUserAgent =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Mobile Safari/537.36';

/// Bot kalkanlarını (Cloudflare, Akamai, Datadome, PerimeterX vb.) aşmak için
/// standart tarayıcı gezinme başlıkları.
const Map<String, String> kUniversalDefaultHeaders = {
  'User-Agent': kUniversalDesktopUserAgent,
  'Sec-Fetch-Mode': 'navigate',
  'Sec-Fetch-Site': 'cross-site',
  'Sec-Fetch-Dest': 'document',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8',
  'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
  'Upgrade-Insecure-Requests': '1',
};

/// ---------------------------------------------------------------------------
/// 3. EVRENSEL URL TEMİZLİK KALKANI
/// ---------------------------------------------------------------------------
/// Tüm platformlardan gelen çıktıların başında/sonunda yer alan Unicode
/// karakterlerini (\u002F), kaçış çizgilerini (\/) ve ham çift tırnak
/// işaretlerini (") otomatik temizleyen, eksik protokollerin başına https:
/// ekleyen evrensel koruma fonksiyonu.
String evrenselTemizUrlShield(String hamUrl) {
  if (hamUrl.trim().isEmpty) return '';

  // 1. Tırnak işaretlerini (" veya ') ve başta/sonda kalan boşlukları temizle
  var link = hamUrl.replaceAll('"', '').replaceAll("'", '').trim();

  // 2. HTML kaçışları (&amp;)
  link = link.replaceAll('&amp;', '&');

  // 3. \u0026, \u002F, \/, \\ ters eğik çizgi ve Unicode kaçışlarını düzelt
  link = link
      .replaceAll(r'\u0026', '&')
      .replaceAll(r'\u002F', '/')
      .replaceAll(r'\u002f', '/')
      .replaceAll(r'\/', '/')
      .replaceAll(r'\', '/');

  // 4. Hatalı kırpılma sonucu metin olarak kalmış "u002F" veya "u002f" kalıntılarını temizle
  link = link.replaceAll(RegExp(r'u002f', caseSensitive: false), '/');

  // 5. Link başındaki ardışık eğik çizgileri temizle
  while (link.startsWith('/')) {
    link = link.substring(1);
  }

  // Eğer metin bir arama sorgusuysa (boşluk içeriyor ve URL özellikleri taşımıyorsa) protokol ekleme
  final hasUrlTraits =
      link.contains('/') || link.contains('.') || link.startsWith('http');
  if (!hasUrlTraits) {
    return link;
  }

  // 6. Protokol bozukluklarını düzelt veya eksik protokolün başına https: ekle
  if (link.startsWith('http://')) {
    // geçerli http protokolü, koru
  } else if (link.startsWith('https://')) {
    // geçerli https protokolü, koru
  } else if (RegExp(r'^https:/+', caseSensitive: false).hasMatch(link)) {
    link = link.replaceFirst(
      RegExp(r'^https:/+', caseSensitive: false),
      'https://',
    );
  } else if (RegExp(r'^http:/+', caseSensitive: false).hasMatch(link)) {
    link = link.replaceFirst(
      RegExp(r'^http:/+', caseSensitive: false),
      'http://',
    );
  } else {
    link = 'https://$link';
  }

  // 7. Protokolden hemen sonraki (host öncesi) fazla eğik çizgileri temizle
  final protoMatch = RegExp(
    r'^(https?://)(.*)$',
    caseSensitive: false,
  ).firstMatch(link);
  if (protoMatch != null) {
    final scheme = protoMatch.group(1)!;
    var rest = protoMatch.group(2)!;
    while (rest.startsWith('/')) {
      rest = rest.substring(1);
    }
    link = '$scheme$rest';
  }

  return link.trim();
}

/// Evrensel URL Temizlik Kalkanı standart çağrısı
String evrenselTemizUrl(String hamUrl) => evrenselTemizUrlShield(hamUrl);

/// ---------------------------------------------------------------------------
/// InAppWebView / Cihaz Hafızası Oturum Çerez Yöneticisi (CookieManager Bridge)
/// ---------------------------------------------------------------------------
class UniversalCookieManager {
  UniversalCookieManager({InMemoryCookieJar? memoryJar})
    : memoryJar = memoryJar ?? AppDio.cookieJar;

  final InMemoryCookieJar memoryJar;
  WebViewCookieManager? _webViewCookieManager;

  WebViewCookieManager get _cookieManager {
    _webViewCookieManager ??= WebViewCookieManager();
    return _webViewCookieManager!;
  }

  /// Belirtilen hedef URI için WebViewCookieManager (cihaz hafızası) ve
  /// InMemoryCookieJar havuzundaki çerezleri birleştirerek 'Cookie: ...' dizesi üretir.
  Future<String?> getCookieHeader(Uri uri) async {
    // 1. Desteklenen platformlarda InAppWebView / WebViewCookieManager üzerinden oku
    if (!kIsWeb &&
        !Platform.environment.containsKey('FLUTTER_TEST') &&
        (Platform.isAndroid || Platform.isIOS || Platform.isMacOS)) {
      try {
        final cookies = await _cookieManager.getCookies(domain: uri);
        for (final c in cookies) {
          memoryJar.saveCookie(uri.host, c.name, c.value);
        }
      } catch (_) {
        // Platform bağımlılığı henüz hazır değilse sessizce geç
      }
    }

    // 2. InMemoryCookieJar havuzundan geçerli çerezleri al
    return memoryJar.getCookieHeader(uri);
  }

  /// Elle çerez ekleme veya oturum güncelleme
  void saveCookie(String domain, String name, String value) {
    memoryJar.saveCookie(domain, name, value);
  }

  /// Çoklu çerez kaydı
  void setCookies(String domain, Map<String, String> cookies) {
    memoryJar.setCookies(domain, cookies);
  }
}

/// ---------------------------------------------------------------------------
/// 1. GLOBAL KAZICI MOTOR YAPILANDIRMASI (UniversalScraper)
/// ---------------------------------------------------------------------------
class UniversalScraper {
  UniversalScraper({
    Dio? dioClient,
    yt_exp.YoutubeExplode? youtubeExplode,
    UniversalCookieManager? cookieManager,
  }) : _cookieManager = cookieManager ?? UniversalCookieManager(),
       _yt = youtubeExplode ?? yt_exp.YoutubeExplode() {
    _dio = dioClient ?? _createConfiguredDio();
  }

  static UniversalScraper? _instance;

  /// Global tekil motor örneği
  static UniversalScraper get instance {
    _instance ??= UniversalScraper();
    return _instance!;
  }

  late final Dio _dio;
  final yt_exp.YoutubeExplode _yt;
  final UniversalCookieManager _cookieManager;

  Dio get dio => _dio;
  yt_exp.YoutubeExplode get yt => _yt;
  UniversalCookieManager get cookieManager => _cookieManager;

  /// Kullanıcının istediği kesin ayarlarla donatılmış Dio motoru:
  /// • followRedirects: true
  /// • maxRedirects: 8
  /// • validateStatus: (status) => status! < 500
  /// • Headers: güncel User-Agent, Sec-Fetch-Mode: navigate, Origin, Referer
  Dio _createConfiguredDio() {
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 30),
        followRedirects: true,
        maxRedirects: 8,
        validateStatus: (status) => status != null && status < 500,
        headers: Map<String, dynamic>.from(kUniversalDefaultHeaders),
      ),
    );

    // Evrensel Çerez ve Dinamik Platform Başlık Kalkanı (Interceptor)
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final uri = options.uri;
          final host = uri.host.toLowerCase();

          // A) Dinamik Platform Köken ve Referans Parametreleri
          final dynamicUserAgent = RemoteConfigService.instance.userAgent;
          if (dynamicUserAgent.isNotEmpty) {
            options.headers['User-Agent'] = dynamicUserAgent;
          }

          if (host.contains('youtube.com') ||
              host.contains('googlevideo.com') ||
              host.contains('youtu.be')) {
            options.headers['Referer'] = 'https://youtube.com';
            options.headers['Origin'] = 'https://youtube.com';
          } else if (host.contains('tiktok.com') ||
              host.contains('tiktokcdn.com') ||
              host.contains('byteoversea.com') ||
              host.contains('ibytedtos.com')) {
            options.headers['Referer'] = 'https://www.tiktok.com/';
            options.headers['Origin'] = 'https://www.tiktok.com';
          } else if (host.contains('instagram.com') ||
              host.contains('cdninstagram.com') ||
              host.contains('fbcdn.net')) {
            options.headers['Referer'] = 'https://www.instagram.com/';
            options.headers['Origin'] = 'https://www.instagram.com';
          } else if (host.contains('facebook.com') ||
              host.contains('fb.watch') ||
              host.contains('fb.com')) {
            options.headers['Referer'] = 'https://www.facebook.com/';
            options.headers['Origin'] = 'https://www.facebook.com';
          } else if (host.contains('pinterest.com') ||
              host.contains('pinimg.com') ||
              host.contains('pin.it')) {
            options.headers['Referer'] = 'https://www.pinterest.com/';
            options.headers['Origin'] = 'https://www.pinterest.com';
          } else if (host.contains('twitter.com') ||
              host.contains('x.com') ||
              host.contains('twimg.com')) {
            options.headers['Referer'] = 'https://twitter.com/';
            options.headers['Origin'] = 'https://twitter.com';
          } else if (host.contains('vimeo.com') ||
              host.contains('vimeocdn.com')) {
            options.headers['Referer'] = 'https://vimeo.com/';
            options.headers['Origin'] = 'https://vimeo.com';
          } else if (host.contains('dailymotion.com') ||
              host.contains('dmcdn.net')) {
            options.headers['Referer'] = 'https://www.dailymotion.com/';
            options.headers['Origin'] = 'https://www.dailymotion.com';
          } else if (!options.headers.containsKey('Referer')) {
            options.headers['Referer'] = '${uri.scheme}://${uri.host}';
            options.headers['Origin'] = '${uri.scheme}://${uri.host}';
          }

          // B) Cihaz Hafızasından Oturum Çerezlerinin (Cookie) Enjeksiyonu
          final cookieHeader = await _cookieManager.getCookieHeader(uri);
          if (cookieHeader != null && cookieHeader.isNotEmpty) {
            options.headers['Cookie'] = cookieHeader;
          }

          handler.next(options);
        },
        onResponse: (response, handler) {
          final setCookies = response.headers['set-cookie'];
          if (setCookies != null && setCookies.isNotEmpty) {
            _cookieManager.memoryJar.saveFromResponse(
              response.requestOptions.uri,
              setCookies,
            );
          }
          handler.next(response);
        },
        onError: (err, handler) {
          if (err.response != null) {
            final setCookies = err.response!.headers['set-cookie'];
            if (setCookies != null && setCookies.isNotEmpty) {
              _cookieManager.memoryJar.saveFromResponse(
                err.response!.requestOptions.uri,
                setCookies,
              );
            }
          }
          handler.next(err);
        },
      ),
    );

    return dio;
  }

  void dispose() {
    _yt.close();
  }

  // ---------------------------------------------------------------------------
  // 2. TÜM PLATFORMLAR İÇİN LOKAL ÇÖZÜMLEYİCİLER (EXTRACTORS)
  // ---------------------------------------------------------------------------

  /// A) YOUTUBE & MP3: youtube_explode_dart streamsClient formatında getManifest
  /// çözüp, en yüksek kalitede video/ses veya saf MP3 akışı sağlar.
  Future<ResolvedMedia> extractYouTube(
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
      // Güncel streamsClient mimarisi ile manifestoyu çöz
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);
      final sanitizedTitle = _sanitizeFileName(video.title);

      if (kind == DownloadKind.audio) {
        // En yüksek kalitedeki ses kanalı (manifest.audioOnly)
        final audioStreams = manifest.audioOnly;
        if (audioStreams.isEmpty) {
          final muxed = manifest.muxed.withHighestBitrate();
          return ResolvedMedia(
            url: muxed.url,
            fileName: '$sanitizedTitle.mp3',
            fileSizeInBytes: muxed.size.totalBytes,
            byteStreamProvider: () => _yt.videos.streamsClient.get(muxed),
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
          byteStreamProvider: () => _yt.videos.streamsClient.get(bestAudio),
          startTime: startTime,
          endTime: endTime,
          audioEffect: audioEffect,
        );
      }

      // Video İndirme: İstenilen çözünürlük veya en yüksek çözünürlük
      if (height != null && height > 0) {
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
            byteStreamProvider: () => _yt.videos.streamsClient.get(videoStream),
            audioUrl: audioStream?.url,
            audioFileSizeInBytes: audioStream?.size.totalBytes,
            audioByteStreamProvider: audioStream != null
                ? () => _yt.videos.streamsClient.get(audioStream)
                : null,
          );
        }
      }

      // Muxed veya en yüksek video+ses kanalları
      if (manifest.muxed.isNotEmpty) {
        final bestMuxed = manifest.muxed.withHighestBitrate();
        if (bestMuxed.videoResolution.height >= 720 ||
            manifest.videoOnly.isEmpty) {
          return ResolvedMedia(
            url: bestMuxed.url,
            fileName: '$sanitizedTitle.mp4',
            fileSizeInBytes: bestMuxed.size.totalBytes,
            byteStreamProvider: () => _yt.videos.streamsClient.get(bestMuxed),
          );
        }
      }

      final bestVideo = manifest.videoOnly.isNotEmpty
          ? manifest.videoOnly.first
          : (manifest.video.isNotEmpty ? manifest.video.first : null);

      if (bestVideo == null) {
        throw const MediaResolverException(
          'İndirilebilir video akışı bulunamadı.',
        );
      }

      final bestAudio = manifest.audioOnly.isNotEmpty
          ? manifest.audioOnly.withHighestBitrate()
          : null;

      return ResolvedMedia(
        url: bestVideo.url,
        fileName: '$sanitizedTitle.mp4',
        fileSizeInBytes: bestVideo.size.totalBytes,
        byteStreamProvider: () => _yt.videos.streamsClient.get(bestVideo),
        audioUrl: bestAudio?.url,
        audioFileSizeInBytes: bestAudio?.size.totalBytes,
        audioByteStreamProvider: bestAudio != null
            ? () => _yt.videos.streamsClient.get(bestAudio)
            : null,
      );
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('YouTube videosu çözülemedi: $e');
    }
  }

  /// B) TIKTOK: Gelen kısa linklerin yönlendirildiği ham HTML sayfa kaynağını
  /// indirip, <script> etiketlerindeki gizli .mp4 adreslerini regex ile ayıklar.
  Future<ResolvedMedia> extractTikTok(Uri source) async {
    try {
      final res = await _dio.get<String>(source.toString());
      final html = res.data ?? '';

      // 1. Dinamik Remote Config ve yerel Script etiketlerindeki regex kalıpları
      final patterns = <RegExp>[];
      final remotePattern = RemoteConfigService.instance.tiktokRegex;
      if (remotePattern.isNotEmpty) {
        for (final p in remotePattern.split('|')) {
          if (p.trim().isNotEmpty) {
            try {
              patterns.add(RegExp(p.trim()));
            } catch (_) {}
          }
        }
      }

      patterns.addAll([
        RegExp(r'"download_url":"(.*?)"'),
        RegExp(r'"playAddr":\s*"([^"]+)"'),
        RegExp(r'"downloadAddr":\s*"([^"]+)"'),
        RegExp(r'"play_addr":\s*\{\s*"url_list":\s*\["([^"]+)"'),
        RegExp(r'"url":\s*"(https://[^"]*tiktokcdn\.com[^"]+\.mp4[^"]*)"'),
        RegExp(r'<video[^>]+src="([^"]+)"'),
      ]);

      for (final pattern in patterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          final rawUrl = (match.groupCount >= 1 ? match.group(1) : null) ?? match.group(0)!;
          final cleanUrl = evrenselTemizUrlShield(rawUrl);
          if (cleanUrl.isNotEmpty && cleanUrl.startsWith('http')) {
            return ResolvedMedia(
              url: Uri.parse(cleanUrl),
              fileName: 'tiktok_${DateTime.now().millisecondsSinceEpoch}.mp4',
              downloadHeaders: {
                'Referer': 'https://www.tiktok.com/',
                'User-Agent': RemoteConfigService.instance.userAgent.isNotEmpty
                    ? RemoteConfigService.instance.userAgent
                    : kUniversalMobileUserAgent,
                'Sec-Fetch-Mode': 'navigate',
              },
            );
          }
        }
      }

      // 2. TikWM Açık İstemci Taraflı Yedek Algoritma (Sıfır Maliyetli Client-Side API)
      final tikwmRes = await _dio.post<Map<String, dynamic>>(
        'https://www.tikwm.com/api/',
        data: {'url': source.toString(), 'count': 12, 'cursor': 0, 'web': 1},
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          headers: {'User-Agent': kUniversalMobileUserAgent},
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
          final cleanUrl = evrenselTemizUrlShield(uriStr);
          return ResolvedMedia(
            url: Uri.parse(cleanUrl),
            fileName: '${_sanitizeFileName(title)}.mp4',
            downloadHeaders: {
              'Referer': 'https://www.tiktok.com/',
              'User-Agent': kUniversalMobileUserAgent,
            },
          );
        }
      }

      throw const MediaResolverException(
        'TikTok video adresi HTML kaynağından ayıklanamadı.',
      );
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('TikTok kazıma hatası: $e');
    }
  }

  /// C) PINTEREST: Kısa link yönlendirmesinden gelen HTML sayfa kaynağını
  /// indirip, <script> etiketlerindeki gizli .mp4 veya orijinal .jpg adreslerini ayıklar.
  Future<ResolvedMedia> extractPinterest(Uri source) async {
    try {
      final res = await _dio.get<String>(source.toString());
      final html = res.data ?? '';

      // 1. Video URL Regex Kalıpları
      final videoPatterns = <RegExp>[];
      final remotePinterest = RemoteConfigService.instance.pinterestRegex;
      if (remotePinterest.isNotEmpty) {
        for (final p in remotePinterest.split('|')) {
          if (p.trim().isNotEmpty) {
            try {
              videoPatterns.add(RegExp(p.trim()));
            } catch (_) {}
          }
        }
      }
      videoPatterns.addAll([
        RegExp(r'"download_url":"(.*?)"'),
        RegExp(r'"url":\s*"(https://[^"]+\.mp4[^"]*)"'),
        RegExp(r'<video[^>]+src="([^"]+)"'),
        RegExp(r'<meta\s+property="og:video"\s+content="([^"]+)"'),
      ]);

      for (final pattern in videoPatterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          final rawUrl = (match.groupCount >= 1 ? match.group(1) : null) ?? match.group(0)!;
          final cleanUrl = evrenselTemizUrlShield(rawUrl);
          if (cleanUrl.isNotEmpty && cleanUrl.contains('.mp4')) {
            return ResolvedMedia(
              url: Uri.parse(cleanUrl),
              fileName:
                  'pinterest_${DateTime.now().millisecondsSinceEpoch}.mp4',
              downloadHeaders: {
                'Referer': 'https://www.pinterest.com/',
                'User-Agent': RemoteConfigService.instance.userAgent.isNotEmpty
                    ? RemoteConfigService.instance.userAgent
                    : kUniversalDesktopUserAgent,
              },
            );
          }
        }
      }

      // 2. Yüksek Çözünürlüklü Orijinal Görsel (Originals / 736x) Regex Kalıpları
      final imagePatterns = [
        RegExp(r'"url":\s*"(https://i\.pinimg\.com/originals/[^"]+)"'),
        RegExp(r'"url":\s*"(https://i\.pinimg\.com/[^"]+)"'),
        RegExp(r'<meta\s+property="og:image"\s+content="([^"]+)"'),
      ];

      for (final pattern in imagePatterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          final rawUrl = match.group(1)!;
          final cleanUrl = evrenselTemizUrlShield(rawUrl);
          if (cleanUrl.isNotEmpty) {
            return ResolvedMedia(
              url: Uri.parse(cleanUrl),
              fileName:
                  'pinterest_${DateTime.now().millisecondsSinceEpoch}.jpg',
              downloadHeaders: {
                'Referer': 'https://www.pinterest.com/',
                'User-Agent': kUniversalDesktopUserAgent,
              },
            );
          }
        }
      }

      throw const MediaResolverException(
        'Pinterest medyası HTML kaynağından ayıklanamadı.',
      );
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('Pinterest kazıma hatası: $e');
    }
  }

  /// D) TWITTER (X): t.co kısa linklerinin HTML sayfasını veya açık
  /// VxTwitter/FxTwitter API'sini kullanarak ham video adresini ayıklar.
  Future<ResolvedMedia> extractTwitter(Uri source) async {
    try {
      // 1. VxTwitter / FxTwitter istemci taraflı ücretsiz JSON köprüsü (Sıfır Maliyet)
      final tweetMatch = RegExp(r'status/(\d+)').firstMatch(source.toString());
      if (tweetMatch != null) {
        final tweetId = tweetMatch.group(1)!;
        try {
          final vxRes = await _dio.get<Map<String, dynamic>>(
            'https://api.vxtwitter.com/Twitter/status/$tweetId',
            options: Options(
              headers: {
                'User-Agent': kUniversalDesktopUserAgent,
                'Sec-Fetch-Mode': 'navigate',
              },
            ),
          );
          final data = vxRes.data;
          if (data != null) {
            final mediaList = data['mediaURLs'] as List<dynamic>?;
            if (mediaList != null && mediaList.isNotEmpty) {
              final videoUrl = mediaList.first.toString();
              final cleanUrl = evrenselTemizUrlShield(videoUrl);
              return ResolvedMedia(
                url: Uri.parse(cleanUrl),
                fileName:
                    'twitter_${DateTime.now().millisecondsSinceEpoch}.mp4',
                downloadHeaders: {
                  'Referer': 'https://twitter.com/',
                  'User-Agent': kUniversalDesktopUserAgent,
                },
              );
            }
          }
        } catch (_) {}
      }

      // 2. Doğrudan HTML ve Script Kaynağı Taraması
      final res = await _dio.get<String>(source.toString());
      final html = res.data ?? '';

      final twPatterns = <RegExp>[];
      final remoteTwitter = RemoteConfigService.instance.twitterRegex;
      if (remoteTwitter.isNotEmpty) {
        for (final p in remoteTwitter.split('|')) {
          if (p.trim().isNotEmpty) {
            try {
              twPatterns.add(RegExp(p.trim()));
            } catch (_) {}
          }
        }
      }
      twPatterns.addAll([
        RegExp(r'"download_url":"(.*?)"'),
        RegExp(r'(https://video\.twimg\.com/[^"\\]+\.mp4[^"\\]*)'),
        RegExp(r'"video_url":\s*"([^"]+)"'),
        RegExp(r'<meta\s+property="og:video:url"\s+content="([^"]+)"'),
        RegExp(r'<meta\s+property="og:video"\s+content="([^"]+)"'),
      ]);

      for (final pattern in twPatterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          final rawUrl = (match.groupCount >= 1 ? match.group(1) : null) ?? match.group(0)!;
          final cleanUrl = evrenselTemizUrlShield(rawUrl);
          if (cleanUrl.isNotEmpty && cleanUrl.contains('.mp4')) {
            return ResolvedMedia(
              url: Uri.parse(cleanUrl),
              fileName: 'twitter_${DateTime.now().millisecondsSinceEpoch}.mp4',
              downloadHeaders: {
                'Referer': 'https://twitter.com/',
                'User-Agent': kUniversalDesktopUserAgent,
              },
            );
          }
        }
      }

      throw const MediaResolverException(
        'Twitter (X) video adresi bulunamadı.',
      );
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('Twitter kazıma hatası: $e');
    }
  }

  /// E) INSTAGRAM: CookieManager üzerinden hafızadaki oturum çerezlerini
  /// (sessionid, ds_user_id) otomatik okuyup istek başlığına yerleştirerek
  /// gizli/erişim kalkanlı medyaları çözer; ddinstagram yedek köprüsünü çalıştırır.
  Future<ResolvedMedia> extractInstagram(Uri source) async {
    try {
      // 1. ddinstagram / InstaFix doğrudan yönlendirme ve CDN köprüsü
      try {
        final path = source.path;
        final ddUri = Uri.parse('https://d.ddinstagram.com$path');
        final headRes = await _dio.head(
          ddUri.toString(),
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
            headers: {'User-Agent': kUniversalMobileUserAgent},
          ),
        );
        final location = headRes.headers.value('location');
        if (location != null && location.isNotEmpty) {
          final cleanLocation = evrenselTemizUrlShield(location);
          return ResolvedMedia(
            url: Uri.parse(cleanLocation),
            fileName: 'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4',
            downloadHeaders: {
              'Referer': 'https://www.instagram.com/',
              'User-Agent': kUniversalMobileUserAgent,
            },
          );
        }
      } catch (_) {}

      // 2. Oturum Çerezi Enjeksiyonu ile Doğrudan Instagram HTML Sayfasını İndir
      final res = await _dio.get<String>(source.toString());
      final html = res.data ?? '';

      final igPatterns = <RegExp>[];
      final remoteIg = RemoteConfigService.instance.instagramRegex;
      if (remoteIg.isNotEmpty) {
        for (final p in remoteIg.split('|')) {
          if (p.trim().isNotEmpty) {
            try {
              igPatterns.add(RegExp(p.trim()));
            } catch (_) {}
          }
        }
      }
      igPatterns.addAll([
        RegExp(r'"download_url":"(.*?)"'),
        RegExp(r'<meta\s+property="og:video"\s+content="([^"]+)"'),
        RegExp(r'<meta\s+content="([^"]+)"\s+property="og:video"'),
        RegExp(r'"video_url":\s*"([^"]+)"'),
      ]);

      for (final pattern in igPatterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          final rawUrl = (match.groupCount >= 1 ? match.group(1) : null) ?? match.group(0)!;
          final cleanUrl = evrenselTemizUrlShield(rawUrl);
          return ResolvedMedia(
            url: Uri.parse(cleanUrl),
            fileName: 'instagram_${DateTime.now().millisecondsSinceEpoch}.mp4',
            downloadHeaders: {
              'Referer': 'https://www.instagram.com/',
              'User-Agent': RemoteConfigService.instance.userAgent.isNotEmpty
                  ? RemoteConfigService.instance.userAgent
                  : kUniversalMobileUserAgent,
            },
          );
        }
      }

      // 3. Instagram Fotoğraf (og:image) Desteği
      final ogImage = RegExp(r'<meta\s+property="og:image"\s+content="([^"]+)"')
          .firstMatch(html);
      if (ogImage != null) {
        final cleanUrl = evrenselTemizUrlShield(ogImage.group(1)!);
        return ResolvedMedia(
          url: Uri.parse(cleanUrl),
          fileName: 'instagram_${DateTime.now().millisecondsSinceEpoch}.jpg',
          downloadHeaders: {
            'Referer': 'https://www.instagram.com/',
            'User-Agent': kUniversalMobileUserAgent,
          },
        );
      }

      throw const MediaResolverException(
        'Instagram medya URL\'si korumalı veya oturum çerezi gerektiriyor.',
      );
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('Instagram çözme hatası: $e');
    }
  }

  /// F) FACEBOOK: CookieManager oturum çerezlerini (c_user, xs) isteğe
  /// ekleyerek HD veya SD video kaynaklarını ayıklar.
  Future<ResolvedMedia> extractFacebook(Uri source) async {
    try {
      final res = await _dio.get<String>(source.toString());
      final html = res.data ?? '';

      final fbPatterns = <RegExp>[];
      final remoteFb = RemoteConfigService.instance.facebookRegex;
      if (remoteFb.isNotEmpty) {
        for (final p in remoteFb.split('|')) {
          if (p.trim().isNotEmpty) {
            try {
              fbPatterns.add(RegExp(p.trim()));
            } catch (_) {}
          }
        }
      }
      fbPatterns.addAll([
        RegExp(r'"download_url":"(.*?)"'),
        RegExp(r'"playable_url_quality_hd":\s*"([^"]+)"'),
        RegExp(r'"hd_src":\s*"([^"]+)"'),
        RegExp(r'"playable_url":\s*"([^"]+)"'),
        RegExp(r'"sd_src":\s*"([^"]+)"'),
        RegExp(r'<meta\s+property="og:video"\s+content="([^"]+)"'),
        RegExp(r'<meta\s+property="og:video:url"\s+content="([^"]+)"'),
      ]);

      for (final pattern in fbPatterns) {
        final match = pattern.firstMatch(html);
        if (match != null) {
          final rawUrl = (match.groupCount >= 1 ? match.group(1) : null) ?? match.group(0)!;
          final cleanUrl = evrenselTemizUrlShield(rawUrl);
          return ResolvedMedia(
            url: Uri.parse(cleanUrl),
            fileName: 'facebook_${DateTime.now().millisecondsSinceEpoch}.mp4',
            downloadHeaders: {
              'Referer': 'https://www.facebook.com/',
              'User-Agent': RemoteConfigService.instance.userAgent.isNotEmpty
                  ? RemoteConfigService.instance.userAgent
                  : kUniversalDesktopUserAgent,
            },
          );
        }
      }

      throw const MediaResolverException(
        'Facebook videosunun doğrudan adresi HTML kaynağında bulunamadı.',
      );
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('Facebook kazıma hatası: $e');
    }
  }

  /// G) VIMEO: Vimeo config ve sayfa kaynağındaki progressive MP4 akışını çözer.
  /// Tür güvenliği: Gelen response.data Map cast edilmez, ham String olarak karşılanır
  /// ve Regex cımbızıyla en yüksek kaliteli progressive MP4 linki doğrudan ayıklanır.
  Future<ResolvedMedia> extractVimeo(Uri source) async {
    try {
      final vimeoMatch = RegExp(r'vimeo\.com/(?:video/)?(\d+)')
          .firstMatch(source.toString());
      final videoId = vimeoMatch?.group(1);

      // 1. Aday URL: Config JSON/HTML uç noktası
      // 2. Aday URL: Doğrudan video sayfası HTML kaynağı
      final targetUrls = <String>[
        if (videoId != null) 'https://player.vimeo.com/video/$videoId/config',
        if (videoId != null) 'https://player.vimeo.com/video/$videoId',
        source.toString(),
      ];

      for (final targetUrl in targetUrls) {
        try {
          final res = await _dio.get<dynamic>(
            targetUrl,
            options: Options(
              responseType: ResponseType.plain,
              headers: {
                'Referer': 'https://vimeo.com/',
                'User-Agent': kUniversalDesktopUserAgent,
              },
              validateStatus: (status) => status != null && status < 500,
            ),
          );

          // 1. Kesin Tür Kalkanı: response.data verisini doğrudan Map'e cast etme!
          final String hamMetin = res.data?.toString() ?? '';
          if (hamMetin.trim().isEmpty) continue;

          // 2. Regex Cımbızı: jsonDecode'a ihtiyaç duymadan progressive MP4 linklerini topla
          final progressiveLinks = <String>[];

          // Kullanıcının birincil Regex yapısı:
          final RegExp vimeoRegex =
              RegExp(r'"progressive":\[.*?file_code.*?"url":"(.*?)"');
          for (final match in vimeoRegex.allMatches(hamMetin)) {
            final raw = match.group(1);
            if (raw != null && raw.isNotEmpty) {
              progressiveLinks.add(raw);
            }
          }

          // Alternatif evrensel Vimeo mp4 yakalayıcı:
          final RegExp altRegex = RegExp(
            r'"url":"(https://player\.vimeo\.com/progressive_redirect/.*?)"',
          );
          for (final match in altRegex.allMatches(hamMetin)) {
            final raw = match.group(1);
            if (raw != null && raw.isNotEmpty) {
              progressiveLinks.add(raw);
            }
          }

          // Ek genel Vimeo CDN / Akamai / progressive MP4 yakalayıcılar
          final genericVimeoPatterns = [
            RegExp(r'"url":\s*"(https://[^"]*(?:vimeocdn|akamaized|fastly)[^"]*\.mp4[^"]*)"'),
            RegExp(r'"url":\s*"(https?://[^"]+\.mp4[^"]*)"'),
            RegExp(r'''['"]url['"]\s*:\s*['"](https?://[^'"]+\.mp4[^'"]*)['"]'''),
            RegExp(r'''url:\s*(https?://[^\s,}\]]+\.mp4[^\s,}\]]*)'''),
            RegExp(r'"download_url":"(https?://[^"]+\.mp4[^"]*)"'),
          ];

          for (final pattern in genericVimeoPatterns) {
            for (final match in pattern.allMatches(hamMetin)) {
              final raw = match.group(1);
              if (raw != null && raw.isNotEmpty) {
                progressiveLinks.add(raw);
              }
            }
          }

          // 3. Kaliteye göre sırala ve en yüksek kalitedeki ham .mp4 adresini bul
          if (progressiveLinks.isNotEmpty) {
            final validUrls = progressiveLinks
                .map(evrenselTemizUrlShield)
                .where((u) => u.startsWith('http') && u.contains('.mp4'))
                .toList();

            if (validUrls.isNotEmpty) {
              int qualityScore(String url) {
                final lower = url.toLowerCase();
                if (lower.contains('1080p') || lower.contains('1080')) return 1080;
                if (lower.contains('720p') || lower.contains('720')) return 720;
                if (lower.contains('540p') || lower.contains('540')) return 540;
                if (lower.contains('480p') || lower.contains('480')) return 480;
                if (lower.contains('360p') || lower.contains('360')) return 360;
                if (lower.contains('240p') || lower.contains('240')) return 240;
                return 100;
              }

              validUrls.sort((a, b) => qualityScore(b).compareTo(qualityScore(a)));
              final bestUrl = validUrls.first;

              final fileSuffix = videoId ?? DateTime.now().millisecondsSinceEpoch.toString();
              return ResolvedMedia(
                url: Uri.parse(bestUrl),
                fileName: 'vimeo_${fileSuffix}_${DateTime.now().millisecondsSinceEpoch}.mp4',
                downloadHeaders: {
                  'Referer': 'https://vimeo.com/',
                  'User-Agent': kUniversalDesktopUserAgent,
                },
              );
            }
          }

          // 4. HLS (.m3u8) Akışı Adayı: Progressive MP4 yoksa parçalı HLS yayınını MP4 olarak akıt
          final hlsPatterns = [
            RegExp(r'"url":\s*"(https://[^"]*(?:skyfire|vimeocdn|akfire|fastly)[^"]*\.m3u8[^"]*)"'),
            RegExp(r'"default_cdn":\s*"[^"]*",.*?"url":\s*"(https://[^"]+\.m3u8[^"]*)"'),
            RegExp(r'"avc_url":\s*"(https://[^"]+\.m3u8[^"]*)"'),
          ];
          for (final pattern in hlsPatterns) {
            final hlsMatch = pattern.firstMatch(hamMetin);
            if (hlsMatch != null) {
              final rawHls = hlsMatch.group(1);
              if (rawHls != null && rawHls.isNotEmpty) {
                final cleanHlsUrl = evrenselTemizUrlShield(rawHls);
                final fileSuffix = videoId ?? DateTime.now().millisecondsSinceEpoch.toString();
                return ResolvedMedia(
                  url: Uri.parse(cleanHlsUrl),
                  fileName: 'vimeo_${fileSuffix}_${DateTime.now().millisecondsSinceEpoch}.mp4',
                  downloadHeaders: {
                    'Referer': 'https://vimeo.com/',
                    'User-Agent': kUniversalDesktopUserAgent,
                  },
                  byteStreamProvider: () => _streamDailymotionHls(cleanHlsUrl),
                );
              }
            }
          }
        } catch (targetErr) {
          debugPrint('UniversalScraper: Vimeo target $targetUrl taranırken hata: $targetErr');
        }
      }

      throw const MediaResolverException('Vimeo video akışı bulunamadı.');
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('Vimeo kazıma hatası: $e');
    }
  }

  /// H) DAILYMOTION: Metadata JSON veya sayfa kaynağındaki mp4 akışını çözer.
  Future<ResolvedMedia> extractDailymotion(Uri source) async {
    try {
      final dmMatch = RegExp(
        r'(?:dailymotion\.com/video/|dai\.ly/)([a-zA-Z0-9]+)',
      ).firstMatch(source.toString());
      if (dmMatch != null) {
        final videoId = dmMatch.group(1)!;
        final metaRes = await _dio.get<Map<String, dynamic>>(
          'https://www.dailymotion.com/player/metadata/video/$videoId',
        );
        final qualities = metaRes.data?['qualities'];
        if (qualities is Map) {
          final autoStreams = qualities['auto'] as List<dynamic>?;
          if (autoStreams != null && autoStreams.isNotEmpty) {
            final streamUrl = autoStreams.first['url']?.toString();
            if (streamUrl != null && streamUrl.isNotEmpty) {
              final cleanUrl = evrenselTemizUrlShield(streamUrl);
              return ResolvedMedia(
                url: Uri.parse(cleanUrl),
                fileName: 'dailymotion_$videoId.mp4',
                downloadHeaders: {
                  'Referer': 'https://www.dailymotion.com/',
                  'User-Agent': kUniversalDesktopUserAgent,
                },
                byteStreamProvider: () => _streamDailymotionHls(cleanUrl),
              );
            }
          }
        }
      }

      final res = await _dio.get<String>(source.toString());
      final html = res.data ?? '';
      final match =
          RegExp(r'<meta\s+property="og:video"\s+content="([^"]+)"')
              .firstMatch(html) ??
          RegExp(r'"download_url":"(.*?)"').firstMatch(html);
      if (match != null) {
        final cleanUrl = evrenselTemizUrlShield(match.group(1)!);
        return ResolvedMedia(
          url: Uri.parse(cleanUrl),
          fileName: 'dailymotion_${DateTime.now().millisecondsSinceEpoch}.mp4',
          downloadHeaders: {
            'Referer': 'https://www.dailymotion.com/',
            'User-Agent': kUniversalDesktopUserAgent,
          },
        );
      }

      throw const MediaResolverException('Dailymotion videosu çözülemedi.');
    } catch (e) {
      if (e is MediaResolverException) rethrow;
      throw MediaResolverException('Dailymotion kazıma hatası: $e');
    }
  }

  /// Dailymotion HLS (.m3u8) yayınını parça parça çekip birleşik mp4 bayt akışı olarak sunar.
  Stream<List<int>> _streamDailymotionHls(String masterM3u8Url) async* {
    final masterUri = Uri.parse(masterM3u8Url);
    final headers = {
      'User-Agent': kUniversalDesktopUserAgent,
      'Referer': 'https://www.dailymotion.com/',
      'Origin': 'https://www.dailymotion.com',
    };

    final masterRes = await _dio.get<String>(
      masterM3u8Url,
      options: Options(headers: headers),
    );
    final masterLines = (masterRes.data ?? '').split('\n');

    // 1. En yüksek kaliteli alt playlist'i seç
    String? chosenPlaylistUrl;
    for (final line in masterLines) {
      final t = line.trim();
      if (t.startsWith('http')) {
        chosenPlaylistUrl = t;
        if (t.contains('1080') || t.contains('720')) {
          break;
        }
      } else if (t.isNotEmpty && !t.startsWith('#')) {
        chosenPlaylistUrl = masterUri.resolve(t).toString();
        if (t.contains('1080') || t.contains('720')) {
          break;
        }
      }
    }

    if (chosenPlaylistUrl == null) {
      throw const MediaResolverException('Dailymotion video oynatma listesi bulunamadı.');
    }

    final subUri = Uri.parse(chosenPlaylistUrl);
    final subRes = await _dio.get<String>(
      chosenPlaylistUrl,
      options: Options(headers: headers),
    );
    final subLines = (subRes.data ?? '').split('\n');

    String? initUriStr;
    final segmentUris = <String>[];

    for (final line in subLines) {
      final t = line.trim();
      if (t.startsWith('#EXT-X-MAP:URI="')) {
        final end = t.indexOf('"', 16);
        if (end > 16) {
          initUriStr = t.substring(16, end);
        }
      } else if (t.isNotEmpty && !t.startsWith('#')) {
        segmentUris.add(t);
      }
    }

    // 2. Fragmented MP4 (fMP4) Init Segment'ini akışa gönder
    if (initUriStr != null) {
      final initFull = subUri.resolve(initUriStr).toString();
      final initRes = await _dio.get<List<int>>(
        initFull,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
        ),
      );
      if (initRes.data != null && initRes.data!.isNotEmpty) {
        yield initRes.data!;
      }
    }

    // 3. Sırasıyla tüm video segmentlerini çek ve kesintisiz akıt
    for (final seg in segmentUris) {
      final segFull = subUri.resolve(seg).toString();
      final segRes = await _dio.get<List<int>>(
        segFull,
        options: Options(
          responseType: ResponseType.bytes,
          headers: headers,
        ),
      );
      if (segRes.data != null && segRes.data!.isNotEmpty) {
        yield segRes.data!;
      }
    }
  }

  /// I) JENERİK VE DOĞRUDAN BAĞLANTI ÇÖZÜMLEMESİ
  Future<ResolvedMedia> extractGeneric(Uri source, DownloadKind kind) async {
    final cleanUrl = evrenselTemizUrlShield(source.toString());
    final effectiveSource = Uri.tryParse(cleanUrl) ?? source;
    final ext = kind == DownloadKind.audio ? '.mp3' : '.mp4';
    return ResolvedMedia(
      url: effectiveSource,
      fileName: 'vidsave_${DateTime.now().millisecondsSinceEpoch}$ext',
      downloadHeaders: {
        'User-Agent': kUniversalMobileUserAgent,
        'Accept': '*/*',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
        'Connection': 'keep-alive',
      },
    );
  }

  /// J) YEDEK ÇÖZÜMLEYİCİ (Regex Fallback Emniyet Supabı):
  /// Ana çözümleyici motorlardan herhangi biri başarısız olduğunda veya istisna fırlattığında
  /// otomatik devreye girer. Gelen ham veriyi String olarak tarayıp içindeki .mp4 veya .mp3
  /// uzantılı bağlantıları doğrudan cımbızlayarak kurtarır.
  Future<ResolvedMedia> extractWithRegexFallback(
    Uri source,
    DownloadKind kind, {
    String? rawData,
  }) async {
    String html = rawData ?? '';
    if (html.isEmpty) {
      try {
        final res = await _dio.get<String>(
          source.toString(),
          options: Options(
            validateStatus: (status) => status != null && status < 500,
          ),
        );
        html = res.data ?? '';
      } catch (e) {
        debugPrint('UniversalScraper Regex Fallback get error: $e');
      }
    }

    if (html.isNotEmpty) {
      final isAudio = kind == DownloadKind.audio;
      final targetExt = isAudio ? 'mp3' : 'mp4';

      final patterns = isAudio
          ? [
              RegExp(r'''(?:https?://|//)[^\s"'<>\\]+?\.(?:mp3|m4a|aac|wav|ogg)(?:[^\s"'<>\\]*)?''', caseSensitive: false),
              RegExp(r'''https?:\\/\\/[^\s"'<>\\]+?\.(?:mp3|m4a|aac|wav|ogg)(?:[^\s"'<>\\]*)?''', caseSensitive: false),
              RegExp(r'"download_url":"(.*?)"'),
              RegExp(r'"audio_url":"(.*?)"'),
              RegExp(r'<audio[^>]+src="([^"]+)"', caseSensitive: false),
            ]
          : [
              RegExp(r'''(?:https?://|//)[^\s"'<>\\]+?\.(?:mp4|m4a|webm)(?:[^\s"'<>\\]*)?''', caseSensitive: false),
              RegExp(r'''https?:\\/\\/[^\s"'<>\\]+?\.(?:mp4|m4a|webm)(?:[^\s"'<>\\]*)?''', caseSensitive: false),
              RegExp(r'"download_url":"(.*?)"'),
              RegExp(r'"playAddr":\s*"([^"]+)"'),
              RegExp(r'"playable_url_quality_hd":\s*"([^"]+)"'),
              RegExp(r'"playable_url":\s*"([^"]+)"'),
              RegExp(r'"video_url":\s*"([^"]+)"'),
              RegExp(r'<video[^>]+src="([^"]+)"', caseSensitive: false),
              RegExp(r'<source[^>]+src="([^"]+)"', caseSensitive: false),
              RegExp(r'<meta[^>]+(?:og:video|twitter:player:stream)[^>]+content="([^"]+)"', caseSensitive: false),
            ];

      for (final pattern in patterns) {
        final matches = pattern.allMatches(html);
        for (final match in matches) {
          final rawMatch = (match.groupCount >= 1 ? match.group(1) : null) ?? match.group(0);
          if (rawMatch != null && rawMatch.trim().isNotEmpty) {
            final clean = evrenselTemizUrlShield(rawMatch);
            final cleanLower = clean.toLowerCase();
            final hasMatchingExt = isAudio
                ? (cleanLower.contains('.mp3') || cleanLower.contains('.m4a'))
                : (cleanLower.contains('.mp4') || cleanLower.contains('.webm') || cleanLower.contains('video'));
            if (clean.startsWith('http') && hasMatchingExt) {
              debugPrint('UniversalScraper: Regex Fallback emniyet supabı başarıyla link yakaladı -> $clean');
              return ResolvedMedia(
                url: Uri.parse(clean),
                fileName: 'fallback_${DateTime.now().millisecondsSinceEpoch}.$targetExt',
                downloadHeaders: {
                  'User-Agent': kUniversalDesktopUserAgent,
                  'Referer': '${source.scheme}://${source.host}/',
                  'Origin': '${source.scheme}://${source.host}',
                },
              );
            }
          }
        }
      }
    }

    throw const MediaResolverException(
      'Medya adresi otomatik yedek taramada da bulunamadı. Lütfen bağlantıyı kontrol edin.',
    );
  }

  /// K) PYTHON BACKEND YEDEK GÜVENCESİ (Fallback URL):
  /// Cihaz içi tüm regex ve kazıma algoritmaları başarısız olursa, Remote Config'den
  /// gelen `backup_api_url` adresine istek göndererek medyayı garantili çözer.
  Future<ResolvedMedia> extractWithBackendFallback(
    Uri source,
    DownloadKind kind, {
    required String backupApiUrl,
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    final baseUri = Uri.parse(evrenselTemizUrlShield(backupApiUrl));
    final body = <String, dynamic>{
      'url': source.toString(),
      'kind': kind == DownloadKind.audio ? 'audio' : 'video',
      if (height != null && height > 0) 'height': height,
      if (startTime != null && startTime > 0) 'start_time': startTime,
      if (endTime != null && endTime > 0) 'end_time': endTime,
      if (audioEffect != null && audioEffect.isNotEmpty) 'audio_effect': audioEffect,
    };

    final res = await _dio.post<Map<String, dynamic>>(
      baseUri.resolve('/api/resolve').toString(),
      data: body,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'User-Agent': kUniversalDesktopUserAgent,
        },
      ),
    );

    final data = res.data;
    if (data == null) {
      throw const MediaResolverException('Yedek backend boş yanıt döndürdü.');
    }

    final status = (data['status'] as String? ?? '').toLowerCase();
    if (status == 'ready' || status == 'ok') {
      final downloadUrl = data['url']?.toString();
      if (downloadUrl != null && downloadUrl.isNotEmpty) {
        final parsedUrl = Uri.tryParse(downloadUrl);
        final effectiveUrl = (parsedUrl != null && parsedUrl.hasScheme)
            ? parsedUrl
            : baseUri.resolve(downloadUrl);
        final title = data['title']?.toString() ?? 'media';
        final ext = kind == DownloadKind.audio ? '.mp3' : '.mp4';
        return ResolvedMedia(
          url: effectiveUrl,
          fileName: '${_sanitizeFileName(title)}$ext',
          downloadHeaders: {
            'User-Agent': kUniversalDesktopUserAgent,
          },
        );
      }
    }

    throw MediaResolverException(
      data['error']?.toString() ?? 'Yedek backend medyayı çözemedi.',
    );
  }

  /// 3 AŞAMALI GÜVENLİK KALKANI: MEDYA DOĞRULAMA FONKSİYONU
  ///
  /// İndirme başlamadan önce linke hafif bir dio.head() isteği atarak Content-Type
  /// ve Content-Length başlıklarını okur.
  /// • Eğer tür text/html, application/json veya text/plain ise,
  /// • Veya boyut 1 MB'tan (1024 * 1024 bayt) küçükse,
  /// Remote Config servisine gizli hata sinyali raporlar ve `false` döndürür.
  Future<bool> _verifyResolvedMediaSecurity(ResolvedMedia media, Uri originalSource) async {
    // ByteStreamProvider (Örn. YoutubeExplode doğrudan pipe akışı) varsa HTTP HEAD gerekmez
    if (media.byteStreamProvider != null) {
      return true;
    }

    try {
      final response = await _dio.head<dynamic>(
        media.url.toString(),
        options: Options(
          headers: media.downloadHeaders,
          followRedirects: true,
          validateStatus: (status) => status != null && status < 500,
        ),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200 || response.statusCode == 206) {
        final contentType =
            (response.headers.value('content-type') ?? '').toLowerCase().trim();
        final lengthStr = response.headers.value('content-length');
        final length = lengthStr != null ? int.tryParse(lengthStr) : null;

        final isBanned = contentType.contains('text/html') ||
            contentType.contains('application/json') ||
            contentType.contains('text/plain');

        final isMedia = contentType.startsWith('video/') ||
            contentType.startsWith('audio/') ||
            contentType.startsWith('image/') ||
            contentType.contains('application/octet-stream') ||
            contentType.contains('application/x-mpegurl') ||
            contentType.contains('application/vnd.apple.mpegurl');

        if (contentType.isNotEmpty && (isBanned || !isMedia)) {
          unawaited(
            RemoteConfigService.instance.reportBotBlockSignal(
              failedUrl: media.url,
              reason: 'Scraper HEAD returned banned or non-media contentType: $contentType',
              contentType: contentType,
              contentLength: length,
            ),
          );
          return false;
        }

        if (length != null && length > 0 && length < kMinValidMediaBytes) {
          unawaited(
            RemoteConfigService.instance.reportBotBlockSignal(
              failedUrl: media.url,
              reason: 'Scraper HEAD returned size < 1MB: $length bytes',
              contentType: contentType,
              contentLength: length,
            ),
          );
          return false;
        }
      }

      return true;
    } catch (e) {
      // HEAD isteği başarısız olduysa (örn. 405 Method Not Allowed) akışı kesme,
      // asıl Dio.download katmanındaki güvenlik sigortası korumayı tamamlar.
      debugPrint('UniversalScraper _verifyResolvedMediaSecurity uyarısı: $e');
      return true;
    }
  }

  // ---------------------------------------------------------------------------
  // EVRENSEL DİREKSİYON (Universal Dispatcher)
  // ---------------------------------------------------------------------------

  /// Verilen ham bağlantıyı evrensel kalkanla temizleyip doğru platform kazıyıcısına yönlendirir.
  Future<ResolvedMedia> resolve(
    Uri source,
    DownloadKind kind, {
    int? height,
    double? startTime,
    double? endTime,
    String? audioEffect,
  }) async {
    final cleanSourceStr = evrenselTemizUrlShield(source.toString());
    final effectiveSource = Uri.tryParse(cleanSourceStr) ?? source;
    final host = effectiveSource.host.toLowerCase();

    ResolvedMedia? result;
    Object? primaryError;

    // 1. Birincil Platform Çözümleyici Katı Try-Catch Sarmalı
    try {
      if (host.contains('youtube.com') || host.contains('youtu.be')) {
        result = await extractYouTube(
          effectiveSource,
          kind,
          height: height,
          startTime: startTime,
          endTime: endTime,
          audioEffect: audioEffect,
        );
      } else if (host.contains('tiktok.com') || host.contains('douyin.com')) {
        result = await extractTikTok(effectiveSource);
      } else if (host.contains('instagram.com') || host.contains('instagr.am')) {
        result = await extractInstagram(effectiveSource);
      } else if (host.contains('facebook.com') ||
          host.contains('fb.watch') ||
          host.contains('fb.com')) {
        result = await extractFacebook(effectiveSource);
      } else if (host.contains('pinterest.com') || host.contains('pin.it')) {
        result = await extractPinterest(effectiveSource);
      } else if (host.contains('twitter.com') ||
          host.contains('x.com') ||
          host.contains('t.co')) {
        result = await extractTwitter(effectiveSource);
      } else if (host.contains('vimeo.com')) {
        result = await extractVimeo(effectiveSource);
      } else if (host.contains('dailymotion.com') || host.contains('dai.ly')) {
        result = await extractDailymotion(effectiveSource);
      } else {
        result = await extractGeneric(effectiveSource, kind);
      }

      // Güvenlik Kalkanı 1. ve 2. Aşama Denetimi:
      // Eğer birincil motor bir HTTP linki döndürdüyse (ve bilinen platform kazıyıcılarından geldiyse),
      // sahte HTML/JSON veya <1MB bot engeli mi kontrol et
      final isGeneric = !host.contains('youtube.com') &&
          !host.contains('youtu.be') &&
          !host.contains('tiktok.com') &&
          !host.contains('douyin.com') &&
          !host.contains('instagram.com') &&
          !host.contains('facebook.com') &&
          !host.contains('fb.watch') &&
          !host.contains('fb.com') &&
          !host.contains('pinterest.com') &&
          !host.contains('pin.it') &&
          !host.contains('twitter.com') &&
          !host.contains('x.com') &&
          !host.contains('vimeo.com') &&
          !host.contains('dailymotion.com');

      if (!isGeneric && result.byteStreamProvider == null && result.url.hasScheme) {
        final isSecure = await _verifyResolvedMediaSecurity(result, effectiveSource);
        if (!isSecure) {
          debugPrint('UniversalScraper: Birincil motor sahte HTML / bot kalkanına takıldı! Otomatik tamir ve yedek hatta yönlendiriliyor...');
          result = null;
        }
      }
    } catch (e, stack) {
      debugPrint('UniversalScraper: Ana çözümleyici hata verdi ($e), Yedek Regex Çözümleyiciye geçiliyor...\n$stack');
      primaryError = e;
    }

    // 2. Yedek Çözümleyici (Regex Fallback Emniyet Supabı)
    // Eğer ana çözümleyici motoru hata verirse, otomatik devreye girer
    if (result == null) {
      try {
        final regexResult = await extractWithRegexFallback(effectiveSource, kind);
        final isSecure = await _verifyResolvedMediaSecurity(regexResult, effectiveSource);
        if (isSecure) {
          result = regexResult;
        } else {
          debugPrint('UniversalScraper: Regex fallback sonucu da sahte HTML veya <1MB bot tuzağı!');
        }
      } catch (fallbackError) {
        debugPrint('UniversalScraper: Yedek regex çözümleyici de başarısız oldu: $fallbackError');
      }
    }

    // 3. PYTHON BACKEND YEDEK GÜVENCESİ (FALLBACK URL - OTOMATİK TAMİR SİNYALİ)
    // Eğer buluttan gelen tüm yerel regex kalıpları başarısız olursa veya sahte HTML tespit edilirse,
    // Remote Config üzerinden yönetilen backup_api_url parametresine isteği yönlendirerek garantili çöz
    if (result == null) {
      final backupUrl = RemoteConfigService.instance.backupApiUrl.trim();
      if (backupUrl.isNotEmpty) {
        try {
          debugPrint('UniversalScraper: Python Backend Yedek Güvencesine (backup_api_url) yönlendiriliyor: $backupUrl');
          result = await extractWithBackendFallback(
            effectiveSource,
            kind,
            backupApiUrl: backupUrl,
            height: height,
            startTime: startTime,
            endTime: endTime,
            audioEffect: audioEffect,
          );
        } catch (backendError) {
          debugPrint('UniversalScraper: Python Backend Yedek API de başarısız oldu: $backendError');
        }
      }
    }

    // 4. Tüm motorlar başarısız olduysa kontrollü ve güvenli hata fırlat
    if (result == null) {
      throw DownloadExceptionHandler.mapToResolverException(primaryError, effectiveSource);
    }

    // Nihai temizlik kalkanını çıktı URL'sine de uygula
    final cleanMediaUrl =
        Uri.tryParse(evrenselTemizUrlShield(result.url.toString())) ??
        result.url;
    final cleanAudioUrl = result.audioUrl != null
        ? (Uri.tryParse(evrenselTemizUrlShield(result.audioUrl.toString())) ??
              result.audioUrl)
        : null;

    return ResolvedMedia(
      url: cleanMediaUrl,
      fileName: result.fileName,
      mimeType: result.mimeType,
      fileSizeInBytes: result.fileSizeInBytes,
      downloadHeaders: result.downloadHeaders,
      audioUrl: cleanAudioUrl,
      audioFileSizeInBytes: result.audioFileSizeInBytes,
      startTime: result.startTime,
      endTime: result.endTime,
      audioEffect: result.audioEffect,
      byteStreamProvider: result.byteStreamProvider,
      audioByteStreamProvider: result.audioByteStreamProvider,
    );
  }

  /// Medya indirilmeden önce başlık ve seçilebilir çözünürlükleri döndürür.
  Future<MediaPreview> preview(Uri source, DownloadKind kind) async {
    final cleanSourceStr = evrenselTemizUrlShield(source.toString());
    final effectiveSource = Uri.tryParse(cleanSourceStr) ?? source;
    final host = effectiveSource.host.toLowerCase();

    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      final videoId = _extractYouTubeVideoId(effectiveSource);
      if (videoId == null) {
        throw const MediaResolverException('Geçersiz YouTube bağlantısı.');
      }
      final video = await _yt.videos.get(videoId);
      final manifest = await _yt.videos.streamsClient.getManifest(videoId);

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
                label:
                    '${numericHeight}p HD (${stream.container.name.toUpperCase()})',
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
    }

    // Diğer platformlar için jenerik önizleme
    final defaultQualities = kind == DownloadKind.audio
        ? const [
            VideoQuality(
              height: 0,
              label: 'MP3 Ses Dosyası (320 kbps - En Yüksek Kalite)',
            ),
            VideoQuality(height: 192, label: 'MP3 Standart Kalite (192 kbps)'),
            VideoQuality(height: 128, label: 'MP3 Hızlı İndir (128 kbps)'),
          ]
        : const [
            VideoQuality(height: 0, label: 'Orijinal HD Medya (Önerilen)'),
            VideoQuality(height: 1080, label: '1080p Full HD'),
            VideoQuality(height: 720, label: '720p HD'),
          ];

    return MediaPreview(
      title: _extractGenericTitle(effectiveSource.toString()),
      qualities: defaultQualities,
    );
  }

  /// YouTube üzerinden müzik ve video arama (İstemci Taraflı)
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
    } catch (_) {
      return const [];
    }
  }

  // ---------------------------------------------------------------------------
  // YARDIMCI METOTLAR
  // ---------------------------------------------------------------------------

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

  String _sanitizeFileName(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n\t]+'), '_')
        .trim();
    return sanitized.isEmpty ? 'vidsave_media' : sanitized;
  }

  String _extractGenericTitle(String url) {
    try {
      final u = Uri.parse(evrenselTemizUrlShield(url));
      final last = u.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
      return last != null && last.isNotEmpty ? last : 'Medya İndirme';
    } catch (_) {
      return 'Medya İndirme';
    }
  }
}
