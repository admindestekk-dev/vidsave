import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  final masterRes = await dio.get<String>(
    'https://player.vimeo.com/video/76979871',
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://vimeo.com/',
      },
    ),
  );

  final html = masterRes.data ?? '';
  final hlsMatch = RegExp(
    r'"url":\s*"(https://[^"]*(?:skyfire|vimeocdn|akfire|fastly)[^"]*\.m3u8[^"]*)"',
  ).firstMatch(html);
  var rawUrl = hlsMatch?.group(1);
  if (rawUrl != null) {
    // Unescape unicode and slashes
    rawUrl = rawUrl
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u003D', '=')
        .replaceAll(r'\u003d', '=');
    print('Cleaned M3U8 URL: $rawUrl');

    final subRes = await dio.get<String>(
      rawUrl,
      options: Options(
        headers: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
          'Referer': 'https://player.vimeo.com/',
        },
      ),
    );

    print('Sub M3U8 STATUS: ${subRes.statusCode}');
    print('Sub M3U8 content (first 300 chars):');
    print(subRes.data?.substring(0, 300));
  }
}
