import 'dart:convert';

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
  var rawHls = hlsMatch?.group(1);
  rawHls = rawHls!
      .replaceAll(r'\/', '/')
      .replaceAll(r'\u0026', '&')
      .replaceAll(r'\u003D', '=')
      .replaceAll(r'\u003d', '=');
  print('Raw Hls: $rawHls');

  // Let's run _streamDailymotionHls logic on this rawHls!
  final masterUri = Uri.parse(rawHls);
  final subRes = await dio.get<String>(
    rawHls,
    options: Options(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Referer': 'https://vimeo.com/',
      },
    ),
  );

  final lines = (subRes.data ?? '').split('\n');
  print('Lines count: ${lines.length}');
  String? chosenUrl;
  for (final l in lines) {
    final t = l.trim();
    if (t.startsWith('http')) {
      chosenUrl = t;
      break;
    } else if (t.isNotEmpty && !t.startsWith('#')) {
      chosenUrl = masterUri.resolve(t).toString();
      break;
    }
  }
  print('Chosen sub playlist: $chosenUrl');
}
