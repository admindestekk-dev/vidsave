import 'package:dio/dio.dart';

/// In-memory cookie jar to store session cookies, bot-bypass tokens and Set-Cookie
/// headers from social media platforms (YouTube, TikTok, Instagram, Facebook).
class InMemoryCookieJar {
  final Map<String, Map<String, String>> _cookiesByDomain = {};

  /// Saves cookies extracted from 'set-cookie' response headers.
  void saveFromResponse(Uri uri, List<String>? setCookieHeaders) {
    if (setCookieHeaders == null || setCookieHeaders.isEmpty) return;

    final host = uri.host.toLowerCase();

    for (final rawHeader in setCookieHeaders) {
      if (rawHeader.trim().isEmpty) continue;
      final parts = rawHeader.split(';');
      if (parts.isNotEmpty) {
        final pair = parts.first.split('=');
        if (pair.length >= 2) {
          final name = pair.first.trim();
          final value = pair.sublist(1).join('=').trim();
          if (name.isNotEmpty) {
            String targetDomain = host;
            // Check if Set-Cookie specifies a Domain attribute
            for (final part in parts.skip(1)) {
              final attr = part.trim();
              if (attr.toLowerCase().startsWith('domain=')) {
                var d = attr.substring(7).trim().toLowerCase();
                if (d.startsWith('.')) d = d.substring(1);
                if (d.isNotEmpty) targetDomain = d;
              }
            }
            _cookiesByDomain.putIfAbsent(targetDomain, () => <String, String>{});
            _cookiesByDomain[targetDomain]![name] = value;
          }
        }
      }
    }
  }

  /// Builds a combined "name1=val1; name2=val2" Cookie header for a given target URI.
  String? getCookieHeader(Uri uri) {
    final host = uri.host.toLowerCase();
    final matchedCookies = <String, String>{};

    for (final entry in _cookiesByDomain.entries) {
      final domain = entry.key;

      // 1. Direct or subdomain match
      if (host == domain ||
          host.endsWith('.$domain') ||
          domain.endsWith('.$host')) {
        matchedCookies.addAll(entry.value);
        continue;
      }

      // 2. Platform-aware cross-CDN cookie sharing (YouTube, TikTok, Instagram, Facebook)
      if ((host.contains('googlevideo.com') || host.contains('youtube.com')) &&
          (domain.contains('googlevideo.com') || domain.contains('youtube.com'))) {
        matchedCookies.addAll(entry.value);
      } else if ((host.contains('tiktok.com') ||
              host.contains('tiktokcdn.com') ||
              host.contains('byteoversea.com')) &&
          (domain.contains('tiktok.com') ||
              domain.contains('tiktokcdn.com') ||
              domain.contains('byteoversea.com'))) {
        matchedCookies.addAll(entry.value);
      } else if ((host.contains('instagram.com') ||
              host.contains('cdninstagram.com') ||
              host.contains('fbcdn.net')) &&
          (domain.contains('instagram.com') ||
              domain.contains('cdninstagram.com') ||
              domain.contains('fbcdn.net'))) {
        matchedCookies.addAll(entry.value);
      } else if ((host.contains('facebook.com') || host.contains('fbcdn.net')) &&
          (domain.contains('facebook.com') || domain.contains('fbcdn.net'))) {
        matchedCookies.addAll(entry.value);
      }
    }

    if (matchedCookies.isEmpty) return null;
    return matchedCookies.entries
        .map((e) => '${e.key}=${e.value}')
        .join('; ');
  }

  /// Returns an immutable copy of all cached cookies for debugging or testing.
  Map<String, Map<String, String>> get cookies =>
      Map.unmodifiable(_cookiesByDomain);

  /// Clears all stored cookies.
  void clear() {
    _cookiesByDomain.clear();
  }
}

/// Dynamically injects platform-specific Referer/Origin headers and maintains
/// cookie sessions to completely eliminate 403 Forbidden / bot detection.
class CookieAndMaskingInterceptor extends Interceptor {
  CookieAndMaskingInterceptor(this.cookieJar);

  final InMemoryCookieJar cookieJar;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final uri = options.uri;
    final host = uri.host.toLowerCase();

    // 1. Dynamic platform impersonation for Referer and Origin
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
    } else if (host.contains('facebook.com') || host.contains('fb.watch')) {
      options.headers['Referer'] = 'https://www.facebook.com/';
      options.headers['Origin'] = 'https://www.facebook.com';
    } else if (host.contains('pinterest.com') || host.contains('pinimg.com')) {
      options.headers['Referer'] = 'https://www.pinterest.com/';
      options.headers['Origin'] = 'https://www.pinterest.com';
    } else if (!options.headers.containsKey('Referer')) {
      options.headers['Referer'] = '${uri.scheme}://${uri.host}';
      options.headers['Origin'] = '${uri.scheme}://${uri.host}';
    }

    // 2. Cookie injection from cookie jar
    final cookieHeader = cookieJar.getCookieHeader(uri);
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      options.headers['Cookie'] = cookieHeader;
    }

    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    _captureCookies(response);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response != null) {
      _captureCookies(err.response!);
    }
    handler.next(err);
  }

  void _captureCookies(Response response) {
    final setCookies = response.headers['set-cookie'];
    if (setCookies != null && setCookies.isNotEmpty) {
      cookieJar.saveFromResponse(response.requestOptions.uri, setCookies);
    }
  }
}

/// Global Dio client configuration matching the user's browser spoofing requirements.
class AppDio {
  AppDio._();

  static final InMemoryCookieJar cookieJar = InMemoryCookieJar();

  static Dio? _instance;

  /// Global singleton Dio instance configured with cookie persistence and legal browser headers.
  static Dio get instance {
    _instance ??= createClient();
    return _instance!;
  }

  /// Factory method to create a new, fully configured Dio instance.
  static Dio createClient({InMemoryCookieJar? jar}) {
    final activeJar = jar ?? cookieJar;

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(minutes: 30),
        followRedirects: true,
        maxRedirects: 10,
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
          'Accept': 'video/webm,video/mp4,video/*,audio/*,*/*',
          'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
          'Referer': 'https://youtube.com', // Platform taklidi için dinamik değişebilir
          'Origin': 'https://youtube.com',
          'Sec-Fetch-Mode': 'cors',
          'Sec-Fetch-Site': 'cross-site',
        },
      ),
    );

    dio.interceptors.add(CookieAndMaskingInterceptor(activeJar));
    return dio;
  }

  /// Helper to get default legal browser headers map.
  static Map<String, String> get defaultHeaders => {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept': 'video/webm,video/mp4,video/*,audio/*,*/*',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
        'Referer': 'https://youtube.com',
        'Origin': 'https://youtube.com',
        'Sec-Fetch-Mode': 'cors',
        'Sec-Fetch-Site': 'cross-site',
      };
}
