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
  print('Raw HLS: $rawHls');

  final masterUri = Uri.parse(rawHls);
  final subRes = await dio.get<String>(
    rawHls,
    options: Options(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Referer': 'https://player.vimeo.com/',
      },
    ),
  );

  final masterLines = (subRes.data ?? '').split('\n');
  String? chosenPlaylistUrl;
  for (final line in masterLines) {
    final t = line.trim();
    if (t.startsWith('http')) {
      chosenPlaylistUrl = t;
      if (t.contains('1080') || t.contains('720')) break;
    } else if (t.isNotEmpty && !t.startsWith('#')) {
      chosenPlaylistUrl = masterUri.resolve(t).toString();
      if (t.contains('1080') || t.contains('720')) break;
    }
  }

  print('Chosen: $chosenPlaylistUrl');

  final mediaRes = await dio.get<String>(
    chosenPlaylistUrl!,
    options: Options(
      headers: {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)',
        'Referer': 'https://player.vimeo.com/',
      },
    ),
  );

  final subLines = (mediaRes.data ?? '').split('\n');
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

  print('initUriStr: $initUriStr');
  print('Segments count: ${segmentUris.length}');
  print('First 3 segments: ${segmentUris.take(3).toList()}');
}
