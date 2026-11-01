import 'dart:convert';

import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  const vimeoUrl = 'https://player.vimeo.com/video/76979871';

  final res = await dio.get<String>(
    vimeoUrl,
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://vimeo.com/',
      },
    ),
  );

  final html = res.data ?? '';
  final configMatch =
      RegExp(
        r'window\.playerConfig\s*=\s*(\{.*?\});\s*window',
        dotAll: true,
      ).firstMatch(html) ??
      RegExp(
        r'window\.playerConfig\s*=\s*(\{.*?\});',
        dotAll: true,
      ).firstMatch(html);

  if (configMatch != null) {
    print('Found window.playerConfig!');
    final jsonStr = configMatch.group(1)!;
    final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
    final request = jsonMap['request'] as Map<String, dynamic>?;
    final files = request?['files'] as Map<String, dynamic>?;
    print('Files keys: ${files?.keys.toList()}');

    final progressive = files?['progressive'] as List<dynamic>?;
    print('Progressive list: $progressive');

    final hls = files?['hls'] as Map<String, dynamic>?;
    print('HLS keys: ${hls?.keys.toList()}');
    print('HLS default_cdn: ${hls?['default_cdn']}');
    final cdns = hls?['cdns'] as Map<String, dynamic>?;
    print('HLS CDNs: ${cdns?.keys.toList()}');
    if (cdns != null) {
      for (final k in cdns.keys) {
        final cdnObj = cdns[k];
        print('  CDN $k -> ${cdnObj['url']}');
      }
    }
  }
}
