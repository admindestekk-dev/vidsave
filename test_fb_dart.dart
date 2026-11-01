import 'package:dio/dio.dart';

void main() async {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
      followRedirects: true,
      maxRedirects: 8,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'tr-TR,tr;q=0.9,en-US;q=0.8,en;q=0.7',
        'Sec-Fetch-Mode': 'navigate',
        'Sec-Fetch-Site': 'none',
        'Sec-Fetch-Dest': 'document',
        'Upgrade-Insecure-Requests': '1',
      },
    ),
  );

  const testReels = [
    'https://www.facebook.com/reel/1065415035800269',
    'https://www.facebook.com/reel/851631117236128',
    'https://www.facebook.com/reel/1330368332523369',
  ];

  for (final url in testReels) {
    print('Testing: $url');
    try {
      final res = await dio.get<String>(url);
      final html = res.data ?? '';
      print('  Status: ${res.statusCode}, Len: ${html.length}');

      final patterns = [
        RegExp(r'"browser_native_hd_url":\s*"([^"]+)"'),
        RegExp(r'"browser_native_sd_url":\s*"([^"]+)"'),
        RegExp(r'"playable_url_quality_hd":\s*"([^"]+)"'),
        RegExp(r'"playable_url":\s*"([^"]+)"'),
        RegExp(r'"hd_src":\s*"([^"]+)"'),
        RegExp(r'"sd_src":\s*"([^"]+)"'),
      ];

      String? matchedUrl;
      for (final p in patterns) {
        final m = p.firstMatch(html);
        if (m != null) {
          final raw = m.group(1)!;
          final clean = raw.replaceAll(r'\/', '/').replaceAll(r'\u0026', '&');
          matchedUrl = clean;
          print(
            '  Found match with pattern: ${p.pattern.substring(0, 25)} -> ${clean.substring(0, 80)}...',
          );
          break;
        }
      }

      if (matchedUrl != null) {
        // Test downloading stream with Dio
        final streamRes = await dio.get<ResponseBody>(
          matchedUrl,
          options: Options(
            responseType: ResponseType.stream,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
              'Referer': 'https://www.facebook.com/',
            },
          ),
        );
        print(
          '  STREAM SUCCESS: ${streamRes.statusCode}, Content-Type: ${streamRes.headers.value('content-type')}, Content-Length: ${streamRes.headers.value('content-length')}',
        );
      } else {
        print('  NO VIDEO URL FOUND!');
      }
    } catch (e) {
      print('  Error: $e');
    }
  }
}
