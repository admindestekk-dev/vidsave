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
    final jsonStr = configMatch.group(1)!;
    final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
    final request = jsonMap['request'] as Map<String, dynamic>?;
    final files = request?['files'] as Map<String, dynamic>?;
    final cdns = files?['hls']?['cdns'] as Map<String, dynamic>?;
    if (cdns != null && cdns.isNotEmpty) {
      final defaultCdn =
          files?['hls']?['default_cdn']?.toString() ?? cdns.keys.first;
      final cdnObj = cdns[defaultCdn] ?? cdns.values.first;
      var hlsUrl = cdnObj['url']?.toString();
      print('HLS URL: $hlsUrl');

      if (hlsUrl != null) {
        // Change master.m3u8 or master.json?base64_init=1
        var masterJsonUrl = hlsUrl;
        if (masterJsonUrl.contains('/playlist.m3u8')) {
          masterJsonUrl = masterJsonUrl.replaceAll(
            '/playlist.m3u8',
            '/master.json?base64_init=1',
          );
        } else if (masterJsonUrl.contains('/master.m3u8')) {
          masterJsonUrl = masterJsonUrl.replaceAll(
            '/master.m3u8',
            '/master.json?base64_init=1',
          );
        } else if (masterJsonUrl.contains('.m3u8')) {
          masterJsonUrl = masterJsonUrl.replaceAll(
            RegExp(r'\.m3u8.*'),
            '/master.json?base64_init=1',
          );
        }
        print('Master JSON URL: $masterJsonUrl');

        try {
          final mjRes = await dio.get<Map<String, dynamic>>(
            masterJsonUrl,
            options: Options(
              headers: {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
                'Referer': 'https://player.vimeo.com/',
              },
            ),
          );
          print('MASTER JSON SUCCESS!');
          final mjData = mjRes.data!;
          print('Clip ID: ${mjData['clip_id']}');
          print('Base URL: ${mjData['base_url']}');
          final videoList = mjData['video'] as List<dynamic>?;
          print('Video streams count: ${videoList?.length}');
          for (final v in videoList ?? []) {
            print(
              '  Video: ${v['id']} -> ${v['width']}x${v['height']}, bitrate: ${v['bitrate']}, segments: ${(v['segments'] as List).length}',
            );
          }
          final audioList = mjData['audio'] as List<dynamic>?;
          print('Audio streams count: ${audioList?.length}');
          for (final a in audioList ?? []) {
            print(
              '  Audio: ${a['id']} -> bitrate: ${a['bitrate']}, segments: ${(a['segments'] as List).length}',
            );
          }
        } catch (e) {
          print('Master JSON failed: $e');
        }
      }
    }
  }
}
