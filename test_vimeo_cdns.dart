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
  // find all .m3u8 urls
  final hlsMatches = RegExp(
    r'"url":\s*"(https://[^"]*(?:skyfire|vimeocdn|akfire|fastly)[^"]*\.m3u8[^"]*)"',
  ).allMatches(html);
  print('Total HLS matches: ${hlsMatches.length}');
  for (final m in hlsMatches) {
    var u = m
        .group(1)!
        .replaceAll(r'\/', '/')
        .replaceAll(r'\u0026', '&')
        .replaceAll(r'\u003D', '=')
        .replaceAll(r'\u003d', '=');
    print('HLS URL: $u');
  }

  // check if there is an open non-drm cdn
  final cdnsMatch = RegExp(
    r'"cdns":\s*(\{.*?\})\s*,\s*"default_cdn"',
    dotAll: true,
  ).firstMatch(html);
  if (cdnsMatch != null) {
    print('CDNs block: ${cdnsMatch.group(1)}');
  }
}
