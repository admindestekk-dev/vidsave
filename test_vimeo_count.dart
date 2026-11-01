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
  final startIdx = html.indexOf('window.playerConfig = {');
  final jsonStart = startIdx + 'window.playerConfig = '.length;
  final endIdx = html.indexOf('</script>', jsonStart);
  var jsonStr = html
      .substring(jsonStart, endIdx != -1 ? endIdx : html.length)
      .trim();
  if (jsonStr.endsWith(';'))
    jsonStr = jsonStr.substring(0, jsonStr.length - 1).trim();

  final jsonMap = jsonDecode(jsonStr) as Map<String, dynamic>;
  final request = jsonMap['request'] as Map<String, dynamic>?;
  final files = request?['files'] as Map<String, dynamic>?;
  final cdns = files?['hls']?['cdns'] as Map<String, dynamic>?;
  final defaultCdn =
      files?['hls']?['default_cdn']?.toString() ?? cdns?.keys.first;
  final cdnObj = cdns?[defaultCdn] ?? cdns?.values.first;
  var hlsUrl = cdnObj['url']?.toString();

  var masterJsonUrl = hlsUrl!;
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
  }

  final mjRes = await dio.get<Map<String, dynamic>>(
    masterJsonUrl,
    options: Options(
      headers: {
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        'Referer': 'https://player.vimeo.com/',
      },
    ),
  );

  final mjData = mjRes.data!;
  print(
    'Total video segments: ${(mjData['video'][0]['segments'] as List).length}',
  );
  print(
    'Total audio segments: ${(mjData['audio'][0]['segments'] as List).length}',
  );
}
